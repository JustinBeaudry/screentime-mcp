-------------------------------------------------------------------------------
-- LLM-Support View Creation
-------------------------------------------------------------------------------

-- Screen Time Database Views for DuckDB
-- These views handle Core Data timestamp conversion (+ 978307200 seconds)

-- ============================================
-- CORE VIEWS
-- ============================================

-- Main app usage view with converted timestamps
CREATE OR REPLACE VIEW v_app_usage AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + TO_SECONDS(978307200.0) as start_time,
    ZENDDATE + TO_SECONDS(978307200.0) as end_time,
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date,
    DATEPART('hour', ZSTARTDATE + TO_SECONDS(978307200.0)) as hour_of_day,
    DATEPART('dow', ZSTARTDATE + TO_SECONDS(978307200.0)) as day_of_week,
    CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
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
    o.ZSTARTDATE + TO_SECONDS(978307200.0) as start_time,
    o.ZENDDATE + TO_SECONDS(978307200.0) as end_time,
    CAST(o.ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date,
    CASE 
        WHEN o.ZENDDATE IS NOT NULL AND o.ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', o.ZENDDATE - o.ZSTARTDATE)
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
    ZSTARTDATE + TO_SECONDS(978307200.0) as notification_time,
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as notification_date,
    DATEPART('hour', ZSTARTDATE + TO_SECONDS(978307200.0)) as hour_of_day,
    ZVALUEINTEGER as value_integer
FROM ZOBJECT
WHERE ZSTREAMNAME = '/notification/usage'
    AND ZVALUESTRING IS NOT NULL;

-- App focus events view
CREATE OR REPLACE VIEW v_app_focus AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + TO_SECONDS(978307200.0) as start_time,
    ZENDDATE + TO_SECONDS(978307200.0) as end_time,
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as focus_date,
    CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
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
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as session_count,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE 0 
    END) as total_seconds,
    AVG(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE NULL 
    END) as avg_session_seconds,
    MAX(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE 0 
    END) as max_session_seconds,
    MIN(ZSTARTDATE + TO_SECONDS(978307200.0)) as first_use,
    MAX(ZENDDATE + TO_SECONDS(978307200.0)) as last_use
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE), ZVALUESTRING;

-- Daily web domain summary
CREATE OR REPLACE VIEW v_daily_web_summary AS
SELECT 
    CAST(o.ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
    COUNT(*) as visit_count,
    SUM(CASE 
        WHEN o.ZENDDATE IS NOT NULL AND o.ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', o.ZENDDATE - o.ZSTARTDATE)
        ELSE 0 
    END) as total_seconds
FROM ZOBJECT o
JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE o.ZSTREAMNAME = '/app/webUsage' 
    AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
GROUP BY CAST(o.ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE), sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN;

-- Hourly usage patterns
CREATE OR REPLACE VIEW v_hourly_usage_pattern AS
SELECT 
    DATEPART('hour', ZSTARTDATE + TO_SECONDS(978307200.0)) as hour_of_day,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as session_count,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE 0 
    END) as total_seconds
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY DATEPART('hour', ZSTARTDATE + TO_SECONDS(978307200.0)), ZVALUESTRING;

-- ============================================
-- ANALYSIS VIEWS
-- ============================================

-- App switching analysis view
CREATE OR REPLACE VIEW v_app_switches AS
WITH ordered_sessions AS (
    SELECT 
        ZSTARTDATE + TO_SECONDS(978307200.0) as start_time,
        ZENDDATE + TO_SECONDS(978307200.0) as end_time,
        ZVALUESTRING as app,
        LAG(ZVALUESTRING) OVER (ORDER BY ZSTARTDATE) as prev_app,
        LAG(ZENDDATE + TO_SECONDS(978307200.0)) OVER (ORDER BY ZSTARTDATE) as prev_end_time,
        CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date
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
        THEN DATEPART('epoch', start_time - prev_end_time)
        ELSE NULL 
    END as seconds_between_apps,
    CASE 
        WHEN prev_app IS NOT NULL AND app != prev_app THEN 1 
        ELSE 0 
    END as is_app_switch,
    CASE 
        WHEN prev_end_time IS NOT NULL AND app != prev_app THEN
            CASE 
                WHEN DATEPART('epoch', start_time - prev_end_time) < 60 THEN 'rapid_switch'
                WHEN DATEPART('epoch', start_time - prev_end_time) < 300 THEN 'quick_switch'
                WHEN DATEPART('epoch', start_time - prev_end_time) < 900 THEN 'moderate_switch'
                ELSE 'focused_period'
            END
        ELSE NULL
    END as switch_type
FROM ordered_sessions;

-- Focus score by day
CREATE OR REPLACE VIEW v_daily_focus_metrics AS
SELECT 
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as usage_date,
    COUNT(DISTINCT ZVALUESTRING) as unique_apps,
    COUNT(*) as total_sessions,
    CAST(COUNT(DISTINCT ZVALUESTRING) AS DOUBLE) / COUNT(*) as app_diversity_ratio,
    AVG(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE NULL 
    END) as avg_session_seconds,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
        ELSE 0 
    END) / 3600.0 as total_hours
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE);

