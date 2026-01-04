#!/bin/bash

# Pipeline execution script for TPC-DS Data Lake

set -e

echo "========================================="
echo "TPC-DS Data Lake Pipeline Execution"
echo "========================================="

# Load deployment configuration
if [ ! -f config/deployment-info.json ]; then
    echo "Error: config/deployment-info.json not found"
    echo "Please run ./scripts/deploy-glue-resources.sh first"
    exit 1
fi

BUCKET_NAME=$(cat config/deployment-info.json | grep -o '"bucket_name": "[^"]*' | cut -d'"' -f4)
DATABASE_NAME=$(cat config/deployment-info.json | grep -o '"database_name": "[^"]*' | cut -d'"' -f4)
AWS_REGION=$(cat config/deployment-info.json | grep -o '"region": "[^"]*' | cut -d'"' -f4)
PROJECT_NAME=$(cat config/deployment-info.json | grep -o '"project_name": "[^"]*' | cut -d'"' -f4)
ENVIRONMENT=$(cat config/deployment-info.json | grep -o '"environment": "[^"]*' | cut -d'"' -f4)

echo "Bucket: $BUCKET_NAME"
echo "Database: $DATABASE_NAME"
echo "Region: $AWS_REGION"
echo ""

# Step 1: Run Bronze Ingestion
echo "Step 1: Running Bronze Ingestion Job..."
aws glue start-job-run \
    --job-name "${PROJECT_NAME}-bronze-ingestion-${ENVIRONMENT}" \
    --arguments "{\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\",\"--TABLE_NAME\":\"store_sales\"}" \
    --region $AWS_REGION

echo "✓ Bronze ingestion job started"
echo "Waiting for job to complete (this may take several minutes)..."
sleep 300

# Step 2: Run Bronze Crawler
echo ""
echo "Step 2: Running Bronze Crawler..."
aws glue start-crawler \
    --name "${PROJECT_NAME}-bronze-crawler-${ENVIRONMENT}" \
    --region $AWS_REGION

echo "✓ Bronze crawler started"
sleep 120

# Step 3: Run Silver Transformation
echo ""
echo "Step 3: Running Silver Transformation Job..."
aws glue start-job-run \
    --job-name "${PROJECT_NAME}-silver-transformation-${ENVIRONMENT}" \
    --arguments "{\"--DATABASE_NAME\":\"${DATABASE_NAME}\",\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\",\"--TABLE_NAME\":\"store_sales\"}" \
    --region $AWS_REGION

echo "✓ Silver transformation job started"
sleep 300

# Step 4: Run Silver Crawler
echo ""
echo "Step 4: Running Silver Crawler..."
aws glue start-crawler \
    --name "${PROJECT_NAME}-silver-crawler-${ENVIRONMENT}" \
    --region $AWS_REGION

echo "✓ Silver crawler started"
sleep 120

# Step 5: Run Gold Aggregation
echo ""
echo "Step 5: Running Gold Aggregation Job..."
aws glue start-job-run \
    --job-name "${PROJECT_NAME}-gold-aggregation-${ENVIRONMENT}" \
    --arguments "{\"--DATABASE_NAME\":\"${DATABASE_NAME}\",\"--TARGET_BUCKET\":\"s3://${BUCKET_NAME}\"}" \
    --region $AWS_REGION

echo "✓ Gold aggregation job started"
sleep 300

# Step 6: Run Gold Crawler
echo ""
echo "Step 6: Running Gold Crawler..."
aws glue start-crawler \
    --name "${PROJECT_NAME}-gold-crawler-${ENVIRONMENT}" \
    --region $AWS_REGION

echo "✓ Gold crawler started"

echo ""
echo "========================================="
echo "Pipeline Execution Complete!"
echo "========================================="
echo ""
echo "You can now query the data using Athena:"
echo "Database: $DATABASE_NAME"
echo "Workgroup: ${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
