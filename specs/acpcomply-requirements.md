# ACP Agent Compliance (acpcomply) – Requirements

This document defines the test model, JSON test schema, and a comprehensive test suite to verify an ACP Agent’s compliance using the existing `AcpClient` library. The compliance runner reads tests, builds a sandbox per test, drives an agent via JSON‑RPC (over stdio, NDJSON framing as used by `AcpClient`), and validates server messages with regex-based matchers.

Design constraints:
- No hardcoded test specifics in the runner. Adding new `.jsont` test files must not require runner code changes.
- The runner is method‑agnostic. It does not special‑case protocol methods; it generically sends requests and notifications defined by each test.
- Tests contain their own metadata (title, description, docs). The runner must not derive or hardcode descriptions.
- The schema is forward‑extensible; fields outside what the runner uses must be ignored safely.

## Goals

- Reuse `AcpClient` for transport, lifecycle, and hooks (FS, Permissions, Terminals).
- Keep the harness simple: JSON template tests (.jsont) + sandbox files + regex expectations.
- Cover the full ACP agent functionality: initialization, session, prompt turns, updates, tools, FS, terminals, modes, plans, slash commands, error handling, and MCP.
- Deterministic, secure: each test runs in a temporary sandbox workspace; permission policy is test‑configurable; MCP server spawned only for MCP tests.

## Compliance Areas (mapped to tests)

- Required
  - Initialize: version negotiation; agentCapabilities present
  - Session creation: `session/new` returns `sessionId`
  - Prompt cancellation: `session/cancel` → `stopReason = cancelled`
  - Capability respect: agent does not call client methods when capability is false (FS, Terminals)
  - Error handling: unknown method yields `-32601`
- Optional (conditional)
  - Session load: `session/load` replays updates then resolves
  - Content: `resource_link` (baseline); `resource` if `embeddedContext`; `image`/`audio` if enabled
  - Tool calls: `tool_call` + `tool_call_update` streaming
  - Permissions: `session/request_permission` decision and cancellation path
  - File system: `fs/read_text_file` and `fs/write_text_file`
  - Terminals: create/wait/output/kill/release
  - Modes: `session/set_mode` + `current_mode_update`
  - Plans: plan entries updates
  - Slash commands: `available_commands_update`
  - MCP (stdio): agent connects to a local stdio MCP server supplied by the test

## Test Model

- Each test is a JSON template file (.jsont). The test ID is derived from the filename (without the .jsont extension). The runner:
  1) Creates a per-test sandbox workspace and writes declared files.
  2) Reads the .jsont file as a string and interpolates template variables (e.g., `${protocolVersionDefault}`).
  3) Parses the interpolated string as JSON.
  4) Runs `initialize` once per agent (outside tests), captures `agentCapabilities` and other metadata (modes, commands) for the header.
  5) Executes test steps sequentially, using the sandbox as the session workspace (via `session/new`).
  6) Validates expectations against server messages (responses/notifications) and Agent→Client requests.
  7) Aggregates results into a Markdown report written to stdout (no tables; per‑agent header, then per‑test sections).

### Expectations (Regex Subset Matching)

- Tests provide partial server messages (responses, notifications, or Agent→Client requests) containing only fields they care about.
- Leaf string values are treated as regular expressions matched against the actual stringified value.
- Fields omitted in expected messages are ignored.
- Arrays are matched with “subset contains” semantics: expected array elements must be matched by at least one actual element; order is not enforced unless explicitly specified by repeating expectations.
- Multiple expected messages can be declared within a time window; extra (unmatched) server messages are ignored by default.
- Variables: basic `${var}` interpolation is supported for built‑in variables. Captures (extracting values from observed messages) are not currently supported.

### Agent→Client Requests

- Tests can expect Agent→Client requests (e.g., `fs/read_text_file`, `terminal/*`, `session/request_permission`) by specifying an expected request envelope. A `reply` may be provided to return a canned client result; if omitted, the real provider handles the request.
- Negative assertions: tests can declare methods that MUST NOT be received within a window (capability respect tests).

## JSON Template Test Schema

Top-level fields (required unless noted):

