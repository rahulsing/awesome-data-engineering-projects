"""
Network Traffic Log Generator - Glue Python Shell Job
Generates realistic network traffic logs and sends them to Kinesis
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
URL_PATHS = [
    '/api/users',
    '/api/orders',
    '/api/products',
    '/api/auth/login',
    '/api/auth/logout',
    '/health',
    '/metrics',
    '/static/css/main.css',
    '/static/js/app.js',
    '/images/logo.png'
]


def generate_uuid():
    """Generate a simple UUID"""
    return f"{random.randint(10000000, 99999999)}-{random.randint(1000, 9999)}-{random.randint(1000, 9999)}"


def generate_ipv4():
    """Generate a random IPv4 address"""
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"


def generate_url():
    """Generate a random URL"""
    return f"https://example.com{random.choice(URL_PATHS)}"


def generate_network_log():
    """Generate a single network traffic log entry"""
    protocol = random.choice(PROTOCOLS)
    
    log = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'connection_id': generate_uuid(),
        'source_ip': generate_ipv4(),
        'source_port': random.randint(1024, 65535),
        'destination_ip': generate_ipv4(),
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
        log['url_path'] = random.choice(URL_PATHS)
        log['user_agent'] = random.choice(USER_AGENTS)
        log['referer'] = generate_url() if random.random() > 0.3 else None
    
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
                log = generate_network_log()
                response = send_to_kinesis(log)
                
                if response:
                    record_count += 1
                    if record_count % 100 == 0:
                        elapsed_minutes = (time.time() - start_job_time) / 60
                        print(f"Sent {record_count} records in {elapsed_minutes:.1f} minutes... Latest: {log['protocol']} {log['source_ip']} -> {log['destination_ip']}")
            
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
