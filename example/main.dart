import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/session/session_manager.dart' show InitializeResult;
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;

import 'args.dart';
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
  final cwd = Directory.current.path;

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

  final client = AcpClient(
    config: AcpConfig(
      workspaceRoot: cwd,
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
            final action = 
                decision == PermissionOutcome.allow ? 'allow' : 'deny';
            stdout.writeln('[permission] auto-$action ${opts.toolName}'
                '${opts.toolKind != null ? ' (${opts.toolKind})' : ''}');
            if (decision == PermissionOutcome.deny && isWriteOp) {
              stdout.writeln(
                  '[permission] Use --write or --yolo to enable writes');
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
    ),
  );

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

  await client.start();
  final init = await client.initialize();
  
  // Handle list flags first if present
  String? listSessionId;
  if (hasListFlags) {
    listSessionId = await _handleListFlags(
      args: args,
      client: client,
      init: init,
      agentName: agentName,
      sessionId: null,
    );
    
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
    await client.loadSession(sessionId: _sessionId!);
  } else {
    _sessionId = await client.newSession();
    if (args.saveSessionPath != null) {
      await File(args.saveSessionPath!).writeAsString(_sessionId!);
    }
  }

  // Subscribe terminal events (text mode only)
  if (args.output == OutputMode.text) {
    client.terminalEvents.listen((e) {
      if (e is TerminalCreated) {
        stdout.writeln('[term] created id=${e.terminalId} cmd=${e.command}');
      } else if (e is TerminalOutputEvent) {
        if (e.output.isNotEmpty) {
          stdout.writeln('[term] output id=${e.terminalId}');
        }
      } else if (e is TerminalExited) {
        stdout.writeln('[term] exited id=${e.terminalId} code=${e.code}');
      } else if (e is TerminalReleased) {
        stdout.writeln('[term] released id=${e.terminalId}');
      }
    });
  }

  // Subscribe to persistent session updates early so we don't miss
  // pre-prompt updates like available_commands_update.
  StreamSubscription<AcpUpdate>? sessionSub;
  final updatesStream = client.sessionUpdates(_sessionId!).asBroadcastStream();
  if (args.output == OutputMode.text) {
    sessionSub = updatesStream.listen((u) {
      // Only print updates during prompt execution, not during list-only mode
      if (u is PlanUpdate) {
          stdout.writeln('[plan] ${jsonEncode(u.plan)}');
        } else if (u is ToolCallUpdate) {
          final t = u.toolCall;
          final title = (t.title ?? '').trim();
          final kind = (t.kind?.toWire() ?? '').trim();
          var locText = '';
          final locs = t.locations ?? const [];
          if (locs.isNotEmpty) {
            final loc = locs.first;
            final path = loc.path;
            if (path.isNotEmpty) locText = ' @ $path';
          }
          final header = [
            if (kind.isNotEmpty) kind,
            if (title.isNotEmpty) title,
          ].join(' ');
          stdout.writeln('[tool] ${header.isEmpty ? t.toolCallId : header}$locText');
          // Show raw input/output snippets when present
          if (t.rawInput != null) {
            final snip = _truncate(_stringify(t.rawInput), 240);
            if (snip.isNotEmpty) stdout.writeln('[tool.in] $snip');
          }
          if (t.rawOutput != null) {
            final snip = _truncate(_stringify(t.rawOutput), 240);
            if (snip.isNotEmpty) stdout.writeln('[tool.out] $snip');
          }
        } else if (u is DiffUpdate) {
          stdout.writeln('[diff] ${jsonEncode(u.diff)}');
        }
    });
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

  final content = _buildContentBlocks(prompt!, cwd: cwd);
  final updates = client.prompt(sessionId: _sessionId!, content: content);

  // In JSONL mode, do not print plain text; only JSONL is emitted to stdout
  // via protocol taps. In text/simple, stream assistant text chunks to stdout.
  await for (final u in updates) {
    if (u is MessageDelta) {
      if (!args.output.isJsonLike) {
        // In simple mode, skip thought chunks
        if (args.output == OutputMode.simple && u.isThought) {
          continue;
        }
        final texts = u.content
            .whereType<TextContent>()
            .map((b) => b.text)
            .join();
        if (texts.isNotEmpty) stdout.writeln(texts);
      }
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

// Args/OutputMode are defined in args.dart

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…';
}

String _stringify(Object? o) {
  if (o == null) return '';
  try {
    if (o is String) return o;
    return jsonEncode(o);
  } on Object {
    return o.toString();
  }
}

List<Map<String, dynamic>> _buildContentBlocks(
  String prompt, {
  required String cwd,
}) {
  final blocks = <Map<String, dynamic>>[];
  // Always include the original user text with @-mentions untouched.
  blocks.add({'type': 'text', 'text': prompt});

  final mentions = _extractMentions(prompt);
  for (final m in mentions) {
    final uri = _toUri(m, cwd: cwd);
    if (uri == null) continue; // skip malformed
    final name = _displayNameFor(uri);
    final mimeType =
        mime.lookupMimeType(uri.path) ?? mime.lookupMimeType(uri.toString());
    final block = {
      'type': 'resource_link',
      'name': name,
      'uri': uri.toString(),
      if (mimeType != null) 'mimeType': mimeType,
    };
    blocks.add(block);
  }
  return blocks;
}

final _mentionRe = RegExp(r'''@("([^"\\]|\\.)*"|'([^'\\]|\\.)*'|\S+)''');

List<String> _extractMentions(String text) {
  final matches = _mentionRe.allMatches(text);
  final out = <String>[];
  for (final m in matches) {
    var token = m.group(1)!;
    // Strip surrounding quotes and unescape simple escapes
    if ((token.startsWith('"') && token.endsWith('"')) ||
        (token.startsWith("'") && token.endsWith("'"))) {
      token = token.substring(1, token.length - 1);
    }
    out.add(token);
  }
  return out;
}

Uri? _toUri(String token, {required String cwd}) {
  // URLs
  if (token.startsWith('http://') || token.startsWith('https://')) {
    try {
      return Uri.parse(token);
    } on FormatException catch (_) {
      stderr.writeln('Warning: invalid URL mention: @$token');
      return null;
    }
  }
  // Local file path
  var path = token;
  if (path.startsWith('~')) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      path = p.join(home, path.substring(1));
    }
  }
  if (!p.isAbsolute(path)) {
    path = p.join(cwd, path);
  }
  // Canonicalize a bit
  path = p.normalize(path);

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Warning: local path not found for mention: @$token');
  }
  return Uri.file(path);
}

