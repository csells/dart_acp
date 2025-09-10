import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Capabilities', () {
    test('defaults: fs.read enabled; fs.write disabled', () {
      const caps = AcpCapabilities();
      expect(caps.fs.readTextFile, isTrue);
      expect(caps.fs.writeTextFile, isFalse);
    });

    test('toJson() includes both fs booleans explicitly', () {
      const caps = AcpCapabilities(
        fs: FsCapabilities(readTextFile: false, writeTextFile: true),
      );
      final json = caps.toJson();
      expect(json, contains('fs'));
      final fs = json['fs'] as Map<String, dynamic>;
      expect(fs['readTextFile'], isFalse);
      expect(fs['writeTextFile'], isTrue);
    });
  });

  group('StopReason mapping', () {
    test('max_turn_requests maps to maxTokens', () {
      expect(stopReasonFromWire('max_turn_requests'), StopReason.maxTokens);
    });
    test('unknown maps to other', () {
      expect(stopReasonFromWire('weird_value'), StopReason.other);
    });
  });

  group('Content helpers', () {
    test('AcpClient.text builds a text content block', () {
      final b = AcpClient.text('hello');
      expect(b['type'], 'text');
      expect(b['text'], 'hello');
    });
  });

  group('FS provider policies', () {
    late Directory ws;
    late Directory outside;

    setUp(() async {
      ws = await Directory.systemTemp.createTemp('dart_acp_ws_');
      outside = await Directory.systemTemp.createTemp('dart_acp_out_');
    });

    tearDown(() async {
      try {
        await ws.delete(recursive: true);
      } on Object catch (_) {}
      try {
        await outside.delete(recursive: true);
      } on Object catch (_) {}
    });

    test('read: relative path resolves within workspace; '
        'outside denied by default', () async {
      File(p.join(ws.path, 'a.txt')).writeAsStringSync('hi');
      final outsideFile = File(p.join(outside.path, 'b.txt'))
        ..writeAsStringSync('there');

      final fs = DefaultFsProvider(workspaceRoot: ws.path);
      final content = await fs.readTextFile('a.txt');
      expect(content, 'hi');

      expect(
        () => fs.readTextFile(outsideFile.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'read: allowReadOutsideWorkspace=true permits outside reads',
      () async {
        final outsideFile = File(p.join(outside.path, 'c.txt'))
          ..writeAsStringSync('ok');
        final fs = DefaultFsProvider(
          workspaceRoot: ws.path,
          allowReadOutsideWorkspace: true,
        );
        final content = await fs.readTextFile(outsideFile.path);
        expect(content, 'ok');
      },
    );

    test('write: always confined to workspace (outside writes fail)', () async {
      final fs = DefaultFsProvider(
        workspaceRoot: ws.path,
        allowReadOutsideWorkspace: true,
      );
      // Inside OK
      final insidePath = p.join(ws.path, 'w.txt');
      await fs.writeTextFile(insidePath, 'data');
      expect(File(insidePath).readAsStringSync(), 'data');

      // Outside denied
      final outsidePath = p.join(outside.path, 'w.txt');
      expect(
        () => fs.writeTextFile(outsidePath, 'nope'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
