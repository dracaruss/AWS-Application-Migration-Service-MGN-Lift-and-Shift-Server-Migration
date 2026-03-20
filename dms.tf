# ============================================================
# DMS — replication instance (Step 5)
# ============================================================
# The actual source/target endpoints and migration task are
# easier to create in the console because you'll be iterating
# on connection settings. This just provisions the instance.

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnets"
  replication_subnet_group_description = "DMS subnets for migration POC"
  subnet_ids                           = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "${var.project_name}-dms-subnets" }
}

resource "aws_dms_replication_instance" "main" {
  replication_instance_id    = "${var.project_name}-dms"
  replication_instance_class = "dms.t3.small" # Cheapest available

  allocated_storage           = 20
  vpc_security_group_ids      = [aws_security_group.dms.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.replication_subnet_group_id

  # Set to true if your Kali source is on the public internet (no VPN)
  # Set to false if you're using a Site-to-Site VPN
  publicly_accessible = true

  # Single-AZ for POC
  multi_az = false

  depends_on = [aws_iam_role_policy_attachment.dms_vpc]

  tags = { Name = "${var.project_name}-dms" }
}
