import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  test('stopReason mapping covers known values', () {
    expect(stopReasonFromWire('end_turn'), StopReason.endTurn);
    expect(stopReasonFromWire('max_tokens'), StopReason.maxTokens);
    expect(stopReasonFromWire('max_turn_requests'), StopReason.maxTokens);
    expect(stopReasonFromWire('cancelled'), StopReason.cancelled);
    expect(stopReasonFromWire('refusal'), StopReason.refusal);
    expect(stopReasonFromWire('anything_else'), StopReason.other);
  });
}
