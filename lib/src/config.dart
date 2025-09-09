import 'package:logging/logging.dart';
import 'capabilities.dart';
import 'providers/fs_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/terminal_provider.dart';

class AcpTimeouts {
  // host may set

  const AcpTimeouts({
    this.initialize = const Duration(seconds: 15),
    this.prompt,
    this.permission,
  });
  final Duration initialize;
  final Duration? prompt; // no hard timeout by default
  final Duration? permission;
}

class AcpConfig {
  AcpConfig({
    required this.workspaceRoot,
    this.agentCommand,
    this.agentArgs = const [],
    this.envOverrides = const {},
    this.capabilities = const AcpCapabilities(),
    this.mcpServers = const [],
    this.allowReadOutsideWorkspace = false,
    this.timeouts = const AcpTimeouts(),
    Logger? logger,
    FsProvider? fsProvider,
    PermissionProvider? permissionProvider,
    this.terminalProvider,
    this.onProtocolOut,
    this.onProtocolIn,
  }) : logger = logger ?? Logger('dart_acp'),
       fsProvider =
           fsProvider ??
           DefaultFsProvider(
             workspaceRoot: workspaceRoot,
             allowReadOutsideWorkspace: allowReadOutsideWorkspace,
           ),
       permissionProvider =
           permissionProvider ?? const DefaultPermissionProvider();
  final String workspaceRoot; // absolute path required
  final String? agentCommand; // required for stdio transport; provided by host
  final List<String> agentArgs;
  final Map<String, String> envOverrides; // additive only
  final AcpCapabilities capabilities;
  // Global MCP servers (forwarded to session/new and session/load)
  final List<Map<String, dynamic>> mcpServers;
  // Allow reads outside workspace (yolo mode)
  final bool allowReadOutsideWorkspace;
  final AcpTimeouts timeouts;
  final Logger logger;
  // Optional taps for raw JSON-RPC frames (unprefixed JSONL). If provided,
  // they are invoked for each frame sent/received by the transport.
  final void Function(String line)? onProtocolOut;
  final void Function(String line)? onProtocolIn;

  // Providers
  final FsProvider fsProvider;
  final PermissionProvider permissionProvider;
  final TerminalProvider? terminalProvider;
}
