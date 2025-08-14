-- Core Views: Raw data access with proper timestamp conversion
-- Apple Core Data timestamps are seconds since 2001-01-01, so we add 31 years

-- App Usage View
CREATE OR REPLACE VIEW v_app_usage AS
SELECT 
    Z_PK as id,
    ZVALUESTRING as app_bundle_id,
    ZSTARTDATE + INTERVAL '31 years' as start_time,
    ZENDDATE + INTERVAL '31 years' as end_time,
    DATE(ZSTARTDATE + INTERVAL '31 years') as usage_date,
    epoch(ZENDDATE) - epoch(ZSTARTDATE) as duration_seconds,
    (epoch(ZENDDATE) - epoch(ZSTARTDATE)) / 60.0 as duration_minutes,
    hour((ZSTARTDATE + INTERVAL '31 years')) as hour_of_day,
    CASE 
        WHEN (epoch(ZENDDATE) - epoch(ZSTARTDATE)) >= 900 THEN 'deep_focus'
        WHEN (epoch(ZENDDATE) - epoch(ZSTARTDATE)) >= 600 THEN 'moderate_focus'
        WHEN (epoch(ZENDDATE) - epoch(ZSTARTDATE)) >= 300 THEN 'light_focus'
        ELSE 'brief'
    END as focus_level
FROM ZOBJECT 
WHERE ZSTREAMNAME = '/app/usage' 
  AND ZVALUESTRING IS NOT NULL;

-- Web Usage View
CREATE OR REPLACE VIEW v_web_usage AS
SELECT 
    zo.Z_PK as id,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN as domain,
    sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBPAGEURL as url,
    zo.ZSTARTDATE + INTERVAL '31 years' as start_time,
    zo.ZENDDATE + INTERVAL '31 years' as end_time,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as usage_date,
    epoch(zo.ZENDDATE) - epoch(zo.ZSTARTDATE) as duration_seconds,
    (epoch(zo.ZENDDATE) - epoch(zo.ZSTARTDATE)) / 60.0 as duration_minutes,
    hour((zo.ZSTARTDATE + INTERVAL '31 years')) as hour_of_day
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/webUsage'
  AND sm.Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL;

-- Notifications View
CREATE OR REPLACE VIEW v_notifications AS
SELECT 
    zo.Z_PK as id,
    sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID as app_bundle_id,
    sm.Z_DKBULLETINBOARDMETADATAKEY__TITLE as title,
    sm.Z_DKBULLETINBOARDMETADATAKEY__MESSAGE as message,
    zo.ZSTARTDATE + INTERVAL '31 years' as notification_time,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as notification_date,
    hour((zo.ZSTARTDATE + INTERVAL '31 years')) as hour_of_day
FROM ZOBJECT zo
JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/notification/usage'
  AND sm.Z_DKNOTIFICATIONUSAGEMETADATAKEY__BUNDLEID IS NOT NULL;

-- Media Usage View
CREATE OR REPLACE VIEW v_media_usage AS
SELECT 
    zo.Z_PK as id,
    zo.ZVALUESTRING as app_bundle_id,
    sm.Z_DKAPPMEDIAUSAGEMETADATAKEY__MEDIAURL as media_url,
    zo.ZSTARTDATE + INTERVAL '31 years' as start_time,
    zo.ZENDDATE + INTERVAL '31 years' as end_time,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as usage_date,
    epoch(zo.ZENDDATE) - epoch(zo.ZSTARTDATE) as duration_seconds,
    (epoch(zo.ZENDDATE) - epoch(zo.ZSTARTDATE)) / 60.0 as duration_minutes
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/mediaUsage'
  AND zo.ZVALUESTRING IS NOT NULL;

-- Now Playing View
CREATE OR REPLACE VIEW v_now_playing AS
SELECT 
    zo.Z_PK as id,
    zo.ZVALUESTRING as app_bundle_id,
    sm.Z_DKNOWPLAYINGMETADATAKEY__TITLE as title,
    sm.Z_DKNOWPLAYINGMETADATAKEY__ARTIST as artist,
    sm.Z_DKNOWPLAYINGMETADATAKEY__ALBUM as album,
    sm.Z_DKNOWPLAYINGMETADATAKEY__GENRE as genre,
    sm.Z_DKNOWPLAYINGMETADATAKEY__PLAYING as is_playing,
    sm.Z_DKNOWPLAYINGMETADATAKEY__DURATION as duration_seconds,
    sm.Z_DKNOWPLAYINGMETADATAKEY__ELAPSED as elapsed_seconds,
    zo.ZSTARTDATE + INTERVAL '31 years' as timestamp
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/media/nowPlaying'
  AND zo.ZVALUESTRING IS NOT NULL;

-- Intent Usage View (Siri shortcuts, app intents)
CREATE OR REPLACE VIEW v_intents AS
SELECT 
    zo.Z_PK as id,
    zo.ZVALUESTRING as app_bundle_id,
    sm.Z_DKINTENTMETADATAKEY__INTENTCLASS as intent_class,
    sm.Z_DKINTENTMETADATAKEY__INTENTVERB as intent_verb,
    sm.Z_DKINTENTMETADATAKEY__DIRECTION as direction,
    zo.ZSTARTDATE + INTERVAL '31 years' as timestamp,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as usage_date
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/intents'
  AND zo.ZVALUESTRING IS NOT NULL;

-- Summary Views: Daily and weekly aggregations

