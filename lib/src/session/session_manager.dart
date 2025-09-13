import 'dart:async';

import 'package:logging/logging.dart';

import '../capabilities.dart';
import '../config.dart';
import '../models/terminal_events.dart';
import '../models/tool_types.dart';
import '../models/types.dart';
import '../models/updates.dart';
import '../providers/permission_provider.dart';
import '../providers/terminal_provider.dart';
import '../rpc/peer.dart';

/// Alias for a JSON map used in requests/responses.
typedef Json = Map<String, dynamic>;

/// Result returned by initialize containing negotiated protocol and caps.
class InitializeResult {
  /// Create an [InitializeResult].
  InitializeResult({
    required this.protocolVersion,
    required this.agentCapabilities,
    required this.authMethods,
  });

  /// Negotiated protocol version.
  final int protocolVersion;

  /// Agent capabilities (if provided).
  final Map<String, dynamic>? agentCapabilities;

  /// Supported auth methods (if any).
  final List<Map<String, dynamic>>? authMethods;
}

/// Orchestrates ACP lifecycle and routes updates/tool/terminal handlers.
class SessionManager {
  /// Create a [SessionManager] with [config] and [peer].
  SessionManager({required this.config, required this.peer})
    : _log = config.logger {
    // Wire client-side handlers
    peer.onReadTextFile = _onReadTextFile;
    peer.onWriteTextFile = _onWriteTextFile;
    peer.onRequestPermission = _onRequestPermission;
    peer.onTerminalCreate = _onTerminalCreate;
    peer.onTerminalOutput = _onTerminalOutput;
    peer.onTerminalWaitForExit = _onTerminalWaitForExit;
    peer.onTerminalKill = _onTerminalKill;
    peer.onTerminalRelease = _onTerminalRelease;

    peer.sessionUpdates.listen(_routeSessionUpdate);
  }

  /// Client configuration.
  final AcpConfig config;

  /// JSON-RPC peer used for requests and client callbacks.
  final JsonRpcPeer peer;
  final Logger _log;

  final Map<String, StreamController<AcpUpdate>> _sessionStreams = {};
  final Map<String, List<AcpUpdate>> _replayBuffers = {};
  final Set<String> _cancellingSessions = <String>{};
  final StreamController<TerminalEvent> _terminalEvents =
      StreamController<TerminalEvent>.broadcast();
  // Track tool calls by session and tool call ID for proper merging
  final Map<String, Map<String, ToolCall>> _toolCalls = {};

  /// Dispose all internal resources and close streams.
  Future<void> dispose() async {
    await _terminalEvents.close();
    for (final c in _sessionStreams.values) {
      await c.close();
    }
    _sessionStreams.clear();
    _replayBuffers.clear();
    _toolCalls.clear();
  }

  /// Send `initialize` with capabilities and return negotiated result.
  Future<InitializeResult> initialize({
    AcpCapabilities? capabilitiesOverride,
  }) async {
    final caps = capabilitiesOverride ?? config.capabilities;
    // Build client capabilities payload from standard caps,
    // and include non-standard terminal capability when supported.
    final clientCaps = Map<String, dynamic>.from(caps.toJson());
    if (config.terminalProvider != null) {
      clientCaps['terminal'] = true; // Non-standard: used by some adapters
    }
    final payload = {'protocolVersion': 1, 'clientCapabilities': clientCaps};
    final resp = await peer.initialize(payload);
    final negotiated = (resp['protocolVersion'] as num?)?.toInt() ?? 0;
    if (negotiated < AcpConfig.minimumProtocolVersion) {
      throw StateError(
        'Unsupported ACP protocol version: $negotiated. '
        'Minimum required: ${AcpConfig.minimumProtocolVersion}.',
      );
    }
    return InitializeResult(
      protocolVersion: (resp['protocolVersion'] as num?)?.toInt() ?? 1,
      agentCapabilities: resp['agentCapabilities'] as Map<String, dynamic>?,
      authMethods: (resp['authMethods'] as List?)?.cast<Map<String, dynamic>>(),
    );
  }

