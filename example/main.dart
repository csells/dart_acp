// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dart_acp/dart_acp.dart';

void main() async {
  final client = await AcpClient.start(
    config: AcpConfig(
      agentCommand: 'npx',
      agentArgs: ['@zed-industries/claude-code-acp'],
    ),
  );

  final workspaceRoot = Directory.current.path;
  final sessionId = await client.newSession(workspaceRoot);
  final stream = client.prompt(
    sessionId: sessionId,
    content: 'examine @main.dart and explain what it does.',
  );

  await for (final update in stream) {
    print(update.text);
  }

  await client.dispose();
  exit(0);
}
