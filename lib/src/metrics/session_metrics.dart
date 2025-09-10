import 'dart:convert';

import '../models/types.dart';
import '../models/updates.dart';

class SessionMetrics {
  SessionMetrics({
    required this.sessionId,
    required this.startTime,
    this.workspaceRoot,
  });

  final String sessionId;
  final DateTime startTime;
  final String? workspaceRoot;
  DateTime? endTime;
  StopReason? stopReason;

  final List<ToolCallMetric> toolCalls = [];
  final List<PermissionMetric> permissions = [];
  final List<TerminalMetric> terminals = [];
  final List<MessageMetric> messages = [];
  final List<DiffMetric> diffs = [];

  int thoughtChunkCount = 0;
  int planUpdateCount = 0;
  int totalContentBlocks = 0;

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  void recordUpdate(AcpUpdate update) {
    switch (update) {
      case ToolCallUpdate(:final toolCall):
        _recordToolCall(toolCall);
      case MessageDelta(:final role, :final content, :final isThought):
        if (isThought) {
          thoughtChunkCount++;
        } else {
          messages.add(
            MessageMetric(
              timestamp: DateTime.now(),
              role: role,
              blockCount: content.length,
            ),
          );
        }
        totalContentBlocks += content.length;
      case DiffUpdate(:final diff):
        diffs.add(
          DiffMetric(
            timestamp: DateTime.now(),
            path: diff['path'] as String? ?? '',
            action: diff['action'] as String? ?? 'unknown',
          ),
        );
      case PlanUpdate():
        planUpdateCount++;
      case TurnEnded(:final stopReason):
        endTime = DateTime.now();
        this.stopReason = stopReason;
      case _:
        break;
    }
  }

  void recordPermissionRequest({
    required String toolName,
    required String? toolKind,
    required String outcome,
  }) {
    permissions.add(
      PermissionMetric(
        timestamp: DateTime.now(),
        toolName: toolName,
        toolKind: toolKind,
        outcome: outcome,
      ),
    );
  }

  void recordTerminalOperation({
    required String terminalId,
    required String operation,
    String? command,
  }) {
    terminals.add(
      TerminalMetric(
        timestamp: DateTime.now(),
        terminalId: terminalId,
        operation: operation,
        command: command,
      ),
    );
  }

