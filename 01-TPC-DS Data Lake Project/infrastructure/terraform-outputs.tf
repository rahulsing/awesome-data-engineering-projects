output "data_lake_bucket_name" {
  description = "S3 Bucket for Data Lake"
  value       = aws_s3_bucket.data_lake.id
}

output "glue_database_name" {
  description = "Glue Database Name"
  value       = aws_glue_catalog_database.data_lake.name
}

output "glue_role_arn" {
  description = "Glue Service Role ARN"
  value       = aws_iam_role.glue_service_role.arn
}

output "athena_workgroup_name" {
  description = "Athena Workgroup Name"
  value       = aws_athena_workgroup.data_lake.name
}

output "bronze_crawler_name" {
  description = "Bronze Layer Crawler Name"
  value       = aws_glue_crawler.bronze.name
}

output "silver_crawler_name" {
  description = "Silver Layer Crawler Name"
  value       = aws_glue_crawler.silver.name
}

output "gold_crawler_name" {
  description = "Gold Layer Crawler Name"
  value       = aws_glue_crawler.gold.name
}
