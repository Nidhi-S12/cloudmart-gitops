variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RDS will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used to restrict DB access to inside the VPC only"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "cloudmart"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "cloudmart_admin"
}

variable "db_password" {
  description = "Master password for the database — pass in via tfvars, never hardcode"
  type        = string
  sensitive   = true  # Terraform will not print this in logs
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"  # cheapest option — fine for portfolio
}

variable "db_allocated_storage" {
  description = "Storage size in GB"
  type        = number
  default     = 20
}

variable "postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15"
}
