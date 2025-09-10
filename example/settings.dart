import 'dart:convert';
import 'dart:io';

class AgentServerConfig {
  AgentServerConfig({
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  factory AgentServerConfig.fromJson(Map<String, dynamic> json) {
    final cmd = json['command'];
    if (cmd is! String || cmd.trim().isEmpty) {
      throw const FormatException(
        'agent_servers[*].command must be a non-empty string',
      );
    }
    final argsRaw = json['args'];
    final args = <String>[];
    if (argsRaw != null) {
      if (argsRaw is! List) {
        throw const FormatException(
          'agent_servers[*].args must be an array of strings',
        );
      }
      for (final e in argsRaw) {
        if (e is! String) {
          throw const FormatException(
            'agent_servers[*].args must be an array of strings',
          );
        }
        args.add(e);
      }
    }

    final envRaw = json['env'];
    final env = <String, String>{};
    if (envRaw != null) {
      if (envRaw is! Map) {
        throw const FormatException(
          'agent_servers[*].env must be an object of string to string',
        );
      }
      envRaw.forEach((k, v) {
        if (k is! String || v is! String) {
          throw const FormatException(
            'agent_servers[*].env must be an object of string to string',
          );
        }
        env[k] = v;
      });
    }

    return AgentServerConfig(command: cmd, args: args, env: env);
  }
  final String command;
  final List<String> args;
  final Map<String, String> env;
}

class Settings {
  Settings(this.agentServers, this.mcpServers);
  final Map<String, AgentServerConfig> agentServers;
  final List<McpServerConfig> mcpServers;

  static Future<Settings> loadFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('settings.json not found', path);
    }
    final text = file.readAsStringSync();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('settings.json must be a JSON object');
    }
    final serversRaw = decoded['agent_servers'];
    if (serversRaw is! Map) {
      throw const FormatException(
        'settings.json must contain an agent_servers object',
      );
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

    // Optional: top-level MCP servers
    final mcpRaw = decoded['mcp_servers'];
    final mcp = <McpServerConfig>[];
    if (mcpRaw != null) {
      if (mcpRaw is! List) {
        throw const FormatException('mcp_servers must be an array');
      }
      for (final e in mcpRaw) {
        if (e is! Map) {
          throw const FormatException('mcp_servers[*] must be an object');
        }
        mcp.add(McpServerConfig.fromJson(Map<String, dynamic>.from(e)));
      }
    }

    return Settings(map, mcp);
  }

  static Future<Settings> loadFromScriptDir() async {
    final scriptDir = File.fromUri(Platform.script).parent.path;
    final path = '$scriptDir${Platform.pathSeparator}settings.json';
    return loadFromFile(path);
  }
}

class McpServerConfig {
  McpServerConfig({
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final cmd = json['command'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException(
        'mcp_servers[*].name must be a non-empty string',
      );
    }
    if (cmd is! String || cmd.trim().isEmpty) {
      throw const FormatException(
        'mcp_servers[*].command must be a non-empty string',
      );
    }
    final argsRaw = json['args'];
    final args = <String>[];
    if (argsRaw != null) {
      if (argsRaw is! List) {
        throw const FormatException(
          'mcp_servers[*].args must be an array of strings',
        );
      }
      for (final e in argsRaw) {
        if (e is! String) {
          throw const FormatException(
            'mcp_servers[*].args must be an array of strings',
          );
        }
        args.add(e);
      }
    }
    final envRaw = json['env'];
    final env = <String, String>{};
    if (envRaw != null) {
      if (envRaw is! Map) {
        throw const FormatException(
          'mcp_servers[*].env must be an object of string to string',
        );
      }
      envRaw.forEach((k, v) {
        if (k is! String || v is! String) {
          throw const FormatException(
            'mcp_servers[*].env must be an object of string to string',
          );
        }
        env[k] = v;
      });
    }
    return McpServerConfig(name: name, command: cmd, args: args, env: env);
  }
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;
}
