import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TerminalProcessHandle {
  final String terminalId;
  final Process process;
  final StreamSubscription<List<int>> _stdoutSub;
  final StreamSubscription<List<int>> _stderrSub;
  final StringBuffer _buffer = StringBuffer();
  bool _released = false;

  TerminalProcessHandle({required this.terminalId, required this.process})
    : _stdoutSub = process.stdout.listen((data) {}),
      _stderrSub = process.stderr.listen((data) {}) {
    // Rewire subscriptions to buffer output as text
    _stdoutSub.onData((data) => _buffer.write(utf8.decode(data)));
    _stderrSub.onData((data) => _buffer.write(utf8.decode(data)));
  }

  String currentOutput() => _buffer.toString();

  Future<int> waitForExit() async {
    return await process.exitCode;
  }

  Future<void> kill() async {
    process.kill(ProcessSignal.sigterm);
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
  }
}

abstract class TerminalProvider {
  Future<TerminalProcessHandle> create({
    required String sessionId,
    required String command,
    List<String> args,
    String? cwd,
    Map<String, String>? env,
  });

  Future<String> currentOutput(TerminalProcessHandle handle);
  Future<int> waitForExit(TerminalProcessHandle handle);
  Future<void> kill(TerminalProcessHandle handle);
  Future<void> release(TerminalProcessHandle handle);
}

class DefaultTerminalProvider implements TerminalProvider {
  final Map<String, TerminalProcessHandle> _handles = {};

  @override
  Future<TerminalProcessHandle> create({
    required String sessionId,
    required String command,
    List<String> args = const [],
    String? cwd,
    Map<String, String>? env,
  }) async {
    final process = await Process.start(
      command,
      args,
      workingDirectory: cwd,
      environment: env,
      runInShell: false,
    );
    final handle = TerminalProcessHandle(
      terminalId: '$sessionId:${DateTime.now().microsecondsSinceEpoch}',
      process: process,
    );
    _handles[handle.terminalId] = handle;
    return handle;
  }

  @override
  Future<String> currentOutput(TerminalProcessHandle handle) async =>
      handle.currentOutput();

  @override
  Future<int> waitForExit(TerminalProcessHandle handle) async =>
      handle.waitForExit();

  @override
  Future<void> kill(TerminalProcessHandle handle) async => handle.kill();

  @override
  Future<void> release(TerminalProcessHandle handle) async {
    await handle.release();
  }
}
