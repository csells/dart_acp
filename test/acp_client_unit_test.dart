// Simplified AcpClient unit tests without problematic mocks

// ignore_for_file: avoid_dynamic_calls

import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/security/workspace_jail.dart';
import 'package:test/test.dart';

void main() {
  group('AcpConfig', () {
    test('creates with required fields', () {
      final config = AcpConfig(
        workspaceRoot: '/test/workspace',
        agentCommand: 'test-agent',
        agentArgs: const ['--test'],
      );
      expect(config.workspaceRoot, '/test/workspace');
      expect(config.agentCommand, 'test-agent');
      expect(config.agentArgs, ['--test']);
    });

    test('has default capabilities', () {
      final config = AcpConfig(
        workspaceRoot: '/test/workspace',
        agentCommand: 'test-agent',
      );
      expect(config.capabilities, isNotNull);
      expect(config.capabilities.fs.readTextFile, isTrue);
      // Default is false for write to be safe
      expect(config.capabilities.fs.writeTextFile, isFalse);
    });

    test('has minimum protocol version', () {
      expect(AcpConfig.minimumProtocolVersion, 1);
    });
  });

  group('StopReason mapping', () {
    test('maps end_turn', () {
      expect(stopReasonFromWire('end_turn'), StopReason.endTurn);
    });

    test('maps cancelled', () {
      expect(stopReasonFromWire('cancelled'), StopReason.cancelled);
    });

    test('maps max_tokens', () {
      expect(stopReasonFromWire('max_tokens'), StopReason.maxTokens);
    });

    test('maps unknown values to other', () {
      expect(stopReasonFromWire('unknown'), StopReason.other);
    });
  });

  group('Update types', () {
    test('MessageDelta handles content blocks', () {
      const update = MessageDelta(
        role: 'assistant',
        content: [TextContent(text: 'Hello')],
        isThought: false,
      );
      expect(update.role, 'assistant');
      expect(update.content.length, 1);
      expect(update.isThought, isFalse);
    });

    test('MessageDelta handles thought chunks', () {
      const update = MessageDelta(
        role: 'assistant',
        content: [TextContent(text: 'Thinking...')],
        isThought: true,
      );
      expect(update.isThought, isTrue);
    });

    test('PlanUpdate contains plan data', () {
      const update = PlanUpdate(
        Plan(
          entries: [
            PlanEntry(
              content: 'Step 1',
              priority: PlanEntryPriority.high,
              status: PlanEntryStatus.pending,
            ),
            PlanEntry(
              content: 'Step 2',
              priority: PlanEntryPriority.medium,
              status: PlanEntryStatus.inProgress,
            ),
          ],
        ),
      );
      expect(update.plan.entries.length, 2);
    });

    test('ToolCallUpdate contains tool data', () {
      const update = ToolCallUpdate(
        ToolCall(toolCallId: 'tool-123', status: ToolCallStatus.inProgress),
      );
      expect(update.toolCall.toolCallId, 'tool-123');
    });

    test('DiffUpdate contains diff data', () {
      const update = DiffUpdate(
        Diff(id: 'diff-123', status: DiffStatus.started, uri: '/test/file.txt'),
      );
      expect(update.diff.uri, '/test/file.txt');
    });

    test('TurnEnded contains stop reason', () {
      const update = TurnEnded(StopReason.endTurn);
      expect(update.stopReason, StopReason.endTurn);
    });
  });

  group('Workspace jail', () {
    test('normalizes paths correctly', () async {
      final jail = WorkspaceJail(workspaceRoot: '/home/user/project');

      // Test resolving relative path
      final resolved = await jail.resolveAndEnsureWithin('src/file.txt');
      expect(resolved, contains('src/file.txt'));
    });
  });

  group('Capabilities JSON structure', () {
    test('client capabilities have correct shape', () {
      const caps = AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      );
      final json = caps.toJson();
      expect(json['fs'], isNotNull);
      expect(json['fs']!['readTextFile'], isTrue);
      expect(json['fs']!['writeTextFile'], isTrue);
    });
  });
}
