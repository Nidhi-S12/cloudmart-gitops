output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket — used in IAM policies to grant access"
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name — used to construct URLs for uploaded assets"
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