-- ============================================
-- HELPER VIEWS
-- ============================================

-- All available stream names
CREATE OR REPLACE VIEW v_stream_names AS
SELECT  
    ZSTREAMNAME as stream_name,
    COUNT(*) as record_count,
    MIN(ZSTARTDATE + TO_SECONDS(978307200.0)) as earliest_date,
    MAX(ZSTARTDATE + TO_SECONDS(978307200.0)) as latest_date
FROM ZOBJECT
GROUP BY ZSTREAMNAME
ORDER BY record_count DESC;

-- All apps with usage stats
CREATE OR REPLACE VIEW v_app_catalog AS
SELECT 
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as total_sessions,
    MIN(CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE)) as first_seen_date,
    MAX(CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE)) as last_seen_date,
    COUNT(DISTINCT CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE)) as days_used,
    SUM(CASE 
        WHEN ZENDDATE IS NOT NULL AND ZSTARTDATE IS NOT NULL 
        THEN DATEPART('epoch', ZENDDATE - ZSTARTDATE)
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
WHERE usage_date = CURRENT_DATE + TO_DAYS(-1);

-- Last 7 days usage
CREATE OR REPLACE VIEW v_week_usage AS
SELECT * FROM v_app_usage 
WHERE start_time >= CURRENT_DATE + TO_DAYS(-7);

-- Last 30 days usage
CREATE OR REPLACE VIEW v_month_usage AS
SELECT * FROM v_app_usage 
WHERE start_time >= CURRENT_DATE + TO_DAYS(-30);

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

-- ============================================
-- ADDITIONAL ANALYSIS VIEWS
-- ============================================

-- Daily notification summary
CREATE OR REPLACE VIEW v_daily_notification_summary AS
SELECT 
    CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE) as notification_date,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as notification_count,
    MIN(ZSTARTDATE + TO_SECONDS(978307200.0)) as first_notification,
    MAX(ZSTARTDATE + TO_SECONDS(978307200.0)) as last_notification
FROM ZOBJECT
WHERE ZSTREAMNAME = '/notification/usage'
    AND ZVALUESTRING IS NOT NULL
GROUP BY CAST(ZSTARTDATE + TO_SECONDS(978307200.0) AS DATE), ZVALUESTRING;

-- App session patterns (for identifying work vs personal apps)
CREATE OR REPLACE VIEW v_app_session_patterns AS
SELECT 
    app_bundle_id,
    COUNT(DISTINCT usage_date) as days_used,
    AVG(CASE WHEN hour_of_day BETWEEN 9 AND 17 THEN 1 ELSE 0 END) as work_hours_ratio,
    AVG(CASE WHEN day_of_week BETWEEN 1 AND 5 THEN 1 ELSE 0 END) as weekday_ratio,
    AVG(duration_seconds) as avg_session_seconds,
    COUNT(*) as total_sessions
FROM v_app_usage
WHERE duration_seconds IS NOT NULL
GROUP BY app_bundle_id
HAVING COUNT(*) >= 10;

-- Recent activity view (last 24 hours)
CREATE OR REPLACE VIEW v_recent_activity AS
SELECT 
    app_bundle_id,
    start_time,
    end_time,
    duration_seconds,
    CASE 
        WHEN duration_seconds < 60 THEN 'brief'
        WHEN duration_seconds < 300 THEN 'short'
        WHEN duration_seconds < 900 THEN 'medium'
        ELSE 'long'
    END as session_type
FROM v_app_usage
WHERE start_time >= CURRENT_TIMESTAMP + TO_HOURS(-24)
ORDER BY start_time DESC;

-- ============================================
-- TEMPORAL ANALYSIS VIEWS
-- ============================================

-- View to find which app was active at any given time
-- This helps correlate web browsing with active applications
CREATE OR REPLACE VIEW v_app_timeline AS
SELECT 
    app_bundle_id,
    start_time,
    end_time,
    usage_date,
    duration_seconds,
    -- Add epoch timestamps for easier range queries
    DATEPART('epoch', start_time) as start_epoch,
    DATEPART('epoch', end_time) as end_epoch
FROM v_app_usage
WHERE duration_seconds > 0;

