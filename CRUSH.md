# Screentime MCP - Build & Style Guide

## Build Commands
```bash
task build          # Build the screentime-mcp service
task tidy           # Run go mod tidy
task clean          # Clean build products
task stdio-schema   # Extract schema from stdio server
go build -v ./...   # Build all packages
go test ./...       # Run all tests
go test -v -run TestName ./path/to/package  # Run single test
```

## Code Style

### Imports
Group imports with blank lines: stdlib → external → internal
```go
import (
    "fmt"
    "os"

    "github.com/spf13/pflag"

    "github.com/AgentDank/screentime-mcp/internal/db"
)
```

### Naming
- Exported: `PascalCase` (functions, types, fields)
- Unexported: `camelCase` (functions, variables, fields)
- Handlers: `FunctionNameHandler` suffix

### Error Handling
- Wrap errors: `fmt.Errorf("context: %w", err)`
- Log before exit: `logger.Error("message", "error", err.Error())`
- Always defer cleanup: `defer resource.Close()`

### File Organization
- Copyright header: `// Copyright (c) 2025 Neomantra Corp`
- Embed resources: `//go:embed filename.sql` with PascalCase var
- Section separators: `///////////////////////////////////////////////////////////////////////////////`