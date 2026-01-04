# Data Engineering Interview Questions - TPC-DS Data Lake Project

## Project Overview Questions

### 1. Architecture & Design (15 minutes)

**Q1.1:** Explain the Medallion architecture implemented in this project. What are the benefits of having Bronze, Silver, and Gold layers?

**Expected Answer:**
- Bronze: Raw data preservation, audit trail, reprocessing capability
- Silver: Data quality, standardization, partitioning for performance
- Gold: Business-ready aggregations, optimized for analytics, reduced query complexity
- Benefits: Data lineage, incremental processing, separation of concerns, cost optimization

**Q1.2:** Why did we choose Parquet format with Snappy compression for this data lake? What are the alternatives and trade-offs?

**Expected Answer:**
- Parquet: Columnar format, excellent compression, predicate pushdown, schema evolution
- Snappy: Fast compression/decompression, good balance between speed and compression ratio
- Alternatives: ORC (better compression), Avro (row-based, better for writes), CSV (human-readable but inefficient)
- Trade-offs: Write performance vs query performance, compression ratio vs CPU usage

**Q1.3:** How would you handle schema evolution in this data lake? What if the source TPC-DS data adds new columns?

**Expected Answer:**
- Parquet supports schema evolution (add columns)
- Glue crawlers can detect schema changes
- Use schema versioning in Glue Catalog
- Implement backward compatibility in ETL jobs
- Consider using schema registry for governance

### 2. AWS Services & Infrastructure (10 minutes)

**Q2.1:** Explain the role of AWS Glue Crawlers in this architecture. When should they run?

**Expected Answer:**
- Auto-discover schema from S3 data
- Create/update Glue Catalog tables
- Detect partitions automatically
- Should run: after ETL jobs complete, on schedule, or event-driven (S3 notifications)
- Cost consideration: don't over-crawl

**Q2.2:** How does Amazon Athena pricing work, and how can you optimize costs?

**Expected Answer:**
- Pricing: $5 per TB of data scanned
- Optimization strategies:
  - Use partitioning to reduce data scanned
  - Use columnar formats (Parquet)
  - Use compression
  - Limit columns in SELECT (avoid SELECT *)
  - Use CTAS for frequently accessed aggregations
  - Set up workgroup limits

**Q2.3:** What IAM permissions are required for the Glue jobs to function properly?

**Expected Answer:**
- S3: GetObject, PutObject on source and target buckets
- Glue: GetTable, UpdateTable, CreateTable on Glue Catalog
- CloudWatch: PutLogEvents for logging
- Least privilege principle
- Use IAM roles, not access keys

### 3. ETL & Data Processing (15 minutes)

**Q3.1:** In the bronze_ingestion.py script, the TPC-DS data is pipe-delimited. How would you handle data quality issues like malformed records?

**Expected Answer:**
- Use badRecordsPath option to capture bad records
- Implement data validation rules
- Add error handling and logging
- Use Spark's PERMISSIVE mode with _corrupt_record column
- Set up monitoring and alerts for data quality issues

**Q3.2:** How would you implement incremental loading instead of full refresh for the Silver layer?

**Expected Answer:**
- Use watermark columns (load_timestamp, modified_date)
- Implement change data capture (CDC) if available
- Use Glue bookmarks to track processed data
- Partition by date and only process new partitions
- Consider using Delta Lake or Apache Hudi for ACID transactions

**Q3.3:** The Gold layer creates aggregations. How would you handle late-arriving data?

**Expected Answer:**
- Implement lookback window (reprocess last N days)
- Use event time vs processing time
- Set up watermarks for late data tolerance
- Consider using streaming for real-time updates
- Document SLA for data freshness

### 4. Performance Optimization (10 minutes)

**Q4.1:** How would you optimize a slow-running Athena query that scans the entire store_sales table?

**Expected Answer:**
- Add partitioning (by date)
- Use WHERE clause on partition columns
- Select only needed columns
- Use CTAS to pre-aggregate frequently accessed data
- Check query execution plan
- Consider bucketing for join optimization

**Q4.2:** What Glue job optimization techniques would you apply to reduce processing time and cost?

**Expected Answer:**
- Right-size DPU allocation (start with 2-10 DPUs)
- Enable job metrics and monitoring
- Use pushdown predicates
- Optimize Spark configurations (executor memory, parallelism)
- Use dynamic partitioning
- Enable Glue job bookmarks for incremental processing
- Consider using Glue 3.0+ for better performance

### 5. Data Quality & Governance (10 minutes)

