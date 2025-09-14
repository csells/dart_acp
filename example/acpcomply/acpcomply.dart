// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_acp/dart_acp.dart';

import '../acpcli/settings.dart' as cli_settings;

/// Simple ACP compliance runner.
///
/// Reads tests from `example/acpcomply/compliance-tests/*.json`, loads
/// agents from settings.json (next to this CLI), and prints a Markdown
/// report to stdout.
Future<void> main([List<String> argv = const []]) async {
  final parser = ArgParser()
    ..addFlag(
      'list-tests',
      negatable: false,
      help: 'List available tests and exit',
    )
    ..addMultiOption(
      'test',
      abbr: 't',
      help: 'Run only the specified test id(s)',
    )
    ..addOption('agent', abbr: 'a', help: 'Run only the specified agent')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Print JSON-RPC I/O and expectation diagnostics');
  late ArgResults args;
  try {
    args = parser.parse(argv);
  } on Object catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    exit(2);
  }
  final settings = await cli_settings.Settings.loadFromScriptDir();
  final testsDir = File.fromUri(
    Platform.script,
  ).parent.uri.resolve('compliance-tests/').toFilePath();
  final testFiles =
      Directory(testsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsont'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (testFiles.isEmpty) {
    stderr.writeln('No tests found in $testsDir');
    exit(2);
  }

  if (args['list-tests'] == true) {
    for (final tf in testFiles) {
      try {
        final j = jsonDecode(await tf.readAsString()) as Map<String, dynamic>;
        final id = tf.uri.pathSegments.last.replaceAll('.jsont', '');
        final title = (j['title'] ?? '').toString();
        stdout.writeln(title.isEmpty ? id : '$id - $title');
      } on Object {
        stdout.writeln(tf.uri.pathSegments.last.replaceAll('.jsont', ''));
      }
    }
    return;
  }

  final onlyAgent = args['agent'] as String?;
  final agents = onlyAgent == null
      ? settings.agentServers
      : {
          if (settings.agentServers.containsKey(onlyAgent))
            onlyAgent: settings.agentServers[onlyAgent]!,
        };
  if (onlyAgent != null && agents.isEmpty) {
    stderr.writeln('Error: agent "$onlyAgent" not found in settings.json');
    exit(2);
  }

  final onlyTests = (args['test'] as List?)?.cast<String>() ?? const <String>[];
  final selectedTestFiles = onlyTests.isEmpty
      ? testFiles
      : testFiles.where((f) {
          final id = f.uri.pathSegments.last.replaceAll('.jsont', '');
          return onlyTests.contains(id);
        }).toList();
  if (onlyTests.isNotEmpty && selectedTestFiles.isEmpty) {
    stderr.writeln('Error: requested tests not found: ${onlyTests.join(', ')}');
    exit(2);
  }
  final results = <String, Map<String, String>>{}; // agent -> testId -> verdict

  final isVerbose = args['verbose'] == true;

  for (final entry in agents.entries) {
    final agentName = entry.key;
    final agentCfg = entry.value;
    stdout.writeln('# Running ACP compliance for $agentName');
    final agentResults = <String, String>{};

    for (final tf in selectedTestFiles) {
      // Read template file and interpolate variables
      var testContent = await tf.readAsString();

      // Interpolate common variables
      testContent = testContent
          .replaceAll(r'${protocolVersionDefault}', '1')
          .replaceAll(r'${clientCapabilitiesDefault}', jsonEncode({
            'fs': {'readTextFile': true, 'writeTextFile': true},
            'terminal': true,
          }));

      final testJson = jsonDecode(testContent) as Map<String, dynamic>;
      final verdict = await _runSingleTest(
        agentName,
        agentCfg,
        testJson,
        verbose: isVerbose,
      );
      final testId = tf.uri.pathSegments.last.replaceAll('.jsont', '');
      agentResults[testId] = verdict;
      stdout.writeln('- $testId: $verdict');
    }

    results[agentName] = agentResults;
    stdout.writeln();
  }

  _printMarkdownReport(results);
}

