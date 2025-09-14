import 'dart:async';

import 'capabilities.dart';
import 'config.dart';
import 'content/content_builder.dart';
import 'models/terminal_events.dart';
import 'models/updates.dart';
import 'rpc/peer.dart';
import 'session/session_manager.dart';
import 'transport/stdio_transport.dart';
import 'transport/transport.dart';

/// High-level ACP client that manages transport, session lifecycle,
/// and streams updates from the agent.
class AcpClient {
  /// Private constructor - use [AcpClient.start] to create instances.
  AcpClient._({required this.config, required AcpTransport transport})
    : _transport = transport;

  /// Create and start a client with the given configuration.
  /// If no transport is provided, creates a StdioTransport that spawns
  /// the agent.
  static Future<AcpClient> start({
    required AcpConfig config,
    AcpTransport? transport,
  }) async {
    final actualTransport =
        transport ??
        StdioTransport(
          command: config.agentCommand,
          args: config.agentArgs,
          envOverrides: config.envOverrides,
          logger: config.logger,
          onProtocolOut: config.onProtocolOut,
          onProtocolIn: config.onProtocolIn,
        );

    await actualTransport.start();

    final client = AcpClient._(config: config, transport: actualTransport);
    client._peer = JsonRpcPeer(actualTransport.channel);
    client._sessionManager = SessionManager(config: config, peer: client._peer);

    return client;
  }

  /// Client configuration.
  final AcpConfig config;
  final AcpTransport _transport;
  late final JsonRpcPeer _peer;
  late final SessionManager _sessionManager;

  /// Dispose the transport and release resources.
  Future<void> dispose() async {
    // Close JSON-RPC peer first to stop inbound traffic cleanly,
    // then dispose session resources and finally stop the transport.
    try {
      await _peer.close();
    } on Exception catch (_) {
      // Ignore close errors during shutdown
    }
    await _sessionManager.dispose();
    await _transport.stop();
  }

  /// Send `initialize` to negotiate protocol and capabilities.
  Future<InitializeResult> initialize({
    AcpCapabilities? capabilitiesOverride,
  }) async =>
      _sessionManager.initialize(capabilitiesOverride: capabilitiesOverride);

  /// Create a new ACP session; returns the session id.
  Future<String> newSession(String workspaceRoot) async =>
      _sessionManager.newSession(workspaceRoot: workspaceRoot);

  /// Load an existing session (if the agent supports it).
  Future<void> loadSession({
    required String sessionId,
    required String workspaceRoot,
  }) async => _sessionManager.loadSession(
    sessionId: sessionId,
    workspaceRoot: workspaceRoot,
  );

  /// Send a prompt to the agent and stream `AcpUpdate`s.
  ///
  /// The [content] string can include @-mentions for files and URLs:
  /// - `@file.txt` or `@"path with spaces/file.txt"` for local files
  /// - `@https://example.com/resource` for URLs
  /// - `@~/Documents/file.txt` for home directory paths
  Stream<AcpUpdate> prompt({
    required String sessionId,
    required String content,
  }) {
    final workspaceRoot = _sessionManager.getWorkspaceRoot(sessionId);
    final contentBlocks = ContentBuilder.buildFromPrompt(
      content,
      workspaceRoot: workspaceRoot,
    );
    return _sessionManager.prompt(sessionId: sessionId, content: contentBlocks);
  }

  /// Subscribe to the persistent session updates stream (includes replay).
  Stream<AcpUpdate> sessionUpdates(String sessionId) =>
      _sessionManager.sessionUpdates(sessionId);

  /// Cancel the current turn for the given session.
  Future<void> cancel({required String sessionId}) async =>
      _sessionManager.cancel(sessionId: sessionId);

  /// Terminal events stream for UI.
  Stream<TerminalEvent> get terminalEvents => _sessionManager.terminalEvents;

  /// Read current buffered output for a managed terminal.
  Future<String> terminalOutput(String terminalId) async =>
      _sessionManager.readTerminalOutput(terminalId);

  /// Kill a managed terminal process.
  Future<void> terminalKill(String terminalId) async {
    await _sessionManager.killTerminal(terminalId);
  }

  /// Wait for a managed terminal process to exit.
  Future<int?> terminalWaitForExit(String terminalId) async =>
      _sessionManager.waitTerminal(terminalId);

  /// Release resources for a managed terminal.
  Future<void> terminalRelease(String terminalId) async {
    await _sessionManager.releaseTerminal(terminalId);
  }

  // ===== Modes (extension) =====

  /// Get current/available modes for a session, if provided by the agent.
  ({String? currentModeId, List<({String id, String name})> availableModes})?
  sessionModes(String sessionId) => _sessionManager.sessionModes(sessionId);

  /// Set the session mode (extension). Returns true on success.
  Future<bool> setMode({
    required String sessionId,
    required String modeId,
  }) async =>
      _sessionManager.setSessionMode(sessionId: sessionId, modeId: modeId);

  /// Send an arbitrary JSON-RPC request (advanced; for compliance harness).
  Future<Map<String, dynamic>> sendRaw(
    String method,
    Map<String, dynamic> params,
  ) async => _peer.sendRaw(method, params);
}
