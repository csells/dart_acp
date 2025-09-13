// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dart_acp/dart_acp.dart';

void main() async {
  final client = AcpClient(
    config: AcpConfig(
      workspaceRoot: Directory.current.path,
      agentCommand: 'npx',
      agentArgs: ['@zed-industries/claude-code-acp'],
    ),
  );

  await client.start();
  final sessionId = await client.newSession();
  final stream = client.prompt(
    sessionId: sessionId,
    content: 'examine @main.dart and explain what it does.',
  );

  await stream.forEach(print);
  await client.dispose();
  exit(0);
}
