import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';

import 'args.dart';
import 'list_operations.dart';
import 'output_formatter.dart';
import 'settings.dart';

Future<void> main(List<String> argv) async {
  final CliArgs args;
  try {
    args = CliArgs.parse(argv);
  } on FormatException catch (e) {
    // ArgParser throws FormatException for unknown args
    stderr.writeln('Error: $e');
    stderr.writeln();
    stdout.writeln(CliArgs.getUsage());
    exitCode = 2;
    return;
  }
  if (args.help) {
    stdout.writeln(CliArgs.getUsage());
    return;
  }

  // Load settings.json next to this CLI (script directory)
  final settings = (args.settingsPath != null && args.settingsPath!.isNotEmpty)
      ? await Settings.loadFromFile(args.settingsPath!)
      : await Settings.loadFromScriptDir();

  // Select agent
  final agentName = args.agentName ?? settings.agentServers.keys.first;
  final agent = settings.agentServers[agentName];
  if (agent == null) {
    stderr.writeln('Error: agent "$agentName" not found in settings.json');
    exitCode = 2;
    return;
  }

  // Emit client-side JSONL metadata about the selected agent (stdout only).
  if (args.output.isJsonLike) {
    final meta = {
      'jsonrpc': '2.0',
      'method': 'client/selected_agent',
      'params': {'name': agentName, 'command': agent.command},
    };
    stdout.writeln(jsonEncode(meta));
  }

  // Build client
  final mcpServers = settings.mcpServers
      .map(
        (s) => {
          'name': s.name,
          'command': s.command,
          'args': s.args,
          if (s.env.isNotEmpty)
            'env': s.env.entries
                .map((e) => {'name': e.key, 'value': e.value})
                .toList(),
        },
      )
      .toList();

  final config = AcpConfig(
    agentCommand: agent.command,
    agentArgs: agent.args,
    envOverrides: agent.env,
    capabilities: AcpCapabilities(
      fs: FsCapabilities(
        readTextFile: true,
        writeTextFile: args.write || args.yolo,
      ),
    ),
    mcpServers: mcpServers,
    allowReadOutsideWorkspace: args.yolo,
    // Enable filesystem provider to support file operations
    fsProvider: const _DummyFsProvider(),
    permissionProvider: DefaultPermissionProvider(
      onRequest: (opts) async {
        // Non-interactive: decide based on CLI flags
        // --yolo or --write enables write operations
        final allowWrites = args.write || args.yolo;

        // Check if this is a write operation
        final isWriteOp =
            opts.toolKind?.toLowerCase().contains('write') ?? false;

        // Auto-decide based on flags
        final decision = (!isWriteOp || allowWrites)
            ? PermissionOutcome.allow
            : PermissionOutcome.deny;

        // Log the decision in text mode (not in JSONL mode)
        if (!args.output.isJsonLike) {
          final action = decision == PermissionOutcome.allow ? 'allow' : 'deny';
          stdout.writeln(
            '[permission] auto-$action ${opts.toolName}'
            '${opts.toolKind != null ? ' (${opts.toolKind})' : ''}',
          );
          if (decision == PermissionOutcome.deny && isWriteOp) {
            stdout.writeln(
              '[permission] Use --write or --yolo to enable writes',
            );
          }
        }

        return decision;
      },
    ),
    onProtocolOut: args.output.isJsonLike
        ? (line) => stdout.writeln(line)
        : null,
    onProtocolIn: args.output.isJsonLike
        ? (line) => stdout.writeln(line)
        : null,
    terminalProvider: DefaultTerminalProvider(),
  );

  final client = await AcpClient.start(config: config);

  // Prepare prompt and check if we're in list-only mode.
  final prompt = await _readPrompt(args);
  final hasListFlags = args.listCaps || args.listCommands || args.listModes;
  final isListOnlyMode =
      hasListFlags && (prompt == null || prompt.trim().isEmpty);

  if (!hasListFlags && (prompt == null || prompt.trim().isEmpty)) {
    stderr.writeln('Error: empty prompt');
    stderr.writeln('Tip: run with --help for usage.');
    exitCode = 2;
    return;
  }

  // Handle Ctrl-C: send best-effort cancel without awaiting, then exit.
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    final sid = _sessionId;
    if (sid != null) {
      // Fire-and-forget: send cancel, then exit
      unawaited(
        client.cancel(sessionId: sid).whenComplete(() => exit(130)),
      ); // 128+SIGINT
      return;
    }
    exit(130);
  });

  final init = await client.initialize();

  // Handle list flags first if present
  String? listSessionId;
  if (hasListFlags) {
    final listHandler = ListOperationsHandler(
      args: args,
      client: client,
      init: init,
      agentName: agentName,
    );
    listSessionId = await listHandler.handleListFlags();

    // If no prompt, exit after lists
    if (isListOnlyMode) {
      await sigintSub.cancel();
      await client.dispose();
      exit(0);
    }
  }
  // If we already created a session for lists, reuse it for the prompt
  if (listSessionId != null) {
    _sessionId = listSessionId;
  } else if (args.resumeSessionId != null) {
    // Guard session/load behind capability per spec
    final supportsLoad =
        (init.agentCapabilities ?? const {})['loadSession'] == true;
    if (!supportsLoad) {
      stderr.writeln(
        'Error: Agent does not support session/load (loadSession=false).',
      );
      await sigintSub.cancel();
      await client.dispose();
      exit(2);
    }
    _sessionId = args.resumeSessionId;
    await client.loadSession(
      sessionId: _sessionId!,
      workspaceRoot: Directory.current.path,
    );
  } else {
    _sessionId = await client.newSession(Directory.current.path);
    if (args.saveSessionPath != null) {
      await File(args.saveSessionPath!).writeAsString(_sessionId!);
    }
  }

  // Create output formatter
  final formatter = OutputFormatter(args.output);

  // Subscribe terminal events (text mode only)
  if (args.output == OutputMode.text) {
    client.terminalEvents.listen(formatter.printTerminalEvent);
  }

  // Subscribe to persistent session updates early so we don't miss
  // pre-prompt updates like available_commands_update.
  StreamSubscription<AcpUpdate>? sessionSub;
  final updatesStream = client.sessionUpdates(_sessionId!).asBroadcastStream();
  if (args.output == OutputMode.text) {
    sessionSub = updatesStream.listen(formatter.printSessionUpdate);
  }

  // If a modeId was provided, set it now (best-effort)
  if (args.modeId != null) {
    final modes = client.sessionModes(_sessionId!);
    const fallback = <({String id, String name})>[];
    final modeList = modes?.availableModes ?? fallback;
    final available = {
      for (final ({String id, String name}) m in modeList) m.id,
    };
    final desired = args.modeId!;
    if (!available.contains(desired)) {
      stderr.writeln('Error: Mode "$desired" not available.');
      await sigintSub.cancel();
      await sessionSub?.cancel();
      await client.dispose();
      exit(2);
    }
    final ok = await client.setMode(sessionId: _sessionId!, modeId: desired);
    if (!ok) {
      stderr.writeln('Warning: Failed to set mode "$desired".');
    }
  }

  final updates = client.prompt(sessionId: _sessionId!, content: prompt!);

  // In JSONL mode, do not print plain text; only JSONL is emitted to stdout
  // via protocol taps. In text/simple, stream assistant text chunks to stdout.
  await for (final u in updates) {
    if (u is MessageDelta) {
      formatter.printMessageDelta(u);
    } else if (u is TurnEnded) {
      // In text/simple, do not print a 'Turn ended' line per request.
      break;
    }
  }

  await sigintSub.cancel();
  // Clean up session update subscription
  if (sessionSub != null) {
    await sessionSub.cancel();
  }
  await client.dispose();
  // Normal completion
  exit(0);
}

Future<String?> _readPrompt(CliArgs args) async {
  if (args.prompt != null) return args.prompt;
  if (!stdin.hasTerminal) {
    // Read entire stdin as UTF-8
    return stdin.transform(utf8.decoder).join();
  }
  return null;
}

String? _sessionId;

/// Dummy filesystem provider - actual operations handled by SessionManager.
class _DummyFsProvider implements FsProvider {
  const _DummyFsProvider();

  @override
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    // This is never called - SessionManager creates its own provider
    throw UnimplementedError('Should not be called');
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    // This is never called - SessionManager creates its own provider
    throw UnimplementedError('Should not be called');
  }
}
