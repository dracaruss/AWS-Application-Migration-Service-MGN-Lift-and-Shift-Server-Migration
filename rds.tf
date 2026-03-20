# ============================================================
# RDS MYSQL — migration target for DMS (Step 5)
# ============================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "target" {
  identifier = "${var.project_name}-target-db"

  # Engine
  engine         = "mysql"
  engine_version = "8.0"

  # Size — free tier
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  # Credentials
  username = var.db_username
  password = var.db_password
  db_name  = "appdb"

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Backup — minimal for POC
  backup_retention_period = 1
  skip_final_snapshot     = true

  # Encryption — always on, even for POC (good habit)
  storage_encrypted = true

  # Parameters — DMS needs binlog on the TARGET too for validation
  parameter_group_name = aws_db_parameter_group.target.name

  tags = { Name = "${var.project_name}-target-db" }
}

resource "aws_db_parameter_group" "target" {
  name   = "${var.project_name}-target-params"
  family = "mysql8.0"

  # DMS validation needs binlog_format = ROW on the target as well
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = { Name = "${var.project_name}-target-params" }
}
