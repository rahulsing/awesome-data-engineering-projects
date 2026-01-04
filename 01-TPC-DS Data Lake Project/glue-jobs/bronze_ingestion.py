"""
Bronze Layer: Ingest raw TPC-DS data from public S3 bucket
Copies data as-is with minimal transformation
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'TARGET_BUCKET', 'TABLE_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Source configuration
source_bucket = "s3://redshift-downloads/TPC-DS/2.13/3TB"
target_bucket = args['TARGET_BUCKET']
table_name = args['TABLE_NAME']

# TPC-DS tables to ingest
tables = [
    'call_center', 'catalog_page', 'catalog_returns', 'catalog_sales',
    'customer', 'customer_address', 'customer_demographics', 'date_dim',
    'household_demographics', 'income_band', 'inventory', 'item',
    'promotion', 'reason', 'ship_mode', 'store', 'store_returns',
    'store_sales', 'time_dim', 'warehouse', 'web_page', 'web_returns',
    'web_sales', 'web_site'
]

def ingest_table(table_name):
    """Ingest a single table from source to bronze layer"""
    try:
        # Read from source
        source_path = f"{source_bucket}/{table_name}/"
        print(f"Reading from: {source_path}")
        
        # Read data (TPC-DS data is in pipe-delimited format)
        df = spark.read \
            .option("delimiter", "|") \
            .option("header", "false") \
            .option("inferSchema", "true") \
            .csv(source_path)
        
        # Convert to DynamicFrame
        dynamic_frame = DynamicFrame.fromDF(df, glueContext, table_name)
        
        # Write to bronze layer with partitioning
        target_path = f"{target_bucket}/bronze/{table_name}/"
        print(f"Writing to: {target_path}")
        
        glueContext.write_dynamic_frame.from_options(
            frame=dynamic_frame,
            connection_type="s3",
            connection_options={
                "path": target_path,
                "partitionKeys": []
            },
            format="parquet",
            format_options={
                "compression": "snappy"
            }
        )
        
        print(f"Successfully ingested {table_name}")
        return True
        
    except Exception as e:
        print(f"Error ingesting {table_name}: {str(e)}")
        return False

# Ingest specified table or all tables
if table_name == 'ALL':
    for table in tables:
        ingest_table(table)
else:
    ingest_table(table_name)

job.commit()
