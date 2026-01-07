"""
Glue Streaming Job: Process Database Logs
Reads from Kinesis, processes, and writes to Iceberg table
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'kinesis_stream_arn',
    'database_name',
    'table_name',
    's3_output_path',
    'checkpoint_location'
])

# Extract stream name and region from ARN
# ARN format: arn:aws:kinesis:region:account:stream/stream-name
arn_parts = args['kinesis_stream_arn'].split(':')
region = arn_parts[3]
stream_name = args['kinesis_stream_arn'].split('/')[-1]

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Define schema for database logs
schema = StructType([
    StructField("timestamp", StringType(), True),
    StructField("query_id", StringType(), True),
    StructField("database", StringType(), True),
    StructField("table", StringType(), True),
    StructField("query_type", StringType(), True),
    StructField("execution_time_ms", DoubleType(), True),
    StructField("rows_affected", IntegerType(), True),
    StructField("user", StringType(), True),
    StructField("client_ip", StringType(), True),
    StructField("status", StringType(), True),
    StructField("error_message", StringType(), True)
])

# Read from Kinesis
kinesis_options = {
    "streamName": stream_name,
    "endpointUrl": f"https://kinesis.{region}.amazonaws.com",
    "startingPosition": "TRIM_HORIZON",
    "inferSchema": "false",
    "awsSTSRoleARN": "",
    "awsSTSSessionName": "glue-kinesis-session"
}

streaming_df = spark.readStream \
    .format("kinesis") \
    .options(**kinesis_options) \
    .load()

# Parse JSON data
parsed_df = streaming_df.select(
    from_json(col("data").cast("string"), schema).alias("log")
).select("log.*")

# Add partitioning columns
processed_df = parsed_df \
    .withColumn("event_timestamp", to_timestamp(col("timestamp"))) \
    .withColumn("year", year(col("event_timestamp"))) \
    .withColumn("month", month(col("event_timestamp"))) \
    .withColumn("day", dayofmonth(col("event_timestamp"))) \
    .withColumn("hour", hour(col("event_timestamp")))

# Create Iceberg table if not exists
table_name = f"glue_catalog.{args['database_name']}.{args['table_name']}"

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {table_name} (
    timestamp STRING,
    query_id STRING,
    database STRING,
    table STRING,
    query_type STRING,
    execution_time_ms DOUBLE,
    rows_affected INT,
    user STRING,
    client_ip STRING,
    status STRING,
    error_message STRING,
    event_timestamp TIMESTAMP,
    year INT,
    month INT,
    day INT,
    hour INT
)
USING iceberg
PARTITIONED BY (year, month, day, hour)
LOCATION '{args['s3_output_path']}'
TBLPROPERTIES (
    'format-version'='2',
    'write.parquet.compression-codec'='snappy'
)
""")

# Write to Iceberg table
query = processed_df.writeStream \
    .format("iceberg") \
    .outputMode("append") \
    .trigger(processingTime='30 seconds') \
    .option("path", args['s3_output_path']) \
    .option("checkpointLocation", args['checkpoint_location']) \
    .option("fanout-enabled", "true") \
    .toTable(table_name)

query.awaitTermination()
job.commit()
