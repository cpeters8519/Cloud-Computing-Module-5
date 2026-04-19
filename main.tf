##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
##############################################################################
# Create a VPC
resource "aws_vpc" "project" {
  cidr_block           = "172.32.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = var.tag-name
  }
}

# Query the VPC information
data "aws_vpc" "project" {
  id = aws_vpc.project.id
}

# Get all AZs in a VPC
data "aws_availability_zones" "available" {
  state = "available"
}

# Print out a list of Availability Zones
output "list-of-azs" {
  description = "List of AZs"
  value       = data.aws_availability_zones.available.names
}

# Create security group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow http inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.project.id

  tags = {
    proto = "http"
    Name  = var.tag-name
  }
}

# HTTP ingress rule - port 80
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

# SSH ingress rule - port 22
resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# MySQL ingress rule - port 3306
# Required for RDS connectivity from EC2 instances
resource "aws_vpc_security_group_ingress_rule" "allow_mysql_ipv4" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}

# Egress - allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Data source to look up the security group by tag for use with RDS
data "aws_security_group" "coursera-project" {
  depends_on = [aws_security_group.allow_http]
  filter {
    name   = "tag:Name"
    values = [var.tag-name]
  }
}

# Create VPC DHCP options -- public DNS provided by Amazon
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_dhcp_options
resource "aws_vpc_dhcp_options" "project" {
  domain_name         = "${var.region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name = var.tag-name
  }
}

# Associate DHCP options with our VPC
resource "aws_vpc_dhcp_options_association" "dns_resolver" {
  vpc_id          = aws_vpc.project.id
  dhcp_options_id = aws_vpc_dhcp_options.project.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.project.id

  tags = {
    Name = var.tag-name
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "example" {
  depends_on = [aws_vpc.project]
  vpc_id     = aws_vpc.project.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = var.tag-name
  }
}

# Associate the route table to each subnet
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "subnets" {
  count          = var.number-of-azs
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.example.id
}

# main route table for the VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/main_route_table_association
resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.project.id
  route_table_id = aws_route_table.example.id
}

##############################################################################
# IAM - Instance Profile, Role, and Policies
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
##############################################################################

resource "aws_iam_instance_profile" "coursera_profile" {
  name = "coursera_profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy" "sqs_fullaccess_policy" {
  name = "sqs_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:*",
          "secretsmanager:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_instance" "backend" {
  ami                    = var.imageid
  instance_type          = var.instance-type
  key_name               = var.key-name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.allow_http.id]

  iam_instance_profile = aws_iam_instance_profile.coursera_profile.name

  user_data = filebase64("./install-env.sh")

  tags = {
    Name = var.tag-name
    Type = "backend"
  }
}

# Trust policy - allows EC2 to assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM
resource "aws_iam_role" "role" {
  name               = "project_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = var.tag-name
  }
}

# IAM Policy 1 of 4: S3 full access
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "s3_fullaccess_policy" {
  name = "s3_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# IAM Policy 2 of 4: RDS full access
resource "aws_iam_role_policy" "rds_fullaccess_policy" {
  name = "rds_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["rds:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# IAM Policy 3 of 4: SNS full access
resource "aws_iam_role_policy" "sns_fullaccess_policy" {
  name = "sns_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["sns:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# IAM Policy 4 of 4: Secrets Manager full access
resource "aws_iam_role_policy" "secretsmanager_fullaccess_policy" {
  name = "secretsmanager_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

##############################################################################
# Subnets - one per AZ
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
##############################################################################
resource "aws_subnet" "private" {
  depends_on              = [aws_vpc.project]
  count                   = var.number-of-azs
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = data.aws_vpc.project.id
  map_public_ip_on_launch = true
  cidr_block              = cidrsubnet(data.aws_vpc.project.cidr_block, 4, count.index + 3)

  tags = {
    Name = var.tag-name
    Type = "private"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.project.id]
  }
}

output "aws_subnets" {
  value = [data.aws_vpc.project.id]
}

##############################################################################
# Launch Template
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template
##############################################################################
resource "aws_launch_template" "lt" {
  image_id                             = var.imageid
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = var.instance-type
  key_name                             = var.key-name
  vpc_security_group_ids               = [aws_security_group.allow_http.id]

  # IAM instance profile - grants EC2 instances permissions to use S3, RDS, SNS, SM
  iam_instance_profile {
    name = aws_iam_instance_profile.coursera_profile.name
  }

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.tag-name
    }
  }

  user_data = filebase64("./install-env.sh")
}

##############################################################################
# Auto Scaling Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
##############################################################################
resource "aws_autoscaling_group" "asg" {
  name                      = var.asg-name
  depends_on                = [aws_launch_template.lt]
  desired_capacity          = var.desired
  max_size                  = var.max
  min_size                  = var.min
  health_check_grace_period = 300
  health_check_type         = "EC2"
  target_group_arns         = [aws_lb_target_group.alb-lb-tg.arn]
  vpc_zone_identifier       = [for subnet in aws_subnet.private : subnet.id]

  tag {
    key                 = "assessment"
    value               = var.tag-name
    propagate_at_launch = true
  }

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

##############################################################################
# Application Load Balancer
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
##############################################################################
resource "aws_lb" "lb" {
  depends_on         = [aws_subnet.private]
  name               = var.elb-name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [for subnet in aws_subnet.private : subnet.id]

  enable_deletion_protection = false

  tags = {
    Name = var.tag-name
  }
}

output "url" {
  value = aws_lb.lb.dns_name
}

##############################################################################
# ASG Attachment to ALB
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
##############################################################################
resource "aws_autoscaling_attachment" "example" {
  depends_on             = [aws_lb.lb]
  autoscaling_group_name = aws_autoscaling_group.asg.id
  lb_target_group_arn    = aws_lb_target_group.alb-lb-tg.arn
}

output "alb-lb-tg-arn" {
  value = aws_lb_target_group.alb-lb-tg.arn
}

output "alb-lb-tg-id" {
  value = aws_lb_target_group.alb-lb-tg.id
}

##############################################################################
# Target Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
##############################################################################
resource "aws_lb_target_group" "alb-lb-tg" {
  depends_on  = [aws_lb.lb]
  name        = var.tg-name
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.project.id
}

##############################################################################
# ALB Listener
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
##############################################################################
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-lb-tg.arn
  }
}