-- Daily App Summary
CREATE OR REPLACE VIEW v_daily_app_summary AS
SELECT 
    usage_date,
    app_bundle_id,
    COUNT(*) as sessions,
    ROUND(SUM(duration_minutes), 1) as total_minutes,
    ROUND(SUM(duration_minutes) / 60.0, 1) as total_hours,
    ROUND(AVG(duration_minutes), 1) as avg_session_minutes,
    COUNT(CASE WHEN focus_level IN ('light_focus', 'moderate_focus', 'deep_focus') THEN 1 END) as focus_sessions,
    MIN(start_time) as first_use,
    MAX(end_time) as last_use
FROM v_app_usage
GROUP BY usage_date, app_bundle_id;

-- Top Apps Today
CREATE OR REPLACE VIEW v_top_apps_today AS
SELECT 
    app_bundle_id,
    sessions,
    total_minutes,
    total_hours,
    focus_sessions,
    ROUND(100.0 * total_minutes / NULLIF(SUM(total_minutes) OVER (), 0), 1) as percentage_of_day
FROM v_daily_app_summary
WHERE usage_date = CURRENT_DATE
ORDER BY total_minutes DESC;

-- Weekly App Summary
CREATE OR REPLACE VIEW v_weekly_app_summary AS
SELECT 
    DATE_TRUNC('week', usage_date) as week_start,
    app_bundle_id,
    COUNT(DISTINCT usage_date) as days_used,
    SUM(sessions) as total_sessions,
    ROUND(SUM(total_minutes), 1) as total_minutes,
    ROUND(SUM(total_minutes) / 60.0, 1) as total_hours,
    ROUND(AVG(total_minutes), 1) as avg_daily_minutes
FROM v_daily_app_summary
GROUP BY DATE_TRUNC('week', usage_date), app_bundle_id;

-- Hourly Usage Patterns
CREATE OR REPLACE VIEW v_hourly_usage_pattern AS
SELECT 
    hour_of_day,
    app_bundle_id,
    COUNT(*) as sessions,
    ROUND(SUM(duration_minutes), 1) as total_minutes,
    ROUND(AVG(duration_minutes), 1) as avg_session_minutes
FROM v_app_usage
WHERE usage_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY hour_of_day, app_bundle_id
ORDER BY hour_of_day, total_minutes DESC;

-- Daily Screen Time Total
CREATE OR REPLACE VIEW v_daily_screen_time AS
SELECT 
    usage_date,
    ROUND(SUM(total_minutes), 1) as total_screen_minutes,
    ROUND(SUM(total_minutes) / 60.0, 1) as total_screen_hours,
    COUNT(DISTINCT app_bundle_id) as unique_apps_used,
    SUM(sessions) as total_sessions
FROM v_daily_app_summary
GROUP BY usage_date
ORDER BY usage_date DESC;

-- Daily Notification Summary
CREATE OR REPLACE VIEW v_daily_notifications AS
SELECT 
    notification_date,
    app_bundle_id,
    COUNT(*) as notification_count,
    MIN(notification_time) as first_notification,
    MAX(notification_time) as last_notification
FROM v_notifications
GROUP BY notification_date, app_bundle_id;

-- Analysis Views: Patterns and insights

-- App Categories (basic categorization)
CREATE OR REPLACE VIEW v_app_categories AS
SELECT 
    app_bundle_id,
    CASE 
        WHEN contains(app_bundle_id, 'VSCode') OR contains(app_bundle_id, 'xcode') OR contains(app_bundle_id, 'terminal') OR contains(app_bundle_id, 'ghostty') OR contains(app_bundle_id, 'git') THEN 'Development'
        WHEN contains(app_bundle_id, 'Safari') OR contains(app_bundle_id, 'Chrome') OR contains(app_bundle_id, 'Firefox') OR contains(app_bundle_id, 'Edge') THEN 'Web Browsing'
        WHEN contains(app_bundle_id, 'Slack') OR contains(app_bundle_id, 'Discord') OR contains(app_bundle_id, 'MobileSMS') OR contains(app_bundle_id, 'airmail') OR contains(app_bundle_id, 'Mail') THEN 'Communication'
        WHEN contains(app_bundle_id, 'music') OR contains(app_bundle_id, 'spotify') OR contains(app_bundle_id, 'youtube') OR contains(app_bundle_id, 'netflix') THEN 'Entertainment'
        WHEN contains(app_bundle_id, 'Notes') OR contains(app_bundle_id, 'TextEdit') OR contains(app_bundle_id, 'Pages') OR contains(app_bundle_id, 'Word') THEN 'Productivity'
        WHEN contains(app_bundle_id, 'Photoshop') OR contains(app_bundle_id, 'Figma') OR contains(app_bundle_id, 'Sketch') OR contains(app_bundle_id, 'bambu') THEN 'Creative'
        WHEN contains(app_bundle_id, 'iCal') OR contains(app_bundle_id, 'Calendar') OR contains(app_bundle_id, 'Reminder') THEN 'Organization'
        ELSE 'Other'
    END as category
FROM (
    SELECT DISTINCT app_bundle_id 
    FROM v_app_usage
);

-- Category Usage Summary
CREATE OR REPLACE VIEW v_category_usage_summary AS
SELECT 
    das.usage_date,
    ac.category,
    COUNT(DISTINCT das.app_bundle_id) as unique_apps,
    SUM(das.sessions) as total_sessions,
    ROUND(SUM(das.total_minutes), 1) as total_minutes,
    ROUND(SUM(das.total_minutes) / 60.0, 1) as total_hours
FROM v_daily_app_summary das
JOIN v_app_categories ac ON das.app_bundle_id = ac.app_bundle_id
GROUP BY das.usage_date, ac.category;

-- Focus Sessions (extended app usage)
CREATE OR REPLACE VIEW v_focus_sessions AS
SELECT 
    usage_date as focus_date,
    app_bundle_id,
    start_time,
    end_time,
    duration_minutes as total_focus_minutes,
    focus_level
