-- Enable and install sqlite extension
INSTALL sqlite;
LOAD sqlite;

-- Attach the macOS Screen Time SQLite database
ATTACH '{{ .HomeDir }}/Library/Application Support/Knowledge/knowledgeC.db' (TYPE sqlite);
USE knowledgeC;


-------------------------------------------------------------------------------
-- LLM-Support View Creation
-------------------------------------------------------------------------------

-- ============================================
-- CORE VIEWS
-- ============================================

-- Main app usage view with converted timestamps
CREATE OR REPLACE VIEW v_app_usage AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + INTERVAL '978307200 seconds' as start_time,
    ZENDDATE + INTERVAL '978307200 seconds' as end_time,
    DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date,
    EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '978307200 seconds')) as hour_of_day,
    EXTRACT(DOW FROM (ZSTARTDATE + INTERVAL '978307200 seconds')) as day_of_week,
    CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE NULL 
    END as duration_seconds,
    ZVALUEINTEGER as value_integer,
    ZVALUEDOUBLE as value_double,
    ZSOURCE as source_id
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
AND ZVALUESTRING IS NOT NULL;

-- Web usage view with domain information
CREATE OR REPLACE VIEW v_web_usage AS
SELECT 
    o.Z_PK as id,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBPAGEURL as url,
    o.ZSTARTDATE + INTERVAL '978307200 seconds' as start_time,
    o.ZENDDATE + INTERVAL '978307200 seconds' as end_time,
    DATE(o.ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date,
    CASE 
        WHEN o.ZENDDATE IS NOT NULL AND o.ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (o.ZENDDATE - o.ZSTARTDATE))
        ELSE NULL 
    END as duration_seconds,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__SAFARIPROFILEID as safari_profile_id
FROM ZOBJECT o
JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE o.ZSTREAMNAME = '/app/webUsage' 
    AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL;

-- Notification view
CREATE OR REPLACE VIEW v_notifications AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + INTERVAL '978307200 seconds' as notification_time,
    DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as notification_date,
    EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '978307200 seconds')) as hour_of_day,
    ZVALUEINTEGER as value_integer
FROM ZOBJECT
WHERE ZSTREAMNAME = '/notification/usage'
    AND ZVALUESTRING IS NOT NULL;

-- App focus events view
CREATE OR REPLACE VIEW v_app_focus AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + INTERVAL '978307200 seconds' as start_time,
    ZENDDATE + INTERVAL '978307200 seconds' as end_time,
    DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as focus_date,
    CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE NULL 
    END as duration_seconds
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/inFocus'
    AND ZVALUESTRING IS NOT NULL;

-- ============================================
-- AGGREGATE VIEWS
-- ============================================

-- Daily app usage summary
CREATE OR REPLACE VIEW v_daily_app_summary AS
SELECT 
    DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as session_count,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE 0 
    END) as total_seconds,
    AVG(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE NULL 
    END) as avg_session_seconds,
    MAX(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE 0 
    END) as max_session_seconds,
    MIN(ZSTARTDATE + INTERVAL '978307200 seconds') as first_use,
    MAX(ZENDDATE + INTERVAL '978307200 seconds') as last_use
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY DATE(ZSTARTDATE + INTERVAL '978307200 seconds'), ZVALUESTRING;

-- Daily web domain summary
CREATE OR REPLACE VIEW v_daily_web_summary AS
SELECT 
    DATE(o.ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
    COUNT(*) as visit_count,
    SUM(CASE 
        WHEN o.ZENDDATE IS NOT NULL AND o.ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (o.ZENDDATE - o.ZSTARTDATE))
        ELSE 0 
    END) as total_seconds
FROM ZOBJECT o
JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE o.ZSTREAMNAME = '/app/webUsage' 
    AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
GROUP BY DATE(o.ZSTARTDATE + INTERVAL '978307200 seconds'), sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN;

-- Hourly usage patterns
CREATE OR REPLACE VIEW v_hourly_usage_pattern AS
SELECT 
    EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '978307200 seconds')) as hour_of_day,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as session_count,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE 0 
    END) as total_seconds
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '978307200 seconds')), ZVALUESTRING;

-- ============================================
-- ANALYSIS VIEWS
-- ============================================

-- App switching analysis view
CREATE OR REPLACE VIEW v_app_switches AS
WITH ordered_sessions AS (
    SELECT 
        ZSTARTDATE + INTERVAL '978307200 seconds' as start_time,
        ZENDDATE + INTERVAL '978307200 seconds' as end_time,
        ZVALUESTRING as app,
        LAG(ZVALUESTRING) OVER (ORDER BY ZSTARTDATE) as prev_app,
        LAG(ZENDDATE + INTERVAL '978307200 seconds') OVER (ORDER BY ZSTARTDATE) as prev_end_time,
        DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date
    FROM ZOBJECT
    WHERE ZSTREAMNAME = '/app/usage'
        AND ZVALUESTRING IS NOT NULL
)
SELECT 
    usage_date,
    start_time,
    end_time,
    app,
    prev_app,
    CASE 
        WHEN prev_end_time IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (start_time - prev_end_time))
        ELSE NULL 
    END as seconds_between_apps,
    CASE 
        WHEN prev_app IS NOT NULL AND app != prev_app THEN 1 
        ELSE 0 
    END as is_app_switch,
    CASE 
        WHEN prev_end_time IS NOT NULL AND app != prev_app THEN
            CASE 
                WHEN EXTRACT(EPOCH FROM (start_time - prev_end_time)) < 60 THEN 'rapid_switch'
                WHEN EXTRACT(EPOCH FROM (start_time - prev_end_time)) < 300 THEN 'quick_switch'
                WHEN EXTRACT(EPOCH FROM (start_time - prev_end_time)) < 900 THEN 'moderate_switch'
                ELSE 'focused_period'
            END
        ELSE NULL
    END as switch_type
