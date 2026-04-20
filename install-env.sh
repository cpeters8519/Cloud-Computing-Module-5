#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

# 1. System Setup
dnf update -y
dnf install -y nginx git unzip
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs
npm install -g pm2

# 2. Directory Setup
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# 3. Create Index
cat > index.html << 'EOF'
<!DOCTYPE html>
<html><body>
    <h1>Module 05 Upload</h1>
    <form method="post" enctype="multipart/form-data" action="/upload">
        Name: <input type="text" name="name"/><br>
        Email: <input type="text" name="email"/><br>
        Phone: <input type="text" name="phone"/><br>
        File: <input type="file" name="uploadFile"/><br>
        <input type="submit" value="Upload"/>
    </form>
</body></html>
EOF

# 4a. Create app.js
cat > app.js << 'EOF'
const express = require('express');
const app = express();
const multer = require("multer");
const multerS3 = require("multer-s3");
const { v4: uuidv4 } = require("uuid");
const mysql = require("mysql2/promise");
const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3');
const { SNSClient, ListTopicsCommand, SubscribeCommand, PublishCommand } = require("@aws-sdk/client-sns");
const { RDSClient, DescribeDBInstancesCommand } = require("@aws-sdk/client-rds");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");
const { SQSClient, SendMessageCommand, GetQueueUrlCommand } = require("@aws-sdk/client-sqs");

const REGION = "us-east-2";
const s3 = new S3Client({ region: REGION });
app.use(express.urlencoded({ extended: true }));

async function getSecret(id) {
    const client = new SecretsManagerClient({ region: REGION });
    const res = await client.send(new GetSecretValueCommand({ SecretId: id }));
    return res.SecretString;
}

const upload = multer({
    storage: multerS3({
        s3: s3,
        bucket: async (req, file, cb) => {
            const data = await s3.send(new ListBucketsCommand({}));
            const bucket = data.Buckets.find(b => b.Name.includes("module-05-raw")).Name;
            cb(null, bucket);
        },
        key: (req, file, cb) => cb(null, file.originalname)
    })
});

async function getDB() {
    const rds = new RDSClient({ region: REGION });
    const data = await rds.send(new DescribeDBInstancesCommand({}));
    const host = data.DBInstances[0].Endpoint.Address;
    const user = await getSecret("uname");
    const pass = await getSecret("pword");
    const conn = await mysql.createConnection({ host, user, password: pass });
    
    // THE BULLETPROOF ADDITION:
    await conn.query("CREATE DATABASE IF NOT EXISTS company");
    await conn.query("USE company");
    await conn.query(`CREATE TABLE IF NOT EXISTS submissions (
        ID INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        RecordNumber VARCHAR(64),
        CustomerName VARCHAR(64),
        Email VARCHAR(64),
        Phone VARCHAR(64),
        Stat INT(1) DEFAULT 0,
        RAWS3URL VARCHAR(200),
        FINSIHEDS3URL VARCHAR(200)
    )`);
    return conn;
}

app.post("/upload", upload.array("uploadFile", 1), async (req, res) => {
    try {
        const data = await s3.send(new ListBucketsCommand({}));
        // SPECIFICALLY look for module-05 to avoid old data
        const bucket = data.Buckets.find(b => b.Name.includes("module-05-raw")).Name;
        const s3URL = `https://${bucket}.s3.amazonaws.com/${req.files[0].originalname}`;

        const conn = await getDB();
        await conn.query("CREATE DATABASE IF NOT EXISTS company");
        await conn.query("USE company");
        
        await conn.query(`CREATE TABLE IF NOT EXISTS submissions (
            ID INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            RecordNumber VARCHAR(64),
            CustomerName VARCHAR(64),
            Email VARCHAR(64),
            Phone VARCHAR(64),
            Stat INT(1) DEFAULT 0,
            RAWS3URL VARCHAR(200),
            FINSIHEDS3URL VARCHAR(200)
        )`);

        await conn.execute(
            "INSERT INTO submissions (RecordNumber, CustomerName, Email, Phone, Stat, RAWS3URL) VALUES (?, ?, ?, ?, ?, ?)",
            [uuidv4(), req.body.name, req.body.email, req.body.phone, 0, s3URL]
        );

        const sqs = new SQSClient({ region: REGION });
        const qData = await sqs.send(new GetQueueUrlCommand({ QueueName: "cpete-module-05-sqs" }));
        await sqs.send(new SendMessageCommand({
            QueueUrl: qData.QueueUrl,
            MessageBody: JSON.stringify({ s3URL, filename: req.files[0].originalname })
        }));

        const sns = new SNSClient({ region: REGION });
        const topics = await sns.send(new ListTopicsCommand({}));
        const tArn = topics.Topics.find(t => t.TopicArn.includes("module-05")).TopicArn;
        await sns.send(new SubscribeCommand({ Protocol: "email", TopicArn: tArn, Endpoint: req.body.email }));
        await sns.send(new PublishCommand({ TopicArn: tArn, Subject: "Upload Ready", Message: `File: ${s3URL}` }));

        res.send("<h1>Success!</h1><p>Check your email.</p>");
        await conn.end();
    } catch (err) {
        res.status(500).send(err.message);
    }
});

