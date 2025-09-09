sealed class TerminalEvent {
  const TerminalEvent();
}

class TerminalCreated extends TerminalEvent {
  final String terminalId;
  final String sessionId;
  final String command;
  final List<String> args;
  final String? cwd;
  const TerminalCreated({
    required this.terminalId,
    required this.sessionId,
    required this.command,
    required this.args,
    this.cwd,
  });
}

class TerminalOutputEvent extends TerminalEvent {
  final String terminalId;
  final String output;
  final bool truncated;
  final int? exitCode; // null if not exited
  const TerminalOutputEvent({
    required this.terminalId,
    required this.output,
    required this.truncated,
    required this.exitCode,
  });
}

class TerminalExited extends TerminalEvent {
  final String terminalId;
  final int code;
  const TerminalExited({required this.terminalId, required this.code});
}

class TerminalReleased extends TerminalEvent {
  final String terminalId;
  const TerminalReleased({required this.terminalId});
}

