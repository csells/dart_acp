import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

import '../example/settings.dart';

void main() {
  test('mock agent responds', () async {
    final settings = await Settings.loadFromFile('example/settings.json');
    final agent = settings.agentServers['mock']!;
    
    final client = AcpClient(
      config: AcpConfig(
        workspaceRoot: Directory.current.path,
        agentCommand: agent.command,
        agentArgs: agent.args,
        envOverrides: agent.env,
        capabilities: const AcpCapabilities(
          fs: FsCapabilities(readTextFile: true, writeTextFile: false),
        ),
        terminalProvider: DefaultTerminalProvider(),
      ),
    );
    
    addTearDown(() async => client.dispose());
    await client.start();
    await client.initialize();
    final sid = await client.newSession();
    
    final updates = client.prompt(
      sessionId: sid,
      content: [AcpClient.text('Hello from test')],
    );
    
    final collected = <AcpUpdate>[];
    await for (final u in updates.timeout(
      const Duration(seconds: 10),
      onTimeout: (sink) {
        sink.close();
      },
    )) {
      collected.add(u);
      if (u is TurnEnded) break;
    }
    
    expect(collected.any((u) => u is MessageDelta), isTrue);
    expect(collected.whereType<TurnEnded>().isNotEmpty, isTrue);
  });
}