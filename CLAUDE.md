# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Running Tests
```bash
# Run unit tests only (recommended for quick testing)
dart test --exclude-tags e2e

# Run all tests including e2e (requires real agents)
dart test

# Run only e2e tests (requires Gemini/Claude Code)
dart test --tags e2e

# Run a specific test file
dart test test/unit_capabilities_test.dart

# Run tests matching a name pattern
dart test -n "session"
```

### Code Quality
```bash
# Analyze code for issues
dart analyze

# Format code
dart format .

# Check formatting without applying changes
dart format --set-exit-if-changed .
```

### Running the Example CLI
```bash
# Basic usage with default agent
dart example/main.dart "Your prompt here"

# Use a specific agent from settings.json
dart example/main.dart -a gemini "Summarize README.md"
dart example/main.dart -a claude-code "Analyze code"

# Different output modes
dart example/main.dart -o jsonl "Your prompt"  # JSONL output
dart example/main.dart -o simple "Your prompt"  # Simple text only

# With permissions
dart example/main.dart --write "Create a file"  # Enable write
dart example/main.dart --yolo "Search system"   # Read everywhere + write
```

## Architecture Overview

### Core Components

1. **AcpClient** (`lib/src/acp_client.dart`): Main entry point that orchestrates the entire ACP client lifecycle. Manages transport, RPC peer, and session manager.

2. **SessionManager** (`lib/src/session/session_manager.dart`): Handles ACP session lifecycle including initialize, new/load session, prompt streaming, and cancellation. Emits typed `AcpUpdate` events.

3. **Transport Layer** (`lib/src/transport/`): Abstraction for communication channels. Primary implementation is `StdioTransport` that spawns agent processes and communicates via stdin/stdout.

4. **RPC Layer** (`lib/src/rpc/`): JSON-RPC 2.0 peer implementation that handles bidirectional communication, including agent-to-client callbacks.

5. **Providers** (`lib/src/providers/`):
   - **FsProvider**: Handles filesystem operations with workspace jail enforcement
   - **PermissionProvider**: Manages permission requests from agents
   - **TerminalProvider**: Manages terminal process lifecycle and events

6. **Security** (`lib/src/security/workspace_jail.dart`): Enforces filesystem access restrictions based on workspace root and capabilities.

7. **Models** (`lib/src/models/`):
   - **updates.dart**: Strongly-typed ACP update events (plans, chunks, tool calls, diffs)
   - **types.dart**: Core ACP protocol types
   - **terminal_events.dart**: Terminal lifecycle events

### Key Design Patterns

- **Stream-based Architecture**: Updates flow as a single ordered stream of `AcpUpdate` events
- **Provider Pattern**: Pluggable providers for FS, permissions, and terminal operations
- **Transport Abstraction**: Protocol-agnostic transport layer (stdio, TCP/WebSocket possible)
- **Capability Negotiation**: Client and agent exchange capabilities during initialization

### Agent Configuration

Agents are configured in `example/settings.json`:
- `agent_servers`: Defines available agents with command, args, and environment
- `mcp_servers`: Optional MCP server configurations forwarded to agents
- Default agent is the first listed; use `-a` flag to select specific agent

### Session Flow

1. **Initialize**: Negotiate protocol version and capabilities
2. **Create Session**: `session/new` with workspace root or `session/load` for existing
3. **Send Prompt**: Stream content blocks, receive typed updates
4. **Handle Callbacks**: Respond to FS operations and permission requests
5. **Cancel/Complete**: Clean shutdown with proper cancellation handling

## Testing Strategy

- **Unit Tests** (`test/unit_*.dart`): Test individual components in isolation
- **E2E Tests** (`test/*_e2e_*.dart`): Full integration tests with real agents
- **Mock Agent** (`example/mock_agent.dart`): For testing without external dependencies

## Important Notes

- The library is transport-agnostic and UI-agnostic
- No credential management - relies on environment variables from host
- Strict workspace jail enforcement for filesystem operations
- All agent interactions follow ACP specification (agentclientprotocol.com)
- Example CLI reads `settings.json` from script directory, not CWD
- Use `@zed-industries/claude-code-acp` adapter for Claude Code (not `acp-claude-code`) as it properly sends available_commands_update