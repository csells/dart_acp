import 'dart:async';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('AcpClient e2e real adapters', () {
    Future<void> runClient({
      required String command,
      required List<String> args,
    }) async {
      final client = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          agentCommand: command,
          agentArgs: args,
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: false),
          ),
        ),
      );
      addTearDown(() async => client.dispose());
      await client.start();
      await client.initialize();
      final sid = await client.newSession();

      final updates = client.prompt(
        sessionId: sid,
        content: [AcpClient.text('Hello from e2e')],
      );

      var sawDelta = false;
      StopReason? end;
      await for (final u in updates) {
        if (u is MessageDelta) {
          sawDelta = true;
        }
        if (u is TurnEnded) {
          end = u.stopReason;
          break;
        }
      }

      expect(sawDelta, isTrue, reason: 'No assistant delta observed');
      expect(end, isNotNull);
    }

    test(
      'gemini responds to prompt (AcpClient)',
      () async {
        await runClient(command: 'gemini', args: ['--experimental-acp']);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'claude-code responds to prompt (AcpClient)',
      () async {
        await runClient(command: 'npx', args: ['acp-claude-code']);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
