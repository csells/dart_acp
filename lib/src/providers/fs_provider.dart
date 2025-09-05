import 'dart:io';
import 'package:path/path.dart' as p;
import '../security/workspace_jail.dart';

abstract class FsProvider {
  Future<String> readTextFile(String path, {int? line, int? limit});
  Future<void> writeTextFile(String path, String content);
}

class DefaultFsProvider implements FsProvider {
  final String workspaceRoot;
  final WorkspaceJail _jail;

  DefaultFsProvider({required this.workspaceRoot})
    : _jail = WorkspaceJail(workspaceRoot: workspaceRoot);

  @override
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    final filePath = await _jail.resolveAndEnsureWithin(path);
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final content = await file.readAsString();
    if (line == null && limit == null) return content;

    final lines = content.split('\n');
    if (line != null) {
      final idx = line.clamp(1, lines.length) - 1;
      final start = (idx - (limit ?? 1) + 1).clamp(0, lines.length);
      final end = (idx + 1).clamp(0, lines.length);
      return lines.sublist(start, end).join('\n');
    }
    // limit only: return first N lines
    return lines.take(limit!).join('\n');
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    final filePath = await _jail.resolveAndEnsureWithin(path);
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(filePath);
    await file.writeAsString(content);
  }
}
