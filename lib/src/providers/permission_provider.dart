enum PermissionOutcome { allow, deny, cancelled }

class PermissionOptions {
  final String title;
  final String rationale;
  final List<String> options; // display-only options from agent
  final String sessionId;
  final String toolName;
  final String? toolKind; // read/edit/execute/etc

  PermissionOptions({
    required this.title,
    required this.rationale,
    required this.options,
    required this.sessionId,
    required this.toolName,
    this.toolKind,
  });
}

abstract class PermissionProvider {
  Future<PermissionOutcome> request(PermissionOptions options);
}

typedef PermissionCallback =
    Future<PermissionOutcome> Function(PermissionOptions options);

class DefaultPermissionProvider implements PermissionProvider {
  final PermissionCallback? onRequest;
  const DefaultPermissionProvider({this.onRequest});

  @override
  Future<PermissionOutcome> request(PermissionOptions options) async {
    if (onRequest != null) {
      return await onRequest!(options);
    }
    // Defaults: allow read; deny write/execute; others deny.
    final lowerName = options.toolName.toLowerCase();
    final lowerKind = options.toolKind?.toLowerCase();
    if (lowerKind == 'read' || lowerName.contains('read')) {
      return PermissionOutcome.allow;
    }
    return PermissionOutcome.deny;
  }
}