FROM v_app_usage
WHERE duration_seconds >= 300  -- 5+ minutes
ORDER BY duration_seconds DESC;

-- App Transitions (switching patterns)
CREATE OR REPLACE VIEW v_app_transitions AS
SELECT 
    usage_date,
    app_bundle_id as from_app,
    LEAD(app_bundle_id, 1) OVER (PARTITION BY usage_date ORDER BY start_time) as to_app,
    start_time as transition_time,
    epoch((LEAD(start_time, 1) OVER (PARTITION BY usage_date ORDER BY start_time) - end_time)) as gap_seconds
FROM v_app_usage
WHERE usage_date >= CURRENT_DATE - INTERVAL '7 days';

-- Daily Productivity Score (based on categories)
CREATE OR REPLACE VIEW v_daily_productivity_score AS
SELECT 
    usage_date,
    ROUND(SUM(CASE WHEN category IN ('Development', 'Productivity', 'Creative') THEN total_minutes ELSE 0 END), 1) as productive_minutes,
    ROUND(SUM(CASE WHEN category NOT IN ('Development', 'Productivity', 'Creative') THEN total_minutes ELSE 0 END), 1) as non_productive_minutes,
    ROUND(SUM(total_minutes), 1) as total_minutes,
    ROUND(100.0 * SUM(CASE WHEN category IN ('Development', 'Productivity', 'Creative') THEN total_minutes ELSE 0 END) / NULLIF(SUM(total_minutes), 0), 1) as productivity_percentage
FROM v_category_usage_summary
GROUP BY usage_date
ORDER BY usage_date DESC;

-- Web Views: Web browsing analysis

