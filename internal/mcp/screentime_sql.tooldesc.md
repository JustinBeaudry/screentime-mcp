# Screen Time SQL Tool

Query macOS Screen Time data (CoreDuet knowledge store) using DuckDB SQL. Access app usage, web browsing, notifications, and device activity from the Knowledge database.

## When to Use
- User asks about Mac app usage, screen time, or digital habits
- Questions about time spent in specific apps or categories
- Analyzing productivity patterns or app usage trends
- Investigating notification/distraction patterns
- Queries about device usage history
- Personal productivity coaching and focus improvement
- Identifying context-switching costs and work fragmentation
- Detecting flow states and optimal work periods

## Quick Start

```sql
-- What did I use today?
SELECT 
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as sessions,
    ROUND(SUM(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0, 1) as total_minutes
FROM ZOBJECT 
WHERE ZSTREAMNAME = '/app/usage' 
  AND ZVALUESTRING IS NOT NULL
  AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
GROUP BY ZVALUESTRING
ORDER BY total_minutes DESC;

-- What websites did I visit today?
SELECT 
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
    COUNT(*) as visits,
    ROUND(SUM(EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) / 60.0, 1) as total_minutes
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/webUsage'
  AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
  AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
GROUP BY sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN
ORDER BY total_minutes DESC;

-- How many notifications did I get today?
SELECT 
    sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID as app_bundle_id,
    COUNT(*) as notification_count
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/notification/usage'
  AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
  AND sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID IS NOT NULL
GROUP BY sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID
ORDER BY notification_count DESC;

-- Analyze my focus patterns and distractions today
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        COUNT(*) as sessions,
        ROUND(AVG((EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0), 1) as avg_duration_min,
        ROUND(SUM((EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0), 1) as total_minutes
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
      AND ZVALUESTRING IS NOT NULL
    GROUP BY ZVALUESTRING
)
SELECT 
    app_bundle_id,
    sessions,
    avg_duration_min,
    total_minutes,
    CASE 
        WHEN sessions >= 10 AND avg_duration_min < 5 THEN 'High Distraction'
        WHEN sessions >= 5 AND avg_duration_min < 10 THEN 'Moderate Distraction'
        WHEN avg_duration_min >= 15 THEN 'Focused Work'
        ELSE 'Mixed Pattern'
    END as focus_pattern
FROM app_sessions
WHERE total_minutes > 5
ORDER BY sessions DESC;

-- Track my context switching between apps
WITH app_sequences AS (
    SELECT 
        ZVALUESTRING as current_app,
        LEAD(ZVALUESTRING, 1) OVER (ORDER BY ZSTARTDATE) as next_app,
        (EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0 as duration_before_switch
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
      AND ZVALUESTRING IS NOT NULL
)
SELECT 
    current_app,
    next_app,
    COUNT(*) as switch_count,
    ROUND(AVG(duration_before_switch), 1) as avg_duration_before_switch
FROM app_sequences
WHERE current_app != next_app 
  AND next_app IS NOT NULL
GROUP BY current_app, next_app
HAVING COUNT(*) >= 3
ORDER BY switch_count DESC;
```

## Core Tables

### ZOBJECT - Main Events Table
- `Z_PK`: Primary key
- `ZSTREAMNAME`: Event type ('/app/usage', '/app/webUsage', '/app/inFocus', etc.)
- `ZVALUESTRING`: App bundle IDs or other identifiers
- `ZSTARTDATE/ZENDDATE`: Event timestamps (Core Data format - add 31 years!)
- `ZSOURCE`: Foreign key to ZSOURCE table
- `ZSTRUCTUREDMETADATA`: Foreign key to metadata table

### ZSTRUCTUREDMETADATA - Event Metadata
- `Z_PK`: Primary key
- `Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN`: Website domains
- `Z_DKDIGITALHEALTHMETADATAKEY__WEBPAGEURL`: Full URLs
- `Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID`: App sending notifications
- `Z_DKBULLETINBOARDMETADATAKEY__TITLE/MESSAGE`: Notification content
- Many other metadata fields for different event types

