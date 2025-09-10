import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

import '../example/settings.dart';

void main() {
  group('AcpClient e2e real adapters', tags: 'e2e', () {
    late Settings settings;

    setUpAll(() async {
      // Read test-specific settings.json so tests don't depend on default CLI
      // settings.
      settings = await Settings.loadFromFile('test/test_settings.json');
    });

    Future<void> runClient({
      required String agentKey,
      required String prompt,
      void Function(List<Map<String, dynamic>> frames)? onJsonFrames,
      FutureOr<void> Function(List<AcpUpdate> updates)? onUpdates,
      String? workspace,
    }) async {
      final agent = settings.agentServers[agentKey]!;
      final capturedOut = <String>[];
      final capturedIn = <String>[];
      final client = AcpClient(
        config: AcpConfig(
          workspaceRoot: workspace ?? Directory.current.path,
          agentCommand: agent.command,
          agentArgs: agent.args,
          envOverrides: agent.env,
          // In tests, allow all permissions so agents can propose diffs, etc.
          permissionProvider: DefaultPermissionProvider(
            onRequest: (opts) async => PermissionOutcome.allow,
          ),
          mcpServers: settings.mcpServers
              .map(
                (s) => {
                  'name': s.name,
                  'command': s.command,
                  'args': s.args,
                  if (s.env.isNotEmpty)
                    'env': s.env.entries
                        .map((e) => {'name': e.key, 'value': e.value})
                        .toList(),
                },
              )
              .toList(),
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: false),
          ),
          // Tap raw frames for JSONL assertions
          onProtocolOut: capturedOut.add,
          onProtocolIn: capturedIn.add,
          terminalProvider: DefaultTerminalProvider(),
        ),
      );
      addTearDown(() async => client.dispose());
      await client.start();
      await client.initialize();
      final sid = await client.newSession();

      final updates = client.prompt(
        sessionId: sid,
        content: [AcpClient.text(prompt)],
      );

      final collected = <AcpUpdate>[];
      await for (final u in updates.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          // If we timeout, close the sink to end the stream
          sink.close();
        },
      )) {
        collected.add(u);
        if (u is TurnEnded) break;
      }

      if (onUpdates != null) {
        await onUpdates(collected);
      }

      if (onJsonFrames != null) {
        final jsonFrames = <Map<String, dynamic>>[];
        for (final l in capturedOut.followedBy(capturedIn)) {
          try {
            jsonFrames.add(jsonDecode(l) as Map<String, dynamic>);
          } on Object catch (_) {}
        }
        onJsonFrames(jsonFrames);
      }
    }

    // (No-op helper section)

    test(
      'echo agent responds to prompt',
      () async {
        await runClient(
          agentKey: 'echo',
          prompt: 'Hello from e2e',
          onUpdates: (updates) {
            // Check we got message deltas
            final messageDeltas = updates.whereType<MessageDelta>().toList();
            expect(
              messageDeltas.isNotEmpty,
              isTrue,
              reason: 'No assistant delta observed',
            );
            
            // Verify the echo response
            final fullText = messageDeltas
                .expand((d) => d.content)
                .where((c) => c['type'] == 'text')
                .map((c) => c['text'] as String)
                .join();
            expect(fullText, equals('Echo: Hello from e2e'));
            
            // Check for completion
            expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'gemini responds to prompt (AcpClient)',
      () async {
        await runClient(
          agentKey: 'gemini',
          prompt: 'Hello from e2e',
          onUpdates: (updates) {
            expect(
              updates.any((u) => u is MessageDelta),
              isTrue,
              reason: 'No assistant delta observed',
            );
            expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code responds to prompt (AcpClient)',
      () async {
        await runClient(
          agentKey: 'claude-code',
          prompt: 'Hello from e2e',
          onUpdates: (updates) {
            expect(
              updates.any((u) => u is MessageDelta),
              isTrue,
              reason: 'No assistant delta observed',
            );
            expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'list commands uses --list-commands (no prompt)',
      () async {
        // Use the CLI to request available commands without sending a prompt.
        final proc = await Process.start('dart', [
          'example/main.dart',
          '-a',
          'gemini',
          '--list-commands',
        ]);
        // No prompt should be sent; close stdin immediately.
        await proc.stdin.close();

        final outBuffer = StringBuffer();
        final errBuffer = StringBuffer();
        proc.stdout.transform(utf8.decoder).listen(outBuffer.write);
        proc.stderr.transform(utf8.decoder).listen(errBuffer.write);

        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        // Allow zero or more commands; only assert successful exit.
        expect(code, 0, reason: 'list-commands run failed. stderr= $errBuffer');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'plan updates present when requested',
      () async {
        await runClient(
          agentKey: 'claude-code',
          prompt:
              'Before doing anything, produce a 3-step plan to add a '
              '"Testing" section to README.md. Stream plan updates for each '
              'step as you go. Stop after presenting the plan; do not apply '
              'changes yet.',
          onUpdates: (updates) {
            expect(
              updates.any((u) => u is PlanUpdate),
              isTrue,
              reason: 'No plan updates observed',
            );
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'diff-only prompt yields diff updates',
      () async {
        final dir = await Directory.systemTemp.createTemp('acp_client_diffs_');
        try {
          File('${dir.path}/README.md').writeAsStringSync('# Test README');
          await runClient(
            agentKey: 'claude-code',
            prompt:
                'Propose changes to README.md adding a "How to Test" section.'
                ' Do not apply changes; send only a diff.',
            workspace: dir.path,
            onUpdates: (updates) {
              final hasStructuredDiff = updates.any((u) => u is DiffUpdate);
              final hasTextDiff = updates.any(
                (u) =>
                    u is MessageDelta &&
                    u.content.any(
                      (b) =>
                          (b['type'] == 'text') &&
                          (b['text'] as String).contains('```diff'),
                    ),
              );
              expect(
                hasStructuredDiff || hasTextDiff,
                isTrue,
                reason: 'No diff update or diff code block observed',
              );
            },
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
      'file read tool call happens when asked to summarize',
      () async {
        final dir = await Directory.systemTemp.createTemp('acp_client_fileio_');
        try {
          File('${dir.path}/README.md').writeAsStringSync('# Test README');
          await runClient(
            agentKey: 'claude-code',
            prompt: 'Read README.md and summarize in one paragraph.',
            workspace: dir.path,
            onJsonFrames: (frames) {
              final sawTool = frames.any(
                (f) =>
                    f['method'] == 'session/update' &&
                    (f['params'] as Map)['update'] is Map &&
                    ((f['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                        'tool_call',
              );
              expect(
                sawTool,
                isTrue,
                reason: 'No tool_call observed for file read',
              );
            },
          );
        } finally {
          try {
            await dir.delete(recursive: true);
          } on Object catch (_) {}
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
