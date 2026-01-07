"""
Network Traffic Log Generator
Generates realistic network traffic logs and sends them to Kinesis
"""
import json
import time
import random
from datetime import datetime
import boto3
from faker import Faker

# Configuration
REGION = 'us-east-1'  # Update with your region
STREAM_NAME = 'streaming-data-lake-network-logs'  # Update after CloudFormation deployment
RECORDS_PER_SECOND = 10

# Initialize
fake = Faker()
kinesis_client = boto3.client('kinesis', region_name=REGION)

# Sample data
PROTOCOLS = ['HTTP', 'HTTPS', 'TCP', 'UDP', 'FTP', 'SSH']
HTTP_METHODS = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
STATUS_CODES = [200, 200, 200, 201, 204, 301, 302, 400, 401, 403, 404, 500, 502, 503]
USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)',
    'curl/7.68.0',
    'python-requests/2.28.0'
]


def generate_network_log():
    """Generate a single network traffic log entry"""
    protocol = random.choice(PROTOCOLS)
    
    log = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'connection_id': fake.uuid4(),
        'source_ip': fake.ipv4(),
        'source_port': random.randint(1024, 65535),
        'destination_ip': fake.ipv4(),
        'destination_port': random.choice([80, 443, 22, 21, 3306, 5432, 8080]),
        'protocol': protocol,
        'bytes_sent': random.randint(100, 1000000),
        'bytes_received': random.randint(100, 5000000),
        'duration_ms': random.randint(10, 5000),
        'packets_sent': random.randint(1, 1000),
        'packets_received': random.randint(1, 2000)
    }
    
    # Add HTTP-specific fields
    if protocol in ['HTTP', 'HTTPS']:
        log['http_method'] = random.choice(HTTP_METHODS)
        log['status_code'] = random.choice(STATUS_CODES)
        log['url_path'] = fake.uri_path()
        log['user_agent'] = random.choice(USER_AGENTS)
        log['referer'] = fake.url() if random.random() > 0.3 else None
    
    return log


def send_to_kinesis(record):
    """Send record to Kinesis stream"""
    try:
        response = kinesis_client.put_record(
            StreamName=STREAM_NAME,
            Data=json.dumps(record),
            PartitionKey=record['source_ip']
        )
        return response
    except Exception as e:
        print(f"Error sending to Kinesis: {e}")
        return None


def main():
    """Main loop to generate and send logs"""
    print(f"Starting Network Log Generator...")
    print(f"Target: {RECORDS_PER_SECOND} records/second")
    print(f"Stream: {STREAM_NAME}")
    print(f"Region: {REGION}")
    print("-" * 50)
    
    record_count = 0
    
    try:
        while True:
            start_time = time.time()
            
            for _ in range(RECORDS_PER_SECOND):
                log = generate_network_log()
                response = send_to_kinesis(log)
                
                if response:
                    record_count += 1
                    if record_count % 100 == 0:
                        print(f"Sent {record_count} records... Latest: {log['protocol']} {log['source_ip']} -> {log['destination_ip']}")
            
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
