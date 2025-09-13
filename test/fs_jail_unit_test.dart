import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('FS jail semantics', () {
    late Directory ws;
    late File inside;
    late File outside;

    setUp(() async {
      ws = await Directory.systemTemp.createTemp('fsjail_');
      inside = File('${ws.path}/inside.txt')..writeAsStringSync('hello');
      // place outside in system temp root (sibling to ws)
      outside = File('${Directory.systemTemp.path}/outside.txt')
        ..writeAsStringSync('world');
    });

    tearDown(() async {
      try {
        if (inside.existsSync()) inside.deleteSync();
        if (outside.existsSync()) outside.deleteSync();
        if (ws.existsSync()) ws.deleteSync(recursive: true);
      } on Object catch (_) {}
    });

    test('read inside workspace succeeds; outside denied by default', () async {
      final fs = DefaultFsProvider(
        workspaceRoot: ws.path,
        allowReadOutsideWorkspace: false,
      );
      final text = await fs.readTextFile(inside.path);
      expect(text, 'hello');
      expect(
        () => fs.readTextFile(outside.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'read outside allowed when yolo enabled; write still denied',
      () async {
        final fs = DefaultFsProvider(
          workspaceRoot: ws.path,
          allowReadOutsideWorkspace: true,
        );
        final text = await fs.readTextFile(outside.path);
        expect(text, 'world');
        // write attempt outside should be blocked
        await expectLater(
          () => fs.writeTextFile(outside.path, 'nope'),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}