-- Web Categories (comprehensive domain categorization)
CREATE OR REPLACE VIEW v_web_categories AS
SELECT 
    domain,
    url,
    usage_date,
    duration_minutes,
    CASE 
        -- Development & Tech
        WHEN contains(domain, 'github') OR contains(domain, 'gitlab') OR contains(domain, 'bitbucket') 
            OR contains(domain, 'stackoverflow') OR contains(domain, 'stackexchange') 
            OR contains(domain, 'docs.') OR contains(domain, 'developer.') OR contains(domain, 'dev.')
            OR contains(domain, 'npm') OR contains(domain, 'pypi') OR contains(domain, 'crates.io')
            OR contains(domain, 'docker') OR contains(domain, 'kubernetes') OR contains(domain, 'aws')
            OR contains(domain, 'azure') OR contains(domain, 'gcp') OR contains(domain, 'cloudflare')
            OR contains(domain, 'python.org') OR contains(domain, 'golang') OR contains(domain, 'rust-lang')
            OR contains(domain, 'javascript') OR contains(domain, 'typescript') OR contains(domain, 'nodejs')
            OR contains(domain, 'reactjs') OR contains(domain, 'vuejs') OR contains(domain, 'angular')
            OR contains(domain, 'vercel') OR contains(domain, 'netlify') OR contains(domain, 'heroku')
            THEN 'Development'
            
        -- Entertainment & Media
        WHEN contains(domain, 'youtube') OR contains(domain, 'netflix') OR contains(domain, 'hulu')
            OR contains(domain, 'spotify') OR contains(domain, 'apple.com/music') OR contains(domain, 'soundcloud')
            OR contains(domain, 'twitch') OR contains(domain, 'disney') OR contains(domain, 'hbo')
            OR contains(domain, 'paramount') OR contains(domain, 'peacock') OR contains(domain, 'crunchyroll')
            OR contains(domain, 'tiktok') OR contains(domain, 'vimeo') OR contains(domain, 'dailymotion')
            OR contains(domain, 'podcasts') OR contains(domain, 'audible') OR contains(domain, 'kindle')
            THEN 'Entertainment'
            
        -- Search & Information
        WHEN contains(domain, 'google') OR contains(domain, 'bing') OR contains(domain, 'duckduckgo')
            OR contains(domain, 'yahoo') OR contains(domain, 'ask') OR contains(domain, 'baidu')
            OR contains(domain, 'yandex') OR contains(domain, 'ecosia') OR contains(domain, 'startpage')
            OR contains(domain, 'wikipedia') OR contains(domain, 'wikimedia') OR contains(domain, 'wiktionary')
            THEN 'Search/Reference'
            
        -- E-commerce & Shopping
        WHEN contains(domain, 'amazon') OR contains(domain, 'ebay') OR contains(domain, 'etsy')
            OR contains(domain, 'walmart') OR contains(domain, 'target') OR contains(domain, 'costco')
            OR contains(domain, 'bestbuy') OR contains(domain, 'newegg') OR contains(domain, 'microcenter')
            OR contains(domain, 'shopify') OR contains(domain, 'aliexpress') OR contains(domain, 'alibaba')
            OR contains(domain, 'shop') OR contains(domain, 'store') OR contains(domain, 'marketplace')
            OR contains(domain, 'payment') OR contains(domain, 'checkout') OR contains(domain, 'cart')
            THEN 'Shopping'
            
        -- Social Media & Forums
        WHEN contains(domain, 'facebook') OR contains(domain, 'instagram') OR contains(domain, 'twitter')
            OR contains(domain, 'linkedin') OR contains(domain, 'snapchat') OR contains(domain, 'pinterest')
            OR contains(domain, 'reddit') OR contains(domain, 'discord') OR contains(domain, 'slack')
            OR contains(domain, 'telegram') OR contains(domain, 'whatsapp') OR contains(domain, 'messenger')
            OR contains(domain, 'forums') OR contains(domain, 'community') OR contains(domain, 'discussion')
            OR contains(domain, 'news.ycombinator') OR contains(domain, 'hackernews')
            THEN 'Social/Forums'
            
        -- News & Current Events
        WHEN contains(domain, 'news') OR contains(domain, 'cnn') OR contains(domain, 'bbc')
            OR contains(domain, 'reuters') OR contains(domain, 'ap.org') OR contains(domain, 'npr')
            OR contains(domain, 'nytimes') OR contains(domain, 'washingtonpost') OR contains(domain, 'wsj')
            OR contains(domain, 'guardian') OR contains(domain, 'bloomberg') OR contains(domain, 'forbes')
            OR contains(domain, 'techcrunch') OR contains(domain, 'ars-technica') OR contains(domain, 'wired')
            OR contains(domain, 'theverge') OR contains(domain, 'engadget') OR contains(domain, 'gizmodo')
            THEN 'News'
            
        -- Finance & Banking
        WHEN contains(domain, 'bank') OR contains(domain, 'credit') OR contains(domain, 'finance')
            OR contains(domain, 'paypal') OR contains(domain, 'stripe') OR contains(domain, 'venmo')
            OR contains(domain, 'coinbase') OR contains(domain, 'binance') OR contains(domain, 'crypto')
            OR contains(domain, 'fidelity') OR contains(domain, 'schwab') OR contains(domain, 'vanguard')
            OR contains(domain, 'chase') OR contains(domain, 'wellsfargo') OR contains(domain, 'citibank')
            OR contains(domain, 'mint') OR contains(domain, 'quicken') OR contains(domain, 'turbotax')
            THEN 'Finance'
            
        -- Productivity & Work Tools
        WHEN contains(domain, 'notion') OR contains(domain, 'airtable') OR contains(domain, 'trello')
            OR contains(domain, 'asana') OR contains(domain, 'monday') OR contains(domain, 'jira')
            OR contains(domain, 'confluence') OR contains(domain, 'miro') OR contains(domain, 'figma')
            OR contains(domain, 'canva') OR contains(domain, 'adobe') OR contains(domain, 'office')
            OR contains(domain, 'docs.google') OR contains(domain, 'sheets.google') OR contains(domain, 'slides.google')
            OR contains(domain, 'dropbox') OR contains(domain, 'onedrive') OR contains(domain, 'icloud')
            OR contains(domain, 'zoom') OR contains(domain, 'teams') OR contains(domain, 'meet')
            THEN 'Productivity'
            
        -- Health & Fitness
        WHEN contains(domain, 'health') OR contains(domain, 'fitness') OR contains(domain, 'medical')
            OR contains(domain, 'webmd') OR contains(domain, 'mayo') OR contains(domain, 'healthcare')
            OR contains(domain, 'strava') OR contains(domain, 'fitbit') OR contains(domain, 'myfitnesspal')
            OR contains(domain, 'peloton') OR contains(domain, 'nike') OR contains(domain, 'adidas')
            OR contains(domain, 'yoga') OR contains(domain, 'meditation') OR contains(domain, 'mindfulness')
            THEN 'Health/Fitness'
            
        -- Education & Learning
        WHEN contains(domain, 'edu') OR contains(domain, 'coursera') OR contains(domain, 'udemy')
            OR contains(domain, 'khan') OR contains(domain, 'edx') OR contains(domain, 'pluralsight')
            OR contains(domain, 'lynda') OR contains(domain, 'skillshare') OR contains(domain, 'masterclass')
            OR contains(domain, 'duolingo') OR contains(domain, 'babbel') OR contains(domain, 'rosetta')
            OR contains(domain, 'school') OR contains(domain, 'university') OR contains(domain, 'college')
            THEN 'Education'
            
        -- Travel & Transportation
        WHEN contains(domain, 'booking') OR contains(domain, 'expedia') OR contains(domain, 'airbnb')
            OR contains(domain, 'hotels') OR contains(domain, 'trivago') OR contains(domain, 'kayak')
            OR contains(domain, 'uber') OR contains(domain, 'lyft') OR contains(domain, 'maps')
            OR contains(domain, 'flight') OR contains(domain, 'airline') OR contains(domain, 'airport')
            OR contains(domain, 'travel') OR contains(domain, 'trip') OR contains(domain, 'vacation')
            THEN 'Travel'
            
        -- Gaming
        WHEN contains(domain, 'steam') OR contains(domain, 'epic') OR contains(domain, 'origin')
            OR contains(domain, 'battle.net') OR contains(domain, 'riot') OR contains(domain, 'minecraft')
            OR contains(domain, 'roblox') OR contains(domain, 'fortnite') OR contains(domain, 'xbox')
            OR contains(domain, 'playstation') OR contains(domain, 'nintendo') OR contains(domain, 'gaming')
            OR contains(domain, 'twitch') OR contains(domain, 'ign') OR contains(domain, 'gamespot')
            THEN 'Gaming'
            
        -- AI & Machine Learning
        WHEN contains(domain, 'openai') OR contains(domain, 'anthropic') OR contains(domain, 'claude')
            OR contains(domain, 'chatgpt') OR contains(domain, 'huggingface') OR contains(domain, 'tensorflow')
            OR contains(domain, 'pytorch') OR contains(domain, 'kaggle') OR contains(domain, 'colab')
            OR contains(domain, 'jupyter') OR contains(domain, 'databricks') OR contains(domain, 'mlflow')
            THEN 'AI/ML'
            
        ELSE 'Other'
    END as web_category
FROM v_web_usage;

