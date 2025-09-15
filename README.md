# dart_acp

A Dart implementation of the [Agent Client Protocol (ACP)](https://agentclientprotocol.com), providing both a library for building ACP clients and a full-featured command-line tool for interacting with ACP agents.

## Overview

`dart_acp` enables Dart and Flutter applications to communicate with AI agents that implement the Agent Client Protocol. The package includes:

- **`dart_acp` library**: A complete ACP client implementation for Dart applications
- **`acpcli` tool**: A command-line interface for testing and interacting with ACP agents
- **`acpcomply` app**: A compliance runner that executes a comprehensive JSON test suite against agents and prints a Markdown report

### Key Features

- **Full ACP Protocol Support**: Compatible with the latest specification from agentclientprotocol.com
- **Streaming Updates**: Typed events for plans, tool calls, diffs, and agent messages
- **Security**: Workspace jail enforcement, permission policies, and secure path handling
- **Extensibility**: Support for session modes, slash commands, and protocol extensions
- **Transport Abstraction**: JSON-RPC over stdio with bidirectional communication
- **Rich Metadata**: Tool call tracking with kinds, locations, and execution status

### Documentation

- [`specs/acpcli-requirements.md`](specs/acpcli-requirements.md): Complete requirements and feature documentation for the CLI
- [`specs/dart_acp_technical_design.md`](specs/dart_acp_technical_design.md): Technical architecture and design decisions
- [`specs/acp-client-best-practices.md`](specs/acp-client-best-practices.md): ACP implementation best practices with conformance checklist

---

## dart_acp Library

The `dart_acp` library provides a high-level API for building ACP client applications.

### Quick Start

```dart
import 'dart:io';
import 'package:dart_acp/dart_acp.dart';

void main() async {
  // Create and start the client
  final client = await AcpClient.start(
    config: AcpConfig(
      agentCommand: 'npx',
      agentArgs: ['@zed-industries/claude-code-acp'],
    ),
  );

  // Initialize and create a session
  await client.initialize();
  final workspaceRoot = Directory.current.path;
  final sessionId = await client.newSession(workspaceRoot);

  // Send a prompt with @-mention support
  final stream = client.prompt(
    sessionId: sessionId,
    content: 'examine @main.dart and explain what it does.',
  );

  // Stream the response
  await for (final update in stream) {
    print(update.text);
  }

  // Clean up
  await client.dispose();
  exit(0);
}
```

See the full example: [`example/main.dart`](example/main.dart)

### Core Components

#### AcpClient
The main entry point for interacting with ACP agents:

```dart
final client = await AcpClient.start(
  config: AcpConfig(
    agentCommand: 'your-agent-binary',
    agentArgs: ['--flag'],
    envOverrides: {'API_KEY': 'value'},
    // Optional providers
    fsProvider: myFsProvider,
    permissionProvider: myPermissionProvider,
    terminalProvider: DefaultTerminalProvider(),
  ),
);
```

#### Session Management
```dart
// Create a new session
final sessionId = await client.newSession(workspaceRoot);

// Resume an existing session (if agent supports it)
await client.loadSession(
  sessionId: existingId,
  workspaceRoot: workspaceRoot,
);

// Subscribe to session updates
client.sessionUpdates(sessionId).listen((update) {
  if (update is PlanUpdate) {
    print('Plan: ${update.plan.title}');
  } else if (update is ToolCallUpdate) {
    print('Tool: ${update.toolCall.title}');
  }
});
```

#### @-Mention Support
The library automatically parses @-mentions in prompts:

```dart
// Local files: @file.txt, @"path with spaces/file.txt"
// URLs: @https://example.com/resource
// Home paths: @~/Documents/file.txt
final updates = client.prompt(
  sessionId: sessionId,
  content: 'Review @lib/src/main.dart and @README.md',
);
```

#### Update Types
The library provides strongly-typed update events:

- `MessageDelta`: Assistant response text chunks
- `PlanUpdate`: Execution plans with priorities
- `ToolCallUpdate`: Tool invocations with status
- `DiffUpdate`: File modification diffs
- `AvailableCommandsUpdate`: Slash commands
- `ModeUpdate`: Session mode changes
- `TurnEnded`: End of response with stop reason

### Advanced Features

#### Providers
Customize behavior with pluggable providers:

```dart
// File system provider with workspace jail
class MyFsProvider implements FsProvider {
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    // Custom implementation
  }

  Future<void> writeTextFile(String path, String content) async {
    // Custom implementation
  }
}

// Permission provider for security
class MyPermissionProvider implements PermissionProvider {
  Future<PermissionOutcome> requestPermission(
    PermissionOptions options,
  ) async {
    // Return allow, deny, or cancelled
  }
}
```

#### Session Modes (Extension)
```dart
// Get available modes
final modes = client.sessionModes(sessionId);
print('Current: ${modes?.currentModeId}');
print('Available: ${modes?.availableModes}');

// Switch mode
await client.setMode(sessionId: sessionId, modeId: 'edit');
```

---

## acpcli Tool

A comprehensive command-line interface for testing and interacting with ACP agents.

### Installation & Setup

1. Configure agents in `example/acpcli/settings.json`:
```json
{
  "agent_servers": {
    "claude-code": {
      "command": "npx",
      "args": ["@zed-industries/claude-code-acp"],
      "env": {
        "ACP_PERMISSION_MODE": "acceptEdits"
      }
    },
    "gemini": {
      "command": "gemini",
      "args": ["--experimental-acp"]
    }
  }
}
```

2. Run the CLI:
```bash
dart example/acpcli/acpcli.dart "Your prompt here"
```

See the full implementation: [`example/acpcli/acpcli.dart`](example/acpcli/acpcli.dart)

### Usage

```
dart example/acpcli/acpcli.dart [options] [--] [prompt]

Options:
  -h, --help             Show help and exit
  -a, --agent <name>     Select agent from settings.json
  -o, --output <mode>    Output mode: text, simple, jsonl, json (default: text)
  --settings <path>      Use specific settings.json file
  --write                Enable write operations (confined to CWD)
  --yolo                 Enable read-anywhere; writes remain confined to CWD
  --list-caps            Show agent capabilities
  --list-modes           Show available session modes
  --list-commands        Show slash commands
  --mode <id>            Set session mode
  --resume <id>          Resume existing session
  --save-session <path>  Save session ID to file

Prompt:
  Provide as positional argument or pipe via stdin
  Use @-mentions for files: @path, @"file.txt", @https://example.com/doc

Examples:
  dart example/acpcli/acpcli.dart -a gemini "Summarize README.md"
  echo "List commands" | dart example/acpcli/acpcli.dart -o jsonl
  dart example/acpcli/acpcli.dart "Review @lib/src/main.dart"
```

### Key Features

#### Agent Selection
Select from configured agents or use the default:
```bash
# Use default (first in settings.json)
dart example/acpcli/acpcli.dart "Hello"

# Select specific agent
dart example/acpcli/acpcli.dart -a claude-code "Hello"
```

#### Output Modes

| Mode | Flag | Description | Use Case |
|------|------|-------------|----------|
| text | `-o text` (default) | Human-readable with metadata | Interactive use |
| simple | `-o simple` | Assistant text only | Clean output |
| jsonl | `-o jsonl` | Raw protocol frames | Debugging/automation |
| json | `-o json` | Alias for jsonl | Protocol analysis |

#### @-Mention Support
Reference files and URLs directly in prompts:
```bash
# Local files
dart example/acpcli/acpcli.dart "Review @src/main.dart"
dart example/acpcli/acpcli.dart "Analyze @\"my file.txt\""

# URLs
dart example/acpcli/acpcli.dart "Summarize @https://example.com/api-docs"

# Home directory
dart example/acpcli/acpcli.dart "Read @~/Documents/notes.txt"
```

#### Permission Control
Non-interactive permission handling via flags:
```bash
# Enable writes (confined to CWD)
dart example/acpcli/acpcli.dart --write "Create a new file"

# Read anywhere; writes remain confined to CWD
dart example/acpcli/acpcli.dart --yolo "Search system files"
```

#### Discovery Commands
Explore agent capabilities without sending prompts:
```bash
# List capabilities
dart example/acpcli/acpcli.dart -a claude-code --list-caps

# List session modes
dart example/acpcli/acpcli.dart -a claude-code --list-modes

# List slash commands
dart example/acpcli/acpcli.dart -a claude-code --list-commands

# Combine multiple lists
dart example/acpcli/acpcli.dart --list-caps --list-modes --list-commands
```

#### Session Management
Save and resume sessions (if agent supports `loadSession`):
```bash
# Save session
dart example/acpcli/acpcli.dart --save-session /tmp/session.txt "Initial prompt"

# Resume later
dart example/acpcli/acpcli.dart --resume $(cat /tmp/session.txt) "Continue"
```

#### Protocol Debugging
Use JSONL mode to inspect raw ACP protocol:
```bash
# Mirror all JSON-RPC frames
dart example/acpcli/acpcli.dart -o jsonl "Test" | jq '.'

# Filter specific message types
dart example/acpcli/acpcli.dart -o jsonl "Test" | grep tool_call
```

### Tool Monitoring

In text mode, the CLI displays rich information about tool usage:
```
[tool] read Read file @ src/main.py
[tool.in] {"path":"src/main.py","line":1,"limit":200}
[tool.out] "import sys..."
```

### Plans and Progress

Track agent execution plans:
```bash
dart example/acpcli/acpcli.dart "Create a plan to refactor the auth module"
# [plan] {"title": "Refactoring", "steps": [...], "status": "in_progress"}
```

### Terminal Support

When agents execute commands:
```bash
dart example/acpcli/acpcli.dart "Run: npm test"
# [term] created id=term_001 cmd=npm
# [term] output id=term_001
# [term] exited id=term_001 code=0
```

---

## acpcomply Compliance App

The compliance runner executes a suite of ACP agent compliance tests and prints a Markdown report to stdout.

- Entrypoint: `example/acpcomply/acpcomply.dart`
- Tests: `example/acpcomply/compliance-tests/*.jsont`
- Requirements/spec: `specs/acpcomply-requirements.md`

### What It Verifies
- Initialization and session setup
- Prompt turns and cancellation semantics
- Capability respect (FS/terminal disabled)
- Error handling (unknown methods, invalid params)
- File system and terminal flows
- Plans, slash commands, and streaming chunks
- Session modes and session load replay
- Tool calls, diffs, locations, and permission flows
- MCP stdio session setup (optional)

### How It Works
- Creates a per-test sandbox workspace and writes declared files
- Reuses `AcpClient` for transport and Agent→Client handling
- Matches server responses/notifications via regex subset matching
- Observes Agent→Client requests (`fs/*`, `terminal/*`, `session/request_permission`)
- Prints an agent-first Markdown report (no summary table): header per agent, then one H2 per test with actionable status and diffs

### Run
```bash
dart run example/acpcomply/acpcomply.dart
```

Notes:
- Some tests are optional and will be marked NA when agents lack the corresponding capability
- The MCP stdio test forwards a local MCP server definition at `tool/mcp_server/bin/server.dart` to the agent

---

## Installing Agents

### Gemini CLI
```bash
# Install from https://github.com/google-gemini/gemini-cli
# Authenticate with: gemini auth login
# Configure in settings.json with --experimental-acp flag
```

### Claude Code Adapter
```bash
# Option 1: Run via npx (recommended)
npx @zed-industries/claude-code-acp

# Option 2: Install globally
npm i -g @zed-industries/claude-code-acp
```

---

## Testing

### Unit Tests
Run fast unit tests without agents:
```bash
dart test --exclude-tags e2e
```

### E2E Tests
Run integration tests with real agents:
```bash
# All tests including e2e
dart test

# Only e2e tests
dart test --tags e2e

# Specific agent tests
dart test --tags e2e -n "gemini"
dart test --tags e2e -n "claude-code"
```

Tests use `test/test_settings.json` for agent configuration.

---

## Troubleshooting

### Gemini "Invalid argument" Errors
Some Gemini models have ACP implementation bugs. Solution:
- Don't set `GEMINI_MODEL` environment variable
- Use the default model or test specific models first

### Permission Denied
Agents need explicit permissions for file operations:
- Use `--write` for write operations (confined to the workspace/CWD)
- Use `--yolo` for read-anywhere; writes still remain confined to the workspace

### Authentication Required
Authenticate with the agent's native tools first:
```bash
gemini auth login
# or follow Claude Code OAuth flow
```

### Settings Not Found
Ensure `example/acpcli/settings.json` exists or use `--settings` to specify a path.

---

## License

See LICENSE file for details.
