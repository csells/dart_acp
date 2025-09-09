import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('agcli e2e real adapters', () {
    test('gemini (jsonl) responds', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        '-o',
        'jsonl',
        'Hello from e2e',
      ]);
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final code = await proc.exitCode.timeout(const Duration(minutes: 2));
      expect(
        code,
        0,
        reason:
            'gemini CLI exited non-zero. stderr=${await proc.stderr.transform(utf8.decoder).join()}',
      );
      final anyJson = lines.any((l) {
        try {
          jsonDecode(l);
          return true;
        } catch (_) {
          return false;
        }
      });
      expect(anyJson, isTrue, reason: 'No JSONL frames emitted by gemini');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('claude-code (jsonl) responds', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'claude-code',
        '-o',
        'jsonl',
        'Hello from e2e',
      ]);
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final code = await proc.exitCode.timeout(const Duration(minutes: 3));
      expect(
        code,
        0,
        reason:
            'claude-code adapter exited non-zero. stderr=${await proc.stderr.transform(utf8.decoder).join()}',
      );
      final anyJson = lines.any((l) {
        try {
          jsonDecode(l);
          return true;
        } catch (_) {
          return false;
        }
      });
      expect(anyJson, isTrue, reason: 'No JSONL frames emitted by claude-code');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