-- Daily Web Usage by Category
CREATE OR REPLACE VIEW v_daily_web_summary AS
SELECT 
    usage_date,
    web_category,
    COUNT(*) as visits,
    COUNT(DISTINCT domain) as unique_domains,
    ROUND(SUM(duration_minutes), 1) as total_minutes
FROM v_web_categories
GROUP BY usage_date, web_category;

-- Hourly Web Browsing Patterns
CREATE OR REPLACE VIEW v_hourly_web_pattern AS
SELECT 
    hour_of_day,
    COUNT(*) as sessions,
    ROUND(SUM(duration_minutes), 1) as total_minutes,
    COUNT(DISTINCT domain) as unique_domains,
    ROUND(AVG(duration_minutes), 1) as avg_session_minutes
FROM v_web_usage
WHERE usage_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Additional Views: Bluetooth, location, etc.

-- Bluetooth Devices
CREATE OR REPLACE VIEW v_bluetooth_devices AS
SELECT 
    zo.Z_PK as id,
    sm.Z_DKBLUETOOTHMETADATAKEY__NAME as device_name,
    sm.Z_DKBLUETOOTHMETADATAKEY__ADDRESS as device_address,
    sm.Z_DKBLUETOOTHMETADATAKEY__DEVICETYPE as device_type,
    zo.ZSTARTDATE + INTERVAL '31 years' as connection_time,
    zo.ZENDDATE + INTERVAL '31 years' as disconnection_time,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as connection_date,
    (epoch(zo.ZENDDATE) - epoch(zo.ZSTARTDATE)) / 3600.0 as connection_hours
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/bluetooth/connection'
  AND sm.Z_DKBLUETOOTHMETADATAKEY__NAME IS NOT NULL;

-- App Install/Uninstall Events
CREATE OR REPLACE VIEW v_app_installs AS
SELECT 
    zo.Z_PK as id,
    zo.ZVALUESTRING as app_bundle_id,
    sm.Z_DKAPPINSTALLMETADATAKEY__TITLE as app_title,
    sm.Z_DKAPPINSTALLMETADATAKEY__PRIMARYCATEGORY as category,
    CASE 
        WHEN sm.Z_DKAPPINSTALLMETADATAKEY__ISINSTALL = 1 THEN 'install'
        ELSE 'uninstall'
    END as action_type,
    zo.ZSTARTDATE + INTERVAL '31 years' as timestamp,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as action_date
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/app/install'
  AND zo.ZVALUESTRING IS NOT NULL;

-- Location Activity
CREATE OR REPLACE VIEW v_location_activity AS
SELECT 
    zo.Z_PK as id,
    zo.ZVALUESTRING as app_bundle_id,
    sm.Z_DKLOCATIONAPPLICATIONACTIVITYMETADATAKEY__CITY as city,
    sm.Z_DKLOCATIONAPPLICATIONACTIVITYMETADATAKEY__COUNTRY as country,
    sm.Z_DKLOCATIONAPPLICATIONACTIVITYMETADATAKEY__LATITUDE as latitude,
    sm.Z_DKLOCATIONAPPLICATIONACTIVITYMETADATAKEY__LONGITUDE as longitude,
    zo.ZSTARTDATE + INTERVAL '31 years' as timestamp,
    DATE(zo.ZSTARTDATE + INTERVAL '31 years') as activity_date
FROM ZOBJECT zo
LEFT JOIN ZSTRUCTUREDMETADATA sm ON zo.ZSTRUCTUREDMETADATA = sm.Z_PK
WHERE zo.ZSTREAMNAME = '/location/activity'
  AND zo.ZVALUESTRING IS NOT NULL
  AND sm.Z_DKLOCATIONAPPLICATIONACTIVITYMETADATAKEY__CITY IS NOT NULL;

-- Advanced Analytics Views