##############################################################################
# S3 Buckets
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
##############################################################################
resource "aws_s3_bucket" "raw-bucket" {
  bucket        = var.raw-s3-bucket
  force_destroy = true
}

resource "aws_s3_bucket" "finished-bucket" {
  bucket        = var.finished-s3-bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "allow_access_from_another_account-raw" {
  bucket     = aws_s3_bucket.raw-bucket.id
  depends_on = [data.aws_iam_policy_document.allow_access_from_another_account-raw]

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_public_access_block" "allow_access_from_another_account-finished" {
  bucket     = aws_s3_bucket.finished-bucket.id
  depends_on = [data.aws_iam_policy_document.allow_access_from_another_account-finished]

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_access_from_another_account-raw" {
  depends_on = [aws_s3_bucket_public_access_block.allow_access_from_another_account-raw]
  bucket     = aws_s3_bucket.raw-bucket.id
  policy     = data.aws_iam_policy_document.allow_access_from_another_account-raw.json
}

resource "aws_s3_bucket_policy" "allow_access_from_another_account-finished" {
  depends_on = [aws_s3_bucket_public_access_block.allow_access_from_another_account-finished]
  bucket     = aws_s3_bucket.finished-bucket.id
  policy     = data.aws_iam_policy_document.allow_access_from_another_account-finished.json
}

data "aws_iam_policy_document" "allow_access_from_another_account-raw" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:GetObject"]

    resources = [
      aws_s3_bucket.raw-bucket.arn,
      "${aws_s3_bucket.raw-bucket.arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "allow_access_from_another_account-finished" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:GetObject"]

    resources = [
      aws_s3_bucket.finished-bucket.arn,
      "${aws_s3_bucket.finished-bucket.arn}/*",
    ]
  }
}

##############################################################################
# SQS Queue
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
##############################################################################
resource "aws_sqs_queue" "coursera_queue" {
  name                       = var.sqs-name
  delay_seconds              = 90
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 180

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# SNS Topic
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
##############################################################################
resource "aws_sns_topic" "user_updates" {
  name = var.user-sns-topic

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# Secrets Manager
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret
##############################################################################

# Generate a random password so it is never hardcoded
data "aws_secretsmanager_random_password" "coursera_project" {
  password_length     = 30
  exclude_numbers     = false
  exclude_punctuation = false
  exclude_characters  = "/@\" "
}

# Secret: uname (username for RDS)
resource "aws_secretsmanager_secret" "coursera_project_username" {
  name                    = "uname"
  recovery_window_in_days = 0

  tags = {
    Name = var.tag-name
  }
}

# Secret: pword (password for RDS)
resource "aws_secretsmanager_secret" "coursera_project_password" {
  name                    = "pword"
  recovery_window_in_days = 0

  tags = {
    Name = var.tag-name
  }
}

# Set the value of uname
resource "aws_secretsmanager_secret_version" "coursera_project_username" {
  secret_id     = aws_secretsmanager_secret.coursera_project_username.id
  secret_string = var.username
}

# Set the value of pword (randomly generated above)
resource "aws_secretsmanager_secret_version" "coursera_project_password" {
  secret_id     = aws_secretsmanager_secret.coursera_project_password.id
  secret_string = data.aws_secretsmanager_random_password.coursera_project.random_password
}

# Retrieve uname secret value (for passing to RDS)
data "aws_secretsmanager_secret_version" "project_username" {
  depends_on = [aws_secretsmanager_secret_version.coursera_project_username]
  secret_id  = aws_secretsmanager_secret.coursera_project_username.id
}

# Retrieve pword secret value (for passing to RDS)
data "aws_secretsmanager_secret_version" "project_password" {
  depends_on = [aws_secretsmanager_secret_version.coursera_project_password]
  secret_id  = aws_secretsmanager_secret.coursera_project_password.id
}

##############################################################################
# DB Subnet Group - places RDS inside our custom VPC subnets
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
##############################################################################
resource "aws_db_subnet_group" "default" {
  name       = "coursera-project"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = var.tag-name
  }
}

# Data source to reference the subnet group
data "aws_db_subnet_group" "database" {
  depends_on = [aws_db_subnet_group.default]
  name       = "coursera-project"
}

##############################################################################
# RDS Instance - restored from snapshot
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
##############################################################################
resource "aws_db_instance" "default" {
  instance_class         = "db.t3.micro"
  snapshot_identifier    = var.snapshot_identifier
  skip_final_snapshot    = true
  username               = data.aws_secretsmanager_secret_version.project_username.secret_string
  password               = data.aws_secretsmanager_secret_version.project_password.secret_string
  vpc_security_group_ids = [data.aws_security_group.coursera-project.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name

  tags = {
    Name = var.tag-name
  }
}

output "db-address" {
  description = "Endpoint URL"
  value       = aws_db_instance.default.address
}

output "db-name" {
  description = "DB Name"
  value       = aws_db_instance.default.db_name
}
