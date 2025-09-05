import 'dart:async';
import 'package:logging/logging.dart';

import '../capabilities.dart';
import '../config.dart';
import '../models/types.dart';
import '../models/updates.dart';
import '../providers/permission_provider.dart';
import '../providers/terminal_provider.dart';
import '../rpc/peer.dart';

typedef Json = Map<String, dynamic>;

class InitializeResult {
  final int protocolVersion;
  final Map<String, dynamic>? agentCapabilities;
  final List<Map<String, dynamic>>? authMethods;
  InitializeResult({
    required this.protocolVersion,
    required this.agentCapabilities,
    required this.authMethods,
  });
}

class SessionManager {
  final AcpConfig config;
  final JsonRpcPeer peer;
  final Logger _log;

  final Map<String, StreamController<AcpUpdate>> _sessionStreams = {};

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

  Future<InitializeResult> initialize({
    AcpCapabilities? capabilitiesOverride,
  }) async {
    final caps = (capabilitiesOverride ?? config.capabilities);
    final payload = {
      'protocolVersion': 1,
      if (caps.toJson().isNotEmpty) 'clientCapabilities': caps.toJson(),
    };
    final resp = await peer.initialize(payload);
    return InitializeResult(
      protocolVersion: (resp['protocolVersion'] as num?)?.toInt() ?? 1,
      agentCapabilities: resp['agentCapabilities'] as Map<String, dynamic>?,
      authMethods: (resp['authMethods'] as List?)?.cast<Map<String, dynamic>>(),
    );
  }

  Future<String> newSession({String? cwd}) async {
    final resp = await peer.newSession({
      'cwd': cwd ?? config.workspaceRoot,
      'mcpServers': <Map<String, dynamic>>[],
    });
    return resp['sessionId'] as String;
  }

  Stream<AcpUpdate> prompt({
    required String sessionId,
    required List<Map<String, dynamic>> content,
  }) {
    final controller = StreamController<AcpUpdate>(
      onCancel: () {
        _sessionStreams.remove(sessionId);
      },
    );
    _sessionStreams[sessionId] = controller;

    () async {
      try {
        final resp = await peer.prompt({
          'sessionId': sessionId,
          'prompt': content,
        });
        final stop = stopReasonFromWire(
          (resp['stopReason'] as String?) ?? 'other',
        );
        controller.add(TurnEnded(stop));
      } catch (e) {
        _log.warning('prompt error: $e');
      } finally {
        await controller.close();
        _sessionStreams.remove(sessionId);
      }
    }();

    return controller.stream;
  }

  Future<void> cancel({required String sessionId}) async {
    await peer.cancel({'sessionId': sessionId});
  }

  void _routeSessionUpdate(Json json) {
    final sessionId = json['sessionId'] as String?;
    final update = json['update'] as Map<String, dynamic>?;
    if (sessionId == null || update == null) return;
    final sink = _sessionStreams[sessionId];
    if (sink == null) return;

    final kind = update['sessionUpdate'];
    if (kind == 'available_commands_update') {
      final cmds =
          (update['availableCommands'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      sink.add(AvailableCommandsUpdate(cmds));
    } else if (kind == 'plan') {
      sink.add(PlanUpdate(update));
    } else if (kind == 'tool_call' || kind == 'tool_call_update') {
      sink.add(ToolCallUpdate(update));
    } else if (kind == 'user_message_chunk' ||
        kind == 'agent_message_chunk' ||
        kind == 'agent_thought_chunk') {
      final content = update['content'];
      final blocks = content is Map<String, dynamic>
          ? <Map<String, dynamic>>[content]
          : (content as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final role = kind == 'user_message_chunk' ? 'user' : 'assistant';
      sink.add(MessageDelta(role: role, content: blocks));
    } else if (kind == 'diff') {
      sink.add(DiffUpdate(update));
    } else {
      sink.add(UnknownUpdate(json));
    }
  }

  // ===== Agent -> Client handlers =====
  Future<Json> _onReadTextFile(Json req) async {
    final path = req['path'] as String;
    final int? line = (req['line'] as num?)?.toInt();
    final int? limit = (req['limit'] as num?)?.toInt();
    final content = await config.fsProvider.readTextFile(
      path,
      line: line,
      limit: limit,
    );
    return {'content': content};
  }

  Future<Json?> _onWriteTextFile(Json req) async {
    final path = req['path'] as String;
    final content = req['content'] as String? ?? '';
    await config.fsProvider.writeTextFile(path, content);
    return null; // per schema null
  }

  Future<Json> _onRequestPermission(Json req) async {
    final options =
        (req['options'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final toolCall = (req['toolCall'] as Map<String, dynamic>?);
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
    String? optionId =
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
    return null;
  }
}
