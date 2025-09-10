import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('Capabilities JSON', () {
    test('default fs caps are read-only', () {
      const caps = AcpCapabilities();
      final json = caps.toJson();
      expect(json.containsKey('fs'), isTrue);
      final fs = json['fs'] as Map<String, dynamic>;
      expect(fs['readTextFile'], isTrue);
      expect(fs['writeTextFile'], isFalse);
    });

    test('custom fs caps set properly', () {
      const caps = AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      );
      final fs = caps.toJson()['fs'] as Map<String, dynamic>;
      expect(fs['readTextFile'], isTrue);
      expect(fs['writeTextFile'], isTrue);
    });
  });
}
