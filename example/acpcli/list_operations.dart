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

    // List sessions (no session needed, but requires capability)
    if (args.listSessions) {
      if (!init.supportsListSessions) {
        if (args.output.isJsonLike) {
          final errorJson = {
            'jsonrpc': '2.0',
            'method': 'client/error',
            'params': {'message': 'Agent does not support session/list'},
          };
          stdout.writeln(jsonEncode(errorJson));
        } else {
          outputSections.add(
            '# Sessions ($agentName)\n'
            '(agent does not support session/list)\n',
          );
        }
      } else {
        final result = await client.listSessions(cwd: Directory.current.path);
        if (args.output.isJsonLike) {
          final sessionsJson = {
            'jsonrpc': '2.0',
            'method': 'client/sessions',
            'params': {
              'sessions': result.sessions.map((s) => s.toJson()).toList(),
              if (result.nextCursor != null) 'nextCursor': result.nextCursor,
            },
          };
          stdout.writeln(jsonEncode(sessionsJson));
        } else {
          outputSections.add(_formatSessionsMarkdown(result, agentName));
        }
      }
    }

    // Create session if needed for modes/commands
    if (needsSession && sessionId == null) {
      // ignore: parameter_assignments
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

    // Use extension helpers for better formatting
    final extCaps = init.extensionCapabilities;

    caps.forEach((key, value) {
      // Handle _meta (extension capabilities) specially
      if (key == '_meta' && extCaps.isNotEmpty) {
        lines.add('- extensions:');
        for (final vendor in extCaps.vendors) {
          lines.add('  - $vendor:');
          final vendorCaps = extCaps.getVendorCapabilities(vendor);
          vendorCaps?.forEach((k, v) {
            if (v is bool && v) {
              lines.add('    - $k');
            } else if (v != null && v != false) {
              lines.add('    - $k: $v');
            }
          });
        }
      } else if (value is bool) {
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

    // Add convenience capability checks
    final convenienceLines = <String>[];
    if (init.supportsLoadSession) {
      convenienceLines.add('  - loadSession (can resume sessions)');
    }
    final prompt = init.promptCapabilities;
    if (prompt.image || prompt.audio || prompt.embeddedContext) {
      convenienceLines.add('  - promptCapabilities:');
      if (prompt.image) convenienceLines.add('    - image');
      if (prompt.audio) convenienceLines.add('    - audio');
      if (prompt.embeddedContext) convenienceLines.add('    - embeddedContext');
    }
    final mcp = init.mcpCapabilities;
    if (mcp.http || mcp.sse) {
      convenienceLines.add('  - mcpCapabilities:');
      if (mcp.http) convenienceLines.add('    - http');
      if (mcp.sse) convenienceLines.add('    - sse');
    }

    if (convenienceLines.isNotEmpty) {
      lines.add('- summary:');
      lines.addAll(convenienceLines);
    }

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

  String _formatSessionsMarkdown(SessionListResult result, String agentName) {
    final buffer = StringBuffer();
    buffer.writeln('# Sessions ($agentName)');

    if (result.sessions.isEmpty) {
      buffer.writeln('(no sessions found)');
    } else {
      for (final s in result.sessions) {
        final title = s.title ?? s.sessionId;
        final updated = s.updatedAt != null
            ? ' (${s.updatedAt!.toLocal().toString().split('.').first})'
            : '';
        buffer.writeln('- $title$updated');
        buffer.writeln('  ID: ${s.sessionId}');
        buffer.writeln('  CWD: ${s.cwd}');
      }
    }

    if (result.hasMore) {
      buffer.writeln('\n(more sessions available - use cursor for pagination)');
    }

    return buffer.toString();
  }
}
