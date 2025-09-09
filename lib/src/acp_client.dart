import 'dart:async';

import 'capabilities.dart';
import 'config.dart';
import 'models/updates.dart';
import 'rpc/peer.dart';
import 'models/terminal_events.dart';
import 'session/session_manager.dart';
import 'transport/stdio_transport.dart';
import 'transport/transport.dart';

class AcpClient {
  final AcpConfig config;
  late final AcpTransport _transport;
  JsonRpcPeer? _peer;
  SessionManager? _sessionManager;

  AcpClient({required this.config}) {
    _transport = StdioTransport(
      cwd: config.workspaceRoot,
      command: config.agentCommand,
      args: config.agentArgs,
      envOverrides: config.envOverrides,
      logger: config.logger,
      onProtocolOut: config.onProtocolOut,
      onProtocolIn: config.onProtocolIn,
    );
  }

  Future<void> start() async {
    await _transport.start();
    _peer = JsonRpcPeer(_transport.channel);
    _sessionManager = SessionManager(config: config, peer: _peer!);
  }

  Future<void> dispose() async {
    await _transport.stop();
  }

  Future<InitializeResult> initialize({
    AcpCapabilities? capabilitiesOverride,
  }) async {
    _ensureReady();
    return await _sessionManager!.initialize(
      capabilitiesOverride: capabilitiesOverride,
    );
  }

  Future<String> newSession({String? cwd}) async {
    _ensureReady();
    return await _sessionManager!.newSession(cwd: cwd);
  }

  Stream<AcpUpdate> prompt({
    required String sessionId,
    required List<Map<String, dynamic>> content,
  }) {
    _ensureReady();
    return _sessionManager!.prompt(sessionId: sessionId, content: content);
  }

  Future<void> cancel({required String sessionId}) async {
    _ensureReady();
    return await _sessionManager!.cancel(sessionId: sessionId);
  }

  // Terminal events stream for UI
  Stream<TerminalEvent> get terminalEvents {
    _ensureReady();
    return _sessionManager!.terminalEvents;
  }

  // Terminal controls (UI helpers)
  Future<String> terminalOutput(String terminalId) async {
    _ensureReady();
    return _sessionManager!.readTerminalOutput(terminalId);
  }

  Future<void> terminalKill(String terminalId) async {
    _ensureReady();
    await _sessionManager!.killTerminal(terminalId);
  }

  Future<int?> terminalWaitForExit(String terminalId) async {
    _ensureReady();
    return _sessionManager!.waitTerminal(terminalId);
  }

  Future<void> terminalRelease(String terminalId) async {
    _ensureReady();
    await _sessionManager!.releaseTerminal(terminalId);
  }

  void _ensureReady() {
    if (_peer == null || _sessionManager == null) {
      throw StateError('AcpClient not started. Call start() first.');
    }
  }

  // Convenience helper to build a text content block
  static Map<String, dynamic> text(String text) => {
    'type': 'text',
    'text': text,
  };
}
