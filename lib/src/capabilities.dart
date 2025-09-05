class AcpCapabilities {
  final FsCapabilities fs;
  final bool terminal;

  const AcpCapabilities({
    this.fs = const FsCapabilities(),
    this.terminal = false,
  });

  Map<String, dynamic> toJson() {
    return {'fs': fs.toJson(), if (terminal) 'terminal': true};
  }
}

class FsCapabilities {
  final bool readTextFile;
  final bool writeTextFile;

  const FsCapabilities({this.readTextFile = true, this.writeTextFile = false});

  Map<String, dynamic> toJson() => {
    if (readTextFile) 'readTextFile': true,
    if (writeTextFile) 'writeTextFile': true,
  };
}
