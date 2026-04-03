# -------------------------------------------------------
# VPC — must be first, everything else depends on it
# -------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  availability_zones   = var.availability_zones
}

# -------------------------------------------------------
# EKS — uses VPC outputs for subnet placement
# -------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  kubernetes_version = var.kubernetes_version
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size

  # These come from the VPC module output
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
}

# -------------------------------------------------------
# RDS — PostgreSQL for product-service
# -------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  db_password        = var.db_password

  # From VPC module
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
}

# -------------------------------------------------------
# ElastiCache — Redis for order-service
# -------------------------------------------------------
module "elasticache" {
  source = "../../modules/elasticache"

  project_name       = var.project_name
  environment        = var.environment

  # From VPC module
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
}

# -------------------------------------------------------
# S3 — asset storage
# -------------------------------------------------------
module "s3" {
  source = "../../modules/s3"

  project_name = var.project_name
  environment  = var.environment
}
