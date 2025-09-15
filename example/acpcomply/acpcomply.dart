// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_acp/dart_acp.dart';

import '../acpcli/settings.dart' as cli_settings;

/// Simple ACP compliance runner.
///
/// Reads tests from `example/acpcomply/compliance-tests/*.json`, loads agents
/// from settings.json (next to this CLI), and prints a Markdown report to
/// stdout.
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
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Print JSON-RPC I/O and expectation diagnostics',
    );
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
  final isVerbose = args['verbose'] == true;

  // Pre-validate all selected tests before running any agents
  for (final tf in selectedTestFiles) {
    late final Map<String, dynamic> j;
    try {
      final raw = await tf.readAsString();
      final interpolated = raw
          .replaceAll(r'${protocolVersionDefault}', '1')
          .replaceAll(
            r'${clientCapabilitiesDefault}',
            jsonEncode({
              'fs': {'readTextFile': true, 'writeTextFile': true},
              'terminal': true,
            }),
          );
      j = jsonDecode(interpolated) as Map<String, dynamic>;
    } on Object {
      throw StateError(
        'JSONT schema violation in '
        '${tf.uri.pathSegments.last}: invalid JSON',
      );
    }
    final id = tf.uri.pathSegments.last.replaceAll('.jsont', '');
    final title = (j['title'] as String?)?.trim() ?? '';
    final description = (j['description'] as String?)?.trim() ?? '';
    final docsList =
        (j['docs'] as List?)?.whereType<String>().toList() ?? const [];
    final steps = (j['steps'] as List?)?.cast<Map<String, dynamic>>();

    final issues = <String>[];
    if (title.isEmpty) issues.add('title: expected non-empty string');
    if (description.isEmpty) {
      issues.add('description: expected non-empty string');
    }
    if (docsList.isEmpty || docsList.any((d) => d.trim().isEmpty)) {
      issues.add('docs: expected non-empty array of non-empty strings');
    }
    if (steps == null || steps.isEmpty) {
      issues.add('steps: expected non-empty array of step objects');
    }
    if (issues.isNotEmpty) {
      throw StateError('JSONT schema violation in $id: ${issues.join('; ')}');
    }
  }

  for (final entry in agents.entries) {
    final agentName = entry.key;
    final agentCfg = entry.value;

    // Probe and print agent summary first
    final profile = await _collectAgentProfile(agentCfg);

    // Agent header (printed once per agent)
    stdout.writeln('# $agentName compliance results');
    if (profile.protocolVersion != null) {
      stdout.writeln('- protocolVersion: ${profile.protocolVersion}');
    }
    if (profile.agentCapabilities.isNotEmpty) {
      stdout.writeln(
        '- agentCapabilities: ${jsonEncode(profile.agentCapabilities)}',
      );
    }
    if (profile.authMethods.isNotEmpty) {
      stdout.writeln('- authMethods: ${jsonEncode(profile.authMethods)}');
    }
    if (profile.modeNames.isNotEmpty || profile.modes.isNotEmpty) {
      final modesList =
          profile.modeNames.entries
              .map(
                (e) => '${e.key}${e.value.isNotEmpty ? ' (${e.value})' : ''}',
              )
              .toList()
            ..sort();
      final extras = profile.modes.difference(profile.modeNames.keys.toSet());
      final combined = [...modesList, ...extras];
      stdout.writeln('- modes: [${combined.join(', ')}]');
    }
    if (profile.commands.isNotEmpty) {
      final cmds = profile.commands.toList()..sort();
      stdout.writeln('- commands: [${cmds.join(', ')}]');
    }
    stdout.writeln();

    for (final tf in selectedTestFiles) {
      // Read template file and interpolate variables
      var testContent = await tf.readAsString();

      // Interpolate common variables
      testContent = testContent
          .replaceAll(r'${protocolVersionDefault}', '1')
          .replaceAll(
            r'${clientCapabilitiesDefault}',
            jsonEncode({
              'fs': {'readTextFile': true, 'writeTextFile': true},
              'terminal': true,
            }),
          );

      final testJson = jsonDecode(testContent) as Map<String, dynamic>;
      final testId = tf.uri.pathSegments.last.replaceAll('.jsont', '');
      final title = (testJson['title'] as String?)?.trim();
      final description =
          (testJson['description'] as String?)?.trim() ??
          (testJson['title'] as String?)?.trim() ??
          testId;

      // Print per-test header before running (progress visibility)
      final headerTitle = title ?? testId;
      stdout.writeln('## $headerTitle');
      stdout.writeln('id: $testId');
      stdout.writeln('agent: $agentName');
      stdout.writeln('description: $description');

      // Run the test
      final report = await _runSingleTest(
        agentName,
        agentCfg,
        testJson,
        profile: profile,
        verbose: isVerbose,
        testId: testId,
        title: headerTitle,
        description: description,
      );

      // Print result after running
      stdout.writeln('status: ${report.status}');
      if (report.status == 'NA' && report.naReason != null) {
        stdout.writeln('na_reason: ${report.naReason}');
      }

      if (report.status == 'FAIL') {
        // Unmet expectations / forbid hits
        if (report.unmetExpectations.isNotEmpty) {
          stdout.writeln();
          stdout.writeln('Unmet expectations:');
          for (final unmet in report.unmetExpectations) {
            if (unmet.kind.isNotEmpty) {
              stdout.writeln('- kind: ${unmet.kind}');
            }
            stdout.writeln('- expected: ${jsonEncode(unmet.expected)}');
            if (unmet.closestActual != null) {
              stdout.writeln(
                '- closest_actual: ${jsonEncode(unmet.closestActual)}',
              );
            }
            if (unmet.diff.isNotEmpty) {
              stdout.writeln('- diff:');
              for (final d in unmet.diff) {
                stdout.writeln('  - $d');
              }
            }
          }
        }
        if (report.forbidViolation != null) {
          stdout.writeln();
          stdout.writeln('Forbidden request observed:');
          stdout.writeln('- method: ${report.forbidViolation!['method']}');
          stdout.writeln(
            '- message: ${jsonEncode(report.forbidViolation!['message'])}',
          );
        }

        // I/O context omitted by request
      }

      // Links (only for failures)
      if (report.status == 'FAIL') {
        final links = report.links;
        if (links.isNotEmpty) {
          stdout.writeln();
          stdout.writeln('links:');
          for (final l in links) {
            stdout.writeln('- $l');
          }
        }
      }

      stdout.writeln();
    }
  }
}

