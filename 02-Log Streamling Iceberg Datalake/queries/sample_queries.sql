-- Sample Athena Queries for Streaming Data Lake

-- ============================================
-- DATABASE LOGS QUERIES
-- ============================================

-- 1. Count total database queries
SELECT COUNT(*) as total_queries
FROM "streaming-data-lake_db"."database_logs";

-- 2. Query performance by type
SELECT 
    query_type,
    COUNT(*) as query_count,
    ROUND(AVG(execution_time_ms), 2) as avg_execution_time_ms,
    ROUND(MAX(execution_time_ms), 2) as max_execution_time_ms,
    ROUND(MIN(execution_time_ms), 2) as min_execution_time_ms
FROM "streaming-data-lake_db"."database_logs"
GROUP BY query_type
ORDER BY query_count DESC;

-- 3. Failed queries analysis
SELECT 
    database,
    table,
    query_type,
    COUNT(*) as failure_count,
    error_message
FROM "streaming-data-lake_db"."database_logs"
WHERE status = 'FAILED'
GROUP BY database, table, query_type, error_message
ORDER BY failure_count DESC
LIMIT 20;

-- 4. Top users by query volume
SELECT 
    user,
    COUNT(*) as query_count,
    ROUND(AVG(execution_time_ms), 2) as avg_execution_time_ms
FROM "streaming-data-lake_db"."database_logs"
GROUP BY user
ORDER BY query_count DESC
LIMIT 10;

-- 5. Hourly query patterns (specific day)
SELECT 
    year,
    month,
    day,
    hour,
    COUNT(*) as query_count,
    ROUND(AVG(execution_time_ms), 2) as avg_execution_time_ms
FROM "streaming-data-lake_db"."database_logs"
WHERE year = 2026 AND month = 1 AND day = 5
GROUP BY year, month, day, hour
ORDER BY hour;

-- 6. Slow queries (> 5 seconds)
SELECT 
    query_id,
    database,
    table,
    query_type,
    execution_time_ms,
    user,
    timestamp
FROM "streaming-data-lake_db"."database_logs"
WHERE execution_time_ms > 5000
ORDER BY execution_time_ms DESC
LIMIT 50;

-- 7. Database activity by database
SELECT 
    database,
    COUNT(*) as total_queries,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful_queries,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed_queries,
    ROUND(AVG(execution_time_ms), 2) as avg_execution_time_ms
FROM "streaming-data-lake_db"."database_logs"
GROUP BY database
ORDER BY total_queries DESC;

-- ============================================
-- NETWORK LOGS QUERIES
-- ============================================

-- 8. Count total network connections
SELECT COUNT(*) as total_connections
FROM "streaming-data-lake_db"."network_logs";

-- 9. Traffic by protocol
SELECT 
    protocol,
    COUNT(*) as connection_count,
    SUM(bytes_sent) as total_bytes_sent,
    SUM(bytes_received) as total_bytes_received,
    ROUND(AVG(duration_ms), 2) as avg_duration_ms
FROM "streaming-data-lake_db"."network_logs"
GROUP BY protocol
ORDER BY connection_count DESC;

-- 10. HTTP status code distribution
SELECT 
    status_code,
    COUNT(*) as request_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM "streaming-data-lake_db"."network_logs"
WHERE protocol IN ('HTTP', 'HTTPS')
GROUP BY status_code
ORDER BY request_count DESC;

-- 11. Top source IPs by traffic volume
SELECT 
    source_ip,
    COUNT(*) as connection_count,
    SUM(bytes_sent) as total_bytes_sent,
    SUM(bytes_received) as total_bytes_received
FROM "streaming-data-lake_db"."network_logs"
GROUP BY source_ip
ORDER BY connection_count DESC
LIMIT 20;

-- 12. Most accessed destination ports
SELECT 
    destination_port,
    protocol,
    COUNT(*) as connection_count
FROM "streaming-data-lake_db"."network_logs"
GROUP BY destination_port, protocol
ORDER BY connection_count DESC
LIMIT 15;

-- 13. HTTP errors (4xx and 5xx)
SELECT 
    status_code,
    http_method,
    url_path,
    COUNT(*) as error_count
FROM "streaming-data-lake_db"."network_logs"
WHERE status_code >= 400
GROUP BY status_code, http_method, url_path
ORDER BY error_count DESC
LIMIT 30;

-- 14. Hourly network traffic patterns
SELECT 
    year,
    month,
    day,
    hour,
    COUNT(*) as connection_count,
    SUM(bytes_sent + bytes_received) as total_bytes
FROM "streaming-data-lake_db"."network_logs"
WHERE year = 2026 AND month = 1 AND day = 5
GROUP BY year, month, day, hour
ORDER BY hour;

-- 15. Top user agents
SELECT 
    user_agent,
    COUNT(*) as request_count
FROM "streaming-data-lake_db"."network_logs"
WHERE user_agent IS NOT NULL
GROUP BY user_agent
ORDER BY request_count DESC
LIMIT 10;

-- ============================================
-- COMBINED ANALYSIS
-- ============================================

-- 16. Activity correlation by hour
SELECT 
    d.hour,
    COUNT(DISTINCT d.query_id) as db_queries,
    COUNT(DISTINCT n.connection_id) as network_connections
FROM "streaming-data-lake_db"."database_logs" d
FULL OUTER JOIN "streaming-data-lake_db"."network_logs" n
    ON d.year = n.year 
    AND d.month = n.month 
    AND d.day = n.day 
    AND d.hour = n.hour
WHERE d.year = 2026 AND d.month = 1 AND d.day = 5
GROUP BY d.hour
ORDER BY d.hour;

-- 17. Time-based partition scan test
SELECT 
    year,
    month,
    day,
    hour,
    COUNT(*) as record_count
FROM "streaming-data-lake_db"."database_logs"
WHERE year = 2026 AND month = 1
GROUP BY year, month, day, hour
ORDER BY year, month, day, hour;