  void _recordToolCall(Map<String, dynamic> toolCall) {
    final name = toolCall['name'] as String? ?? 'unknown';
    final status = toolCall['status'] as String?;

    final existing = toolCalls
        .where((t) => t.callId == toolCall['id'])
        .firstOrNull;
    if (existing != null) {
      existing.status = status ?? existing.status;
      existing.endTime = DateTime.now();
    } else {
      toolCalls.add(
        ToolCallMetric(
          callId: toolCall['id'] as String? ?? '',
          name: name,
          status: status ?? 'running',
          startTime: DateTime.now(),
        ),
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'duration': duration.inMilliseconds,
    'workspaceRoot': workspaceRoot,
    'stopReason': stopReason?.name,
    'summary': {
      'totalToolCalls': toolCalls.length,
      'successfulToolCalls': toolCalls
          .where((t) => t.status == 'success')
          .length,
      'failedToolCalls': toolCalls.where((t) => t.status == 'error').length,
      'totalMessages': messages.length,
      'thoughtChunks': thoughtChunkCount,
      'planUpdates': planUpdateCount,
      'totalContentBlocks': totalContentBlocks,
      'permissions': permissions.length,
      'terminals': terminals.length,
      'diffs': diffs.length,
    },
    'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    'permissions': permissions.map((p) => p.toJson()).toList(),
    'terminals': terminals.map((t) => t.toJson()).toList(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'diffs': diffs.map((d) => d.toJson()).toList(),
  };

  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Metric,Value');
    buffer.writeln('Session ID,$sessionId');
    buffer.writeln('Start Time,${startTime.toIso8601String()}');
    buffer.writeln('End Time,${endTime?.toIso8601String() ?? "ongoing"}');
    buffer.writeln('Duration (ms),${duration.inMilliseconds}');
    buffer.writeln('Stop Reason,${stopReason?.name ?? "ongoing"}');
    buffer.writeln('Total Tool Calls,${toolCalls.length}');
    buffer.writeln(
      'Successful Tool Calls,${toolCalls.where((t) => t.status == "success").length}',
    );
    buffer.writeln(
      'Failed Tool Calls,${toolCalls.where((t) => t.status == "error").length}',
    );
    buffer.writeln('Total Messages,${messages.length}');
    buffer.writeln('Thought Chunks,$thoughtChunkCount');
    buffer.writeln('Plan Updates,$planUpdateCount');
    buffer.writeln('Total Content Blocks,$totalContentBlocks');
    buffer.writeln('Permissions Requested,${permissions.length}');
    buffer.writeln('Terminal Operations,${terminals.length}');
    buffer.writeln('File Diffs,${diffs.length}');
    return buffer.toString();
  }

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# Session Metrics Report');
    buffer.writeln();
    buffer.writeln('## Session Information');
    buffer.writeln('- **Session ID**: $sessionId');
    buffer.writeln('- **Start Time**: ${startTime.toIso8601String()}');
    buffer.writeln(
      '- **End Time**: ${endTime?.toIso8601String() ?? "ongoing"}',
    );
    buffer.writeln('- **Duration**: ${_formatDuration(duration)}');
    buffer.writeln('- **Stop Reason**: ${stopReason?.name ?? "ongoing"}');
    if (workspaceRoot != null) {
      buffer.writeln('- **Workspace**: $workspaceRoot');
    }
    buffer.writeln();

    buffer.writeln('## Summary Statistics');
    buffer.writeln('| Metric | Count |');
    buffer.writeln('|--------|-------|');
    buffer.writeln('| Tool Calls | ${toolCalls.length} |');
    buffer.writeln(
      '| Successful | ${toolCalls.where((t) => t.status == "success").length} |',
    );
    buffer.writeln(
      '| Failed | ${toolCalls.where((t) => t.status == "error").length} |',
    );
    buffer.writeln('| Messages | ${messages.length} |');
    buffer.writeln('| Thought Chunks | $thoughtChunkCount |');
    buffer.writeln('| Plan Updates | $planUpdateCount |');
    buffer.writeln('| Content Blocks | $totalContentBlocks |');
    buffer.writeln('| Permissions | ${permissions.length} |');
    buffer.writeln('| Terminal Ops | ${terminals.length} |');
    buffer.writeln('| File Diffs | ${diffs.length} |');
    buffer.writeln();

    if (toolCalls.isNotEmpty) {
      buffer.writeln('## Tool Calls');
      buffer.writeln('| Tool | Status | Duration |');
      buffer.writeln('|------|--------|----------|');
      for (final tool in toolCalls) {
        final duration = tool.duration != null
            ? '${tool.duration!.inMilliseconds}ms'
            : 'ongoing';
        buffer.writeln('| ${tool.name} | ${tool.status} | $duration |');
      }
      buffer.writeln();
    }

    if (permissions.isNotEmpty) {
      buffer.writeln('## Permission Requests');
      buffer.writeln('| Tool | Type | Outcome |');
      buffer.writeln('|------|------|---------|');
      for (final perm in permissions) {
        buffer.writeln(
          '| ${perm.toolName} | ${perm.toolKind ?? "n/a"} | ${perm.outcome} |',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inSeconds > 0) {
      return '${d.inSeconds}s ${d.inMilliseconds.remainder(1000)}ms';
    } else {
      return '${d.inMilliseconds}ms';
    }
  }
}

class ToolCallMetric {
  ToolCallMetric({
    required this.callId,
    required this.name,
    required this.status,
    required this.startTime,
    this.endTime,
  });

  final String callId;
  final String name;
  String status;
  final DateTime startTime;
  DateTime? endTime;

  Duration? get duration => endTime?.difference(startTime);

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'name': name,
    'status': status,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'duration': duration?.inMilliseconds,
  };
}

class PermissionMetric {
  const PermissionMetric({
    required this.timestamp,
    required this.toolName,
    required this.toolKind,
    required this.outcome,
  });

  final DateTime timestamp;
  final String toolName;
  final String? toolKind;
  final String outcome;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'toolName': toolName,
    'toolKind': toolKind,
    'outcome': outcome,
  };
}

class TerminalMetric {
  const TerminalMetric({
    required this.timestamp,
    required this.terminalId,
    required this.operation,
    this.command,
  });

  final DateTime timestamp;
  final String terminalId;
  final String operation;
  final String? command;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'terminalId': terminalId,
    'operation': operation,
    'command': command,
  };
}

class MessageMetric {
  const MessageMetric({
    required this.timestamp,
    required this.role,
    required this.blockCount,
  });

  final DateTime timestamp;
  final String role;
  final int blockCount;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'role': role,
    'blockCount': blockCount,
  };
}

class DiffMetric {
  const DiffMetric({
    required this.timestamp,
    required this.path,
    required this.action,
  });

  final DateTime timestamp;
  final String path;
  final String action;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'path': path,
    'action': action,
  };
}