-- Session Sequences: App switching patterns with timing analysis
CREATE OR REPLACE VIEW v_session_sequences AS
WITH app_sessions AS (
    SELECT 
        ZVALUESTRING as app_bundle_id,
        ZSTARTDATE + INTERVAL '31 years' as start_time,
        ZENDDATE + INTERVAL '31 years' as end_time,
        DATE(ZSTARTDATE + INTERVAL '31 years') as usage_date,
        (epoch(ZENDDATE) - epoch(ZSTARTDATE)) / 60.0 as duration_minutes,
        ROW_NUMBER() OVER (PARTITION BY DATE(ZSTARTDATE + INTERVAL '31 years') ORDER BY ZSTARTDATE) as session_order
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT 
    a1.usage_date,
    a1.app_bundle_id as from_app,
    a2.app_bundle_id as to_app,
    a1.end_time as from_end_time,
    a2.start_time as to_start_time,
    epoch((a2.start_time - a1.end_time)) as gap_seconds,
    ROUND(epoch((a2.start_time - a1.end_time)) / 60.0, 1) as gap_minutes,
    a1.duration_minutes as from_duration_minutes,
    a2.duration_minutes as to_duration_minutes,
    CASE 
        WHEN epoch((a2.start_time - a1.end_time)) < 30 THEN 'immediate'
        WHEN epoch((a2.start_time - a1.end_time)) < 300 THEN 'quick'
        WHEN epoch((a2.start_time - a1.end_time)) < 1800 THEN 'pause'
        ELSE 'break'
    END as transition_type
FROM app_sessions a1
JOIN app_sessions a2 ON a1.usage_date = a2.usage_date 
    AND a1.session_order + 1 = a2.session_order
WHERE a1.app_bundle_id != a2.app_bundle_id;

-- Productivity Time Blocks: Sustained focus analysis
CREATE OR REPLACE VIEW v_productivity_blocks AS
WITH productivity_apps AS (
    SELECT DISTINCT app_bundle_id
    FROM v_app_categories 
    WHERE category IN ('Development', 'Productivity', 'AI/ML')
),
focus_sessions AS (
    SELECT 
        v.usage_date,
        v.app_bundle_id,
        v.start_time,
        v.end_time,
        v.duration_minutes,
        CASE WHEN v.duration_minutes >= 25 THEN 'deep_focus'
             WHEN v.duration_minutes >= 15 THEN 'moderate_focus'
             WHEN v.duration_minutes >= 5 THEN 'light_focus'
             ELSE 'brief' END as focus_level
    FROM v_app_usage v
    JOIN productivity_apps p ON v.app_bundle_id = p.app_bundle_id
    WHERE v.duration_minutes >= 5
),
time_blocks AS (
    SELECT 
        usage_date,
        DATE_TRUNC('hour', start_time) as hour_block,
        SUM(duration_minutes) as productive_minutes,
        COUNT(*) as sessions,
        AVG(duration_minutes) as avg_session_duration,
        COUNT(CASE WHEN focus_level = 'deep_focus' THEN 1 END) as deep_focus_sessions
    FROM focus_sessions
    GROUP BY usage_date, DATE_TRUNC('hour', start_time)
)
SELECT 
    usage_date,
    hour_block,
    productive_minutes,
    sessions,
    ROUND(avg_session_duration, 1) as avg_session_duration,
    deep_focus_sessions,
    CASE 
        WHEN productive_minutes >= 45 THEN 'high_productivity'
        WHEN productive_minutes >= 20 THEN 'moderate_productivity'
        WHEN productive_minutes >= 10 THEN 'light_productivity'
        ELSE 'minimal_productivity'
    END as productivity_score
FROM time_blocks
ORDER BY usage_date DESC, hour_block;

-- Distraction Detection: High-frequency, low-duration app usage
CREATE OR REPLACE VIEW v_distraction_analysis AS
WITH app_patterns AS (
    SELECT 
        app_bundle_id,
        usage_date,
        COUNT(*) as daily_sessions,
        SUM(duration_minutes) as daily_minutes,
        AVG(duration_minutes) as avg_session_duration,
        MIN(duration_minutes) as min_session_duration,
        MAX(duration_minutes) as max_session_duration,
        STDDEV(duration_minutes) as session_duration_stddev
    FROM v_app_usage
    WHERE usage_date >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY app_bundle_id, usage_date
),
weekly_aggregates AS (
    SELECT 
        app_bundle_id,
        AVG(daily_sessions) as avg_daily_sessions,
        AVG(daily_minutes) as avg_daily_minutes,
        AVG(avg_session_duration) as avg_session_duration,
        SUM(daily_sessions) as total_sessions,
        SUM(daily_minutes) as total_minutes
    FROM app_patterns
    GROUP BY app_bundle_id
)
SELECT 
    app_bundle_id,
    ROUND(avg_daily_sessions, 1) as avg_daily_sessions,
    ROUND(avg_daily_minutes, 1) as avg_daily_minutes,
    ROUND(avg_session_duration, 1) as avg_session_duration,
    total_sessions,
    ROUND(total_minutes, 1) as total_minutes,
    CASE 
        WHEN avg_daily_sessions >= 20 AND avg_session_duration < 2 THEN 'high_distraction'
        WHEN avg_daily_sessions >= 10 AND avg_session_duration < 5 THEN 'moderate_distraction'
        WHEN avg_daily_sessions >= 5 AND avg_session_duration < 10 THEN 'low_distraction'
        ELSE 'focused_usage'
    END as distraction_level,
    ROUND(total_minutes / NULLIF(total_sessions, 0), 1) as overall_avg_duration
FROM weekly_aggregates
WHERE total_sessions >= 5
ORDER BY avg_daily_sessions DESC, avg_session_duration ASC;

-- Deep Work Analysis: Sustained focus periods across apps
CREATE OR REPLACE VIEW v_deep_work_analysis AS
WITH productive_categories AS (
    SELECT app_bundle_id, category
    FROM v_app_categories 
    WHERE category IN ('Development', 'Productivity', 'AI/ML', 'Education')
),
deep_sessions AS (
    SELECT 
        v.usage_date,
        v.app_bundle_id,
        p.category,
        v.start_time,
        v.end_time,
        v.duration_minutes,
        v.focus_level,
        hour(v.start_time) as hour_of_day
    FROM v_app_usage v
    JOIN productive_categories p ON v.app_bundle_id = p.app_bundle_id
    WHERE v.duration_minutes >= 15  -- 15+ minute sessions
),
session_blocks AS (
    SELECT 
        usage_date,
        category,
        hour_of_day,
        COUNT(*) as deep_sessions,
        SUM(duration_minutes) as total_deep_minutes,
        AVG(duration_minutes) as avg_session_duration,
        MAX(duration_minutes) as longest_session,
        COUNT(CASE WHEN duration_minutes >= 45 THEN 1 END) as flow_state_sessions
    FROM deep_sessions
    GROUP BY usage_date, category, hour_of_day
)
SELECT 
    usage_date,
    category,
    hour_of_day,
    deep_sessions,
    ROUND(total_deep_minutes, 1) as total_deep_minutes,
    ROUND(avg_session_duration, 1) as avg_session_duration,
    ROUND(longest_session, 1) as longest_session,
    flow_state_sessions,
    CASE 
        WHEN total_deep_minutes >= 120 THEN 'excellent_focus'
        WHEN total_deep_minutes >= 60 THEN 'good_focus'
        WHEN total_deep_minutes >= 30 THEN 'moderate_focus'
        ELSE 'limited_focus'
    END as focus_quality
FROM session_blocks
ORDER BY usage_date DESC, total_deep_minutes DESC;

-- Context Switching Cost Analysis: Penalty for frequent app switching
CREATE OR REPLACE VIEW v_context_switching_analysis AS
WITH switching_patterns AS (
    SELECT 
        usage_date,
        from_app,
        to_app,
        gap_seconds,
        transition_type,
        from_duration_minutes,
        to_duration_minutes,
        CASE 
            WHEN gap_seconds < 10 THEN 'rapid_switch'
            WHEN gap_seconds < 60 THEN 'quick_switch'
            WHEN gap_seconds < 300 THEN 'normal_switch'
            ELSE 'delayed_switch'
        END as switch_speed
    FROM v_session_sequences
    WHERE gap_seconds >= 0 AND gap_seconds < 3600  -- Within 1 hour
),
daily_switching_stats AS (
    SELECT 
        usage_date,
        COUNT(*) as total_switches,
        COUNT(CASE WHEN switch_speed = 'rapid_switch' THEN 1 END) as rapid_switches,
        COUNT(CASE WHEN switch_speed = 'quick_switch' THEN 1 END) as quick_switches,
        AVG(gap_seconds) as avg_switch_time,
        AVG(from_duration_minutes) as avg_session_before_switch,
        COUNT(CASE WHEN from_duration_minutes < 5 THEN 1 END) as interrupted_sessions,
        COUNT(DISTINCT from_app) as unique_apps_used
    FROM switching_patterns
    GROUP BY usage_date
)
SELECT 
    usage_date,
    total_switches,
    rapid_switches,
    quick_switches,
    ROUND(avg_switch_time, 1) as avg_switch_time_seconds,
    ROUND(avg_session_before_switch, 1) as avg_session_before_switch,
    interrupted_sessions,
    unique_apps_used,
    ROUND(100.0 * interrupted_sessions / NULLIF(total_switches, 0), 1) as interruption_rate_percent,
    ROUND(total_switches * 1.0 / NULLIF(unique_apps_used, 0), 1) as switches_per_app,
    CASE 
        WHEN rapid_switches >= 10 OR (100.0 * interrupted_sessions / NULLIF(total_switches, 0)) >= 50 THEN 'high_switching_cost'
        WHEN rapid_switches >= 5 OR (100.0 * interrupted_sessions / NULLIF(total_switches, 0)) >= 30 THEN 'moderate_switching_cost'
        ELSE 'low_switching_cost'
    END as switching_cost_level
FROM daily_switching_stats
ORDER BY usage_date DESC;

-- Enhanced Context Switching Cost: Detailed per-hour analysis
-- TEMPORARILY COMMENTED OUT DUE TO SYNTAX ERROR
/*
CREATE OR REPLACE VIEW v_context_switching_cost AS
WITH app_switches AS (
    SELECT 
        DATE(ZSTARTDATE + INTERVAL '31 years') as switch_date,
        EXTRACT(HOUR FROM (ZSTARTDATE + INTERVAL '31 years')) as hour_of_day,
        ZVALUESTRING as from_app,
        LEAD(ZVALUESTRING, 1) OVER (PARTITION BY DATE(ZSTARTDATE + INTERVAL '31 years') ORDER BY ZSTARTDATE) as to_app,
        ZSTARTDATE + INTERVAL '31 years' as switch_time,
        LEAD(ZSTARTDATE + INTERVAL '31 years', 1) OVER (PARTITION BY DATE(ZSTARTDATE + INTERVAL '31 years') ORDER BY ZSTARTDATE) as next_switch_time,
        (EXTRACT(EPOCH FROM ZENDDATE) - EXTRACT(EPOCH FROM ZSTARTDATE)) / 60.0 as session_duration_minutes
    FROM ZOBJECT 
    WHERE ZSTREAMNAME = '/app/usage' 
      AND ZVALUESTRING IS NOT NULL
      AND DATE(ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '30 days'
),
hourly_stats AS (
    SELECT 
        switch_date,
        hour_of_day,
        COUNT(*) as switches_in_hour,
        COUNT(DISTINCT from_app) as unique_apps_in_hour,
        ROUND(AVG(session_duration_minutes), 2) as avg_session_duration,
        ROUND(MIN(session_duration_minutes), 2) as shortest_session,
        COUNT(CASE WHEN session_duration_minutes < 1 THEN 1 ELSE NULL END) as micro_sessions,
        COUNT(CASE WHEN session_duration_minutes < 5 THEN 1 ELSE NULL END) as short_sessions,
        ROUND(60.0 / NULLIF(COUNT(*), 0), 2) as minutes_between_switches
    FROM app_switches
    WHERE from_app != to_app OR to_app IS NULL
    GROUP BY switch_date, hour_of_day
)
SELECT 
    switch_date,
    hour_of_day,
    switches_in_hour,
    unique_apps_in_hour,
    avg_session_duration,
    shortest_session,
    micro_sessions,
    short_sessions,
    minutes_between_switches,
    ROUND(100.0 * micro_sessions / NULLIF(switches_in_hour, 0), 1) as micro_session_percent,
    CASE 
        WHEN switches_in_hour >= 30 THEN 'extreme_switching'
        WHEN switches_in_hour >= 20 THEN 'high_switching'
        WHEN switches_in_hour >= 10 THEN 'moderate_switching'
        ELSE 'low_switching'
    END as switching_intensity,
    ROUND(switches_in_hour * (1.0 - avg_session_duration / 10.0), 1) as context_switch_cost_score
FROM hourly_stats
ORDER BY switch_date DESC, hour_of_day;
*/

-- Work Fragmentation Analysis: How broken up is your work?
-- TEMPORARILY COMMENTED OUT DUE TO SYNTAX ERROR
/*
CREATE OR REPLACE VIEW v_work_fragmentation AS
WITH work_apps AS (
    SELECT DISTINCT app_bundle_id
    FROM v_app_categories 
    WHERE category IN ('Development', 'Productivity', 'AI/ML')
),
work_sessions AS (
    SELECT 
        DATE(zo.ZSTARTDATE + INTERVAL '31 years') as work_date,
        EXTRACT(HOUR FROM (zo.ZSTARTDATE + INTERVAL '31 years')) as hour_of_day,
        zo.ZVALUESTRING as app_bundle_id,
        zo.ZSTARTDATE + INTERVAL '31 years' as start_time,
        zo.ZENDDATE + INTERVAL '31 years' as end_time,
        (EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) / 60.0 as duration_minutes
    FROM ZOBJECT zo
    JOIN work_apps wa ON zo.ZVALUESTRING = wa.app_bundle_id
    WHERE zo.ZSTREAMNAME = '/app/usage'
      AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '30 days'
),
hourly_fragmentation AS (
    SELECT 
        work_date,
        hour_of_day,
        COUNT(*) as work_sessions,
        ROUND(SUM(duration_minutes), 1) as total_work_minutes,
        ROUND(AVG(duration_minutes), 2) as avg_session_duration,
        ROUND(STDDEV(duration_minutes), 2) as session_duration_variance,
        MAX(duration_minutes) as longest_session,
        MIN(duration_minutes) as shortest_session,
        COUNT(CASE WHEN duration_minutes >= 25 THEN 1 ELSE NULL END) as pomodoro_sessions,
        COUNT(CASE WHEN duration_minutes < 5 THEN 1 ELSE NULL END) as fragment_sessions
    FROM work_sessions
    GROUP BY work_date, hour_of_day
)
SELECT 
    work_date,
    hour_of_day,
    work_sessions,
    total_work_minutes,
    avg_session_duration,
    session_duration_variance,
    longest_session,
    shortest_session,
    pomodoro_sessions,
    fragment_sessions,
    ROUND(100.0 * fragment_sessions / NULLIF(work_sessions, 0), 1) as fragmentation_percent,
    CASE 
        WHEN avg_session_duration >= 20 AND session_duration_variance < 10 THEN 'sustained_focus'
        WHEN avg_session_duration >= 10 AND fragment_sessions < 3 THEN 'moderate_focus'
        WHEN fragment_sessions >= work_sessions * 0.5 THEN 'highly_fragmented'
        ELSE 'mixed_pattern'
    END as fragmentation_type,
    ROUND(total_work_minutes * (avg_session_duration / 25.0), 1) as effective_work_score
FROM hourly_fragmentation
WHERE total_work_minutes > 0
ORDER BY work_date DESC, hour_of_day;
*/

-- Flow State Detection: Identify periods of deep, uninterrupted work
-- TEMPORARILY COMMENTED OUT - TO BE FIXED
/*
CREATE OR REPLACE VIEW v_flow_state_detection AS
WITH productive_apps AS (
    SELECT DISTINCT app_bundle_id
    FROM v_app_categories 
    WHERE category IN ('Development', 'Productivity', 'AI/ML', 'Creative')
),
potential_flow_sessions AS (
    SELECT 
        DATE(zo.ZSTARTDATE + INTERVAL '31 years') as flow_date,
        zo.ZVALUESTRING as app_bundle_id,
        zo.ZSTARTDATE + INTERVAL '31 years' as start_time,
        zo.ZENDDATE + INTERVAL '31 years' as end_time,
        (EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) / 60.0 as duration_minutes,
        EXTRACT(HOUR FROM (zo.ZSTARTDATE + INTERVAL '31 years')) as start_hour,
        EXTRACT(DOW FROM (zo.ZSTARTDATE + INTERVAL '31 years')) as day_of_week
    FROM ZOBJECT zo
    JOIN productive_apps pa ON zo.ZVALUESTRING = pa.app_bundle_id
    WHERE zo.ZSTREAMNAME = '/app/usage'
      AND (EXTRACT(EPOCH FROM zo.ZENDDATE) - EXTRACT(EPOCH FROM zo.ZSTARTDATE)) >= 1500  -- 25+ minutes
      AND DATE(zo.ZSTARTDATE + INTERVAL '31 years') >= CURRENT_DATE - INTERVAL '30 days'
),
flow_analysis AS (
    SELECT 
        flow_date,
        app_bundle_id,
        start_time,
        end_time,
        duration_minutes,
        start_hour,
        day_of_week,
        CASE 
            WHEN duration_minutes >= 90 THEN 'deep_flow'
            WHEN duration_minutes >= 45 THEN 'moderate_flow'
            ELSE 'light_flow'
        END as flow_intensity,
        CASE 
            WHEN start_hour BETWEEN 5 AND 11 THEN 'morning'
            WHEN start_hour BETWEEN 12 AND 16 THEN 'afternoon'
            WHEN start_hour BETWEEN 17 AND 21 THEN 'evening'
            ELSE 'night'
        END as time_of_day
    FROM potential_flow_sessions
)
SELECT 
    flow_date,
    app_bundle_id,
    start_time,
    end_time,
    ROUND(duration_minutes, 1) as duration_minutes,
    flow_intensity,
    time_of_day,
    CASE day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_name,
    start_hour,
    ROUND(duration_minutes / 25.0, 1) as pomodoro_equivalents
FROM flow_analysis
ORDER BY flow_date DESC, duration_minutes DESC;
*/