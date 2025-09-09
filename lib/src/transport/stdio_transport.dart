import 'dart:io';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';
import '../rpc/line_channel.dart';
import '../transport/transport.dart';

class StdioTransport implements AcpTransport {
  final String? command;
  final List<String> args;
  final String cwd;
  final Map<String, String> envOverrides;
  final Logger logger;
  final void Function(String line)? onProtocolOut;
  final void Function(String line)? onProtocolIn;

  Process? _process;
  LineJsonChannel? _channel;

  StdioTransport({
    required this.cwd,
    this.command,
    this.args = const [],
    this.envOverrides = const {},
    required this.logger,
    this.onProtocolOut,
    this.onProtocolIn,
  });

  @override
  StreamChannel<String> get channel {
    if (_channel == null) {
      throw StateError('Transport not started');
    }
    return _channel!.channel;
  }

  @override
  Future<void> start() async {
    final baseEnv = Map<String, String>.from(Platform.environment);
    baseEnv.addAll(envOverrides);

    Future<Process> spawn(String cmd, List<String> a) async {
      return await Process.start(
        cmd,
        a,
        workingDirectory: cwd,
        environment: baseEnv,
      );
    }

    if (command == null || command!.trim().isEmpty) {
      throw StateError(
        'AcpTransport requires an explicit agent command provided by the host.',
      );
    }
    final cmd = command!;
    final proc = await spawn(cmd, args);
    logger.fine('Spawned agent: $cmd ${args.join(' ')}');

    _process = proc;
    _channel = LineJsonChannel(
      proc,
      onStderr: (s) => logger.finer('[agent stderr] $s'),
      onInboundLine: onProtocolIn,
      onOutboundLine: onProtocolOut,
    );
  }

  @override
  Future<void> stop() async {
    if (_channel != null) {
      await _channel!.dispose();
      _channel = null;
    }
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      _process = null;
    }
  }
}