-- View to track app-to-app transitions with timing
CREATE OR REPLACE VIEW v_app_transitions AS
WITH ordered_apps AS (
    SELECT 
        app_bundle_id,
        start_time,
        end_time,
        LAG(app_bundle_id) OVER (ORDER BY start_time) as prev_app,
        LAG(end_time) OVER (ORDER BY start_time) as prev_end_time,
        LEAD(app_bundle_id) OVER (ORDER BY start_time) as next_app,
        LEAD(start_time) OVER (ORDER BY start_time) as next_start_time
    FROM v_app_usage
    WHERE duration_seconds IS NOT NULL
)
SELECT 
    prev_app as from_app,
    app_bundle_id as to_app,
    DATEPART('epoch', start_time - prev_end_time) as gap_seconds,
    CASE 
        WHEN DATEPART('epoch', start_time - prev_end_time) < 1 THEN 'instant'
        WHEN DATEPART('epoch', start_time - prev_end_time) < 5 THEN 'immediate'
        WHEN DATEPART('epoch', start_time - prev_end_time) < 60 THEN 'quick'
        WHEN DATEPART('epoch', start_time - prev_end_time) < 300 THEN 'delayed'
        ELSE 'separate_session'
    END as transition_speed,
    start_time as transition_time,
    CAST(start_time AS DATE) as transition_date
FROM ordered_apps
WHERE prev_app IS NOT NULL;

-- View for correlating web visits with the active app at that time
CREATE OR REPLACE VIEW v_web_usage_with_active_app AS
SELECT 
    w.domain,
    w.url,
    w.start_time as web_start_time,
    w.duration_seconds as web_duration_seconds,
    w.usage_date,
    -- Find the app that was active when this web visit started
    (SELECT app_bundle_id 
     FROM v_app_timeline a 
     WHERE a.usage_date = w.usage_date
       AND w.start_time >= a.start_time 
       AND w.start_time < a.end_time
     ORDER BY a.start_time DESC
     LIMIT 1) as active_app_during_visit
FROM v_web_usage w;

-- ============================================
-- ANALYSIS HELPER VIEWS
-- ============================================

-- Simplified view for app-to-Safari transitions
CREATE OR REPLACE VIEW v_safari_transitions AS
SELECT 
    from_app,
    transition_speed,
    gap_seconds,
    transition_time,
    transition_date
FROM v_app_transitions
WHERE to_app = 'com.apple.Safari'
  AND from_app != 'com.apple.Safari';

-- View showing domains visited after specific app transitions
CREATE OR REPLACE VIEW v_post_transition_web_activity AS
SELECT 
    t.from_app,
    t.to_app,
    t.transition_time,
    w.domain,
    w.start_time as web_start_time,
    DATEPART('epoch', w.start_time - t.transition_time) as seconds_after_transition
FROM v_app_transitions t
JOIN v_web_usage w 
  ON CAST(t.transition_time AS DATE) = w.usage_date
  AND w.start_time >= t.transition_time
  AND w.start_time < t.transition_time + TO_SECONDS(300.0) -- Within 5 minutes
WHERE t.to_app = 'com.apple.Safari';

-- ============================================
-- AGGREGATED ANALYSIS VIEWS
-- ============================================

-- Summary of web browsing by active application
CREATE OR REPLACE VIEW v_web_browsing_by_app_summary AS
SELECT 
    active_app_during_visit as app_bundle_id,
    COUNT(DISTINCT domain) as unique_domains,
    COUNT(*) as total_visits,
    SUM(web_duration_seconds) / 60.0 as total_web_minutes,
    AVG(web_duration_seconds) as avg_visit_seconds
FROM v_web_usage_with_active_app
WHERE active_app_during_visit IS NOT NULL
GROUP BY active_app_during_visit;

-- Daily summary of app transition patterns
CREATE OR REPLACE VIEW v_daily_transition_summary AS
SELECT 
    transition_date,
    from_app,
    to_app,
    COUNT(*) as transition_count,
    AVG(gap_seconds) as avg_gap_seconds,
    COUNT(CASE WHEN transition_speed = 'instant' THEN 1 END) as instant_transitions,
    COUNT(CASE WHEN transition_speed = 'immediate' THEN 1 END) as immediate_transitions
FROM v_app_transitions
GROUP BY transition_date, from_app, to_app;

-- ============================================
-- PATTERN DETECTION VIEWS
-- ============================================

-- Detect "research sessions" - rapid switches between coding apps and Safari
CREATE OR REPLACE VIEW v_research_sessions AS
WITH safari_returns AS (
    SELECT 
        t1.from_app as coding_app,
        t1.transition_time as to_safari_time,
        t2.transition_time as back_from_safari_time,
        DATEPART('epoch', t2.transition_time - t1.transition_time) as safari_duration_seconds
    FROM v_app_transitions t1
    JOIN v_app_transitions t2 
        ON t1.to_app = 'com.apple.Safari'
        AND t2.from_app = 'com.apple.Safari'
        AND t2.to_app = t1.from_app
        AND t2.transition_time > t1.transition_time
        AND t2.transition_time < t1.transition_time + TO_SECONDS(600.0) -- Within 10 minutes
)
SELECT 
    coding_app,
    to_safari_time,
    back_from_safari_time,
    safari_duration_seconds,
    CASE 
        WHEN safari_duration_seconds < 30 THEN 'quick_lookup'
        WHEN safari_duration_seconds < 120 THEN 'short_research'
        WHEN safari_duration_seconds < 300 THEN 'medium_research'
        ELSE 'extended_research'
    END as research_type
FROM safari_returns;
