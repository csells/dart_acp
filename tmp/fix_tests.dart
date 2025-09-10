// Script to find and fix test stdin issues
import 'dart:io';

void main() {
  final file = File('test/agcli_e2e_real_test.dart');
  var content = file.readAsStringSync();
  
  // Find all Process.start blocks and check if they need stdin.close()
  final processStartPattern = RegExp(
    r'final proc = await Process\.start\([^)]+\)\;',
    multiLine: true,
  );
  
  // Tests that write to stdin (don't need the fix)
  final stdinWriteTests = [
    'gemini: stdin prompt (jsonl)',
    'claude-code: stdin prompt',
  ];
  
  // Process each test
  var currentTestName = '';
  final lines = content.split('\n');
  final newLines = <String>[];
  
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    
    // Track current test name
    if (line.contains('test(') || line.contains('test(\'')) {
      final match = RegExp(r"test\('([^']+)'").firstMatch(line);
      if (match != null) {
        currentTestName = match.group(1)!;
      }
    }
    
    newLines.add(line);
    
    // If this is a Process.start line and not in a stdin-writing test
    if (line.contains('final proc = await Process.start(') &&
        !stdinWriteTests.any((t) => currentTestName.contains(t))) {
      // Check if next lines already have stdin.close()
      var hasStdinClose = false;
      for (var j = i + 1; j < i + 10 && j < lines.length; j++) {
        if (lines[j].contains('proc.stdin.close()')) {
          hasStdinClose = true;
          break;
        }
        if (lines[j].contains('proc.stdin.write')) {
          // This test writes to stdin, skip
          hasStdinClose = true;
          break;
        }
      }
      
      if (!hasStdinClose) {
        // Find the end of Process.start statement
        var endIndex = i;
        var parenCount = 0;
        var inProcStart = false;
        for (var j = i; j < lines.length; j++) {
          final checkLine = lines[j];
          if (checkLine.contains('Process.start(')) inProcStart = true;
          if (inProcStart) {
            parenCount += checkLine.split('(').length - 1;
            parenCount -= checkLine.split(')').length - 1;
            if (parenCount == 0 && checkLine.contains(');')) {
              endIndex = j;
              break;
            }
          }
        }
        
        // Add stdin.close() after Process.start
        if (endIndex > i) {
          // Skip to endIndex
          for (var j = i + 1; j <= endIndex && j < lines.length; j++) {
            i++;
            newLines.add(lines[j]);
          }
          // Add the stdin.close() line
          newLines.add('      // Close stdin immediately since we\'re not sending any input');
          newLines.add('      await proc.stdin.close();');
          print('Added stdin.close() after line ${endIndex + 1} in test: $currentTestName');
        }
      }
    }
  }
  
  // Write the fixed content
  file.writeAsStringSync(newLines.join('\n'));
  print('Fixed test file');
}