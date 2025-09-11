## dart_acp

This repository contains a Dart ACP client library that talks to an ACP agent
over stdio JSON‑RPC. It handles transport, session lifecycle, routing updates,
workspace jail, permissions, and optional terminal provider.

### Specs

- `specs/acp-client-best-practices.md`: Language-agnostic ACP client best practices with Dart notes—covers initialization, sessions, streaming/cancellation, tool calls/permissions, FS/terminal, security, telemetry, testing, and includes diagrams and a conformance checklist (with Zed code references).
- `specs/dart_acp_technical_design.md`: Technical design of the Dart ACP client and example CLI—goals, architecture, lifecycle flows, providers (FS, permissions, terminal), configuration, testing strategy, and open questions.
- `specs/architecture-best-practices.md`: General architecture guidelines for this repo—DRY, separation of concerns, SRP, low coupling/high cohesion, observability/testability, security by design, and simplicity.
- `specs/acp-llms.txt`: Local snapshot of the ACP specification website for offline reference—initialization, session setup, prompt turn, tool calls, file system, terminal, and schema.

### Features
- Stdio transport (JSON‑RPC over stdin/stdout between client and agent).
- JSON‑RPC peer with client callbacks (fs.read/write, permission prompts,
  terminal lifecycle).
- Session manager: `initialize`, `newSession`, `prompt` streaming (`AcpUpdate`
  types), `cancel`.
- Providers: FS jail enforcement, default permission policy, default terminal
  process provider.
- Terminal events stream for UIs: created/output/exited/released.

### Quick Start (Example CLI)
```bash
# Ensure example/settings.json exists next to the CLI (see specs)
dart example/main.dart -a my-agent "Say hello"
```
See `specs/dart_acp_technical_design.md` §17 for full CLI usage.

### Prompt Input
- Positional argument: Provide the prompt at the end of the command.
  - Example: `dart example/main.dart -a gemini "Summarize README.md"`
- Stdin: Pipe text into the CLI; it reads the entire stream as the prompt when stdin is not a TTY.
  - Example: `echo "List available commands" | dart example/main.dart -o jsonl`

Full usage:

```
Usage: dart example/main.dart [options] [--] [prompt]

Options:
  -a, --agent <name>     Select agent from settings.json next to this CLI
      --settings <path>  Use a specific settings.json (overrides default next to CLI)
  -o, --output <mode>    Output mode: jsonl|json|text|simple (default: text)
      --yolo             Enable read-everywhere and write-enabled (writes still confined to CWD)
      --write            Enable write capability (still confined to CWD)
      --list-commands    Print available slash commands (ACP AvailableCommand) without sending a prompt
      --list-caps        Print capabilities from initialize (protocolVersion, authMethods, agentCapabilities) and exit
      --resume <id>      Resume an existing session (replay), then send the prompt
      --save-session <p> Save new sessionId to file
  -h, --help             Show this help and exit

Prompt:
  Provide as a positional argument, or pipe via stdin.
  Use @-mentions to add context: @path, @"a file.txt", @https://example.com/file

Examples:
  dart example/main.dart -a my-agent "Summarize README.md"
  echo "List available commands" | dart example/main.dart -o jsonl
~/Code/dart_acp$ 
```

### Output Modes
- text (default): assistant text, plus plan/tool/diff/commands lines.
  - Example: `dart example/main.dart -a gemini "Summarize README.md"`
- simple: assistant text only (no plan/tool/diff/commands).
  - Example: `dart example/main.dart -a claude-code -o simple "Hello"`
- jsonl/json: raw JSON‑RPC frames mirrored to stdout.
  - Example: `dart example/main.dart -a gemini -o json "Hello"`

## Troubleshooting

- Authentication required errors:
  If you see a JSON‑RPC "authentication required" error from an agent, you’ll
  need to authenticate for that agent before sending prompts. For example,
  log out and log back in via the agent’s own CLI or UI, then retry. Ensure
  any required API keys or environment variables are set in your shell
  prior to launching the CLI.

- Settings not found or invalid:
  The CLI loads `settings.json` from the `example/` directory by default or
  from `--settings <path>`. If parsing fails, fix the JSON shape or point to a
  valid file. The `agent_servers` section must contain at least one entry with
  a `command` string; optional `args` is an array of strings and `env` is a
  map of string→string.

- Empty prompt:
  Provide a prompt as trailing args or via stdin (`echo "Hi" | dart example/main.dart`).

### File Mentions (@‑mentions)
- Inline file/URL references in prompts:
  - Local: `@path`, `@"file with spaces.txt"`, absolute or relative; `~` expands.
  - URLs: `@https://example.com/spec`.
- The `@...` remains visible in the user text; a `resource_link` block is added per mention.
- Examples:
  - `dart example/main.dart -a gemini "Review @lib/src/acp_client.dart"`
  - `dart example/main.dart -a claude-code "Analyze @\"specs/dart acp.md\""`
  - `dart example/main.dart -a gemini "Fetch @https://example.com/spec"`

