terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state — stores terraform.tfstate in S3 instead of locally
  # This means state is shared and survives laptop wipes
  # DynamoDB table provides locking so concurrent applies don't corrupt state
  #
  # BEFORE FIRST APPLY: create these manually (one-time bootstrap):
  #   aws s3api create-bucket --bucket cloudmart-tfstate-<your-account-id> --region eu-west-1
  #   aws dynamodb create-table \
  #     --table-name cloudmart-tfstate-lock \
  #     --attribute-definitions AttributeName=LockID,AttributeType=S \
  #     --key-schema AttributeName=LockID,KeyType=HASH \
  #     --billing-mode PAY_PER_REQUEST \
  #     --region eu-west-1
  backend "s3" {
    bucket         = "cloudmart-tfstate-529088262693"
    key            = "production/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "cloudmart-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloudmart"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}
