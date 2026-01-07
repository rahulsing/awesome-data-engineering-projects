# Deployment Guide

## Prerequisites

- AWS CLI configured with appropriate credentials
- Python 3.8+
- AWS account with permissions for CloudFormation, S3, Kinesis, Glue, IAM, Athena

## Step-by-Step Deployment

### 1. Deploy CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name streaming-data-lake \
  --template-body file://cloudformation/infrastructure.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

Wait for stack creation to complete:
```bash
aws cloudformation wait stack-create-complete \
  --stack-name streaming-data-lake \
  --region us-east-1
```

### 2. Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name streaming-data-lake \
  --region us-east-1 \
  --query 'Stacks[0].Outputs'
```

Note down:
- DataLakeBucketName
- ScriptsBucketName
- DatabaseLogStreamName
- NetworkLogStreamName
- GlueDatabaseName

### 3. Upload Glue Scripts to S3

```bash
# Get the scripts bucket name from outputs
SCRIPTS_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name streaming-data-lake \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ScriptsBucketName`].OutputValue' \
  --output text)

# Upload scripts
aws s3 cp glue-jobs/process_database_logs.py s3://${SCRIPTS_BUCKET}/scripts/
aws s3 cp glue-jobs/process_network_logs.py s3://${SCRIPTS_BUCKET}/scripts/
```

### 4. Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 5. Start Data Generator Jobs

Start the Glue Python Shell jobs to generate data:

```bash
# Start database log generator (runs for 60 minutes by default)
aws glue start-job-run \
  --job-name streaming-data-lake-generate-database-logs \
  --region us-east-1

# Start network log generator (runs for 60 minutes by default)
aws glue start-job-run \
  --job-name streaming-data-lake-generate-network-logs \
  --region us-east-1
```

To customize the generation rate and duration, use arguments:
```bash
aws glue start-job-run \
  --job-name streaming-data-lake-generate-database-logs \
  --arguments '{
    "--records_per_second":"10",
    "--duration_minutes":"30"
  }' \
  --region us-east-1
```

### 6. Start Glue Streaming Jobs

Option A - AWS Console:
1. Go to AWS Glue Console
2. Navigate to ETL Jobs
3. Find `streaming-data-lake-process-database-logs`
4. Click "Run job"
5. Repeat for `streaming-data-lake-process-network-logs`

Option B - AWS CLI:
```bash
aws glue start-job-run \
  --job-name streaming-data-lake-process-database-logs \
  --region us-east-1

aws glue start-job-run \
  --job-name streaming-data-lake-process-network-logs \
  --region us-east-1
```

### 7. Monitor Progress

Check data generator job status:
```bash
aws glue get-job-runs \
  --job-name streaming-data-lake-generate-database-logs \
  --region us-east-1 \
  --max-items 1
```

Check streaming job logs:
```bash
aws glue get-job-runs \
  --job-name streaming-data-lake-process-database-logs \
  --region us-east-1
```

Check S3 for data:
```bash
DATA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name streaming-data-lake \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' \
  --output text)

aws s3 ls s3://${DATA_BUCKET}/iceberg/ --recursive
```

### 8. Query Data with Athena

1. Open AWS Athena Console
2. Select database: `streaming-data-lake_db`
3. Run queries from `queries/sample_queries.sql`

Example first query:
```sql
SELECT COUNT(*) as total_queries
FROM "streaming-data-lake_db"."database_logs";
```

## Troubleshooting

### Data Generator Jobs Fail
- Check CloudWatch Logs: `/aws-glue/python-jobs/output`
- Verify Kinesis stream names are correct
- Ensure IAM role has Kinesis PutRecord permissions

### Glue Streaming Job Fails
- Check CloudWatch Logs: `/aws-glue/jobs/output`
- Verify IAM role has correct permissions
- Ensure scripts are uploaded to S3

### No Data in Tables
- Verify data generators are running
- Check Kinesis stream has incoming records
- Verify Glue jobs are running (not stopped)
- Check checkpoint locations in S3

### Athena Query Errors
- Ensure Glue jobs have created tables
- Verify S3 paths are correct
- Check Athena query result location is configured

## Clean Up

Stop all Glue jobs:
```bash
# Stop data generators
aws glue batch-stop-job-run \
  --job-name streaming-data-lake-generate-database-logs \
  --job-run-ids $(aws glue get-job-runs --job-name streaming-data-lake-generate-database-logs --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)

aws glue batch-stop-job-run \
  --job-name streaming-data-lake-generate-network-logs \
  --job-run-ids $(aws glue get-job-runs --job-name streaming-data-lake-generate-network-logs --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)

# Stop streaming processors
```bash
aws glue batch-stop-job-run \
  --job-name streaming-data-lake-process-database-logs \
  --job-run-ids $(aws glue get-job-runs --job-name streaming-data-lake-process-database-logs --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)
```

Empty S3 buckets:
```bash
aws s3 rm s3://${DATA_BUCKET} --recursive
aws s3 rm s3://${SCRIPTS_BUCKET} --recursive
```

Delete CloudFormation stack:
```bash
aws cloudformation delete-stack \
  --stack-name streaming-data-lake \
  --region us-east-1
```

## Cost Considerations

- Kinesis: ~$0.015 per shard hour + data ingestion
- Glue Streaming Jobs: ~$0.44 per DPU hour (2 DPUs per job)
- Glue Python Shell Jobs: ~$0.44 per DPU hour (0.0625 DPU per job)
- S3: Storage + requests
- Athena: ~$5 per TB scanned

Estimated cost for 1 hour of testing: $2-5
- Data generators: ~$0.03/hour (2 jobs × 0.0625 DPU × $0.44)
- Streaming processors: ~$1.76/hour (2 jobs × 2 DPU × $0.44)
- Kinesis: ~$0.03/hour (2 shards × $0.015)
- S3 & Athena: Minimal for testing
