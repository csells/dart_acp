import 'package:logging/logging.dart';
import 'capabilities.dart';
import 'providers/fs_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/credentials_provider.dart';
import 'providers/terminal_provider.dart';

class AcpTimeouts {
  final Duration initialize;
  final Duration? prompt; // no hard timeout by default
  final Duration? permission; // host may set

  const AcpTimeouts({
    this.initialize = const Duration(seconds: 15),
    this.prompt,
    this.permission,
  });
}

class AcpConfig {
  final String workspaceRoot; // absolute path required
  final String? agentCommand; // default: claude-code-acp (with npx fallback)
  final List<String> agentArgs;
  final Map<String, String> envOverrides; // additive only
  final AcpCapabilities capabilities;
  final AcpTimeouts timeouts;
  final Logger logger;

  // Providers
  final FsProvider fsProvider;
  final PermissionProvider permissionProvider;
  final CredentialsProvider? credentialsProvider;
  final TerminalProvider? terminalProvider;

  AcpConfig({
    required this.workspaceRoot,
    this.agentCommand,
    this.agentArgs = const [],
    this.envOverrides = const {},
    this.capabilities = const AcpCapabilities(),
    this.timeouts = const AcpTimeouts(),
    Logger? logger,
    FsProvider? fsProvider,
    PermissionProvider? permissionProvider,
    this.credentialsProvider,
    this.terminalProvider,
  }) : logger = logger ?? Logger('dart_acp'),
       fsProvider =
           fsProvider ?? DefaultFsProvider(workspaceRoot: workspaceRoot),
       permissionProvider =
           permissionProvider ?? const DefaultPermissionProvider();
}
