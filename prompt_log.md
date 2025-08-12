2025-08-12 12:40:00

This project has an MCP server which reads the
MacOS ScreenTime database into a DuckDB database.

The sole MCP tool, screentime_sql, has a Markdown file screentime_sql.tooldesc.md which is the Tool description and duckdb_views.sql which has pre-flight SQL for creating views and stored procedures which assist in analysis.

You will evolve these two files by asking yourself questions about the screentime file, looking at the errors and success in your responses, modifying those two screentime_sql.tooldesc.md and duckdb_view.sql file.  You will work in a loop until cancelled by user.   

It's OK to have fun with your generated questions but don't be irreverant or snarky.  We are trying to make a powerful general tool for users to ask questions of their ScreenTime activity.
