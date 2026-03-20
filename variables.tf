variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "migration-poc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC — must not overlap with your home network"
  type        = string
  default     = "10.20.0.0/16"
}

variable "home_ip" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.50/32). Find it at checkip.amazonaws.com"
  type        = string
  # No default — you must provide this
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "migration_admin"
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
  # No default — you must provide this
}

variable "create_nat_gateway" {
  description = "Set to true when you need private subnet internet access (DMS, patching). DELETE WHEN DONE — costs $0.045/hr."
  type        = bool
  default     = false
}
