-- Sample Athena Queries for TPC-DS Data Lake

-- ============================================
-- BRONZE LAYER QUERIES (Raw Data Exploration)
-- ============================================

-- Check row counts in bronze tables
SELECT COUNT(*) as row_count 
FROM bronze_store_sales;

-- Sample bronze data
SELECT * 
FROM bronze_customer 
LIMIT 10;


-- ============================================
-- SILVER LAYER QUERIES (Cleaned Data)
-- ============================================

-- Sales by year and month
SELECT 
    year,
    month,
    COUNT(*) as transaction_count,
    SUM(ss_sales_price) as total_sales,
    AVG(ss_sales_price) as avg_sale_price
FROM silver_store_sales
GROUP BY year, month
ORDER BY year, month;

-- Customer demographics
SELECT 
    c_birth_country,
    COUNT(*) as customer_count,
    AVG(c_birth_year) as avg_birth_year
FROM silver_customer
WHERE c_birth_country IS NOT NULL
GROUP BY c_birth_country
ORDER BY customer_count DESC
LIMIT 20;

-- Weekend vs Weekday sales
SELECT 
    d.is_weekend,
    COUNT(*) as transaction_count,
    SUM(ss.ss_sales_price) as total_sales,
    AVG(ss.ss_sales_price) as avg_sale
FROM silver_store_sales ss
JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
GROUP BY d.is_weekend;


-- ============================================
-- GOLD LAYER QUERIES (Business Analytics)
-- ============================================

-- Daily sales trends
SELECT 
    d_date,
    d_day_name,
    total_sales,
    transaction_count,
    unique_customers,
    avg_sale_price
FROM gold_daily_sales_summary
WHERE d_year = 2023
ORDER BY d_date DESC
LIMIT 30;

-- Top 10 customers by lifetime value
SELECT 
    c_customer_id,
    full_name,
    customer_segment,
    lifetime_value,
    total_transactions,
    avg_transaction_value
FROM gold_customer_lifetime_value
ORDER BY lifetime_value DESC
LIMIT 10;

-- Customer segmentation distribution
SELECT 
    customer_segment,
    COUNT(*) as customer_count,
    SUM(lifetime_value) as total_value,
    AVG(lifetime_value) as avg_value,
    AVG(total_transactions) as avg_transactions
FROM gold_customer_lifetime_value
GROUP BY customer_segment
ORDER BY total_value DESC;

-- Top performing products by category
SELECT 
    i_category,
    i_brand,
    i_item_desc,
    total_revenue,
    units_sold,
    category_rank
FROM gold_product_performance
WHERE d_year = 2023 
  AND category_rank <= 5
ORDER BY i_category, category_rank;

-- Monthly revenue trends with growth
SELECT 
    d_year,
    d_month,
    monthly_revenue,
    monthly_transactions,
    unique_customers,
    ROUND(revenue_growth_pct, 2) as revenue_growth_pct
FROM gold_monthly_trends
WHERE d_year >= 2022
ORDER BY d_year, d_month;

-- Year-over-year comparison
SELECT 
    d_month,
    SUM(CASE WHEN d_year = 2022 THEN monthly_revenue ELSE 0 END) as revenue_2022,
    SUM(CASE WHEN d_year = 2023 THEN monthly_revenue ELSE 0 END) as revenue_2023,
    ROUND(
        (SUM(CASE WHEN d_year = 2023 THEN monthly_revenue ELSE 0 END) - 
         SUM(CASE WHEN d_year = 2022 THEN monthly_revenue ELSE 0 END)) / 
        NULLIF(SUM(CASE WHEN d_year = 2022 THEN monthly_revenue ELSE 0 END), 0) * 100,
        2
    ) as yoy_growth_pct
FROM gold_monthly_trends
WHERE d_year IN (2022, 2023)
GROUP BY d_month
ORDER BY d_month;


-- ============================================
-- ADVANCED ANALYTICS
-- ============================================

-- Customer cohort analysis
WITH first_purchase AS (
    SELECT 
        c_customer_sk,
        DATE_TRUNC('month', CAST(first_purchase_date AS DATE)) as cohort_month
    FROM gold_customer_lifetime_value
)
SELECT 
    cohort_month,
    COUNT(*) as cohort_size,
    AVG(ltv.lifetime_value) as avg_ltv,
    SUM(ltv.lifetime_value) as total_ltv
FROM first_purchase fp
JOIN gold_customer_lifetime_value ltv ON fp.c_customer_sk = ltv.c_customer_sk
GROUP BY cohort_month
ORDER BY cohort_month;

-- Product category performance comparison
SELECT 
    i_category,
    SUM(total_revenue) as category_revenue,
    SUM(units_sold) as category_units,
    COUNT(DISTINCT i_item_sk) as product_count,
    AVG(avg_price) as avg_product_price
FROM gold_product_performance
WHERE d_year = 2023
GROUP BY i_category
ORDER BY category_revenue DESC;