String _displayNameFor(Uri uri) {
  if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final segs = uri.pathSegments;
    return segs.isNotEmpty ? segs.last : uri.host;
  }
  return p.basename(uri.path);
}

Future<String?> _handleListFlags({
  required CliArgs args,
  required AcpClient client,
  required InitializeResult init,
  required String agentName,
  String? sessionId,
}) async {
  final needsSession = args.listModes || args.listCommands;
  final outputSections = <String>[];
  
  // Capabilities (no session needed)
  if (args.listCaps) {
    if (args.output.isJsonLike) {
      final capsJson = {
        'jsonrpc': '2.0',
        'method': 'client/capabilities',
        'params': {
          'protocolVersion': init.protocolVersion,
          'authMethods': init.authMethods ?? [],
          'agentCapabilities': init.agentCapabilities ?? {},
        },
      };
      stdout.writeln(jsonEncode(capsJson));
    } else {
      outputSections.add(_formatCapabilitiesMarkdown(
        protocolVersion: init.protocolVersion,
        agentName: agentName,
        authMethods: init.authMethods,
        agentCapabilities: init.agentCapabilities,
      ));
    }
  }
  
  // Create session if needed for modes/commands
  if (needsSession && sessionId == null) {
    sessionId = await client.newSession();
    _sessionId = sessionId;
  }
  
  // Modes (needs session)
  if (args.listModes && sessionId != null) {
    final modes = client.sessionModes(sessionId);
    final currentId = modes?.currentModeId ?? '';
    final list = modes?.availableModes ?? const <({String id, String name})>[];
    
    if (args.output.isJsonLike) {
      final modesJson = {
        'jsonrpc': '2.0',
        'method': 'client/modes',
        'params': {
          'sessionId': sessionId,
          'currentModeId': currentId,
          'availableModes': [
            for (final m in list) {'id': m.id, 'name': m.name},
          ],
        },
      };
      stdout.writeln(jsonEncode(modesJson));
    } else {
      outputSections.add(_formatModesMarkdown(list, agentName));
    }
  }
  
  // Commands (needs session and waiting for update)
  if (args.listCommands && sessionId != null) {
    final commands = await _waitForCommands(client, sessionId, args);
    
    if (args.output.isJsonLike) {
      // For JSONL, the session update already emitted or we synthesize one
      if (commands.isEmpty) {
        final synthetic = {
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'available_commands_update',
              'availableCommands': <dynamic>[],
            },
          },
        };
        stdout.writeln(jsonEncode(synthetic));
      }
    } else {
      outputSections.add(_formatCommandsMarkdown(commands, agentName));
    }
  }
  
  // Print all sections for text/simple mode with blank line between
  if (!args.output.isJsonLike && outputSections.isNotEmpty) {
    for (var i = 0; i < outputSections.length; i++) {
      final section = outputSections[i];
      stdout.write(section);
      // Ensure section ends with newline
      if (!section.endsWith('\n')) {
        stdout.writeln();
      }
      // Add blank line after each section (including the last)
      stdout.writeln();
    }
  }
  
  // Return sessionId for reuse if created
  return sessionId;
}

