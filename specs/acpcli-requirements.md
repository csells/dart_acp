# acpcli Requirements Document

## Executive Summary

`acpcli` is a command-line interface demonstration application for the `dart_acp` library, providing a full-featured reference implementation of an Agent Client Protocol (ACP) client. It serves as both a testing tool for ACP agents and a practical example of how to integrate the `dart_acp` library into applications.

This document defines the requirements, features, and implementation status of `acpcli`, incorporating compliance tracking previously maintained in separate documents.

## Table of Contents

1. [Purpose & Goals](#purpose--goals)
2. [User Scenarios](#user-scenarios)
3. [Feature Inventory](#feature-inventory)
4. [CLI Usage Reference](#cli-usage-reference)
5. [Configuration](#configuration)
6. [Output Modes](#output-modes)
7. [Security & Permissions](#security--permissions)
8. [ACP Best Practices Coverage](#acp-best-practices-coverage)
9. [Implementation Status](#implementation-status)
10. [Testing Requirements](#testing-requirements)
11. [Known Limitations](#known-limitations)
12. [Future Work](#future-work)

## Purpose & Goals

### Goals

1. **Demonstrate Library Usage**: Provide a complete, working example of `dart_acp` library integration
2. **Enable Agent Testing**: Offer a robust CLI for testing ACP-compliant agents
3. **Protocol Exploration**: Support protocol debugging with JSONL mirroring
4. **Compliance Validation**: Implement all stable ACP features and select unstable features
5. **Non-Interactive Operation**: Function as a scriptable, automation-friendly tool

### Non-Goals

1. **Interactive UI**: No interactive prompts or menus (fully non-interactive)
2. **Credential Management**: No storage or management of API keys or secrets
3. **Agent Implementation**: Client-only, no agent-side functionality
4. **Session Persistence**: No long-term session storage (only in-memory during execution)
5. **Custom Protocols**: Strict ACP compliance only, no proprietary extensions

## User Scenarios

### 1. Basic Prompt Execution
```bash
# Send a simple prompt to the default agent
dart example/acpcli/acpcli.dart "Summarize README.md"

# Use a specific agent
dart example/acpcli/acpcli.dart -a gemini "Explain this code"
```

### 2. File Context with @-mentions
```bash
# Reference local files
dart example/acpcli/acpcli.dart "Review @lib/src/main.dart and @README.md"

# Reference files with spaces
dart example/acpcli/acpcli.dart "Analyze @\"my file.txt\" for issues"

# Reference URLs
dart example/acpcli/acpcli.dart "Summarize @https://example.com/api-docs"

# Home directory expansion
dart example/acpcli/acpcli.dart "Read @~/Documents/notes.txt"
```

### 3. Protocol Debugging
```bash
# Mirror all JSON-RPC frames to stdout
dart example/acpcli/acpcli.dart -o jsonl "Test prompt"

# Pipe to analysis tools
dart example/acpcli/acpcli.dart -o jsonl "Test" | jq '.method'"
```

### 4. Agent Capability Discovery
```bash
# List agent capabilities
dart example/acpcli/acpcli.dart -a claude-code --list-caps

# List available modes
dart example/acpcli/acpcli.dart -a claude-code --list-modes

# List slash commands
dart example/acpcli/acpcli.dart -a claude-code --list-commands

# Stack multiple list operations
dart example/acpcli/acpcli.dart --list-caps --list-modes --list-commands
```

### 5. Session Management
```bash
# Save session for later
dart example/acpcli/acpcli.dart --save-session session.txt "Initial prompt"

# Resume session (requires loadSession capability)
dart example/acpcli/acpcli.dart --resume $(cat session.txt) "Follow-up"

# Set session mode
dart example/acpcli/acpcli.dart --mode edit "Refactor this function"
```

### 6. Permission Control
```bash
# Enable write operations
dart example/acpcli/acpcli.dart --write "Create a new file called test.txt"

# Enable read-everywhere and write
dart example/acpcli/acpcli.dart --yolo "Search system for config files"
```

### 7. Piped Input
```bash
# Read prompt from stdin
echo "Explain quantum computing" | dart example/acpcli/acpcli.dart

# Process file contents
cat script.py | dart example/acpcli/acpcli.dart "Review this Python code"
```

### 8. Custom Settings
```bash
# Use alternative settings file
dart example/acpcli/acpcli.dart --settings ~/my-agents.json "Test"
```

## Feature Inventory

### Core Features

| Feature | Description | Status |
|---------|-------------|---------|
| **Agent Selection** | Select agent via `-a/--agent` flag | ✅ Implemented |
| **Settings File** | JSON configuration for agents | ✅ Implemented |
| **Protocol Initialization** | Negotiate version and capabilities | ✅ Implemented |
| **Session Creation** | Create new ACP sessions | ✅ Implemented |
| **Prompt Execution** | Send prompts and receive responses | ✅ Implemented |
| **@-mention Support** | Parse and attach resource links | ✅ Implemented |
| **Output Modes** | text, simple, jsonl formats | ✅ Implemented |
| **Permission Handling** | Non-interactive permission decisions | ✅ Implemented |
| **Cancellation** | Ctrl-C handling with proper cleanup | ✅ Implemented |
| **Exit Codes** | Semantic exit codes for automation | ✅ Implemented |

### Extended Features

| Feature | Description | Status |
|---------|-------------|---------|
| **Session Resume** | Load existing sessions (`--resume`) | ✅ Implemented |
| **Session Save** | Save session ID (`--save-session`) | ✅ Implemented |
| **Mode Selection** | Set session modes (`--mode`) | ✅ Implemented |
| **Capability Listing** | Show agent capabilities (`--list-caps`) | ✅ Implemented |
| **Mode Listing** | Show available modes (`--list-modes`) | ✅ Implemented |
| **Command Listing** | Show slash commands (`--list-commands`) | ✅ Implemented |
| **MCP Forwarding** | Forward MCP server configs | ✅ Implemented |
| **Terminal Support** | Terminal capability provider | ✅ Implemented |
| **Protocol Mirroring** | JSONL output for debugging | ✅ Implemented |
| **Custom Settings Path** | Override settings location | ✅ Implemented |

### Update Types Supported

| Update Type | Description | Display Format | Status |
|-------------|-------------|----------------|---------|
| **Message Chunks** | Assistant response text | Direct output | ✅ Implemented |
| **Thought Chunks** | Internal reasoning | `[thought]` prefix (text mode) | ✅ Implemented |
| **Plans** | Execution plans with priorities | `[plan]` with JSON | ✅ Implemented |
| **Tool Calls** | Tool invocations with metadata | `[tool]` with kind/title/location | ✅ Implemented |
| **Diffs** | File modifications | `[diff]` with JSON | ✅ Implemented |
| **Available Commands** | Slash command updates | Via `--list-commands` | ✅ Implemented |
| **Mode Updates** | Session mode changes | Reflected in state | ✅ Implemented |
| **Terminal Events** | Terminal lifecycle | `[term]` prefixed output | ✅ Implemented |

## CLI Usage Reference

### Synopsis
```bash
dart example/acpcli/acpcli.dart [options] [--] [prompt]
```

### Options

#### Core Options

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-h` | `--help` | Show help and exit | - |
| `-a <name>` | `--agent <name>` | Select agent from settings.json | First listed |
| `-o <mode>` | `--output <mode>` | Output mode: text, simple, json, jsonl | text |
| | `--settings <path>` | Path to settings.json file | Script directory |

#### Permission Flags

| Flag | Description | Effect |
|------|-------------|--------|
| `--write` | Enable write operations | Allows fs.writeTextFile |
| `--yolo` | Enable read‑anywhere (debug) | Read anywhere; writes enabled but confined to workspace |

#### List Operations

| Flag | Description | Notes |
|------|-------------|-------|
| `--list-caps` | Show agent capabilities | No prompt sent if used alone |
| `--list-modes` | Show available modes | Creates session if needed |
| `--list-commands` | Show slash commands | Creates session if needed |

**Note**: List flags can be combined to show multiple types of information in a single invocation.

#### Session Management

| Flag | Description | Requirements |
|------|-------------|--------------|
| `--mode <id>` | Set session mode after creation | Mode must be available |
| `--resume <id>` | Resume existing session | Agent must support loadSession |
| `--save-session <path>` | Save new session ID to file | - |

### Exit Codes

| Code | Meaning | Scenarios |
|------|---------|-----------|
| 0 | Success | Prompt completed normally |
| 2 | Configuration/Usage Error | Invalid args, missing agent, bad settings |
| 130 | User Cancellation | Ctrl-C pressed (128 + SIGINT) |
| 1+ | Other Errors | Transport failures, protocol errors |

### Prompt Input Methods

1. **Positional Argument**: `dart example/acpcli/acpcli.dart "Your prompt"`
2. **Stdin (Piped)**: `echo "Your prompt" | dart example/acpcli/acpcli.dart`
3. **Stdin (Interactive TTY)**: Not supported (exits with error)

## Configuration

### Settings File Location

1. **Default**: `example/acpcli/settings.json` (next to the CLI script)
2. **Override**: `--settings /path/to/settings.json`

### Settings Schema

```json
{
  "agent_servers": {
    "<agent-name>": {
      "command": "executable-path",
      "args": ["--flag1", "value1"],
      "env": {
        "ENV_VAR": "value"
      }
    }
  },
  "mcp_servers": [
    {
      "name": "server-name",
      "command": "/path/to/mcp-server",
      "args": ["--stdio"],
      "env": {
        "CONFIG": "value"
      }
    }
  ]
}
```

### Field Requirements

- `agent_servers`: Required object with at least one agent
- `agent_servers.<name>.command`: Required string (executable path)
- `agent_servers.<name>.args`: Optional array of strings
- `agent_servers.<name>.env`: Optional object of string key-value pairs
- `mcp_servers`: Optional array of MCP server configurations

### Example Configuration

```json
{
  "agent_servers": {
    "claude-code": {
      "command": "npx",
      "args": ["@zed-industries/claude-code-acp"],
      "env": {
        "ACP_PERMISSION_MODE": "acceptEdits",
        "ACP_DEBUG": "true"
      }
    },
    "gemini": {
      "command": "gemini",
      "args": ["--experimental-acp"]
    }
  }
}
```

## Output Modes

### text (Default)
Human-readable output with structured prefixes:
- Assistant messages: Direct output
- Plans: `[plan] <json>`
- Tool calls: `[tool] <kind> <title> @ <location>`
- Tool I/O: `[tool.in]` / `[tool.out]` with truncated content
- Diffs: `[diff] <json>`
- Terminal: `[term] created|output|exited|released`
- Permissions: `[permission] auto-allow|auto-deny <operation>`

### simple
Minimal output - only assistant message text (no metadata, no thought chunks)

### jsonl / json
Raw JSON-RPC protocol frames, one per line:
- All client→agent requests
- All agent→client responses and notifications
- Client metadata line: `{"jsonrpc":"2.0","method":"client/selected_agent",...}`
- No human-readable text

## Security & Permissions

### Workspace Jail
- All file operations confined to current working directory by default
- `--yolo` flag enables read-anywhere (writes still confined)
- Path canonicalization prevents traversal attacks

### Permission Model
Non-interactive permission handling based on CLI flags:

| Operation | Default | --write | --yolo |
|-----------|---------|---------|--------|
| Read (in workspace) | ✅ Allow | ✅ Allow | ✅ Allow |
| Read (outside workspace) | ❌ Deny | ❌ Deny | ✅ Allow |
| Write (in workspace) | ❌ Deny | ✅ Allow | ✅ Allow |
| Write (outside workspace) | ❌ Deny | ❌ Deny | ❌ Deny |
| Other operations | ✅ Allow | ✅ Allow | ✅ Allow |

Classification notes
- Read operations include file reads (e.g., `fs/read_text_file`).
- Write operations include file edits/creation (e.g., `fs/write_text_file`).
- Execute operations include terminal lifecycle (e.g., `terminal/create`).

### Environment Security
- No credential storage or management
- Environment variables from settings.json merged additively
- Parent process environment inherited but not modified
- Secrets should be provided via parent environment

## ACP Best Practices Coverage

Based on `specs/acp-client-best-practices.md`, acpcli implements:

### Core Protocol (✅ Full Coverage)
- [x] JSON-RPC 2.0 over stdio
- [x] Protocol version negotiation with minimum enforcement
- [x] Capability declaration and discovery
- [x] Session lifecycle (new, load with capability guard)
- [x] Prompt execution with streaming updates
- [x] All session update types (chunks, plans, tools, diffs)
- [x] Stop reason handling
- [x] Cancellation with proper cleanup

### Content & Resources (✅ Full Coverage)
- [x] Text content blocks
- [x] Resource links via @-mentions
- [x] URL and file path support
- [x] Home directory expansion
- [x] MIME type detection
- [x] Preference for links over embedded resources

### Tool Calls & Permissions (✅ Full Coverage)
- [x] Tool call lifecycle tracking
- [x] Permission request handling (non-interactive)
- [x] Tool metadata display (kind, title, locations)
- [x] Raw input/output snippets
- [x] Status transitions (pending→in_progress→completed/failed/cancelled)
- [x] Tool call merging semantics

### File System (✅ Full Coverage)
- [x] read_text_file with line/limit support
- [x] write_text_file with workspace jail
- [x] Path security and canonicalization
- [x] Optional read-everywhere mode

### Terminal Capability (✅ Full Coverage)
- [x] Terminal provider implementation
- [x] create_terminal, terminal_output, wait_for_terminal_exit
- [x] kill_terminal, release_terminal
- [x] Terminal event streaming
- [x] Non-standard capability flag when provider present

### Extensions (✅ Full Coverage)
- [x] Session modes (list, set, updates)
- [x] Slash commands (available_commands_update)
- [x] Priority levels in plans (high/medium/low)
- [x] Enhanced tool statuses
- [x] Command input hints
- [x] Meta field support foundation

### Error Handling (✅ Full Coverage)
- [x] Structured error reporting
- [x] Semantic exit codes
- [x] Transport fault handling
- [x] Protocol violation detection
- [x] Clear error messages

### Observability (✅ Full Coverage)
- [x] JSONL protocol mirroring
- [x] Bidirectional frame logging
- [x] Client metadata injection
- [x] No secrets in logs

## Implementation Status

### Compliance Checklist

#### Transport & Initialization
- [x] JSON-RPC 2.0 over stdio; logs on stderr
- [x] Sends `initialize(protocolVersion, clientCapabilities)`
- [x] Verifies returned `protocolVersion` ≥ minimum (static check)
- [ ] Authenticate when required (deferred - no interactive flow)

#### Sessions
- [x] Calls `session/new` with absolute `cwd`; forwards MCP servers
- [x] Uses `session/load` only if `loadSession` advertised (exits with error if unsupported)
- [x] Consumes replay via `session/load`

#### Prompt Turn & Streaming
- [x] Sends `session/prompt` with text + `resource_link` blocks
- [x] Processes all update types (message, thought, plan, tool, diff, commands, mode)
- [x] Handles plan entries with priority levels
- [x] Processes enhanced tool call statuses
- [x] Supports all stop reasons including max_turn_requests
- [ ] Chunk coalescing (optional optimization)

#### Tool Calls & Permissioning
- [x] Implements `session/request_permission` with allow/deny/cancelled
- [x] Tracks tool/diff updates for UI
- [x] Displays rich tool metadata
- [x] Supports all ACP tool kinds
- [x] Handles tool call locations with path and line number

#### File System Capability
- [x] `read_text_file` with line/limit windowing
- [x] `write_text_file` with workspace enforcement
- [x] Workspace jail with optional read-everywhere
- [ ] Soft cap for huge files (deferred - agents typically pass limits)

#### Terminal Capability (UNSTABLE)
- [x] All terminal methods implemented
- [x] Advertises `clientCapabilities.terminal` when provider present
- [x] Terminal event streaming
- [ ] Ring buffer with truncation (optional optimization)

#### Modes & Commands (Extensions)
- [x] Mode listing and selection
- [x] Current mode updates
- [x] Slash command discovery with input hints
- [x] Available commands waiting with timeout

#### Cancellation & Errors
- [x] `session/cancel` supported with Ctrl-C
- [x] Permission prompts resolved as cancelled
- [ ] Provider abort → StopReason mapping (agent-specific)

### Recently Resolved Issues

#### Tool Call Update Merging (Major Fix)
**Problem:** dart_acp incorrectly replaced entire tool calls when receiving updates, nullifying existing fields.

**Root Cause:** Updates were creating new ToolCall objects instead of merging fields into existing ones.

**Solution:** Implemented proper merge semantics following Zed's pattern:
- Added `ToolCall.merge()` method to only update non-null fields
- SessionManager maintains `_toolCalls` map to track tool calls by ID
- `tool_call` creates new entries, `tool_call_update` merges into existing

**Impact:** Fixed failing file operation tests for both Claude-code and Gemini agents.

#### Echo Agent Path Resolution
**Problem:** Echo agent tests failed when working directory changed to temp sandbox folders.

**Solution:** Tests now dynamically create temporary settings files with absolute paths for echo agent.

**Impact:** All 7 echo agent tests now pass with proper sandbox isolation.

#### Early Process Exit Detection
**Problem:** Agent crashes resulted in broken pipe errors instead of meaningful messages.

**Solution:** Added 100ms delay after spawn to detect immediate exits with clear error reporting.

#### Session Update Replay
**Problem:** `sessionUpdates()` wasn't including TurnEnded markers in replay buffer.

**Solution:** Added TurnEnded to replay buffer for proper session resumption.

#### Other Recent Fixes
- **CLI Test Paths**: Standardized to absolute paths for subprocess spawning
- **Invalid Session Handling**: Now throws ArgumentError instead of empty stream
- **API Design**: Changed to factory constructor pattern for clearer initialization
- **Permission Handling**: Fixed to respect configured permissions (no auto-allow)
- **Priority Support**: Plan entries now support high/medium/low priorities
- **Enhanced Statuses**: Tool calls use latest ACP status values
- **Tool Metadata**: Rich display of kind, title, and locations

## Testing Requirements

### Unit Testing
- Settings file parsing and validation
- Argument parsing
- Output formatting
- Permission decision logic

### E2E Testing
Location: `test/cli_app_e2e_test.dart`

Required test scenarios:
1. Basic prompt execution
2. Agent selection
3. Output modes (text, simple, jsonl)
4. List operations (caps, modes, commands)
5. Permission flags (--write, --yolo)
6. Session management (save, resume)
7. Mode switching
8. @-mention parsing
9. Cancellation handling
10. Error scenarios

### Test Agents
- **echo_agent**: Mock agent for basic testing
- **gemini**: Real agent with experimental ACP
- **claude-code**: Real agent via SDK adapter

### Test Workarounds
For issues with specific agent tests:
- Run tests with specific agents: `dart test --tags e2e -n "gemini"`
- Use manual testing for verification: `dart example/acpcli/acpcli.dart -a gemini "prompt"`
- Echo agent tests should always pass: `dart test --tags e2e -n "echo"`
- Ensure test/test_settings.json doesn't override `GEMINI_MODEL` for problematic models

## Known Issues & Limitations

### Agent-Specific Issues

#### Gemini Model Compatibility
**Status:** Partially improved in gemini-cli v0.6.0-nightly (as of Sep 13, 2025)

**Current State:**
- Default model (no `GEMINI_MODEL` env): Works for single prompt, **fails** on multiple prompts to same session
- `gemini-2.0-flash-exp`: **Broken** - returns empty output
- `gemini-2.5-flash`: **Works** for single prompts
- Terminal/execute operations: Not reported by agent (test skipped)

**Symptoms:**
- JSON-RPC error -32603: "Request contains an invalid argument" or "Internal error"
- Multiple prompts to same session fail with default model
- gemini-2.0-flash-exp returns empty output instead of error

**Root Cause:** Bug in Gemini's experimental ACP implementation (confirmed by comparison with Zed)

**Workaround:**
- Single prompts: Use default model or gemini-2.5-flash
- Multiple prompts: No working Gemini model currently
- Avoid gemini-2.0-flash-exp entirely
- Test specific models before production use

**E2E Test Results (after dart_acp fixes):**
- `create/manage sessions and cancellation`: **FAILS** (Gemini limitation)
- `session replay via sessionUpdates`: **PASSES**
- `file read operations`: **PASSES** (fixed by tool call merging)
- `file write operations`: **PASSES** (fixed by tool call merging)
- `execute via terminal`: **SKIPPED** (Gemini doesn't report execute tool calls)

#### Claude-code Test Environment
- File operations may timeout in rapid test scenarios
- Works correctly in manual testing
- May be related to rapid test execution handling

### Design Limitations

#### Non-Interactive Design
- No user prompts for permissions (by design)
- No interactive authentication flows
- No session management UI
- All permissions decided via CLI flags

#### Resource Constraints
- No chunk coalescing (may impact with high-frequency updates)
- No terminal output buffering limits
- No soft cap on file read sizes (agents typically pass limits)

## Future Work

### Authentication Support
- Implement `authenticate` method handling
- Support auth method selection
- Enable credential flow integration

### Performance Optimizations
- Chunk coalescing for high-frequency updates
- Terminal output ring buffer
- Soft file size limits

### Enhanced Features
- Model selection via CLI flag
- Session persistence across runs
- Interactive mode option
- Custom provider injection

### Testing Improvements
- @-mention parsing unit tests
- ContentBuilder coverage
- Mock agent enhancements
- Performance benchmarks

## Conclusion

`acpcli` provides a comprehensive, production-ready implementation of an ACP client that serves as both a reference implementation and a practical tool. It demonstrates proper usage of the `dart_acp` library while maintaining strict compliance with ACP specifications and best practices. The non-interactive design makes it ideal for automation, testing, and integration scenarios.
