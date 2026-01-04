terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket for Data Lake
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Glue Database
resource "aws_glue_catalog_database" "data_lake" {
  name        = "${var.project_name}_${var.environment}"
  description = "TPC-DS Data Lake Database"
}

# IAM Role for Glue
resource "aws_iam_role" "glue_service_role" {
  name = "${var.project_name}-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "s3-access"
  role = aws_iam_role.glue_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/*",
          "arn:aws:s3:::redshift-downloads/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "arn:aws:s3:::redshift-downloads"
        ]
      }
    ]
  })
}

# Glue Crawlers
resource "aws_glue_crawler" "bronze" {
  name          = "${var.project_name}-bronze-crawler-${var.environment}"
  role          = aws_iam_role.glue_service_role.arn
  database_name = aws_glue_catalog_database.data_lake.name
  table_prefix  = "bronze_"

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/bronze/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

resource "aws_glue_crawler" "silver" {
  name          = "${var.project_name}-silver-crawler-${var.environment}"
  role          = aws_iam_role.glue_service_role.arn
  database_name = aws_glue_catalog_database.data_lake.name
  table_prefix  = "silver_"

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/silver/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

resource "aws_glue_crawler" "gold" {
  name          = "${var.project_name}-gold-crawler-${var.environment}"
  role          = aws_iam_role.glue_service_role.arn
  database_name = aws_glue_catalog_database.data_lake.name
  table_prefix  = "gold_"

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/gold/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# Athena Workgroup
resource "aws_athena_workgroup" "data_lake" {
  name = "${var.project_name}-workgroup-${var.environment}"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
    }
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
  }
}

data "aws_caller_identity" "current" {}
