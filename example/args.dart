import 'dart:io';

enum OutputMode { text, simple, jsonl }

OutputMode parseOutputMode(String v) {
  final value = v.toLowerCase();
  if (value == 'text') return OutputMode.text;
  if (value == 'simple') return OutputMode.simple;
  if (value == 'json' || value == 'jsonl') return OutputMode.jsonl;
  throw ArgumentError('Unknown output mode: $v');
}

extension OutputModeX on OutputMode {
  bool get isJsonLike => this == OutputMode.jsonl;
}

class CliArgs {
  CliArgs({
    required this.output,
    required this.help,
    this.settingsPath,
    this.agentName,
    this.yolo = false,
    this.write = false,
    this.listCommands = false,
    this.listCaps = false,
    this.resumeSessionId,
    this.saveSessionPath,
    this.prompt,
  });

  factory CliArgs.parse(List<String> argv) {
    String? agent;
    String? settingsPath;
    var output = OutputMode.text;
    var help = false;
    var yolo = false;
    var write = false;
    var listCommands = false;
    var listCaps = false;
    String? resume;
    String? savePath;

    final rest = <String>[];
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (a == '-h' || a == '--help') {
        help = true;
      } else if (a == '--settings') {
        if (i + 1 >= argv.length) {
          throw ArgumentError('--settings requires a path');
        }
        settingsPath = argv[++i];
      } else if (a == '-a' || a == '--agent') {
        if (i + 1 >= argv.length) {
          throw ArgumentError('--agent requires a name');
        }
        agent = argv[++i];
      } else if (a == '-o' || a == '--output') {
        if (i + 1 >= argv.length) {
          throw ArgumentError('--output requires a mode');
        }
        output = parseOutputMode(argv[++i]);
      } else if (a == '--yolo') {
        yolo = true;
      } else if (a == '--write') {
        write = true;
      } else if (a == '--list-commands') {
        listCommands = true;
      } else if (a == '--list-caps') {
        listCaps = true;
      } else if (a == '--resume') {
        if (i + 1 >= argv.length) {
          throw ArgumentError('--resume requires a sessionId');
        }
        resume = argv[++i];
      } else if (a == '--save-session') {
        if (i + 1 >= argv.length) {
          throw ArgumentError('--save-session requires a path');
        }
        savePath = argv[++i];
      } else if (a.startsWith('-')) {
        throw ArgumentError('Unknown option: $a');
      } else {
        rest.add(a);
      }
    }

    String? prompt;
    if (rest.isNotEmpty) {
      prompt = rest.join(' ');
    } else if (stdin.hasTerminal) {
      prompt = null;
    } else {
      // In non-interactive mode, prompt is provided via stdin by the caller.
      prompt = null;
    }

    return CliArgs(
      output: output,
      help: help,
      settingsPath: settingsPath,
      agentName: agent,
      yolo: yolo,
      write: write,
      listCommands: listCommands,
      listCaps: listCaps,
      resumeSessionId: resume,
      saveSessionPath: savePath,
      prompt: prompt,
    );
  }

  final OutputMode output;
  final bool help;
  final String? settingsPath;
  final String? agentName;
  final bool yolo;
  final bool write;
  final bool listCommands;
  final bool listCaps;
  final String? resumeSessionId;
  final String? saveSessionPath;
  final String? prompt;
}
