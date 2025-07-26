// Copyright (c) 2025 Neomantra Corp

package mcp

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/AgentDank/screentime-mcp/internal/db"
	"github.com/mark3labs/mcp-go/mcp"
	mcp_server "github.com/mark3labs/mcp-go/server"
)

// registerTools registers all the tools with the MCP server.
func registerTools(mcpServer *mcp_server.MCPServer) error {
	if mcpServer == nil {
		return fmt.Errorf("MCP server is nil")
	}

	// Description of the tool
	var toolDesc = ScreentimeSqlToolDesc
	toolDesc += "\n\n## Create Views Statements\n```sql\n"
	toolDesc += db.DuckdbViewsMigration
	toolDesc += "\n```\n"

	// Register tools here
	mcpServer.AddTool(mcp.NewTool("screentime_sql",
		mcp.WithDescription(toolDesc),
		mcp.WithString("sql",
			mcp.Title("SQL statement to query"),
			mcp.Required(),
			mcp.Description(`Queries Screen Time DuckDB with the SQL statement.`),
		)), QueryToolHandler)

	return nil
}

//////////////////////////////////////////////////////////////////////////////

//go:embed screentime_sql.tooldesc.md
var ScreentimeSqlToolDesc string

//////////////////////////////////////////////////////////////////////////////

// QueryToolHandler handles the query tool request, taking the SQL query from the request parameters and marshalling the results to CSV.
func QueryToolHandler(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	// Extract the parameter
	if duckdbConn == nil {
		return nil, fmt.Errorf("No database")
	}
	queryStr, err := request.RequireString("sql")
	if err != nil {
		return nil, fmt.Errorf("sql must be set: %w", err)
	}

	// Query the database
	rows, err := duckdbConn.QueryContext(context.Background(), queryStr)
	if err != nil {
		return nil, fmt.Errorf("failed to query screentime: %w", err)
	}
	defer rows.Close()

	// Marshal results to CSV
	csvData, err := db.RowsToCSV(rows)
	if err != nil {
		return nil, fmt.Errorf("failed to convert rows to CSV: %w", err)
	}

	// Return CSV response
	return mcp.NewToolResultText(csvData), nil
}
