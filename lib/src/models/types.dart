enum StopReason { endTurn, maxTokens, cancelled, refusal, other }

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
