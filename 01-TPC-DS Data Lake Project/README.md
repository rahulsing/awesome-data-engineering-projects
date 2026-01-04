# TPC-DS Data Lake Project

A production-ready data lake implementation using the Medallion architecture (Bronze, Silver, Gold) with AWS services to process and analyze TPC-DS benchmark data.

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

```bash
chmod +x scripts/run-pipeline.sh
./scripts/run-pipeline.sh
```

This will execute:
1. Bronze ingestion → Bronze crawler
2. Silver transformation → Silver crawler
3. Gold aggregation → Gold crawler

### 3. Query Data with Athena

```sql
-- View available tables
SHOW TABLES IN tpcds_datalake_dev;

-- Query gold layer
SELECT 
    d_year,
    d_month,
    SUM(total_sales) as monthly_revenue
FROM gold_daily_sales_summary
GROUP BY d_year, d_month
ORDER BY d_year, d_month;
```

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

### Logs
- Glue job logs: `/aws-glue/jobs/output`
- Crawler logs: `/aws-glue/crawlers`

## Cleanup

```bash
# CloudFormation
aws cloudformation delete-stack --stack-name tpcds-datalake-dev

# Terraform
cd infrastructure && terraform destroy
```

## Technologies

- **AWS S3** - Data lake storage
- **AWS Glue** - ETL and data catalog
- **Amazon Athena** - Serverless SQL queries
- **Apache Spark** - Distributed data processing
- **Parquet** - Columnar storage format

## License

This project is provided as-is for educational and demonstration purposes.
