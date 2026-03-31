output "redis_endpoint" {
  description = "Redis primary endpoint — used in app environment variables"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_cluster.main.port
}

output "redis_security_group_id" {
  description = "Security group ID — reference this to allow Redis access from other resources"
  value       = aws_security_group.redis.id
}
