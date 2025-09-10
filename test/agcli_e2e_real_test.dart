import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('agcli e2e real adapters', tags: 'e2e', () {
    test('gemini: list commands (jsonl) — may be empty', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        '-o',
        'jsonl',
        '--list-commands',
      ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
      
      // Collect output in background without waiting
      final lines = <String>[];
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);
      final stderrBuffer = StringBuffer();
      proc.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      
      final code = await proc.exitCode.timeout(const Duration(seconds: 30));
      expect(
        code,
        0,
        reason: 'list-commands run failed. stderr= ${stderrBuffer.toString()}',
      );
      // Gemini may not emit available_commands_update; accept absence.
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('gemini: list commands (text mode)', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        '--list-commands',
      ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
      
      final outBuffer = StringBuffer();
      proc.stdout.transform(utf8.decoder).listen(outBuffer.write);
      
      final code = await proc.exitCode.timeout(const Duration(seconds: 30));
      expect(code, 0);
      // Gemini returns no commands, so output should be empty
      expect(
        outBuffer.toString().trim(),
        isEmpty,
        reason: 'Expected empty output for no commands',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'claude-code: list commands (jsonl)',
      () async {
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          '--list-commands',
        ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
        final linesFuture = proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrFuture = proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        final lines = await linesFuture;
        final stderrText = await stderrFuture;
        expect(
          code,
          0,
          reason: 'list-commands run failed. stderr= $stderrText',
        );
        final hasAvail = lines.any(
          (l) => l.contains('"sessionUpdate":"available_commands_update"'),
        );
        expect(
          hasAvail,
          isTrue,
          reason: 'No available_commands_update observed',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
    test('gemini: output text mode', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        'Quick check of text mode',
      ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
      final outFuture = proc.stdout.transform(utf8.decoder).join();
      final stderrFuture = proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(minutes: 1));
      final out = await outFuture;
      final stderrText = await stderrFuture;
      expect(
        code,
        0,
        reason:
            'non-zero exit. stderr= '
            '$stderrText',
      );
      expect(out, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('gemini: stdin prompt (jsonl)', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        '-o',
        'jsonl',
      ]);
      proc.stdin.writeln('Hello from stdin');
      await proc.stdin.flush();
      await proc.stdin.close();
      final linesFuture = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stderrFuture = proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(minutes: 2));
      final lines = await linesFuture;
      final stderrText2 = await stderrFuture;
      expect(
        code,
        0,
        reason:
            'stdin jsonl run failed. stderr= '
            '$stderrText2',
      );
      final anyJson = lines.any((l) {
        try {
          jsonDecode(l);
          return true;
        } on Object catch (_) {
          return false;
        }
      });
      expect(anyJson, isTrue, reason: 'No JSONL frames emitted on stdin run');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'claude-code: output simple mode',
      () async {
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          '-o',
          'simple',
          'Hello',
        ]);
        final outFuture = proc.stdout.transform(utf8.decoder).join();
        final stderrFuture = proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(minutes: 2));
        final out = await outFuture;
        final stderrText3 = await stderrFuture;
        expect(
          code,
          0,
          reason:
              'non-zero exit. stderr= '
              '$stderrText3',
        );
        // Should not contain our bracketed sections in simple mode
        expect(
          out.contains('[plan]') ||
              out.contains('[tool]') ||
              out.contains('[diff]') ||
              out.contains('[commands]'),
          isFalse,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code: stdin prompt (text)',
      () async {
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
        ]);
        proc.stdin.writeln('Hello from stdin');
        await proc.stdin.flush();
        await proc.stdin.close();
        final outFuture = proc.stdout.transform(utf8.decoder).join();
        final stderrFuture = proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(minutes: 3));
        final out = await outFuture;
        final stderrText4 = await stderrFuture;
        expect(
          code,
          0,
          reason:
              'stdin text run failed. stderr= '
              '$stderrText4',
        );
        expect(out, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'gemini: file mentions produce resource_link blocks (jsonl)',
      () async {
        final dir = await Directory.systemTemp.createTemp('agcli_mentions_');
        try {
          final f1 = File('${dir.path}/a.txt')..writeAsStringSync('one');
          final f2 = File('${dir.path}/file space.txt')
            ..writeAsStringSync('two');
          final prompt =
              'Review @${f1.path} and @"${f2.path}" and @https://example.com/spec.txt';
          final proc = await Process.start('dart', [
            'example/agcli.dart',
            '-a',
            'gemini',
            '-o',
            'jsonl',
            prompt,
          ]);
          final lines = await proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
          final code = await proc.exitCode.timeout(const Duration(minutes: 2));
          final stderrText = await proc.stderr.transform(utf8.decoder).join();
          expect(
            code,
            0,
            reason:
                'non-zero exit. stderr= '
                '$stderrText',
          );
          final promptLines = lines.where(
            (l) => l.contains('"method":"session/prompt"'),
          );
          expect(promptLines, isNotEmpty, reason: 'No session/prompt frame');
          final jsons = promptLines
              .map((l) => jsonDecode(l) as Map<String, dynamic>)
              .toList();
          final hasResourceLinks = jsons.any((m) {
            final params = m['params'] as Map<String, dynamic>;
            final prompt = params['prompt'] as List<dynamic>;
            return prompt.any((b) => b is Map && b['type'] == 'resource_link');
          });
          expect(
            hasResourceLinks,
            isTrue,
            reason: 'No resource_link blocks present',
          );
        } finally {
          try {
            await dir.delete(recursive: true);
          } on Object catch (_) {}
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code: session/new includes mcpServers (jsonl)',
      () async {
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          'Hello',
        ]);
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        // Agent may fail on mcp spawn; still assert we sent session/new with mcpServers
        final newLines = lines.where(
          (l) => l.contains('"method":"session/new"'),
        );
        expect(newLines, isNotEmpty, reason: 'No session/new frame');
        final hasMcp = newLines.any((l) {
          final obj = jsonDecode(l) as Map<String, dynamic>;
          final params = obj['params'] as Map<String, dynamic>;
          return params['mcpServers'] is List;
        });
        expect(hasMcp, isTrue, reason: 'session/new missing mcpServers');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'gemini: session resumption emits session/load (jsonl)',
      () async {
        final sidFile = File(
          '${Directory.systemTemp.path}/agcli_sid_${DateTime.now().microsecondsSinceEpoch}.txt',
        );
        try {
          var proc = await Process.start('dart', [
            'example/agcli.dart',
            '-a',
            'gemini',
            '--save-session',
            sidFile.path,
            '-o',
            'jsonl',
            'Hello',
          ]);
          var lines = await proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
          var code = await proc.exitCode.timeout(const Duration(minutes: 2));
          final stderrText5 = await proc.stderr.transform(utf8.decoder).join();
          expect(
            code,
            0,
            reason:
                'initial save-session run failed. stderr= '
                '$stderrText5',
          );
          expect(sidFile.existsSync(), isTrue);
          final sid = sidFile.readAsStringSync();
          proc = await Process.start('dart', [
            'example/agcli.dart',
            '-a',
            'gemini',
            '--resume',
            sid.trim(),
            '-o',
            'jsonl',
            'Continue',
          ]);
          lines = await proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
          code = await proc.exitCode.timeout(const Duration(minutes: 2));
          final loadLines = lines.where(
            (l) => l.contains('"method":"session/load"'),
          );
          expect(loadLines, isNotEmpty, reason: 'No session/load frame');
        } finally {
          try {
            await sidFile.delete();
          } on Object catch (_) {}
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
    test('gemini: output jsonl responds', () async {
      final proc = await Process.start('dart', [
        'example/agcli.dart',
        '-a',
        'gemini',
        '-o',
        'jsonl',
        'Hello from e2e',
      ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
      final lines = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final code = await proc.exitCode.timeout(const Duration(minutes: 2));
      final stderrText = await proc.stderr.transform(utf8.decoder).join();
      expect(
        code,
        0,
        reason:
            'gemini CLI exited non-zero. stderr= '
            '$stderrText',
      );
      final anyJson = lines.any((l) {
        try {
          jsonDecode(l);
          return true;
        } on Object catch (_) {
          return false;
        }
      });
      expect(anyJson, isTrue, reason: 'No JSONL frames emitted by gemini');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'claude-code: output jsonl responds',
      () async {
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          'Hello from e2e',
        ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
        final linesFuture = proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final stderrFuture = proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        final lines = await linesFuture;
        final stderrText = await stderrFuture;
        expect(
          code,
          0,
          reason:
              'claude-code adapter exited non-zero. stderr= '
              '$stderrText',
        );
        final anyJson = lines.any((l) {
          try {
            jsonDecode(l);
            return true;
          } on Object catch (_) {
            return false;
          }
        });
        expect(
          anyJson,
          isTrue,
          reason: 'No JSONL frames emitted by claude-code',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'claude-code: session resumption emits session/load (jsonl)',
      () async {
        final sidFile = File(
          '${Directory.systemTemp.path}/agcli_sid_${DateTime.now().microsecondsSinceEpoch}_c.txt',
        );
        try {
          var proc = await Process.start('dart', [
            'example/agcli.dart',
            '-a',
            'claude-code',
            '--save-session',
            sidFile.path,
            '-o',
            'jsonl',
            'Hello',
          ]);
          var lines = await proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
          var code = await proc.exitCode.timeout(const Duration(minutes: 3));
          final stderrText = await proc.stderr.transform(utf8.decoder).join();
          expect(
            code,
            0,
            reason:
                'initial save-session run failed. stderr= '
                '$stderrText',
          );
          expect(sidFile.existsSync(), isTrue);
          final sid = sidFile.readAsStringSync();
          proc = await Process.start('dart', [
            'example/agcli.dart',
            '-a',
            'claude-code',
            '--resume',
            sid.trim(),
            '-o',
            'jsonl',
            'Continue',
          ]);
          lines = await proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
          code = await proc.exitCode.timeout(const Duration(minutes: 3));
          final loadLines = lines.where(
            (l) => l.contains('"method":"session/load"'),
          );
          expect(loadLines, isNotEmpty, reason: 'No session/load frame');
        } finally {
          try {
            await sidFile.delete();
          } on Object catch (_) {}
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'plans: text rendering and jsonl frames',
      () async {
        // JSONL assertion first (gemini)
        const planPrompt =
            'Before doing anything, produce a 3-step plan to add a '
            '"Testing" section to README.md. '
            'Stream plan updates for each step as you go. '
            'Stop after presenting the plan; do not apply changes yet.';
        var proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'gemini',
          '-o',
          'jsonl',
          planPrompt,
        ]);
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        var code = await proc.exitCode.timeout(const Duration(minutes: 2));
        expect(code, 0);
        final hasPlanFrame = lines.any(
          (l) =>
              l.contains('"method":"session/update"') && l.contains('"plan"'),
        );
        expect(hasPlanFrame, isTrue, reason: 'No plan session/update observed');

        // Text rendering check (claude-code)
        proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          planPrompt,
        ]);
        final outText = await proc.stdout.transform(utf8.decoder).join();
        code = await proc.exitCode.timeout(const Duration(minutes: 3));
        expect(code, 0);
        expect(outText.contains('[plan]'), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'diffs: text rendering and jsonl frames',
      () async {
        // JSONL assertion (claude-code)
        const diffPrompt =
            'Propose changes to README.md adding a "How to Test" section. '
            'Do not apply changes; send only a diff.';
        var proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'claude-code',
          '-o',
          'jsonl',
          diffPrompt,
        ]);
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        var code = await proc.exitCode.timeout(const Duration(minutes: 3));
        expect(code, 0);
        final hasDiffFrame = lines.any(
          (l) =>
              l.contains('"method":"session/update"') && l.contains('"diff"'),
        );
        expect(hasDiffFrame, isTrue, reason: 'No diff session/update observed');

        // Text rendering check (gemini)
        proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'gemini',
          diffPrompt,
        ]);
        final outText = await proc.stdout.transform(utf8.decoder).join();
        code = await proc.exitCode.timeout(const Duration(minutes: 2));
        expect(code, 0);
        expect(outText.contains('[diff]'), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'file I/O: tool calls appear in jsonl',
      () async {
        // Ask to read a file to encourage fs/read_text_file
        final proc = await Process.start('dart', [
          'example/agcli.dart',
          '-a',
          'gemini',
          '-o',
          'jsonl',
          'Read README.md and summarize in one paragraph.',
        ]);
      // Close stdin immediately since we're not sending any input
      await proc.stdin.close();
        final lines = await proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final code = await proc.exitCode.timeout(const Duration(minutes: 2));
        expect(code, 0);
        final sawTool = lines.any(
          (l) =>
              l.contains('"sessionUpdate":"tool_call"') ||
              l.contains('"sessionUpdate":"tool_call_update"'),
        );
        expect(sawTool, isTrue, reason: 'No tool_call frames observed');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
