# ACP Client Compliance — dart_acp

This document tracks conformance of `dart_acp` against the ACP spec and best practices. It lists the checklist, what we implemented in this round, and what’s deferred.

## Round Scope (This PR)

- Enforce minimum protocol version (static in `AcpConfig`) — Implemented
- Guard `session/load` behind the `loadSession` capability — Implemented (CLI exits with error when unsupported)
- Modes (extension): discover, list, and set — Implemented (`--list-modes`, `--mode`, typed `current_mode_update`)
- Terminal probe helper stability (tests) — Implemented (fixes early return)
- Display richer tool metadata in text mode — Implemented (`[tool]`, `[tool.in]`, `[tool.out]`)
- Permission handling — Fixed to respect configured permissions (no auto-allow)
- **NEW**: Plan entries with priorities — Implemented (high/medium/low priority levels)
- **NEW**: Enhanced tool call statuses — Implemented (pending/in_progress/completed/failed/cancelled)
- **NEW**: Tool kinds and locations — Implemented (read/edit/delete/move/search/execute/think/fetch/other)
- **NEW**: Command input hints — Implemented (hint field for slash commands)
- **NEW**: Updated stop reasons — Implemented (max_turn_requests support)
- **NEW**: Meta field support foundation — Implemented (base AcpType class)
- Gemini ACP compatibility — Investigated; found bug in Gemini's experimental ACP implementation (session/prompt fails)

Deferred: authentication flow, model selection flags, terminal buffering, chunk coalescing, write guard.

## Checklist

- Transport & Initialization
  - [x] JSON‑RPC 2.0 over stdio; logs on stderr
  - [x] Sends `initialize(protocolVersion, clientCapabilities)`
  - [x] Verifies returned `protocolVersion` ≥ minimum (static) — `AcpConfig.minimumProtocolVersion`
  - [ ] Authenticate when required (expose auth flow and retry)

- Sessions
  - [x] Calls `session/new` with absolute `cwd`; forwards MCP servers
  - [x] Uses `session/load` only if `loadSession` is advertised — CLI exits with error if `--resume` and unsupported
  - [x] Consumes replay via `session/load` (existing support)

- Prompt Turn & Streaming
  - [x] Sends `session/prompt` with text + `resource_link` blocks
  - [x] Processes `agent_message_chunk`, `agent_thought_chunk`, `plan`, `tool_call(_update)`, `available_commands_update`, `current_mode_update`
  - [x] **NEW**: Handles plan entries with priority levels (high/medium/low)
  - [x] **NEW**: Processes enhanced tool call statuses (pending/in_progress/completed/failed/cancelled)
  - [x] **NEW**: Supports max_turn_requests stop reason
  - [ ] Coalesce chunks (optional)

- Tool Calls & Permissioning
  - [x] Implements `session/request_permission` with allow/deny/cancelled
  - [x] Tracks tool/diff updates for UI
  - [x] Display richer tool metadata (title/locations/raw_* in text mode)
  - [x] **NEW**: Supports all ACP tool kinds (read/edit/delete/move/search/execute/think/fetch/other)
  - [x] **NEW**: Handles tool call locations with path and optional line number

- File System Capability
  - [x] `fs/read_text_file` (line/limit) and `fs/write_text_file`
  - [x] Workspace jail; optional read-everywhere (`--yolo`)
  - [ ] Soft cap for huge files when no limit (optional)

- Terminal Capability (UNSTABLE)
  - [x] `create_terminal`, `terminal_output`, `wait_for_terminal_exit`, `kill_terminal`, `release_terminal`
  - [x] Advertises non-standard `clientCapabilities.terminal` when provider present
  - [x] Test helper probe fixed to avoid flaky skips
  - [ ] Ring buffer + truncation flag (optional)

- Modes Selection (Extensions)
  - [x] Modes extension: list (`--list-modes`), set (`--mode`), `current_mode_update` routed
  - [x] **NEW**: Enhanced command support with input hints

- Authentication
  - [ ] Present `authMethods`, run chosen flow, retry `session/new`

- Cancellation & Errors
  - [x] `session/cancel` supported; permission prompts cancel
  - [ ] Map provider aborts to `StopReason::Cancelled` (error mapping)

## Implementation Notes

- Minimum Protocol Version: `AcpConfig.minimumProtocolVersion` is a manual static constant; `SessionManager.initialize()` enforces it and throws a clear error when violated.
- Guarded `session/load`: CLI checks `initialize.result.agentCapabilities.loadSession === true` when `--resume` is provided; otherwise prints a descriptive error and exits with code 2.
- Modes: `SessionManager.newSession()` captures `modes` from the session response; `AcpClient.sessionModes(sessionId)` exposes current/available modes; `AcpClient.setMode()` calls `session/set_mode`; `current_mode_update` is surfaced via `ModeUpdate`.
- **NEW**: Plan Priorities: Updated `Plan` and `PlanEntry` models to support ACP priority levels (high/medium/low) with proper enum types and wire format conversion.
- **NEW**: Enhanced Tool Call Status: Updated `ToolCallStatus` enum to match latest ACP spec (pending/in_progress/completed/failed/cancelled) with backward compatibility for legacy values.
- **NEW**: Tool Kinds & Locations: Added `ToolKind` enum and `ToolCallLocation` class to properly model tool categories and file locations per ACP specification.
- **NEW**: Command Input Hints: Added `AvailableCommandInput` class to support input specifications with hints for slash commands.
- **NEW**: Stop Reason Enhancement: Added `max_turn_requests` to `StopReason` enum to support latest ACP specification.
- **NEW**: Meta Field Foundation: Added base `AcpType` class to support `_meta` fields for protocol extensibility.
- Terminal Probe (tests): `test/helpers/adapter_caps.dart` now returns success only when a `tool_call_update` includes a `{"type":"terminal"}` block; result cached per adapter.
- Richer Tool Metadata (text mode): Text mode prints a human-readable header `[tool] <kind> <title>` and first location `@ path/uri` when present, followed by `[tool.in]`/`[tool.out]` snippets from `raw_input`/`raw_output` (truncated).
  - Print logic: `example/main.dart`
  - Parsed fields: `lib/src/models/tool_types.dart` (`title`, `locations`, `raw_input`, `raw_output`)
- Large Files (soft cap rationale): Prompts use `resource_link` for files (not embedded bytes), keeping payloads small. FS reads can still return whole files if an agent omits `line/limit`, but typical adapters pass limits. We're deferring a soft cap unless we see real-world issues.
- Permission Handling: Fixed to respect configured permissions from `AcpConfig` and CLI args. No auto-allowing; agents that request more permissions than granted will receive denial responses.
- Gemini Compatibility: Gemini's experimental ACP implementation works correctly with the default model. However, certain models (like `gemini-2.0-flash-exp` and `gemini-2.5-flash`) cause `session/prompt` requests to fail with "Invalid argument" errors. Do not set `GEMINI_MODEL` environment variable unless you've verified the specific model works with ACP.
