// Copyright 2025 Neomantra Corp
package main

import (
	"fmt"
	"log/slog"
	"os"

	"github.com/AgentDank/screentime-mcp/internal/db"
	"github.com/AgentDank/screentime-mcp/internal/mcp"
	"github.com/spf13/pflag"
)

///////////////////////////////////////////////////////////////////////////////

const (
	mcpServerName    = "screentime-mcp"
	mcpServerVersion = "0.0.1"

	defaultSSEHostPort = ":8889"
	defaultDBFile      = ":memory:"
	defaultLogDest     = "screentime-mcp.log"
)

type Config struct {
	DuckDBFile string // DuckDB file to connect to

	LogJSON bool // Log in JSON format instead of text
	Verbose bool // Verbose logging
	DevMode bool // Enable dev mode

	MCPConfig mcp.Config // MCP config
}

///////////////////////////////////////////////////////////////////////////////

func main() {
	var config Config
	var logFilename string
	var showHelp bool

	pflag.StringVarP(&config.DuckDBFile, "db", "", ":memory:", "DuckDB data file to use, use ':memory:' for in-memory. Default is ':memory:")
	pflag.StringVarP(&logFilename, "log-file", "l", "", "Log file destination (or MCP_LOG_FILE envvar). Default is stderr")
	pflag.BoolVarP(&config.LogJSON, "log-json", "j", false, "Log in JSON (default is plaintext)")
	pflag.BoolVarP(&config.Verbose, "verbose", "v", false, "Verbose logging")
	pflag.BoolVarP(&config.DevMode, "dev", "d", false, "Activate dev mode")
	pflag.StringVarP(&config.MCPConfig.SSEHostPort, "sse-host", "", "", "host:port to listen to SSE connections")
	pflag.BoolVarP(&config.MCPConfig.UseSSE, "sse", "", false, "Use SSE Transport (default is STDIO transport)")
	pflag.BoolVarP(&config.MCPConfig.OneShot, "once", "o", false, "Exit after one tool call")
	pflag.BoolVarP(&showHelp, "help", "h", false, "Show help")
	pflag.Parse()

	if showHelp {
		fmt.Fprintf(os.Stdout, "usage: %s [opts]\n\n", os.Args[0])
		pflag.PrintDefaults()
		os.Exit(0)
	}

	if config.MCPConfig.SSEHostPort == "" {
		config.MCPConfig.SSEHostPort = defaultSSEHostPort
	}

	config.MCPConfig.Name = mcpServerName
	config.MCPConfig.Version = mcpServerVersion

	if config.DuckDBFile == "" {
		config.DuckDBFile = ":memory:"
	}

	// Set up logging
	logWriter := os.Stderr // default is stderr
	if logFilename == "" { // prefer CLI option
		logFilename = os.Getenv("MCP_LOG_FILE")
	}
	if logFilename != "" {
		logFile, err := os.OpenFile(logFilename, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to open log file: %s\n", err.Error())
			os.Exit(1)
		}
		logWriter = logFile
		defer logFile.Close()
	}

	var logLevel = slog.LevelInfo
	if config.Verbose {
		logLevel = slog.LevelDebug
	}

	var logger *slog.Logger
	if config.LogJSON {
		logger = slog.New(slog.NewJSONHandler(logWriter, &slog.HandlerOptions{Level: logLevel}))
	} else {
		logger = slog.New(slog.NewTextHandler(logWriter, &slog.HandlerOptions{Level: logLevel}))
	}

	logger.Info("screentime-mcp")

	// Setup our database
	filename := config.DuckDBFile
	if filename != ":memory:" {
		filename += "?access_mode=read_only"
	}
	db.SetDuckDBFilename(filename)
	db.SetDevMode(config.DevMode)

	// Open a DB to dry-run it for later
	if duckdbConn, err := db.Open(filename); err != nil {
		if !config.DevMode {
			logger.Error("Failed to open database", "error", err.Error())
			os.Exit(1)
		}
	} else {
		duckdbConn.Close()
		duckdbConn = nil
	}

	// Run our MCP server
	err := mcp.RunRouter(config.MCPConfig, logger)
	if err != nil {
		logger.Error("MCP router error", "error", err.Error())
		os.Exit(1)
	}
}
