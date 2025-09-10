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
      // Read example/settings.json from the CLI folder so the tests pick up
      // your local agent configuration and environment.
      settings = await Settings.loadFromFile('example/settings.json');
    });

    Future<void> runClient({
      required String agentKey,
      required String prompt,
      void Function(List<Map<String, dynamic>> frames)? onJsonFrames,
      FutureOr<void> Function(List<AcpUpdate> updates)? onUpdates,
    }) async {
      final agent = settings.agentServers[agentKey]!;
      final capturedOut = <String>[];
      final capturedIn = <String>[];
      final client = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          agentCommand: agent.command,
          agentArgs: agent.args,
          envOverrides: agent.env,
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
      'available commands via neutral prompt',
      () async {
        await runClient(
          agentKey: 'gemini',
          prompt:
              'List your available commands and briefly describe each one.'
              ' Do not execute anything until further instruction.',
          onUpdates: (updates) {
            expect(
              updates.any((u) => u is AvailableCommandsUpdate),
              isTrue,
              reason: 'No available_commands_update observed',
            );
          },
        );
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
        await runClient(
          agentKey: 'gemini',
          prompt:
              'Propose changes to README.md adding a "How to Test" section.'
              ' Do not apply changes; send only a diff.',
          onUpdates: (updates) {
            expect(
              updates.any((u) => u is DiffUpdate),
              isTrue,
              reason: 'No diff update observed',
            );
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'file read tool call happens when asked to summarize',
      () async {
        await runClient(
          agentKey: 'claude-code',
          prompt: 'Read README.md and summarize in one paragraph.',
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
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