**Q5.1:** How would you implement data quality checks in the Silver transformation layer?

**Expected Answer:**
- Null value validation for critical columns
- Data type validation
- Range checks (dates, amounts)
- Referential integrity checks (foreign keys)
- Duplicate detection
- Use AWS Glue Data Quality or Great Expectations
- Fail job or quarantine bad data based on severity

**Q5.2:** How would you implement data lineage tracking in this pipeline?

**Expected Answer:**
- Use AWS Glue Data Catalog lineage
- Tag data with metadata (source, load_timestamp, job_id)
- Implement audit tables
- Use Apache Atlas or AWS Lake Formation for governance
- Document transformations in code and metadata

## Hands-On Coding Challenges

### Challenge 1: Write a Silver Transformation (20 minutes)

**Task:** Implement a Silver layer transformation for the `store_sales` table that:
1. Removes duplicate records based on `ss_ticket_number` and `ss_item_sk`
2. Filters out records with null `ss_sold_date_sk`
3. Adds a `load_timestamp` column
4. Partitions by year and month derived from `ss_sold_date_sk`

```python
# Your implementation here
def transform_store_sales_to_silver(glueContext, bronze_table):
    """
    Transform bronze store_sales to silver layer
    """
    # TODO: Implement transformation
    pass
```

**Expected Solution:**
```python
from pyspark.sql.functions import col, current_timestamp, year, month
from awsglue.dynamicframe import DynamicFrame

def transform_store_sales_to_silver(glueContext, bronze_table):
    # Read bronze data
    bronze_df = glueContext.create_dynamic_frame.from_catalog(
        database="tpcds_bronze",
        table_name=bronze_table
    ).toDF()
    
    # Remove duplicates
    silver_df = bronze_df.dropDuplicates(['ss_ticket_number', 'ss_item_sk'])
    
    # Filter null dates
    silver_df = silver_df.filter(col('ss_sold_date_sk').isNotNull())
    
    # Add metadata
    silver_df = silver_df.withColumn('load_timestamp', current_timestamp())
    
    # Add partition columns (assuming date dimension join or date parsing)
    # For simplicity, using year/month from current date
    silver_df = silver_df.withColumn('year', year(current_timestamp()))
    silver_df = silver_df.withColumn('month', month(current_timestamp()))
    
    # Convert back to DynamicFrame
    silver_dynamic_frame = DynamicFrame.fromDF(silver_df, glueContext, "silver_store_sales")
    
    return silver_dynamic_frame
```

### Challenge 2: Write a Gold Aggregation (20 minutes)

**Task:** Create a Gold layer table called `top_selling_products_by_store` that shows:
- Store ID and name
- Product ID and description
- Total revenue
- Total units sold
- Rank within each store (by revenue)
- Only include top 10 products per store

```python
# Your implementation here
def create_top_selling_products_by_store(spark):
    """
    Create gold layer aggregation for top selling products by store
    """
    # TODO: Implement aggregation
    pass
```

**Expected Solution:**
```python
from pyspark.sql.functions import col, sum, count, row_number
from pyspark.sql.window import Window

def create_top_selling_products_by_store(spark):
    # Read silver tables
    store_sales = spark.table("silver_store_sales")
    stores = spark.table("silver_store")
    items = spark.table("silver_item")
    
    # Join and aggregate
    result = store_sales.alias("ss") \
        .join(stores.alias("s"), col("ss.ss_store_sk") == col("s.s_store_sk")) \
        .join(items.alias("i"), col("ss.ss_item_sk") == col("i.i_item_sk")) \
        .groupBy(
            col("s.s_store_sk"),
            col("s.s_store_name"),
            col("i.i_item_sk"),
            col("i.i_item_desc")
        ) \
        .agg(
            sum(col("ss.ss_sales_price")).alias("total_revenue"),
            count("*").alias("units_sold")
        )
    
    # Add ranking
    window_spec = Window.partitionBy("s_store_sk").orderBy(col("total_revenue").desc())
    result = result.withColumn("store_rank", row_number().over(window_spec))
    
    # Filter top 10
    result = result.filter(col("store_rank") <= 10)
    
    return result
```

## TPC-DS Complex Query Challenges

### Challenge 3: Customer Segmentation Query (15 minutes)

**Task:** Write an Athena/SQL query to segment customers into 4 categories based on their purchase behavior:
- **VIP**: Customers with >$10,000 lifetime value and >20 transactions
- **High Value**: Customers with >$5,000 lifetime value
- **Regular**: Customers with >$1,000 lifetime value
- **Occasional**: All other customers

