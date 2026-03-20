# ============================================================
# SSH / BASTION — only your home IP
# ============================================================

resource "aws_security_group" "ssh" {
  name        = "${var.project_name}-ssh"
  description = "SSH access from home IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ssh-sg" }
}

# ============================================================
# APP SERVER — HTTP/HTTPS + SSH
# ============================================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "Web app access"
  vpc_id      = aws_vpc.main.id

  # HTTP from your home IP (for testing)
  ingress {
    description = "HTTP from home"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  # HTTPS from your home IP
  ingress {
    description = "HTTPS from home"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  # SSH from your home IP
  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# ============================================================
# DATABASE (RDS) — app server + DMS + your home IP
# ============================================================

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db"
  description = "Database access from app, DMS, and home"
  vpc_id      = aws_vpc.main.id

  # From the app server
  ingress {
    description     = "MySQL from app servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # From DMS replication instance
  ingress {
    description     = "MySQL from DMS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
  }

  # From your home IP (for manual testing with mysql client)
  ingress {
    description = "MySQL from home"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}

# ============================================================
# DMS REPLICATION INSTANCE
# ============================================================

resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms"
  description = "DMS replication instance"
  vpc_id      = aws_vpc.main.id

  # DMS needs to reach your Kali VM's MySQL (source).
  # If using VPN: add a rule for your on-prem CIDR.
  # If using public internet: DMS uses its own public IP to connect
  # to your source, so this SG only needs outbound access.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-dms-sg" }
}

# ============================================================
# MGN REPLICATION — used by the MGN staging/replication servers
# ============================================================

resource "aws_security_group" "mgn" {
  name        = "${var.project_name}-mgn"
  description = "MGN replication traffic"
  vpc_id      = aws_vpc.main.id

  # MGN agent on your Kali VM connects TO AWS on port 1500 (TCP)
  ingress {
    description = "MGN replication from source"
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # MGN agent connects from your home IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-mgn-sg" }
}