class _UnmetExpectation {
  _UnmetExpectation({
    required this.expected,
    required this.kind,
    this.closestActual,
    this.diff = const <String>[],
  });

  final Map<String, dynamic> expected;
  final String kind; // response | notification | clientRequest
  final Map<String, dynamic>? closestActual;
  final List<String> diff;
}

class _TestReport {
  _TestReport({
    required this.agentName,
    required this.testId,
    required this.title,
    required this.description,
    required this.status,
    required List<String> links,
    this.naReason,
    this.unmetExpectations = const <_UnmetExpectation>[],
    this.forbidViolation,
    this.clientMessages = const <String>[],
    this.agentMessages = const <String>[],
  }) : _links = links;

  final String agentName;
  final String testId;
  final String title;
  final String description;
  final String status; // PASS | FAIL | NA
  final String? naReason;
  final List<_UnmetExpectation> unmetExpectations;
  final Map<String, dynamic>? forbidViolation;
  final List<String> clientMessages; // serialized JSONL or raw
  final List<String> agentMessages; // serialized JSONL or raw
  List<String> get links => _links;
  final List<String> _links;
}

class _AgentProfile {
  Map<String, dynamic> agentCapabilities = {};
  List<Map<String, dynamic>> authMethods = [];
  String? protocolVersion;
  // Mode id -> name (if known)
  final Map<String, String> modeNames = {};
  final Set<String> modes = <String>{};
  final Set<String> commands = <String>{};
}

