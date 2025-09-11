/// Example demonstrating the typed API for ACP updates.
// ignore_for_file: avoid_print

import 'package:dart_acp/dart_acp.dart';

void main() async {
  // Configure the client
  final config = AcpConfig(
    workspaceRoot: '/workspace',
    agentCommand: 'my-agent',
  );

  final client = AcpClient(config: config);
  await client.start();
  await client.initialize();

  // Create a session
  final sessionId = await client.newSession();

  // Send a prompt with typed content blocks
  final updates = client.prompt(
    sessionId: sessionId,
    content: [
      // Raw JSON format (still supported)
      AcpClient.text('Hello, agent!'),

      // Or use typed content blocks by converting to JSON
      AcpClient.textContent('What can you do?').toJson(),
    ],
  );

  // Process typed updates
  await for (final update in updates) {
    switch (update) {
      case MessageDelta(:final content, :final role):
        // Access typed content blocks
        for (final block in content) {
          switch (block) {
            case TextContent(:final text):
              print('$role: $text');
            case ImageContent(:final mimeType, :final data):
              print('$role sent image: $mimeType (${data.length} bytes)');
            case ResourceContent(:final uri, :final title):
              print('$role sent resource: ${title ?? uri}');
            case UnknownContent(:final data):
              print('$role sent unknown content: $data');
          }
        }

      case ToolCallUpdate(:final toolCall):
        // Access typed tool call properties
        print('Tool ${toolCall.name}: ${toolCall.status.name}');
        if (toolCall.error != null) {
          print('  Error: ${toolCall.error}');
        }

      case DiffUpdate(:final diff):
        // Access typed diff properties
        print('Diff ${diff.id} for ${diff.uri}: ${diff.status.name}');
        for (final change in diff.changes) {
          print('  ${change.type} at line ${change.line}: ${change.content}');
        }

      case PlanUpdate(:final plan):
        // Access typed plan blocks
        print('Plan: ${plan.title ?? "Execution Plan"}');
        for (final block in plan.blocks) {
          print(
            '  ${block.id}: ${block.content} (${block.status ?? "pending"})',
          );
        }

      case AvailableCommandsUpdate(:final commands):
        // Access typed commands
        print('Available commands:');
        for (final cmd in commands) {
          print('  ${cmd.name}: ${cmd.description ?? "No description"}');
        }

      case TurnEnded(:final stopReason):
        print('Turn ended: ${stopReason.name}');
      // Exit the loop

      case UnknownUpdate(:final raw):
        print('Unknown update: $raw');
    }
  }

  await client.dispose();
}
