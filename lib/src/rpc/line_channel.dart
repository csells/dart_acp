import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

/// Wraps a process's stdio as a line-delimited JSON StreamChannel.
class LineJsonChannel {
  final Process process;
  final StreamChannelController<String> _controller = StreamChannelController();
  late final StreamSubscription _stdoutSub;
  late final StreamSubscription _stderrSub;
  final void Function(String line)? onInboundLine;
  final void Function(String line)? onOutboundLine;

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
          if (onInboundLine != null) onInboundLine!(line);
          _controller.local.sink.add(line);
        });
    _stderrSub = process.stderr.transform(utf8.decoder).listen((line) {
      if (onStderr != null) onStderr(line);
    });

    _controller.local.stream.listen((out) {
      // Each outgoing payload is one JSON-RPC message; append newline
      if (onOutboundLine != null) onOutboundLine!(out);
      process.stdin.add(utf8.encode(out));
      process.stdin.add([0x0A]);
    });
  }

  StreamChannel<String> get channel => _controller.foreign;

  Future<void> dispose() async {
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    await process.stdin.flush();
  }
}
