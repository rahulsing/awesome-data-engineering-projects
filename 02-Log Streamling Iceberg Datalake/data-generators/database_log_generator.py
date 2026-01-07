"""
Database Log Generator
Generates realistic database query logs and sends them to Kinesis
"""
import json
import time
import random
from datetime import datetime
import boto3
from faker import Faker

# Configuration
REGION = 'us-east-1'  # Update with your region
STREAM_NAME = 'streaming-data-lake-database-logs'  # Update after CloudFormation deployment
RECORDS_PER_SECOND = 5

# Initialize
fake = Faker()
kinesis_client = boto3.client('kinesis', region_name=REGION)

# Sample data
QUERY_TYPES = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'JOIN']
DATABASES = ['users_db', 'orders_db', 'products_db', 'analytics_db']
TABLES = ['users', 'orders', 'products', 'transactions', 'sessions', 'events']
STATUSES = ['SUCCESS', 'SUCCESS', 'SUCCESS', 'SUCCESS', 'FAILED']  # 80% success rate


def generate_database_log():
    """Generate a single database log entry"""
    query_type = random.choice(QUERY_TYPES)
    execution_time = random.uniform(0.01, 5.0) if random.random() > 0.1 else random.uniform(5.0, 30.0)
    
    log = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'query_id': fake.uuid4(),
        'database': random.choice(DATABASES),
        'table': random.choice(TABLES),
        'query_type': query_type,
        'execution_time_ms': round(execution_time * 1000, 2),
        'rows_affected': random.randint(0, 10000) if query_type != 'SELECT' else random.randint(0, 50000),
        'user': fake.user_name(),
        'client_ip': fake.ipv4(),
        'status': random.choice(STATUSES),
        'error_message': fake.sentence() if random.random() < 0.2 else None
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
    print(f"Stream: {STREAM_NAME}")
    print(f"Region: {REGION}")
    print("-" * 50)
    
    record_count = 0
    
    try:
        while True:
            start_time = time.time()
            
            for _ in range(RECORDS_PER_SECOND):
                log = generate_database_log()
                response = send_to_kinesis(log)
                
                if response:
                    record_count += 1
                    if record_count % 100 == 0:
                        print(f"Sent {record_count} records... Latest: {log['query_type']} on {log['table']}")
            
            # Sleep to maintain target rate
            elapsed = time.time() - start_time
            sleep_time = max(0, 1.0 - elapsed)
            time.sleep(sleep_time)
            
    except KeyboardInterrupt:
        print(f"\nStopping generator. Total records sent: {record_count}")
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
