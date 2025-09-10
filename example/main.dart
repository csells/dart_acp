import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;

import 'settings.dart';

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  if (args.help) {
    _printUsage();
    return;
  }
  final cwd = Directory.current.path;

  // Load settings.json next to this CLI (script directory)
  Settings settings;
  try {
    settings = await Settings.loadFromScriptDir();
  } on Object catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln('Tip: run with --help for usage.');
    exitCode = 2;
    return;
  }

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
          // Simple CLI prompt. Auto-allow in non-interactive environments.
          if (!stdin.hasTerminal) {
            // In JSONL mode, suppress human-readable prints entirely.
            if (!args.output.isJsonLike) {
              stdout.writeln('[permission] auto-allow ${opts.toolName}');
            }
            return PermissionOutcome.allow;
          }
          stdout.writeln(
            'Permission requested: ${opts.toolName}'
            '${opts.toolKind != null ? ' (${opts.toolKind})' : ''}',
          );
          if (opts.rationale.isNotEmpty) {
            stdout.writeln('Rationale: ${opts.rationale}');
          }
          stdout.write('Allow once? [y/N]: ');
          final input = stdin.readLineSync();
          if (input != null &&
              (input.toLowerCase() == 'y' || input.toLowerCase() == 'yes')) {
            return PermissionOutcome.allow;
          }
          return PermissionOutcome.deny;
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

  // Prepare prompt and decide if we're in list-only mode.
  final prompt = await _readPrompt(args);
  final listOnly =
      args.listCommands && (prompt == null || prompt.trim().isEmpty);
  if (!listOnly && (prompt == null || prompt.trim().isEmpty)) {
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

  try {
    await client.start();
    await client.initialize();
    if (args.resumeSessionId != null) {
      _sessionId = args.resumeSessionId;
      await client.loadSession(sessionId: _sessionId!);
    } else {
      _sessionId = await client.newSession();
      if (args.saveSessionPath != null) {
        try {
          await File(args.saveSessionPath!).writeAsString(_sessionId!);
        } on Exception catch (e) {
          stderr.writeln('Warning: failed to save session id: $e');
        }
      }
    }
  } on rpc.RpcException catch (e) {
    // Improve the auth-required error with selected agent context and guidance.
    final message = e.message.toLowerCase();
    if (e.code == -32000 &&
        message.contains('auth') &&
        message.contains('required')) {
      stderr.writeln(
        'JSON-RPC error -32000: Authentication required '
        '(agent_server: $agentName -> ${agent.command}).',
      );
      stderr.writeln(
        'Tip: try logging out, then logging back in for this agent, and retry.',
      );
    } else {
      stderr.writeln('JSON-RPC error ${e.code}: ${e.message}');
    }
    await sigintSub.cancel();
    await client.dispose();
    exitCode = 2;
    return;
  } on Object catch (e) {
    stderr.writeln('Error: $e');
    await sigintSub.cancel();
    await client.dispose();
    exitCode = 2;
    return;
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
      if (u is AvailableCommandsUpdate) {
        // Only print commands if --list-commands was passed
        if (listOnly) {
          final cmds = u.commands;
          if (cmds.isNotEmpty) {
            for (final c in cmds) {
              final name = (c['name'] ?? c['title'] ?? '').toString();
              final desc = (c['description'] ?? '').toString();
              if (name.isEmpty) continue;
              if (desc.isEmpty) {
                stdout.writeln('/$name');
              } else {
                stdout.writeln('/$name - $desc');
              }
            }
          }
        }
      } else if (!listOnly) {
        if (u is PlanUpdate) {
          stdout.writeln('[plan] ${jsonEncode(u.plan)}');
        } else if (u is ToolCallUpdate) {
          stdout.writeln('[tool] ${jsonEncode(u.toolCall)}');
        } else if (u is DiffUpdate) {
          stdout.writeln('[diff] ${jsonEncode(u.diff)}');
        }
      }
    });
  }

  // In list-only mode, do not send a prompt. Wait briefly for an
  // available_commands_update and then exit. If none arrives, print an empty
  // list in text mode.
  if (listOnly) {
    final settle = Completer<void>();
    late final StreamSubscription<AcpUpdate> onceSub;
    onceSub = updatesStream.listen((u) {
      if (!settle.isCompleted && u is AvailableCommandsUpdate) {
        settle.complete();
        unawaited(onceSub.cancel());
      }
    });
    // Wait briefly for command discovery; if none arrives in time,
    // treat it as an empty available commands result for tooling.
    try {
      await settle.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // If the agent didn't emit available_commands_update and we're in
      // JSONL mode, synthesize an empty available_commands_update frame
      // for tooling consistency.
      if (args.output.isJsonLike) {
        final synthetic = {
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': _sessionId,
            'update': {
              'sessionUpdate': 'available_commands_update',
              'availableCommands': <dynamic>[],
            },
          },
        };
        stdout.writeln(jsonEncode(synthetic));
      }
    }
    await onceSub.cancel(); // Cancel the subscription
    await sigintSub.cancel();
    await sessionSub?.cancel();
    await client.dispose();
    exit(0);
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
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'] as String)
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

