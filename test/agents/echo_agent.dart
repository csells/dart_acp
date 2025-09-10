import 'dart:convert';
import 'dart:io';

void main() async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      // Ignore malformed lines
      continue;
    }
    final method = msg['method'] as String?;
    final id = msg['id'];
    final params =
        (msg['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (method == null) continue;
    switch (method) {
      case 'initialize':
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': 1,
            'agentCapabilities': {
              'promptCapabilities': {'embeddedContext': true},
            },
            'authMethods': <dynamic>[],
          },
        });
      case 'session/new':
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'sessionId': _uuid()},
        });
      case 'session/load':
        _send({'jsonrpc': '2.0', 'id': id, 'result': {}});
      case 'session/prompt':
        final sessionId = params['sessionId'] as String? ?? '';
        final blocks =
            (params['prompt'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        final text = blocks
            .where((b) => b['type'] == 'text')
            .map((b) => (b['text'] ?? '').toString())
            .join();
        final reply = 'Echo: ${text.trim()}';
        _send({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': reply},
            },
          },
        });
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
      case 'session/cancel':
        break;
      default:
        if (id != null) {
          _send({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32601, 'message': 'Method not found'},
          });
        }
    }
  }
}

void _send(Map<String, dynamic> obj) {
  stdout.writeln(jsonEncode(obj));
}

String _uuid() {
  final hex = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  return '$hex-echo';
}
