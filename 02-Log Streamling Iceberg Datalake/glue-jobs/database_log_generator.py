"""
Database Log Generator - Glue Python Shell Job
Generates realistic database query logs and sends them to Kinesis
"""
import sys
import json
import time
import random
from datetime import datetime
import boto3
from awsglue.utils import getResolvedOptions

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'kinesis_stream_name',
    'region',
    'records_per_second',
    'duration_minutes'
])

# Configuration from parameters
REGION = args['region']
STREAM_NAME = args['kinesis_stream_name']
RECORDS_PER_SECOND = int(args['records_per_second'])
DURATION_MINUTES = int(args['duration_minutes'])

# Initialize
kinesis_client = boto3.client('kinesis', region_name=REGION)

# Sample data
QUERY_TYPES = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'JOIN']
DATABASES = ['users_db', 'orders_db', 'products_db', 'analytics_db']
TABLES = ['users', 'orders', 'products', 'transactions', 'sessions', 'events']
STATUSES = ['SUCCESS', 'SUCCESS', 'SUCCESS', 'SUCCESS', 'FAILED']  # 80% success rate
USERS = ['alice', 'bob', 'charlie', 'david', 'emma', 'frank', 'grace', 'henry']
ERROR_MESSAGES = [
    'Connection timeout',
    'Deadlock detected',
    'Syntax error near WHERE',
    'Table does not exist',
    'Permission denied',
    'Constraint violation'
]


def generate_uuid():
    """Generate a simple UUID"""
    return f"{random.randint(10000000, 99999999)}-{random.randint(1000, 9999)}-{random.randint(1000, 9999)}"


def generate_ipv4():
    """Generate a random IPv4 address"""
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"


def generate_database_log():
    """Generate a single database log entry"""
    query_type = random.choice(QUERY_TYPES)
    execution_time = random.uniform(0.01, 5.0) if random.random() > 0.1 else random.uniform(5.0, 30.0)
    status = random.choice(STATUSES)
    
    log = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'query_id': generate_uuid(),
        'database': random.choice(DATABASES),
        'table': random.choice(TABLES),
        'query_type': query_type,
        'execution_time_ms': round(execution_time * 1000, 2),
        'rows_affected': random.randint(0, 10000) if query_type != 'SELECT' else random.randint(0, 50000),
        'user': random.choice(USERS),
        'client_ip': generate_ipv4(),
        'status': status,
        'error_message': random.choice(ERROR_MESSAGES) if status == 'FAILED' else None
    }
    
    return log


def send_to_kinesis(record):
    """Send record to Kinesis stream"""
    try:
        response = kinesis_client.put_record(
            StreamName=STREAM_NAME,
            Data=json.dumps(record),
            PartitionKey=record['database']
        )
        return response
    except Exception as e:
        print(f"Error sending to Kinesis: {e}")
        return None


def main():
    """Main loop to generate and send logs"""
    print(f"Starting Database Log Generator...")
    print(f"Target: {RECORDS_PER_SECOND} records/second")
    print(f"Duration: {DURATION_MINUTES} minutes")
    print(f"Stream: {STREAM_NAME}")
    print(f"Region: {REGION}")
    print("-" * 50)
    
    record_count = 0
    start_job_time = time.time()
    end_time = start_job_time + (DURATION_MINUTES * 60)
    
    try:
        while time.time() < end_time:
            start_time = time.time()
            
            for _ in range(RECORDS_PER_SECOND):
                log = generate_database_log()
                response = send_to_kinesis(log)
                
                if response:
                    record_count += 1
                    if record_count % 100 == 0:
                        elapsed_minutes = (time.time() - start_job_time) / 60
                        print(f"Sent {record_count} records in {elapsed_minutes:.1f} minutes... Latest: {log['query_type']} on {log['table']}")
            
            # Sleep to maintain target rate
            elapsed = time.time() - start_time
            sleep_time = max(0, 1.0 - elapsed)
            time.sleep(sleep_time)
        
        print(f"\nCompleted! Total records sent: {record_count}")
        
    except Exception as e:
        print(f"Error: {e}")
        raise


if __name__ == "__main__":
    main()