Future<String?> _readPrompt(_Args args) async {
  if (args.prompt != null) return args.prompt;
  if (!stdin.hasTerminal) {
    // Read entire stdin as UTF-8
    return stdin.transform(utf8.decoder).join();
  }
  return null;
}

String? _sessionId;

class _Args {
  // Unnamed constructor first (lint: sort_unnamed_constructors_first)
  _Args({
    required this.output,
    required this.help,
    this.agentName,
    this.yolo = false,
    this.write = false,
    this.listCommands = false,
    this.resumeSessionId,
    this.saveSessionPath,
    this.prompt,
  });

  factory _Args.parse(List<String> argv) {
    String? agent;
    var output = OutputMode.text;
    var help = false;
    var yolo = false;
    var write = false;
    var listCommands = false;
    String? resume;
    String? savePath;
    final rest = <String>[];
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (a == '-h' || a == '--help') {
        help = true;
      } else if (a == '-a' || a == '--agent') {
        if (i + 1 >= argv.length) {
          stderr.writeln('Error: --agent requires a value');
          _printUsage();
          exit(2);
        }
        agent = argv[++i];
      } else if (a == '-o' || a == '--output') {
        if (i + 1 >= argv.length) {
          stderr.writeln('Error: --output requires a value');
          _printUsage();
          exit(2);
        }
        final mode = argv[++i];
        output = parseOutputMode(mode);
      } else if (a == '--yolo') {
        yolo = true;
      } else if (a == '--write') {
        write = true;
      } else if (a == '--list-commands') {
        listCommands = true;
      } else if (a == '--resume') {
        if (i + 1 >= argv.length) {
          stderr.writeln('Error: --resume requires a sessionId');
          _printUsage();
          exit(2);
        }
        resume = argv[++i];
      } else if (a == '--save-session') {
        if (i + 1 >= argv.length) {
          stderr.writeln('Error: --save-session requires a path');
          _printUsage();
          exit(2);
        }
        savePath = argv[++i];
      } else if (a == '--') {
        if (i + 1 < argv.length) {
          rest.addAll(argv.sublist(i + 1));
        }
        break;
      } else if (a.startsWith('-')) {
        stderr.writeln('Error: unknown option: $a');
        _printUsage();
        exit(2);
      } else {
        rest.add(a);
      }
    }
    final prompt = rest.isNotEmpty ? rest.join(' ') : null;
    return _Args(
      agentName: agent,
      output: output,
      help: help,
      yolo: yolo,
      write: write,
      listCommands: listCommands,
      resumeSessionId: resume,
      saveSessionPath: savePath,
      prompt: prompt,
    );
  }

  final String? agentName;
  final OutputMode output;
  final bool help;
  final bool yolo;
  final bool write;
  final bool listCommands;
  final String? resumeSessionId;
  final String? saveSessionPath;
  final String? prompt;
}

enum OutputMode { text, simple, jsonl }

OutputMode parseOutputMode(String s) {
  final v = s.toLowerCase().trim();
  if (v == 'text') return OutputMode.text;
  if (v == 'simple') return OutputMode.simple;
  if (v == 'json' || v == 'jsonl') return OutputMode.jsonl;
  stderr.writeln(
    'Error: invalid output mode: $s (expected jsonl|json|text|simple)',
  );
  exit(2);
}

extension OutputModeX on OutputMode {
  bool get isJsonLike => this == OutputMode.jsonl;
}

void _printUsage() {
  // Print to stdout for --help
  stdout.writeln('Usage: dart example/main.dart [options] [--] [prompt]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  -a, --agent <name>     Select agent from settings.json next to this CLI',
  );
  stdout.writeln('  -o, --output <mode>    Output mode:');
  stdout.writeln('                         jsonl|json|text|simple');
  stdout.writeln('                         (default: text)');
  stdout.writeln('      --yolo             Enable read-everywhere and');
  stdout.writeln('                         write-enabled (writes still');
  stdout.writeln('                         confined to CWD)');
  stdout.writeln(
    '      --write            Enable write capability (still confined to CWD)',
  );
  stdout.writeln('      --list-commands    Print available slash commands');
  stdout.writeln('                         (no prompt sent)');
  stdout.writeln('      --resume <id>      Resume an existing');
  stdout.writeln('                         session (replay), then send');
  stdout.writeln('                         the prompt');
  stdout.writeln('      --save-session <p> Save new sessionId to file');
  stdout.writeln('  -h, --help             Show this help and exit');
  stdout.writeln('');
  stdout.writeln('Prompt:');
  stdout.writeln('  Provide as a positional argument, or pipe via stdin.');
  stdout.writeln('  Use @-mentions to add context:');
  stdout.writeln('    @path, @"a file.txt",');
  stdout.writeln('    @https://example.com/file');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart example/main.dart -a my-agent "Summarize README.md"');
  stdout.writeln(
    '  echo "List available commands" | dart example/main.dart -o jsonl',
  );
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
