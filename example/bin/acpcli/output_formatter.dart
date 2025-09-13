import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';

import 'args.dart';

/// Handles output formatting for different modes (text, simple, jsonl).
class OutputFormatter {
  OutputFormatter(this.mode);

  final OutputMode mode;

  /// Format and print terminal events.
  void printTerminalEvent(TerminalEvent event) {
    if (mode != OutputMode.text) return;

    if (event is TerminalCreated) {
      stdout.writeln(
        '[term] created id=${event.terminalId} cmd=${event.command}',
      );
    } else if (event is TerminalOutputEvent) {
      if (event.output.isNotEmpty) {
        stdout.writeln('[term] output id=${event.terminalId}');
      }
    } else if (event is TerminalExited) {
      stdout.writeln('[term] exited id=${event.terminalId} code=${event.code}');
    } else if (event is TerminalReleased) {
      stdout.writeln('[term] released id=${event.terminalId}');
    }
  }

  /// Format and print session updates.
  void printSessionUpdate(AcpUpdate update) {
    if (mode != OutputMode.text) return;

    if (update is PlanUpdate) {
      stdout.writeln('[plan] ${jsonEncode(update.plan)}');
    } else if (update is ToolCallUpdate) {
      _printToolCall(update.toolCall);
    } else if (update is DiffUpdate) {
      stdout.writeln('[diff] ${jsonEncode(update.diff)}');
    }
  }

  void _printToolCall(ToolCall toolCall) {
    final title = (toolCall.title ?? '').trim();
    final kind = (toolCall.kind?.toWire() ?? '').trim();
    var locText = '';
    final locs = toolCall.locations ?? const [];
    if (locs.isNotEmpty) {
      final loc = locs.first;
      final path = loc.path;
      if (path.isNotEmpty) locText = ' @ $path';
    }
    final header = [
      if (kind.isNotEmpty) kind,
      if (title.isNotEmpty) title,
    ].join(' ');
    stdout.writeln(
      '[tool] ${header.isEmpty ? toolCall.toolCallId : header}$locText',
    );
    // Show raw input/output snippets when present
    if (toolCall.rawInput != null) {
      final snip = _truncate(_stringify(toolCall.rawInput), 240);
      if (snip.isNotEmpty) stdout.writeln('[tool.in] $snip');
    }
    if (toolCall.rawOutput != null) {
      final snip = _truncate(_stringify(toolCall.rawOutput), 240);
      if (snip.isNotEmpty) stdout.writeln('[tool.out] $snip');
    }
  }

  /// Print message content for text/simple modes.
  void printMessageDelta(MessageDelta delta) {
    if (mode.isJsonLike) return;

    // In simple mode, skip thought chunks
    if (mode == OutputMode.simple && delta.isThought) {
      return;
    }

    final texts = delta.content
        .whereType<TextContent>()
        .map((b) => b.text)
        .join();
    if (texts.isNotEmpty) stdout.writeln(texts);
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  String _stringify(Object? o) {
    if (o == null) return '';
    try {
      if (o is String) return o;
      return jsonEncode(o);
    } on Object {
      return o.toString();
    }
  }
}
