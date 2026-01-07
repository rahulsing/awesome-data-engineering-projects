"""
Glue Streaming Job: Process Network Logs
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

# Define schema for network logs
schema = StructType([
    StructField("timestamp", StringType(), True),
    StructField("connection_id", StringType(), True),
    StructField("source_ip", StringType(), True),
    StructField("source_port", IntegerType(), True),
    StructField("destination_ip", StringType(), True),
    StructField("destination_port", IntegerType(), True),
    StructField("protocol", StringType(), True),
    StructField("bytes_sent", IntegerType(), True),
    StructField("bytes_received", IntegerType(), True),
    StructField("duration_ms", IntegerType(), True),
    StructField("packets_sent", IntegerType(), True),
    StructField("packets_received", IntegerType(), True),
    StructField("http_method", StringType(), True),
    StructField("status_code", IntegerType(), True),
    StructField("url_path", StringType(), True),
    StructField("user_agent", StringType(), True),
    StructField("referer", StringType(), True)
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
    connection_id STRING,
    source_ip STRING,
    source_port INT,
    destination_ip STRING,
    destination_port INT,
    protocol STRING,
    bytes_sent INT,
    bytes_received INT,
    duration_ms INT,
    packets_sent INT,
    packets_received INT,
    http_method STRING,
    status_code INT,
    url_path STRING,
    user_agent STRING,
    referer STRING,
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
