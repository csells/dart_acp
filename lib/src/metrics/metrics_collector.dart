import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/updates.dart';
import '../session/session_manager.dart';
import 'session_metrics.dart';

class MetricsCollector {
  MetricsCollector({required this.sessionManager});

  final SessionManager sessionManager;
  final Map<String, SessionMetrics> _sessions = {};
  final Map<String, StreamSubscription<AcpUpdate>> _subscriptions = {};

  SessionMetrics? getMetrics(String sessionId) => _sessions[sessionId];

  List<SessionMetrics> getAllMetrics() => _sessions.values.toList();

  void startTracking(String sessionId, {String? workspaceRoot}) {
    if (_sessions.containsKey(sessionId)) return;

    final metrics = SessionMetrics(
      sessionId: sessionId,
      startTime: DateTime.now(),
      workspaceRoot: workspaceRoot,
    );
    _sessions[sessionId] = metrics;

    // Subscribe to session updates
    final subscription = sessionManager
        .sessionUpdates(sessionId)
        .listen(metrics.recordUpdate);
    _subscriptions[sessionId] = subscription;
  }

  void stopTracking(String sessionId) {
    _subscriptions[sessionId]?.cancel();
    _subscriptions.remove(sessionId);
    _sessions[sessionId]?.endTime ??= DateTime.now();
  }

  void recordPermission({
    required String sessionId,
    required String toolName,
    required String? toolKind,
    required String outcome,
  }) {
    _sessions[sessionId]?.recordPermissionRequest(
      toolName: toolName,
      toolKind: toolKind,
      outcome: outcome,
    );
  }

  void recordTerminal({
    required String sessionId,
    required String terminalId,
    required String operation,
    String? command,
  }) {
    _sessions[sessionId]?.recordTerminalOperation(
      terminalId: terminalId,
      operation: operation,
      command: command,
    );
  }

  Future<void> exportToFile({
    required String sessionId,
    required String filePath,
    required ExportFormat format,
  }) async {
    final metrics = _sessions[sessionId];
    if (metrics == null) {
      throw ArgumentError('No metrics found for session $sessionId');
    }

    final file = File(filePath);
    String content;

    switch (format) {
      case ExportFormat.json:
        content = metrics.toJsonString(pretty: true);
      case ExportFormat.csv:
        content = metrics.toCsv();
      case ExportFormat.markdown:
        content = metrics.toMarkdown();
    }

    await file.writeAsString(content);
  }

  Future<void> exportAllToFile({
    required String filePath,
    required ExportFormat format,
  }) async {
    if (_sessions.isEmpty) {
      throw StateError('No metrics to export');
    }

    final file = File(filePath);
    String content;

    switch (format) {
      case ExportFormat.json:
        final allMetrics = _sessions.values.map((m) => m.toJson()).toList();
        content = const JsonEncoder.withIndent('  ').convert({
          'sessions': allMetrics,
          'exportTime': DateTime.now().toIso8601String(),
          'totalSessions': allMetrics.length,
        });
      case ExportFormat.csv:
        final buffer = StringBuffer();
        buffer.writeln(
          'Session ID,Start Time,End Time,Duration (ms),Stop Reason,Tool Calls,Messages,Permissions,Terminals',
        );
        for (final metrics in _sessions.values) {
          buffer.writeln(
            '${metrics.sessionId},'
            '${metrics.startTime.toIso8601String()},'
            '${metrics.endTime?.toIso8601String() ?? "ongoing"},'
            '${metrics.duration.inMilliseconds},'
            '${metrics.stopReason?.name ?? "ongoing"},'
            '${metrics.toolCalls.length},'
            '${metrics.messages.length},'
            '${metrics.permissions.length},'
            '${metrics.terminals.length}',
          );
        }
        content = buffer.toString();
      case ExportFormat.markdown:
        final buffer = StringBuffer();
        buffer.writeln('# All Sessions Metrics Report');
        buffer.writeln();
        buffer.writeln('**Export Time**: ${DateTime.now().toIso8601String()}');
        buffer.writeln('**Total Sessions**: ${_sessions.length}');
        buffer.writeln();

        for (final metrics in _sessions.values) {
          buffer.writeln('---');
          buffer.writeln();
          buffer.writeln(metrics.toMarkdown());
        }
        content = buffer.toString();
    }

    await file.writeAsString(content);
  }

  void clear() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _sessions.clear();
  }

  void dispose() {
    clear();
  }
}

enum ExportFormat { json, csv, markdown }

extension ExportFormatExtension on ExportFormat {
  String get extension {
    switch (this) {
      case ExportFormat.json:
        return 'json';
      case ExportFormat.csv:
        return 'csv';
      case ExportFormat.markdown:
        return 'md';
    }
  }

  static ExportFormat fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'json':
        return ExportFormat.json;
      case 'csv':
        return ExportFormat.csv;
      case 'md':
      case 'markdown':
        return ExportFormat.markdown;
      default:
        throw ArgumentError('Unsupported format: $ext');
    }
  }
}
