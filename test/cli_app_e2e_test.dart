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
