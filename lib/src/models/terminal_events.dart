sealed class TerminalEvent {
  const TerminalEvent();
}

class TerminalCreated extends TerminalEvent {
  const TerminalCreated({
    required this.terminalId,
    required this.sessionId,
    required this.command,
    required this.args,
    this.cwd,
  });
  final String terminalId;
  final String sessionId;
  final String command;
  final List<String> args;
  final String? cwd;
}

class TerminalOutputEvent extends TerminalEvent {
  // null if not exited
  const TerminalOutputEvent({
    required this.terminalId,
    required this.output,
    required this.truncated,
    required this.exitCode,
  });
  final String terminalId;
  final String output;
  final bool truncated;
  final int? exitCode;
}

class TerminalExited extends TerminalEvent {
  const TerminalExited({required this.terminalId, required this.code});
  final String terminalId;
  final int code;
}

class TerminalReleased extends TerminalEvent {
  const TerminalReleased({required this.terminalId});
  final String terminalId;
}
