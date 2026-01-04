-- Business Analytics Queries for TPC-DS Data Lake

-- ============================================
-- CUSTOMER ANALYTICS
-- ============================================

-- Customer Retention Analysis
WITH customer_months AS (
    SELECT 
        c_customer_sk,
        DATE_TRUNC('month', CAST(ss_sold_date_sk AS DATE)) as purchase_month
    FROM silver_store_sales ss
    JOIN silver_customer c ON ss.ss_customer_sk = c.c_customer_sk
    GROUP BY c_customer_sk, DATE_TRUNC('month', CAST(ss_sold_date_sk AS DATE))
),
retention AS (
    SELECT 
        purchase_month,
        COUNT(DISTINCT c_customer_sk) as active_customers,
        COUNT(DISTINCT CASE 
            WHEN LAG(purchase_month) OVER (PARTITION BY c_customer_sk ORDER BY purchase_month) 
                = purchase_month - INTERVAL '1' MONTH 
            THEN c_customer_sk 
        END) as retained_customers
    FROM customer_months
    GROUP BY purchase_month
)
SELECT 
    purchase_month,
    active_customers,
    retained_customers,
    ROUND(100.0 * retained_customers / NULLIF(active_customers, 0), 2) as retention_rate
FROM retention
ORDER BY purchase_month;

-- RFM Analysis (Recency, Frequency, Monetary)
WITH rfm_calc AS (
    SELECT 
        c_customer_sk,
        full_name,
        DATEDIFF(day, MAX(CAST(ss_sold_date_sk AS DATE)), CURRENT_DATE) as recency,
        COUNT(DISTINCT ss_ticket_number) as frequency,
        SUM(ss_sales_price) as monetary
    FROM silver_store_sales ss
    JOIN silver_customer c ON ss.ss_customer_sk = c.c_customer_sk
    GROUP BY c_customer_sk, full_name
),
rfm_scores AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY recency DESC) as r_score,
        NTILE(5) OVER (ORDER BY frequency) as f_score,
        NTILE(5) OVER (ORDER BY monetary) as m_score
    FROM rfm_calc
)
SELECT 
    c_customer_sk,
    full_name,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) as rfm_total,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Regular'
    END as customer_segment
FROM rfm_scores
ORDER BY rfm_total DESC;


-- ============================================
-- PRODUCT ANALYTICS
-- ============================================

-- Product Affinity Analysis (Market Basket)
WITH product_pairs AS (
    SELECT 
        a.ss_ticket_number,
        a.ss_item_sk as item_a,
        b.ss_item_sk as item_b,
        i1.i_item_desc as item_a_desc,
        i2.i_item_desc as item_b_desc
    FROM silver_store_sales a
    JOIN silver_store_sales b ON a.ss_ticket_number = b.ss_ticket_number
    JOIN silver_item i1 ON a.ss_item_sk = i1.i_item_sk
    JOIN silver_item i2 ON b.ss_item_sk = i2.i_item_sk
    WHERE a.ss_item_sk < b.ss_item_sk
)
SELECT 
    item_a_desc,
    item_b_desc,
    COUNT(*) as co_occurrence_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT ss_ticket_number) FROM silver_store_sales), 2) as support_pct
FROM product_pairs
GROUP BY item_a_desc, item_b_desc
HAVING COUNT(*) > 100
ORDER BY co_occurrence_count DESC
LIMIT 50;

-- Product Lifecycle Analysis
SELECT 
    i_item_sk,
    i_item_desc,
    i_category,
    MIN(d_date) as first_sale_date,
    MAX(d_date) as last_sale_date,
    DATEDIFF(day, MIN(d_date), MAX(d_date)) as product_lifetime_days,
    COUNT(DISTINCT ss_ticket_number) as total_transactions,
    SUM(ss_quantity) as total_units_sold,
    SUM(ss_sales_price) as total_revenue,
    CASE 
        WHEN DATEDIFF(day, MAX(d_date), CURRENT_DATE) < 30 THEN 'Active'
        WHEN DATEDIFF(day, MAX(d_date), CURRENT_DATE) < 90 THEN 'Declining'
        ELSE 'Discontinued'
    END as lifecycle_stage
