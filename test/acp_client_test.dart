import 'dart:async';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('AcpClient with mock agent', () {
    late Directory workspace;
    late List<String> outFrames;
    late List<String> inFrames;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('acp_client_ws_');
      outFrames = [];
      inFrames = [];
    });

    tearDown(() async {
      try {
        await workspace.delete(recursive: true);
      } catch (_) {}
    });

    Future<AcpClient> startClient() async {
      final client = AcpClient(
        config: AcpConfig(
          workspaceRoot: workspace.path,
          agentCommand: 'dart',
          agentArgs: ['example/mock_agent.dart'],
          capabilities: const AcpCapabilities(),
          onProtocolOut: (l) => outFrames.add(l),
          onProtocolIn: (l) => inFrames.add(l),
        ),
      );
      await client.start();
      await client.initialize();
      return client;
    }

    test(
      'initialize + newSession + prompt streaming + end',
      () async {
        final client = await startClient();
        addTearDown(() async => client.dispose());

        final sid = await client.newSession();
        expect(sid, startsWith('sess_'));

        final updates = client.prompt(
          sessionId: sid,
          content: [AcpClient.text('Hello')],
        );

        var sawChunk = false;
        StopReason? end;
        await for (final u in updates) {
          if (u is MessageDelta) {
            final texts = u.content
                .where((b) => b['type'] == 'text')
                .map((b) => b['text'] as String)
                .join();
            if (texts.contains('Hello from mock agent.')) {
              sawChunk = true;
            }
          } else if (u is TurnEnded) {
            end = u.stopReason;
          }
        }

        expect(sawChunk, isTrue, reason: 'No assistant chunk observed');
        expect(end, StopReason.endTurn);

        // JSONL taps recorded protocol frames
        expect(
          outFrames.any((l) => l.contains('"method":"initialize"')),
          isTrue,
        );
        expect(inFrames.any((l) => l.contains('"result"')), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'cancel turns produce stopReason=cancelled',
      () async {
        final client = await startClient();
        addTearDown(() async => client.dispose());

        final sid = await client.newSession();
        final updates = client.prompt(
          sessionId: sid,
          content: [AcpClient.text('Please cancel')],
        );

        // Cancel immediately
        unawaited(client.cancel(sessionId: sid));

        StopReason? end;
        await for (final u in updates) {
          if (u is TurnEnded) {
            end = u.stopReason;
          }
        }
        expect(end, StopReason.cancelled);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'loadSession replays without error and updates stream exposed',
      () async {
        final client = await startClient();
        addTearDown(() async => client.dispose());
        final sid = await client.newSession();

        // First prompt
        await client
            .prompt(sessionId: sid, content: [AcpClient.text('Hello')])
            .drain();

        // Listen to sessionUpdates broadcast
        final all = <AcpUpdate>[];
        final sub = client.sessionUpdates(sid).listen(all.add);

        // Load session -> mock agent will replay its stored updates
        await client.loadSession(sessionId: sid);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        await sub.cancel();

        // We should have at least one MessageDelta from replay
        expect(all.any((u) => u is MessageDelta), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
