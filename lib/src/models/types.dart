/// Terminal reasons reported when a prompt turn completes.
enum StopReason {
  /// The model finished the turn without requesting more tools.
  endTurn,

  /// The agent hit token or request limits for the turn.
  maxTokens,

  /// The client cancelled the turn (`session/cancel`).
  cancelled,

  /// The agent refused to continue the turn.
  refusal,

  /// Any other non-standard stop reason.
  other,
}

/// Convert a wire stop reason string to [StopReason].
StopReason stopReasonFromWire(String s) {
  switch (s) {
    case 'end_turn':
      return StopReason.endTurn;
    case 'max_tokens':
    case 'max_turn_requests':
      return StopReason.maxTokens;
    case 'cancelled':
      return StopReason.cancelled;
    case 'refusal':
      return StopReason.refusal;
    default:
      return StopReason.other;
  }
}
