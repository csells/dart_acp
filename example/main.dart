import 'dart:async';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';

Future<void> main() async {
  final cwd = Directory.current.path;
  final client = AcpClient(
    config: AcpConfig(
      workspaceRoot: cwd,
      capabilities: const AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      ),
      permissionProvider: DefaultPermissionProvider(
        onRequest: (opts) async {
          // Simple CLI prompt. Auto-allow in non-interactive environments.
          if (!stdin.hasTerminal) {
            stdout.writeln(
              '[permission] non-interactive; auto-allow ${opts.toolName}',
            );
            return PermissionOutcome.allow;
          }
          stdout.writeln(
            'Permission requested: ${opts.toolName}${opts.toolKind != null ? ' (${opts.toolKind})' : ''}',
          );
          if (opts.rationale.isNotEmpty) {
            stdout.writeln('Rationale: ${opts.rationale}');
          }
          stdout.write('Allow once? [y/N]: ');
          final input = stdin.readLineSync();
          if (input != null &&
              (input.toLowerCase() == 'y' || input.toLowerCase() == 'yes')) {
            return PermissionOutcome.allow;
          }
          return PermissionOutcome.deny;
        },
      ),
      // agentCommand: 'claude-code-acp', // optional; falls back to npx if missing
      // terminalProvider: DefaultTerminalProvider(), // optional
    ),
  );

  await client.start();
  await client.initialize();
  final sessionId = await client.newSession();

  final updates = client.prompt(
    sessionId: sessionId,
    content: [
      AcpClient.text(
        'Please write a "Hello, World!" program in an obscure language of your choice.',
      ),
    ],
  );

  await for (final u in updates) {
    if (u is MessageDelta) {
      final texts = u.content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join();
      stdout.writeln('[${u.role}] $texts');
    } else if (u is PlanUpdate) {
      stdout.writeln('[plan] ${u.plan}');
    } else if (u is ToolCallUpdate) {
      stdout.writeln(
        '[tool] ${u.toolCall['title'] ?? u.toolCall['toolCallId']}',
      );
    } else if (u is AvailableCommandsUpdate) {
      stdout.writeln(
        '[commands] ${u.commands.map((c) => c['name']).join(', ')}',
      );
    } else if (u is TurnEnded) {
      stdout.writeln('Turn ended: ${u.stopReason}');
    }
  }

  await client.dispose();
}
