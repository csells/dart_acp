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

      final updates = client.prompt(sessionId: sid, content: prompt);

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
        var id = update.toolCall.toolCallId;
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
              .prompt(sessionId: sessionId, content: 'What is 2+2?')
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
              .prompt(sessionId: sessionId, content: 'Count to 1000000 slowly')
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
          await client.prompt(sessionId: sessionId, content: 'Hello').drain();
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
          // Skip Gemini - doesn't report tool calls as expected by test
          if (agentName == 'gemini') {
            markTestSkipped(
              "Gemini doesn't report read tool calls as expected",
            );
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
                content: 'Read the file test.txt and summarize it',
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
                content: 'Create a file output.txt with content "Test output"',
              )
              .forEach(updates.add);
          final finalToolCalls = getFinalToolCalls(updates);
          final writeCalls = finalToolCalls.values.where(
            (tc) =>
                tc.kind == ToolKind.edit ||
                (tc.title?.contains('write') ?? false),
          );
          expect(writeCalls.isNotEmpty, isTrue);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }

    test(
      'permission configuration is respected',
      () async {
        // Test that permissions configured in AcpConfig are properly respected
        final dir = await Directory.systemTemp.createTemp('acp_perm_cfg_');
        addTearDown(() async {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        });

        File(path.join(dir.path, 'test.txt')).writeAsStringSync('Test data');

        // Create a client with specific permission configuration
        final permissionRequests = <String>[];
        final client = await createClient(
          'claude-code',
          workspaceRoot: dir.path,
          permissionProvider: DefaultPermissionProvider(
            onRequest: (opts) async {
              permissionRequests.add(opts.toolKind ?? opts.toolName);
              // Deny write operations, allow read
              if ((opts.toolKind?.contains('write') ?? false) ||
                  opts.toolName.contains('write')) {
                return PermissionOutcome.deny;
              }
              return PermissionOutcome.allow;
            },
          ),
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: true),
          ),
        );
        addTearDown(client.dispose);

        final sessionId = await client.newSession();
        final updates = <AcpUpdate>[];

        // Ask to both read and write
        await client
            .prompt(
              sessionId: sessionId,
              content: 'Read test.txt and then write "Modified" to output.txt',
            )
            .forEach(updates.add);

        // Verify permission requests were made
        expect(
          permissionRequests.isNotEmpty,
          isTrue,
          reason: 'Permission provider should have been consulted',
        );

        // Check that the agent handled the denial appropriately
        final messages = updates
            .whereType<MessageDelta>()
            .expand((m) => m.content)
            .whereType<TextContent>()
            .map((t) => t.text)
            .join()
            .toLowerCase();

        // Should have read the file (allowed)
        expect(
          messages.contains('test data') || messages.contains('test.txt'),
          isTrue,
          reason: 'Agent should have been able to read the file',
        );

        // Should NOT have created output.txt (denied)
        expect(
          File(path.join(dir.path, 'output.txt')).existsSync(),
          isFalse,
          reason: 'Write should have been denied',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

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
          .prompt(sessionId: sessionId, content: 'Read the file secret.txt')
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
        () => client.prompt(sessionId: invalid, content: 'Hello').drain(),
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

    // Note: Minimum protocol version enforcement test is skipped because
    // AcpConfig.minimumProtocolVersion is a static constant (currently 1)
    // and all real agents return protocol version 1, so we cannot test
    // the rejection case without modifying the source code.

    test('richer tool metadata display', () async {
      // Test that tool calls include title, locations, raw_input, raw_output
      final dir = await Directory.systemTemp.createTemp('acp_tool_meta_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      File(path.join(dir.path, 'test.txt')).writeAsStringSync('Test content');

      final client = await createClient(
        'claude-code',
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
            content: 'Read test.txt and tell me what it contains',
          )
          .forEach(updates.add);

      // Find tool call updates
      final toolCalls = updates.whereType<ToolCallUpdate>();
      expect(toolCalls.isNotEmpty, isTrue, reason: 'No tool calls observed');

      // Check for richer metadata
      final readCall = toolCalls.firstWhere(
        (tc) =>
            tc.toolCall.kind == ToolKind.read ||
            (tc.toolCall.title?.contains('read') ?? false),
        orElse: () => toolCalls.first,
      );

      // Verify at least some metadata fields are present
      // Note: Not all fields may be present in every tool call
      final hasMetadata =
          readCall.toolCall.title != null ||
          readCall.toolCall.locations != null ||
          readCall.toolCall.rawInput != null ||
          readCall.toolCall.rawOutput != null;

      expect(
        hasMetadata,
        isTrue,
        reason: 'Tool call should have at least some metadata fields',
      );
    });

    test('current_mode_update routing', () async {
      // Test that current_mode_update events are properly routed as ModeUpdate
      final client = await createClient('claude-code');
      addTearDown(client.dispose);

      final sessionId = await client.newSession();

      // Get available modes
      final modes = client.sessionModes(sessionId);
      if (modes == null || modes.availableModes.isEmpty) {
        markTestSkipped('No modes available for testing');
        return;
      }

      // Find a mode different from current
      final currentMode = modes.currentModeId;
      final targetMode = modes.availableModes.firstWhere(
        (m) => m.id != currentMode,
        orElse: () => modes.availableModes.first,
      );

      if (targetMode.id == currentMode) {
        markTestSkipped('Only one mode available, cannot test mode change');
        return;
      }

      // Set up listener for mode updates
      final updates = <AcpUpdate>[];
      final sub = client
          .prompt(sessionId: sessionId, content: 'Hello')
          .listen(updates.add);

      // Change mode (this should trigger current_mode_update)
      await client.setMode(sessionId: sessionId, modeId: targetMode.id);

      // Wait a bit for the update to be routed
      await Future.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      // Check if we received a ModeUpdate
      final modeUpdates = updates.whereType<ModeUpdate>();
      expect(
        modeUpdates.isNotEmpty,
        isTrue,
        reason: 'No ModeUpdate received after changing mode',
      );

      final modeUpdate = modeUpdates.first;
      expect(modeUpdate.currentModeId, equals(targetMode.id));
    });

    group('Terminal Operations', () {
      for (final agentName in ['gemini', 'claude-code']) {
        test(
          '$agentName: execute via terminal or execute tool',
          () async {
            // Skip Gemini - doesn't report execute tool calls as expected
            if (agentName == 'gemini') {
              markTestSkipped(
                "Gemini doesn't report execute tool calls as expected - "
                'this is an agent limitation, not a dart_acp bug',
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
                  content: 'Run the command: echo "Hello from terminal"',
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
                  tc.kind == ToolKind.execute ||
                  (tc.title?.contains('execute') ?? false),
            );
            expect(events.isNotEmpty || execCalls.isNotEmpty, isTrue);
          },
          // skip: skipIfNoRuntimeTerminal(agentName),
        );
      }
    });
  });
}
