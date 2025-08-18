# `screentime-mcp`

`screentime-mcp` is a Model Context Procotol (MCP) server that respond to questions about your [MacOS Screen Time](https://support.apple.com/guide/macbook-air/screen-time-apd35460a9f3/mac).  It is brought to you by AgentDank for educational purposes.

This MCP server loads that into a DuckDB database and exposes that database as an endpoint called `screentime_sql`.  That endpoint takes a `sql` argument allowing the LLM to query the data. The result always comes back as a CSV, simplifying the handling for the LLM.

----

  * [Screen Time SQLite Data](#screen-time-sqlite-data)
  * [Installation](#installation)
  * [Using with LLMs](#usage)
    * [Claude Desktop](#claude-desktop)
    * [Ollama and mcphost](#ollama-and-mcphost)
  * [Command Line Usage](#command-line-usage)
  * [Building](#building)
  * [Metadata](#metadata)
  * [Contribution and Conduct](#contribution-and-conduct)
  * [Credits and License](#credits-and-license)

## Screen Time SQLite Data

Your Screen Time data is stored on your MacOS computer in a [SQLite database](https://www.sqlite.org/).  Here's some references:

 * [Accessing / Exporting Apple's Screen Time Data](https://gist.github.com/0xdevalias/38cfc92278f85ae89a46f0c156208fd5)

 * [Using MacOS Screen Time data to create work hour reports](https://flaky.build/using-macos-screen-time-data-to-create-work-hour-reports)

 * [How to Retrieve Screen Time Data on macOS via the Command Line](https://medium.com/@carmenliu0208/how-to-retrieve-screen-time-data-on-macos-via-the-command-line-66e269278ba5)


Currently, this is sensitive data, so you must enable "Full Disk Permissions" for the host environment of this MCP server.   It runs on your computer, as it reads the local database file.

The MCP Server exposes the following [Tool Description](./internal/mcp/screentime_sql.tooldesc.md) and [Generated SQL Views](./internal/db/duckdb_views.sql).

## Installation

While we'd like to have pre-built binaries and Homebrew packages, we're having an issue with that right now.  So the preferred way to install is using `go install` or [building from source](#building):

```sh
$ go install github.com/AgentDank/screentime-mcp@latest
```

It will be installed in your `$GOPATH/bin` directory, which is often `~/go/bin`.


## Using with LLMs

To use this `screentime-mcp` MCP server, you must configure your host program to use it.  We will illustrate with [Claude Desktop](https://claude.ai/download).  We must find the `screentime-mcp` program on our system; the example below shows where `screentime-mcp` is installed with my `go install`.

The following configuration JSON ([also in the repo as `mcp-config.json`](./mcp-config.json)) sets this up:

```json
{
    "mcpServers": {
      "screentime": {
        "command": "~/go/bin/screentime-mcp",
        "args": [
        ]
      }
    }
  }
```

### Claude Desktop

Using Claude Desktop, you can follow [their configuration tutorial](https://modelcontextprotocol.io/quickstart/user) but substitute the configuration above.  With that in place, you can ask Claude question and it will use the `screentime-mcp` server.  

**PROBLEMO:** To get this to work, you need to grant ["Full Disk Access"](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web) to Claude Desktop (`Claude.app`) .  *What's the worst that can happen?!?*   The ScreenTime `knowledgeC.db` file is protected otherwise.

### Ollama and `mcphost`

**I'm currently having issues with this working well, but leaving instructions for those interested. **

For local inferencing, there are MCP hosts that support [Ollama](https://ollama.com/download).  You can use any [Ollama LLM that supports "Tools"](https://ollama.com/search?c=tools).  We experimented with [`mcphost`](https://github.com/mark3labs/mcphost), authored by the developer of the [`mcp-go` library](https://github.com/mark3labs/mcp-go) that peformed the heavy lifting for us.

Here's how to install and run with it with the configuration above, stored in `mcp-config.json`:

```
$ go install github.com/mark3labs/mcphost@latest
$ ollama pull llama3.3
$ mcphost -m ollama:llama3.3 --config mcp-config.json
...chat away...
```

Similarly, you may need to grant your terminal application "Full Disk Access".  Be careful out there.

## Command Line Usage

Here is the command-line help:

```
usage: ./bin/screentime-mcp [opts]

      --db string         DuckDB data file to use, use ':memory:' for in-memory. Default is ':memory: (default ":memory:")
  -d, --dev               Activate dev mode
  -h, --help              Show help
  -l, --log-file string   Log file destination (or MCP_LOG_FILE envvar). Default is stderr
  -j, --log-json          Log in JSON (default is plaintext)
  -o, --once              Exit after one tool call
      --sse               Use SSE Transport (default is STDIO transport)
      --sse-host string   host:port to listen to SSE connections
  -v, --verbose           Verbose logging
```

To see what the MCP schema looks like, you can run `task stdio-schema | jq` ([link](./Taskfile.yml#L45)).

The `--dev` mode will reload the pre-flight migration file ([`./internal/db/duckdb_views.sql`](./internal/db/duckdb_views.sql)) into a new DuckDB database on each tool call.  This causes the MCP server to lose any DB state and try out a fresh migration without needing a re-build.  It will also allow the MCP server to start with a failed migration.

The `--once` flag will only allow an MCP server to hadle one tool call. It literally `os.Exit` the MCP server after a short timeout.  This is also useful for development.

## Building

Building is performed with [task](https://taskfile.dev/):

```
$ task
task: [build] go build -o screentime-mcp main.go
```

----

## Contribution and Conduct

Pull requests and issues are welcome.  Or fork it.  You do you.

Either way, obey our [Code of Conduct](./CODE_OF_CONDUCT.md).  Be shady, but don't be a jerk.

## Metadata

I was inspired to create this after reading a [HackerNews comment](https://news.ycombinator.com/item?id=44684966) in a thread about an [Apple Health MCP Server](https://github.com/neiltron/apple-health-mcp).   A high school researcher introduced me to the available ScreenTime sqlite data, as he used it in his attention/performance-tracking project.   As I note [on that thread](https://news.ycombinator.com/item?id=44689345):
```
I’ve found good value in making purpose-build MCP servers like that with the general model: Data<>DuckDB<>MCP<>LLM With verbose description for the LLM of an “sql” tool endpoint for it to use to explore.
```

I have since been using Claude to help improve the raw tool.  This involves improving the [Tool Description](./internal/mcp/screentime_sql.tooldesc.md) and the pre-flight [SQL View Creation](./internal/db/duckdb_up.sql).  I ask Claude to do some work with the tool, look at the problems it had with it (e.g. DuckDB dialect issues, timestamp conversion) and create changes.   Since it knows the view and the tool description, it can do much of the heavy lifting itself, with a human guiding it along (mostly as a piece of meat restarting Claude Desktop).


## Credits and License

Copyright (c) 2025 Neomantra Corp.  Authored by Evan Wies for [AgentDank](https://github.com/AgentDank), based on the [`dank-mcp`](https://github.com/agentdank/dank-mcp) codebase.

Released under the [MIT License](https://en.wikipedia.org/wiki/MIT_License), see [LICENSE.txt](./LICENSE.txt).

----
Made with :heart: and :fire: by the team behind [AgentDank](https://github.com/AgentDank).