### ZSOURCE - Application Information
- `Z_PK`: Primary key
- `ZBUNDLEID`: App bundle identifier
- `ZSOURCEID`: Source identifier
- `ZDEVICEID`: Device identifier

## Key Stream Types
- `/app/usage` - Application usage sessions with start/end times
- `/app/webUsage` - Web browsing activity with domains and URLs  
- `/app/inFocus` - App focus events
- `/notification/usage` - Notification events from apps
- `/app/mediaUsage` - Media playback tracking
- `/app/intents` - Siri shortcuts and app intents
- `/bluetooth/connection` - Bluetooth device connections
- `/app/install` - App installation/removal events
- `/discoverability/signals` - Various user interaction signals

## User Timezone
 - `timestamp` - UNIX Time when the timezone was recorded
 - `location` - IANA Location
 - `timezone` - Location information
 - `utc_offset_seconds` - seconds adjustment from UTC
 - `is_dst` - True if daylight savings is active
 - `is_weekend` - True if the timestamp is a weekend
 - `day_of_week` - True if the timestamp is a day of the week

## Important: Timestamp Handling

Apple Core Data stores timestamps as seconds since 2001-01-01 00:00:00 UTC (not Unix epoch). Always add 31 years:

```sql
-- Convert Apple timestamp to proper date
ZSTARTDATE + INTERVAL '31 years' as start_time

-- Filter by today's date
DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE

-- Extract hour of day
EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '31 years')) as hour_of_day

-- Calculate duration in minutes
(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0 as duration_minutes
```

## Available Views (if created)

### Basic Usage Views
- `v_app_usage` - App usage with corrected timestamps
- `v_web_usage` - Web browsing data
- `v_notifications` - Notification events
- `v_app_focus` - Focus events
- `v_stream_names` - Available data streams

### Daily Summary Views
- `v_today_summary` - Today's app usage summary
- `v_today_web_summary` - Today's web browsing
- `v_daily_app_summary` - Historical daily summaries
- `v_daily_focus_metrics` - Focus scores by day

### Temporal Analysis Views
- `v_app_timeline` - Apps with epoch timestamps
- `v_app_transitions` - App-to-app switching patterns
- `v_app_switches` - Detailed switch analysis
- `v_safari_transitions` - Transitions to Safari
- `v_web_usage_with_active_app` - Web visits correlated with active app

### Pattern Detection Views
- `v_research_sessions` - Coding research patterns
- `v_focus_sessions` - Extended focus periods
- `v_post_transition_web_activity` - Web activity after app switches

### Convenience Views
- `v_today_usage` - Today's detailed usage
- `v_yesterday_usage` - Yesterday's usage
- `v_week_usage` - Last 7 days
- `v_month_usage` - Last 30 days

Note: Views may not be available by default. Use raw table queries with JOINs as shown in examples.

## Common Query Patterns

### Daily Dashboard
```sql
-- Today's app usage with basic categorization
WITH app_usage_today AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        COUNT(*) as sessions,
        ROUND(SUM(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0, 1) as total_minutes
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
    GROUP BY ZVALUESTRING
),
categorized AS (
    SELECT 
        app_bundle_id,
        sessions,
        total_minutes,
        CASE 
            WHEN app_bundle_id LIKE '%VSCode%' OR app_bundle_id LIKE '%terminal%' OR app_bundle_id LIKE '%ghostty%' THEN 'Development'
            WHEN app_bundle_id LIKE '%Safari%' OR app_bundle_id LIKE '%Chrome%' THEN 'Web Browsing'
            WHEN app_bundle_id LIKE '%Slack%' OR app_bundle_id LIKE '%Discord%' OR app_bundle_id LIKE '%MobileSMS%' THEN 'Communication'
            ELSE 'Other'
        END as category
    FROM app_usage_today
)
SELECT 
    category,
    COUNT(*) as apps,
    SUM(sessions) as total_sessions,
    ROUND(SUM(total_minutes), 1) as total_minutes
FROM categorized
GROUP BY category
ORDER BY total_minutes DESC;
```

