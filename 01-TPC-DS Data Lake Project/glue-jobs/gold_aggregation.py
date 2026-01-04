"""
Gold Layer: Create business-level aggregations and analytics-ready datasets
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'DATABASE_NAME',
    'TARGET_BUCKET'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

database_name = args['DATABASE_NAME']
target_bucket = args['TARGET_BUCKET']

# Read Silver layer tables
store_sales = glueContext.create_dynamic_frame.from_catalog(
    database=database_name,
    table_name="silver_store_sales"
).toDF()

customer = glueContext.create_dynamic_frame.from_catalog(
    database=database_name,
    table_name="silver_customer"
).toDF()

date_dim = glueContext.create_dynamic_frame.from_catalog(
    database=database_name,
    table_name="silver_date_dim"
).toDF()

item = glueContext.create_dynamic_frame.from_catalog(
    database=database_name,
    table_name="silver_item"
).toDF()

# Gold Table 1: Daily Sales Summary
daily_sales = store_sales \
    .join(date_dim, store_sales.ss_sold_date_sk == date_dim.d_date_sk) \
    .groupBy("d_date", "d_year", "d_month", "d_day_name") \
    .agg(
        sum("ss_sales_price").alias("total_sales"),
        sum("ss_quantity").alias("total_quantity"),
        count("ss_ticket_number").alias("transaction_count"),
        avg("ss_sales_price").alias("avg_sale_price"),
        countDistinct("ss_customer_sk").alias("unique_customers")
    ) \
    .withColumn("load_timestamp", current_timestamp())

daily_sales.write \
    .mode("overwrite") \
    .partitionBy("d_year", "d_month") \
    .parquet(f"{target_bucket}/gold/daily_sales_summary/")

print("Created gold table: daily_sales_summary")

# Gold Table 2: Customer Lifetime Value
customer_ltv = store_sales \
    .join(customer, store_sales.ss_customer_sk == customer.c_customer_sk) \
    .groupBy(
        "c_customer_sk",
        "c_customer_id",
        "full_name",
        "c_email_address",
        "c_birth_country"
    ) \
    .agg(
        sum("ss_sales_price").alias("lifetime_value"),
        count("ss_ticket_number").alias("total_transactions"),
        avg("ss_sales_price").alias("avg_transaction_value"),
        min("ss_sold_date_sk").alias("first_purchase_date"),
        max("ss_sold_date_sk").alias("last_purchase_date")
    ) \
    .withColumn("load_timestamp", current_timestamp()) \
    .withColumn("customer_segment",
               when(col("lifetime_value") > 10000, "Premium")
               .when(col("lifetime_value") > 5000, "Gold")
               .when(col("lifetime_value") > 1000, "Silver")
               .otherwise("Bronze"))

customer_ltv.write \
    .mode("overwrite") \
    .parquet(f"{target_bucket}/gold/customer_lifetime_value/")

print("Created gold table: customer_lifetime_value")

# Gold Table 3: Product Performance
product_performance = store_sales \
    .join(item, store_sales.ss_item_sk == item.i_item_sk) \
    .join(date_dim, store_sales.ss_sold_date_sk == date_dim.d_date_sk) \
    .groupBy(
        "i_item_sk",
        "i_item_id",
        "i_item_desc",
        "i_category",
        "i_brand",
        "d_year"
    ) \
    .agg(
        sum("ss_sales_price").alias("total_revenue"),
        sum("ss_quantity").alias("units_sold"),
        count("ss_ticket_number").alias("transaction_count"),
        avg("ss_sales_price").alias("avg_price")
    ) \
    .withColumn("load_timestamp", current_timestamp())

# Add ranking within category
window_spec = Window.partitionBy("i_category", "d_year").orderBy(desc("total_revenue"))
product_performance = product_performance \
    .withColumn("category_rank", rank().over(window_spec))

product_performance.write \
    .mode("overwrite") \
    .partitionBy("d_year", "i_category") \
    .parquet(f"{target_bucket}/gold/product_performance/")

print("Created gold table: product_performance")

# Gold Table 4: Monthly Trends
monthly_trends = store_sales \
    .join(date_dim, store_sales.ss_sold_date_sk == date_dim.d_date_sk) \
    .groupBy("d_year", "d_month", "d_moy") \
    .agg(
        sum("ss_sales_price").alias("monthly_revenue"),
        sum("ss_quantity").alias("monthly_quantity"),
        count("ss_ticket_number").alias("monthly_transactions"),
        countDistinct("ss_customer_sk").alias("unique_customers"),
        avg("ss_sales_price").alias("avg_transaction_value")
    ) \
    .withColumn("load_timestamp", current_timestamp()) \
    .orderBy("d_year", "d_month")

# Calculate month-over-month growth
window_spec = Window.orderBy("d_year", "d_month")
monthly_trends = monthly_trends \
    .withColumn("prev_month_revenue", lag("monthly_revenue").over(window_spec)) \
    .withColumn("revenue_growth_pct",
               ((col("monthly_revenue") - col("prev_month_revenue")) / col("prev_month_revenue") * 100))

monthly_trends.write \
    .mode("overwrite") \
    .partitionBy("d_year") \
    .parquet(f"{target_bucket}/gold/monthly_trends/")

print("Created gold table: monthly_trends")

job.commit()
