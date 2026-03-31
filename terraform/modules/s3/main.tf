# -------------------------------------------------------
# S3 Bucket
# Bucket names are globally unique across all AWS accounts
# Using project + environment + account ID suffix avoids clashes
# -------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-${var.environment}-assets-${data.aws_caller_identity.current.account_id}"

  # force_destroy = true lets terraform destroy delete the bucket even if it has
  # files in it — important for a demo so you don't get stuck with orphaned buckets
  force_destroy = var.force_destroy

  tags = {
    Name        = "${var.project_name}-${var.environment}-assets"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# Block all public access
# These 4 settings close every route to accidental public exposure
# -------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true  # reject any request that includes a public ACL
  block_public_policy     = true  # reject bucket policies that grant public access
  ignore_public_acls      = true  # ignore any existing public ACLs
  restrict_public_buckets = true  # restrict access to AWS services and authorised users
}

# -------------------------------------------------------
# Versioning — keeps previous versions of overwritten files
# Useful for recovering accidentally deleted images
# -------------------------------------------------------
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -------------------------------------------------------
# Server-side encryption — all objects encrypted at rest
# SSE-S3 uses AWS-managed keys, zero cost, zero config overhead
# -------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -------------------------------------------------------
# Lifecycle rule — auto-expire old non-current versions after 30 days
# Without this, versioning accumulates old copies indefinitely = surprise bills
# -------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