Future<_AgentProfile> _collectAgentProfile(
  cli_settings.AgentServerConfig agentCfg,
) async {
  final profile = _AgentProfile();
  final sandbox = await Directory.systemTemp.createTemp('acpcomply-probe-');
  try {
    final inbound = <Map<String, dynamic>>[];
    void onIn(String line) {
      try {
        inbound.add(jsonDecode(line) as Map<String, dynamic>);
      } on Object {
        // ignore non-JSON
      }
    }

    void onOut(String line) {}

    final config = AcpConfig(
      agentCommand: agentCfg.command,
      agentArgs: agentCfg.args,
      envOverrides: agentCfg.env,
      capabilities: const AcpCapabilities(
        fs: FsCapabilities(readTextFile: true, writeTextFile: true),
      ),
      fsProvider: const _DummyFsProvider(),
      permissionProvider: const DefaultPermissionProvider(),
      terminalProvider: DefaultTerminalProvider(),
      onProtocolIn: onIn,
      onProtocolOut: onOut,
      mcpServers: const <Map<String, dynamic>>[],
    );

    final client = await AcpClient.start(config: config);
    try {
      final initR = await client.initialize();
      profile.agentCapabilities = initR.agentCapabilities ?? const {};
      profile.authMethods = (initR.authMethods ?? const [])
          .map<Map<String, dynamic>>(Map<String, dynamic>.from)
          .toList();
      profile.protocolVersion = '${initR.protocolVersion}';

      // Try to discover modes/commands by creating a session and listening
      // briefly
      final sid = await client.newSession(sandbox.path);
      final modes = client.sessionModes(sid);
      if (modes != null) {
        if (modes.currentModeId != null) {
          profile.modes.add(modes.currentModeId!);
        }
        for (final m in modes.availableModes) {
          profile.modes.add(m.id);
          if (m.name.isNotEmpty) profile.modeNames[m.id] = m.name;
        }
      }
      final sub = client.sessionUpdates(sid).listen((u) {
        if (u is AvailableCommandsUpdate) {
          for (final c in u.commands) {
            profile.commands.add(c.name);
          }
        } else if (u is ModeUpdate) {
          if (u.currentModeId.isNotEmpty) profile.modes.add(u.currentModeId);
        }
      });
      // Allow short window for agents that eagerly send commands on session/new
      await Future.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
    } finally {
      await client.dispose();
    }
  } on Object catch (_) {
    // ignore probe failures; summary stays minimal
  } finally {
    try {
      await sandbox.delete(recursive: true);
    } on Object catch (_) {}
  }
  return profile;
}

