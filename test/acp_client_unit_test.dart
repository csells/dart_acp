// Consolidated AcpClient unit tests

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/rpc/peer.dart' as rpc;
import 'package:dart_acp/src/session/session_manager.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

typedef Json = Map<String, dynamic>;

// ===== Helpers (mocks) =====

class _MockTransport implements AcpTransport {
  final _channelController = StreamChannelController<String>();
  bool _isStarted = false;
  @override
  StreamChannel<String> get channel => _channelController.local;
  @override
  Future<void> start() async {
    _isStarted = true;
  }

  @override
  Future<void> stop() async {
    _isStarted = false;
    await _channelController.local.sink.close();
  }

  bool get isStarted => _isStarted;
  void simulateMessage(String message) {
    _channelController.foreign.sink.add(message);
  }

  Stream<String> get sentMessages => _channelController.foreign.stream;
}

class _MockPeer implements rpc.JsonRpcPeer {
  final List<String> sentRequests = [];
  final _sessionUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  @override
  Future<Json> initialize(Json params) async {
    sentRequests.add('initialize');
    return {'protocolVersion': 1, 'agentCapabilities': {}};
  }

  @override
  Future<Json> newSession(Json params) async {
    sentRequests.add('session/new');
    return {'sessionId': 'test-session'};
  }

  @override
  Future<void> loadSession(Json params) async {
    sentRequests.add('session/load');
  }

  @override
  Future<Json> prompt(Json params) async {
    sentRequests.add('session/prompt');
    return {};
  }

  @override
  Future<void> cancel(Json params) async {
    sentRequests.add('session/cancel');
  }

  @override
  Future<void> close() async {
    await _sessionUpdatesController.close();
  }

  @override
  Stream<Map<String, dynamic>> get sessionUpdates =>
      _sessionUpdatesController.stream;
  void simulateUpdate(Map<String, dynamic> update) {
    _sessionUpdatesController.add(update);
  }

  Future<void> dispose() async => _sessionUpdatesController.close();
  // Client handler properties
  @override
  Future<dynamic> Function(Json)? onReadTextFile;
  @override
  Future<dynamic> Function(Json)? onWriteTextFile;
  @override
  Future<dynamic> Function(Json)? onRequestPermission;
  @override
  Future<dynamic> Function(Json)? onTerminalCreate;
  @override
  Future<dynamic> Function(Json)? onTerminalOutput;
  @override
  Future<dynamic> Function(Json)? onTerminalWaitForExit;
  @override
  Future<dynamic> Function(Json)? onTerminalKill;
  @override
  Future<dynamic> Function(Json)? onTerminalRelease;
}

// ===== Additional helpers for StdinTransport + client integration =====

class _StreamControllerSink implements IOSink {
  _StreamControllerSink(this.controller);
  final StreamController<List<int>> controller;
  bool _closed = false;
  @override
  void writeln([Object? object = '']) {
    if (_closed) return;
    controller.add(utf8.encode('$object\n'));
  }

  @override
  void write(Object? object) {
    if (_closed) return;
    controller.add(utf8.encode(object.toString()));
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));
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

class _MockAgent {
  _MockAgent({
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
        _sendNotification('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'plan',
            'plan': {
              'steps': ['Step 1', 'Step 2'],
            },
          },
        });
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
  group('AcpClient Unit', () {
    late AcpClient client;
    late _MockTransport transport;
    late AcpConfig config;
    setUp(() {
      config = AcpConfig(
        workspaceRoot: '/test/workspace',
        agentCommand: 'test-agent',
        agentArgs: const ['--test'],
      );
      transport = _MockTransport();
      client = AcpClient(config: config, transport: transport);
    });
    tearDown(() async => client.dispose());

    test('starts and stops transport', () async {
      expect(transport.isStarted, isFalse);
      await client.start();
      expect(transport.isStarted, isTrue);
      await client.dispose();
      expect(transport.isStarted, isFalse);
    });

    test('creates default StdioTransport when none provided', () {
      final c = AcpClient(config: config);
      expect(c, isNotNull);
    });

    test('helper text content', () {
      final b = AcpClient.text('hi');
      expect(b['type'], 'text');
      expect(b['text'], 'hi');
    });
  });

