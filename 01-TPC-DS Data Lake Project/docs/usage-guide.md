# Usage Guide

## Querying Data with Athena

### Connect to Athena

1. **AWS Console**: Navigate to Athena service
2. **AWS CLI**: Use `aws athena` commands
3. **JDBC/ODBC**: Connect from BI tools

### Sample Queries

See `athena-queries/sample-queries.sql` for comprehensive examples.

#### Quick Start Queries

```sql
-- Check available tables
SHOW TABLES IN tpcds_datalake_dev;

-- View table schema
DESCRIBE gold_daily_sales_summary;

-- Simple aggregation
SELECT 
    d_year,
    SUM(total_sales) as yearly_sales
FROM gold_daily_sales_summary
GROUP BY d_year
ORDER BY d_year;
```

## Running ETL Jobs

### Manual Execution

```bash
# Run specific table ingestion
aws glue start-job-run \
  --job-name tpcds-bronze-ingestion-dev \
  --arguments '{"--TABLE_NAME":"store_sales"}'

# Run transformation for specific table
aws glue start-job-run \
  --job-name tpcds-silver-transformation-dev \
  --arguments '{"--TABLE_NAME":"store_sales"}'
```

### Scheduled Execution

Create Glue Triggers for automated runs:

```bash
# Daily trigger for bronze ingestion
aws glue create-trigger \
  --name daily-bronze-ingestion \
  --type SCHEDULED \
  --schedule "cron(0 2 * * ? *)" \
  --actions JobName=tpcds-bronze-ingestion-dev \
  --start-on-creation
```

## Monitoring

### CloudWatch Metrics

Monitor Glue jobs:
- Job run duration
- DPU hours consumed
- Success/failure rates

Monitor Athena:
- Query execution time
- Data scanned
- Query count

### CloudWatch Logs

View logs:
```bash
# Glue job logs
aws logs tail /aws-glue/jobs/output --follow

# Glue crawler logs
aws logs tail /aws-glue/crawlers --follow
```

## Data Refresh Strategy

### Full Refresh
- Drop and recreate all layers
- Use for major schema changes

### Incremental Refresh
- Process only new/changed data
- Partition-based updates
- Merge with existing data

### Example: Incremental Load

```python
# In silver_transformation.py
silver_df.write \
    .mode("append") \
    .partitionBy("year", "month") \
    .parquet(f"{target_bucket}/silver/{table_name}/")
```

## Performance Optimization

### Query Optimization

1. **Use Partitioning**:
```sql
SELECT * FROM gold_daily_sales_summary
WHERE d_year = 2023 AND d_month = 12;
```

2. **Limit Columns**:
```sql
SELECT d_date, total_sales 
FROM gold_daily_sales_summary
LIMIT 100;
```

3. **Use CTAS for Complex Queries**:
```sql
CREATE TABLE temp_results AS
SELECT ... FROM gold_daily_sales_summary
WHERE ...;
```

### ETL Optimization

1. **Adjust Worker Count**: Scale based on data volume
2. **Use Appropriate Worker Type**: G.1X, G.2X, G.4X, G.8X
3. **Enable Job Bookmarks**: Track processed data
4. **Optimize Partitioning**: Balance partition size

## Cost Management

### Monitor Costs

- S3 storage costs
- Glue DPU hours
- Athena data scanned
- Data transfer costs

### Cost Optimization Tips

1. **Compress Data**: Use Parquet with Snappy
2. **Partition Wisely**: Reduce data scanned
3. **Lifecycle Policies**: Move old data to Glacier
4. **Query Optimization**: Limit columns and rows
5. **Use Workgroups**: Set query limits

## Integration with BI Tools

### Tableau
1. Install Athena JDBC driver
2. Connect using JDBC URL
3. Use Glue catalog as data source

### Power BI
1. Use Amazon Athena connector
2. Configure workgroup and database
3. Import or DirectQuery mode

### QuickSight
1. Native Athena integration
2. Create datasets from Glue tables
3. Build dashboards and visualizations

## Troubleshooting

### Common Issues

**Query Timeout**:
- Optimize query with partitions
- Increase workgroup timeout
- Break into smaller queries

**Out of Memory**:
- Increase Glue worker size
- Reduce data processed per partition
- Optimize transformations

**Schema Mismatch**:
- Run crawler to update schema
- Check data format consistency
- Verify partition structure

**Access Denied**:
- Check IAM permissions
- Verify S3 bucket policies
- Review Glue role permissions