  /// Create a new session and return its id.
  Future<String> newSession({String? cwd}) async {
    final resp = await peer.newSession({
      'cwd': cwd ?? config.workspaceRoot,
      'mcpServers': config.mcpServers,
    });
    final id = resp['sessionId'] as String;
    _sessionStreams.putIfAbsent(id, StreamController<AcpUpdate>.broadcast);
    _replayBuffers.putIfAbsent(id, () => <AcpUpdate>[]);
    // Capture any modes info from session/new
    final modes = resp['modes'];
    if (modes is Map<String, dynamic>) {
      final current = modes['currentModeId'] as String?;
      final avail =
          (modes['availableModes'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      _sessionModes[id] = (
        currentModeId: current,
        availableModes: avail
            .map(
              (m) => (
                id: (m['id'] as String?) ?? '',
                name: (m['name'] as String?) ?? '',
              ),
            )
            .toList(),
      );
    }
    return id;
  }

  /// Load a previous session and replay updates to the client.
  Future<void> loadSession({required String sessionId, String? cwd}) async {
    _sessionStreams.putIfAbsent(
      sessionId,
      StreamController<AcpUpdate>.broadcast,
    );
    _replayBuffers.putIfAbsent(sessionId, () => <AcpUpdate>[]);
    await peer.loadSession({
      'sessionId': sessionId,
      'cwd': cwd ?? config.workspaceRoot,
      'mcpServers': config.mcpServers,
    });
  }

  /// Send a prompt and stream typed updates for this turn only.
  /// The returned stream automatically closes after [TurnEnded].
  Stream<AcpUpdate> prompt({
    required String sessionId,
    required List<Map<String, dynamic>> content,
  }) {
    if (!_sessionStreams.containsKey(sessionId)) {
      // Unknown session; throw error
      throw ArgumentError('Invalid session ID: $sessionId');
    }

    unawaited(() async {
      try {
        final resp = await peer.prompt({
          'sessionId': sessionId,
          'prompt': content,
        });
        final stop = stopReasonFromWire(
          (resp['stopReason'] as String?) ?? 'other',
        );
        final turnEnded = TurnEnded(stop);
        _replayBuffers[sessionId]?.add(turnEnded);
        _sessionStreams[sessionId]!.add(turnEnded);
        if (stop == StopReason.cancelled) {
          _cancellingSessions.remove(sessionId);
        }
      } on Object catch (e, st) {
        _log.warning('prompt error: $e');
        // Surface error to listeners so UIs can react
        _sessionStreams[sessionId]!.addError(e, st);
      } finally {}
    }());

    final base = _sessionStreams[sessionId]!.stream;
    return Stream<AcpUpdate>.multi((emitter) {
      late final StreamSubscription sub;
      sub = base.listen(
        (u) {
          emitter.add(u);
          if (u is TurnEnded) {
            unawaited(sub.cancel());
            scheduleMicrotask(emitter.close);
          }
        },
        onError: (e, st) => emitter.addError(e, st),
        onDone: () => scheduleMicrotask(emitter.close),
      );
    });
  }

  /// Cancel the current turn for a session.
  Future<void> cancel({required String sessionId}) async {
    _cancellingSessions.add(sessionId);
    await peer.cancel({'sessionId': sessionId});
  }

  /// Stream of terminal lifecycle events.
  Stream<TerminalEvent> get terminalEvents => _terminalEvents.stream;

  // Expose a persistent session updates stream (includes replay from
  // session/load and updates across multiple prompts)
  /// Persistent session update stream, including replay.
  Stream<AcpUpdate> sessionUpdates(String sessionId) async* {
    final buffer = List<AcpUpdate>.from(_replayBuffers[sessionId] ?? const []);
    for (final u in buffer) {
      yield u;
    }
    yield* _sessionStreams
        .putIfAbsent(sessionId, StreamController<AcpUpdate>.broadcast)
        .stream;
  }

  void _routeSessionUpdate(Json json) {
    final sessionId = json['sessionId'] as String?;
    final update = json['update'] as Map<String, dynamic>?;
    if (sessionId == null || update == null) return;
    // Ensure structures exist so we don't drop early updates (e.g., commands
    // emitted immediately after session/new).
    _sessionStreams.putIfAbsent(
      sessionId,
      StreamController<AcpUpdate>.broadcast,
    );
    _replayBuffers.putIfAbsent(sessionId, () => <AcpUpdate>[]);

    final kind = update['sessionUpdate'];
    if (kind == 'available_commands_update') {
      final cmds =
          (update['availableCommands'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      final u = AvailableCommandsUpdate.fromRaw(cmds);
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else if (kind == 'plan') {
      final u = PlanUpdate.fromJson(update);
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else if (kind == 'tool_call' || kind == 'tool_call_update') {
      // Get tool call ID from the update
      final toolCallId =
          update['toolCallId'] as String? ?? update['id'] as String? ?? '';

      // Initialize tool calls map for session if needed
      _toolCalls.putIfAbsent(sessionId, () => {});

      final ToolCall toolCall;
      if (kind == 'tool_call') {
        // New tool call - create and store it
        toolCall = ToolCall.fromJson(update);
        _toolCalls[sessionId]![toolCallId] = toolCall;
      } else {
        // tool_call_update - merge with existing
        final existing = _toolCalls[sessionId]![toolCallId];
        if (existing != null) {
          // Merge update fields into existing tool call
          toolCall = existing.merge(update);
          _toolCalls[sessionId]![toolCallId] = toolCall;
        } else {
          // No existing tool call found, create new one from update
          toolCall = ToolCall.fromJson(update);
          _toolCalls[sessionId]![toolCallId] = toolCall;
        }
      }

      final u = ToolCallUpdate(toolCall);
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else if (kind == 'user_message_chunk' ||
        kind == 'agent_message_chunk' ||
        kind == 'agent_thought_chunk') {
      final content = update['content'];
      final blocks = content is Map<String, dynamic>
          ? <Map<String, dynamic>>[content]
          : (content as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final role = kind == 'user_message_chunk' ? 'user' : 'assistant';
      final u = MessageDelta.fromRaw(
        role: role,
        rawContent: blocks,
        isThought: kind == 'agent_thought_chunk',
      );
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else if (kind == 'diff') {
      final u = DiffUpdate.fromJson(update);
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else if (kind == 'current_mode_update') {
      final currentModeId = update['currentModeId'] as String?;
      if (currentModeId != null) {
        final existing = _sessionModes[sessionId];
        if (existing != null) {
          _sessionModes[sessionId] = (
            currentModeId: currentModeId,
            availableModes: existing.availableModes,
          );
        } else {
          _sessionModes[sessionId] = (
            currentModeId: currentModeId,
            availableModes: const <({String id, String name})>[],
          );
        }
      }
      final u = ModeUpdate(currentModeId ?? '');
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    } else {
      final u = UnknownUpdate(json);
      _replayBuffers[sessionId]!.add(u);
      _sessionStreams[sessionId]!.add(u);
    }
  }

  // ===== Modes support (extension) =====
  // Store current mode and available modes per session when provided.
  final Map<
    String,
    ({String? currentModeId, List<({String id, String name})> availableModes})
  >
  _sessionModes = {};

  /// Returns currently known modes info for the session, if any.
  ({String? currentModeId, List<({String id, String name})> availableModes})?
  sessionModes(String sessionId) => _sessionModes[sessionId];

  /// Set the session mode (extension). Returns true if RPC succeeds.
  Future<bool> setSessionMode({
    required String sessionId,
    required String modeId,
  }) async {
    try {
      await peer.setSessionMode({'sessionId': sessionId, 'modeId': modeId});
      return true;
    } on Exception catch (_) {
      return false;
    }
  }

  // ===== Agent -> Client handlers =====
  Future<Json> _onReadTextFile(Json req) async {
    final path = req['path'] as String;
    final line = (req['line'] as num?)?.toInt();
    final limit = (req['limit'] as num?)?.toInt();
    _log.fine('fs/read_text_file <- path=$path line=$line limit=$limit');
    try {
      final content = await config.fsProvider.readTextFile(
        path,
        line: line,
        limit: limit,
      );
      _log.fine('fs/read_text_file -> ok path=$path bytes=${content.length}');
      return {'content': content};
    } catch (e) {
      _log.warning('fs/read_text_file -> error path=$path: $e');
      rethrow;
    }
  }

  Future<Json?> _onWriteTextFile(Json req) async {
    final path = req['path'] as String;
    final content = req['content'] as String? ?? '';
    _log.fine('fs/write_text_file <- path=$path bytes=${content.length}');
    try {
      await config.fsProvider.writeTextFile(path, content);
      _log.fine('fs/write_text_file -> ok path=$path');
      return null; // per schema null
    } catch (e) {
      _log.warning('fs/write_text_file -> error path=$path: $e');
      rethrow;
    }
  }

  Future<Json> _onRequestPermission(Json req) async {
    final reqSessionId = req['sessionId'] as String? ?? '';
    if (_cancellingSessions.contains(reqSessionId)) {
      return {
        'outcome': {'outcome': 'cancelled'},
      };
    }
    final options =
        (req['options'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final toolCall = req['toolCall'] as Map<String, dynamic>?;
    final toolName = (toolCall?['title'] as String?) ?? 'operation';
    final toolKind = toolCall?['kind'] as String?;
    final outcome = await config.permissionProvider.request(
      PermissionOptions(
        title: toolName,
        rationale: 'Requested by agent',
        options: options.map((e) => (e['name'] as String?) ?? '').toList(),
        sessionId: req['sessionId'] as String? ?? '',
        toolName: toolName,
        toolKind: toolKind,
      ),
    );

    if (outcome == PermissionOutcome.cancelled) {
      return {
        'outcome': {'outcome': 'cancelled'},
      };
    }

    String? chosenKind;
    if (outcome == PermissionOutcome.allow) {
      chosenKind = 'allow_once';
    } else if (outcome == PermissionOutcome.deny) {
      chosenKind = 'reject_once';
    }
    // pick matching optionId
    var optionId =
        options.cast<Map<String, dynamic>?>().firstWhere(
              (o) => o != null && o['kind'] == chosenKind,
              orElse: () => null,
            )?['optionId']
            as String?;
    optionId ??= options.isNotEmpty
        ? (options.first['optionId'] as String?)
        : null;
    if (optionId == null) {
      // Fallback cancelled if options empty
      return {
        'outcome': {'outcome': 'cancelled'},
      };
    }
    return {
      'outcome': {'outcome': 'selected', 'optionId': optionId},
    };
  }

  final Map<String, TerminalProcessHandle> _terminals = {};

  Future<Json> _onTerminalCreate(Json req) async {
    final provider = config.terminalProvider;
    if (provider == null) {
      throw Exception('Terminal not supported');
    }
    final cmd = req['command'] as String;
    final args = (req['args'] as List?)?.cast<String>() ?? const [];
    final sessionId = req['sessionId'] as String? ?? '';
    final cwd = req['cwd'] as String?;
    final envList = (req['env'] as List?)?.cast<Map<String, dynamic>>();
    final env = <String, String>{
      if (envList != null)
        for (final e in envList) (e['name'] as String): (e['value'] as String),
    };
    final handle = await provider.create(
      sessionId: sessionId,
      command: cmd,
      args: args,
      cwd: cwd,
      env: env.isEmpty ? null : env,
    );
    _terminals[handle.terminalId] = handle;
    _terminalEvents.add(
      TerminalCreated(
        terminalId: handle.terminalId,
        sessionId: sessionId,
        command: cmd,
        args: args,
        cwd: cwd,
      ),
    );
    return {'terminalId': handle.terminalId};
  }

  Future<Json> _onTerminalOutput(Json req) async {
    final provider = config.terminalProvider;
    if (provider == null) {
      return {'output': '', 'truncated': false, 'exitStatus': null};
    }
    final termId = req['terminalId'] as String;
    final handle = _terminals[termId];
    if (handle == null) {
      return {'output': '', 'truncated': false, 'exitStatus': null};
    }
    final output = await provider.currentOutput(handle);
    int? exitCode;
    try {
      exitCode = await handle.process.exitCode.timeout(
        const Duration(milliseconds: 1),
      );
    } on TimeoutException {
      exitCode = null;
    }
    _terminalEvents.add(
      TerminalOutputEvent(
        terminalId: termId,
        output: output,
        truncated: false,
        exitCode: exitCode,
      ),
    );
    return {
      'output': output,
      'truncated': false,
      'exitStatus': exitCode == null ? null : {'code': exitCode},
    };
  }

  Future<Json> _onTerminalWaitForExit(Json req) async {
    final provider = config.terminalProvider;
    if (provider == null) {
      return {
        'output': '',
        'truncated': false,
        'exitStatus': {'code': 0},
      };
    }
    final termId = req['terminalId'] as String;
    final handle = _terminals[termId];
    if (handle == null) {
      return {
        'output': '',
        'truncated': false,
        'exitStatus': {'code': 0},
      };
    }
    final code = await provider.waitForExit(handle);
    _terminalEvents.add(TerminalExited(terminalId: termId, code: code));
    return {
      'output': handle.currentOutput(),
      'truncated': false,
      'exitStatus': {'code': code},
    };
  }

  Future<Json?> _onTerminalKill(Json req) async {
    final provider = config.terminalProvider;
    final termId = req['terminalId'] as String;
    final handle = _terminals[termId];
    if (provider != null && handle != null) {
      await provider.kill(handle);
    }
    return null;
  }

  Future<Json?> _onTerminalRelease(Json req) async {
    final provider = config.terminalProvider;
    final termId = req['terminalId'] as String;
    final handle = _terminals.remove(termId);
    if (provider != null && handle != null) {
      await provider.release(handle);
    }
    _terminalEvents.add(TerminalReleased(terminalId: termId));
    return null;
  }

  // UI helpers to interact with terminals
  /// Read buffered output for a managed terminal.
  Future<String> readTerminalOutput(String terminalId) async {
    final handle = _terminals[terminalId];
    if (handle == null) return '';
    return handle.currentOutput();
  }

  /// Kill a managed terminal process.
  Future<void> killTerminal(String terminalId) async {
    final provider = config.terminalProvider;
    final handle = _terminals[terminalId];
    if (provider != null && handle != null) {
      await provider.kill(handle);
    }
  }

  /// Wait for a terminal to exit and return its code, or null if unavailable.
  Future<int?> waitTerminal(String terminalId) async {
    final provider = config.terminalProvider;
    final handle = _terminals[terminalId];
    if (provider != null && handle != null) {
      final code = await provider.waitForExit(handle);
      return code;
    }
    return null;
  }

  /// Release resources for a managed terminal.
  Future<void> releaseTerminal(String terminalId) async {
    final provider = config.terminalProvider;
    final handle = _terminals.remove(terminalId);
    if (provider != null && handle != null) {
      await provider.release(handle);
    }
  }
}
