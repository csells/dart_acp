import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

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
