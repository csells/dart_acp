import 'dart:async';

import 'capabilities.dart';
import 'config.dart';
import 'models/content_types.dart';
import 'models/terminal_events.dart';
import 'models/updates.dart';
import 'rpc/peer.dart';
import 'session/session_manager.dart';
import 'transport/stdio_transport.dart';
import 'transport/transport.dart';

/// High-level ACP client that manages transport, session lifecycle,
/// and streams updates from the agent.
class AcpClient {
  /// Create a client with the given configuration and optional transport.
  /// If no transport is provided, creates a StdioTransport that spawns
  /// the agent.
  AcpClient({required this.config, AcpTransport? transport}) {
    _transport =
        transport ??
        StdioTransport(
          cwd: config.workspaceRoot,
          command: config.agentCommand,
          args: config.agentArgs,
          envOverrides: config.envOverrides,
          logger: config.logger,
          onProtocolOut: config.onProtocolOut,
          onProtocolIn: config.onProtocolIn,
        );
  }

  /// Client configuration.
  final AcpConfig config;
  late final AcpTransport _transport;
  JsonRpcPeer? _peer;
  SessionManager? _sessionManager;

  /// Start the underlying transport and wire JSON-RPC peer.
  Future<void> start() async {
    await _transport.start();
    _peer = JsonRpcPeer(_transport.channel);
    _sessionManager = SessionManager(config: config, peer: _peer!);
  }

  /// Dispose the transport and release resources.
  Future<void> dispose() async {
    if (_sessionManager != null) {
      await _sessionManager!.dispose();
    }
    await _transport.stop();
  }

  /// Send `initialize` to negotiate protocol and capabilities.
  Future<InitializeResult> initialize({
    AcpCapabilities? capabilitiesOverride,
  }) async {
    _ensureReady();
    return _sessionManager!.initialize(
      capabilitiesOverride: capabilitiesOverride,
    );
  }

  /// Create a new ACP session; returns the session id.
  Future<String> newSession({String? cwd}) async {
    _ensureReady();
    return _sessionManager!.newSession(cwd: cwd);
  }

  /// Load an existing session (if the agent supports it).
  Future<void> loadSession({required String sessionId, String? cwd}) async {
    _ensureReady();
    return _sessionManager!.loadSession(sessionId: sessionId, cwd: cwd);
  }

  /// Send a prompt to the agent and stream `AcpUpdate`s.
  Stream<AcpUpdate> prompt({
    required String sessionId,
    required List<Map<String, dynamic>> content,
  }) {
    _ensureReady();
    return _sessionManager!.prompt(sessionId: sessionId, content: content);
  }

  /// Subscribe to the persistent session updates stream (includes replay).
  Stream<AcpUpdate> sessionUpdates(String sessionId) {
    _ensureReady();
    return _sessionManager!.sessionUpdates(sessionId);
  }

  /// Cancel the current turn for the given session.
  Future<void> cancel({required String sessionId}) async {
    _ensureReady();
    return _sessionManager!.cancel(sessionId: sessionId);
  }

  /// Terminal events stream for UI.
  Stream<TerminalEvent> get terminalEvents {
    _ensureReady();
    return _sessionManager!.terminalEvents;
  }

  /// Read current buffered output for a managed terminal.
  Future<String> terminalOutput(String terminalId) async {
    _ensureReady();
    return _sessionManager!.readTerminalOutput(terminalId);
  }

  /// Kill a managed terminal process.
  Future<void> terminalKill(String terminalId) async {
    _ensureReady();
    await _sessionManager!.killTerminal(terminalId);
  }

  /// Wait for a managed terminal process to exit.
  Future<int?> terminalWaitForExit(String terminalId) async {
    _ensureReady();
    return _sessionManager!.waitTerminal(terminalId);
  }

  /// Release resources for a managed terminal.
  Future<void> terminalRelease(String terminalId) async {
    _ensureReady();
    await _sessionManager!.releaseTerminal(terminalId);
  }

  void _ensureReady() {
    if (_peer == null || _sessionManager == null) {
      throw StateError('AcpClient not started. Call start() first.');
    }
  }

  /// Convenience helper to build a text content block.
  static Map<String, dynamic> text(String text) => {
    'type': 'text',
    'text': text,
  };

  /// Create a typed text content block.
  static TextContent textContent(String text) => TextContent(text: text);

  /// Create a typed image content block.
  static ImageContent imageContent(String mimeType, String data) =>
      ImageContent(mimeType: mimeType, data: data);

  /// Create a typed resource content block.
  static ResourceContent resourceContent(
    String uri, {
    String? title,
    String? mimeType,
  }) => ResourceContent(uri: uri, title: title, mimeType: mimeType);

  /// Create a typed resource link content block (preferred).
  static ResourceContent resourceLinkContent(
    String uri, {
    String? title,
    String? mimeType,
  }) => ResourceContent(uri: uri, title: title, mimeType: mimeType);

  // ===== Modes (extension) =====

  /// Get current/available modes for a session, if provided by the agent.
  ({String? currentModeId, List<({String id, String name})> availableModes})?
  sessionModes(String sessionId) {
    _ensureReady();
    return _sessionManager!.sessionModes(sessionId);
  }

  /// Set the session mode (extension). Returns true on success.
  Future<bool> setMode({
    required String sessionId,
    required String modeId,
  }) async {
    _ensureReady();
    return _sessionManager!.setSessionMode(
      sessionId: sessionId,
      modeId: modeId,
    );
  }
}
