# ============================================================
# BOOTSTRAP — Run this ONCE with local state to create the
# S3 bucket and DynamoDB table that Terraform needs for its
# remote backend.
#
# Usage:
#   1. Copy this file to a separate directory
#   2. Run: terraform init && terraform apply
#   3. Note the bucket name from the output
#   4. Update provider.tf in the main project with that bucket name
#   5. Run terraform init in the main project
#   6. You can delete this bootstrap directory afterward
# ============================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state — this is intentional for bootstrapping
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "tf_state" {
  bucket_prefix = "migration-poc-tfstate-"
  force_destroy = true

  tags = { Purpose = "Terraform state for migration POC" }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "Copy this value into provider.tf backend config"
  value       = aws_s3_bucket.tf_state.id
}
