#!/bin/bash
set -euxo pipefail

# (ONLY ADDITION) Helps debug EC2 boot failures
exec > /var/log/user-data.log 2>&1

# 1. Install System Packages
dnf update -y
dnf swap -y curl-minimal curl
dnf install -y nginx git unzip mariadb105

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

npm install -g pm2

# 2. Setup App Directory
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# 3. Create index.html (UNCHANGED)
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>ITMO 463 Module 04</title></head>
<body>
    <h1>Student Name</h1>
    <form class="form-horizontal" method="post" enctype="multipart/form-data" action="/upload">
        Name: <input type="text" name="name"/><br>
        Email: <input type="text" name="email"/><br>
        Phone: <input type="text" name="phone"/><br>
        File: <input type="file" name="uploadFile"/><br>
        <input type="submit" value="Upload"/>
    </form>
</body>
</html>
EOF

# 4. Create app.js (UNCHANGED LOGIC — only SAFE AWS SDK stability tweak)

cat > app.js << 'EOF'
const express = require('express');
const app = express();
const multer = require("multer");
const multerS3 = require("multer-s3");
const { v4: uuidv4 } = require("uuid");

const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3');
const { SNSClient, ListTopicsCommand, SubscribeCommand, PublishCommand } = require("@aws-sdk/client-sns");
const { RDSClient, DescribeDBInstancesCommand } = require("@aws-sdk/client-rds");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");

const REGION = "us-east-2";

const s3 = new S3Client({ region: REGION });

app.use(express.urlencoded({ extended: true }));

async function getRawBucketName() {
    const data = await s3.send(new ListBucketsCommand({}));
    return data.Buckets.find(b => b.Name.includes("raw")).Name;
}

const upload = multer({
    storage: multerS3({
        s3: s3,
        bucket: async (req, file, cb) => {
            const data = await s3.send(new ListBucketsCommand({}));
            const bucket = data.Buckets.find(b => b.Name.includes("raw")).Name;
            cb(null, bucket);
        },
        key: function (req, file, cb) {
            cb(null, file.originalname);
        }
    })
});

async function getSecret(id) {
    const client = new SecretsManagerClient({ region: REGION });
    const res = await client.send(new GetSecretValueCommand({ SecretId: id }));
    return res.SecretString;
}

app.post("/upload", upload.array("uploadFile", 1), async (req, res) => {
    try {
        const bucketName = await getRawBucketName();
        const s3URL = `https://${bucketName}.s3.amazonaws.com/${req.files[0].originalname}`;

        const rds = new RDSClient({ region: REGION });
        const dbData = await rds.send(new DescribeDBInstancesCommand({}));
        const host = dbData.DBInstances[0].Endpoint.Address;

        const user = await getSecret("uname");
        const pass = await getSecret("pword");

        const mysql = require("mysql2/promise");
        const connection = await mysql.createConnection({
            host: host,
            user: user,
            password: pass
        });

        await connection.query("CREATE DATABASE IF NOT EXISTS company");
        await connection.query("USE company");

        await connection.query(`CREATE TABLE IF NOT EXISTS entries (
            RecordNumber VARCHAR(255),
            CustomerName VARCHAR(255),
            Email VARCHAR(255),
            Phone VARCHAR(255),
            Stat INT,
            RAWS3URL VARCHAR(255)
        )`);

        await connection.execute(
            "INSERT INTO entries VALUES (?,?,?,?,1,?)",
            [uuidv4(), req.body.name, req.body.email, req.body.phone, s3URL]
        );

        const sns = new SNSClient({ region: REGION });
        const topics = await sns.send(new ListTopicsCommand({}));
        const topicArn = topics.Topics[0].TopicArn;

        await sns.send(new SubscribeCommand({
            Protocol: "email",
            TopicArn: topicArn,
            Endpoint: req.body.email
        }));

        await sns.send(new PublishCommand({
            TopicArn: topicArn,
            Subject: "Upload Ready",
            Message: `File: ${s3URL}`
        }));

        res.send("<h1>Success!</h1><p>Check your email to confirm subscription.</p>");
    } catch (err) {
        console.error(err);
        res.status(500).send("Error: " + err.message);
    }
});

app.get("/", (req, res) => res.sendFile(__dirname + "/index.html"));
app.listen(3000);
EOF

# 5. Install Node Dependencies (UNCHANGED)
npm init -y
npm install express multer multer-s3 @aws-sdk/client-s3 @aws-sdk/client-sns @aws-sdk/client-rds @aws-sdk/client-secrets-manager mysql2 uuid

# 6. Nginx Setup (UNCHANGED)
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

# 7. Start App (UNCHANGED)
chown -R ec2-user:ec2-user /home/ec2-user/app

sudo -u ec2-user pm2 start /home/ec2-user/app/app.js --name "node-app"
sudo -u ec2-user pm2 save