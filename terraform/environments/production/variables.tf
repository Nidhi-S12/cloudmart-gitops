variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name — used as prefix for all resource names"
  type        = string
  default     = "cloudmart"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "availability_zones" {
  description = "AZs to spread subnets across (must be in the selected region)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# EKS
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

# RDS
variable "db_password" {
  description = "Master password for PostgreSQL — set in terraform.tfvars, never hardcode"
  type        = string
  sensitive   = true
}
