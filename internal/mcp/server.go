// Copyright (c) 2025 Neomantra Corp

package mcp

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	mcp_server "github.com/mark3labs/mcp-go/server"
)

const (
	regex10  = `^(0(\.\d+)?|1(\.0+)?)$`
	regexInt = `^[0-9]*$`
)

// Config is configuration for our MCP server
type Config struct {
	Name    string // Service Name
	Version string // Service Version

	OneShot bool // Only execute one toolcall, then exit with error

	UseSSE      bool   // Use SSE Transport instead of STDIO
	SSEHostPort string // HostPort to use for SSE
}

// Our MCP Tools' DuckDB connection, set during RegisterMCP
// We resort to module-global variable rather than setting up closures
var duckdbConn *sql.DB
var duckdbMigrationError string

//////////////////////////////////////////////////////////////////////////////

// SetDatabase sets the DuckDB connection for the MCP server.
func SetDatabase(conn *sql.DB, migrationError string) error {
	if conn == nil {
		return fmt.Errorf("DuckDB connection is nil")
	}
	duckdbConn = conn
	duckdbMigrationError = migrationError
	return nil
}

// RunRouter runs the MCP server with the given configuration and logger.
func RunRouter(config Config, logger *slog.Logger) error {
	if duckdbConn == nil {
		return fmt.Errorf("DuckDB connection is nil")
	}

	hooks := &mcp_server.Hooks{}
	if config.OneShot {
		hooks.AddAfterCallTool(
			func(ctx context.Context, id any, message *mcp.CallToolRequest, result *mcp.CallToolResult) {
				logger.Info("one shot exit in one second")
				go func() {
					time.Sleep(1 * time.Second)
					os.Exit(1)
				}()
			},
		)
	}

	// Create the MCP Server and register Tools on it
	mcpServer := mcp_server.NewMCPServer(
		config.Name, config.Version,
		mcp_server.WithHooks(hooks))

	if err := registerTools(mcpServer); err != nil {
		return err
	}

	// Run the appropriate server
	if config.UseSSE {
		sseServer := mcp_server.NewSSEServer(mcpServer)
		logger.Info("MCP SSE server started", "hostPort", config.SSEHostPort)
		if err := sseServer.Start(config.SSEHostPort); err != nil {
			return fmt.Errorf("MCP SSE server error: %w", err)
		}
	} else {
		logger.Info("MCP STDIO server started")
		if err := mcp_server.ServeStdio(mcpServer); err != nil {
			return fmt.Errorf("MCP STDIO server error: %w", err)
		}
	}

	return nil
}

//////////////////////////////////////////////////////////////////////////////
