import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Mock agent that responds to ACP protocol messages via stdin/stdout.
class MockAgent {
  MockAgent({
    required this.inputController,
    required this.outputSink,
    this.capabilities = const {},
  });
  final StreamController<List<int>> inputController;
  final IOSink outputSink;
  final Map<String, dynamic> capabilities;

  void start() {
    inputController.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final message = jsonDecode(line) as Map<String, dynamic>;
          _handleMessage(message);
        });
  }

  void _handleMessage(Map<String, dynamic> message) {
    final method = message['method'] as String?;
    final id = message['id'];

    if (method == null) return;

    switch (method) {
      case 'initialize':
        _sendResponse(id, {
          'protocolVersion': 1,
          'agentCapabilities': capabilities,
        });

      case 'session/new':
        _sendResponse(id, {
          'sessionId': 'test-session-123',
          'sessionUrl': 'https://example.com/session/test-session-123',
        });

      case 'session/prompt':
        final params = message['params'] as Map<String, dynamic>?;
        final sessionId = params?['sessionId'] as String?;

        // Send a plan update
        _sendNotification('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'plan',
            'plan': {
              'steps': ['Step 1', 'Step 2'],
            },
          },
        });

        // Send some chunks
        _sendNotification('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Hello from mock agent! '},
          },
        });
        _sendNotification('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Processing your request...'},
          },
        });

        // Complete the prompt
        _sendResponse(id, {'stopReason': 'completed'});

      default:
        _sendError(id, -32601, 'Method not found');
    }
  }

  void _sendResponse(dynamic id, Map<String, dynamic> result) {
    final response = {'jsonrpc': '2.0', 'id': id, 'result': result};
    outputSink.writeln(jsonEncode(response));
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final notification = {'jsonrpc': '2.0', 'method': method, 'params': params};
    outputSink.writeln(jsonEncode(notification));
  }

  void _sendError(dynamic id, int code, String message) {
    final error = {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    };
    outputSink.writeln(jsonEncode(error));
  }
}

void main() {
  group('StdinTransport Integration', () {
    late Logger logger;
    late StreamController<List<int>> toAgentController;
    late StreamController<List<int>> fromAgentController;
    late IOSink toAgentSink;
    late MockAgent mockAgent;
    late StdinTransport transport;
    late AcpClient client;

    setUp(() {
      logger = Logger('test');

      // Create bidirectional streams
      toAgentController = StreamController<List<int>>.broadcast();
      fromAgentController = StreamController<List<int>>.broadcast();

      // Create mock agent with reverse connections
      toAgentSink = _StreamControllerSink(fromAgentController);
      mockAgent = MockAgent(
        inputController: toAgentController,
        outputSink: toAgentSink,
        capabilities: {
          'commands': ['read', 'write'],
        },
      );
      mockAgent.start();

      // Create transport with connections to agent
      transport = StdinTransport(
        logger: logger,
        inputStream: fromAgentController.stream,
        outputSink: _StreamControllerSink(toAgentController),
      );

      // Create client
      client = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: true),
          ),
        ),
        transport: transport,
      );
    });

    tearDown(() async {
      await client.dispose();
      await toAgentController.close();
      await fromAgentController.close();
      await toAgentSink.close();
    });

    test('can initialize and create session with stdin transport', () async {
      await client.start();

      final initResult = await client.initialize();
      expect(initResult.protocolVersion, equals(1));
      expect(initResult.agentCapabilities?['commands'], contains('read'));

      final sessionId = await client.newSession();
      expect(sessionId, equals('test-session-123'));
    });

    test('can send prompt and receive updates via stdin transport', () async {
      await client.start();
      await client.initialize();
      final sessionId = await client.newSession();

      final updates = <AcpUpdate>[];
      await client
          .prompt(
            sessionId: sessionId,
            content: [AcpClient.text('Test prompt')],
          )
          .forEach(updates.add);

      // Verify we received the expected updates
      expect(updates, isNotEmpty);

      // Check for plan update
      final planUpdate = updates.whereType<PlanUpdate>().firstOrNull;
      expect(planUpdate, isNotNull);
      final planData = planUpdate!.plan['plan'] as Map<String, dynamic>?;
      expect(planData?['steps'], equals(['Step 1', 'Step 2']));

      // Check for message delta updates
      final deltaUpdates = updates.whereType<MessageDelta>().toList();
      expect(deltaUpdates, hasLength(2));

      // Extract text from content blocks
      final firstContent = deltaUpdates[0].content.first;
      final secondContent = deltaUpdates[1].content.first;
      expect(firstContent['text'], equals('Hello from mock agent! '));
      expect(secondContent['text'], equals('Processing your request...'));
    });

    test('handles disconnect during initialization', () async {
      // Create a client that will have its transport cut off
      final disconnectingTransport = StdinTransport(
        logger: logger,
        inputStream: fromAgentController.stream.take(
          0,
        ), // Empty stream, immediately done
        outputSink: _StreamControllerSink(toAgentController),
      );

      final disconnectingClient = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: true),
          ),
        ),
        transport: disconnectingTransport,
      );

      await disconnectingClient.start();

      // Initialize should fail gracefully due to no response
      expect(
        () async => disconnectingClient.initialize(),
        throwsA(isA<StateError>()),
      );

      await disconnectingClient.dispose();
    });
  });
}

/// Helper class to adapt StreamController to IOSink interface
class _StreamControllerSink implements IOSink {
  _StreamControllerSink(this.controller);
  final StreamController<List<int>> controller;
  bool _closed = false;

  @override
  void writeln([Object? object = '']) {
    if (_closed) return;
    final data = utf8.encode('$object\n');
    controller.add(data);
  }

  @override
  void write(Object? object) {
    if (_closed) return;
    final data = utf8.encode(object.toString());
    controller.add(data);
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    if (_closed) return;
    controller.add([charCode]);
  }

  @override
  void add(List<int> data) {
    if (_closed) return;
    controller.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    controller.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) => controller.addStream(stream);

  @override
  Future close() async {
    _closed = true;
    await controller.close();
  }

  @override
  Future get done => controller.done;

  @override
  Future flush() async {}

  @override
  Encoding encoding = utf8;
}
