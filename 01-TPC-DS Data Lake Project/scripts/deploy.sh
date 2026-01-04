#!/bin/bash

# Complete deployment script for TPC-DS Data Lake
# This script handles infrastructure deployment and Glue resource setup

set -e

# Configuration
PROJECT_NAME="tpcds-datalake"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"

echo "========================================="
echo "TPC-DS Data Lake Deployment"
echo "========================================="

# Function to check AWS CLI
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed"
        exit 1
    fi
    echo "✓ AWS CLI found"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials not configured"
        exit 1
    fi
    echo "✓ AWS credentials configured"
}

# Function to deploy CloudFormation stack
deploy_cloudformation() {
    echo ""
    echo "Deploying CloudFormation stack..."
    
    STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
    
    aws cloudformation deploy \
        --template-file infrastructure/cloudformation-stack.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides \
            ProjectName=$PROJECT_NAME \
            Environment=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION
    
    echo "✓ CloudFormation stack deployed (includes S3 bucket, Glue database, crawlers, IAM roles)"
}

# Function to deploy Terraform
deploy_terraform() {
    echo ""
    echo "Deploying with Terraform..."
    
    cd infrastructure
    
    terraform init
    terraform plan \
        -var="project_name=$PROJECT_NAME" \
        -var="environment=$ENVIRONMENT" \
        -var="aws_region=$AWS_REGION"
    
    terraform apply \
        -var="project_name=$PROJECT_NAME" \
        -var="environment=$ENVIRONMENT" \
        -var="aws_region=$AWS_REGION" \
        -auto-approve
    
    cd ..
    
    echo "✓ Terraform deployment complete (includes S3 bucket, Glue database, crawlers, IAM roles)"
}

# Function to get stack outputs
get_stack_outputs() {
    echo ""
    echo "Retrieving stack outputs..."
    
    if [ "$DEPLOYMENT_METHOD" == "cloudformation" ]; then
        BUCKET_NAME=$(aws cloudformation describe-stacks \
            --stack-name "${PROJECT_NAME}-${ENVIRONMENT}" \
            --query "Stacks[0].Outputs[?OutputKey=='DataLakeBucketName'].OutputValue" \
            --output text \
            --region $AWS_REGION)
        
        ROLE_ARN=$(aws cloudformation describe-stacks \
            --stack-name "${PROJECT_NAME}-${ENVIRONMENT}" \
            --query "Stacks[0].Outputs[?OutputKey=='GlueRoleArn'].OutputValue" \
            --output text \
            --region $AWS_REGION)
        
        DATABASE_NAME=$(aws cloudformation describe-stacks \
            --stack-name "${PROJECT_NAME}-${ENVIRONMENT}" \
            --query "Stacks[0].Outputs[?OutputKey=='GlueDatabaseName'].OutputValue" \
            --output text \
            --region $AWS_REGION)
    else
        cd infrastructure
        BUCKET_NAME=$(terraform output -raw data_lake_bucket_name)
        ROLE_ARN=$(terraform output -raw glue_role_arn)
        DATABASE_NAME=$(terraform output -raw glue_database_name)
        cd ..
    fi
    
    echo "✓ S3 Bucket: $BUCKET_NAME"
    echo "✓ Glue Database: $DATABASE_NAME"
    echo "✓ IAM Role: $ROLE_ARN"
}

# Function to upload Glue scripts
upload_glue_scripts() {
    echo ""
    echo "Uploading Glue ETL scripts to S3..."
    
    aws s3 cp glue-jobs/ s3://${BUCKET_NAME}/scripts/ --recursive --region $AWS_REGION
    
    echo "✓ Glue scripts uploaded to s3://${BUCKET_NAME}/scripts/"
}