### MCP Servers
- Configure top‑level `mcp_servers` in `example/settings.json`; they’re forwarded to `session/new` and `session/load`.
- Example snippet:
  ```json
  {
    "mcp_servers": [
      {
        "name": "filesystem",
        "command": "/abs/path/to/mcp-server",
        "args": ["--stdio"],
        "env": {"FOO": "bar"}
      }
    ]
  }
  ```

### Session Resumption
- Save session ID: `dart example/main.dart -a gemini --save-session /tmp/sid "Hello"`
- Resume and continue: `dart example/main.dart -a gemini --resume "$(cat /tmp/sid)" "Continue"`
- Resume with stdin: `echo "Continue" | dart example/main.dart -a claude-code --resume "$(cat /tmp/sid)"`

### Agent Selection
- `-a, --agent <name>` selects an entry from `agent_servers` in `example/settings.json`.
- Default is the first listed agent if `-a` is omitted.
  - Examples: `-a gemini`, `-a claude-code`.
- `--settings <path>` overrides the default `example/settings.json` (useful for CI/tests).

### Read / Write Permissions
- `--write` enables write capability (writes remain confined to CWD).
- `--yolo` enables read‑everywhere and write capability; writes still fail outside CWD.
  - Examples:
    - `dart example/main.dart -a gemini --write "Create CHANGELOG entry"`
    - `dart example/main.dart -a claude-code --yolo "Search @/etc/hosts"`

### Cancellation
- Ctrl‑C sends `session/cancel` and exits with code 130. Use when turns run long.

### Install Agents and ACP Adapters

- Google Gemini CLI (ACP-capable):
  - Repo: https://github.com/google-gemini/gemini-cli
  - Install per the README, then authenticate (the CLI supports OAuth-style login flows). Ensure the `gemini` binary is on your PATH.
  - ACP: enable with `--experimental-acp` (the example `settings.json` uses this flag).

