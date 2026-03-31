output "db_endpoint" {
  description = "RDS connection endpoint — used in app environment variables"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Master username"
  value       = aws_db_instance.main.username
}

output "db_port" {
  description = "Database port"
  value       = aws_db_instance.main.port
}

output "rds_security_group_id" {
  description = "Security group ID — other modules can reference this to allow DB access"
  value       = aws_security_group.rds.id
}
