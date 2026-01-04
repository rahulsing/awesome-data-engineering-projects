# TPC-DS Data Lake Project

A production-ready data lake implementation using the Medallion architecture (Bronze, Silver, Gold) with AWS services to process and analyze TPC-DS benchmark data.

> **⚠️ COST NOTICE**: Running this project in your AWS account will incur costs (S3 storage, Glue jobs, Athena queries). Estimated costs: $200+ depending on data volume and usage. If you want to understand the project without incurring costs, review the comprehensive documentation in the `docs/` folder which covers architecture, deployment steps, and usage examples.

## Architecture Overview

- **Bronze Layer**: Raw data ingestion from TPC-DS dataset
- **Silver Layer**: Cleaned, validated, and partitioned data
- **Gold Layer**: Business-level aggregations and analytics-ready datasets
- **Services**: S3 for storage, Glue for ETL, Athena for querying

## Source Data

Public TPC-DS dataset: `s3://redshift-downloads/TPC-DS/2.13/3TB/`

Contains 24 tables including store_sales, customer, item, date_dim, and more.

## Project Structure

```
├── infrastructure/          # CloudFormation/Terraform for AWS resources
│   ├── cloudformation-stack.yaml
│   ├── terraform-main.tf
│   ├── terraform-variables.tf
│   └── terraform-outputs.tf
├── glue-jobs/              # ETL scripts for data transformation
│   ├── bronze_ingestion.py
│   ├── silver_transformation.py
│   └── gold_aggregation.py
├── athena-queries/         # Sample analytical queries
│   ├── sample-queries.sql
│   └── business-analytics.sql
├── scripts/                # Deployment and execution scripts
│   ├── deploy.sh
│   └── run-pipeline.sh
├── config/                 # Configuration files
│   ├── glue-job-config.json
│   └── crawler-config.json
└── docs/                   # Documentation
    ├── architecture.md
    ├── deployment-guide.md
    └── usage-guide.md
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         SOURCE DATA                              │
│              s3://redshift-downloads/TPC-DS/2.13/3TB/           │
│                    (24 TPC-DS Tables)                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BRONZE LAYER (Raw Data)                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Job: bronze_ingestion.py                           │  │
│  │  • Read pipe-delimited files from source                 │  │
│  │  • Convert to Parquet with Snappy compression            │  │
│  │  • Minimal transformation (format conversion only)       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│              s3://bucket/bronze/{table_name}/                   │
│                   (Parquet format)                              │
│                             │                                    │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Crawler: bronze-crawler                            │  │
│  │  • Auto-discover schema                                  │  │
│  │  • Create/update Glue Catalog tables                     │  │
│  │  • Table prefix: bronze_                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  SILVER LAYER (Cleaned Data)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Job: silver_transformation.py                      │  │
│  │  • Data quality checks (null handling, validation)       │  │
│  │  • Remove duplicates                                     │  │
│  │  • Standardize formats and naming                        │  │
│  │  • Add metadata columns (load_timestamp)                 │  │
│  │  • Partition by date dimensions (year, month)            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│         s3://bucket/silver/{table_name}/year=/month=/           │
│              (Partitioned Parquet format)                       │
│                             │                                    │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Crawler: silver-crawler                            │  │
│  │  • Discover partitioned schema                           │  │
│  │  • Update Glue Catalog                                   │  │
│  │  • Table prefix: silver_                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              GOLD LAYER (Business Analytics)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Job: gold_aggregation.py                           │  │
│  │  • Join multiple silver tables                           │  │
│  │  • Create business metrics and KPIs                      │  │
│  │  • Calculate aggregations and rankings                   │  │
│  │  • Generate analytics-ready datasets                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Gold Tables:                                            │   │
│  │  • daily_sales_summary - Daily sales metrics            │   │
│  │  • customer_lifetime_value - Customer segmentation      │   │
│  │  • product_performance - Product analytics & rankings   │   │
│  │  • monthly_trends - Time-series with growth metrics     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                    │
│                             ▼                                    │
│         s3://bucket/gold/{table_name}/year=/month=/             │
│              (Optimized Parquet format)                         │
│                             │                                    │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Glue Crawler: gold-crawler                              │  │
│  │  • Catalog business tables                               │  │
│  │  • Table prefix: gold_                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    QUERY & ANALYTICS LAYER                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Amazon Athena                                           │  │
│  │  • Serverless SQL queries                                │  │
│  │  • Query all layers (Bronze, Silver, Gold)              │  │
│  │  • Connect to BI tools (Tableau, Power BI, QuickSight)  │  │
│  │  • Ad-hoc analysis and reporting                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Sample Queries Available:                                      │
│  • Daily/Monthly sales trends                                   │
│  • Customer segmentation & RFM analysis                         │
│  • Product performance & affinity                               │
│  • Cohort analysis & retention                                  │
│  • Year-over-year comparisons                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Deploy Infrastructure

**Option A: CloudFormation**
```bash
aws cloudformation deploy \
  --template-file infrastructure/cloudformation-stack.yaml \
  --stack-name tpcds-datalake-dev \
  --parameter-overrides ProjectName=tpcds-datalake Environment=dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

**Option B: Terraform**
```bash
cd infrastructure
terraform init
terraform apply -var="project_name=tpcds-datalake" -var="environment=dev"
```

**Option C: Automated Script**
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

### 2. Run ETL Pipeline

**Option A: Automated Script**
```bash
chmod +x scripts/run-pipeline.sh
./scripts/run-pipeline.sh
```

**Option B: Manual Execution**

