// Minimal MCP stdio server for compliance tests. Provides deterministic tools
// so agents can connect and call tools if desired.

import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  // Create an MCP server with basic capabilities (tools & resources
  // advertised).
  final server = McpServer(
    const Implementation(name: 'dart-acp-mcp', version: '0.1.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
      ),
    ),
  );

  // Register a simple ping tool
  server.registerTool(
    'ping',
    description: 'Returns pong',
    callback: (args, extra) async =>
        const CallToolResult(content: [TextContent(text: 'pong')]),
  );

  // Register a read_file tool: { path: string }
  server.registerTool(
    'read-file',
    description: 'Read a text file and return content',
    inputSchema: const ToolInputSchema(
      properties: {
        'path': JsonString(description: 'Absolute path to the file to read'),
      },
      required: ['path'],
    ),
    callback: (args, extra) async {
      final path = args['path'];
      if (path is! String || path.trim().isEmpty) {
        return const CallToolResult(
          content: [TextContent(text: 'Invalid path')],
          isError: true,
        );
      }
      try {
        final content = await File(path).readAsString();
        return CallToolResult(content: [TextContent(text: content)]);
      } on Exception catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Error: $e')],
          isError: true,
        );
      }
    },
  );

  // Register a list-files tool: { path: string }
  server.registerTool(
    'list-files',
    description: 'List files in a directory (non-recursive)',
    inputSchema: const ToolInputSchema(
      properties: {
        'path': JsonString(description: 'Absolute path to a directory to list'),
      },
      required: ['path'],
    ),
    callback: (args, extra) async {
      final path = args['path'];
      if (path is! String || path.trim().isEmpty) {
        return const CallToolResult(
          content: [TextContent(text: 'Invalid path')],
          isError: true,
        );
      }
      final dir = Directory(path);
      if (!dir.existsSync()) {
        return CallToolResult(
          content: [TextContent(text: 'Directory does not exist: $path')],
          isError: true,
        );
      }
      try {
        final entries = await dir.list(followLinks: false).toList();
        final files = <Map<String, dynamic>>[];
        for (final e in entries) {
          final type = await e.stat().then((s) => s.type);
          files.add({
            'path': e.path,
            'type': type == FileSystemEntityType.directory
                ? 'directory'
                : (type == FileSystemEntityType.file ? 'file' : 'other'),
          });
        }
        return CallToolResult.fromStructuredContent({'files': files});
      } on Exception catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Error: $e')],
          isError: true,
        );
      }
    },
  );

  // Connect the server to stdio
  final transport = StdioServerTransport();
  await server.connect(transport);

  // Keep the process alive; exit when stdin closes
  final done = Completer<void>();
  transport.onclose = () {
    if (!done.isCompleted) done.complete();
  };
  await done.future;
}
