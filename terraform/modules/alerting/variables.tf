variable "project_name" {
  description = "Project name — used as prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., production)"
  type        = string
}

variable "alert_email" {
  description = "Email address that receives AlertManager notifications"
  type        = string
}
