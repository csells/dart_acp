import 'types.dart';

sealed class AcpUpdate {
  const AcpUpdate();
}

class PlanUpdate extends AcpUpdate {
  // structure TBD
  const PlanUpdate(this.plan);
  final Map<String, dynamic> plan;
}

class MessageDelta extends AcpUpdate {
  // content blocks
  const MessageDelta({required this.role, required this.content});
  final String role; // 'assistant' or 'user'
  final List<Map<String, dynamic>> content;
}

class ToolCallUpdate extends AcpUpdate {
  // created/updated/completed
  const ToolCallUpdate(this.toolCall);
  final Map<String, dynamic> toolCall;
}

class DiffUpdate extends AcpUpdate {
  // file diffs
  const DiffUpdate(this.diff);
  final Map<String, dynamic> diff;
}

class AvailableCommandsUpdate extends AcpUpdate {
  const AvailableCommandsUpdate(this.commands);
  final List<Map<String, dynamic>> commands;
}

class TurnEnded extends AcpUpdate {
  const TurnEnded(this.stopReason);
  final StopReason stopReason;
}

class UnknownUpdate extends AcpUpdate {
  const UnknownUpdate(this.raw);
  final Map<String, dynamic> raw;
}
