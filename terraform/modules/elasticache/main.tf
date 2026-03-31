# -------------------------------------------------------
# Security Group — only allows Redis port from within VPC
# -------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Allow Redis access from within the VPC only"
  vpc_id      = var.vpc_id

  ingress {
    description = "Redis from within VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# Subnet Group — tells ElastiCache which subnets to use
# -------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis-subnet-group"
  description = "Private subnets for ElastiCache Redis"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-subnet-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# ElastiCache Redis Cluster
# -------------------------------------------------------
resource "aws_elasticache_cluster" "main" {
  cluster_id        = "${var.project_name}-${var.environment}-redis"
  engine            = "redis"
  engine_version    = var.redis_version
  node_type         = var.node_type
  num_cache_nodes   = var.num_cache_nodes
  port              = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Automatic minor version upgrades (e.g. 7.0.x patches)
  auto_minor_version_upgrade = true

  # Maintenance window — low traffic hours UTC
  maintenance_window = "sun:05:00-sun:06:00"

  # Snapshot for backup — keeps 1 day (minimum, keeps costs low)
  snapshot_retention_limit = 1
  snapshot_window          = "04:00-05:00"

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis"
    Project     = var.project_name
    Environment = var.environment
  }
}
