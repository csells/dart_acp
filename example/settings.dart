import 'dart:convert';
import 'dart:io';

class AgentServerConfig {
  final String command;
  final List<String> args;
  final Map<String, String> env;

  AgentServerConfig({
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  factory AgentServerConfig.fromJson(Map<String, dynamic> json) {
    final cmd = json['command'];
    if (cmd is! String || cmd.trim().isEmpty) {
      throw const FormatException('agent_servers[*].command must be a non-empty string');
    }
    final argsRaw = json['args'];
    final args = <String>[];
    if (argsRaw != null) {
      if (argsRaw is! List) {
        throw const FormatException('agent_servers[*].args must be an array of strings');
      }
      for (final e in argsRaw) {
        if (e is! String) {
          throw const FormatException('agent_servers[*].args must be an array of strings');
        }
        args.add(e);
      }
    }

    final envRaw = json['env'];
    final env = <String, String>{};
    if (envRaw != null) {
      if (envRaw is! Map) {
        throw const FormatException('agent_servers[*].env must be an object of string to string');
      }
      envRaw.forEach((k, v) {
        if (k is! String || v is! String) {
          throw const FormatException('agent_servers[*].env must be an object of string to string');
        }
        env[k] = v;
      });
    }

    return AgentServerConfig(command: cmd, args: args, env: env);
  }
}

class Settings {
  final Map<String, AgentServerConfig> agentServers;

  Settings(this.agentServers);

  static Future<Settings> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('settings.json not found', path);
    }
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('settings.json must be a JSON object');
    }
    final serversRaw = decoded['agent_servers'];
    if (serversRaw is! Map) {
      throw const FormatException('settings.json must contain an agent_servers object');
    }
    final map = <String, AgentServerConfig>{};
    serversRaw.forEach((key, value) {
      if (key is! String) {
        throw const FormatException('agent_servers keys must be strings');
      }
      if (value is! Map) {
        throw const FormatException('agent_servers[*] must be an object');
      }
      map[key] = AgentServerConfig.fromJson(Map<String, dynamic>.from(value));
    });
    if (map.isEmpty) {
      throw const FormatException('agent_servers must have at least one entry');
    }
    return Settings(map);
  }

  static Future<Settings> loadFromScriptDir() async {
    final scriptDir = File.fromUri(Platform.script).parent.path;
    final path = '$scriptDir${Platform.pathSeparator}settings.json';
    return loadFromFile(path);
  }
}
