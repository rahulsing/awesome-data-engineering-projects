"""
Silver Layer: Clean and validate data from Bronze layer
Apply data quality rules, standardization, and partitioning
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *

args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 
    'DATABASE_NAME',
    'TARGET_BUCKET',
    'TABLE_NAME'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

database_name = args['DATABASE_NAME']
target_bucket = args['TARGET_BUCKET']
table_name = args['TABLE_NAME']

def transform_store_sales():
    """Transform store_sales table with data quality checks"""
    # Read from Bronze
    bronze_df = glueContext.create_dynamic_frame.from_catalog(
        database=database_name,
        table_name=f"bronze_{table_name}"
    ).toDF()
    
    # Data quality transformations
    silver_df = bronze_df \
        .filter(col("ss_sold_date_sk").isNotNull()) \
        .filter(col("ss_quantity") > 0) \
        .filter(col("ss_sales_price") >= 0) \
        .withColumn("load_timestamp", current_timestamp()) \
        .withColumn("year", year(to_date(col("ss_sold_date_sk").cast("string"), "yyyyMMdd"))) \
        .withColumn("month", month(to_date(col("ss_sold_date_sk").cast("string"), "yyyyMMdd")))
    
    # Remove duplicates
    silver_df = silver_df.dropDuplicates()
    
    # Write to Silver layer with partitioning
    silver_df.write \
        .mode("overwrite") \
        .partitionBy("year", "month") \
        .parquet(f"{target_bucket}/silver/{table_name}/")
    
    print(f"Transformed {table_name} to Silver layer")

def transform_customer():
    """Transform customer table"""
    bronze_df = glueContext.create_dynamic_frame.from_catalog(
        database=database_name,
        table_name=f"bronze_{table_name}"
    ).toDF()
    
    silver_df = bronze_df \
        .filter(col("c_customer_sk").isNotNull()) \
        .withColumn("load_timestamp", current_timestamp()) \
        .withColumn("full_name", 
                   concat_ws(" ", col("c_first_name"), col("c_last_name"))) \
        .dropDuplicates(["c_customer_sk"])
    
    silver_df.write \
        .mode("overwrite") \
        .parquet(f"{target_bucket}/silver/{table_name}/")
    
    print(f"Transformed {table_name} to Silver layer")

def transform_date_dim():
    """Transform date dimension table"""
    bronze_df = glueContext.create_dynamic_frame.from_catalog(
        database=database_name,
        table_name=f"bronze_{table_name}"
    ).toDF()
    
    silver_df = bronze_df \
        .filter(col("d_date_sk").isNotNull()) \
        .withColumn("load_timestamp", current_timestamp()) \
        .withColumn("is_weekend", 
                   when(col("d_day_name").isin(["Saturday", "Sunday"]), True)
                   .otherwise(False)) \
        .dropDuplicates(["d_date_sk"])
    
    silver_df.write \
        .mode("overwrite") \
        .parquet(f"{target_bucket}/silver/{table_name}/")
    
    print(f"Transformed {table_name} to Silver layer")

# Route to appropriate transformation
transformation_map = {
    'store_sales': transform_store_sales,
    'customer': transform_customer,
    'date_dim': transform_date_dim
}

if table_name in transformation_map:
    transformation_map[table_name]()
else:
    # Generic transformation for other tables
    bronze_df = glueContext.create_dynamic_frame.from_catalog(
        database=database_name,
        table_name=f"bronze_{table_name}"
    ).toDF()
    
    silver_df = bronze_df \
        .withColumn("load_timestamp", current_timestamp()) \
        .dropDuplicates()
    
    silver_df.write \
        .mode("overwrite") \
        .parquet(f"{target_bucket}/silver/{table_name}/")
    
    print(f"Transformed {table_name} to Silver layer (generic)")

job.commit()