app.get("/db", async (req, res) => {
    try {
        const conn = await getDB();
        await conn.query("USE company");
        const [rows] = await conn.query("SELECT * FROM submissions");
        // ADD THE FINSIHEDS3URL HEADER
        let html = "<table border='1'><tr><th>ID</th><th>Name</th><th>Email</th><th>Stat</th><th>RawURL</th><th>FinishedURL</th></tr>";
        rows.forEach(r => {
            // INCLUDE THE r.FINSIHEDS3URL DATA
            html += `<tr><td>${r.ID}</td><td>${r.CustomerName}</td><td>${r.Email}</td><td>${r.Stat}</td><td>${r.RAWS3URL}</td><td>${r.FINSIHEDS3URL}</td></tr>`;
        });
        res.send(html + "</table>");
        await conn.end();
    } catch (err) {
        res.status(500).send(err.message);
    }
});

app.get("/", (req, res) => res.sendFile(__dirname + "/index.html"));
app.listen(3000);
EOF

# 4b. Create backend.js
cat > backend.js << 'EOF'
const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand, GetQueueUrlCommand } = require("@aws-sdk/client-sqs");
const { S3Client, CopyObjectCommand, ListBucketsCommand } = require("@aws-sdk/client-s3");
const mysql = require("mysql2/promise");
const { RDSClient, DescribeDBInstancesCommand } = require("@aws-sdk/client-rds");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");

const REGION = "us-east-2";
const sqs = new SQSClient({ region: REGION });
const s3 = new S3Client({ region: REGION });

async function getSecret(id) {
    const client = new SecretsManagerClient({ region: REGION });
    const res = await client.send(new GetSecretValueCommand({ SecretId: id }));
    return res.SecretString;
}

async function getDB() {
    const rds = new RDSClient({ region: REGION });
    const data = await rds.send(new DescribeDBInstancesCommand({}));
    const host = data.DBInstances[0].Endpoint.Address;
    const user = await getSecret("uname");
    const pass = await getSecret("pword");
    const conn = await mysql.createConnection({ host, user, password: pass });
    
    // BULLETPROOF: Ensure DB and Table exist before doing anything else
    await conn.query("CREATE DATABASE IF NOT EXISTS company");
    await conn.query("USE company");
    await conn.query(`CREATE TABLE IF NOT EXISTS submissions (
        ID INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        RecordNumber VARCHAR(64),
        CustomerName VARCHAR(64),
        Email VARCHAR(64),
        Phone VARCHAR(64),
        Stat INT(1) DEFAULT 0,
        RAWS3URL VARCHAR(200),
        FINSIHEDS3URL VARCHAR(200)
    )`);
    return conn;
}

async function processMessages() {
    try {
        const qData = await sqs.send(new GetQueueUrlCommand({ QueueName: "cpete-module-05-sqs" }));
        const res = await sqs.send(new ReceiveMessageCommand({
            QueueUrl: qData.QueueUrl,
            MaxNumberOfMessages: 1,
            WaitTimeSeconds: 10
        }));

        if (res.Messages) {
            for (const msg of res.Messages) {
                const body = JSON.parse(msg.Body);
                const { s3URL, filename } = body;

                // 1. Find the finished bucket
                const buckets = await s3.send(new ListBucketsCommand({}));
                const rawBucket = buckets.Buckets.find(b => b.Name.includes("raw")).Name;
                const finishedBucket = buckets.Buckets.find(b => b.Name.includes("finished")).Name;

                // 2. "Process" (Copy from Raw to Finished)
                await s3.send(new CopyObjectCommand({
                    Bucket: finishedBucket,
                    CopySource: `${rawBucket}/${filename}`,
                    Key: filename
                }));

                // 3. UPDATE DB TO SAY 'done'
                const conn = await getDB();
                await conn.execute(
                    "UPDATE submissions SET Stat = 1, RAWS3URL = 'done', FINSIHEDS3URL = ? WHERE RAWS3URL = ?",
                    [`https://s3.amazonaws.com/${finishedBucket}/${filename}`, s3URL]
                );
                await conn.end();

                // 4. Delete message from Queue
                await sqs.send(new DeleteMessageCommand({
                    QueueUrl: qData.QueueUrl,
                    ReceiptHandle: msg.ReceiptHandle
                }));
                console.log(`Processed ${filename}`);
            }
        }
    } catch (err) {
        console.error("Worker Error:", err);
    }
    setTimeout(processMessages, 5000); // Check again in 5 seconds
}

processMessages();
EOF

# 5. Dependencies
npm init -y
npm install express multer multer-s3 @aws-sdk/client-s3 @aws-sdk/client-sns @aws-sdk/client-rds @aws-sdk/client-secrets-manager @aws-sdk/client-sqs mysql2 uuid

chmod o+x /home/ec2-user

# 6. Nginx config
chmod o+x /home/ec2-user
cat > /etc/nginx/conf.d/node_app.conf << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
    }
}
EOF
rm -f /etc/nginx/conf.d/default.conf
systemctl restart nginx
systemctl enable nginx

# 7. Final Start
chown -R ec2-user:ec2-user /home/ec2-user/app
sudo -u ec2-user pm2 delete all || true

# Start the web server (Frontend)
sudo -u ec2-user pm2 start /home/ec2-user/app/app.js --name "web-app"

sudo -u ec2-user pm2 save