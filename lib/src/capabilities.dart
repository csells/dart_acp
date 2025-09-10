/// Advertised client capabilities in ACP initialization.
class AcpCapabilities {
  /// Create capabilities; defaults to read-only file system support.
  const AcpCapabilities({this.fs = const FsCapabilities()});

  /// File system capability flags.
  final FsCapabilities fs;

  /// Convert to JSON payload for the `initialize` request.
  Map<String, dynamic> toJson() => {
    // Only advertise standard capabilities per ACP; avoid custom keys.
    'fs': fs.toJson(),
  };
}

/// File system capability flags for client-provided fs methods.
class FsCapabilities {
  /// By default, allow reading but disallow writing.
  const FsCapabilities({this.readTextFile = true, this.writeTextFile = false});

  /// Whether `fs/read_text_file` is available.
  final bool readTextFile;

  /// Whether `fs/write_text_file` is available.
  final bool writeTextFile;

  /// JSON representation used in `clientCapabilities.fs`.
  Map<String, dynamic> toJson() => {
    'readTextFile': readTextFile,
    'writeTextFile': writeTextFile,
  };
}
