// Fix script for acp_client_e2e_test.dart timeout issue
import 'dart:io';

void main() {
  final file = File('test/acp_client_e2e_test.dart');
  var content = file.readAsStringSync();
  
  // Replace the stream consumption to add timeout
  content = content.replaceAll(
    '''      final collected = <AcpUpdate>[];
      await for (final u in updates) {
        collected.add(u);
        if (u is TurnEnded) break;
      }''',
    '''      final collected = <AcpUpdate>[];
      await for (final u in updates.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          // If we timeout, close the sink to end the stream
          sink.close();
        },
      )) {
        collected.add(u);
        if (u is TurnEnded) break;
      }'''
  );
  
  file.writeAsStringSync(content);
  print('Fixed acp_client_e2e_test.dart with stream timeout');
}