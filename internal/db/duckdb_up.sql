-- Enable and install sqlite extension
INSTALL sqlite;
LOAD sqlite;

-- Attach the macOS Screen Time SQLite database
ATTACH '{{ .HomeDir }}/Library/Application Support/Knowledge/knowledgeC.db' (TYPE sqlite);

-- For debugging, copy knowledgeC.db locally from the Library folder and switch the comment
--ATTACH '{{ .HomeDir }}/knowledgeC.db' (TYPE sqlite);

USE knowledgeC;

-- Create timezone information table for MCP client use
CREATE TABLE IF NOT EXISTS user_timezone (
    timestamp TIMESTAMP,
    location VARCHAR,
    timezone VARCHAR,
    utc_offset_seconds INTEGER,
    is_dst BOOLEAN,
    is_weekend BOOLEAN,
    day_of_week INTEGER
);
-- Ensure it gets a single entry
TRUNCATE TABLE user_timezone;
-- Insert current timezone information
INSERT INTO user_timezone VALUES (
    {{ .TimezoneInfo.Timestamp }},
    '{{ .TimezoneInfo.Location }}',
    '{{ .TimezoneInfo.Timezone }}',
    {{ .TimezoneInfo.UTCOffsetSeconds }},
    {{ .TimezoneInfo.IsDST }},
    {{ .TimezoneInfo.IsWeekend }},
    {{ .TimezoneInfo.DayOfWeek }}
);
