# Streaming Data Lake Project

A real-time data lake implementation using AWS Kinesis, Glue Streaming, and Apache Iceberg.

## Architecture

- **Data Sources**: Two Glue Python Shell jobs generating database and network traffic logs
- **Ingestion**: AWS Kinesis Data Streams (2 streams)
- **Processing**: AWS Glue Streaming Jobs (2 jobs)
- **Storage**: S3 with Apache Iceberg tables
- **Partitioning**: Year/Month/Day/Hour
- **Querying**: AWS Athena

## Project Structure

```
streaming-data-lake/
├── cloudformation/
│   └── infrastructure.yaml       # All AWS resources
├── data-generators/
│   ├── database_log_generator.py # Standalone DB log producer (optional)
│   └── network_log_generator.py  # Standalone network log producer (optional)
├── glue-jobs/
│   ├── database_log_generator.py # Glue Python Shell - DB log producer
│   ├── network_log_generator.py  # Glue Python Shell - Network log producer
│   ├── process_database_logs.py  # Glue Streaming - DB log processor
│   └── process_network_logs.py   # Glue Streaming - Network log processor
├── queries/
│   └── sample_queries.sql        # Athena queries
└── requirements.txt              # For standalone generators only
```

## Setup

1. **Deploy Infrastructure**:
   ```bash
   aws cloudformation create-stack \
     --stack-name streaming-data-lake \
     --template-body file://cloudformation/infrastructure.yaml \
     --capabilities CAPABILITY_NAMED_IAM
   ```

2. **Get ScriptsBucket Name**:
   ```bash
   aws cloudformation describe-stacks --stack-name streaming-data-lake --query "Stacks[0].Outputs[?OutputKey=='ScriptsBucketName'].OutputValue" --output text
   ```

3. **Upload Glue Scripts**:
   ```bash
   aws s3 cp glue-jobs/ s3://YOUR-BUCKET-NAME/scripts/ --recursive
   ```

4. **Start Data Generator Jobs**:
   ```bash
   aws glue start-job-run --job-name streaming-data-lake-generate-database-logs
   aws glue start-job-run --job-name streaming-data-lake-generate-network-logs
   ```

5. **Start Glue Streaming Jobs** from AWS Console or CLI

6. **Query Data** using Athena with queries from `queries/sample_queries.sql`

## Configuration

The data generators run as Glue Python Shell jobs with configurable parameters:
- `records_per_second`: Rate of log generation (default: 5 for DB, 10 for network)
- `duration_minutes`: How long to generate data (default: 60 minutes)

Customize when starting jobs:
```bash
aws glue start-job-run \
  --job-name streaming-data-lake-generate-database-logs \
  --arguments '{"--records_per_second":"20","--duration_minutes":"30"}'
```


## Clean Up

Follow these steps in order to properly clean up all resources:

1. **Stop Data Generator Jobs**:
   Manually OR using CLI:

   ```bash
   aws glue get-job-runs --job-name streaming-data-lake-generate-database-logs --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text | xargs -I {} aws glue batch-stop-job-run --job-name streaming-data-lake-generate-database-logs --job-run-ids {}
   aws glue get-job-runs --job-name streaming-data-lake-generate-network-logs --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text | xargs -I {} aws glue batch-stop-job-run --job-name streaming-data-lake-generate-network-logs --job-run-ids {}
   ```

2. **Stop Glue Streaming Jobs**:
   Manually OR using CLI:

   ```bash
   aws glue get-job-runs --job-name streaming-data-lake-process-database-logs --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text | xargs -I {} aws glue batch-stop-job-run --job-name streaming-data-lake-process-database-logs --job-run-ids {}
   aws glue get-job-runs --job-name streaming-data-lake-process-network-logs --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text | xargs -I {} aws glue batch-stop-job-run --job-name streaming-data-lake-process-network-logs --job-run-ids {}
   ```

3. **Delete S3 Buckets** (CloudFormation cannot delete non-empty buckets):
   Manually OR using CLI:

   ```bash
   # Get bucket names
   SCRIPTS_BUCKET=$(aws cloudformation describe-stacks --stack-name streaming-data-lake --query "Stacks[0].Outputs[?OutputKey=='ScriptsBucketName'].OutputValue" --output text)
   DATA_BUCKET=$(aws cloudformation describe-stacks --stack-name streaming-data-lake --query "Stacks[0].Outputs[?OutputKey=='DataLakeBucketName'].OutputValue" --output text)
   
   # Empty and delete buckets
   aws s3 rm s3://$SCRIPTS_BUCKET --recursive
   aws s3 rb s3://$SCRIPTS_BUCKET
   aws s3 rm s3://$DATA_BUCKET --recursive
   aws s3 rb s3://$DATA_BUCKET
   ```

4. **Delete CloudFormation Stack**:
   ```bash
   aws cloudformation delete-stack --stack-name streaming-data-lake
   ```
