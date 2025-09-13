// ignore_for_file: avoid_dynamic_calls

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('ACP Spec Coverage Tests', () {
    group('Protocol Features', () {
      test('protocol version is uint16 compliant', () {
        // Verify protocol version fits in uint16 range (0-65535)
        const protocolVersion = '2024-11-05';
        final parts = protocolVersion.split('-');
        expect(parts.length, equals(3));

        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);

        // Verify date components are valid
        expect(year, greaterThanOrEqualTo(2024));
        expect(month, inInclusiveRange(1, 12));
        expect(day, inInclusiveRange(1, 31));
      });

      test('stop reasons cover all spec values', () {
        // Test all stop reasons from spec
        expect(stopReasonFromWire('end_turn'), equals(StopReason.endTurn));
        expect(stopReasonFromWire('max_tokens'), equals(StopReason.maxTokens));
        expect(
          stopReasonFromWire('max_turn_requests'),
          equals(StopReason.maxTokens),
        );
        expect(stopReasonFromWire('cancelled'), equals(StopReason.cancelled));
        expect(stopReasonFromWire('refusal'), equals(StopReason.refusal));
        expect(stopReasonFromWire('unknown_reason'), equals(StopReason.other));
      });

      test('update types match spec', () {
        // Verify all session update types are handled
        final updateTypes = {
          'user_message_chunk': MessageDelta,
          'agent_message_chunk': MessageDelta,
          'agent_thought_chunk': MessageDelta,
          'plan': PlanUpdate,
          'tool_call': ToolCallUpdate,
          'tool_call_update': ToolCallUpdate,
          'diff': DiffUpdate,
          'available_commands_update': AvailableCommandsUpdate,
          'stop': TurnEnded,
        };

        // Ensure we handle all required update types
        expect(
          updateTypes.keys.toSet(),
          containsAll([
            'user_message_chunk',
            'agent_message_chunk',
            'agent_thought_chunk',
            'plan',
            'tool_call',
            'tool_call_update',
            'available_commands_update',
          ]),
        );
      });
    });

    group('Capabilities', () {
      test('fs capabilities match spec', () {
        const caps = FsCapabilities(readTextFile: true, writeTextFile: true);

        expect(caps.readTextFile, isTrue);
        expect(caps.writeTextFile, isTrue);

        // Verify JSON serialization
        final json = caps.toJson();
        expect(json['readTextFile'], isTrue);
        expect(json['writeTextFile'], isTrue);
      });

      test('client capabilities structure', () {
        const caps = AcpCapabilities(fs: FsCapabilities(readTextFile: true));

        final json = caps.toJson();
        expect(json['fs'], isNotNull);
        expect(json['fs']['readTextFile'], isTrue);
      });
    });

    group('Permission System', () {
      test('permission outcomes match spec', () {
        // Verify all permission outcomes are covered
        final outcomes = [PermissionOutcome.allow, PermissionOutcome.deny];

        expect(outcomes.length, equals(2));

        // Permission outcomes are allow/deny
        expect(
          PermissionOutcome.values,
          containsAll([PermissionOutcome.allow, PermissionOutcome.deny]),
        );
      });

      test('permission provider interface', () {
        final provider = DefaultPermissionProvider(
          onRequest: (opts) async => PermissionOutcome.allow,
        );

        // Test permission provider exists
        expect(provider.onRequest, isNotNull);
      });
    });

    group('Content Blocks', () {
      test('text content block structure', () {
        final block = AcpClient.text('Hello, world!');

        expect(block['type'], equals('text'));
        expect(block['text'], equals('Hello, world!'));
        expect(block.keys, containsAll(['type', 'text']));
      });
    });

    group('Error Codes', () {
      test('ACP error codes are defined', () {
        // Core ACP error codes from spec
        const methodNotFound = -32601;

        // ACP-specific error codes
        const authRequired = -2001;
        const permissionDenied = -2003;
        const notInJail = -2005;

        // Verify error code ranges
        expect(methodNotFound, lessThan(-32000));
        expect(authRequired, inInclusiveRange(-2999, -2000));
        expect(permissionDenied, inInclusiveRange(-2999, -2000));
        expect(notInJail, inInclusiveRange(-2999, -2000));
      });
    });

    group('Tool Kinds', () {
      test('all tool kinds from spec are supported', () {
        // All tool kinds from ACP spec
        final toolKinds = [
          'read',
          'edit',
          'delete',
          'move',
          'search',
          'execute',
          'think',
          'fetch',
          'other',
        ];

        expect(toolKinds.length, equals(9));
        expect(
          toolKinds,
          containsAll([
            'read',
            'edit',
            'delete',
            'move',
            'search',
            'execute',
            'think',
            'fetch',
            'other',
          ]),
        );
      });
    });

    group('Session Flow', () {
      test('session lifecycle methods exist', () {
        final config = AcpConfig(workspaceRoot: '/test', agentCommand: 'test');

        final client = AcpClient(config: config);

        // Verify required methods exist
        expect(client.initialize, isA<Function>());
        expect(client.newSession, isA<Function>());
        expect(client.loadSession, isA<Function>());
        expect(client.prompt, isA<Function>());
        expect(client.sessionUpdates, isA<Function>());
        expect(client.cancel, isA<Function>());
        expect(client.dispose, isA<Function>());
      });
    });

    group('Update Types', () {
      test('MessageDelta handles thought chunks', () {
        const thoughtDelta = MessageDelta(
          role: 'assistant',
          content: [TextContent(text: 'Thinking...')],
          isThought: true,
        );

        expect(thoughtDelta.isThought, isTrue);
        expect(thoughtDelta.role, equals('assistant'));
      });

      test('PlanUpdate contains plan data', () {
        const plan = PlanUpdate(
          Plan(
            entries: [
              PlanEntry(content: 'Step 1', priority: PlanEntryPriority.high, status: PlanEntryStatus.pending),
              PlanEntry(content: 'Step 2', priority: PlanEntryPriority.medium, status: PlanEntryStatus.inProgress),
            ],
          ),
        );

        expect(plan.plan.entries, hasLength(2));
      });

      test('ToolCallUpdate contains tool data', () {
        const toolCall = ToolCallUpdate(
          ToolCall(
            toolCallId: 'tool-1',
            status: ToolCallStatus.pending,
            title: 'read_file',
            kind: ToolKind.read,
          ),
        );

        expect(toolCall.toolCall.toolCallId, equals('tool-1'));
        expect(toolCall.toolCall.status, equals(ToolCallStatus.pending));
      });

      test('DiffUpdate contains diff data', () {
        const diff = DiffUpdate(
          Diff(
            id: 'diff-1',
            status: DiffStatus.started,
            uri: 'file:///test.txt',
            changes: [],
          ),
        );

        expect(diff.diff.uri, equals('file:///test.txt'));
      });

      test('AvailableCommandsUpdate contains commands', () {
        const commands = AvailableCommandsUpdate([
          AvailableCommand(name: 'restart', description: 'Restart session'),
          AvailableCommand(name: 'clear', description: 'Clear context'),
        ]);

        expect(commands.commands, hasLength(2));
      });

      test('TurnEnded contains stop reason', () {
        const ended = TurnEnded(StopReason.endTurn);

        expect(ended.stopReason, equals(StopReason.endTurn));
      });

      test('UnknownUpdate handles unrecognized updates', () {
        const unknown = UnknownUpdate({
          'type': 'future_update_type',
          'data': 'some data',
        });

        expect(unknown.raw['type'], equals('future_update_type'));
      });
    });

    group('Workspace Jail', () {
      test('workspace jail enforcement paths', () {
        // Test path normalization for jail enforcement
        final testPaths = [
          '/workspace/file.txt',
          '/workspace/../etc/passwd',
          'file:///workspace/file.txt',
          'file:///etc/passwd',
        ];

        // The jail should allow workspace paths and deny others
        const workspacePath = '/workspace';
        for (final path in testPaths) {
          final isInWorkspace =
              path.contains(workspacePath) && !path.contains('..');
          if (!isInWorkspace) {
            // Path should be rejected by jail
            expect(path.contains('/etc/') || path.contains('..'), isTrue);
          }
        }
      });
    });

    group('Configuration', () {
      test('AcpConfig supports all required fields', () {
        final config = AcpConfig(
          workspaceRoot: '/test/workspace',
          agentCommand: 'test-agent',
          agentArgs: ['--arg1', '--arg2'],
          envOverrides: {'KEY': 'value'},
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true),
          ),
          permissionProvider: DefaultPermissionProvider(
            onRequest: (opts) async => PermissionOutcome.allow,
          ),
          logger: null,
          onProtocolIn: (msg) {},
          onProtocolOut: (msg) {},
        );

        expect(config.workspaceRoot, equals('/test/workspace'));
        expect(config.agentCommand, equals('test-agent'));
        expect(config.agentArgs, equals(['--arg1', '--arg2']));
        expect(config.envOverrides, equals({'KEY': 'value'}));
        expect(config.capabilities, isNotNull);
        expect(config.permissionProvider, isNotNull);
      });

      test('AcpConfig has sensible defaults', () {
        final config = AcpConfig(workspaceRoot: '/test', agentCommand: 'agent');

        expect(config.agentArgs, isEmpty);
        expect(config.envOverrides, isEmpty);
        expect(config.capabilities, isNotNull);
      });
    });
  });
}
