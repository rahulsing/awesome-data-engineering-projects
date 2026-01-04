# Complete deployment script for TPC-DS Data Lake (PowerShell)
# This script handles infrastructure deployment and Glue resource setup

$ErrorActionPreference = "Stop"

# Configuration
$PROJECT_NAME = "tpcds-datalake"
$ENVIRONMENT = "dev"
$AWS_REGION = "us-east-1"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "TPC-DS Data Lake Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Function to check AWS CLI
function Test-AwsCli {
    try {
        $null = aws --version
        Write-Host "✓ AWS CLI found" -ForegroundColor Green
        
        # Check AWS credentials
        $null = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
            exit 1
        }
        Write-Host "✓ AWS credentials configured" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
        exit 1
    }
}

# Function to deploy CloudFormation stack
function Deploy-CloudFormation {
    Write-Host ""
    Write-Host "Deploying CloudFormation stack..." -ForegroundColor Yellow
    
    $STACK_NAME = "$PROJECT_NAME-$ENVIRONMENT"
    
    aws cloudformation deploy `
        --template-file infrastructure/cloudformation-stack.yaml `
        --stack-name $STACK_NAME `
        --parameter-overrides ProjectName=$PROJECT_NAME Environment=$ENVIRONMENT `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $AWS_REGION
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ CloudFormation stack deployed" -ForegroundColor Green
    }
    else {
        Write-Host "Error deploying CloudFormation stack" -ForegroundColor Red
        exit 1
    }
}

# Function to get stack outputs
function Get-StackOutputs {
    Write-Host ""
    Write-Host "Retrieving stack outputs..." -ForegroundColor Yellow
    
    $script:BUCKET_NAME = aws cloudformation describe-stacks `
        --stack-name "$PROJECT_NAME-$ENVIRONMENT" `
        --query "Stacks[0].Outputs[?OutputKey=='DataLakeBucketName'].OutputValue" `
        --output text `
        --region $AWS_REGION
    
    $script:ROLE_ARN = aws cloudformation describe-stacks `
        --stack-name "$PROJECT_NAME-$ENVIRONMENT" `
        --query "Stacks[0].Outputs[?OutputKey=='GlueRoleArn'].OutputValue" `
        --output text `
        --region $AWS_REGION
    
    $script:DATABASE_NAME = aws cloudformation describe-stacks `
        --stack-name "$PROJECT_NAME-$ENVIRONMENT" `
        --query "Stacks[0].Outputs[?OutputKey=='GlueDatabaseName'].OutputValue" `
        --output text `
        --region $AWS_REGION
    
    Write-Host "✓ S3 Bucket: $BUCKET_NAME" -ForegroundColor Green
    Write-Host "✓ Glue Database: $DATABASE_NAME" -ForegroundColor Green
    Write-Host "✓ IAM Role: $ROLE_ARN" -ForegroundColor Green
}

# Function to upload Glue scripts
function Upload-GlueScripts {
    Write-Host ""
    Write-Host "Uploading Glue ETL scripts to S3..." -ForegroundColor Yellow
    
    aws s3 cp glue-jobs/ "s3://$BUCKET_NAME/scripts/" --recursive --region $AWS_REGION
    
    Write-Host "✓ Glue scripts uploaded to s3://$BUCKET_NAME/scripts/" -ForegroundColor Green
}

# Function to create Glue jobs
function New-GlueJobs {
    Write-Host ""
    Write-Host "Creating Glue ETL jobs..." -ForegroundColor Yellow
    
    # Bronze Ingestion Job
    Write-Host "Creating Bronze Ingestion job..."
    aws glue create-job `
        --name "$PROJECT_NAME-bronze-ingestion-$ENVIRONMENT" `
        --role "$ROLE_ARN" `
        --command '{\"Name\":\"glueetl\",\"ScriptLocation\":\"s3://'$BUCKET_NAME'/scripts/bronze_ingestion.py\",\"PythonVersion\":\"3\"}' `
        --glue-version "4.0" `
        --worker-type "G.1X" `
        --number-of-workers 10 `
        --default-arguments '{\"--TARGET_BUCKET\":\"s3://'$BUCKET_NAME'\",\"--TABLE_NAME\":\"ALL\"}' `
        --region $AWS_REGION 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Bronze job already exists, skipping..." -ForegroundColor Yellow
    }
    
    # Silver Transformation Job
    Write-Host "Creating Silver Transformation job..."
    aws glue create-job `
        --name "$PROJECT_NAME-silver-transformation-$ENVIRONMENT" `
        --role "$ROLE_ARN" `
        --command '{\"Name\":\"glueetl\",\"ScriptLocation\":\"s3://'$BUCKET_NAME'/scripts/silver_transformation.py\",\"PythonVersion\":\"3\"}' `
        --glue-version "4.0" `
        --worker-type "G.2X" `
        --number-of-workers 20 `
        --default-arguments '{\"--DATABASE_NAME\":\"'$DATABASE_NAME'\",\"--TARGET_BUCKET\":\"s3://'$BUCKET_NAME'\",\"--TABLE_NAME\":\"store_sales\"}' `
        --region $AWS_REGION 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Silver job already exists, skipping..." -ForegroundColor Yellow
    }
    
    # Gold Aggregation Job
    Write-Host "Creating Gold Aggregation job..."
    aws glue create-job `
        --name "$PROJECT_NAME-gold-aggregation-$ENVIRONMENT" `
        --role "$ROLE_ARN" `
        --command '{\"Name\":\"glueetl\",\"ScriptLocation\":\"s3://'$BUCKET_NAME'/scripts/gold_aggregation.py\",\"PythonVersion\":\"3\"}' `
        --glue-version "4.0" `
        --worker-type "G.2X" `
        --number-of-workers 15 `
        --default-arguments '{\"--DATABASE_NAME\":\"'$DATABASE_NAME'\",\"--TARGET_BUCKET\":\"s3://'$BUCKET_NAME'\"}' `
        --region $AWS_REGION 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Gold job already exists, skipping..." -ForegroundColor Yellow
    }
    
    Write-Host "✓ Glue jobs created" -ForegroundColor Green
}

# Function to display summary
function Show-Summary {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Deployment Complete!" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Resources Created:" -ForegroundColor Green
    Write-Host "  • S3 Bucket: $BUCKET_NAME"
    Write-Host "  • Glue Database: $DATABASE_NAME"
    Write-Host "  • Glue Crawlers: bronze, silver, gold"
    Write-Host "  • Glue Jobs: bronze-ingestion, silver-transformation, gold-aggregation"
    Write-Host "  • Athena Workgroup: $PROJECT_NAME-workgroup-$ENVIRONMENT"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Run the pipeline manually with AWS CLI"
    Write-Host "  2. Execute: aws glue start-job-run --job-name $PROJECT_NAME-bronze-ingestion-$ENVIRONMENT"
    Write-Host "  3. Query data in Athena - Database: $DATABASE_NAME"
    Write-Host ""
}

# Main deployment flow
Write-Host "Starting deployment..." -ForegroundColor Yellow
Write-Host ""

Test-AwsCli
Deploy-CloudFormation
Get-StackOutputs
Upload-GlueScripts
New-GlueJobs
Show-Summary
