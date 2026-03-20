# ============================================================
# IAM ROLE FOR EC2 — lets migrated instances talk to AWS services
# ============================================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = { Name = "${var.project_name}-ec2-role" }
}

# ============================================================
# IAM ROLE FOR DMS 
# ============================================================

resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_user" "mgn_agent" {
  name = "mgn-agent"
}

resource "aws_iam_user_policy_attachment" "mgn_install" {
  user       = aws_iam_user.mgn_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationMigrationAgentInstallationPolicy"
}

resource "aws_iam_user_policy_attachment" "mgn_agent" {
  user       = aws_iam_user.mgn_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationMigrationAgentPolicy"
}

# Allow EC2 to write CloudWatch logs and access SSM (for Session Manager)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ============================================================
# CLOUDTRAIL — audit log (free for 1 management trail)
# ============================================================

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false # Single region for POC
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.trail_logs]
}

resource "aws_s3_bucket" "trail_logs" {
  bucket_prefix = "${var.project_name}-trail-"
  force_destroy = true # Allow terraform destroy to delete non-empty bucket

  tags = { Name = "${var.project_name}-trail-logs" }
}

resource "aws_s3_bucket_policy" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.trail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.trail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
