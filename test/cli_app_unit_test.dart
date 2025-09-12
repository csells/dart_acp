import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../example/args.dart';
import '../example/settings.dart';

void main() {
  group('CLI args parse', () {
    test('defaults', () {
      final a = CliArgs.parse([]);
      expect(a.output, OutputMode.text);
      expect(a.help, isFalse);
      expect(a.agentName, isNull);
      expect(a.prompt, isNull);
    });

    test('agent and output', () {
      final a = CliArgs.parse(['-a', 'gemini', '-o', 'json']);
      expect(a.agentName, 'gemini');
      expect(a.output, OutputMode.jsonl);
      final b = CliArgs.parse(['--agent', 'claude-code', '--output', 'simple']);
      expect(b.agentName, 'claude-code');
      expect(b.output, OutputMode.simple);
    });

    test('flags and prompt', () {
      final a = CliArgs.parse([
        '--yolo',
        '--write',
        '--list-commands',
        '--list-caps',
        '--resume',
        'sid123',
        '--save-session',
        '/tmp/sid',
        'Hello',
        'world',
      ]);
      expect(a.yolo, isTrue);
      expect(a.write, isTrue);
      expect(a.listCommands, isTrue);
      expect(a.listCaps, isTrue);
      expect(a.resumeSessionId, 'sid123');
      expect(a.saveSessionPath, '/tmp/sid');
      expect(a.prompt, 'Hello world');
    });

    test('settings path', () {
      final a = CliArgs.parse(['--settings', '/tmp/settings.json']);
      expect(a.settingsPath, '/tmp/settings.json');
    });

    test('modes flags and parse', () {
      final a = CliArgs.parse(['--list-modes', '--mode', 'edit']);
      expect(a.listModes, isTrue);
      expect(a.modeId, 'edit');
    });
  });

  group('settings.json load', () {
    test('parses minimal valid file', () async {
      final dir = await Directory.systemTemp.createTemp('cli_settings_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final file = File('${dir.path}/settings.json');
      final json = jsonEncode({
        'agent_servers': {
          'echo': {
            'command': 'dart',
            'args': ['run', 'echo'],
          },
        },
        'mcp_servers': [
          {
            'name': 'fs',
            'command': '/bin/true',
            'args': [],
            'env': {'FOO': 'bar'},
          },
        ],
      });
      await file.writeAsString(json);
      final s = await Settings.loadFromFile(file.path);
      expect(s.agentServers.containsKey('echo'), isTrue);
      expect(s.mcpServers.single.name, 'fs');
    });

    test('invalid shape throws', () async {
      final dir = await Directory.systemTemp.createTemp('cli_settings_bad_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final file = File('${dir.path}/settings.json');
      await file.writeAsString(jsonEncode({'agent_servers': {}}));
      expect(
        () => Settings.loadFromFile(file.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