Include: customer_id, total_spent, transaction_count, segment, and average_order_value

```sql
-- Your query here
```

**Expected Solution:**
```sql
WITH customer_metrics AS (
    SELECT 
        c.c_customer_sk,
        c.c_customer_id,
        COALESCE(c.c_first_name || ' ' || c.c_last_name, 'Unknown') as customer_name,
        COUNT(DISTINCT ss.ss_ticket_number) as transaction_count,
        SUM(ss.ss_sales_price) as total_spent,
        AVG(ss.ss_sales_price) as avg_order_value
    FROM silver_customer c
    LEFT JOIN silver_store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
    GROUP BY c.c_customer_sk, c.c_customer_id, c.c_first_name, c.c_last_name
)
SELECT 
    c_customer_id,
    customer_name,
    total_spent,
    transaction_count,
    ROUND(avg_order_value, 2) as avg_order_value,
    CASE 
        WHEN total_spent > 10000 AND transaction_count > 20 THEN 'VIP'
        WHEN total_spent > 5000 THEN 'High Value'
        WHEN total_spent > 1000 THEN 'Regular'
        ELSE 'Occasional'
    END as customer_segment
FROM customer_metrics
WHERE total_spent IS NOT NULL
ORDER BY total_spent DESC;
```

### Challenge 4: Cohort Retention Analysis (20 minutes)

**Task:** Write a query to perform cohort analysis showing monthly retention rates:
- Group customers by their first purchase month (cohort)
- Show how many customers from each cohort made purchases in subsequent months
- Calculate retention percentage for each cohort/month combination

```sql
-- Your query here
```

**Expected Solution:**
```sql
WITH first_purchase AS (
    SELECT 
        ss.ss_customer_sk,
        MIN(d.d_date) as first_purchase_date,
        DATE_TRUNC('month', MIN(d.d_date)) as cohort_month
    FROM silver_store_sales ss
    JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    WHERE d.d_date IS NOT NULL
    GROUP BY ss.ss_customer_sk
),
customer_purchases AS (
    SELECT DISTINCT
        ss.ss_customer_sk,
        DATE_TRUNC('month', d.d_date) as purchase_month
    FROM silver_store_sales ss
    JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    WHERE d.d_date IS NOT NULL
),
cohort_data AS (
    SELECT 
        fp.cohort_month,
        cp.purchase_month,
        COUNT(DISTINCT fp.ss_customer_sk) as customers,
        DATEDIFF(month, fp.cohort_month, cp.purchase_month) as months_since_first
    FROM first_purchase fp
    JOIN customer_purchases cp ON fp.ss_customer_sk = cp.ss_customer_sk
    GROUP BY fp.cohort_month, cp.purchase_month
),
cohort_sizes AS (
    SELECT 
        cohort_month,
        COUNT(DISTINCT ss_customer_sk) as cohort_size
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT 
    cd.cohort_month,
    cd.months_since_first,
    cd.customers,
    cs.cohort_size,
    ROUND(100.0 * cd.customers / cs.cohort_size, 2) as retention_pct
FROM cohort_data cd
JOIN cohort_sizes cs ON cd.cohort_month = cs.cohort_month
WHERE cd.months_since_first <= 12  -- First 12 months
ORDER BY cd.cohort_month, cd.months_since_first;
```

### Challenge 5: Product Affinity Analysis (25 minutes)

**Task:** Write a query to find product pairs that are frequently purchased together:
- Find products bought in the same transaction (same ticket_number)
- Calculate support (% of transactions containing both products)
- Only show pairs with at least 100 co-occurrences
- Rank by frequency

```sql
-- Your query here
```

**Expected Solution:**
```sql
WITH product_pairs AS (
    SELECT 
        ss1.ss_ticket_number,
        ss1.ss_item_sk as product_a,
        ss2.ss_item_sk as product_b
    FROM silver_store_sales ss1
    JOIN silver_store_sales ss2 
        ON ss1.ss_ticket_number = ss2.ss_ticket_number
        AND ss1.ss_item_sk < ss2.ss_item_sk  -- Avoid duplicates and self-pairs
),
pair_counts AS (
    SELECT 
        product_a,
        product_b,
        COUNT(*) as co_occurrence_count
    FROM product_pairs
    GROUP BY product_a, product_b
    HAVING COUNT(*) >= 100
),
total_transactions AS (
    SELECT COUNT(DISTINCT ss_ticket_number) as total_txn
    FROM silver_store_sales
)
SELECT 
    pc.product_a,
    i1.i_item_desc as product_a_desc,
    i1.i_category as product_a_category,
    pc.product_b,
    i2.i_item_desc as product_b_desc,
    i2.i_category as product_b_category,
    pc.co_occurrence_count,
    ROUND(100.0 * pc.co_occurrence_count / tt.total_txn, 4) as support_pct,
    DENSE_RANK() OVER (ORDER BY pc.co_occurrence_count DESC) as affinity_rank
FROM pair_counts pc
CROSS JOIN total_transactions tt
JOIN silver_item i1 ON pc.product_a = i1.i_item_sk
JOIN silver_item i2 ON pc.product_b = i2.i_item_sk
ORDER BY pc.co_occurrence_count DESC
LIMIT 50;
```