### Weekly Comparison
```sql
-- Compare this week to last week
WITH weekly AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        SUM(CASE WHEN DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days' 
            THEN EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE) ELSE 0 END) / 60.0 as this_week,
        SUM(CASE WHEN DATE(ZSTARTDATE + INTERVAL '31 years') < CURRENT_DATE - INTERVAL '7 days' 
            AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '14 days'
            THEN EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE) ELSE 0 END) / 60.0 as last_week
    FROM ZOBJECT
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY ZVALUESTRING
)
SELECT 
    app_bundle_id,
    ROUND(this_week, 0) as this_week_min,
    ROUND(last_week, 0) as last_week_min,
    ROUND(this_week - last_week, 0) as change
FROM weekly
WHERE this_week > 30 OR last_week > 30
ORDER BY ABS(this_week - last_week) DESC
LIMIT 10;
```

### Focus Sessions Analysis
```sql
-- Find deep work sessions (15+ minutes continuous)
SELECT 
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + INTERVAL '31 years' as start_time,
    ZENDDATE + INTERVAL '31 years' as end_time,
    ROUND((EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0, 1) as duration_minutes,
    CASE 
        WHEN (EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) >= 1800 THEN 'Deep Focus (30+ min)'
        WHEN (EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) >= 900 THEN 'Moderate Focus (15+ min)'
        ELSE 'Light Focus (10+ min)'
    END as focus_level
FROM ZOBJECT 
WHERE ZSTREAMNAME = '/app/usage' 
  AND ZVALUESTRING IS NOT NULL
  AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
  AND (EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) >= 600  -- 10+ minutes
ORDER BY duration_minutes DESC;
```

### Distraction Detection
```sql
-- Find frequently used but brief apps
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        COUNT(*) as sessions,
        AVG(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) as avg_seconds
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY ZVALUESTRING
)
SELECT 
    app_bundle_id,
    sessions,
    ROUND(avg_seconds, 0) as avg_seconds
FROM app_sessions
WHERE sessions >= 20 AND avg_seconds < 60
ORDER BY sessions DESC;
```

### Personal Productivity Coaching Examples
```sql
-- Identify your optimal work hours based on flow states
SELECT 
    start_hour,
    COUNT(*) as flow_sessions,
    ROUND(AVG(duration_minutes), 1) as avg_flow_duration,
    STRING_AGG(DISTINCT app_bundle_id, ', ') as apps_used
FROM v_flow_state_detection
WHERE flow_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY start_hour
HAVING COUNT(*) >= 3
ORDER BY avg_flow_duration DESC;

-- Measure context switching cost by hour
SELECT 
    hour_of_day,
    AVG(switches_in_hour) as avg_switches,
    AVG(micro_sessions) as avg_micro_sessions,
    AVG(context_switch_cost_score) as avg_cost_score,
    MAX(switching_intensity) as typical_intensity
FROM v_context_switching_cost
WHERE switch_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY hour_of_day
ORDER BY avg_cost_score DESC;

-- Track work fragmentation patterns
SELECT 
    work_date,
    SUM(fragment_sessions) as total_fragments,
    ROUND(AVG(fragmentation_percent), 1) as avg_fragmentation,
    SUM(pomodoro_sessions) as completed_pomodoros,
    ROUND(SUM(effective_work_score), 1) as daily_effectiveness
FROM v_work_fragmentation
WHERE work_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY work_date
ORDER BY work_date DESC;
```

