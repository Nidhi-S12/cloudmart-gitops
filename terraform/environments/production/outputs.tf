# These values are printed after `terraform apply`
# Save them — you'll need them to configure kubectl and app secrets

output "eks_cluster_name" {
  description = "Run: aws eks update-kubeconfig --name <value> --region us-east-1"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "PostgreSQL connection string (set as DATABASE_URL in product-service)"
  value       = module.rds.db_endpoint
}

output "redis_endpoint" {
  description = "Redis connection string (set as REDIS_URL in order-service)"
  value       = module.elasticache.redis_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name for asset uploads"
  value       = module.s3.bucket_name
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — needed when creating IRSA roles for pods"
  value       = module.eks.oidc_provider_arn
}