FROM ordered_sessions;

-- Focus score by day
CREATE OR REPLACE VIEW v_daily_focus_metrics AS
SELECT 
    DATE(ZSTARTDATE + INTERVAL '978307200 seconds') as usage_date,
    COUNT(DISTINCT ZVALUESTRING) as unique_apps,
    COUNT(*) as total_sessions,
    CAST(COUNT(DISTINCT ZVALUESTRING) AS DOUBLE) / COUNT(*) as app_diversity_ratio,
    AVG(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE NULL 
    END) as avg_session_seconds,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE 0 
    END) / 3600.0 as total_hours
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY DATE(ZSTARTDATE + INTERVAL '978307200 seconds');

-- ============================================
-- HELPER VIEWS
-- ============================================

-- All available stream names
CREATE OR REPLACE VIEW v_stream_names AS
SELECT  
    ZSTREAMNAME as stream_name,
    COUNT(*) as record_count,
    MIN(ZSTARTDATE + INTERVAL '978307200 seconds') as earliest_date,
    MAX(ZSTARTDATE + INTERVAL '978307200 seconds') as latest_date
FROM ZOBJECT
GROUP BY ZSTREAMNAME
ORDER BY record_count DESC;

-- All apps with usage stats
CREATE OR REPLACE VIEW v_app_catalog AS
SELECT 
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as total_sessions,
    MIN(DATE(ZSTARTDATE + INTERVAL '978307200 seconds')) as first_seen_date,
    MAX(DATE(ZSTARTDATE + INTERVAL '978307200 seconds')) as last_seen_date,
    COUNT(DISTINCT DATE(ZSTARTDATE + INTERVAL '978307200 seconds')) as days_used,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (ZENDDATE - ZSTARTDATE))
        ELSE 0 
    END) / 3600.0 as total_hours
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY ZVALUESTRING
ORDER BY total_hours DESC;

-- Source information view
CREATE OR REPLACE VIEW v_sources AS
SELECT 
    s.Z_PK as source_id,
    s.ZBUNDLEID as bundle_id,
    s.ZSOURCEID as source_identifier,
    s.ZDEVICEID as device_id,
    s.ZGROUPID as group_id,
    COUNT(o.Z_PK) as event_count
FROM ZSOURCE s
LEFT JOIN ZOBJECT o ON s.Z_PK = o.ZSOURCE
GROUP BY s.Z_PK, s.ZBUNDLEID, s.ZSOURCEID, s.ZDEVICEID, s.ZGROUPID;

-- ============================================
-- CONVENIENCE VIEWS FOR COMMON QUERIES
-- ============================================

-- Today's usage
CREATE OR REPLACE VIEW v_today_usage AS
SELECT * FROM v_app_usage 
WHERE usage_date = CURRENT_DATE;

-- Yesterday's usage
CREATE OR REPLACE VIEW v_yesterday_usage AS
SELECT * FROM v_app_usage 
WHERE usage_date = CURRENT_DATE - INTERVAL '1 day';

-- Last 7 days usage
CREATE OR REPLACE VIEW v_week_usage AS
SELECT * FROM v_app_usage 
WHERE start_time >= CURRENT_DATE - INTERVAL '7 days';

-- Last 30 days usage
CREATE OR REPLACE VIEW v_month_usage AS
SELECT * FROM v_app_usage 
WHERE start_time >= CURRENT_DATE - INTERVAL '30 days';

-- ============================================
-- SIMPLIFIED QUERY VIEWS
-- ============================================

-- Simple today summary
CREATE OR REPLACE VIEW v_today_summary AS
SELECT 
    app_bundle_id,
    COUNT(*) as sessions,
    ROUND(SUM(duration_seconds) / 60.0, 1) as total_minutes,
    ROUND(AVG(duration_seconds), 1) as avg_seconds_per_session
FROM v_app_usage
WHERE usage_date = CURRENT_DATE
    AND duration_seconds IS NOT NULL
GROUP BY app_bundle_id
ORDER BY total_minutes DESC;

-- Simple web summary for today
CREATE OR REPLACE VIEW v_today_web_summary AS
SELECT 
    domain,
    COUNT(*) as visits,
    ROUND(SUM(duration_seconds) / 60.0, 1) as total_minutes
FROM v_web_usage
WHERE usage_date = CURRENT_DATE
    AND duration_seconds IS NOT NULL
GROUP BY domain
ORDER BY total_minutes DESC;