### Web Browsing Analysis
```sql
-- Top domains by category with comprehensive categorization
WITH web_usage AS (
    SELECT 
        sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
        COUNT(*) as visits,
        ROUND(SUM(EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) / 60.0, 1) as total_minutes
    FROM ZOBJECT zo
    JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
    WHERE zo.ZSTREAMNAME = '/app/webUsage'
      AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
      AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
    GROUP BY sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN
),
categorized AS (
    SELECT 
        domain,
        visits,
        total_minutes,
        CASE 
            WHEN domain LIKE '%github%' OR domain LIKE '%stackoverflow%' OR domain LIKE '%docs.%' THEN 'Development'
            WHEN domain LIKE '%youtube%' OR domain LIKE '%twitch%' OR domain LIKE '%netflix%' THEN 'Entertainment'
            WHEN domain LIKE '%google%' OR domain LIKE '%bing%' OR domain LIKE '%duckduckgo%' THEN 'Search'
            WHEN domain LIKE '%news%' OR domain LIKE '%cnn%' OR domain LIKE '%bbc%' THEN 'News'
            WHEN domain LIKE '%amazon%' OR domain LIKE '%ebay%' OR domain LIKE '%shop%' THEN 'Shopping'
            WHEN domain LIKE '%reddit%' OR domain LIKE '%news.ycombinator%' THEN 'Social/Forums'
            WHEN domain LIKE '%anthropic%' OR domain LIKE '%openai%' OR domain LIKE '%claude%' THEN 'AI/ML'
            WHEN domain LIKE '%facebook%' OR domain LIKE '%twitter%' OR domain LIKE '%linkedin%' THEN 'Social Media'
            ELSE 'Other'
        END as category
    FROM web_usage
    WHERE total_minutes >= 5
)
SELECT 
    category,
    COUNT(*) as unique_domains,
    SUM(visits) as total_visits,
    ROUND(SUM(total_minutes), 1) as total_minutes
FROM categorized
GROUP BY category
ORDER BY total_minutes DESC;
```

### Notification Analysis
```sql
-- Most distracting apps by notification count
SELECT 
    sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID as app_bundle_id,
    COUNT(*) as total_notifications,
    COUNT(DISTINCT DATE(zo.ZSTARTDATE + INTERVAL '31 years')) as days_active,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT DATE(zo.ZSTARTDATE + INTERVAL '31 years')), 1) as daily_avg
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/notification/usage'
  AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
  AND sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID IS NOT NULL
GROUP BY sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID
ORDER BY total_notifications DESC
LIMIT 10;
```

## Advanced Patterns

### Workflow Detection
```sql
-- Find common app sequences (app switching patterns)
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        ZSTARTDATE + INTERVAL '31 years' as start_time,
        DATE(ZSTARTDATE + INTERVAL '31 years') as usage_date
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
),
sequences AS (
    SELECT 
        app_bundle_id as app1,
        LEAD(app_bundle_id, 1) OVER (PARTITION BY usage_date ORDER BY start_time) as app2,
        usage_date
    FROM app_sessions
)
SELECT 
    app1, app2,
    COUNT(*) as occurrences
FROM sequences
WHERE app1 IS NOT NULL AND app2 IS NOT NULL AND app1 != app2
GROUP BY app1, app2
HAVING COUNT(*) >= 5
ORDER BY occurrences DESC
LIMIT 20;
```

### Research Sessions Detection
```sql
-- Find coding research patterns (VSCode → Safari → VSCode)
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        ZSTARTDATE + INTERVAL '31 years' as start_time,
        ZENDDATE + INTERVAL '31 years' as end_time,
        DATE(ZSTARTDATE + INTERVAL '31 years') as usage_date,
        ROW_NUMBER() OVER (PARTITION BY DATE(ZSTARTDATE + INTERVAL '31 years') ORDER BY ZSTARTDATE) as session_order
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
)
SELECT 
    a1.app_bundle_id as coding_app,
    a2.app_bundle_id as browser_app,
    COUNT(*) as research_sessions,
    ROUND(AVG(EXTRACT(EPOCH FROM a2.end_time) - EXTRACT(EPOCH FROM a2.start_time)) / 60.0, 1) as avg_research_minutes
FROM app_sessions a1
JOIN app_sessions a2 ON a1.usage_date = a2.usage_date 
    AND a1.session_order + 1 = a2.session_order
JOIN app_sessions a3 ON a2.usage_date = a3.usage_date 
    AND a2.session_order + 1 = a3.session_order
WHERE a1.app_bundle_id LIKE '%VSCode%'
  AND a2.app_bundle_id LIKE '%Safari%'
  AND a3.app_bundle_id LIKE '%VSCode%'
GROUP BY a1.app_bundle_id, a2.app_bundle_id
ORDER BY research_sessions DESC;
```

