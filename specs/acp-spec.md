# Agent Client Protocol (ACP) Specification
# Source: https://agentclientprotocol.com (Official Documentation)
Repository: https://github.com/zed-industries/agent-client-protocol

## Table of Contents

- [Overview](#overview)
  - [Architecture Overview](#architecture-overview)
- [Communication Model](#communication-model)
  - [Message Flow](#message-flow)
- [Agent Interface](#agent-interface)
- [Client Interface](#client-interface)
- [Argument Requirements](#argument-requirements)
- [Error Handling](#error-handling)
  - [Error Mapping](#error-mapping)
- [Initialization](#initialization)
  - [Protocol Version](#protocol-version)
  - [Version Negotiation](#version-negotiation)
  - [Capabilities](#capabilities)
  - [Authentication](#authentication)
- [Session Setup](#session-setup)
  - [Creating a Session](#creating-a-session)
  - [Loading Sessions](#loading-sessions)
- [Prompt Turn](#prompt-turn)
  - [The Prompt Turn Lifecycle](#the-prompt-turn-lifecycle)
  - [Session Updates](#session-updates)
- [Content](#content)
  - [Content Types](#content-types)
- [File System](#file-system)
  - [Reading Files](#reading-files)
  - [Writing Files](#writing-files)
- [Tool Calls](#tool-calls)
- [Terminals](#terminals)
  - [Executing Commands](#executing-commands)
  - [Getting Output](#getting-output)
  - [Waiting for Exit](#waiting-for-exit)
  - [Killing Commands](#killing-commands)
  - [Releasing Terminals](#releasing-terminals)
- [Session Modes](#session-modes)
  - [Initial State](#initial-state)
  - [Setting the Current Mode](#setting-the-current-mode)
- [Agent Plan](#agent-plan)
  - [Creating Plans](#creating-plans)
  - [Updating Plans](#updating-plans)
- [Slash Commands](#slash-commands)
  - [Advertising Commands](#advertising-commands)
  - [Running Commands](#running-commands)
- [Extensibility](#extensibility)
  - [The _meta Field](#the-meta-field)
  - [Extension Methods](#extension-methods)
  - [Advertising Custom Capabilities](#advertising-custom-capabilities)
- [Transport](#transport)
  - [Wire Format Examples](#wire-format-examples)
- [Supported Editors](#supported-editors)
- [Supported Agents](#supported-agents)
- [Libraries and Schema](#libraries-and-schema)
- [Type Reference](#type-reference)
  - [Identifiers](#identifiers)
  - [Capabilities](#capabilities-1)
  - [MCP Servers](#mcp-servers-1)
  - [Content Blocks](#content-blocks)
  - [Authentication](#authentication-1)
  - [Tool Calls](#tool-calls-1)
  - [Plans](#plans)
  - [Permissions](#permissions)
  - [Terminals](#terminals-1)
  - [Validation Tips](#validation-tips)
- [Reference Flows](#reference-flows)
  - [Client Happy Path](#client-happy-path)
  - [Agent Happy Path](#agent-happy-path)
- [Compliance](#compliance)
  - [Agent Checklist](#agent-checklist)
  - [Client Checklist](#client-checklist)

## Overview

Docs: [Introduction](https://agentclientprotocol.com/overview/introduction) • [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • GitHub: [docs/overview/introduction.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/overview/introduction.mdx), [docs/protocol/overview.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/overview.mdx)

The Agent Client Protocol (ACP) standardizes communication between code editors (IDEs, text-editors, etc.) and coding agents (programs that use generative AI to autonomously modify code).

The protocol is still under development, but it should be complete enough to build interesting user experiences using it.

### Why ACP?

AI coding agents and editors are tightly coupled but interoperability isn't the default. Each editor must build custom integrations for every agent they want to support, and agents must implement editor-specific APIs to reach users.

This creates several problems:
- Integration overhead: Every new agent-editor combination requires custom work
- Limited compatibility: Agents work with only a subset of available editors
- Developer lock-in: Choosing an agent often means accepting their available interfaces

ACP solves this by providing a standardized protocol for agent-editor communication, similar to how the Language Server Protocol (LSP) standardized language server integration.

Agents that implement ACP work with any compatible editor. Editors that support ACP gain access to the entire ecosystem of ACP-compatible agents. This decoupling allows both sides to innovate independently while giving developers the freedom to choose the best tools for their workflow.

### Architecture Overview

Docs: [Architecture](https://agentclientprotocol.com/overview/architecture) • GitHub: [docs/overview/architecture.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/overview/architecture.mdx)

ACP assumes that the user is primarily in their editor, and wants to reach out and use agents to assist them with specific tasks.

Agents run as sub-processes of the code editor, and communicate using JSON-RPC over stdio. The protocol re-uses the JSON representations used in MCP where possible, but includes custom types for useful agentic coding UX elements, like displaying diffs.

The default format for user-readable text is Markdown, which allows enough flexibility to represent rich formatting without requiring that the code editor is capable of rendering HTML.

## Communication Model

Docs: [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • GitHub: [docs/protocol/overview.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/overview.mdx)

The protocol follows the JSON-RPC 2.0 specification with two types of messages:

- **Methods**: Request-response pairs that expect a result or error
- **Notifications**: One-way messages that don't expect a response

### Message Flow

A typical flow follows this pattern:

1. **Initialization Phase**
   - Client → Agent: `initialize` to establish connection
   - Client → Agent: `authenticate` if required by the Agent

2. **Session Setup - either:**
   - Client → Agent: `session/new` to create a new session
   - Client → Agent: `session/load` to resume an existing session if supported

3. **Prompt Turn**
   - Client → Agent: `session/prompt` to send user message
   - Agent → Client: `session/update` notifications for progress updates
   - Agent → Client: File operations or permission requests as needed
   - Client → Agent: `session/cancel` to interrupt processing if needed
   - Turn ends and the Agent sends the `session/prompt` response with a stop reason

## Agent Interface

Docs: [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • GitHub: [docs/protocol/overview.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/overview.mdx)

Agents are programs that use generative AI to autonomously modify code. They typically run as subprocesses of the Client.

### Baseline Methods

**initialize**
Negotiate versions and exchange capabilities.

**authenticate** 
Authenticate with the Agent (if required).

**session/new**
Create a new conversation session.

**session/prompt**
Send user prompts to the Agent.

### Optional Methods

**session/load**
Load an existing session (requires `loadSession` capability).

**session/set_mode**
Switch between agent operating modes.

### Notifications

**session/cancel**
Cancel ongoing operations (no response expected).

## Client Interface

Docs: [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • GitHub: [docs/protocol/overview.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/overview.mdx)

Clients provide the interface between users and agents. They are typically code editors (IDEs, text editors) but can also be other UIs for interacting with agents. Clients manage the environment, handle user interactions, and control access to resources.

### Baseline Methods

**session/request_permission**
Request user authorization for tool calls.

### Optional Methods

**fs/read_text_file**
Read file contents (requires `fs.readTextFile` capability).

**fs/write_text_file**
Write file contents (requires `fs.writeTextFile` capability).

**terminal/create**
Create a new terminal (requires `terminal` capability).

**terminal/output**
Get terminal output and exit status (requires `terminal` capability).

**terminal/release**
Release a terminal (requires `terminal` capability).

**terminal/wait_for_exit**
Wait for terminal command to exit (requires `terminal` capability).

**terminal/kill**
Kill terminal command without releasing (requires `terminal` capability).

### Notifications

**session/update**
Send session updates to inform the Client of changes (no response expected). This includes:
- Message chunks (agent, user, thought)
- Tool calls and updates
- Plans
- Available commands updates
- Mode changes

## Argument Requirements

Docs: [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • [Schema](https://agentclientprotocol.com/protocol/schema) • GitHub: [schema/schema.json](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/schema/schema.json)

- All file paths in the protocol **MUST** be absolute.
- Line numbers are 1-based

## Error Handling

Docs: [Protocol Overview](https://agentclientprotocol.com/protocol/overview) • [Error](https://agentclientprotocol.com/protocol/error) • GitHub: [docs/protocol/overview.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/overview.mdx), [rust/error.rs](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/rust/error.rs)

All methods follow standard [JSON-RPC 2.0 error handling](https://www.jsonrpc.org/specification#error_object):

- Successful responses include a `result` field
- Errors include an `error` object with `code`, `message`, and optional `data`
- Notifications never receive responses (success or error)

### Error Codes

The protocol uses standard JSON-RPC error codes and ACP-specific codes in the reserved range (-32000 to -32099):

#### Standard JSON-RPC Error Codes
- `-32700` **Parse Error**: Invalid JSON was received by the server
- `-32600` **Invalid Request**: The JSON sent is not a valid Request object
- `-32601` **Method Not Found**: The method does not exist or is not available
- `-32602` **Invalid Params**: Invalid method parameter(s)
- `-32603` **Internal Error**: Internal JSON-RPC error

#### ACP-Specific Error Codes
- `-32000` **Authentication Required**: Authentication is required before this operation can be performed
- `-32001` to `-32099`: Reserved for implementation-defined server errors (e.g., rate limiting, permission denied)

### Error Response Structure

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": {
      "method": "_example.com/custom_method",
      "reason": "Custom method not supported"
    }
  }
}
```

### Error Mapping Guidelines

Implementations should map ACP semantics to JSON-RPC errors consistently:

#### Version Negotiation Mismatch
Agents SHOULD NOT return an error when the requested `protocolVersion` is unsupported.
Instead, respond from `initialize` with the latest version the Agent supports. If the
Client doesn't support that version, it SHOULD close the connection and inform the user.

#### Authentication Required
When authentication is needed for `session/new` or `session/load`:
- Return error code `-32000` (Authentication Required)
- Include in `error.data`:
  - `reason`: `"auth_required"`
  - `authMethods`: Available authentication methods
- Clients SHOULD respond by calling `authenticate`

#### Capability Not Implemented
When receiving an unsupported method (e.g., optional `terminal/*` methods):
- Return error code `-32601` (Method Not Found)
- Include method name in `error.data.method` if helpful

#### Invalid Parameters
For structurally invalid or schema-violating inputs:
- Return error code `-32602` (Invalid Params)
- Provide concise, actionable message
- Include validation details in `error.data` when helpful

#### Internal Errors
For unexpected server errors:
- Return error code `-32603` (Internal Error)
- Use generic message to avoid leaking sensitive information
- Consider including `error.data.correlationId` for diagnostics
- Never expose stack traces in production

#### Cancellation Handling
Cancellation is NOT an error condition:
- For `session/prompt`: Return `result.stopReason = "cancelled"` after flushing pending updates
- For `session/request_permission`: Return `result.outcome = { outcome: "cancelled" }`
- Never return an error for user-initiated cancellation

#### Tool Execution Failures
Tool failures should be reported as part of normal flow:
- Use `session/update` with tool call status `"failed"`
- Include error details in tool call's `content` or `rawOutput`
- Only fail `session/prompt` for catastrophic errors

#### Rate Limiting and Permissions
For domain-specific restrictions:
- Use application error codes in range `-32001` to `-32099`
- Include in `error.data`:
  - `reason`: `"rate_limited"` or `"permission_denied"`
  - `retryAfter`: Seconds until retry allowed (for rate limiting)
  - `scope`: What permission was denied (for authorization)

### Implementation Best Practices

1. **Consistent Error Codes**: Always use the same error code for the same type of error
2. **Helpful Messages**: Provide clear, actionable error messages
3. **Structured Data**: Use `error.data` for machine-readable details
4. **Graceful Degradation**: Clients should handle unknown error codes gracefully
5. **No Silent Failures**: Always report errors explicitly
6. **Validation First**: Validate inputs early and return clear parameter errors
7. **Security Conscious**: Never leak implementation details or sensitive data in errors

## Initialization

Docs: [Initialization](https://agentclientprotocol.com/protocol/initialization) • GitHub: [docs/protocol/initialization.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/initialization.mdx) • Schema: [initialize](https://agentclientprotocol.com/protocol/schema#initialize) • [InitializeResponse](https://agentclientprotocol.com/protocol/schema#initializeresponse) • [ClientCapabilities](https://agentclientprotocol.com/protocol/schema#clientcapabilities) • [AgentCapabilities](https://agentclientprotocol.com/protocol/schema#agentcapabilities) • [PromptCapabilities](https://agentclientprotocol.com/protocol/schema#promptcapabilities) • [McpCapabilities](https://agentclientprotocol.com/protocol/schema#mcpcapabilities) • [ProtocolVersion](https://agentclientprotocol.com/protocol/schema#protocolversion)

The Initialization phase allows Clients and Agents to negotiate protocol versions, capabilities, and authentication methods.

Before a Session can be created, Clients **MUST** initialize the connection by calling the `initialize` method with:

- The latest protocol version supported
- The capabilities supported

```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "protocolVersion": 1,
    "clientCapabilities": {
      "fs": {
        "readTextFile": true,
        "writeTextFile": true
      },
      "terminal": true
    }
  }
}
```

The Agent **MUST** respond with the chosen protocol version and the capabilities it supports:

```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "result": {
    "protocolVersion": 1,
    "agentCapabilities": {
      "loadSession": true,
      "promptCapabilities": {
        "image": true,
        "audio": true,
        "embeddedContext": true
      },
      "mcpCapabilities": {
        "http": true,
        "sse": true
      }
    },
    "authMethods": []
  }
}
```

### Protocol Version

The protocol versions that appear in the `initialize` requests and responses are a single integer that identifies a **MAJOR** protocol version. This version is only incremented when breaking changes are introduced.

Clients and Agents **MUST** agree on a protocol version and act according to its specification.

### Version Negotiation

The `initialize` request **MUST** include the latest protocol version the Client supports.

If the Agent supports the requested version, it **MUST** respond with the same version. Otherwise, the Agent **MUST** respond with the latest version it supports.

If the Client does not support the version specified by the Agent in the `initialize` response, the Client **SHOULD** close the connection and inform the user about it.

### Capabilities

Capabilities describe features supported by the Client and the Agent.

All capabilities included in the `initialize` request are **OPTIONAL**. Clients and Agents **SHOULD** support all possible combinations of their peer's capabilities.

The introduction of new capabilities is not considered a breaking change. Therefore, Clients and Agents **MUST** treat all capabilities omitted in the `initialize` request as **UNSUPPORTED**.

#### Client Capabilities

The Client **SHOULD** specify whether it supports the following capabilities:

**File System**
- `readTextFile` (boolean): The `fs/read_text_file` method is available.
- `writeTextFile` (boolean): The `fs/write_text_file` method is available.

**Terminal**
- `terminal` (boolean): All `terminal/*` methods are available, allowing the Agent to execute and manage shell commands.

#### Agent Capabilities

The Agent **SHOULD** specify whether it supports the following capabilities:

**loadSession** (boolean, default: false): The `session/load` method is available.

**promptCapabilities** (PromptCapabilities Object): Object indicating the different types of content that may be included in `session/prompt` requests.

**Prompt capabilities**
As a baseline, all Agents **MUST** support `ContentBlock::Text` and `ContentBlock::ResourceLink` in `session/prompt` requests.

Optionally, they **MAY** support richer types of content by specifying the following capabilities:
- `image` (boolean, default: false): The prompt may include `ContentBlock::Image`
- `audio` (boolean, default: false): The prompt may include `ContentBlock::Audio`
- `embeddedContext` (boolean, default: false): The prompt may include `ContentBlock::Resource`

**mcpCapabilities**
- `http` (boolean, default: false): The Agent supports connecting to MCP servers over HTTP.
- `sse` (boolean, default: false): The Agent supports connecting to MCP servers over SSE. Note: This transport has been deprecated by the MCP spec.

### Authentication

Some agents require authentication before allowing session creation.

Docs: [Initialization](https://agentclientprotocol.com/protocol/initialization) • Schema: [`authenticate`](https://agentclientprotocol.com/protocol/schema#authenticate) • [AuthenticateResponse](https://agentclientprotocol.com/protocol/schema#authenticateresponse) • [AuthMethod](https://agentclientprotocol.com/protocol/schema#authmethod) • [AuthMethodId](https://agentclientprotocol.com/protocol/schema#authmethodid)

- Method: `authenticate`
- When required: Agents advertise available methods in `initialize.result.authMethods`.
- Request params:
  - `methodId` (AuthMethodId, required): One of the IDs returned in `authMethods`.
- Response: `{}` on success.
- Errors: `session/new` and `session/load` MAY return an `auth_required` error until authentication succeeds.

Flow:
- Client calls `initialize`, inspects `authMethods`.
- If non-empty and the agent returns `auth_required` on `session/new`, call `authenticate` with a chosen `methodId`.
- Retry `session/new` after successful authentication.

## Session Setup

Docs: [Session Setup](https://agentclientprotocol.com/protocol/session-setup) • GitHub: [docs/protocol/session-setup.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/session-setup.mdx) • Schema: [NewSessionRequest](https://agentclientprotocol.com/protocol/schema#newsessionrequest) • [NewSessionResponse](https://agentclientprotocol.com/protocol/schema#newsessionresponse) • [LoadSessionRequest](https://agentclientprotocol.com/protocol/schema#loadsessionrequest) • [LoadSessionResponse](https://agentclientprotocol.com/protocol/schema#loadsessionresponse) • [McpServer](https://agentclientprotocol.com/protocol/schema#mcpserver) • [EnvVariable](https://agentclientprotocol.com/protocol/schema#envvariable) • [HttpHeader](https://agentclientprotocol.com/protocol/schema#httpheader)

Sessions represent a specific conversation or thread between the Client and Agent. Each session maintains its own context, conversation history, and state, allowing multiple independent interactions with the same Agent.

Before creating a session, Clients **MUST** first complete the initialization phase to establish protocol compatibility and capabilities.

### Creating a Session

Clients create a new session by calling the `session/new` method with:
- The working directory for the session
- A list of MCP servers the Agent should connect to

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/new",
  "params": {
    "cwd": "/home/user/project",
    "mcpServers": [
      {
        "name": "filesystem",
        "command": "/path/to/mcp-server",
        "args": ["--stdio"],
        "env": []
      }
    ]
  }
}
```

The Agent **MUST** respond with a unique Session ID that identifies this conversation:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "sessionId": "sess_abc123def456"
  }
}
```

### Loading Sessions

Agents that support the `loadSession` capability allow Clients to resume previous conversations. This feature enables persistence across restarts and sharing sessions between different Client instances.

#### Checking Support

Before attempting to load a session, Clients **MUST** verify that the Agent supports this capability by checking the `loadSession` field in the `initialize` response.

If `loadSession` is `false` or not present, the Agent does not support loading sessions and Clients **MUST NOT** attempt to call `session/load`.

#### Loading a Session

To load an existing session, Clients **MUST** call the `session/load` method with:
- The Session ID to resume
- MCP servers to connect to
- The working directory

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/load",
  "params": {
    "sessionId": "sess_789xyz",
    "cwd": "/home/user/project",
    "mcpServers": [
      {
        "name": "filesystem",
        "command": "/path/to/mcp-server",
        "args": ["--mode", "filesystem"],
        "env": []
      }
    ]
  }
}
```

The Agent **MUST** replay the entire conversation to the Client in the form of `session/update` notifications.

When **all** the conversation entries have been streamed to the Client, the Agent **MUST** respond to the original `session/load` request.

### Session ID

The session ID returned by `session/new` is a unique identifier for the conversation context.

Clients use this ID to:
- Send prompt requests via `session/prompt`
- Cancel ongoing operations via `session/cancel`
- Load previous sessions via `session/load` (if the Agent supports the `loadSession` capability)

### Working Directory

The `cwd` (current working directory) parameter establishes the file system context for the session. This directory:
- **MUST** be an absolute path
- **MUST** be used for the session regardless of where the Agent subprocess was spawned
- **SHOULD** serve as a boundary for tool operations on the file system

### MCP Servers

The Model Context Protocol (MCP) allows Agents to access external tools and data sources. When creating a session, Clients **MAY** include connection details for MCP servers that the Agent should connect to.

MCP servers can be connected to using different transports. All Agents **MUST** support the stdio transport, while HTTP and SSE transports are optional capabilities that can be checked during initialization.

#### Transport Types

**Stdio Transport**
All Agents **MUST** support connecting to MCP servers via stdio (standard input/output). This is the default transport mechanism.

Parameters:
- `name` (string, required): A human-readable identifier for the server
- `command` (string, required): The absolute path to the MCP server executable
- `args` (array, required): Command-line arguments to pass to the server
- `env` (EnvVariable[]): Environment variables to set when launching the server

**HTTP Transport**
When the Agent supports `mcpCapabilities.http`, Clients can specify MCP servers configurations using the HTTP transport.

Parameters:
- `type` (string, required): Must be `"http"` to indicate HTTP transport
- `name` (string, required): A human-readable identifier for the server
- `url` (string, required): The URL of the MCP server
- `headers` (HttpHeader[], required): HTTP headers to include in requests to the server

**SSE Transport** *(Deprecated)*
When the Agent supports `mcpCapabilities.sse`, Clients can specify MCP servers configurations using the SSE transport.

**⚠️ Warning: This transport has been deprecated by the MCP specification and should not be used for new implementations.**

Parameters:
- `type` (string, required): Must be `"sse"` to indicate SSE transport
- `name` (string, required): A human-readable identifier for the server
- `url` (string, required): The URL of the SSE endpoint
- `headers` (HttpHeader[], required): HTTP headers to include when establishing the SSE connection

## Prompt Turn

Docs: [Prompt Turn](https://agentclientprotocol.com/protocol/prompt-turn) • [Content](https://agentclientprotocol.com/protocol/content) • GitHub: [docs/protocol/prompt-turn.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/prompt-turn.mdx), [docs/protocol/content.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/content.mdx) • Schema: [PromptRequest](https://agentclientprotocol.com/protocol/schema#promptrequest) • [PromptResponse](https://agentclientprotocol.com/protocol/schema#promptresponse) • [StopReason](https://agentclientprotocol.com/protocol/schema#stopreason) • [SessionNotification](https://agentclientprotocol.com/protocol/schema#sessionnotification) • [SessionUpdate](https://agentclientprotocol.com/protocol/schema#sessionupdate) • [ContentBlock](https://agentclientprotocol.com/protocol/schema#contentblock)

A prompt turn represents a complete interaction cycle between the Client and Agent, starting with a user message and continuing until the Agent completes its response. This may involve multiple exchanges with the language model and tool invocations.

Before sending prompts, Clients **MUST** first complete the initialization phase and session setup.

### The Prompt Turn Lifecycle

A prompt turn follows a structured flow that enables rich interactions between the user, Agent, and any connected tools.

#### 1. User Message

The turn begins when the Client sends a `session/prompt`:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_abc123def456",
    "prompt": [
      {
        "type": "text",
        "text": "Can you analyze this code for potential issues?"
      },
      {
        "type": "resource",
        "resource": {
          "uri": "file:///home/user/project/main.py",
          "mimeType": "text/x-python",
          "text": "def process_data(items):\n    for item in items:\n        print(item)"
        }
      }
    ]
  }
}
```

Parameters:
- `sessionId` (SessionId): The ID of the session to send this message to.
- `prompt` (ContentBlock[]): The contents of the user message, e.g. text, images, files, etc.

Clients **MUST** restrict types of content according to the Prompt Capabilities established during initialization.

#### 2. Agent Processing

Upon receiving the prompt request, the Agent processes the user's message and sends it to the language model, which **MAY** respond with text content, tool calls, or both.

#### 3. Agent Reports Output

The Agent reports the model's output to the Client via `session/update` notifications. This may include the Agent's plan for accomplishing the task:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "plan",
      "entries": [
        {
          "content": "Check for syntax errors",
          "priority": "high",
          "status": "pending"
        },
        {
          "content": "Identify potential type issues",
          "priority": "medium",
          "status": "pending"
        }
      ]
    }
  }
}
```

The Agent then reports text responses from the model:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "agent_message_chunk",
      "content": {
        "type": "text",
        "text": "I'll analyze your code for potential issues. Let me examine it..."
      }
    }
  }
}
```

If the model requested tool calls, these are also reported immediately:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call",
      "toolCallId": "call_001",
      "title": "Analyzing Python code",
      "kind": "other",
      "status": "pending"
    }
  }
}
```

#### 4. Check for Completion

If there are no pending tool calls, the turn ends and the Agent **MUST** respond to the original `session/prompt` request with a `StopReason`:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "stopReason": "end_turn"
  }
}
```

#### 5. Tool Invocation and Status Reporting

Before proceeding with execution, the Agent **MAY** request permission from the Client via the `session/request_permission` method.

Once permission is granted (if required), the Agent **SHOULD** invoke the tool and report a status update marking the tool as `in_progress`:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call_update",
      "toolCallId": "call_001",
      "status": "in_progress"
    }
  }
}
```

When the tool completes, the Agent sends another update with the final status and any content:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call_update",
      "toolCallId": "call_001",
      "status": "completed",
      "content": [
        {
          "type": "content",
          "content": {
            "type": "text",
            "text": "Analysis complete:\n- No syntax errors found\n- Consider adding type hints for better clarity"
          }
        }
      ]
    }
  }
}
```

#### 6. Continue Conversation

The Agent sends the tool results back to the language model as another request.

The cycle returns to step 2, continuing until the language model completes its response without requesting additional tool calls or the turn gets stopped by the Agent or cancelled by the Client.

### Stop Reasons

When an Agent stops a turn, it must specify the corresponding `StopReason`:

- `end_turn`: The language model finishes responding without requesting more tools
- `max_tokens`: The maximum token limit is reached
- `max_turn_requests`: The maximum number of model requests in a single turn is exceeded
- `refusal`: The Agent refuses to continue
- `cancelled`: The Client cancels the turn

### Cancellation

Clients **MAY** cancel an ongoing prompt turn at any time by sending a `session/cancel` notification:

```json
{
  "jsonrpc": "2.0",
  "method": "session/cancel",
  "params": {
    "sessionId": "sess_abc123def456"
  }
}
```

The Client **SHOULD** preemptively mark all non-finished tool calls pertaining to the current turn as `cancelled` as soon as it sends the `session/cancel` notification.

When the Agent receives this notification, it **SHOULD** stop all language model requests and all tool call invocations as soon as possible.

After all ongoing operations have been successfully aborted and pending updates have been sent, the Agent **MUST** respond to the original `session/prompt` request with the `cancelled` stop reason.

### Session Updates

Agents stream progress via `session/update` notifications. The `params` shape is:
- `sessionId` (SessionId, required)
- `update` (SessionUpdate, required): One of the variants below

Variants:
- `user_message_chunk`: A chunk of the user's message
  - `content` (ContentBlock, required)
- `agent_message_chunk`: A chunk of the agent's message
  - `content` (ContentBlock, required)
- `agent_thought_chunk`: A chunk of the agent's internal reasoning
  - `content` (ContentBlock, required)
- `tool_call`: New tool call started
  - Fields: `toolCallId` (required), `title` (required), `kind` (ToolKind), `status` (ToolCallStatus), `content` (ToolCallContent[]), `locations` (ToolCallLocation[]), `rawInput` (object), `rawOutput` (object)
- `tool_call_update`: Updates an existing tool call
  - Fields (all optional except `toolCallId`): `toolCallId` (required), `status`, `title`, `kind`, `content` (replace), `locations` (replace), `rawInput`, `rawOutput`
- `plan`: Current execution plan
  - `entries` (PlanEntry[], required). Client replaces the whole plan on each update.
- `available_commands_update`: Current commands available
  - `availableCommands` (AvailableCommand[], required)
- `current_mode_update`: Current session mode changed
  - `currentModeId` (SessionModeId, required)

## Content

Content blocks represent displayable information that flows through the Agent Client Protocol. They provide a structured way to handle various types of user-facing content—whether it's text from language models, images for analysis, or embedded resources for context.

Content blocks appear in:
- User prompts sent via `session/prompt`
- Language model output streamed through `session/update` notifications
- Progress updates and results from tool calls

The Agent Client Protocol uses the same `ContentBlock` structure as the Model Context Protocol (MCP). This design choice enables Agents to seamlessly forward content from MCP tool outputs without transformation.

### Content Types

Docs: [Content](https://agentclientprotocol.com/protocol/content) • GitHub: [docs/protocol/content.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/content.mdx) • Schema: [schema.json](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/schema/schema.json)

#### Text Content

Plain text messages form the foundation of most interactions.

```json
{
  "type": "text",
  "text": "What's the weather like today?"
}
```

All Agents **MUST** support text content blocks when included in prompts.

Parameters:
- `text` (string, required): The text content to display
- `annotations` (Annotations): Optional metadata about how the content should be used or displayed.

#### Image Content

Images can be included for visual context or analysis.

```json
{
  "type": "image",
  "mimeType": "image/png",
  "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB..."
}
```

*Requires the `image` prompt capability when included in prompts.*

Parameters:
- `data` (string, required): Base64-encoded image data
- `mimeType` (string, required): The MIME type of the image (e.g., "image/png", "image/jpeg")
- `uri` (string): Optional URI reference for the image source
- `annotations` (Annotations): Optional metadata about how the content should be used or displayed.

#### Audio Content

Audio data for transcription or analysis.

```json
{
  "type": "audio",
  "mimeType": "audio/wav",
  "data": "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAAB..."
}
```

*Requires the `audio` prompt capability when included in prompts.*

Parameters:
- `data` (string, required): Base64-encoded audio data
- `mimeType` (string, required): The MIME type of the audio (e.g., "audio/wav", "audio/mp3")
- `annotations` (Annotations): Optional metadata about how the content should be used or displayed.

#### Embedded Resource

Complete resource contents embedded directly in the message.

```json
{
  "type": "resource",
  "resource": {
    "uri": "file:///home/user/script.py",
    "mimeType": "text/x-python",
    "text": "def hello():\n    print('Hello, world!')"
  }
}
```

This is the preferred way to include context in prompts, such as when using @-mentions to reference files or other resources.

*Requires the `embeddedContext` prompt capability when included in prompts.*

Parameters:
- `resource` (EmbeddedResourceResource, required): The embedded resource contents, which can be either:
  - Text Resource: `uri`, `text`, `mimeType` (optional)
  - Blob Resource: `uri`, `blob` (base64-encoded binary data), `mimeType` (optional)
- `annotations` (Annotations): Optional metadata about how the content should be used or displayed.

#### Resource Link

References to resources that the Agent can access.

```json
{
  "type": "resource_link",
  "uri": "file:///home/user/document.pdf",
  "name": "document.pdf",
  "mimeType": "application/pdf",
  "size": 1024000
}
```

Parameters:
- `uri` (string, required): The URI of the resource
- `name` (string, required): A human-readable name for the resource
- `mimeType` (string): The MIME type of the resource
- `title` (string): Optional display title for the resource
- `description` (string): Optional description of the resource contents
- `size` (integer): Optional size of the resource in bytes
- `annotations` (Annotations): Optional metadata about how the content should be used or displayed.

## File System

Docs: [File System](https://agentclientprotocol.com/protocol/file-system) • GitHub: [docs/protocol/file-system.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/file-system.mdx) • Schema: [ReadTextFileRequest](https://agentclientprotocol.com/protocol/schema#readtextfilerequest) • [ReadTextFileResponse](https://agentclientprotocol.com/protocol/schema#readtextfileresponse) • [WriteTextFileRequest](https://agentclientprotocol.com/protocol/schema#writetextfilerequest) • [WriteTextFileResponse](https://agentclientprotocol.com/protocol/schema#writetextfileresponse)

The filesystem methods allow Agents to read and write text files within the Client's environment. These methods enable Agents to access unsaved editor state and allow Clients to track file modifications made during agent execution.

### Checking Support

Before attempting to use filesystem methods, Agents **MUST** verify that the Client supports these capabilities by checking the Client Capabilities field in the `initialize` response.

If `readTextFile` or `writeTextFile` is `false` or not present, the Agent **MUST NOT** attempt to call the corresponding filesystem method.

### Reading Files

The `fs/read_text_file` method allows Agents to read text file contents from the Client's filesystem, including unsaved changes in the editor.

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "fs/read_text_file",
  "params": {
    "sessionId": "sess_abc123def456",
    "path": "/home/user/project/src/main.py",
    "line": 10,
    "limit": 50
  }
}
```

Parameters:
- `sessionId` (SessionId, required): The Session ID for this request
- `path` (string, required): Absolute path to the file to read
- `line` (number): Optional line number to start reading from (1-based)
- `limit` (number): Optional maximum number of lines to read

The Client responds with the file contents:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": "def hello_world():\n    print('Hello, world!')\n"
  }
}
```

### Writing Files

The `fs/write_text_file` method allows Agents to write or update text files in the Client's filesystem.

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "fs/write_text_file",
  "params": {
    "sessionId": "sess_abc123def456",
    "path": "/home/user/project/config.json",
    "content": "{\n  \"debug\": true,\n  \"version\": \"1.0.0\"\n}"
  }
}
```

Parameters:
- `sessionId` (SessionId, required): The Session ID for this request
- `path` (string, required): Absolute path to the file to write. The Client **MUST** create the file if it doesn't exist.
- `content` (string, required): The text content to write to the file

The Client responds with an empty result on success:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": null
}
```

## Tool Calls

Docs: [Tool Calls](https://agentclientprotocol.com/protocol/tool-calls) • GitHub: [docs/protocol/tool-calls.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/tool-calls.mdx) • Schema: [ToolCall](https://agentclientprotocol.com/protocol/schema#toolcall) • [ToolCallUpdate](https://agentclientprotocol.com/protocol/schema#toolcallupdate) • [ToolCallContent](https://agentclientprotocol.com/protocol/schema#toolcallcontent) • [ToolCallLocation](https://agentclientprotocol.com/protocol/schema#toolcalllocation) • [RequestPermissionRequest](https://agentclientprotocol.com/protocol/schema#requestpermissionrequest) • [RequestPermissionResponse](https://agentclientprotocol.com/protocol/schema#requestpermissionresponse) • [RequestPermissionOutcome](https://agentclientprotocol.com/protocol/schema#requestpermissionoutcome) • [PermissionOption](https://agentclientprotocol.com/protocol/schema#permissionoption) • [ToolCallStatus](https://agentclientprotocol.com/protocol/schema#toolcallstatus) • [ToolKind](https://agentclientprotocol.com/protocol/schema#toolkind)

Tool calls represent actions that language models request Agents to perform during a prompt turn. When an LLM determines it needs to interact with external systems—like reading files, running code, or fetching data—it generates tool calls that the Agent executes on its behalf.

Agents report tool calls through `session/update` notifications, allowing Clients to display real-time progress and results to users.

### Creating

When the language model requests a tool invocation, the Agent **SHOULD** report it to the Client:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call",
      "toolCallId": "call_001",
      "title": "Reading configuration file",
      "kind": "read",
      "status": "pending"
    }
  }
}
```

Parameters:
- `toolCallId` (ToolCallId, required): A unique identifier for this tool call within the session
- `title` (string, required): A human-readable title describing what the tool is doing
- `kind` (ToolKind): The category of tool being invoked.
  - `read` - Reading files or data
  - `edit` - Modifying files or content
  - `delete` - Removing files or data
  - `move` - Moving or renaming files
  - `search` - Searching for information
  - `execute` - Running commands or code
  - `think` - Internal reasoning or planning
  - `fetch` - Retrieving external data
  - `switch_mode` - Switching the current session mode
  - `other` - Other tool types (default)
- `status` (ToolCallStatus): The current execution status (defaults to `pending`)
- `content` (ToolCallContent[]): Content produced by the tool call
- `locations` (ToolCallLocation[]): File locations affected by this tool call
- `rawInput` (object): The raw input parameters sent to the tool
- `rawOutput` (object): The raw output returned by the tool

### Updating

As tools execute, Agents send updates to report progress and results.

Updates use the `session/update` notification with `tool_call_update`:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call_update",
      "toolCallId": "call_001",
      "status": "in_progress",
      "content": [
        {
          "type": "content",
          "content": {
            "type": "text",
            "text": "Found 3 configuration files..."
          }
        }
      ]
    }
  }
}
```

All fields except `toolCallId` are optional in updates. Only the fields being changed need to be included.

### Requesting Permission

The Agent **MAY** request permission from the user before executing a tool call by calling the `session/request_permission` method:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "session/request_permission",
  "params": {
    "sessionId": "sess_abc123def456",
    "toolCall": {
      "toolCallId": "call_001"
    },
    "options": [
      {
        "optionId": "allow-once",
        "name": "Allow once",
        "kind": "allow_once"
      },
      {
        "optionId": "reject-once",
        "name": "Reject",
        "kind": "reject_once"
      }
    ]
  }
}
```

Parameters:
- `sessionId` (SessionId, required): The session ID for this request
- `toolCall` (ToolCallUpdate, required): The tool call update containing details about the operation
- `options` (PermissionOption[], required): Available permission options for the user to choose from

The Client responds with the user's decision:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "outcome": {
      "outcome": "selected",
      "optionId": "allow-once"
    }
  }
}
```

#### Permission Options

Each permission option provided to the Client contains:
- `optionId` (string, required): Unique identifier for this option
- `name` (string, required): Human-readable label to display to the user
- `kind` (PermissionOptionKind, required): A hint to help Clients choose appropriate icons and UI treatment for each option.
  - `allow_once` - Allow this operation only this time
  - `allow_always` - Allow this operation and remember the choice
  - `reject_once` - Reject this operation only this time
  - `reject_always` - Reject this operation and remember the choice

### Status

Tool calls progress through different statuses during their lifecycle:
- `pending`: The tool call hasn't started running yet because the input is either streaming or awaiting approval
- `in_progress`: The tool call is currently running
- `completed`: The tool call completed successfully
- `failed`: The tool call failed with an error

### Content

Tool calls can produce different types of content:

#### Regular Content

Standard content blocks like text, images, or resources:

```json
{
  "type": "content",
  "content": {
    "type": "text",
    "text": "Analysis complete. Found 3 issues."
  }
}
```

#### Diffs

File modifications shown as diffs:

```json
{
  "type": "diff",
  "path": "/home/user/project/src/config.json",
  "oldText": "{\n  \"debug\": false\n}",
  "newText": "{\n  \"debug\": true\n}"
}
```

Parameters:
- `path` (string, required): The absolute file path being modified
- `oldText` (string): The original content (null for new files)
- `newText` (string, required): The new content after modification

#### Terminals

Live terminal output from command execution:

```json
{
  "type": "terminal",
  "terminalId": "term_xyz789"
}
```

Parameters:
- `terminalId` (string, required): The ID of a terminal created with `terminal/create`

When a terminal is embedded in a tool call, the Client displays live output as it's generated and continues to display it even after the terminal is released.

### Following the Agent

Tool calls can report file locations they're working with, enabling Clients to implement "follow-along" features that track which files the Agent is accessing or modifying in real-time.

```json
{
  "path": "/home/user/project/src/main.py",
  "line": 42
}
```

Parameters:
- `path` (string, required): The absolute file path being accessed or modified
- `line` (number): Optional line number within the file

## Terminals

Docs: [Terminals](https://agentclientprotocol.com/protocol/terminals) • GitHub: [docs/protocol/terminals.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/terminals.mdx) • Schema: [CreateTerminalRequest](https://agentclientprotocol.com/protocol/schema#createterminalrequest) • [CreateTerminalResponse](https://agentclientprotocol.com/protocol/schema#createterminalresponse) • [TerminalOutputRequest](https://agentclientprotocol.com/protocol/schema#terminaloutputrequest) • [TerminalOutputResponse](https://agentclientprotocol.com/protocol/schema#terminaloutputresponse) • [WaitForTerminalExitRequest](https://agentclientprotocol.com/protocol/schema#waitforterminalexitrequest) • [WaitForTerminalExitResponse](https://agentclientprotocol.com/protocol/schema#waitforterminalexitresponse) • [KillTerminalCommandRequest](https://agentclientprotocol.com/protocol/schema#killterminalcommandrequest) • [KillTerminalCommandResponse](https://agentclientprotocol.com/protocol/schema#killterminalcommandresponse) • [ReleaseTerminalRequest](https://agentclientprotocol.com/protocol/schema#releaseterminalrequest) • [ReleaseTerminalResponse](https://agentclientprotocol.com/protocol/schema#releaseterminalresponse)

The terminal methods allow Agents to execute shell commands within the Client's environment. These methods enable Agents to run build processes, execute scripts, and interact with command-line tools while providing real-time output streaming and process control.

### Checking Support

Before attempting to use terminal methods, Agents **MUST** verify that the Client supports this capability by checking the Client Capabilities field in the `initialize` response.

If `terminal` is `false` or not present, the Agent **MUST NOT** attempt to call any terminal methods.

### Executing Commands

The `terminal/create` method starts a command in a new terminal:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "terminal/create",
  "params": {
    "sessionId": "sess_abc123def456",
    "command": "npm",
    "args": ["test", "--coverage"],
    "env": [
      {
        "name": "NODE_ENV",
        "value": "test"
      }
    ],
    "cwd": "/home/user/project",
    "outputByteLimit": 1048576
  }
}
```

Parameters:
- `sessionId` (SessionId, required): The Session ID for this request
- `command` (string, required): The command to execute
- `args` (string[]): Array of command arguments
- `env` (EnvVariable[]): Environment variables for the command. Each variable has: `name` (environment variable name), `value` (environment variable value)
- `cwd` (string): Working directory for the command (absolute path)
- `outputByteLimit` (number): Maximum number of output bytes to retain. Once exceeded, earlier output is truncated to stay within this limit.

The Client returns a Terminal ID immediately without waiting for completion:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "terminalId": "term_xyz789"
  }
}
```

This allows the command to run in the background while the Agent performs other operations.

*Note: The Agent **MUST** release the terminal using `terminal/release` when it's no longer needed.*

### Embedding in Tool Calls

Terminals can be embedded directly in tool calls to provide real-time output to users:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "tool_call",
      "toolCallId": "call_002",
      "title": "Running tests",
      "kind": "execute",
      "status": "in_progress",
      "content": [
        {
          "type": "terminal",
          "terminalId": "term_xyz789"
        }
      ]
    }
  }
}
```

When a terminal is embedded in a tool call, the Client displays live output as it's generated and continues to display it even after the terminal is released.

### Getting Output

The `terminal/output` method retrieves the current terminal output without waiting for the command to complete:

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "terminal/output",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

The Client responds with the current output and exit status (if the command has finished):

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "output": "Running tests...\n✓ All tests passed (42 total)\n",
    "truncated": false,
    "exitStatus": {
      "exitCode": 0,
      "signal": null
    }
  }
}
```

Response fields:
- `output` (string, required): The terminal output captured so far
- `truncated` (boolean, required): Whether the output was truncated due to byte limits
- `exitStatus` (TerminalExitStatus): Present only if the command has exited. Contains: `exitCode` (process exit code, may be null), `signal` (signal that terminated the process, may be null)

### Waiting for Exit

The `terminal/wait_for_exit` method returns once the command completes:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "terminal/wait_for_exit",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

The Client responds once the command exits:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "exitCode": 0,
    "signal": null
  }
}
```

Response fields:
- `exitCode` (number): The process exit code (may be null if terminated by signal)
- `signal` (string): The signal that terminated the process (may be null if exited normally)

### Killing Commands

The `terminal/kill` method terminates a command without releasing the terminal:

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "terminal/kill",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

After killing a command, the terminal remains valid and can be used with:
- `terminal/output` to get the final output
- `terminal/wait_for_exit` to get the exit status

The Agent **MUST** still call `terminal/release` when it's done using it.

#### Building a Timeout

Agents can implement command timeouts by combining terminal methods:

1. Create a terminal with `terminal/create`
2. Start a timer for the desired timeout duration
3. Concurrently wait for either the timer to expire or `terminal/wait_for_exit` to return
4. If the timer expires first:
   - Call `terminal/kill` to terminate the command
   - Call `terminal/output` to retrieve any final output
   - Include the output in the response to the model
5. Call `terminal/release` when done

### Releasing Terminals

The `terminal/release` kills the command if still running and releases all resources:

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "terminal/release",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

After release the terminal ID becomes invalid for all other `terminal/*` methods.

If the terminal was added to a tool call, the client **SHOULD** continue to display its output after release.

## Session Modes

Docs: [Session Modes](https://agentclientprotocol.com/protocol/session-modes) • GitHub: [docs/protocol/session-modes.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/session-modes.mdx) • Schema: [SetSessionModeRequest](https://agentclientprotocol.com/protocol/schema#setsessionmoderequest) • [SetSessionModeResponse](https://agentclientprotocol.com/protocol/schema#setsessionmoderesponse) • [SessionModeState](https://agentclientprotocol.com/protocol/schema#sessionmodestate) • [SessionMode](https://agentclientprotocol.com/protocol/schema#sessionmode) • [SessionUpdate (current_mode_update)](https://agentclientprotocol.com/protocol/schema#sessionupdate)

Agents can provide a set of modes they can operate in. Modes often affect the system prompts used, the availability of tools, and whether they request permission before running.

### Initial State

During Session Setup the Agent **MAY** return a list of modes it can operate in and the currently active mode:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "sessionId": "sess_abc123def456",
    "modes": {
      "currentModeId": "ask",
      "availableModes": [
        {
          "id": "ask",
          "name": "Ask",
          "description": "Request permission before making any changes"
        },
        {
          "id": "architect",
          "name": "Architect",
          "description": "Design and plan software systems without implementation"
        },
        {
          "id": "code",
          "name": "Code",
          "description": "Write and modify code with full tool access"
        }
      ]
    }
  }
}
```

#### SessionModeState

- `currentModeId` (SessionModeId, required): The ID of the mode that is currently active
- `availableModes` (SessionMode[], required): The set of modes that the Agent can operate in

#### SessionMode

- `id` (SessionModeId, required): Unique identifier for this mode
- `name` (string, required): Human-readable name of the mode
- `description` (string): Optional description providing more details about what this mode does

### Setting the Current Mode

The current mode can be changed at any point during a session, whether the Agent is idle or generating a response.

#### From the Client

Typically, Clients display the available modes to the user and allow them to change the current one, which they can do by calling the `session/set_mode` method.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "session/set_mode",
  "params": {
    "sessionId": "sess_abc123def456",
    "modeId": "code"
  }
}
```

On success, the Agent responds with an empty object (`result: {}`).

Parameters:
- `sessionId` (SessionId, required): The ID of the session to set the mode for
- `modeId` (SessionModeId, required): The ID of the mode to switch to. Must be one of the modes listed in `availableModes`

#### From the Agent

The Agent can also change its own mode and let the Client know by sending the `current_mode_update` session notification:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "current_mode_update",
      "currentModeId": "code"
    }
  }
}
```

#### Exiting Plan Modes

A common case where an Agent might switch modes is from within a special "exit mode" tool that can be provided to the language model during plan/architect modes. The language model can call this tool when it determines it's ready to start implementing a solution.

This "switch mode" tool will usually request permission before running, which it can do just like any other tool.

## Agent Plan

Docs: [Agent Plan](https://agentclientprotocol.com/protocol/agent-plan) • GitHub: [docs/protocol/agent-plan.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/agent-plan.mdx) • Schema: [Plan](https://agentclientprotocol.com/protocol/schema#plan) • [PlanEntry](https://agentclientprotocol.com/protocol/schema#planentry) • [PlanEntryPriority](https://agentclientprotocol.com/protocol/schema#planentrypriority) • [PlanEntryStatus](https://agentclientprotocol.com/protocol/schema#planentrystatus)

Plans are execution strategies for complex tasks that require multiple steps.

Agents may share plans with Clients through `session/update` notifications, providing real-time visibility into their thinking and progress.

### Creating Plans

When the language model creates an execution plan, the Agent **SHOULD** report it to the Client:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "plan",
      "entries": [
        {
          "content": "Analyze the existing codebase structure",
          "priority": "high",
          "status": "pending"
        },
        {
          "content": "Identify components that need refactoring",
          "priority": "high",
          "status": "pending"
        },
        {
          "content": "Create unit tests for critical functions",
          "priority": "medium",
          "status": "pending"
        }
      ]
    }
  }
}
```

Parameters:
- `entries` (PlanEntry[], required): An array of plan entries representing the tasks to be accomplished

### Plan Entries

Each plan entry represents a specific task or goal within the overall execution strategy:

- `content` (string, required): A human-readable description of what this task aims to accomplish
- `priority` (PlanEntryPriority, required): The relative importance of this task.
  - `high`
  - `medium`
  - `low`
- `status` (PlanEntryStatus, required): The current execution status of this task
  - `pending`
  - `in_progress`
  - `completed`

### Updating Plans

As the Agent progresses through the plan, it **SHOULD** report updates by sending more `session/update` notifications with the same structure.

The Agent **MUST** send a complete list of all plan entries in each update and their current status. The Client **MUST** replace the current plan completely.

#### Dynamic Planning

Plans can evolve during execution. The Agent **MAY** add, remove, or modify plan entries as it discovers new requirements or completes tasks, allowing it to adapt based on what it learns.

## Slash Commands

Docs: [Slash Commands](https://agentclientprotocol.com/protocol/slash-commands) • GitHub: [docs/protocol/slash-commands.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/slash-commands.mdx) • Schema: [AvailableCommand](https://agentclientprotocol.com/protocol/schema#availablecommand) • [AvailableCommandInput](https://agentclientprotocol.com/protocol/schema#availablecommandinput)

Agents can advertise a set of slash commands that users can invoke. These commands provide quick access to specific agent capabilities and workflows. Commands are run as part of regular prompt requests where the Client includes the command text in the prompt.

### Advertising Commands

After creating a session, the Agent **MAY** send a list of available commands via the `available_commands_update` session notification:

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123def456",
    "update": {
      "sessionUpdate": "available_commands_update",
      "availableCommands": [
        {
          "name": "web",
          "description": "Search the web for information",
          "input": {
            "hint": "query to search for"
          }
        },
        {
          "name": "test",
          "description": "Run tests for the current project"
        },
        {
          "name": "plan",
          "description": "Create a detailed implementation plan",
          "input": {
            "hint": "description of what to plan"
          }
        }
      ]
    }
  }
}
```

Parameters:
- `availableCommands` (AvailableCommand[]): The list of commands available in this session

#### AvailableCommand

- `name` (string, required): The command name (e.g., "web", "test", "plan")
- `description` (string, required): Human-readable description of what the command does
- `input` (AvailableCommandInput): Optional input specification for the command

#### AvailableCommandInput

Currently supports unstructured text input:
- `hint` (string, required): A hint to display when the input hasn't been provided yet

### Dynamic Updates

The Agent can update the list of available commands at any time during a session by sending another `available_commands_update` notification. This allows commands to be added based on context, removed when no longer relevant, or modified with updated descriptions.

### Running Commands

Commands are included as regular user messages in prompt requests:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_abc123def456",
    "prompt": [
      {
        "type": "text",
        "text": "/web agent client protocol"
      }
    ]
  }
}
```

The Agent recognizes the command prefix and processes it accordingly. Commands may be accompanied by any other user message content types (images, audio, etc.) in the same prompt array.

## Extensibility

Docs: [Extensibility](https://agentclientprotocol.com/protocol/extensibility) • GitHub: [docs/protocol/extensibility.mdx](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/docs/protocol/extensibility.mdx) • Schema: [schema.json](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/schema/schema.json)

The Agent Client Protocol provides built-in extension mechanisms that allow implementations to add custom functionality while maintaining compatibility with the core protocol. These mechanisms ensure that Agents and Clients can innovate without breaking interoperability.

### The `_meta` Field

All types in the protocol include a `_meta` field that implementations can use to attach custom information. This includes requests, responses, notifications, and even nested types like content blocks, tool calls, plan entries, and capability objects.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_abc123def456",
    "prompt": [
      {
        "type": "text",
        "text": "Hello, world!"
      }
    ],
    "_meta": {
      "zed.dev/debugMode": true
    }
  }
}
```

Implementations **MUST NOT** add any custom fields at the root of a type that's part of the specification. All possible names are reserved for future protocol versions.

### Extension Methods

The protocol reserves any method name starting with an underscore (`_`) for custom extensions. This allows implementations to add new functionality without the risk of conflicting with future protocol versions.

Extension methods follow standard JSON-RPC 2.0 semantics:
- **Requests** - Include an `id` field and expect a response
- **Notifications** - Omit the `id` field and are one-way

#### Custom Requests

In addition to the requests specified by the protocol, implementations **MAY** expose and call custom JSON-RPC requests as long as their name starts with an underscore (`_`).

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "_zed.dev/workspace/buffers",
  "params": {
    "language": "rust"
  }
}
```

Upon receiving a custom request, implementations **MUST** respond accordingly with the provided `id`.

If the receiving end doesn't recognize the custom method name, it should respond with the standard "Method not found" error.

To avoid such cases, extensions **SHOULD** advertise their custom capabilities so that callers can check their availability first and adapt their behavior or interface accordingly.

#### Custom Notifications

Custom notifications are regular JSON-RPC notifications that start with an underscore (`_`). Like all notifications, they omit the `id` field:

```json
{
  "jsonrpc": "2.0",
  "method": "_zed.dev/file_opened",
  "params": {
    "path": "/home/user/project/src/editor.rs"
  }
}
```

Unlike with custom requests, implementations **SHOULD** ignore unrecognized notifications.

### Advertising Custom Capabilities

Implementations **SHOULD** use the `_meta` field in capability objects to advertise support for extensions and their methods:

```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "result": {
    "protocolVersion": 1,
    "agentCapabilities": {
      "loadSession": true,
      "_meta": {
        "zed.dev": {
          "workspace": true,
          "fileNotifications": true
        }
      }
    }
  }
}
```

This allows implementations to negotiate custom features during initialization without breaking compatibility with standard Clients and Agents.

## Transport

- Protocol transport is JSON-RPC 2.0 over stdio.
- Implementations MUST write only JSON-RPC frames to stdout; logs and diagnostics should go to stderr.
- Framing is implementation-defined. Common approaches:
  - Newline-delimited JSON objects (one JSON object per line)
  - LSP-style `Content-Length` headers followed by JSON body
- Choose one framing and keep both sides consistent.

### Wire Format Examples

NDJSON (newline-delimited JSON), UTF-8
```text
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true},"terminal":true}}}
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"audio":false,"embeddedContext":true}},"authMethods":[{"id":"api_key","name":"API Key"}]}}
```

LSP-style Content-Length framing, UTF-8
```text
Content-Length: <byte-count>\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true},"terminal":true}}}

Content-Length: <byte-count>\r\n
\r\n
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"audio":false,"embeddedContext":true}},"authMethods":[]}}
```

Notes
- Use UTF-8 everywhere. Ensure writers flush promptly to avoid head-of-line blocking.
- With NDJSON, write one complete JSON object per line and avoid printing logs to stdout.
- With Content-Length, the byte-count is the number of bytes in the UTF-8 JSON body, not characters.

## Supported Editors

- [Zed](https://zed.dev/docs/ai/external-agents)
- [neovim](https://neovim.io/) through the [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) plugin
- [yetone/avante.nvim](https://github.com/yetone/avante.nvim): A Neovim plugin designed to emulate the behaviour of the Cursor AI IDE.

## Supported Agents

- [Gemini](https://github.com/google-gemini/gemini-cli)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
  - [via Zed's SDK adapter](https://github.com/zed-industries/claude-code-acp)
  - [via Xuanwo's SDK adapter](https://github.com/Xuanwo/acp-claude-code)

## Libraries and Schema

- **Rust**: [`agent-client-protocol`](https://crates.io/crates/agent-client-protocol)
  - Docs: [Rust Library](https://agentclientprotocol.com/libraries/rust)
  - GitHub: [rust/](https://github.com/zed-industries/agent-client-protocol/tree/HEAD/rust)
- **TypeScript**: [`@zed-industries/agent-client-protocol`](https://www.npmjs.com/package/@zed-industries/agent-client-protocol)
  - Docs: [TypeScript Library](https://agentclientprotocol.com/libraries/typescript)
  - GitHub: [typescript/](https://github.com/zed-industries/agent-client-protocol/tree/HEAD/typescript)
- **JSON Schema**: [schema.json](./schema/schema.json) • Docs: [Schema](https://agentclientprotocol.com/protocol/schema) • GitHub: [schema/schema.json](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/schema/schema.json)
  - TypeScript bindings (GitHub): [typescript/schema.ts](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/typescript/schema.ts)
  - TypeScript protocol types (GitHub): [typescript/acp.ts](https://github.com/zed-industries/agent-client-protocol/blob/HEAD/typescript/acp.ts)

## Type Reference

This appendix summarizes core types to implement the protocol. See the JSON Schema for complete details and validation constraints.

### Identifiers

- `SessionId` (string): Unique session identifier
- `ToolCallId` (string): Unique ID for a tool call within a session
- `TerminalId` (string): Terminal instance identifier
- `AuthMethodId` (string): Authentication method identifier
- `PermissionOptionId` (string): Permission option identifier
- `SessionModeId` (string): Session mode identifier

### Stop Reasons

- `end_turn`: The language model finishes responding without requesting more tools. Schema: [StopReason](https://agentclientprotocol.com/protocol/schema#stopreason)
- `max_tokens`: The maximum token limit is reached
- `max_turn_requests`: The maximum number of model requests in a single turn is exceeded
- `refusal`: The Agent refuses to continue
- `cancelled`: The Client cancels the turn via `session/cancel`

### Capabilities

- `ClientCapabilities`
  - `fs.readTextFile` (bool, default false)
  - `fs.writeTextFile` (bool, default false)
  - `terminal` (bool, default false)
- `AgentCapabilities`
  - `loadSession` (bool, default false)
  - `promptCapabilities` (object)
    - `image` (bool, default false)
    - `audio` (bool, default false)
    - `embeddedContext` (bool, default false)
  - `mcpCapabilities` (object)
    - `http` (bool, default false)
    - `sse` (bool, default false)

### MCP Servers

- Stdio: `{ name, command, args[], env[] }`
- HTTP: `{ type: "http", name, url, headers[] }`
- SSE: `{ type: "sse", name, url, headers[] }` (deprecated by MCP spec)
- `EnvVariable`: `{ name, value }`
- `HttpHeader`: `{ name, value }`

### Content Blocks

- `text`: `{ type: "text", text, annotations? }`
- `image`: `{ type: "image", mimeType, data, uri?, annotations? }`
- `audio`: `{ type: "audio", mimeType, data, annotations? }`
- `resource_link`: `{ type: "resource_link", uri, name, mimeType?, title?, description?, size?, annotations? }`
- `resource`: `{ type: "resource", resource: EmbeddedResourceResource, annotations? }`
  - `TextResourceContents`: `{ uri, text, mimeType? }`
  - `BlobResourceContents`: `{ uri, blob, mimeType? }`

### Authentication

- `AuthMethod`: `{ id, name, description? }`

### Tool Calls

- `ToolKind`: `read | edit | delete | move | search | execute | think | fetch | switch_mode | other`
- `ToolCallStatus`: `pending | in_progress | completed | failed`
- `ToolCall` fields: `toolCallId`, `title`, `kind?`, `status?`, `content?[]`, `locations?[]`, `rawInput?`, `rawOutput?`
- `ToolCallUpdate` updates: `toolCallId` required; other fields optional as replacements/updates
- `ToolCallContent` variants:
  - `content`: `{ type: "content", content: ContentBlock }`
  - `diff`: `{ type: "diff", path, oldText?, newText }`
  - `terminal`: `{ type: "terminal", terminalId }`
- `ToolCallLocation`: `{ path, line? }`

### Plans

- `PlanEntry`: `{ content, priority: PlanEntryPriority, status: PlanEntryStatus }`
- `PlanEntryPriority`: `high | medium | low`
- `PlanEntryStatus`: `pending | in_progress | completed`

### Permissions

- `PermissionOption`: `{ optionId, name, kind }`
- `PermissionOptionKind`: `allow_once | allow_always | reject_once | reject_always`
- `RequestPermissionOutcome`:
  - `cancelled`: `{ outcome: "cancelled" }`
  - `selected`: `{ outcome: "selected", optionId }`

### Terminals

- `terminal/create` request: `{ sessionId, command, args?[], env?[], cwd?, outputByteLimit? }`
- `terminal/output` response: `{ output, truncated, exitStatus?{ exitCode?, signal? } }`
- `terminal/wait_for_exit` response: `{ exitCode?, signal? }`

### Validation Tips

- Use the official JSON Schema (`schema/schema.json`) to validate requests, responses, and notifications.
- Recommended libraries:
  - TypeScript: `ajv@^8` (strict mode), `@types` for generated types
  - Rust: `schemars` (for generation) + `jsonschema` crate or custom validation
  - Python: `jsonschema`
- Enforce no custom fields at the root of spec-defined types; use `_meta` for extensions.
- Validate numeric bounds (e.g., `ProtocolVersion` is `uint16`).
- Treat omitted capabilities as unsupported; do not assume defaults beyond the schema.
- In development, enable strict mode and fail fast; in production, prefer logging and graceful degradation for unrecognized `SessionUpdate` variants or extension data.

## Reference Flows

### Client Happy Path

Pseudo-code for a minimal, compliant client (editor/host):

```text
spawn_agent_subprocess()
open stdio as (agent_stdin, agent_stdout)

// Initialize
send { jsonrpc: "2.0", id: 1, method: "initialize", params: {
  protocolVersion: 1,
  clientCapabilities: { fs: { readTextFile: true, writeTextFile: true }, terminal: true }
}}
resp = recv(id: 1)
assert resp.result.protocolVersion == 1
authMethods = resp.result.authMethods

// Optionally authenticate if needed
try_new = send { id: 2, method: "session/new", params: { cwd: ABS_PATH, mcpServers: [] } }
if error == auth_required and authMethods not empty:
  choose methodId from authMethods
  send { id: 3, method: "authenticate", params: { methodId } }
  recv(id: 3)
  send { id: 4, method: "session/new", params: { cwd: ABS_PATH, mcpServers: [] } }
resp_new = recv(id: 2|4)
sessionId = resp_new.result.sessionId

// Prompt turn
send { id: 5, method: "session/prompt", params: { sessionId, prompt: [ { type: "text", text: "Hello" } ] } }

// Stream updates
loop recv notifications:
  if method == "session/update":
    switch update.sessionUpdate:
      case "agent_message_chunk": render content
      case "plan": render entries
      case "tool_call": show pending; maybe ask permission
      case "tool_call_update": update status/content/locations
      case "available_commands_update": update UI palette
      case "current_mode_update": reflect mode change
  else if response to id:5 arrives:
    assert result.stopReason in { end_turn, max_tokens, max_turn_requests, refusal, cancelled }
    break

// (Optional) file system and terminal requests received from agent
on request fs/read_text_file | fs/write_text_file | terminal/*: handle per capability

// Cancellation (user initiated)
on user_cancel: send { method: "session/cancel", params: { sessionId } }
```

### Agent Happy Path

Pseudo-code for a minimal, compliant agent:

```text
loop read JSON-RPC frames:
  switch method:
    case "initialize":
      reply { result: { protocolVersion: 1, agentCapabilities: { promptCapabilities: { image: false, audio: false, embeddedContext: true } }, authMethods: [] } }

    case "authenticate":
      // Validate provided methodId; configure credentials
      reply { result: {} }

    case "session/new":
      validate cwd absolute; store session; connect MCP if provided
      reply { result: { sessionId } }

    case "session/prompt":
      // Start a prompt turn
      // 1) (optional) share plan
      notify session/update { plan: { entries: [...] } }
      // 2) stream model output
      notify session/update { agent_message_chunk: { content: { type: "text", text: "Working..." } } }
      // 3) (optional) tools
      notify session/update { tool_call: { toolCallId, title, kind, status: "pending" } }
      //    (optional) ask for permission via session/request_permission
      //    execute tool; stream updates
      notify session/update { tool_call_update: { toolCallId, status: "in_progress" } }
      notify session/update { tool_call_update: { toolCallId, status: "completed", content: [...] } }
      // 4) end turn
      reply { result: { stopReason: "end_turn" } }

    case "session/cancel":
      abort outstanding LLM/tool work; flush pending updates
      // ensure prompt() returns { stopReason: "cancelled" }

    case terminal/* or fs/* (client-side methods):
      // Not applicable here; agent calls these on the client, not vice versa
```

## Compliance

### Agent Checklist

- Implement: `initialize`, `session/new`, `session/prompt`, `session/cancel`
- Stream updates via `session/update` using the variants defined above
- Respect `ClientCapabilities` and only call supported Client methods
- Support `ContentBlock::Text` and `ContentBlock::ResourceLink` in prompts
- Enforce absolute paths and 1-based line numbers
- Return `StopReason` on `session/prompt` and `cancelled` after `session/cancel`
- Advertise `authMethods` if authentication is required; accept `authenticate`
- Optional: `session/load`, modes (`session/set_mode` + mode updates), terminals, slash commands

### Client Checklist

- Implement: `session/request_permission`
- Optional: `fs/read_text_file`, `fs/write_text_file`, `terminal/*`
- Spawn agent subprocess and connect via JSON-RPC over stdio
- Provide absolute `cwd` for sessions and treat it as an execution boundary
- Display session updates (messages, plans, tool calls, terminals)
- Handle permission requests and cancellation reliably
- Never write non-JSON to stdout; use stderr for logs

---

*This specification is based on the official Agent Client Protocol documentation from https://agentclientprotocol.com and represents the complete protocol as of the documentation snapshot.*
