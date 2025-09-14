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

# Run specific agent tests
dart test --tags e2e -n "claude-code"
dart test --tags e2e -n "gemini"
```

### Code Quality
```bash
# Analyze code for issues
dart analyze

# Analyze specific directories (excludes tmp/)
dart analyze lib test

# Format code
dart format .

# Check formatting without applying changes
dart format --set-exit-if-changed .
```

### Running the Example CLI
```bash
# Basic usage with default agent
dart example/acpcli/acpcli.dart "Your prompt here"

# Use a specific agent from settings.json
dart example/acpcli/acpcli.dart -a gemini "Summarize README.md"
dart example/acpcli/acpcli.dart -a claude-code "Analyze code"

# Different output modes
dart example/acpcli/acpcli.dart -o jsonl "Your prompt"  # JSONL output
dart example/acpcli/acpcli.dart -o simple "Your prompt"  # Simple text only

# With permissions
dart example/acpcli/acpcli.dart --write "Create a file"  # Enable write
dart example/acpcli/acpcli.dart --yolo "Search system"   # Read everywhere + write

# List agent capabilities
dart example/acpcli/acpcli.dart -a claude-code --list-caps
dart example/acpcli/acpcli.dart -a claude-code --list-modes
dart example/acpcli/acpcli.dart -a claude-code --list-commands
```

## Architecture Overview

### Core Components

1. **AcpClient** (`lib/src/acp_client.dart`): Main entry point that orchestrates the entire ACP client lifecycle. Manages transport, RPC peer, and session manager.

2. **SessionManager** (`lib/src/session/session_manager.dart`): 
   - Handles ACP session lifecycle including initialize, new/load session, prompt streaming, and cancellation
   - Emits typed `AcpUpdate` events
   - **CRITICAL**: Maintains `_toolCalls` map to track tool calls by ID for proper merge semantics on updates

3. **Transport Layer** (`lib/src/transport/`): 
   - Abstraction for communication channels
   - `StdioTransport` spawns agent processes and communicates via stdin/stdout
   - Handles early process exit detection with 100ms delay

4. **RPC Layer** (`lib/src/rpc/`): 
   - JSON-RPC 2.0 peer implementation
   - `LineChannel` handles newline-delimited JSON frames
   - Bidirectional communication including agent-to-client callbacks

5. **Providers** (`lib/src/providers/`):
   - **FsProvider**: Handles filesystem operations with workspace jail enforcement
   - **PermissionProvider**: Manages permission requests from agents
   - **TerminalProvider**: Manages terminal process lifecycle and events

6. **Security** (`lib/src/security/workspace_jail.dart`): 
   - Enforces filesystem access restrictions based on workspace root and capabilities
   - Prevents path traversal attacks

7. **Models** (`lib/src/models/`):
   - **updates.dart**: Strongly-typed ACP update events (plans, chunks, tool calls, diffs)
   - **tool_types.dart**: Tool call types with `merge()` method for proper update handling
   - **types.dart**: Core ACP protocol types
   - **terminal_events.dart**: Terminal lifecycle events

### Key Implementation Details

#### Tool Call Update Merging
The SessionManager properly handles tool call updates by:
1. Tracking tool calls in `_toolCalls` map indexed by session ID and tool call ID
2. Distinguishing between `tool_call` (new) and `tool_call_update` (merge)
3. Using `ToolCall.merge()` to only update non-null fields, preserving existing metadata

#### CLI Test Path Handling
CLI tests use consistent absolute paths via `path.join(Directory.current.path, 'example', 'acpcli', 'acpcli.dart')` for subprocess spawning.

### Agent Configuration

Agents are configured in `example/settings.json`:
- `agent_servers`: Defines available agents with command, args, and environment
- `mcp_servers`: Optional MCP server configurations forwarded to agents
- Default agent is the first listed; use `-a` flag to select specific agent

Example configuration:
```json
{
  "agent_servers": {
    "gemini": {
      "command": "gemini",
      "args": ["--experimental-acp"]
    },
    "claude-code": {
      "command": "npx",
      "args": ["@zed-industries/claude-code-acp"]
    }
  }
}
```

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
- **Test Settings**: E2E tests use `test/test_settings.json` for agent configuration

## Known Issues and Limitations

### Gemini Agent
- Multiple prompts to same session may fail (agent limitation)
- Terminal/execute tool calls not reported as expected (test skipped)
- Some models (e.g., gemini-2.0-flash-exp) have ACP implementation bugs

### Testing Notes
- Scratch/debug files should be created in `tmp/` folder
- Tests should be silent on success (no print statements except for debugging)
- No try-catch blocks in tests or example apps unless explicitly needed

## Important Notes

- **Temporary files**: Always use the `tmp/` folder at the project root for temporary files, test outputs, debug logs, or any transient data
- The library is transport-agnostic and UI-agnostic
- No credential management - relies on environment variables from host
- Strict workspace jail enforcement for filesystem operations
- All agent interactions follow ACP specification (agentclientprotocol.com)
- Example CLI reads `settings.json` from script directory, not CWD
- Use `@zed-industries/claude-code-acp` adapter for Claude Code (properly sends available_commands_update)