Start Bronze ingestion:
```bash
aws glue start-job-run \
  --job-name tpcds-datalake-bronze-ingestion-dev \
  --region us-east-1
```

Monitor job progress:
```bash
aws glue get-job-runs \
  --job-name tpcds-datalake-bronze-ingestion-dev \
  --region us-east-1
```

Run crawlers and subsequent jobs:
```bash
# Catalog Bronze data
aws glue start-crawler \
  --name tpcds-datalake-bronze-crawler-dev \
  --region us-east-1

# Wait for crawler to complete, then run Silver transformation
aws glue start-job-run \
  --job-name tpcds-datalake-silver-transformation-dev \
  --region us-east-1

# Catalog Silver data
aws glue start-crawler \
  --name tpcds-datalake-silver-crawler-dev \
  --region us-east-1

# Run Gold aggregation
aws glue start-job-run \
  --job-name tpcds-datalake-gold-aggregation-dev \
  --region us-east-1

# Catalog Gold data
aws glue start-crawler \
  --name tpcds-datalake-gold-crawler-dev \
  --region us-east-1
```

This will execute:
1. Bronze ingestion → Bronze crawler
2. Silver transformation → Silver crawler
3. Gold aggregation → Gold crawler

### 3. Query Data with Athena

Once crawlers complete, query your data:

```sql
-- Check available tables
SHOW TABLES IN tpcds_datalake_dev;

-- Query Bronze layer
SELECT COUNT(*) FROM bronze_store_sales;

-- Query Silver layer
SELECT 
    year,
    month,
    COUNT(*) as transaction_count,
    SUM(ss_sales_price) as total_sales
FROM silver_store_sales
GROUP BY year, month
ORDER BY year, month;

-- Query Gold layer
SELECT 
    d_date,
    total_sales,
    transaction_count,
    unique_customers
FROM gold_daily_sales_summary
ORDER BY d_date DESC
LIMIT 30;
```

### 4. Access AWS Console

- **S3 Bucket**: https://s3.console.aws.amazon.com/s3/buckets/
- **Glue Database**: https://console.aws.amazon.com/glue/home?region=us-east-1#/v2/data-catalog/databases
- **Glue Jobs**: https://console.aws.amazon.com/glue/home?region=us-east-1#/v2/etl-jobs
- **Athena Console**: https://console.aws.amazon.com/athena/home?region=us-east-1

## Key Features

### Medallion Architecture
- **Bronze**: Raw data preservation with minimal transformation
- **Silver**: Cleaned, validated, and partitioned for reliability
- **Gold**: Business-ready aggregations for fast analytics

### Data Quality
- Null value handling and validation
- Duplicate removal
- Data type standardization
- Referential integrity checks

### Performance Optimization
- Parquet format with Snappy compression
- Partitioning by date dimensions
- Predicate pushdown support
- Optimized for Athena queries

### Cost Optimization
- S3 lifecycle policies
- Efficient data formats
- Query result caching
- Workgroup limits

## Documentation

- **[Architecture Guide](docs/architecture.md)** - Detailed architecture and design decisions
- **[Deployment Guide](docs/deployment-guide.md)** - Step-by-step deployment instructions
- **[Deployment Success](docs/DEPLOYMENT-SUCCESS.md)** - Deployment verification and validation checklist
- **[Usage Guide](docs/usage-guide.md)** - Query examples and best practices
- **[Interview Questions](docs/INTERVIEW-QUESTIONS.md)** - Comprehensive interview question set with TPC-DS query challenges

## Monitoring & Maintenance

### CloudWatch Metrics
- Glue job execution time and DPU usage
- Athena query performance and data scanned
- S3 storage metrics

### CloudWatch Logs
- Glue job logs: `/aws-glue/jobs/output`
- Crawler logs: `/aws-glue/crawlers`

### Cost Considerations

**Estimated Monthly Costs** (based on moderate usage):
- S3 Storage: ~$23/TB/month
- Glue ETL: ~$0.44/DPU-hour
- Athena Queries: ~$5/TB scanned
- Glue Crawlers: ~$0.44/DPU-hour

**Cost Optimization Tips**:
1. Use partitioning to reduce data scanned
2. Compress data with Parquet format
3. Set up S3 lifecycle policies
4. Use Athena workgroup limits
5. Monitor Glue job metrics and right-size DPUs

## Cleanup

To avoid ongoing costs, delete resources when done:

**CloudFormation:**
```bash
# Empty S3 bucket first
aws s3 rm s3://tpcds-datalake-dev-<account-id> --recursive

# Delete stack
aws cloudformation delete-stack --stack-name tpcds-datalake-dev --region us-east-1
```

**Terraform:**
```bash
cd infrastructure
terraform destroy -var="project_name=tpcds-datalake" -var="environment=dev"
```

**Manual Cleanup (if needed):**
```bash
# Delete Glue jobs
aws glue delete-job --job-name tpcds-datalake-bronze-ingestion-dev
aws glue delete-job --job-name tpcds-datalake-silver-transformation-dev
aws glue delete-job --job-name tpcds-datalake-gold-aggregation-dev

# Delete crawlers
aws glue delete-crawler --name tpcds-datalake-bronze-crawler-dev
aws glue delete-crawler --name tpcds-datalake-silver-crawler-dev
aws glue delete-crawler --name tpcds-datalake-gold-crawler-dev
```

## Technologies

- **AWS S3** - Data lake storage
- **AWS Glue** - ETL and data catalog
- **Amazon Athena** - Serverless SQL queries
- **Apache Spark** - Distributed data processing
- **Parquet** - Columnar storage format

## License

This project is provided as-is for educational and demonstration purposes.
