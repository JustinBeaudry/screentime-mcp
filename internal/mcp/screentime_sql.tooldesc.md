# Screen Time SQL Tool

Query macOS Screen Time data using DuckDB SQL. Access app usage, web browsing, notifications, and device activity from the Knowledge database.

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
```

## Available Data Sources

The Screen Time database contains rich activity data stored in these core tables:

- **ZOBJECT**: Main event table with timestamps, app bundle IDs, and stream types
- **ZSTRUCTUREDMETADATA**: Additional metadata like web domains, URLs, notification details
- **ZSOURCE**: Application source information

### Key Stream Types
- `/app/usage` - Application usage sessions with start/end times
- `/app/webUsage` - Web browsing activity with domains and URLs  
- `/notification/usage` - Notification events from apps
- `/app/mediaUsage` - Media playback tracking
- `/app/intents` - Siri shortcuts and app intents
- `/bluetooth/connection` - Bluetooth device connections
- `/app/install` - App installation/removal events

### 📊 Important Note About Views
The database views mentioned in this documentation may not be available by default. All queries should use the raw tables (ZOBJECT, ZSTRUCTUREDMETADATA) with proper JOIN operations and timestamp conversions as shown in the examples below.

## Common Queries

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
-- Compare this week to last week (using raw tables)
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

### Hourly Activity Pattern
```sql
-- See your activity patterns by hour today
SELECT 
    EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '31 years')) as hour_of_day,
    ZVALUESTRING as app_bundle_id,
    COUNT(*) as sessions,
    ROUND(SUM(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0, 1) as total_minutes
FROM ZOBJECT 
WHERE ZSTREAMNAME = '/app/usage' 
  AND ZVALUESTRING IS NOT NULL
  AND DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE
  AND ZVALUESTRING IN ('com.microsoft.VSCode', 'com.apple.Safari', 'com.mitchellh.ghostty')
GROUP BY EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '31 years')), ZVALUESTRING
ORDER BY hour_of_day, total_minutes DESC;
```

### Focus Sessions Analysis
```sql
-- Find your deep work sessions (10+ minutes continuous)
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
-- Find frequently used but brief apps (using raw tables)
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

### Web Browsing Analysis
```sql
-- Top domains by category (manual categorization)
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
            WHEN domain LIKE '%youtube%' OR domain LIKE '%twitch%' OR domain LIKE '%facebook%' THEN 'Entertainment'
            WHEN domain LIKE '%google%' OR domain LIKE '%news%' THEN 'Search/News'
            WHEN domain LIKE '%amazon%' OR domain LIKE '%costco%' OR domain LIKE '%shop%' THEN 'Shopping'
            WHEN domain LIKE '%reddit%' OR domain LIKE '%news.ycombinator%' THEN 'Social/Forums'
            WHEN domain LIKE '%anthropic%' OR domain LIKE '%openai%' OR domain LIKE '%claude%' THEN 'AI/Work'
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

-- Hourly web browsing patterns
SELECT 
    EXTRACT(HOUR FROM (zo.ZSTARTDATE + INTERVAL '31 years')) as hour_of_day,
    COUNT(*) as sessions,
    ROUND(SUM(EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) / 60.0, 1) as total_minutes
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/webUsage'
  AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '7 days'
  AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL
GROUP BY EXTRACT(HOUR FROM (zo.ZSTARTDATE + INTERVAL '31 years'))
ORDER BY hour_of_day;
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
-- Find common app sequences (using raw tables with window functions)
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

## Tips

### Time Ranges
- `CURRENT_DATE - INTERVAL '7 days'` - Last week
- `DATE_TRUNC('week', usage_date)` - Week grouping
- `EXTRACT(HOUR FROM start_time)` - Hour of day

### Filtering
- `WHERE usage_date >= CURRENT_DATE - INTERVAL '30 days'`
- `WHERE app_bundle_id LIKE '%chrome%'`
- `HAVING SUM(duration_minutes) >= 60`

### Aggregations
- `COUNT(DISTINCT app_bundle_id)` - Unique apps
- `ROUND(SUM(duration_minutes), 0)` - Readable totals
- `STRING_AGG(app_bundle_id, ', ')` - Lists

## Raw Tables and Timestamp Handling

### Core Tables
- **ZOBJECT**: Main event table (timestamps, values, stream names)
- **ZSTRUCTUREDMETADATA**: Event metadata (titles, URLs, etc.)  
- **ZSOURCE**: Application source information

### Important: Apple Core Data Timestamps
Apple stores timestamps as seconds since 2001-01-01 00:00:00 UTC (not Unix epoch). To get proper dates, add 31 years:

```sql
-- Convert Apple timestamp to proper date
ZSTARTDATE + INTERVAL '31 years' as start_time

-- Filter by today's date
DATE(ZSTARTDATE + INTERVAL '31 years') = CURRENT_DATE

-- Extract hour of day
EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '31 years')) as hour_of_day
```

### Duration Calculations
```sql
-- Calculate session duration in seconds
EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE) as duration_seconds

-- Convert to minutes
(EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0 as duration_minutes
```