Future<_TestReport> _runSingleTest(
  String agentName,
  cli_settings.AgentServerConfig agentCfg,
  Map<String, dynamic> test, {
  required _AgentProfile profile,
  required bool verbose,
  required String testId,
  required String title,
  required String description,
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

    final policy =
        (init?['permissionPolicy'] as String?)?.toLowerCase().trim() ?? 'yolo';

    PermissionOutcome decideByPolicy(PermissionOptions opts) {
      final kind = (opts.toolKind ?? '').toLowerCase();
      final name = opts.toolName.toLowerCase();
      switch (policy) {
        case 'none':
          return PermissionOutcome.deny;
        case 'read':
          if (kind == 'read' || name.contains('read')) {
            return PermissionOutcome.allow;
          }
          return PermissionOutcome.deny;
        case 'write':
          if (kind == 'read' ||
              kind == 'write' ||
              name.contains('read') ||
              name.contains('write')) {
            return PermissionOutcome.allow;
          }
          return PermissionOutcome.deny;
        case 'yolo':
        default:
          return PermissionOutcome.allow;
      }
    }

    final inbound = <Map<String, dynamic>>[]; // parsed inbound JSON
    final inboundLines = <String>[]; // all agent lines as strings
    void onIn(String line) {
      if (verbose) stdout.writeln('[IN ] $line');
      inboundLines.add(line);
      try {
        inbound.add(jsonDecode(line) as Map<String, dynamic>);
      } on Object {
        // Keep non-JSON lines for context
      }
    }

    final outbound = <Map<String, dynamic>>[]; // parsed outbound JSON
    final outboundLines = <String>[]; // all client lines as strings
    void onOut(String line) {
      if (verbose) stdout.writeln('[OUT] $line');
      outboundLines.add(line);
      try {
        outbound.add(jsonDecode(line) as Map<String, dynamic>);
      } on Object {
        // Keep non-JSON lines for context
      }
    }

    // No scripted permission outcomes; use policy-only decisions

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
          final sid = opts.sessionId;
          const totalMs = 800;
          const stepMs = 50;
          var waited = 0;
          while (waited < totalMs) {
            final cancelled = outbound.any((m) {
              try {
                if (m['method'] != 'session/cancel') return false;
                final p = m['params'] as Map<String, dynamic>?;
                return (p?['sessionId'] as String?) == sid;
              } on Object {
                return false;
              }
            });
            if (cancelled) return PermissionOutcome.cancelled;
            await Future.delayed(const Duration(milliseconds: stepMs));
            waited += stepMs;
          }
          return decideByPolicy(opts);
        },
      ),
      terminalProvider: DefaultTerminalProvider(),
      onProtocolIn: onIn,
      onProtocolOut: onOut,
      mcpServers: mcpServers,
    );
    final client = await AcpClient.start(config: config);

    try {
      // Initialize if not sent by the test
      final sendsInit = stepsArr.any(
        (s) => (s['send'] as Map<String, dynamic>?)?['method'] == 'initialize',
      );
      var agentCaps = const <String, dynamic>{};
      if (!sendsInit) {
        final initR = await client.initialize();
        agentCaps = initR.agentCapabilities ?? const {};
        profile.agentCapabilities = agentCaps;
        profile.authMethods = (initR.authMethods ?? const [])
            .map<Map<String, dynamic>>(Map<String, dynamic>.from)
            .toList();
        profile.protocolVersion = '${initR.protocolVersion}';
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
            _cancelActiveSubscriptions();
            final reason =
                "Precondition failed: agentCap '$capPath' "
                'mustBe $want (actual: ${_stringify(actual)})';
            return _TestReport(
              agentName: agentName,
              testId: testId,
              title: title,
              description: description,
              status: 'NA',
              naReason: reason,
              links: _extractLinks(test),
              clientMessages: const <String>[],
              agentMessages: const <String>[],
            );
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

      Future<({bool ok, List<_UnmetExpectation> unmet})> waitExpect(
        Map<String, dynamic> expect,
      ) async {
        final timeoutMs = (expect['timeoutMs'] as num?)?.toInt() ?? 10000;
        final messages = (expect['messages'] as List)
            .cast<Map<String, dynamic>>();
        final start = DateTime.now();
        final matched = List<bool>.filled(messages.length, false);
        final unmet = <_UnmetExpectation>[];
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
                (m) =>
                    m['method'] == notif['method'] && _partialMatch(m, notif),
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
          if (matched.every((e) => e)) {
            return (ok: true, unmet: const <_UnmetExpectation>[]);
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        // Build unmet list with diffs
        for (var i = 0; i < messages.length; i++) {
          if (matched[i]) continue;
          final env = _interpolateVars(messages[i], vars);
          final kind = env.keys.firstWhere(
            (k) =>
                k == 'response' || k == 'notification' || k == 'clientRequest',
            orElse: () => 'unknown',
          );
          final expected = Map<String, dynamic>.from(env[kind] as Map);
          final closest = _closestActual(expected, kind, inbound);
          final diffs = closest == null
              ? <String>['no similar message observed']
              : _diffPartial(closest, expected);
          unmet.add(
            _UnmetExpectation(
              expected: expected,
              kind: kind,
              closestActual: closest,
              diff: diffs,
            ),
          );
        }
        return (ok: false, unmet: unmet);
      }

      Future<({bool ok, Map<String, dynamic>? violation})> waitForbid(
        Map<String, dynamic> forbid,
      ) async {
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
        return (ok: !hit, violation: found);
      }

      final unmetAll = <_UnmetExpectation>[];
      Map<String, dynamic>? forbidViolation;

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
          // Subscribe to typed updates to collect commands/modes
          final sub = client.sessionUpdates(sid).listen((u) {
            if (u is AvailableCommandsUpdate) {
              for (final c in u.commands) {
                profile.commands.add(c.name);
              }
            } else if (u is ModeUpdate) {
              if (u.currentModeId.isNotEmpty) {
                profile.modes.add(u.currentModeId);
              }
            }
          });
          // Also capture known session modes from session manager
          final modes = client.sessionModes(sid);
          if (modes != null) {
            if (modes.currentModeId != null) {
              profile.modes.add(modes.currentModeId!);
            }
            for (final m in modes.availableModes) {
              profile.modes.add(m.id);
              if (m.name.isNotEmpty) profile.modeNames[m.id] = m.name;
            }
          }
          // Detach listener at end of prompt by cancelling later when client
          // disposed Store on vars so we can cancel if needed
          _activeSubscriptions.add(sub);
          continue;
        }
        if (step.containsKey('send')) {
          final send = step['send'] as Map<String, dynamic>;
          final method = send['method'] as String;
          final expectError = send['expectError'] as bool? ?? false;
          final params = _interpolateVars(
            send['params'] as Map<String, dynamic>? ?? const {},
            vars,
          );
          final hasId = send.containsKey('id');
          if (hasId) {
            if (expectError) {
              try {
                await client.sendRaw(method, params);
              } on Exception {
                // Expected for error tests
              }
            } else {
              await client.sendRaw(method, params);
            }
          } else {
            await client.sendNotificationRaw(method, params);
          }
          continue;
        }
        if (step.containsKey('expect')) {
          final res = await waitExpect(step['expect'] as Map<String, dynamic>);
          if (!res.ok) {
            unmetAll.addAll(res.unmet);
            // continue gathering to show all unmet expectations for this test
          }
          continue;
        }
        if (step.containsKey('forbid')) {
          final res = await waitForbid(step['forbid'] as Map<String, dynamic>);
          if (!res.ok && forbidViolation == null) {
            forbidViolation = {
              'method': res.violation?['method'],
              'message': res.violation,
            };
          }
          continue;
        }
      }

      await client.dispose();
      _cancelActiveSubscriptions();

      if (unmetAll.isNotEmpty || forbidViolation != null) {
        return _TestReport(
          agentName: agentName,
          testId: testId,
          title: title,
          description: description,
          status: 'FAIL',
          links: _extractLinks(test),
          unmetExpectations: unmetAll,
          forbidViolation: forbidViolation,
          clientMessages: outboundLines,
          agentMessages: inboundLines,
        );
      }

      return _TestReport(
        agentName: agentName,
        testId: testId,
        title: title,
        description: description,
        status: 'PASS',
        links: _extractLinks(test),
      );
    } on Exception catch (e, st) {
      if (verbose) {
        stdout.writeln('[ERROR] Test failed with exception: $e');
        stdout.writeln('[STACK] $st');
      }
      await client.dispose();
      _cancelActiveSubscriptions();
      return _TestReport(
        agentName: agentName,
        testId: testId,
        title: title,
        description: description,
        status: 'FAIL',
        links: _extractLinks(test),
        unmetExpectations: [
          _UnmetExpectation(
            expected: const {'error': 'exception thrown'},
            kind: 'exception',
            closestActual: {'exception': e.toString()},
            diff: const ['exception thrown during test execution'],
          ),
        ],
        clientMessages: outboundLines,
        agentMessages: inboundLines,
      );
    }
  } on Exception catch (e) {
    if (verbose) {
      stdout.writeln('[ERROR] Failed to create client: $e');
    }
    _cancelActiveSubscriptions();
    return _TestReport(
      agentName: agentName,
      testId: testId,
      title: title,
      description: description,
      status: 'FAIL',
      links: _extractLinks(test),
      unmetExpectations: [
        _UnmetExpectation(
          expected: const {'error': 'failed to create client'},
          kind: 'startup',
          closestActual: {'exception': e.toString()},
          diff: const ['client failed to start'],
        ),
      ],
    );
  } finally {
    await sandbox.delete(recursive: true);
  }
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

