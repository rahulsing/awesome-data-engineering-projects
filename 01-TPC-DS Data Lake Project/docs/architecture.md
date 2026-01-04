# Data Lake Architecture

## Overview

This project implements a Medallion architecture data lake using AWS services to process TPC-DS benchmark data.

## Architecture Layers

### Bronze Layer (Raw Data)
- **Purpose**: Store raw data as-is from source
- **Location**: `s3://bucket/bronze/`
- **Format**: Parquet with Snappy compression
- **Source**: TPC-DS dataset from `s3://redshift-downloads/TPC-DS/2.13/3TB/`
- **Processing**: Minimal transformation, just format conversion
- **Tables**: All 24 TPC-DS tables

### Silver Layer (Cleaned Data)
- **Purpose**: Cleaned, validated, and standardized data
- **Location**: `s3://bucket/silver/`
- **Format**: Parquet with partitioning
- **Transformations**:
  - Data quality checks (null handling, value validation)
  - Deduplication
  - Standardization (naming, formats)
  - Partitioning by date dimensions
  - Add metadata columns (load_timestamp)

### Gold Layer (Business Metrics)
- **Purpose**: Aggregated, business-ready analytics tables
- **Location**: `s3://bucket/gold/`
- **Format**: Parquet optimized for queries
- **Tables**:
  - `daily_sales_summary`: Daily sales metrics
  - `customer_lifetime_value`: Customer segmentation and LTV
  - `product_performance`: Product analytics with rankings
  - `monthly_trends`: Time-series analysis with growth metrics

## AWS Services

### S3 (Storage)
- Centralized data lake storage
- Lifecycle policies for cost optimization
- Encryption at rest (AES-256)
- Versioning enabled

### Glue (ETL & Catalog)
- **Glue Crawlers**: Automatic schema discovery
- **Glue Jobs**: PySpark ETL transformations
- **Glue Data Catalog**: Centralized metadata repository

### Athena (Query Engine)
- Serverless SQL queries
- Presto-based engine
- Direct S3 data access
- Workgroup for cost control

## Data Flow

```
Source (TPC-DS)
    ↓
Bronze Ingestion (Glue Job)
    ↓
Bronze Layer (S3)
    ↓
Bronze Crawler (Glue)
    ↓
Silver Transformation (Glue Job)
    ↓
Silver Layer (S3)
    ↓
Silver Crawler (Glue)
    ↓
Gold Aggregation (Glue Job)
    ↓
Gold Layer (S3)
    ↓
Gold Crawler (Glue)
    ↓
Athena Queries
```

## Security

- S3 bucket encryption enabled
- IAM roles with least privilege
- VPC endpoints for private connectivity (optional)
- CloudTrail logging for audit
- Public access blocked on S3

## Cost Optimization

- Parquet format for compression
- Partitioning for query pruning
- S3 lifecycle policies
- Glue job auto-scaling
- Athena query result caching