Future<String> _runSingleTest(
  String agentName,
  cli_settings.AgentServerConfig agentCfg,
  Map<String, dynamic> test, {
  required bool verbose,
}) async {
  final sandbox = await Directory.systemTemp.createTemp('acpcomply-');
  try {
    // Create sandbox files
    final sandboxDecl = test['sandbox'] as Map<String, dynamic>?;
    if (sandboxDecl != null) {
      final files =
          (sandboxDecl['files'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      for (final f in files) {
        final p = f['path'] as String;
        final file = File('${sandbox.path}${Platform.pathSeparator}$p');
        await file.parent.create(recursive: true);
        if (f.containsKey('text')) {
          await file.writeAsString(f['text'] as String);
        } else if (f.containsKey('base64')) {
          await file.writeAsBytes(base64.decode(f['base64'] as String));
        } else {
          await file.create();
        }
      }
    }

    // Extract per-test MCP servers if provided in steps
    final stepsArr = (test['steps'] as List).cast<Map<String, dynamic>>();
    var mcpServers = const <Map<String, dynamic>>[];
    for (final s in stepsArr) {
      final ns = s['newSession'] as Map<String, dynamic>?;
      if (ns != null && ns['mcpServers'] is List) {
        mcpServers = (ns['mcpServers'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
        break;
      }
    }

    // Build config (per test)
    final init = test['init'] as Map<String, dynamic>?;
    final capsOverride = init?['clientCapabilities'] as Map<String, dynamic>?;
    final fsCaps = capsOverride?['fs'] as Map<String, dynamic>?;
    final readCap = fsCaps == null || (fsCaps['readTextFile'] as bool? ?? true);
    final writeCap =
        fsCaps == null || (fsCaps['writeTextFile'] as bool? ?? true);

    final inbound = <Map<String, dynamic>>[];
    void onIn(String line) {
      if (verbose) stdout.writeln('[IN ] $line');
      try {
        inbound.add(jsonDecode(line) as Map<String, dynamic>);
      } on Object {
        // Ignore non-JSON lines (agent logs)
      } 
   }

    void onOut(String line) {
      if (verbose) stdout.writeln('[OUT] $line');
    }

    // Pre-script permission outcomes
    final scriptedPermissionOutcomes = _collectScriptedPermissionOutcomes(test);

    final config = AcpConfig(
      agentCommand: agentCfg.command,
      agentArgs: agentCfg.args,
      envOverrides: agentCfg.env,
      capabilities: AcpCapabilities(
        fs: FsCapabilities(readTextFile: readCap, writeTextFile: writeCap),
      ),
      // Use default providers so the agent can read/write/execute in sandbox
      fsProvider: const _DummyFsProvider(),
      permissionProvider: DefaultPermissionProvider(
        onRequest: (opts) async {
          if (scriptedPermissionOutcomes.isNotEmpty) {
            return scriptedPermissionOutcomes.removeAt(0);
          }
          // Default: allow
          return PermissionOutcome.allow;
        },
      ),
      terminalProvider: DefaultTerminalProvider(),
      onProtocolIn: onIn,
      onProtocolOut: onOut,
      mcpServers: mcpServers,
    );
    final client = await AcpClient.start(config: config);

    // Initialize if not sent by the test
    final sendsInit = stepsArr.any(
      (s) => (s['send'] as Map<String, dynamic>?)?['method'] == 'initialize',
    );
    var agentCaps = const <String, dynamic>{};
    if (!sendsInit) {
      final initR = await client.initialize();
      agentCaps = initR.agentCapabilities ?? const {};
    }

    // Evaluate preconditions (agent capabilities) if present
    final preconditions =
        (test['preconditions'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    for (final pre in preconditions) {
      final capPath = pre['agentCap'] as String?;
      if (capPath != null) {
        final want = pre['mustBe'] as bool? ?? true;
        final actual = _readPath(agentCaps, capPath);
        if ((actual == true) != want) {
          await client.dispose();
          return 'NA';
        }
      }
    }

    final steps = stepsArr;
    final vars = <String, String>{
      'sandbox': sandbox.path,
      'protocolVersionDefault': '1',
      'clientCapabilitiesDefault': jsonEncode({
        'fs': {'readTextFile': true, 'writeTextFile': true},
        'terminal': true,
      }),
    };

    Future<bool> waitExpect(Map<String, dynamic> expect) async {
      final timeoutMs = (expect['timeoutMs'] as num?)?.toInt() ?? 10000;
      final messages = (expect['messages'] as List)
          .cast<Map<String, dynamic>>();
      final start = DateTime.now();
      final matched = List<bool>.filled(messages.length, false);
      while (DateTime.now().difference(start).inMilliseconds < timeoutMs) {
        for (var i = 0; i < messages.length; i++) {
          if (matched[i]) continue;
          final env = _interpolateVars(messages[i], vars);
          final resp = env['response'] as Map<String, dynamic>?;
          final notif = env['notification'] as Map<String, dynamic>?;
          final clientReq = env['clientRequest'] as Map<String, dynamic>?;
          if (resp != null) {
            // Treat id like any other field (regex-capable) via partial match
            final ok = inbound.any((m) => _partialMatch(m, resp));
            matched[i] = ok;
          } else if (notif != null) {
            final ok = inbound.any(
              (m) => m['method'] == notif['method'] && _partialMatch(m, notif),
            );
            matched[i] = ok;
          } else if (clientReq != null) {
            final ok = inbound.any(
              (m) =>
                  m['method'] == clientReq['method'] &&
                  _partialMatch(m, clientReq),
            );
            matched[i] = ok;
            // NOTE: replies are handled by providers; test-specified replies
            // are ignored here
          }
        }
        if (matched.every((e) => e)) return true;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (verbose) {
        for (var i = 0; i < messages.length; i++) {
          if (!matched[i]) {
            stdout.writeln('[EXPECT NOT MET] ${jsonEncode(messages[i])}');
          }
        }
        final tail = inbound.length > 10
            ? inbound.sublist(inbound.length - 10)
            : inbound;
        for (final m in tail) {
          stdout.writeln('[SEEN] ${jsonEncode(m)}');
        }
      }
      return false;
    }

    Future<bool> waitForbid(Map<String, dynamic> forbid) async {
      final timeoutMs = (forbid['timeoutMs'] as num?)?.toInt() ?? 5000;
      final methods = (forbid['methods'] as List).cast<String>();
      final startSize = inbound.length;
      await Future.delayed(Duration(milliseconds: timeoutMs));
      final slice = inbound.sublist(startSize);
      Map<String, dynamic>? found;
      for (final m in slice) {
        if (methods.contains(m['method'])) {
          found = m;
          break;
        }
      }
      final hit = found != null;
      if (hit && verbose) {
        stdout.writeln('[FORBID HIT] ${found['method']}: ${jsonEncode(found)}');
      }
      return !hit;
    }

    for (final step in steps) {
      if (step.containsKey('delayMs')) {
        await Future.delayed(
          Duration(milliseconds: (step['delayMs'] as num).toInt()),
        );
        continue;
      }
      if (step.containsKey('newSession')) {
        final sid = await client.newSession(sandbox.path);
        vars['sessionId'] = sid;
        continue;
      }
      if (step.containsKey('send')) {
        final send = step['send'] as Map<String, dynamic>;
        final method = send['method'] as String;
        if (method == 'initialize') {
          final params = _interpolateVars(
            send['params'] as Map<String, dynamic>? ?? const {},
            vars,
          );
          await client.sendRaw('initialize', params);
        } else if (method == 'session/prompt') {
          final params = send['params'] as Map<String, dynamic>? ?? const {};
          final sid = params['sessionId'] as String? ?? vars['sessionId'];
          final prompt = params['prompt'];
          if (sid == null) {
            await client.dispose();
            return 'FAIL';
          }
          if (prompt is List || prompt is Map) {
            final rawParams = _interpolateVars(params, vars);
            await client.sendRaw('session/prompt', rawParams);
          } else {
            final content = _stringifyPrompt(prompt, sandbox.path);
            if (content == null) {
              await client.dispose();
              return 'FAIL';
            }
            unawaited(client.prompt(sessionId: sid, content: content).drain());
          }
        } else if (method == 'session/cancel') {
          final params = send['params'] as Map<String, dynamic>? ?? const {};
          final sid = params['sessionId'] as String? ?? vars['sessionId'];
          if (sid == null) {
            await client.dispose();
            return 'FAIL';
          }
          await client.cancel(sessionId: sid);
        } else if (method == 'session/set_mode') {
          final params = send['params'] as Map<String, dynamic>? ?? const {};
          final sid = params['sessionId'] as String? ?? vars['sessionId'];
          final modeId = params['modeId'] as String?;
          if (sid == null || modeId == null) {
            await client.dispose();
            return 'FAIL';
          }
          await client.setMode(sessionId: sid, modeId: modeId);
        } else if (method == 'session/load') {
          final params = send['params'] as Map<String, dynamic>? ?? const {};
          final sid = params['sessionId'] as String? ?? vars['sessionId'];
          final cwd = params['cwd'] as String? ?? sandbox.path;
          await client.loadSession(sessionId: sid!, workspaceRoot: cwd);
        } else if (method == 'session/new') {
          // handled by newSession step
        } else {
          final params = _interpolateVars(
            send['params'] as Map<String, dynamic>? ?? const {},
            vars,
          );
          await client.sendRaw(method, params);
        }
        continue;
      }
      if (step.containsKey('expect')) {
        final ok = await waitExpect(step['expect'] as Map<String, dynamic>);
        if (!ok) {
          await client.dispose();
          return 'FAIL';
        }
        continue;
      }
      if (step.containsKey('forbid')) {
        final ok = await waitForbid(step['forbid'] as Map<String, dynamic>);
        if (!ok) {
          await client.dispose();
          return 'FAIL';
        }
        continue;
      }
    }

    await client.dispose();
    return 'PASS';
  } on Exception catch (_) {
    return 'FAIL';
  } finally {
    await sandbox.delete(recursive: true);
  }
}

String? _stringifyPrompt(dynamic prompt, String sandboxPath) {
  if (prompt is String) return prompt;
  if (prompt is List) {
    final parts = <String>[];
    for (final b in prompt) {
      if (b is Map<String, dynamic>) {
        if (b['type'] == 'text') {
          parts.add(b['text']?.toString() ?? '');
        } else if (b['type'] == 'resource_link') {
          final uri = (b['uri']?.toString() ?? '').replaceAll('file://', '');
          parts.add(' @$uri ');
        } else {
          // Other content types not supported in freeform text
        }
      }
    }
    return parts.join('\n');
  }
  return null;
}

bool _partialMatch(Map<String, dynamic> actual, Map<String, dynamic> expected) {
  for (final entry in expected.entries) {
    final k = entry.key;
    final v = entry.value;
    if (!actual.containsKey(k)) return false;
    final av = actual[k];
    if (v is Map<String, dynamic> && av is Map<String, dynamic>) {
      if (!_partialMatch(Map<String, dynamic>.from(av), v)) return false;
    } else if (v is List && av is List) {
      // subset contains
      for (final want in v) {
        final matched = av.any((got) {
          if (want is Map && got is Map) {
            return _partialMatch(
              Map<String, dynamic>.from(got),
              Map<String, dynamic>.from(want),
            );
          }
          return _matchLeaf(got, want);
        });
        if (!matched) return false;
      }
    } else {
      if (!_matchLeaf(av, v)) return false;
    }
  }
  return true;
}

bool _matchLeaf(dynamic actual, dynamic pattern) {
  final as = _stringify(actual);
  final ps = _stringify(pattern);
  try {
    return RegExp(ps).hasMatch(as);
  } on Exception catch (_) {
    return as == ps;
  }
}

String _stringify(dynamic v) => v == null ? 'null' : v.toString();

dynamic _readPath(Map<String, dynamic> obj, String path) {
  dynamic cur = obj;
  for (final part in path.split('.')) {
    if (cur is Map<String, dynamic>) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

Map<String, dynamic> _interpolateVars(
  Map<String, dynamic> params,
  Map<String, String> vars,
) {
  dynamic subst(dynamic v) {
    if (v is String) {
      return v.replaceAllMapped(
        RegExp(r'\$\{([a-zA-Z0-9_]+)\}'),
        (m) => vars[m.group(1)] ?? m.group(0)!,
      );
    }
    if (v is Map<String, dynamic>) {
      return v.map((k, vv) => MapEntry(k, subst(vv)));
    }
    if (v is List) {
      return v.map(subst).toList();
    }
    return v;
  }

  return Map<String, dynamic>.from(subst(params));
}

class _DummyFsProvider implements FsProvider {
  const _DummyFsProvider();

  @override
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    throw UnimplementedError('Handled by SessionManager');
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    throw UnimplementedError('Handled by SessionManager');
  }
}

List<PermissionOutcome> _collectScriptedPermissionOutcomes(
  Map<String, dynamic> test,
) {
  final outcomes = <PermissionOutcome>[];
  final steps =
      (test['steps'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final step in steps) {
    final expect = step['expect'] as Map<String, dynamic>?;
    if (expect == null) continue;
    final messages =
        (expect['messages'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final msg in messages) {
      final cr = msg['clientRequest'] as Map<String, dynamic>?;
      if (cr == null) continue;
      if (cr['method'] == 'session/request_permission') {
        final reply = msg['reply'] as Map<String, dynamic>?;
        if (reply != null) {
          final outcome =
              ((reply['result'] as Map?)?['outcome'] as Map?)?['outcome']
                  as String?;
          final optionId =
              ((reply['result'] as Map?)?['outcome'] as Map?)?['optionId']
                  as String?;
          if (outcome == 'cancelled') {
            outcomes.add(PermissionOutcome.cancelled);
          } else if (outcome == 'selected') {
            if (optionId != null && optionId.contains('allow')) {
              outcomes.add(PermissionOutcome.allow);
            } else {
              outcomes.add(PermissionOutcome.deny);
            }
          }
        }
      }
    }
  }
  return outcomes;
}

void _printMarkdownReport(Map<String, Map<String, String>> results) {
  final agents = results.keys.toList()..sort();
  final allTestIds = <String>{};
  for (final r in results.values) {
    allTestIds.addAll(r.keys);
  }
  final tests = allTestIds.toList()..sort();

  stdout.writeln('# ACP Compliance Report');
  stdout.writeln();
  stdout.writeln('Methodology: sandboxed tests via AcpClient over stdio.');
  stdout.writeln();

  // Header
  final header = ['Compliance Area', ...agents];
  stdout.writeln('| ${header.join(' | ')} |');
  stdout.writeln('|${List.filled(header.length, '---').join('|')}|');
  for (final t in tests) {
    final row = <String>[];
    row.add(t);
    for (final a in agents) {
      row.add(results[a]?[t] ?? 'NA');
    }
    stdout.writeln('| ${row.join(' | ')} |');
  }
}
