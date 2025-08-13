// Copyright (c) 2025 Neomantra Corp

package db

import (
	"bytes"
	"database/sql"
	_ "embed"
	"fmt"
	"io"
	"os"
	"os/user"
	"strings"
	"text/template"

	// Import the DuckDB driver
	_ "github.com/marcboeker/go-duckdb/v2"
)

// MigrationInfo holds data to be injected by our migration template
type MigrationInfo struct {
	HomeDir string
}

//go:embed duckdb_up.sql
var duckdbUpMigration string

//go:embed duckdb_safe.sql
var duckdbSafeMigration string

//go:embed duckdb_views.sql
var duckdbViewsMigration string

var devMode = false

var duckDBFilename = ":memory:"

var duckdbConn *sql.DB

///////////////////////////////////////////////////////////////////////////////

func SetDevMode(isOn bool) {
	devMode = isOn
}

func GetDevMode() bool {
	return devMode
}

///////////////////////////////////////////////////////////////////////////////

// GetDuckDBFilename returns the DuckDB filename.
func GetDuckDBFilename() string {
	return duckDBFilename
}

// SetDuckDBFilename sets the DuckDB filename.  Default is :memory:
func SetDuckDBFilename(filename string) {
	duckDBFilename = filename
}

func GetDuckdbUpMigrationEmbed() string {
	return duckdbUpMigration
}

func GetDuckdbSafeMigrationEmbed() string {
	return duckdbSafeMigration
}

func GetDuckdbViewsMigrationEmbed() string {
	return duckdbViewsMigration
}

func GetDuckdbViewsMigration() string {
	if devMode {
		migration, err := readFile("./internal/db/duckdb_views.sql")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading duckdb_views.sql: %s\n", err.Error())
		}
		return migration
	}
	return GetDuckdbViewsMigrationEmbed()

}

///////////////////////////////////////////////////////////////////////////////

// GetDuckDBConnection returns the a Screentime DuckDB connection
func GetDuckDBConnection() (*sql.DB, error) {
	// in dev mode it is always a new connection
	if duckdbConn == nil || devMode {
		conn, err := Open(duckDBFilename)
		if err != nil {
			return nil, err
		}
		duckdbConn = conn
	}

	return duckdbConn, nil
}

///////////////////////////////////////////////////////////////////////////////

// Open opens a connection to the DuckDB database.
func Open(filename string) (*sql.DB, error) {
	duckdbConn, err := sql.Open("duckdb", filename)
	if err != nil {
		return nil, err
	}

	// Run our migration.
	// This will load the Screen Time SQLite database from the user's home directory.
	err = RunMigration(duckdbConn)
	if err != nil {
		if !devMode {
			duckdbConn.Close()
			return nil, fmt.Errorf("failed to run duckdb migration %w", err)
		}
	}

	// Let's lock it down even more!
	err = RunSafeMode(duckdbConn)
	if err != nil {
		return nil, fmt.Errorf("failed to run safe mode %w", err)
	}

	return duckdbConn, nil
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

	// Template the Up migration
	migrationTempl, err := template.New("migration").Parse(GetDuckdbUpMigrationEmbed())
	if err != nil {
		return fmt.Errorf("failed to create template migration: %w", err)
	}
	var migrationBytes bytes.Buffer
	err = migrationTempl.Execute(&migrationBytes, MigrationInfo{
		HomeDir: homeDir,
	})
	if err != nil {
		return fmt.Errorf("failed to template up migration: %w", err)
	}

	// Execute the Up migration
	_, err = conn.Exec(migrationBytes.String())
	if err != nil {
		return fmt.Errorf("failed to run up migration: %w", err)
	}

	// Execute the Views migration
	_, err = conn.Exec(GetDuckdbViewsMigration())
	if err != nil {
		return fmt.Errorf("failed to run views migration: %w", err)
	}
	return nil

}

// RunSafeMode locks the database down with the DuckdbSafeMigration.
// Returns an error, if any
func RunSafeMode(conn *sql.DB) error {
	_, err := conn.Exec(GetDuckdbSafeMigrationEmbed())
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

func readFile(filepath string) (string, error) {
	fd, err := os.Open(filepath)
	if err != nil {
		return "", err
	}

	data, err := io.ReadAll(fd)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