List<String> _diffPartial(
  Map<String, dynamic> actual,
  Map<String, dynamic> expected, [
  String basePath = '',
]) {
  final diffs = <String>[];

  for (final entry in expected.entries) {
    final k = entry.key;
    final v = entry.value;
    final path = basePath.isEmpty ? k : '$basePath.$k';
    if (!actual.containsKey(k)) {
      diffs.add("missing field '$path'");
      continue;
    }
    final av = actual[k];
    if (v is Map<String, dynamic> && av is Map<String, dynamic>) {
      diffs.addAll(_diffPartial(Map<String, dynamic>.from(av), v, path));
    } else if (v is List && av is List) {
      // subset contains; ensure each expected element has at least one match
      for (final want in v) {
        final matchFound = av.any((got) {
          if (want is Map && got is Map) {
            return _partialMatch(
              Map<String, dynamic>.from(got),
              Map<String, dynamic>.from(want),
            );
          }
          return _matchLeaf(got, want);
        });
        if (!matchFound) {
          final wantStr = want is Map || want is List
              ? jsonEncode(want)
              : _stringify(want);
          diffs.add("no matching element for '$path[]' expected $wantStr");
        }
      }
    } else {
      if (!_matchLeaf(av, v)) {
        final as = _stringify(av);
        final ps = _stringify(v);
        diffs.add("$path: expected /$ps/, got '$as'");
      }
    }
  }

  return diffs;
}

