import 'dart:async';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';

typedef Json = Map<String, dynamic>;

class JsonRpcPeer {
  final rpc.Peer _peer;
  final StreamController<Json> _sessionUpdates = StreamController.broadcast();

  Stream<Json> get sessionUpdates => _sessionUpdates.stream;

  JsonRpcPeer(StreamChannel<String> channel) : _peer = rpc.Peer(channel) {
    _registerClientHandlers();
    _peer.listen();
  }

  void _registerClientHandlers() {
    _peer.registerMethod('session/update', (rpc.Parameters params) async {
      final json = params.value as Map;
      _sessionUpdates.add(Map<String, dynamic>.from(json));
      return null;
    });
    // The following methods are handled by higher-level wiring. We expose
    // registration points for them via onX setters.
    _peer.registerMethod('fs/read_text_file', (rpc.Parameters params) async {
      if (onReadTextFile == null) {
        throw rpc.RpcException.methodNotFound('fs/read_text_file');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onReadTextFile!(json);
    });
    _peer.registerMethod('fs/write_text_file', (rpc.Parameters params) async {
      if (onWriteTextFile == null) {
        throw rpc.RpcException.methodNotFound('fs/write_text_file');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onWriteTextFile!(json);
    });
    _peer.registerMethod('session/request_permission', (
      rpc.Parameters params,
    ) async {
      if (onRequestPermission == null) {
        throw rpc.RpcException.methodNotFound('session/request_permission');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onRequestPermission!(json);
    });
    _peer.registerMethod('terminal/create', (rpc.Parameters params) async {
      if (onTerminalCreate == null) {
        throw rpc.RpcException.methodNotFound('terminal/create');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onTerminalCreate!(json);
    });
    _peer.registerMethod('terminal/output', (rpc.Parameters params) async {
      if (onTerminalOutput == null) {
        throw rpc.RpcException.methodNotFound('terminal/output');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onTerminalOutput!(json);
    });
    _peer.registerMethod('terminal/wait_for_exit', (
      rpc.Parameters params,
    ) async {
      if (onTerminalWaitForExit == null) {
        throw rpc.RpcException.methodNotFound('terminal/wait_for_exit');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onTerminalWaitForExit!(json);
    });
    _peer.registerMethod('terminal/kill', (rpc.Parameters params) async {
      if (onTerminalKill == null) {
        throw rpc.RpcException.methodNotFound('terminal/kill');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onTerminalKill!(json);
    });
    _peer.registerMethod('terminal/release', (rpc.Parameters params) async {
      if (onTerminalRelease == null) {
        throw rpc.RpcException.methodNotFound('terminal/release');
      }
      final json = Map<String, dynamic>.from(params.value as Map);
      return await onTerminalRelease!(json);
    });
  }

  // Client handlers (Agent -> Client callbacks)
  Future<dynamic> Function(Json)? onReadTextFile;
  Future<dynamic> Function(Json)? onWriteTextFile;
  Future<dynamic> Function(Json)? onRequestPermission;
  Future<dynamic> Function(Json)? onTerminalCreate;
  Future<dynamic> Function(Json)? onTerminalOutput;
  Future<dynamic> Function(Json)? onTerminalWaitForExit;
  Future<dynamic> Function(Json)? onTerminalKill;
  Future<dynamic> Function(Json)? onTerminalRelease;

  // Client -> Agent requests
  Future<Json> initialize(Json params) async =>
      Map<String, dynamic>.from(await _peer.sendRequest('initialize', params));

  Future<Json> newSession(Json params) async =>
      Map<String, dynamic>.from(await _peer.sendRequest('session/new', params));

  Future<void> loadSession(Json params) async =>
      await _peer.sendRequest('session/load', params);

  Future<Json> prompt(Json params) async => Map<String, dynamic>.from(
    await _peer.sendRequest('session/prompt', params),
  );

  Future<void> cancel(Json params) async =>
      await _peer.sendRequest('session/cancel', params);
}
