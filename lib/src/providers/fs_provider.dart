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
  final bool allowReadOutsideWorkspace;

  DefaultFsProvider({required this.workspaceRoot, this.allowReadOutsideWorkspace = false})
    : _jail = WorkspaceJail(workspaceRoot: workspaceRoot);

  @override
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    final filePath = allowReadOutsideWorkspace
        ? await _jail.resolveForgiving(path)
        : await _jail.resolveAndEnsureWithin(path);
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
    // Writes must stay within the workspace; if requested outside, fail with
    // a descriptive error so the agent can adjust.
    final canonical = await _jail.resolveForgiving(path);
    if (!await _jail.isWithinWorkspace(canonical)) {
      throw FileSystemException(
        'Write denied: path is outside the workspace root. '
        'Please write within the project directory or adjust the path.',
        canonical,
      );
    }
    final filePath = canonical;
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(filePath);
    await file.writeAsString(content);
  }
}