### Challenge 6: Time-Series Forecasting Data Prep (20 minutes)

**Task:** Prepare data for time-series forecasting by creating a query that:
- Aggregates daily sales by product category
- Includes 7-day and 30-day moving averages
- Calculates day-over-day and week-over-week growth rates
- Adds seasonality indicators (day of week, month, quarter)

```sql
-- Your query here
```

**Expected Solution:**
```sql
WITH daily_category_sales AS (
    SELECT 
        d.d_date,
        i.i_category,
        SUM(ss.ss_sales_price) as daily_revenue,
        COUNT(DISTINCT ss.ss_ticket_number) as daily_transactions
    FROM silver_store_sales ss
    JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    JOIN silver_item i ON ss.ss_item_sk = i.i_item_sk
    WHERE d.d_date IS NOT NULL
    GROUP BY d.d_date, i.i_category
),
enriched_data AS (
    SELECT 
        d_date,
        i_category,
        daily_revenue,
        daily_transactions,
        -- Moving averages
        AVG(daily_revenue) OVER (
            PARTITION BY i_category 
            ORDER BY d_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) as ma_7day,
        AVG(daily_revenue) OVER (
            PARTITION BY i_category 
            ORDER BY d_date 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) as ma_30day,
        -- Lag values for growth calculation
        LAG(daily_revenue, 1) OVER (
            PARTITION BY i_category ORDER BY d_date
        ) as prev_day_revenue,
        LAG(daily_revenue, 7) OVER (
            PARTITION BY i_category ORDER BY d_date
        ) as prev_week_revenue
    FROM daily_category_sales
)
SELECT 
    d_date,
    i_category,
    daily_revenue,
    daily_transactions,
    ROUND(ma_7day, 2) as moving_avg_7day,
    ROUND(ma_30day, 2) as moving_avg_30day,
    -- Growth rates
    ROUND(100.0 * (daily_revenue - prev_day_revenue) / NULLIF(prev_day_revenue, 0), 2) as dod_growth_pct,
    ROUND(100.0 * (daily_revenue - prev_week_revenue) / NULLIF(prev_week_revenue, 0), 2) as wow_growth_pct,
    -- Seasonality indicators
    EXTRACT(DOW FROM d_date) as day_of_week,
    EXTRACT(MONTH FROM d_date) as month,
    EXTRACT(QUARTER FROM d_date) as quarter,
    CASE WHEN EXTRACT(DOW FROM d_date) IN (0, 6) THEN 1 ELSE 0 END as is_weekend
FROM enriched_data
WHERE d_date >= DATE '2023-01-01'
ORDER BY i_category, d_date;
```

### Challenge 7: Advanced RFM Analysis (20 minutes)

**Task:** Implement RFM (Recency, Frequency, Monetary) analysis:
- Recency: Days since last purchase
- Frequency: Number of purchases in last 12 months
- Monetary: Total spent in last 12 months
- Score each dimension 1-5 (quintiles)
- Create combined RFM score

```sql
-- Your query here
```

