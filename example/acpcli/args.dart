import 'package:args/args.dart';

enum OutputMode { text, simple, jsonl }

class CliArgs {
  CliArgs({
    required this.output,
    required this.help,
    this.settingsPath,
    this.agentName,
    this.yolo = false,
    this.write = false,
    this.listCommands = false,
    this.listModes = false,
    this.listCaps = false,
    this.modeId,
    this.resumeSessionId,
    this.saveSessionPath,
    this.prompt,
  });

  factory CliArgs.parse(List<String> argv) {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', help: 'Show this help and exit')
      ..addOption('agent', abbr: 'a', help: 'Select agent from settings.json')
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output mode',
        allowed: ['text', 'simple', 'json', 'jsonl'],
        defaultsTo: 'text',
      )
      ..addOption('settings', help: 'Use a specific settings.json')
      ..addFlag('yolo', help: 'Enable read-everywhere and write-enabled')
      ..addFlag(
        'write',
        help: 'Enable write capability (still confined to CWD)',
      )
      ..addFlag(
        'list-commands',
        help: 'Print available slash commands (no prompt sent)',
      )
      ..addFlag(
        'list-modes',
        help: 'Print available session modes (no prompt sent)',
      )
      ..addFlag(
        'list-caps',
        help: 'Print agent capabilities from initialize (no prompt sent)',
      )
      ..addOption('mode', help: 'Set session mode after creation')
      ..addOption('resume', help: 'Resume an existing session (replay)')
      ..addOption('save-session', help: 'Save new sessionId to file');

    final results = parser.parse(argv);

    // Parse output mode
    final outputStr = results['output'] as String;
    OutputMode output;
    switch (outputStr) {
      case 'simple':
        output = OutputMode.simple;
      case 'json':
      case 'jsonl':
        output = OutputMode.jsonl;
      default:
        output = OutputMode.text;
    }

    // Collect remaining arguments as prompt
    String? prompt;
    if (results.rest.isNotEmpty) {
      prompt = results.rest.join(' ');
    }

    return CliArgs(
      output: output,
      help: results['help'] as bool,
      settingsPath: results['settings'] as String?,
      agentName: results['agent'] as String?,
      yolo: results['yolo'] as bool,
      write: results['write'] as bool,
      listCommands: results['list-commands'] as bool,
      listModes: results['list-modes'] as bool,
      listCaps: results['list-caps'] as bool,
      modeId: results['mode'] as String?,
      resumeSessionId: results['resume'] as String?,
      saveSessionPath: results['save-session'] as String?,
      prompt: prompt,
    );
  }

  static String getUsage() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', help: 'Show this help and exit')
      ..addOption('agent', abbr: 'a', help: 'Select agent from settings.json')
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output mode',
        allowed: ['text', 'simple', 'json', 'jsonl'],
        defaultsTo: 'text',
      )
      ..addOption('settings', help: 'Use a specific settings.json')
      ..addFlag('yolo', help: 'Enable read-everywhere and write-enabled')
      ..addFlag(
        'write',
        help: 'Enable write capability (still confined to CWD)',
      )
      ..addFlag(
        'list-commands',
        help: 'Print available slash commands (no prompt sent)',
      )
      ..addFlag(
        'list-modes',
        help: 'Print available session modes (no prompt sent)',
      )
      ..addFlag(
        'list-caps',
        help: 'Print agent capabilities from initialize (no prompt sent)',
      )
      ..addOption('mode', help: 'Set session mode after creation')
      ..addOption('resume', help: 'Resume an existing session (replay)')
      ..addOption('save-session', help: 'Save new sessionId to file');

    return '''
Usage: dart example/acpcli/acpcli.dart [options] [--] [prompt]

${parser.usage}

Prompt:
  Provide as a positional argument, or pipe via stdin.
  Use @-mentions to add context:
    @path, @"a file.txt", @https://example.com/file

Examples:
  dart example/acpcli/acpcli.dart -a my-agent "Summarize README.md"
  echo "List available commands" | dart example/acpcli/acpcli.dart -o jsonl''';
  }

  final OutputMode output;
  final bool help;
  final String? settingsPath;
  final String? agentName;
  final bool yolo;
  final bool write;
  final bool listCommands;
  final bool listModes;
  final bool listCaps;
  final String? modeId;
  final String? resumeSessionId;
  final String? saveSessionPath;
  final String? prompt;
}

extension OutputModeX on OutputMode {
  bool get isJsonLike => this == OutputMode.jsonl;
}
