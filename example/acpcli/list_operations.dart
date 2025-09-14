import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/session/session_manager.dart'
    show InitializeResult;

import 'args.dart';

/// Handles --list-* operations for the CLI.
class ListOperationsHandler {
  ListOperationsHandler({
    required this.args,
    required this.client,
    required this.init,
    required this.agentName,
  });

  final CliArgs args;
  final AcpClient client;
  final InitializeResult init;
  final String agentName;

  /// Handle list flags and return a session ID if one was created.
  Future<String?> handleListFlags({String? sessionId}) async {
    final needsSession = args.listModes || args.listCommands;
    final outputSections = <String>[];

    // Capabilities (no session needed)
    if (args.listCaps) {
      if (args.output.isJsonLike) {
        final capsJson = {
          'jsonrpc': '2.0',
          'method': 'client/capabilities',
          'params': {
            'protocolVersion': init.protocolVersion,
            'authMethods': init.authMethods ?? [],
            'agentCapabilities': init.agentCapabilities ?? {},
          },
        };
        stdout.writeln(jsonEncode(capsJson));
      } else {
        outputSections.add(
          '# Capabilities ($agentName)\n'
          'Protocol Version: ${init.protocolVersion}\n'
          '${_formatAgentCapabilities(init.agentCapabilities)}\n',
        );
      }
    }

    // Create session if needed for modes/commands
    if (needsSession && sessionId == null) {
      sessionId = await client.newSession(Directory.current.path);

      // Wait briefly for available_commands_update
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Modes (needs session)
    if (args.listModes && sessionId != null) {
      final modes = client.sessionModes(sessionId);
      if (args.output.isJsonLike) {
        final modesJson = {
          'jsonrpc': '2.0',
          'method': 'client/modes',
          'params': {
            'current': modes?.currentModeId,
            'available':
                modes?.availableModes
                    .map((m) => {'id': m.id, 'name': m.name})
                    .toList() ??
                [],
          },
        };
        stdout.writeln(jsonEncode(modesJson));
      } else {
        if (modes != null) {
          final current = modes.currentModeId ?? '(none)';
          final available = modes.availableModes.isEmpty
              ? '(no modes)'
              : modes.availableModes
                    .map((m) => '- ${m.id}: ${m.name}')
                    .join('\n');
          outputSections.add(
            '# Modes ($agentName)\n'
            'Current: $current\n'
            'Available:\n$available\n',
          );
        } else {
          outputSections.add('# Modes ($agentName)\n(no modes)\n');
        }
      }
    }

    // Commands (needs session)
    if (args.listCommands && sessionId != null) {
      final commands = await _waitForCommands(client, sessionId);

      if (args.output.isJsonLike) {
        // For JSONL, the session update already emitted or we synthesize one
        if (commands.isEmpty) {
          final synthetic = {
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': sessionId,
              'update': {
                'sessionUpdate': 'available_commands_update',
                'availableCommands': <dynamic>[],
              },
            },
          };
          stdout.writeln(jsonEncode(synthetic));
        }
      } else {
        outputSections.add(_formatCommandsMarkdown(commands, agentName));
      }
    }

    // Print all sections for text mode
    if (!args.output.isJsonLike && outputSections.isNotEmpty) {
      for (final section in outputSections) {
        stdout.write(section);
        stdout.writeln(); // Blank line after each section
      }
    }

    return sessionId;
  }

  String _formatAgentCapabilities(Map<String, dynamic>? caps) {
    if (caps == null || caps.isEmpty) return '(no capabilities reported)';

    final lines = <String>[];
    caps.forEach((key, value) {
      if (value is bool) {
        if (value) lines.add('- $key');
      } else if (value is Map) {
        lines.add('- $key:');
        value.forEach((k, v) {
          if (v is bool && v) {
            lines.add('  - $k');
          } else if (v != null && v != false) {
            lines.add('  - $k: $v');
          }
        });
      } else if (value != null) {
        lines.add('- $key: $value');
      }
    });

    return lines.isEmpty ? '(no capabilities)' : lines.join('\n');
  }

  Future<List<AvailableCommand>> _waitForCommands(
    AcpClient client,
    String sessionId,
  ) async {
    final completer = Completer<List<AvailableCommand>>();
    late StreamSubscription<AcpUpdate> sub;

    sub = client.sessionUpdates(sessionId).listen((update) {
      if (update is AvailableCommandsUpdate) {
        if (!completer.isCompleted) {
          completer.complete(update.commands);
          unawaited(sub.cancel());
        }
      }
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await sub.cancel();
      return [];
    }
  }

  String _formatCommandsMarkdown(
    List<AvailableCommand> commands,
    String agentName,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('# Commands ($agentName)');

    if (commands.isEmpty) {
      buffer.writeln('(no commands)');
    } else {
      for (final c in commands) {
        final name = c.name;
        final desc = c.description ?? '';
        if (name.isEmpty) continue;
        if (desc.isEmpty) {
          buffer.writeln('- /$name');
        } else {
          buffer.writeln('- /$name - $desc');
        }
      }
    }

    return buffer.toString();
  }
}
