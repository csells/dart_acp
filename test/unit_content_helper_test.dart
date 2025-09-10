import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  test('AcpClient.text helper produces text block', () {
    final b = AcpClient.text('hi');
    expect(b['type'], 'text');
    expect(b['text'], 'hi');
  });
}
