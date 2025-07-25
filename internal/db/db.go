// Copyright (c) 2025 Neomantra Corp

package db

import (
	"bytes"
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"os/user"
	"strings"
	"text/template"

	// Import the DuckDB driver
	_ "github.com/marcboeker/go-duckdb/v2"
)

//go:embed duckdb_up.sql
var DuckdbUpMigration string

//go:embed duckdb_safe.sql
var DuckdbSafeMigration string

// MigrationInfo holds data to be injected by our migration template
type MigrationInfo struct {
	HomeDir string
}

///////////////////////////////////////////////////////////////////////////////

// RunMigration executes the migration string on the DuckDB connection.
// Returns an error, if any.
func RunMigration(conn *sql.DB) error {
	// Get the home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		// Try to get the username
		currentUser, err := user.Current()
		if err != nil {
			return fmt.Errorf("Error getting current user: %w", err)
		}
		homeDir = "/Users/" + currentUser.Username
	}

	// Template the migration
	migrationTempl, err := template.New("migration").Parse(DuckdbUpMigration)
	if err != nil {
		return fmt.Errorf("failed to create template migration: %w", err)
	}
	var migrationBytes bytes.Buffer
	err = migrationTempl.Execute(&migrationBytes, MigrationInfo{
		HomeDir: homeDir,
	})
	if err != nil {
		return fmt.Errorf("failed to template migration: %w", err)
	}

	// Execute the migration
	_, err = conn.Exec(migrationBytes.String())
	if err != nil {
		return fmt.Errorf("failed to run migration: %w", err)
	}
	return nil
}

// RunSafeMode locks the database down with the DuckdbSafeMigration.
// Returns an error, if any
func RunSafeMode(conn *sql.DB) error {
	_, err := conn.Exec(DuckdbSafeMigration)
	if err != nil {
		return fmt.Errorf("failed to run safe mode migration: %w", err)
	}
	return nil
}

///////////////////////////////////////////////////////////////////////////////

// String internally quotes a string for use in a SQL query.
func String(str string) string {
	return strings.Replace(str, "'", "''", -1)
}
