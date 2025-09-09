import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('agcli with mock agent', () {
    test('text mode prints assistant text', () async {
      final proc = await Process.start(
        'dart',
        ['example/agcli.dart', '-a', 'mock', 'Say hi @example/mock_agent.dart'],
      );
      final stdoutLines = proc.stdout.transform(utf8.decoder).transform(const LineSplitter());
      final stderrStr = proc.stderr.transform(utf8.decoder).join();

      final got = Completer<String>();
      final sub = stdoutLines.listen((line) {
        if (line.contains('Hello from mock agent.')) {
          got.complete(line);
        }
      });

      final code = await proc.exitCode.timeout(const Duration(seconds: 20));
      await sub.cancel();
      final err = await stderrStr;
      if (!got.isCompleted) {
        fail('Did not see assistant text. exit=$code stderr=$err');
      }
      expect(code, 0);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('jsonl mode emits JSON-RPC frames', () async {
      final proc = await Process.start(
        'dart',
        ['example/agcli.dart', '-a', 'mock', '-o', 'jsonl', 'Hello'],
      );
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final code = await proc.exitCode.timeout(const Duration(seconds: 20));
      expect(code, 0);
      // Expect at least one line to be valid JSON
      final anyJson = lines.any((l) {
        try { jsonDecode(l); return true; } catch (_) { return false; }
      });
      expect(anyJson, isTrue, reason: 'No JSONL frames found: ${lines.join('\n')}');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