- Claude Code ACP Adapter:
  - Recommended (Zed's SDK adapter): https://github.com/zed-industries/claude-code-acp
    - Run via `npx @zed-industries/claude-code-acp` (our default in `example/settings.json`)
    - Or install globally: `npm i -g @zed-industries/claude-code-acp` and invoke `claude-code-acp`
    - Authenticate per the adapter/Claude Code instructions (OAuth-style login supported)
    - This version properly sends available_commands_update after session creation

#### Usage examples

Plain text (default agent):
```bash
dart example/main.dart "Summarize README.md"
```

Plain text (specific agent):
```bash
dart example/main.dart -a my-agent "Summarize README.md"
```

JSONL (default agent):
```bash
dart example/main.dart -o jsonl "Summarize README.md"
```

JSONL (specific agent):
```bash
dart example/main.dart -a my-agent -o jsonl "Summarize README.md"
```

Reading prompt from stdin:
```bash
# Pipe a prompt (plain text mode)
echo "Refactor the following code…" | dart example/main.dart

# Pipe a file as the prompt
cat PROMPT.md | dart example/main.dart

# Pipe with JSONL output
echo "List available commands" | dart example/main.dart -o jsonl
```

#### Configuring agents (example/settings.json)

Create or edit `example/settings.json` next to the CLI. Strict JSON (no comments/trailing commas):

```json
{
  "agent_servers": {
    "my-agent": {
      "command": "your-agent-binary",
      "args": ["--flag"],
      "env": {
        "FOO": "bar"
      }
    },
    "gemini": {
      "command": "gemini",
      "args": ["--experimental-acp"]
    },
    "claude-code": {
      "command": "npx",
      "args": ["acp-claude-code"]
    },
    "another-agent": {
      "command": "another-agent",
      "args": []
    }
  }
}
```

Notes:
- The CLI picks the first listed agent by default.
- `-a/--agent` selects a specific agent by key.
- The library itself does not read settings; it accepts explicit command/args/env.

Using the library directly:

```dart
import 'package:dart_acp/dart_acp.dart';

final client = AcpClient(
  config: AcpConfig(
    workspaceRoot: '/path/to/workspace',
    agentCommand: 'your-agent-binary',
    agentArgs: ['--flag'],
    envOverrides: {'FOO': 'bar'},
  ),
);
```
```
### Slash Commands

Agents can expose slash commands (like `/help`, `/status`, etc.) via the ACP protocol. The CLI provides discovery and execution of these commands.

#### Discovering Available Commands

Use `--list-commands` to see what commands the agent supports:

```bash
# List commands without sending a prompt
dart example/main.dart -a claude-code --list-commands

# Example output:
# /init - Initialize a new CLAUDE.md file with codebase documentation
# /review - Review a pull request
# ...
```

Note: Gemini currently doesn't expose slash commands, so the list will be empty.

### Capabilities (Initialize)

Inspect agent capabilities negotiated during `initialize`:

```bash
# Human-readable summary (no session is created)
dart example/main.dart -a claude-code --list-caps

# Example output (text mode)
protocolVersion: 1
authMethods:
  - claude-login: Log in with Claude Code
agentCapabilities:
  - promptCapabilities:
    - embeddedContext: true
    - image: true

# JSONL frames (inspect the initialize result)
dart example/main.dart -a claude-code -o jsonl --list-caps | jq 'select(.result!=null)'
```

The JSONL initialize result may include:
- `protocolVersion`: negotiated protocol version
- `authMethods`: available auth methods (if any)
- `agentCapabilities`: adapter-reported capabilities (if any)

#### Executing Commands

Simply include the slash command in your prompt:

```bash
# Commands can be combined with other text
dart example/main.dart -a claude-code "/review this PR and suggest improvements"
```

### Plans and Progress Tracking

Agents can emit structured plans showing their approach to complex tasks, with real-time progress updates.

#### Requesting Plans

Ask the agent to create a plan before executing:

```bash
# Request a plan without execution
dart example/main.dart -a gemini "Create a detailed plan to refactor the authentication module. Don't implement yet, just show the plan."

# In text mode, plan updates appear as:
# [plan] {"title": "Refactoring Authentication", "steps": [...], "status": "in_progress"}
```

#### Viewing Progress

As the agent works through a plan, it emits progress updates:

```bash
# Execute a multi-step task with progress tracking
dart example/main.dart -a claude-code "Add comprehensive error handling to all API endpoints"

# Progress appears in text mode as:
# [plan] {"step": 1, "description": "Analyzing existing error handling", "status": "complete"}
# [plan] {"step": 2, "description": "Adding try-catch blocks", "status": "in_progress"}
```

#### JSONL Mode for Plans

For programmatic access, use JSONL mode:

```bash
dart example/main.dart -a gemini -o jsonl "Create a testing strategy" | grep '"plan"'
# Outputs session/update frames with plan details
```

### Diffs and Code Changes

Agents can propose changes as diffs before applying them, allowing review of modifications.

#### Requesting Diffs

Ask for changes to be shown as diffs:

```bash
# Request a diff without applying changes
dart example/main.dart -a claude-code "Show me a diff to add input validation to the login function. Don't apply the changes."

# In text mode, diffs appear as:
# [diff] {"file": "auth.js", "changes": [{"line": 42, "old": "...", "new": "..."}]}
```

#### Reviewing Before Applying

```bash
# Two-step process: review then apply
dart example/main.dart -a gemini "Create a diff to optimize the database queries"
# Review the diff output...
dart example/main.dart -a gemini "Apply the optimization changes we just reviewed"
```

#### Diff Format in JSONL

```bash
# Get structured diff data
dart example/main.dart -a claude-code -o jsonl "Propose type safety improvements" | jq '.params.update | select(.sessionUpdate == "diff")'
```

### Tool Calls and File Operations

Monitor what tools the agent is using:

```bash
# In text mode, tool calls are shown
dart example/main.dart -a gemini "Analyze all Python files for security issues"
# [tool] {"name": "fs_read_text_file", "path": "main.py"}
# [tool] {"name": "fs_read_text_file", "path": "auth.py"}
# ...

# In JSONL mode for detailed tool tracking
dart example/main.dart -a claude-code -o jsonl "Update dependencies" | grep tool_call
```

### Output Modes Summary

The CLI supports different output modes to suit various use cases:

| Mode   | Flag                | Description                  | Shows                                                        |
| ------ | ------------------- | ---------------------------- | ------------------------------------------------------------ |
| Text   | `-o text` (default) | Human-readable with metadata | Assistant messages, thinking, [plan], [diff], [tool] markers |
| Simple | `-o simple`         | Clean output only            | Assistant messages only (no thinking or metadata)            |
| JSONL  | `-o jsonl`          | Raw protocol frames          | All JSON-RPC messages, one per line                          |
| JSON   | `-o json`           | Same as JSONL                | Alias for JSONL mode                                         |

### How to Test

This project uses the `test` package and contains a mix of unit and end-to-end (e2e) tests.

#### Unit Tests (Always Run)
To run only the unit tests (recommended for quick testing):

```bash
dart test --exclude-tags e2e
```

#### E2E Tests (Require Real Agents)
The e2e tests require actual agents (Gemini, Claude Code) to be configured and available. These tests are tagged with 'e2e' and will timeout if the agents aren't running.

To run all tests including e2e:

```bash
dart test
```

To run only e2e tests:

```bash
dart test --tags e2e
```

The e2e tests use a test-specific settings file: `test/test_settings.json`. The tests pass this file to the CLI via `--settings` so they don’t depend on your default `example/settings.json`.

To run a specific test file:

```bash
dart test test/unit_capabilities_test.dart
```
