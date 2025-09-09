## dart_acp

This repository contains a Dart ACP client library that talks to an ACP agent
over stdio JSON‑RPC. It handles transport, session lifecycle, routing updates,
workspace jail, permissions, and optional terminal provider.

See `specs/` for details.

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
dart example/agcli.dart -a my-agent "Say hello"
```
See `specs/dart_acp_technical_design.md` §17 for full CLI usage.

### Prompt Input
- Positional argument: Provide the prompt at the end of the command.
  - Example: `dart example/agcli.dart -a gemini "Summarize README.md"`
- Stdin: Pipe text into the CLI; it reads the entire stream as the prompt when stdin is not a TTY.
  - Example: `echo "List available commands" | dart example/agcli.dart -o jsonl`

Full usage:

```
Usage: dart example/agcli.dart [options] [--] [prompt]

Options:
  -a, --agent <name>     Select agent from settings.json next to this CLI
  -o, --output <mode>    Output mode: jsonl|json|text|simple (default: text)
      --yolo             Enable read-everywhere and write-enabled (writes still confined to CWD)
      --write            Enable write capability (still confined to CWD)
      --resume <id>      Resume an existing session (replay), then send the prompt
      --save-session <p> Save new sessionId to file
  -h, --help             Show this help and exit

Prompt:
  Provide as a positional argument, or pipe via stdin.
  Use @-mentions to add context: @path, @"a file.txt", @https://example.com/file

Examples:
  dart example/agcli.dart -a my-agent "Summarize README.md"
  echo "List available commands" | dart example/agcli.dart -o jsonl
~/Code/dart_acp$ 
```

### Output Modes
- text (default): assistant text, plus plan/tool/diff/commands lines.
  - Example: `dart example/agcli.dart -a gemini "Summarize README.md"`
- simple: assistant text only (no plan/tool/diff/commands).
  - Example: `dart example/agcli.dart -a claude-code -o simple "Hello"`
- jsonl/json: raw JSON‑RPC frames mirrored to stdout.
  - Example: `dart example/agcli.dart -a gemini -o json "Hello"`

### File Mentions (@‑mentions)
- Inline file/URL references in prompts:
  - Local: `@path`, `@"file with spaces.txt"`, absolute or relative; `~` expands.
  - URLs: `@https://example.com/spec`.
- The `@...` remains visible in the user text; a `resource_link` block is added per mention.
- Examples:
  - `dart example/agcli.dart -a gemini "Review @lib/src/acp_client.dart"`
  - `dart example/agcli.dart -a claude-code "Analyze @\"specs/dart acp.md\""`
  - `dart example/agcli.dart -a gemini "Fetch @https://example.com/spec"`

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
- Save session ID: `dart example/agcli.dart -a gemini --save-session /tmp/sid "Hello"`
- Resume and continue: `dart example/agcli.dart -a gemini --resume "$(cat /tmp/sid)" "Continue"`
- Resume with stdin: `echo "Continue" | dart example/agcli.dart -a claude-code --resume "$(cat /tmp/sid)"`

### Agent Selection
- `-a, --agent <name>` selects an entry from `agent_servers` in `example/settings.json`.
- Default is the first listed agent if `-a` is omitted.
  - Examples: `-a gemini`, `-a claude-code`.

### Read / Write Permissions
- `--write` enables write capability (writes remain confined to CWD).
- `--yolo` enables read‑everywhere and write capability; writes still fail outside CWD.
  - Examples:
    - `dart example/agcli.dart -a gemini --write "Create CHANGELOG entry"`
    - `dart example/agcli.dart -a claude-code --yolo "Search @/etc/hosts"`

### Cancellation
- Ctrl‑C sends `session/cancel` and exits with code 130. Use when turns run long.

### Install Agents and ACP Adapters

- Google Gemini CLI (ACP-capable):
  - Repo: https://github.com/google-gemini/gemini-cli
  - Install per the README, then authenticate (the CLI supports OAuth-style login flows). Ensure the `gemini` binary is on your PATH.
  - ACP: enable with `--experimental-acp` (the example `settings.json` uses this flag).

- Claude Code ACP Adapter:
  - Option A (Node/npm adapter published by Xuanwo): https://github.com/Xuanwo/acp-claude-code
    - Run via `npx acp-claude-code` (our default in `example/settings.json`) or install globally `npm i -g acp-claude-code` and invoke `acp-claude-code`.
    - Authenticate per the adapter/Claude Code instructions (OAuth-style login supported).
  - Option B (Zed’s SDK adapter): https://github.com/zed-industries/claude-code-acp
    - Use if you prefer Zed’s version; configure the command accordingly.

#### Usage examples

Plain text (default agent):
```bash
dart example/agcli.dart "Summarize README.md"
```

Plain text (specific agent):
```bash
dart example/agcli.dart -a my-agent "Summarize README.md"
```

JSONL (default agent):
```bash
dart example/agcli.dart -o jsonl "Summarize README.md"
```

JSONL (specific agent):
```bash
dart example/agcli.dart -a my-agent -o jsonl "Summarize README.md"
```

Reading prompt from stdin:
```bash
# Pipe a prompt (plain text mode)
echo "Refactor the following code…" | dart example/agcli.dart

# Pipe a file as the prompt
cat PROMPT.md | dart example/agcli.dart

# Pipe with JSONL output
echo "List available commands" | dart example/agcli.dart -o jsonl
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
