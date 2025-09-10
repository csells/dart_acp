import 'package:logging/logging.dart';
import 'capabilities.dart';
import 'providers/fs_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/terminal_provider.dart';

/// Collection of timeout knobs for ACP requests.
class AcpTimeouts {
  /// Create timeouts; all optional.
  const AcpTimeouts({
    this.initialize = const Duration(seconds: 15),
    this.prompt,
    this.permission,
  });

  /// Initialize call timeout.
  final Duration initialize;

  /// Optional prompt turn timeout (no hard timeout by default).
  final Duration? prompt;

  /// Optional permission prompt timeout.
  final Duration? permission;
}

/// Client configuration describing workspace, transport, providers, and caps.
class AcpConfig {
  /// Construct a configuration; call sites provide agent command/args/env.
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

  /// Absolute path to the workspace root used for FS jail and session cwd.
  final String workspaceRoot;

  /// Agent executable name/path (for stdio transport).
  final String? agentCommand;

  /// Arguments passed to the agent executable.
  final List<String> agentArgs;

  /// Environment variable overlay for the agent process.
  final Map<String, String> envOverrides;

  /// Client capability advertisement.
  final AcpCapabilities capabilities;

  /// Global MCP servers forwarded to session/new and session/load.
  final List<Map<String, dynamic>> mcpServers;

  /// Whether reads may escape the workspace root (yolo mode).
  final bool allowReadOutsideWorkspace;

  /// Request timeout configuration.
  final AcpTimeouts timeouts;

  /// Logger used by the client and transport.
  final Logger logger;

  /// Optional tap for raw outbound JSON-RPC frames (unprefixed JSONL).
  final void Function(String line)? onProtocolOut;

  /// Optional tap for raw inbound JSON-RPC frames (unprefixed JSONL).
  final void Function(String line)? onProtocolIn;

  /// File system provider used to fulfill fs/* requests.
  final FsProvider fsProvider;

  /// Permission provider used to answer session/request_permission.
  final PermissionProvider permissionProvider;

  /// Optional terminal provider to allow terminal lifecycle methods.
  final TerminalProvider? terminalProvider;
}
