import 'package:stream_channel/stream_channel.dart';

abstract class AcpTransport {
  /// A bidirectional channel of JSON-RPC messages (one JSON per string).
  StreamChannel<String> get channel;

  Future<void> start();
  Future<void> stop();
}