- `title` (string): Human-readable title
- `description` (string): What this test verifies in plain language
- `severity` (string): `required` | `optional`
- `docs` (string[]): Links to relevant docs/spec anchors
- `preconditions` (optional): Array of conditions to gate execution
  - `{ "agentCap": "mcpCapabilities.http", "mustBe": true }` (example)
  - `{ "cap": "client.fs.readTextFile", "mustBe": true }` (example)
- `sandbox` (object):
  - `files` (array): `{ path: string, text?: string, base64?: string }`
- `init` (optional):
  - `clientCapabilities` (object): override defaults per test
  - `permissionPolicy` (string, optional): default permissions policy for this test: one of `none` | `read` | `write` | `yolo`.
    - `none`: deny all operations
    - `read`: allow read operations; deny write/execute
    - `write`: allow read and write operations
    - `yolo`: allow all operations (default)

Steps array (`steps: []`) – each item is one of:

- `newSession` (object): create session with the sandbox as cwd
  - `mcpServers` (optional): full objects to pass through
  - `capture` (string): variable to store `sessionId`

- `send` (object): a single JSON-RPC frame to send (client→agent)
  - When `id` is present, the runner sends a JSON‑RPC request and awaits a response (or error if `expectError = true`).
  - When `id` is absent, the runner sends a JSON‑RPC notification (no response awaited).
  - `expectError` (boolean, optional): if true, expects a JSON‑RPC error response (default: false)

- `expect` (object): wait window for server messages
  - `timeoutMs` (number, default 10000)
  - `messages` (array of expected message envelopes). Each envelope is one of:
    - `response`: Partial JSON-RPC response with regex-valued fields (id/result/error)
    - `notification`: Partial JSON-RPC notification with regex-valued fields (method/params)
    - `clientRequest`: Partial Agent→Client request with regex-valued fields (method/params); optional `reply` can specify a canned client result. If omitted, the configured providers handle the request.
  - Note: Captures are not currently supported.

- `forbid` (object): declare Agent→Client method names that MUST NOT appear within a window
  - `timeoutMs` (number)
  - `methods` (string[]): e.g., `["fs/read_text_file"]`

- `delayMs` (number): simple delay before next step

Notes:
- String leaf values in any expected envelope are regexes.
- Non-string leaves are stringified before regex matching (e.g., `0` → "0").
- Arrays in expected messages behave as subset contains; specify only items you need to see.

### Built-in Variables

The runner provides these variables for interpolation in `send` frames and some expected envelopes:

- `${sandbox}`: Absolute path of the per-test workspace directory.
- `${protocolVersionDefault}`: Client’s latest supported protocol version.
- `${clientCapabilitiesDefault}`: Default client capabilities (fs.read=true, fs.write=true, terminal=true unless overridden by `init.clientCapabilities`).
- `${sessionId}`: When created via `newSession.capture`.

## Sample Report (stdout)

```
# ACP Compliance Report

Methodology: Initialized each agent, ran sandboxed tests using AcpClient over stdio (NDJSON). Expectations use regex subset matching over server responses/notifications and Agent→Client requests. MCP tests spawned a local stdio MCP server per run.

| Compliance Area                     | agent-claude | agent-gemini |
|-------------------------------------|--------------|--------------|
| Initialize                          | PASS         | PASS         |
| Session New                         | PASS         | PASS         |
| Prompt Cancel                       | PASS         | PASS         |
| Capability Respect (FS disabled)    | PASS         | FAIL [1]     |
| Capability Respect (Terminal off)   | NA           | PASS         |
| Unknown Method Error                | PASS         | PASS         |
| FS Read                             | PASS         | PASS         |
| FS Write                            | PASS         | PASS         |
| Terminal Usage                      | PARTIAL [2]  | PASS         |
| Modes                               | NA           | PASS         |
| Plans                               | PASS         | PASS         |
| Slash Commands                      | NA           | NA           |
| MCP (stdio)                         | PASS         | NA           |

[1] Agent attempted fs/read_text_file when client capability was false.
[2] Terminal/create observed, but no terminal/release received within timeout (optional).

## agent-claude Summary
- Caps: fs(read:true, write:true), terminal:true; mcpCapabilities.http:false
- Modes: not advertised
- Notes: Respected terminal disabled; attempted fs/read_text_file when fs disabled
- Links: Initialize, Capabilities, File System

## agent-gemini Summary
- Caps: fs(read:true, write:true), terminal:true; mcpCapabilities.http:true
- Modes: architect/code
- Notes: MCP connected, tool calls observed
- Links: MCP, Tool Calls, Terminals
```

