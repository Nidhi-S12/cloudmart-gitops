# -------------------------------------------------------
# Security Group — controls who can reach the database
# Only allows port 5432 from within the VPC
# -------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL access from within the VPC only"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # only internal VPC traffic
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# DB Subnet Group — tells RDS which subnets it can use
# Must span at least 2 AZs (AWS requirement)
# -------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Private subnets for RDS"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-subnet-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# RDS PostgreSQL Instance
# -------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true  # encrypt data at rest

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # No public access — only reachable from within the VPC
  publicly_accessible = false

  # Automated backups — keep 7 days of daily snapshots
  backup_retention_period = 7
  backup_window           = "03:00-04:00"  # UTC, low-traffic window

  # Maintenance window for AWS to apply patches
  maintenance_window = "Mon:04:00-Mon:05:00"

  # For portfolio — skip final snapshot on destroy to avoid leftover costs
  skip_final_snapshot = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres"
    Project     = var.project_name
    Environment = var.environment
  }
}
