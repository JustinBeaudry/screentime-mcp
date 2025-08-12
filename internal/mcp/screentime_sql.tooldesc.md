# Screen Time SQL Tool

screentime_sql queries MacOS Screen Time data using DuckDB SQL dialect. The database contains app usage, notifications, and device activity data from the macOS Knowledge database.

Of the course of agentic loops, this screentime_sql.tooldesc.md file and the duckdb_views.sql file will be updated.

We append the duckdb_views.sql file to the end of the tool description.

Since the MCP hosts cannot reload the MCP server, this MCP server periodically reloads both the tool description and the SQL views.  If there is any failure, the MCP server will return an error on any screentime_sql request.