Future<List<AvailableCommand>> _waitForCommands(
  AcpClient client,
  String sessionId,
  CliArgs args,
) async {
  final completer = Completer<List<AvailableCommand>>();
  late StreamSubscription<AcpUpdate> sub;
  
  sub = client.sessionUpdates(sessionId).listen((update) {
    if (update is AvailableCommandsUpdate) {
      if (!completer.isCompleted) {
        completer.complete(update.commands);
        unawaited(sub.cancel());
      }
    }
  });
  
  try {
    return await completer.future.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    await sub.cancel();
    return [];
  }
}

String _formatCapabilitiesMarkdown({
  required int protocolVersion,
  required String agentName,
  List<Map<String, dynamic>>? authMethods,
  Map<String, dynamic>? agentCapabilities,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# Capabilities ($agentName)');
  buffer.writeln('- Protocol Version: $protocolVersion');
  
  if (authMethods != null && authMethods.isNotEmpty) {
    buffer.writeln('- Auth Methods:');
    for (final m in authMethods) {
      final id = m['id'] ?? '';
      final name = m['name'] ?? '';
      final desc = m['description'];
      final descStr = 
          (desc == null || desc.toString().isEmpty) ? '' : ': $desc';
      buffer.writeln('  - $id - $name$descStr');
    }
  }
  
  if (agentCapabilities != null && agentCapabilities.isNotEmpty) {
    buffer.writeln('- Agent Capabilities:');
    _formatMapMarkdown(buffer, agentCapabilities, indent: 2);
  }
  
  return buffer.toString();
}

String _formatModesMarkdown(
  List<({String id, String name})> modes,
  String agentName,
) {
  final buffer = StringBuffer();
  buffer.writeln('# Modes ($agentName)');
  
  if (modes.isEmpty) {
    buffer.writeln('(no modes)');
  } else {
    for (final m in modes) {
      final line = m.name.isEmpty ? '- ${m.id}' : '- ${m.id} - ${m.name}';
      buffer.writeln(line);
    }
  }
  
  return buffer.toString();
}

String _formatCommandsMarkdown(
  List<AvailableCommand> commands,
  String agentName,
) {
  final buffer = StringBuffer();
  buffer.writeln('# Commands ($agentName)');
  
  if (commands.isEmpty) {
    buffer.writeln('(no commands)');
  } else {
    for (final c in commands) {
      final name = c.name;
      final desc = c.description ?? '';
      if (name.isEmpty) continue;
      if (desc.isEmpty) {
        buffer.writeln('- /$name');
      } else {
        buffer.writeln('- /$name - $desc');
      }
    }
  }
  
  return buffer.toString();
}

void _formatMapMarkdown(
  StringBuffer buffer,
  Map<String, dynamic> map, {
  int indent = 0,
}) {
  final pad = ' ' * indent;
  final keys = map.keys.toList()..sort();
  for (final k in keys) {
    final v = map[k];
    if (v is Map) {
      buffer.writeln('$pad- $k:');
      _formatMapMarkdown(
        buffer,
        Map<String, dynamic>.from(v),
        indent: indent + 2,
      );
    } else if (v is List) {
      buffer.writeln('$pad- $k:');
      _formatListMarkdown(buffer, v, indent: indent + 2);
    } else {
      buffer.writeln('$pad- $k: $v');
    }
  }
}

void _formatListMarkdown(StringBuffer buffer, List list, {int indent = 0}) {
  final pad = ' ' * indent;
  for (final item in list) {
    if (item is Map) {
      buffer.writeln('$pad-');
      _formatMapMarkdown(
        buffer,
        Map<String, dynamic>.from(item),
        indent: indent + 2,
      );
    } else {
      buffer.writeln('$pad- $item');
    }
  }
}