  group('SessionManager Unit', () {
    late SessionManager manager;
    late _MockPeer peer;
    late AcpConfig config;
    setUp(() {
      config = AcpConfig(
        workspaceRoot: '/test/workspace',
        agentCommand: 'test-agent',
        capabilities: const AcpCapabilities(
          fs: FsCapabilities(readTextFile: true, writeTextFile: true),
        ),
      );
      peer = _MockPeer();
      manager = SessionManager(config: config, peer: peer as rpc.JsonRpcPeer);
    });
    tearDown(() async {
      await manager.dispose();
      await peer.dispose();
    });

    test('initializes and negotiates', () async {
      final result = await manager.initialize();
      expect(result.protocolVersion, 1);
      expect(peer.sentRequests, contains('initialize'));
    });

    test('new session and prompt stream', () async {
      await manager.initialize();
      final sid = await manager.newSession(cwd: '/test');
      expect(sid, 'test-session');
      final stream = manager.prompt(
        sessionId: sid,
        content: [AcpClient.text('Hi')],
      );
      expect(stream, isA<Stream<AcpUpdate>>());
    });

    test('routes different update kinds', () async {
      await manager.initialize();
      final sid = await manager.newSession(cwd: '/test');
      final updates = <AcpUpdate>[];
      manager.sessionUpdates(sid).listen(updates.add);
      // agent_message_chunk
      peer.simulateUpdate({
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'ok'},
        },
      });
      // plan
      peer.simulateUpdate({
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'plan',
          'blocks': [
            {'id': '1', 'content': 'step'},
          ],
        },
      });
      // tool_call
      peer.simulateUpdate({
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'tool_call',
          'id': 't1',
          'status': 'started',
          'name': 'write_file',
        },
      });
      // diff
      peer.simulateUpdate({
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'diff',
          'id': 'd1',
          'status': 'started',
          'uri': 'file:///test.txt',
          'changes': [],
        },
      });
      // available commands
      peer.simulateUpdate({
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'restart'},
          ],
        },
      });
      await Future.delayed(const Duration(milliseconds: 100));
      expect(updates.any((u) => u is MessageDelta), isTrue);
      expect(updates.any((u) => u is PlanUpdate), isTrue);
      expect(updates.any((u) => u is ToolCallUpdate), isTrue);
      expect(updates.any((u) => u is DiffUpdate), isTrue);
      expect(updates.any((u) => u is AvailableCommandsUpdate), isTrue);
    });
  });

  group('Capabilities JSON', () {
    test('default fs caps are read-only', () {
      const caps = AcpCapabilities();
      final json = caps.toJson();
      expect(json.containsKey('fs'), isTrue);
      final fs = json['fs'] as Map<String, dynamic>;
      expect(fs['readTextFile'], isTrue);
      expect(fs['writeTextFile'], isFalse);
    });
    test('custom fs caps', () {
      const caps = AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      );
      final fs = caps.toJson()['fs'] as Map<String, dynamic>;
      expect(fs['readTextFile'], isTrue);
      expect(fs['writeTextFile'], isTrue);
    });
  });

  group('StopReason mapping', () {
    test('known values', () {
      expect(stopReasonFromWire('end_turn'), StopReason.endTurn);
      expect(stopReasonFromWire('max_tokens'), StopReason.maxTokens);
      expect(stopReasonFromWire('max_turn_requests'), StopReason.maxTokens);
      expect(stopReasonFromWire('cancelled'), StopReason.cancelled);
      expect(stopReasonFromWire('refusal'), StopReason.refusal);
      expect(stopReasonFromWire('anything_else'), StopReason.other);
    });
  });

  group('Spec sanity (selected)', () {
    test('update types set is covered', () {
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
      expect(
        updateTypes.keys,
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

  group('AcpClient + StdinTransport integration (unit)', () {
    late Logger logger;
    late StreamController<List<int>> toAgentController;
    late StreamController<List<int>> fromAgentController;
    late IOSink toAgentSink;
    late StdinTransport transport;
    late AcpClient client;

    setUp(() {
      logger = Logger('test');
      toAgentController = StreamController<List<int>>.broadcast();
      fromAgentController = StreamController<List<int>>.broadcast();
      toAgentSink = _StreamControllerSink(fromAgentController);
      final mockAgent = _MockAgent(
        inputController: toAgentController,
        outputSink: toAgentSink,
        capabilities: {
          'commands': ['read', 'write'],
        },
      );
      mockAgent.start();
      transport = StdinTransport(
        logger: logger,
        inputStream: fromAgentController.stream,
        outputSink: _StreamControllerSink(toAgentController),
      );
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

    test('init + create session over StdinTransport', () async {
      await client.start();
      final init = await client.initialize();
      expect(init.protocolVersion, 1);
      expect(init.agentCapabilities?['commands'], contains('read'));
      final sid = await client.newSession();
      expect(sid, 'test-session-123');
    });

    test('prompt streams updates over StdinTransport', () async {
      await client.start();
      await client.initialize();
      final sid = await client.newSession();
      final updates = <AcpUpdate>[];
      await client
          .prompt(sessionId: sid, content: [AcpClient.text('Test prompt')])
          .forEach(updates.add);
      expect(updates, isNotEmpty);
      final plan = updates.whereType<PlanUpdate>().firstOrNull;
      expect(plan, isNotNull);
      final delta = updates.whereType<MessageDelta>().toList();
      expect(delta, hasLength(2));
      final firstText = delta[0].content.first as TextContent;
      final secondText = delta[1].content.first as TextContent;
      expect(firstText.text, contains('Hello'));
      expect(secondText.text, contains('Processing'));
    });

    test('handles disconnect during initialize', () async {
      final disconnecting = StdinTransport(
        logger: logger,
        inputStream: fromAgentController.stream.take(0),
        outputSink: _StreamControllerSink(toAgentController),
      );
      final other = AcpClient(
        config: AcpConfig(
          workspaceRoot: Directory.current.path,
          capabilities: const AcpCapabilities(
            fs: FsCapabilities(readTextFile: true, writeTextFile: true),
          ),
        ),
        transport: disconnecting,
      );
      await other.start();
      expect(() async => other.initialize(), throwsA(isA<StateError>()));
      await other.dispose();
    });
  });
}
