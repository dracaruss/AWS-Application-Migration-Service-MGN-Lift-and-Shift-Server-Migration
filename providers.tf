terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # IMPORTANT: The S3 bucket and DynamoDB table must exist BEFORE you run
  # terraform init. See bootstrap.tf for how to create them, or create
  # them manually in the console first.
  #
  # Comment out this entire backend block for your first run if you want
  # to use local state while bootstrapping, then uncomment and run
  # terraform init -migrate-state to switch to S3.

  backend "s3" {
    bucket       = "migration-poc-tfstate-20260320024223697500000001" # CHANGE THIS — must be globally unique
    key          = "migration-poc/terraform.tfstate"
    region       = "us-east-1" # Match var.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "poc"
      ManagedBy   = "terraform"
    }
  }
}
