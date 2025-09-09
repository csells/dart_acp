import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Minimal ACP-compatible mock agent over JSON-RPC 2.0 via stdio.
// Supports: initialize, session/new, session/load, session/prompt, session/cancel.

void main() async {
  final stdinLines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  final sessions = <String, List<Map<String, dynamic>>>{};
  String? cancellingSession;

  Future<void> send(Map<String, dynamic> msg) async {
    stdout.add(utf8.encode(jsonEncode(msg)));
    stdout.add([0x0A]);
    await stdout.flush();
  }

  await for (final line in stdinLines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final method = msg['method'];
    final id = msg['id'];
    final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (method == 'initialize') {
      await send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': true,
            'promptCapabilities': {
              'embeddedContext': true,
              'image': true,
              'audio': true,
            },
          },
          'authMethods': [],
        },
      });
    } else if (method == 'session/new') {
      final sid = 'sess_${DateTime.now().microsecondsSinceEpoch}';
      sessions[sid] = <Map<String, dynamic>>[];
      await send({'jsonrpc': '2.0', 'id': id, 'result': {'sessionId': sid}});
    } else if (method == 'session/load') {
      final sid = params['sessionId'] as String;
      final history = sessions[sid] ?? const [];
      for (final u in history) {
        await send({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': sid,
            'update': u,
          },
        });
      }
      await send({'jsonrpc': '2.0', 'id': id, 'result': null});
    } else if (method == 'session/prompt') {
      final sid = params['sessionId'] as String;
      final cancelled = (cancellingSession == sid);
      // Send a simple assistant message chunk.
      final update = {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': cancelled ? 'Cancelled.' : 'Hello from mock agent.',
        },
      };
      sessions[sid]?.add(update);
      await send({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': sid,
          'update': update,
        },
      });
      await send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'stopReason': cancelled ? 'cancelled' : 'end_turn'},
      });
      if (cancelled) cancellingSession = null;
    } else if (method == 'session/cancel') {
      final sid = params['sessionId'] as String?;
      if (sid != null) cancellingSession = sid;
      // Notification: no response
    } else {
      if (id != null) {
        await send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'Method not found: $method'},
        });
      }
    }
  }
}

