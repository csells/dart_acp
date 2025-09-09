class AcpCapabilities {
  const AcpCapabilities({this.fs = const FsCapabilities()});
  final FsCapabilities fs;

  Map<String, dynamic> toJson() {
    // Only advertise standard capabilities per ACP; avoid custom keys.
    return {'fs': fs.toJson()};
  }
}

class FsCapabilities {
  const FsCapabilities({this.readTextFile = true, this.writeTextFile = false});
  final bool readTextFile;
  final bool writeTextFile;

  Map<String, dynamic> toJson() => {
    'readTextFile': readTextFile,
    'writeTextFile': writeTextFile,
  };
}
