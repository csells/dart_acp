// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

class AgentCaps {
  AgentCaps({required this.agent, required this.result});
  final String agent;
  final Map<String, dynamic> result;
  Map<String, dynamic> get agentCapabilities =>
      (result['agentCapabilities'] as Map?)?.cast<String, dynamic>() ??
      const {};
  int get protocolVersion => (result['protocolVersion'] as num?)?.toInt() ?? 0;
}

final Map<String, AgentCaps> _capsCache = {};

AgentCaps capsFor(String agent) {
  if (_capsCache.containsKey(agent)) return _capsCache[agent]!;
  final settingsPath = File('test/test_settings.json').absolute.path;
  final proc = Process.runSync(
    'dart',
    [
      'example/main.dart',
      '--settings',
      settingsPath,
      '-a',
      agent,
      '-o',
      'jsonl',
      '--list-caps',
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (proc.exitCode != 0) {
    // Return an empty capabilities set on failure, but log stderr for context.
    final res = AgentCaps(agent: agent, result: const {});
    _capsCache[agent] = res;
    // Helpful when running locally
    print('[caps] list-caps failed for $agent: ${proc.stderr}');
    return res;
  }
  Map<String, dynamic>? initResult;
  for (final line in const LineSplitter().convert(proc.stdout as String)) {
    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) {
        final result = m['result'];
        if (result is Map && result.containsKey('protocolVersion')) {
          initResult = result.cast<String, dynamic>();
        }
      }
    } on Object {
      // ignore malformed JSONL lines
    }
  }
  final res = AgentCaps(agent: agent, result: initResult ?? const {});
  _capsCache[agent] = res;
  return res;
}

bool _hasKeyLike(dynamic node, String pattern) {
  if (node is Map) {
    for (final entry in node.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains(pattern)) return true;
      if (_hasKeyLike(entry.value, pattern)) return true;
    }
  } else if (node is List) {
    for (final v in node) {
      if (_hasKeyLike(v, pattern)) return true;
    }
  }
  return false;
}

/// Returns null if supported; otherwise a skip reason. All patterns must match.
String? skipIfMissingAll(
  String agent,
  List<String> capKeyPatterns,
  String name,
) {
  final caps = capsFor(agent);
  final ac = caps.agentCapabilities;
  // If agentCapabilities map is empty, be conservative and skip.
  if (ac.isEmpty) {
    return "Adapter '$agent' does not advertise capabilities; skipping $name";
  }
  final missing = <String>[];
  for (final p in capKeyPatterns) {
    if (!_hasKeyLike(ac, p.toLowerCase())) missing.add(p);
  }
  if (missing.isEmpty) return null;
  return "Adapter '$agent' lacks $name (missing: ${missing.join(', ')})";
}

/// Returns null if any pattern matches; otherwise a skip reason.
String? skipUnlessAny(String agent, List<String> patterns, String name) {
  final caps = capsFor(agent);
  final ac = caps.agentCapabilities;
  if (ac.isEmpty) {
    return "Adapter '$agent' does not advertise capabilities; skipping $name";
  }
  for (final p in patterns) {
    if (_hasKeyLike(ac, p.toLowerCase())) return null;
  }
  return "Adapter '$agent' does not advertise $name "
      "(needs one of: ${patterns.join(', ')})";
}