**Expected Solution:**
```sql
WITH customer_rfm_metrics AS (
    SELECT 
        c.c_customer_sk,
        c.c_customer_id,
        c.c_first_name || ' ' || c.c_last_name as customer_name,
        -- Recency: days since last purchase
        DATE_DIFF('day', MAX(d.d_date), CURRENT_DATE) as recency_days,
        -- Frequency: number of purchases in last 12 months
        COUNT(DISTINCT ss.ss_ticket_number) as frequency,
        -- Monetary: total spent in last 12 months
        SUM(ss.ss_sales_price) as monetary_value
    FROM silver_customer c
    JOIN silver_store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
    JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    WHERE d.d_date >= DATE_ADD('month', -12, CURRENT_DATE)
    GROUP BY c.c_customer_sk, c.c_customer_id, c.c_first_name, c.c_last_name
),
rfm_scores AS (
    SELECT 
        *,
        -- Recency score (lower is better, so reverse)
        NTILE(5) OVER (ORDER BY recency_days DESC) as r_score,
        -- Frequency score (higher is better)
        NTILE(5) OVER (ORDER BY frequency ASC) as f_score,
        -- Monetary score (higher is better)
        NTILE(5) OVER (ORDER BY monetary_value ASC) as m_score
    FROM customer_rfm_metrics
)
SELECT 
    c_customer_id,
    customer_name,
    recency_days,
    frequency,
    ROUND(monetary_value, 2) as monetary_value,
    r_score,
    f_score,
    m_score,
    CAST(r_score AS VARCHAR) || CAST(f_score AS VARCHAR) || CAST(m_score AS VARCHAR) as rfm_score,
    -- Segment classification
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Regular'
    END as customer_segment
FROM rfm_scores
ORDER BY r_score DESC, f_score DESC, m_score DESC;
```

## System Design Questions

### Challenge 8: Real-Time Analytics Extension (Discussion - 15 minutes)

**Question:** How would you extend this batch-based data lake to support real-time analytics with <5 minute latency?

**Expected Discussion Points:**
- Use Amazon Kinesis Data Streams for real-time ingestion
- Kinesis Data Firehose for S3 delivery
- AWS Glue Streaming ETL or Spark Structured Streaming
- Lambda for lightweight transformations
- Consider Apache Kafka + Flink for complex event processing
- Materialized views or caching layer (ElastiCache, DynamoDB)
- Trade-offs: complexity, cost, consistency

### Challenge 9: Data Lake Security (Discussion - 10 minutes)

**Question:** Design a comprehensive security strategy for this data lake including:
- Access control
- Data encryption
- Audit logging
- PII handling

**Expected Discussion Points:**
- AWS Lake Formation for fine-grained access control
- S3 bucket policies and IAM roles
- Encryption at rest (S3 SSE) and in transit (TLS)
- CloudTrail for audit logging
- Data masking/tokenization for PII
- VPC endpoints for private connectivity
- Compliance requirements (GDPR, CCPA)

### Challenge 10: Cost Optimization Strategy (Discussion - 10 minutes)

**Question:** The data lake is growing to 100TB. How would you optimize costs while maintaining performance?

**Expected Discussion Points:**
- S3 Intelligent-Tiering or lifecycle policies
- Partition pruning and data compaction
- Query result caching in Athena
- Right-size Glue job DPUs
- Use S3 Select for filtering at source
- Implement data retention policies
- Consider Reserved Capacity for predictable workloads
- Monitor and optimize query patterns

## Behavioral & Scenario Questions

### Q11: Production Incident
**Scenario:** The Gold layer aggregation job has been failing for 3 days. How do you troubleshoot and resolve?

**Expected Approach:**
1. Check CloudWatch logs for error messages
2. Verify source data availability and quality
3. Check for schema changes
4. Review resource utilization (memory, DPU)
5. Test with smaller data subset
6. Implement monitoring and alerting
7. Document root cause and prevention

### Q12: Stakeholder Communication
**Scenario:** Business users report that Athena queries are too slow and expensive. How do you address this?

**Expected Approach:**
1. Gather specific query examples and metrics
2. Analyze query patterns and data scanned
3. Propose optimizations (partitioning, CTAS, format)
4. Educate users on best practices
5. Implement query templates or views
6. Set up cost alerts and budgets
7. Regular review and optimization cycles

## Evaluation Rubric

### Technical Skills (40%)
- SQL proficiency and query optimization
- PySpark and ETL development
- AWS services knowledge
- Data modeling and architecture

### Problem Solving (30%)
- Analytical thinking
- Debugging approach
- Trade-off analysis
- Creative solutions

### Communication (20%)
- Clear explanations
- Documentation
- Stakeholder management
- Teaching ability

### Best Practices (10%)
- Code quality
- Security awareness
- Cost consciousness
- Monitoring and observability

---

**Interview Duration:** 90-120 minutes
**Recommended Format:** 
- 30 min: Architecture & AWS questions
- 40 min: Hands-on coding challenges
- 30 min: Complex SQL queries
- 20 min: System design discussion

**Difficulty Levels:**
- Junior: Q1-Q5, Challenge 1, Challenge 3
- Mid-Level: Q1-Q10, Challenges 1-5
- Senior: All questions, focus on Challenges 6-10 and system design