### Web Usage During App Sessions
```sql
-- Find web browsing during VSCode usage
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        ZSTARTDATE + INTERVAL '31 years' as app_start,
        ZENDDATE + INTERVAL '31 years' as app_end
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING = 'com.microsoft.VSCode'
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
),
web_sessions AS (
    SELECT 
        sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
        zo.ZSTARTDATE + INTERVAL '31 years' as web_start,
        zo.ZENDDATE + INTERVAL '31 years' as web_end
    FROM ZOBJECT zo
    JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
    WHERE zo.ZSTREAMNAME = '/app/webUsage'
      AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
      AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
)
SELECT 
    w.domain,
    COUNT(*) as visits_during_vscode,
    ROUND(SUM(EXTRACT(EPOCH FROM w.web_end) - EXTRACT(EPOCH FROM w.web_start)) / 60.0, 1) as minutes
FROM web_sessions w
JOIN app_sessions a ON w.web_start >= a.app_start AND w.web_end <= a.app_end
GROUP BY w.domain
ORDER BY visits_during_vscode DESC;
```

## SQL Syntax Notes

### DuckDB-Specific Functions
- Use `EXTRACT(HOUR FROM timestamp)` not `strftime` for hour extraction
- Use `EXTRACT(EPOCH FROM (end - start))` for duration calculations
- Use `DATE(timestamp)` for date extraction
- Use `DATE_TRUNC('week', date)` for week grouping
- Use `INTERVAL` arithmetic for date math

### Best Practices
- Always handle NULLs explicitly in duration calculations
- Use CASE statements for conditional logic
- Cast types explicitly when needed
- Test timestamp comparisons with ORDER BY and LIMIT first
- Use CTEs (WITH clauses) for complex queries

### Common Filters
- `WHERE usage_date >= CURRENT_DATE - INTERVAL '30 days'`
- `WHERE app_bundle_id LIKE '%chrome%'`
- `HAVING SUM(duration_minutes) >= 60`
- `WHERE ZVALUESTRING IS NOT NULL`

### Useful Aggregations
- `COUNT(DISTINCT app_bundle_id)` - Unique apps
- `ROUND(SUM(duration_minutes), 1)` - Readable totals
- `STRING_AGG(app_bundle_id, ', ')` - Comma-separated lists
- `AVG(duration_seconds)` - Average durations

## Error Prevention Tips
- **Always use proper DuckDB syntax** - no MySQL/SQLite specific functions
- **Add 31 years to timestamps** - Core Data offset issue
- **Check for NULL values** in ZVALUESTRING and metadata fields
- **Use proper JOIN syntax** - JOIN table ON condition (not USING)
- **Handle timezone considerations** - timestamps are in UTC
- **Verify stream names exist** before filtering

## Limitations
- Read-only SELECT queries only
- Data availability depends on user's Screen Time settings
- Some fields contain binary data (BLOB) requiring interpretation
- Complex metadata stored in structured format requiring joins
- Views may not be available - use raw table queries

## Performance Tips
- Filter by date range early in WHERE clause
- Use indexes on ZSTARTDATE when filtering by date
- Limit result sets with LIMIT when exploring
- Use CTEs to break complex queries into steps
- Aggregate in subqueries before joining