FROM silver_store_sales ss
JOIN silver_item i ON ss.ss_item_sk = i.i_item_sk
JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
GROUP BY i_item_sk, i_item_desc, i_category
ORDER BY total_revenue DESC;


-- ============================================
-- TIME SERIES ANALYTICS
-- ============================================

-- Seasonality Analysis
SELECT 
    d_month,
    d_moy,
    AVG(monthly_revenue) as avg_monthly_revenue,
    STDDEV(monthly_revenue) as revenue_stddev,
    MIN(monthly_revenue) as min_revenue,
    MAX(monthly_revenue) as max_revenue
FROM gold_monthly_trends
GROUP BY d_month, d_moy
ORDER BY d_moy;

-- Day of Week Performance
SELECT 
    d_day_name,
    COUNT(*) as transaction_count,
    SUM(ss_sales_price) as total_sales,
    AVG(ss_sales_price) as avg_transaction_value,
    SUM(ss_quantity) as total_quantity
FROM silver_store_sales ss
JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
GROUP BY d_day_name
ORDER BY 
    CASE d_day_name
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END;

-- Moving Average Analysis
WITH daily_sales AS (
    SELECT 
        d_date,
        SUM(ss_sales_price) as daily_revenue
    FROM silver_store_sales ss
    JOIN silver_date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    GROUP BY d_date
)
SELECT 
    d_date,
    daily_revenue,
    AVG(daily_revenue) OVER (
        ORDER BY d_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as ma_7day,
    AVG(daily_revenue) OVER (
        ORDER BY d_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as ma_30day
FROM daily_sales
ORDER BY d_date DESC
LIMIT 90;


-- ============================================
-- COHORT ANALYTICS
-- ============================================

-- Customer Cohort Revenue Analysis
WITH first_purchase AS (
    SELECT 
        c_customer_sk,
        DATE_TRUNC('month', MIN(CAST(ss_sold_date_sk AS DATE))) as cohort_month
    FROM silver_store_sales ss
    JOIN silver_customer c ON ss.ss_customer_sk = c.c_customer_sk
    GROUP BY c_customer_sk
),
cohort_sales AS (
    SELECT 
        fp.cohort_month,
        DATE_TRUNC('month', CAST(ss.ss_sold_date_sk AS DATE)) as purchase_month,
        COUNT(DISTINCT ss.ss_customer_sk) as customers,
        SUM(ss.ss_sales_price) as revenue
    FROM first_purchase fp
    JOIN silver_store_sales ss ON fp.c_customer_sk = ss.ss_customer_sk
    GROUP BY fp.cohort_month, DATE_TRUNC('month', CAST(ss.ss_sold_date_sk AS DATE))
)
SELECT 
    cohort_month,
    purchase_month,
    DATEDIFF(month, cohort_month, purchase_month) as months_since_first,
    customers,
    revenue,
    ROUND(revenue / customers, 2) as revenue_per_customer
FROM cohort_sales
WHERE cohort_month >= DATE_ADD('month', -12, CURRENT_DATE)
ORDER BY cohort_month, months_since_first;


-- ============================================
-- ADVANCED METRICS
-- ============================================

-- Customer Lifetime Value Prediction
WITH customer_metrics AS (
    SELECT 
        c_customer_sk,
        COUNT(DISTINCT ss_ticket_number) as purchase_frequency,
        AVG(ss_sales_price) as avg_order_value,
        DATEDIFF(day, MIN(CAST(ss_sold_date_sk AS DATE)), MAX(CAST(ss_sold_date_sk AS DATE))) as customer_lifespan_days,
        SUM(ss_sales_price) as total_spent
    FROM silver_store_sales ss
    GROUP BY c_customer_sk
)
SELECT 
    c_customer_sk,
    purchase_frequency,
    avg_order_value,
    customer_lifespan_days,
    total_spent,
    CASE 
        WHEN customer_lifespan_days > 0 
        THEN ROUND((purchase_frequency * avg_order_value * 365.0) / customer_lifespan_days, 2)
        ELSE avg_order_value
    END as predicted_annual_value
FROM customer_metrics
WHERE purchase_frequency > 1
ORDER BY predicted_annual_value DESC
LIMIT 100;
