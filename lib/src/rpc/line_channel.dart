import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

/// Wraps a process's stdio as a line-delimited JSON StreamChannel.
class LineJsonChannel {
  /// Create a line-delimited channel around [process].
  LineJsonChannel(
    this.process, {
    void Function(String)? onStderr,
    this.onInboundLine,
    this.onOutboundLine,
  }) {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) return;
          onInboundLine?.call(line);
          _controller.local.sink.add(line);
        });
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .listen((line) => onStderr?.call(line));

    _controller.local.stream.listen((out) {
      // Each outgoing payload is one JSON-RPC message; append newline
      onOutboundLine?.call(out);
      process.stdin.add(utf8.encode(out));
      process.stdin.add([0x0A]);
    });
  }

  /// Underlying process.
  final Process process;
  final StreamChannelController<String> _controller = StreamChannelController();
  late final StreamSubscription _stdoutSub;
  late final StreamSubscription _stderrSub;

  /// Callback invoked for raw inbound lines.
  final void Function(String line)? onInboundLine;

  /// Callback invoked for raw outbound lines.
  final void Function(String line)? onOutboundLine;

  /// Exposed stream channel used by the JSON-RPC peer.
  StreamChannel<String> get channel => _controller.foreign;

  /// Dispose resources and flush stdin.
  Future<void> dispose() async {
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    await process.stdin.flush();
  }
}