## Example Tests

See `example/acpcomply/compliance-tests/` for a comprehensive suite. Representative samples (trimmed for brevity):

### required.initialize.jsont

```json
{
  "title": "Initialize negotiation",
  "severity": "required",
  "docs": [
    "https://agentclientprotocol.com/protocol/initialization",
    "https://agentclientprotocol.com/protocol/schema#initialize",
    "https://agentclientprotocol.com/protocol/schema#initializeresponse"
  ],
  "sandbox": { "files": [] },
  "steps": [
    {
      "send": {
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {
          "protocolVersion": ${protocolVersionDefault},
          "clientCapabilities": ${clientCapabilitiesDefault}
        }
      }
    },
    {
      "expect": {
        "timeoutMs": 3000,
        "messages": [
          {
            "response": {
              "jsonrpc": "2.0",
              "id": 0,
              "result": {
                "protocolVersion": "^\\d+$",
                "agentCapabilities": { "loadSession": "^(true|false)$" }
              }
            }
          }
        ],
        "captures": [ { "path": "result.protocolVersion", "var": "agentProtocolVersion" } ]
      }
    }
  ]
}
```

### required.prompt.cancel.jsont

```json
{
  "title": "Cancel a running prompt",
  "severity": "required",
  "docs": [
    "https://agentclientprotocol.com/protocol/prompt-turn#cancellation",
    "https://agentclientprotocol.com/protocol/schema#promptresponse",
    "https://agentclientprotocol.com/protocol/schema#stopreason"
  ],
  "sandbox": { "files": [] },
  "steps": [
    { "newSession": { "capture": "sessionId" } },
    {
      "send": {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "session/prompt",
        "params": { "sessionId": "${sessionId}", "prompt": [ { "type": "text", "text": "Think a bit then respond." } ] }
      }
    },
    { "delayMs": 200 },
    {
      "send": { "jsonrpc": "2.0", "method": "session/cancel", "params": { "sessionId": "${sessionId}" } }
    },
    {
      "expect": {
        "timeoutMs": 5000,
        "messages": [
          { "response": { "id": 2, "result": { "stopReason": "^cancelled$" } } }
        ]
      }
    }
  ]
}
```

### required.error.method-not-found.jsont

```json
{
  "title": "Unknown method → -32601",
  "severity": "required",
  "docs": [
    "https://www.jsonrpc.org/specification#error_object"
  ],
  "sandbox": { "files": [] },
  "steps": [
    { "newSession": { "capture": "sessionId" } },
    {
      "send": { "jsonrpc": "2.0", "id": 99, "method": "this/method/does/not/exist", "params": {} }
    },
    {
      "expect": {
        "timeoutMs": 2000,
        "messages": [
          { "response": { "id": 99, "error": { "code": "^-32601$" } } }
        ]
      }
    }
  ]
}
```

### required.capabilities.respect-fs-disabled.jsont

```json
{
  "title": "Agent must not call fs/* when capability is false",
  "severity": "required",
  "docs": [
    "https://agentclientprotocol.com/protocol/initialization#client-capabilities"
  ],
  "init": { "clientCapabilities": { "fs": { "readTextFile": false, "writeTextFile": false }, "terminal": true } },
  "sandbox": { "files": [ { "path": "greeting.txt", "text": "hello" } ] },
  "steps": [
    { "newSession": { "capture": "sessionId" } },
    {
      "send": { "jsonrpc": "2.0", "id": 5, "method": "session/prompt", "params": { "sessionId": "${sessionId}", "prompt": [ { "type": "text", "text": "Read greeting.txt and tell me its contents." } ] } }
    },
    {
      "forbid": { "timeoutMs": 5000, "methods": [ "fs/read_text_file", "fs/write_text_file" ] }
    }
  ]
}
```
