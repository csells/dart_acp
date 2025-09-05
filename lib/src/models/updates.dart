import 'types.dart';

sealed class AcpUpdate {
  const AcpUpdate();
}

class PlanUpdate extends AcpUpdate {
  final Map<String, dynamic> plan; // structure TBD
  const PlanUpdate(this.plan);
}

class MessageDelta extends AcpUpdate {
  final String role; // 'assistant' or 'user'
  final List<Map<String, dynamic>> content; // content blocks
  const MessageDelta({required this.role, required this.content});
}

class ToolCallUpdate extends AcpUpdate {
  final Map<String, dynamic> toolCall; // created/updated/completed
  const ToolCallUpdate(this.toolCall);
}

class DiffUpdate extends AcpUpdate {
  final Map<String, dynamic> diff; // file diffs
  const DiffUpdate(this.diff);
}

class AvailableCommandsUpdate extends AcpUpdate {
  final List<Map<String, dynamic>> commands;
  const AvailableCommandsUpdate(this.commands);
}

class TurnEnded extends AcpUpdate {
  final StopReason stopReason;
  const TurnEnded(this.stopReason);
}

class UnknownUpdate extends AcpUpdate {
  final Map<String, dynamic> raw;
  const UnknownUpdate(this.raw);
}