Map<String, dynamic>? _closestActual(
  Map<String, dynamic> expected,
  String kind,
  List<Map<String, dynamic>> inbound,
) {
  if (inbound.isEmpty) return null;
  if (kind == 'response') {
    final expId = expected['id'];
    if (expId != null) {
      // Find last response with same id
      for (var i = inbound.length - 1; i >= 0; i--) {
        final m = inbound[i];
        if (m.containsKey('id') && !_hasMethod(m)) {
          final aid = m['id'];
          if (_stringify(aid) == _stringify(expId)) return m;
        }
      }
    }
    // Fallback: last response-like message
    for (var i = inbound.length - 1; i >= 0; i--) {
      final m = inbound[i];
      if (m.containsKey('id') && !_hasMethod(m)) return m;
    }
  } else {
    final expMethod = expected['method'];
    if (expMethod is String && expMethod.isNotEmpty) {
      for (var i = inbound.length - 1; i >= 0; i--) {
        final m = inbound[i];
        if (m['method'] == expMethod) return m;
      }
    }
    // Fallback: last notification-like message
    for (var i = inbound.length - 1; i >= 0; i--) {
      final m = inbound[i];
      if (_hasMethod(m)) return m;
    }
  }
  return inbound.last;
}

bool _hasMethod(Map<String, dynamic> m) => m.containsKey('method');

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

// Scripted permission outcomes are not supported; compliance requires real
// flows.

List<String> _extractLinks(Map<String, dynamic> test) =>
    ((test['docs'] as List?)?.cast<String>() ?? const <String>[])
        .where((s) => s.trim().isNotEmpty)
        .toList();

final List<StreamSubscription> _activeSubscriptions = <StreamSubscription>[];
void _cancelActiveSubscriptions() {
  for (final s in _activeSubscriptions) {
    try {
      unawaited(s.cancel());
    } on Object catch (_) {}
  }
  _activeSubscriptions.clear();
}

// Deprecated: descriptions are now provided by the .jsont test files.

// Removed table summary output per new reporting requirements.
