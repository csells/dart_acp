import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
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

  // Build client
  final client = AcpClient(
    config: AcpConfig(
      workspaceRoot: cwd,
      agentCommand: agent.command,
      agentArgs: agent.args,
      envOverrides: agent.env,
      capabilities: const AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      ),
      permissionProvider: DefaultPermissionProvider(
        onRequest: (opts) async {
          // Simple CLI prompt. Auto-allow in non-interactive environments.
          if (!stdin.hasTerminal) {
            stdout.writeln('[permission] auto-allow ${opts.toolName}');
            return PermissionOutcome.allow;
          }
          stdout.writeln(
            'Permission requested: ${opts.toolName}${opts.toolKind != null ? ' (${opts.toolKind})' : ''}',
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
      onProtocolOut: args.jsonl ? (line) => stderr.writeln(line) : null,
      onProtocolIn: args.jsonl ? (line) => stderr.writeln(line) : null,
    ),
  );

  // Prepare prompt
  final prompt = await _readPrompt(args);
  if (prompt == null || prompt.trim().isEmpty) {
    stderr.writeln('Error: empty prompt');
    stderr.writeln('Tip: run with --help for usage.');
    exitCode = 2;
    return;
  }

  // Handle Ctrl-C: send best-effort cancel without awaiting, then exit.
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    final sid = _sessionId;
    if (sid != null) {
      // Fire-and-forget; server may not respond to cancel.
      unawaited(client.cancel(sessionId: sid));
    }
    exit(130); // 128+SIGINT
  });

  await client.start();
  await client.initialize();
  _sessionId = await client.newSession();

  final updates = client.prompt(
    sessionId: _sessionId!,
    content: [AcpClient.text(prompt)],
  );

  // In JSONL mode, do not print plain text; only JSONL is emitted to stderr
  // via protocol taps. In plain mode, stream assistant text chunks to stdout.
  // No buffer needed; we either stream plain text (default) or emit JSONL only.
  await for (final u in updates) {
    if (u is MessageDelta) {
      final texts = u.content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join();
      if (texts.isEmpty) continue;
      if (!args.jsonl) stdout.writeln(texts);
    } else if (u is TurnEnded) {
      break; // End the app after the turn ends
    }
  }

  await sigintSub.cancel();
  await client.dispose();
  // Normal completion
  exit(0);
}

Future<String?> _readPrompt(_Args args) async {
  if (args.prompt != null) return args.prompt;
  if (!stdin.hasTerminal) {
    // Read entire stdin as UTF-8
    return await stdin.transform(utf8.decoder).join();
  }
  return null;
}
String? _sessionId;

class _Args {
  final String? agentName;
  final bool jsonl;
  final bool help;
  final String? prompt;

  _Args({this.agentName, required this.jsonl, required this.help, this.prompt});

  static _Args parse(List<String> argv) {
    String? agent;
    bool jsonl = false;
    bool help = false;
    final rest = <String>[];
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (a == '-j' || a == '--jsonl') {
        jsonl = true;
      } else if (a == '-h' || a == '--help') {
        help = true;
      } else if (a == '-a' || a == '--agent') {
        if (i + 1 >= argv.length) {
          stderr.writeln('Error: --agent requires a value');
          _printUsage();
          exit(2);
        }
        agent = argv[++i];
      } else if (a == '--') {
        // Remainder is prompt
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
    return _Args(agentName: agent, jsonl: jsonl, help: help, prompt: prompt);
  }
}

void _printUsage() {
  // Print to stdout for --help
  stdout.writeln('Usage: dart run example/main.dart [options] [--] [prompt]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  -a, --agent <name>   Select agent from settings.json next to this CLI');
  stdout.writeln('  -j, --jsonl          Emit protocol JSON-RPC frames to stderr (no plain text)');
  stdout.writeln('  -h, --help           Show this help and exit');
  stdout.writeln('');
  stdout.writeln('Prompt:');
  stdout.writeln('  Provide as a positional argument, or pipe via stdin.');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart run example/main.dart -a my-agent "Summarize README.md"');
  stdout.writeln('  echo "List available commands" | dart run example/main.dart -j');
}
