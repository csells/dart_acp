class AcpCapabilities {
  final FsCapabilities fs;

  const AcpCapabilities({
    this.fs = const FsCapabilities(),
  });

  Map<String, dynamic> toJson() {
    // Only advertise standard capabilities per ACP; avoid custom keys.
    return {'fs': fs.toJson()};
  }
}

class FsCapabilities {
  final bool readTextFile;
  final bool writeTextFile;

  const FsCapabilities({this.readTextFile = true, this.writeTextFile = false});

  Map<String, dynamic> toJson() => {
    'readTextFile': readTextFile,
    'writeTextFile': writeTextFile,
  };
}
