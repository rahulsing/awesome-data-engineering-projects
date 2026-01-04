# Deployment Guide

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform (optional, for Terraform deployment)
- Bash shell (for deployment scripts)

## Deployment Options

### Option 1: CloudFormation

1. Deploy infrastructure:
```bash
aws cloudformation deploy \
  --template-file infrastructure/cloudformation-stack.yaml \
  --stack-name tpcds-datalake-dev \
  --parameter-overrides ProjectName=tpcds-datalake Environment=dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

2. Upload Glue scripts:
```bash
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name tpcds-datalake-dev \
  --query "Stacks[0].Outputs[?OutputKey=='DataLakeBucketName'].OutputValue" \
  --output text)

aws s3 cp glue-jobs/ s3://${BUCKET}/scripts/ --recursive
```

### Option 2: Terraform

1. Initialize Terraform:
```bash
cd infrastructure
terraform init
```

2. Plan deployment:
```bash
terraform plan \
  -var="project_name=tpcds-datalake" \
  -var="environment=dev" \
  -var="aws_region=us-east-1"
```

3. Apply configuration:
```bash
terraform apply \
  -var="project_name=tpcds-datalake" \
  -var="environment=dev" \
  -var="aws_region=us-east-1"
```

### Option 3: Automated Script

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Post-Deployment Setup

### 1. Create Glue Jobs

```bash
# Get outputs
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name tpcds-datalake-dev \
  --query "Stacks[0].Outputs[?OutputKey=='DataLakeBucketName'].OutputValue" \
  --output text)

ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name tpcds-datalake-dev \
  --query "Stacks[0].Outputs[?OutputKey=='GlueRoleArn'].OutputValue" \
  --output text)

# Create Bronze Ingestion Job
aws glue create-job \
  --name tpcds-bronze-ingestion-dev \
  --role "$ROLE_ARN" \
  --command "Name=glueetl,ScriptLocation=s3://${BUCKET}/scripts/bronze_ingestion.py,PythonVersion=3" \
  --glue-version "4.0" \
  --worker-type "G.1X" \
  --number-of-workers 10 \
  --default-arguments "{\"--TARGET_BUCKET\":\"s3://${BUCKET}\",\"--TABLE_NAME\":\"ALL\"}"

# Create Silver Transformation Job
aws glue create-job \
  --name tpcds-silver-transformation-dev \
  --role "$ROLE_ARN" \
  --command "Name=glueetl,ScriptLocation=s3://${BUCKET}/scripts/silver_transformation.py,PythonVersion=3" \
  --glue-version "4.0" \
  --worker-type "G.2X" \
  --number-of-workers 20

# Create Gold Aggregation Job
aws glue create-job \
  --name tpcds-gold-aggregation-dev \
  --role "$ROLE_ARN" \
  --command "Name=glueetl,ScriptLocation=s3://${BUCKET}/scripts/gold_aggregation.py,PythonVersion=3" \
  --glue-version "4.0" \
  --worker-type "G.2X" \
  --number-of-workers 15
```

### 2. Run Pipeline

Execute the automated pipeline:
```bash
chmod +x scripts/run-pipeline.sh
./scripts/run-pipeline.sh
```

Or run manually:

```bash
# Step 1: Bronze Ingestion
aws glue start-job-run --job-name tpcds-bronze-ingestion-dev

# Step 2: Run Bronze Crawler
aws glue start-crawler --name tpcds-datalake-bronze-crawler-dev

# Step 3: Silver Transformation
aws glue start-job-run --job-name tpcds-silver-transformation-dev

# Step 4: Run Silver Crawler
aws glue start-crawler --name tpcds-datalake-silver-crawler-dev

# Step 5: Gold Aggregation
aws glue start-job-run --job-name tpcds-gold-aggregation-dev

# Step 6: Run Gold Crawler
aws glue start-crawler --name tpcds-datalake-gold-crawler-dev
```

## Verification

### Check Glue Catalog Tables

```bash
aws glue get-tables --database-name tpcds_datalake_dev
```

### Query with Athena

```bash
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM gold_daily_sales_summary" \
  --query-execution-context Database=tpcds_datalake_dev \
  --result-configuration OutputLocation=s3://${BUCKET}/athena-results/ \
  --work-group tpcds-datalake-workgroup-dev
```

## Cleanup

### CloudFormation
```bash
aws cloudformation delete-stack --stack-name tpcds-datalake-dev
```

### Terraform
```bash
cd infrastructure
terraform destroy
```

## Troubleshooting

### Glue Job Failures
- Check CloudWatch Logs: `/aws-glue/jobs/output`
- Verify IAM permissions
- Check S3 bucket access

### Crawler Issues
- Ensure data exists in S3 path
- Verify IAM role permissions
- Check crawler logs in CloudWatch

### Athena Query Errors
- Verify table exists in Glue Catalog
- Check S3 data format
- Review query syntax
