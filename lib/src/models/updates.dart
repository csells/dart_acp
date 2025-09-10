import 'types.dart';

/// Base class for typed session/update events.
sealed class AcpUpdate {
  /// Create an update instance.
  const AcpUpdate();
}

/// Update containing the agent's current execution plan.
class PlanUpdate extends AcpUpdate {
  /// Construct with the raw plan object.
  const PlanUpdate(this.plan);

  /// Raw plan payload (structure may vary by agent).
  final Map<String, dynamic> plan;
}

/// Streaming message delta, for user/assistant content blocks.
class MessageDelta extends AcpUpdate {
  /// Create a message delta.
  const MessageDelta({
    required this.role,
    required this.content,
    this.isThought = false,
  });

  /// Role of the author ('assistant' or 'user').
  final String role;

  /// Content blocks comprising this delta.
  final List<Map<String, dynamic>> content;

  /// Whether this is a thought chunk (vs a message chunk).
  final bool isThought;
}

/// Tool call creation/progress/completion update.
class ToolCallUpdate extends AcpUpdate {
  /// Construct a tool call update with raw payload.
  const ToolCallUpdate(this.toolCall);

  /// Raw tool call payload.
  final Map<String, dynamic> toolCall;
}

/// File diff update with proposed changes.
class DiffUpdate extends AcpUpdate {
  /// Construct a diff update with raw diff payload.
  const DiffUpdate(this.diff);

  /// Raw diff payload.
  final Map<String, dynamic> diff;
}

/// Update containing currently available commands for the agent.
class AvailableCommandsUpdate extends AcpUpdate {
  /// Construct with the list of commands.
  const AvailableCommandsUpdate(this.commands);

  /// Raw command definitions.
  final List<Map<String, dynamic>> commands;
}

/// Terminal update indicating a prompt turn is complete.
class TurnEnded extends AcpUpdate {
  /// Construct with the terminal [stopReason].
  const TurnEnded(this.stopReason);

  /// Reason for stopping the turn.
  final StopReason stopReason;
}

/// Update type used for unclassified session/update payloads.
class UnknownUpdate extends AcpUpdate {
  /// Construct with the raw notification payload.
  const UnknownUpdate(this.raw);

  /// Raw session/update map.
  final Map<String, dynamic> raw;
}
