variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "force_destroy" {
  description = "Delete bucket contents on terraform destroy (set true for portfolio/demo)"
  type        = bool
  default     = true
}
