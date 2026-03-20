# ============================================================
# OUTPUTS — displayed after terraform apply
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID — use for bastion or MGN test instances"
  value       = aws_subnet.public_a.id
}

output "private_subnet_a_id" {
  description = "Private subnet AZ-a"
  value       = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  description = "Private subnet AZ-b"
  value       = aws_subnet.private_b.id
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint — use this in your app's connection string"
  value       = aws_db_instance.target.endpoint
}

output "rds_address" {
  description = "RDS hostname only (no port)"
  value       = aws_db_instance.target.address
}

output "dms_replication_instance_arn" {
  description = "DMS replication instance ARN — use when creating endpoints in the console"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "app_security_group_id" {
  description = "SG to attach to your migrated EC2 instance"
  value       = aws_security_group.app.id
}

output "ec2_instance_profile" {
  description = "Instance profile to attach to EC2 for SSM + CloudWatch"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "nat_gateway_status" {
  description = "Whether the NAT Gateway is currently deployed ($$$ warning)"
  value       = var.create_nat_gateway ? "RUNNING — costs $0.045/hr!" : "Off — private subnets have no internet"
}
