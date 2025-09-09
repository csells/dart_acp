import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('Capabilities defaults', () {
    test('fs.read enabled; fs.write disabled', () {
      final caps = AcpCapabilities();
      expect(caps.fs.readTextFile, isTrue);
      expect(caps.fs.writeTextFile, isFalse);
    });
  });
}
