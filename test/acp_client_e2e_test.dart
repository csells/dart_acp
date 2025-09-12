import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../example/settings.dart';
// import 'helpers/adapter_caps.dart'; // Commented out - causes test loading issues

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
          jsonFrames.add(jsonDecode(l) as Map<String, dynamic>);
        }
        onJsonFrames(jsonFrames);
      }
    }

    // Helper to create a configured client for direct control in tests
    // (createClient helper defined in consolidated group below)

    // (No-op helper section)

    test('echo agent responds to prompt', () async {
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
              .whereType<TextContent>()
              .map((c) => c.text)
              .join();
          expect(fullText, equals('Echo: Hello from e2e'));

          // Check for completion
          expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

    test(
      'gemini responds to prompt (AcpClient)',
      () async {
        await runClient(
          agentKey: 'gemini',
          prompt: 'Say hello',
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
          prompt: 'Say hello',
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
                      (b) => b is TextContent && b.text.contains('```diff'),
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
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
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
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  // Additional E2E coverage consolidated from comprehensive tests
  group('AcpClient e2e consolidated', tags: 'e2e', () {
    late Settings settings;
    setUpAll(() async {
      settings = await Settings.loadFromFile('test/test_settings.json');
    });

    Future<AcpClient> createClient(
      String agentKey, {
      String? workspaceRoot,
      AcpCapabilities? capabilities,
      PermissionProvider? permissionProvider,
      TerminalProvider? terminalProvider,
    }) async {
      final agent = settings.agentServers[agentKey]!;
      final client = AcpClient(
        config: AcpConfig(
          workspaceRoot: workspaceRoot ?? Directory.current.path,
          agentCommand: agent.command,
          agentArgs: agent.args,
          envOverrides: agent.env,
          capabilities:
              capabilities ??
              const AcpCapabilities(
                fs: FsCapabilities(readTextFile: true, writeTextFile: true),
              ),
          permissionProvider:
              permissionProvider ?? const DefaultPermissionProvider(),
          terminalProvider: terminalProvider ?? DefaultTerminalProvider(),
        ),
      );
      await client.start();
      await client.initialize();
      return client;
    }

    Map<String, ToolCall> getFinalToolCalls(List<AcpUpdate> updates) {
      final toolCallsById = <String, ToolCall>{};
      var emptyIdCounter = 0;
      for (final update in updates.whereType<ToolCallUpdate>()) {
        var id = update.toolCall.id;
        if (id.isEmpty) {
          id = '__empty_${emptyIdCounter++}';
        }
        toolCallsById[id] = update.toolCall;
      }
      return toolCallsById;
    }

    for (final agentName in ['gemini', 'claude-code']) {
      test(
        '$agentName: create/manage sessions and cancellation',
        () async {
          final client = await createClient(agentName);
          addTearDown(client.dispose);
          final sessionId = await client.newSession();
          expect(sessionId, isNotEmpty);

          // Prompt and ensure response completes
          await client
              .prompt(
                sessionId: sessionId,
                content: [AcpClient.text('What is 2+2?')],
              )
              .drain();

          // Skip multiple prompts test for Gemini due to known bug
          if (agentName == 'gemini') {
            // Gemini's experimental ACP implementation has a bug
            // where it fails on multiple prompts to the same session
            // when using the default model. See specs/issues.md
            return;
          }

          // Test multiple prompts in same session
          await Future.delayed(const Duration(seconds: 1));
          final draining = client
              .prompt(
                sessionId: sessionId,
                content: [AcpClient.text('Count to 1000000 slowly')],
              )
              .drain();
          await Future.delayed(const Duration(milliseconds: 100));
          await client.cancel(sessionId: sessionId);
          await draining;
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        '$agentName: session replay via sessionUpdates',
        () async {
          final client = await createClient(agentName);
          addTearDown(client.dispose);
          final sessionId = await client.newSession();
          await client
              .prompt(sessionId: sessionId, content: [AcpClient.text('Hello')])
              .drain();
          final replayed = <AcpUpdate>[];
          await for (final u in client.sessionUpdates(sessionId)) {
            replayed.add(u);
            if (u is TurnEnded) break;
          }
          expect(replayed.whereType<MessageDelta>(), isNotEmpty);
        },
        timeout: const Timeout(Duration(seconds: 60)),
        // skip: skipIfMissingAll(agentName, [
        //   'loadsession',
        //   'load_session',
        // ], 'session/load'),
      );

      test(
        '$agentName: file read operations',
        () async {
          // Skip Gemini due to session/prompt bug
          if (agentName == 'gemini') {
            markTestSkipped("Gemini's experimental ACP has session/prompt bug");
            return;
          }
          final dir = await Directory.systemTemp.createTemp('acp_read_');
          addTearDown(() async {
            if (dir.existsSync()) {
              await dir.delete(recursive: true);
            }
          });
          File(
            path.join(dir.path, 'test.txt'),
          ).writeAsStringSync('Hello from test file');
          // For file operations test, we need to allow permissions
          // This simulates a user approving file access
          final client = await createClient(
            agentName,
            workspaceRoot: dir.path,
            permissionProvider: DefaultPermissionProvider(
              onRequest: (opts) async => PermissionOutcome.allow,
            ),
          );
          addTearDown(client.dispose);
          final sessionId = await client.newSession();
          final updates = <AcpUpdate>[];
          await client
              .prompt(
                sessionId: sessionId,
                content: [
                  AcpClient.text('Read the file test.txt and summarize it'),
                ],
              )
              .forEach(updates.add);
          final finalToolCalls = getFinalToolCalls(updates);
          expect(finalToolCalls, isNotEmpty);
          final messages = updates
              .whereType<MessageDelta>()
              .expand((m) => m.content)
              .whereType<TextContent>()
              .map((t) => t.text)
              .join()
              .toLowerCase();
          expect(messages, contains('hello'));
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        '$agentName: file write operations',
        () async {
          // Skip Gemini due to session/prompt bug
          if (agentName == 'gemini') {
            markTestSkipped("Gemini's experimental ACP has session/prompt bug");
            return;
          }
          final dir = await Directory.systemTemp.createTemp('acp_write_');
          addTearDown(() async {
            if (dir.existsSync()) {
              await dir.delete(recursive: true);
            }
          });
          // For write operations, we need both capabilities and permissions
          final client = await createClient(
            agentName,
            workspaceRoot: dir.path,
            capabilities: const AcpCapabilities(
              fs: FsCapabilities(readTextFile: true, writeTextFile: true),
            ),
            permissionProvider: DefaultPermissionProvider(
              onRequest: (opts) async => PermissionOutcome.allow,
            ),
          );
          addTearDown(client.dispose);
          final sessionId = await client.newSession();
          final updates = <AcpUpdate>[];
          await client
              .prompt(
                sessionId: sessionId,
                content: [
                  AcpClient.text(
                    'Create a file output.txt with content "Test output"',
                  ),
                ],
              )
              .forEach(updates.add);
          final finalToolCalls = getFinalToolCalls(updates);
          final writeCalls = finalToolCalls.values.where(
            (tc) =>
                tc.kind == 'write' ||
                tc.kind == 'edit' ||
                (tc.name?.contains('write') ?? false),
          );
          expect(writeCalls.isNotEmpty, isTrue);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }

    test('permission denial is respected', () async {
      // Test that when permissions are denied, operations fail appropriately
      final dir = await Directory.systemTemp.createTemp('acp_perm_test_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      File(path.join(dir.path, 'secret.txt')).writeAsStringSync('Secret data');

      final client = await createClient(
        'claude-code',
        workspaceRoot: dir.path,
        permissionProvider: DefaultPermissionProvider(
          onRequest: (opts) async => PermissionOutcome.deny,
        ),
      );
      addTearDown(client.dispose);

      final sessionId = await client.newSession();
      final updates = <AcpUpdate>[];
      await client
          .prompt(
            sessionId: sessionId,
            content: [AcpClient.text('Read the file secret.txt')],
          )
          .forEach(updates.add);

      // The agent should indicate it couldn't read the file
      final messages = updates
          .whereType<MessageDelta>()
          .expand((m) => m.content)
          .whereType<TextContent>()
          .map((t) => t.text)
          .join()
          .toLowerCase();

      // Should NOT contain the secret data
      expect(messages, isNot(contains('secret data')));
      // Should indicate permission issue or inability to read
      expect(
        messages.contains('permission') ||
            messages.contains('unable') ||
            messages.contains('cannot') ||
            messages.contains('denied'),
        isTrue,
        reason: 'Agent should indicate permission was denied',
      );
    });

    test('invalid session id yields error', () async {
      final client = await createClient('claude-code');
      addTearDown(client.dispose);
      final sessionId = await client.newSession();
      final invalid = 'invalid-$sessionId-mod';
      expect(
        () => client
            .prompt(sessionId: invalid, content: [AcpClient.text('Hello')])
            .drain(),
        throwsA(anything),
      );
    });

    test('agent crash surfaces error', () async {
      final crashing = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          agentCommand: 'false',
          agentArgs: const [],
        ),
      );
      addTearDown(() async {
        try {
          await crashing.dispose();
        } on Object {
          // Ignore disposal errors for crashed agent
        }
      });
      // The agent crashes immediately, so start should throw
      await expectLater(
        crashing.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Agent process exited immediately'),
          ),
        ),
      );
    });

    group('Terminal Operations', () {
      for (final agentName in ['gemini', 'claude-code']) {
        test(
          '$agentName: execute via terminal or execute tool',
          () async {
            // Skip Gemini due to session/prompt bug
            if (agentName == 'gemini') {
              markTestSkipped(
                "Gemini's experimental ACP has session/prompt bug",
              );
              return;
            }
            final client = await createClient(agentName);
            addTearDown(client.dispose);
            final sessionId = await client.newSession();
            final events = <TerminalEvent>[];
            final sub = client.terminalEvents.listen(events.add);
            final updates = <AcpUpdate>[];
            await client
                .prompt(
                  sessionId: sessionId,
                  content: [
                    AcpClient.text(
                      'Run the command: echo "Hello from terminal"',
                    ),
                  ],
                )
                .forEach(updates.add);
            await Future.delayed(const Duration(milliseconds: 500));
            await sub.cancel();
            if (events.isNotEmpty) {
              final created = events.whereType<TerminalCreated>().firstOrNull;
              if (created != null) {
                final out = await client.terminalOutput(created.terminalId);
                expect(out, contains('Hello'));
              }
            }
            final finalToolCalls = getFinalToolCalls(updates);
            final execCalls = finalToolCalls.values.where(
              (tc) =>
                  tc.kind == 'execute' ||
                  (tc.name?.contains('execute') ?? false),
            );
            expect(events.isNotEmpty || execCalls.isNotEmpty, isTrue);
          },
          // skip: skipIfNoRuntimeTerminal(agentName),
        );
      }
    });
  });
}