# Function to create Glue jobs
create_glue_jobs() {
    echo ""
    echo "Creating Glue ETL jobs..."
    
    # Bronze Ingestion Job
    echo "Creating Bronze Ingestion job..."
    aws glue create-job \
        --name "${PROJECT_NAME}-bronze-ingestion-${ENVIRONMENT}" \
        --role "$ROLE_ARN" \
        --command "Name=glueetl,ScriptLocation=s3://${BUCKET_NAME}/scripts/bronze_ingestion.py,PythonVersion=3" \
        --glue-version "4.0" \
        --worker-type "G.1X" \
        --number-of-workers 10 \
        --default-arguments "{\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\",\"--TABLE_NAME\":\"ALL\",\"--enable-metrics\":\"true\",\"--enable-spark-ui\":\"true\",\"--enable-continuous-cloudwatch-log\":\"true\"}" \
        --region $AWS_REGION \
        2>/dev/null || echo "  Bronze job already exists, skipping..."
    
    # Silver Transformation Job
    echo "Creating Silver Transformation job..."
    aws glue create-job \
        --name "${PROJECT_NAME}-silver-transformation-${ENVIRONMENT}" \
        --role "$ROLE_ARN" \
        --command "Name=glueetl,ScriptLocation=s3://${BUCKET_NAME}/scripts/silver_transformation.py,PythonVersion=3" \
        --glue-version "4.0" \
        --worker-type "G.2X" \
        --number-of-workers 20 \
        --default-arguments "{\"--DATABASE_NAME\":\"${DATABASE_NAME}\",\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\",\"--TABLE_NAME\":\"store_sales\",\"--enable-metrics\":\"true\",\"--enable-spark-ui\":\"true\",\"--enable-continuous-cloudwatch-log\":\"true\"}" \
        --region $AWS_REGION \
        2>/dev/null || echo "  Silver job already exists, skipping..."
    
    # Gold Aggregation Job
    echo "Creating Gold Aggregation job..."
    aws glue create-job \
        --name "${PROJECT_NAME}-gold-aggregation-${ENVIRONMENT}" \
        --role "$ROLE_ARN" \
        --command "Name=glueetl,ScriptLocation=s3://${BUCKET_NAME}/scripts/gold_aggregation.py,PythonVersion=3" \
        --glue-version "4.0" \
        --worker-type "G.2X" \
        --number-of-workers 15 \
        --default-arguments "{\"--DATABASE_NAME\":\"${DATABASE_NAME}\",\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\",\"--enable-metrics\":\"true\",\"--enable-spark-ui\":\"true\",\"--enable-continuous-cloudwatch-log\":\"true\"}" \
        --region $AWS_REGION \
        2>/dev/null || echo "  Gold job already exists, skipping..."
    
    echo "✓ Glue jobs created"
}

# Function to display summary
display_summary() {
    echo ""
    echo "========================================="
    echo "Deployment Complete!"
    echo "========================================="
    echo ""
    echo "Resources Created:"
    echo "  • S3 Bucket: $BUCKET_NAME"
    echo "  • Glue Database: $DATABASE_NAME"
    echo "  • Glue Crawlers: bronze, silver, gold"
    echo "  • Glue Jobs: bronze-ingestion, silver-transformation, gold-aggregation"
    echo "  • Athena Workgroup: ${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
    echo ""
    echo "Next Steps:"
    echo "  1. Run the pipeline: ./scripts/run-pipeline.sh"
    echo "  2. Or execute manually:"
    echo "     aws glue start-job-run --job-name ${PROJECT_NAME}-bronze-ingestion-${ENVIRONMENT}"
    echo "     aws glue start-crawler --name ${PROJECT_NAME}-bronze-crawler-${ENVIRONMENT}"
    echo "  3. Query data in Athena:"
    echo "     Database: $DATABASE_NAME"
    echo "     Workgroup: ${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
    echo ""
    echo "Documentation:"
    echo "  • Architecture: docs/architecture.md"
    echo "  • Usage Guide: docs/usage-guide.md"
    echo "  • Sample Queries: athena-queries/sample-queries.sql"
}

# Main deployment flow
main() {
    echo "Starting deployment..."
    echo ""
    
    check_aws_cli
    
    # Choose deployment method
    echo ""
    echo "Select deployment method:"
    echo "1) CloudFormation (recommended)"
    echo "2) Terraform"
    read -p "Enter choice (1 or 2): " choice
    
    case $choice in
        1)
            DEPLOYMENT_METHOD="cloudformation"
            deploy_cloudformation
            ;;
        2)
            DEPLOYMENT_METHOD="terraform"
            deploy_terraform
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
    
    get_stack_outputs
    upload_glue_scripts
    create_glue_jobs
    display_summary
}

main
