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
dart example/agcli.dart -j "Summarize README.md"
```

JSONL (specific agent):
```bash
dart example/agcli.dart -a my-agent -j "Summarize README.md"
```

Reading prompt from stdin:
```bash
# Pipe a prompt (plain text mode)
echo "Refactor the following code…" | dart example/agcli.dart

# Pipe a file as the prompt
cat PROMPT.md | dart example/agcli.dart

# Pipe with JSONL output
echo "List available commands" | dart example/agcli.dart -j
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
