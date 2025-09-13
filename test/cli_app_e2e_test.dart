import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/adapter_caps.dart';

void main() {
  group('CLI app e2e real adapters', tags: 'e2e', () {
    final settingsPath = File('test/test_settings.json').absolute.path;

    test(
      'claude-code: list caps (jsonl)',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          '--list-caps',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'list-caps failed. stderr= $stderrText');
        final hasInitResult = lines
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .any(
              (m) =>
                  (m['result'] is Map) &&
                  (m['result'] as Map).containsKey('protocolVersion'),
            );
        expect(hasInitResult, isTrue, reason: 'No initialize result observed');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code: richer tool metadata in text mode',
      () async {
        final dir = await Directory.systemTemp.createTemp('cli_tool_meta_');
        addTearDown(() async {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        });
        
        File('${dir.path}/test.txt').writeAsStringSync('Test content');
        
        final proc = await Process.start(
          'dart',
          [
            File('example/main.dart').absolute.path,
            '--settings',
            settingsPath,
            '-a',
            'claude-code',
            '--write',  // Enable write to allow tools
            'Read test.txt and tell me what it contains',
          ],
          workingDirectory: dir.path,
        );
        await proc.stdin.close();
        final stdoutText = await proc.stdout.transform(utf8.decoder).join();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 90));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        
        // Check for tool metadata markers
        // The text mode should display [tool] markers when tools are used
        expect(stdoutText, contains('[tool]'),
               reason: 'Should display tool markers');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'stacking --list-xxx flags with markdown output',
      () async {
        // Test that all three list flags can be combined and output markdown
        final proc = await Process.start(
          'dart',
          [
            File('example/main.dart').absolute.path,
            '--settings',
            settingsPath,
            '-a',
            'claude-code',
            '--list-caps',
            '--list-modes',
            '--list-commands',
          ],
        );
        await proc.stdin.close();
        final stdoutText = await proc.stdout.transform(utf8.decoder).join();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        
        // Check for markdown headers
        expect(stdoutText, contains('# Capabilities'),
               reason: 'Should contain Capabilities header');
        expect(stdoutText, contains('# Modes'),
               reason: 'Should contain Modes header');
        expect(stdoutText, contains('# Commands'),
               reason: 'Should contain Commands header');
        
        // Check order (caps before modes before commands)
        final capsIndex = stdoutText.indexOf('# Capabilities');
        final modesIndex = stdoutText.indexOf('# Modes');
        final commandsIndex = stdoutText.indexOf('# Commands');
        
        expect(capsIndex < modesIndex, isTrue,
               reason: 'Capabilities should appear before Modes');
        expect(modesIndex < commandsIndex, isTrue,
               reason: 'Modes should appear before Commands');
        
        // Check for content
        expect(stdoutText, contains('Protocol Version:'),
               reason: 'Should show protocol version');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'stacking --list-xxx flags with JSONL output',
      () async {
        // Test JSONL output with all three list flags
        final proc = await Process.start(
          'dart',
          [
            File('example/main.dart').absolute.path,
            '--settings',
            settingsPath,
            '-a',
            'claude-code',
            '--list-caps',
            '--list-modes',
            '--list-commands',
            '-o',
            'jsonl',
          ],
        );
        await proc.stdin.close();
        final stdoutText = await proc.stdout.transform(utf8.decoder).join();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        
        // Parse JSONL lines
        final lines = stdoutText.trim().split('\n');
        final jsonLines = <Map<String, dynamic>>[];
        for (final line in lines) {
          if (line.isNotEmpty) {
            try {
              jsonLines.add(jsonDecode(line) as Map<String, dynamic>);
            } on FormatException {
              // Skip non-JSON lines
            }
          }
        }
        
        // Check for client/capabilities frame
        final capsFrame = jsonLines.firstWhere(
          (obj) => obj['method'] == 'client/capabilities',
          orElse: () => {},
        );
        expect(capsFrame.isNotEmpty, isTrue,
               reason: 'Should have client/capabilities frame');
        final capsParams = capsFrame['params'] as Map<String, dynamic>?;
        expect(capsParams?['protocolVersion'], isNotNull,
               reason: 'Capabilities should include protocol version');
        
        // Check for client/modes frame
        final modesFrame = jsonLines.firstWhere(
          (obj) => obj['method'] == 'client/modes',
          orElse: () => {},
        );
        expect(modesFrame.isNotEmpty, isTrue,
               reason: 'Should have client/modes frame');
        
        // Check for available_commands_update
        final commandsFrame = jsonLines.firstWhere(
          (obj) {
            if (obj['method'] != 'session/update') return false;
            final params = obj['params'] as Map<String, dynamic>?;
            final update = params?['update'] as Map<String, dynamic>?;
            return update?['sessionUpdate'] == 'available_commands_update';
          },
          orElse: () => {},
        );
        expect(commandsFrame.isNotEmpty, isTrue,
               reason: 'Should have available_commands_update');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'individual --list-commands with markdown format',
      () async {
        // Test that individual flag still works with markdown format
        final proc = await Process.start(
          'dart',
          [
            File('example/main.dart').absolute.path,
            '--settings',
            settingsPath,
            '-a',
            'claude-code',
            '--list-commands',
          ],
        );
        await proc.stdin.close();
        final stdoutText = await proc.stdout.transform(utf8.decoder).join();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        
        // Should have markdown header
        expect(stdoutText, contains('# Commands'),
               reason: 'Should have Commands markdown header');
        
        // Should NOT have other headers
        expect(stdoutText, isNot(contains('# Capabilities')),
               reason: 'Should not have Capabilities header');
        expect(stdoutText, isNot(contains('# Modes')),
               reason: 'Should not have Modes header');
        
        // Should have command entries with dash prefix OR no commands message
        final hasCommands = stdoutText.contains('- /') || 
                           stdoutText.contains('(no commands)');
        expect(hasCommands, isTrue,
               reason: 'Should show commands or no commands message');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'claude-code: terminal markers in text mode',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          // text mode prints [term] markers from TerminalEvents
          'Run the command: echo "Hello from terminal"',
        ]);
        await proc.stdin.close();
        final stdoutText = await proc.stdout.transform(utf8.decoder).join();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 90));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        // Accept any lifecycle marker to reduce flakiness across environments
        final sawTerm =
            stdoutText.contains('[term] created') ||
            stdoutText.contains('[term] output') ||
            stdoutText.contains('[term] exited');
        expect(
          sawTerm,
          isTrue,
          reason:
              'No terminal markers observed in text mode. stdout= $stdoutText',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipIfNoRuntimeTerminal('claude-code'),
    );

    test(
      'list modes: emits client/modes (jsonl)',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          '--list-modes',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'list-modes failed. stderr= $stderrText');
        final saw = lines.any((l) {
          try {
            final m = jsonDecode(l) as Map<String, dynamic>;
            return m['method'] == 'client/modes';
          } on Exception catch (_) {
            return false;
          }
        });
        expect(saw, isTrue, reason: 'No client/modes metadata observed');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'set mode fails when unavailable',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '--mode',
          'nonexistent-mode',
          'Hello',
        ]);
        await proc.stdin.close();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 60));
        expect(
          code,
          2,
          reason: 'Expected failure for unavailable mode. stderr= $stderrText',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '--resume guarded by loadSession capability (error when unsupported)',
      () async {
        final caps = capsFor('gemini');
        final ac = caps.agentCapabilities;
        final supports = ac['loadSession'] == true;
        if (supports) {
          return; // Skip if agent explicitly supports loadSession
        }
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'gemini',
          '--resume',
          'abc',
          'Hi',
        ]);
        await proc.stdin.close();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(
          code,
          2,
          reason:
              'Expected error when loadSession unsupported. '
              'stderr= $stderrText',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code: terminal frame appears in JSONL',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          'Run the command: echo "Hello from terminal"',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 120));
        expect(code, 0, reason: 'CLI failed. stderr= $stderrText');
        // Look for a tool_call_update with a terminal content block
        final sawTerminalContent = lines.any((l) {
          try {
            final m = jsonDecode(l) as Map<String, dynamic>;
            if (m['method'] != 'session/update') return false;
            final params = m['params'];
            if (params is! Map) return false;
            final upd = params['update'];
            if (upd is! Map) return false;
            if (upd['sessionUpdate'] != 'tool_call_update') return false;
            final content = upd['content'];
            if (content is! List) return false;
            return content.any((c) => c is Map && c['type'] == 'terminal');
          } on Exception catch (_) {
            return false;
          }
        });
        expect(
          sawTerminalContent,
          isTrue,
          reason:
              'No terminal content observed in JSONL tool_call_update frames',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipIfNoRuntimeTerminal('claude-code'),
    );

    test(
      'initialize (outbound) includes non-standard clientCapabilities.terminal',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          // Use list-caps to avoid creating a session; still emits initialize
          '--list-caps',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'list-caps failed. stderr= $stderrText');
        final sawOutboundInitWithTerminal = lines.any((l) {
          try {
            final m = jsonDecode(l) as Map<String, dynamic>;
            if (m['method'] != 'initialize') return false;
            final params = m['params'];
            if (params is! Map) return false;
            final caps = params['clientCapabilities'];
            if (caps is! Map) return false;
            return caps['terminal'] == true;
          } on Exception catch (_) {
            return false;
          }
        });
        expect(
          sawOutboundInitWithTerminal,
          isTrue,
          reason:
              'Outbound initialize did not include '
              'clientCapabilities.terminal: true',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: skipIfNoRuntimeTerminal('claude-code'),
    );
    test('gemini: list caps (jsonl)', () async {
      final proc = await Process.start('dart', [
        'example/main.dart',
        '--settings',
        settingsPath,
        '-a',
        'gemini',
        '-o',
        'jsonl',
        '--list-caps',
      ]);
      await proc.stdin.close();
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stderrText = await proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(seconds: 30));
      expect(code, 0, reason: 'list-caps failed. stderr= $stderrText');
      final hasInitResult = lines
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .any(
            (m) =>
                (m['result'] is Map) &&
                (m['result'] as Map).containsKey('protocolVersion'),
          );
      expect(hasInitResult, isTrue, reason: 'No initialize result observed');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'claude-code: list caps (json alias to jsonl)',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'claude-code',
          '-o',
          'json',
          '--list-caps',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'list-caps failed. stderr= $stderrText');
        final hasInitResult = lines
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .any(
              (m) =>
                  (m['result'] is Map) &&
                  (m['result'] as Map).containsKey('protocolVersion'),
            );
        expect(hasInitResult, isTrue, reason: 'No initialize result observed');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('echo: stacking --list-xxx flags with markdown output', () async {
      final proc = await Process.start('dart', [
        'example/main.dart',
        '--settings',
        settingsPath,
        '-a',
        'echo',
        '--list-caps',
        '--list-modes',
        '--list-commands',
      ]);
      await proc.stdin.close();
      final output = await proc.stdout.transform(utf8.decoder).join();
      final stderrText = await proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(seconds: 10));
      expect(code, 0, reason: 'stacking flags failed. stderr= $stderrText');
      
      // Verify all three sections appear with agent name
      expect(output, contains('# Capabilities (echo)'));
      expect(output, contains('# Modes (echo)'));
      expect(output, contains('# Commands (echo)'));
      
      // Verify order: capabilities -> modes -> commands
      final capsIndex = output.indexOf('# Capabilities');
      final modesIndex = output.indexOf('# Modes');
      final commandsIndex = output.indexOf('# Commands');
      expect(capsIndex, lessThan(modesIndex));
      expect(modesIndex, lessThan(commandsIndex));
      
      // Verify blank line between sections
      expect(output, contains('# Capabilities (echo)\n'));
      expect(output, contains('\n\n# Modes (echo)\n'));
      expect(output, contains('\n\n# Commands (echo)\n'));
    });

    test('echo: --list-xxx flags with prompt continues to process', () async {
      final proc = await Process.start('dart', [
        'example/main.dart',
        '--settings',
        settingsPath,
        '-a',
        'echo',
        '--list-caps',
        '--list-modes',
        'echo test message',
      ]);
      await proc.stdin.close();
      final output = await proc.stdout.transform(utf8.decoder).join();
      final stderrText = await proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(seconds: 10));
      expect(code, 0, reason: 'list+prompt failed. stderr= $stderrText');
      
      // Verify lists appear first
      expect(output, contains('# Capabilities (echo)'));
      expect(output, contains('# Modes (echo)'));
      
      // Verify prompt was processed after lists
      expect(output, contains('Echo: echo test message'));
      
      // Verify order: lists before prompt response
      final capsIndex = output.indexOf('# Capabilities');
      final echoIndex = output.indexOf('Echo: echo test message');
      expect(capsIndex, lessThan(echoIndex));
      
      // Verify blank line separates lists from prompt output
      expect(output, contains('(no modes)\n\nEcho: echo test message'));
    });

    test('echo: --list-xxx flags in JSONL mode', () async {
      final proc = await Process.start('dart', [
        'example/main.dart',
        '--settings',
        settingsPath,
        '-a',
        'echo',
        '-o',
        'jsonl',
        '--list-caps',
        '--list-modes',
        '--list-commands',
      ]);
      await proc.stdin.close();
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stderrText = await proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(seconds: 10));
      expect(code, 0, reason: 'jsonl list failed. stderr= $stderrText');
      
      // Parse JSONL lines
      final jsonObjects = lines
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      
      // Should have client/selected_agent, caps, modes, commands
      final hasSelectedAgent = 
          jsonObjects.any((m) => m['method'] == 'client/selected_agent');
      final hasCaps = 
          jsonObjects.any((m) => m['method'] == 'client/capabilities');
      final hasModes = 
          jsonObjects.any((m) => m['method'] == 'client/modes');
      final hasCommands = jsonObjects.any((m) {
        if (m['method'] != 'session/update') return false;
        final params = m['params'] as Map<String, dynamic>?;
        final update = params?['update'] as Map<String, dynamic>?;
        return update?['sessionUpdate'] == 'available_commands_update';
      });
      
      expect(hasSelectedAgent, isTrue, reason: 'Missing client/selected_agent');
      expect(hasCaps, isTrue, reason: 'Missing client/capabilities');
      expect(hasModes, isTrue, reason: 'Missing client/modes');
      expect(hasCommands, isTrue, reason: 'Missing available_commands_update');
    });

    test(
      'gemini: list commands (jsonl) — emits empty available_commands_update',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'gemini',
          '-o',
          'jsonl',
          '--list-commands',
        ]);
        await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrText = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(code, 0, reason: 'list-commands failed. stderr= $stderrText');
        final updates = lines
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .where((m) => m['method'] == 'session/update');
        final hasEmptyAvail = updates.any((m) {
          final params = m['params'];
          if (params is! Map) return false;
          final upd = params['update'];
          if (upd is! Map) return false;
          if (upd['sessionUpdate'] != 'available_commands_update') return false;
          final cmds = upd['availableCommands'];
          return cmds is List && cmds.isEmpty;
        });
        expect(hasEmptyAvail, isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'gemini: list commands (text mode)',
      () async {
        final proc = await Process.start('dart', [
          'example/main.dart',
          '--settings',
          settingsPath,
          '-a',
          'gemini',
          '--list-commands',
        ]);
        await proc.stdin.close();
        final stderrBuffer = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        expect(
          code,
          0,
          reason: 'list-commands run failed. stderr= $stderrBuffer',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
