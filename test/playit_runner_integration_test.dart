import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/workflow_templates.dart';

void main() {
  late Directory temp;
  late Directory bin;
  late Directory workspace;
  late File runnerHarness;
  late File fakeAgent;

  const String testSecret = 'a1b2c3d4e5f6';
  const String fakeAgentSource = r'''#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 3 ] && [ "${1:-}" = "--secret-path" ] && [ "${3:-}" = "--platform-docker" ] || exit 91
secret_path="$2"
[ -f "$secret_path" ] || { echo "private Agent secret file missing"; exit 92; }
[ "$(stat -c %a "$secret_path")" = "600" ] || exit 93
[ -z "${PLAYIT_SECRET_KEY:-}" ] || exit 94
grep -Eq '^[[:xdigit:]]+$' "$secret_path" || { echo "private Agent secret format invalid"; exit 95; }
[ "$(cat "$secret_path")" = "${MOCK_EXPECTED_SECRET:-}" ] || exit 96
case "${MOCK_AGENT_MODE:-connected}" in
  connected)
    echo "playit connected; tunnels loaded"
    exec /usr/bin/sleep 30
    ;;
  invalid)
    echo "InvalidAgentKey: invalid agent key"
    exec /usr/bin/sleep 30
    ;;
  network)
    echo "Could not connect to Playit: network is unreachable"
    exec /usr/bin/sleep 30
    ;;
  exit)
    exit "${MOCK_AGENT_EXIT_CODE:-37}"
    ;;
esac
exit 94
''';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nova-playit-lifecycle-');
    bin = Directory('${temp.path}/bin')..createSync();
    workspace = Directory('${temp.path}/workspace')..createSync();
    Directory('${workspace.path}/nova-craft').createSync(recursive: true);
    File('${workspace.path}/nova-craft/playit.py').writeAsStringSync(WorkflowTemplates.playitScript);

    fakeAgent = File('${temp.path}/fake-playitd')..writeAsStringSync(fakeAgentSource);
    await Process.run('chmod', <String>['700', fakeAgent.path]);
    File('${bin.path}/curl').writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
out=""
config=""
url=""
while (($#)); do
  case "$1" in
    -o|--output|--config|-w|-X|-H|-d|--connect-timeout|--max-time|--retry)
      option="$1"
      value="${2:-}"
      case "$option" in
        -o|--output) out="$value" ;;
        --config) config="$value" ;;
      esac
      shift 2
      ;;
    *)
      [[ "$1" == https://* ]] && url="$1"
      shift
      ;;
  esac
done
if [[ "$url" == *"playit-agent/releases/download"* ]]; then
  cp "$MOCK_AGENT_FILE" "$out"
  exit 0
fi
if [[ "$url" == "https://api.playit.gg/v1/agents/rundata" ]]; then
  if [[ "${MOCK_API_MODE:-success}" == "network" ]]; then
    echo "curl: (7) Failed to connect to api.playit.gg port 443: Network is unreachable" >&2
    exit 7
  fi
  [ "$(stat -c %a "$config")" = "600" ] || exit 97
  grep -q 'Authorization: Agent-Key ' "$config" || exit 98
  printf '%s' "$MOCK_PLAYIT_BODY" > "$out"
  printf '%s' "$MOCK_PLAYIT_HTTP_STATUS"
  exit 0
fi
echo "unexpected mocked curl URL" >&2
exit 96
''');
    File('${bin.path}/sha256sum').writeAsStringSync(r'''#!/usr/bin/env bash
# This harness substitutes an inert daemon binary; production checksum logic is
# pinned by contract tests and is intentionally not tested with a fake digest.
cat >/dev/null || true
exit 0
''');
    File('${bin.path}/sleep').writeAsStringSync(r'''#!/usr/bin/env bash
exec /usr/bin/sleep 0.01
''');
    for (final String name in <String>['curl', 'sha256sum', 'sleep']) {
      await Process.run('chmod', <String>['700', '${bin.path}/$name']);
    }

    final String script = WorkflowTemplates.runnerScript;
    const String startMarker = 'playit_api() {';
    const String endMarker = '\nTUNNEL_STATE=unknown\nTUNNEL_DIAGNOSTIC=minecraft_starting';
    final int start = script.indexOf(startMarker);
    final int end = script.indexOf(endMarker, start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final String playitFunctions = script.substring(start, end);

    final String harnessText = <String>[
      r'''#!/usr/bin/env bash
set -uo pipefail
WORKSPACE_ABS="''',
      workspace.path,
      r'''"
RUNNER_TEMP="''',
      '${temp.path}/runner-temp',
      r'''"
GITHUB_RUN_ID=98765
GITHUB_RUN_ATTEMPT=1
EDITION=JAVA
GAME_PORT=25565
PLAYIT_TUNNEL_ID=""
PLAYIT_PID=""
PLAYIT_SECRET_FILE=""
PLAYIT_CURL_CONFIG=""
PLAYIT_LOG_PATH=""
PLAYIT_TEMP_DIR=""
PLAYIT_AGENT_STATUS=not_started
PLAYIT_AGENT_DIAGNOSTIC=agent_not_started
PLAYIT_AGENT_EXIT_CODE=not_started
PLAYIT_AGENT_EXIT_CAPTURED=false
PLAYIT_SECRET_STATUS=missing
SERVER_PORT_STATUS=listening
TUNNEL_STATE=unknown
TUNNEL_DIAGNOSTIC=not_started
TUNNEL_MSG=""
TUNNEL_ADDR=""
TUNNEL_NAME=""
TUNNEL_ID=""
TUNNEL_PROTO=""
TUNNEL_ISSUE=""
TUNNEL_LOCAL_IP=""
TUNNEL_LOCAL_PORT=""
AGENT_ID=""
SRV_PID=1234
cd "$WORKSPACE_ABS"
log() { printf '%s' "$*" >> "''',
      temp.path,
      r'''/runner.log"; }
publish_status() { :; }
''',
      playitFunctions,
      r'''
start_playit
echo "__RESULT__agentStatus=$PLAYIT_AGENT_STATUS"
echo "__RESULT__agentDiagnostic=$PLAYIT_AGENT_DIAGNOSTIC"
echo "__RESULT__agentExitCode=$PLAYIT_AGENT_EXIT_CODE"
echo "__RESULT__secretStatus=$PLAYIT_SECRET_STATUS"
echo "__RESULT__serverPortStatus=$SERVER_PORT_STATUS"
echo "__RESULT__tunnelStatus=$TUNNEL_STATE"
echo "__RESULT__tunnelDiagnostic=$TUNNEL_DIAGNOSTIC"
echo "__RESULT__tunnelAddress=$TUNNEL_ADDR"
echo "__RESULT__tunnelMessage=$TUNNEL_MSG"
if [ -n "$PLAYIT_PID" ] && kill -0 "$PLAYIT_PID" 2>/dev/null; then
  kill "$PLAYIT_PID" 2>/dev/null || true
  wait "$PLAYIT_PID" 2>/dev/null || true
fi
[ -n "$PLAYIT_TEMP_DIR" ] && rm -rf "$PLAYIT_TEMP_DIR"
rm -f "$WORKSPACE_ABS/playitd" "$WORKSPACE_ABS/playitd.tmp"
''',
    ].join();
    runnerHarness = File('${temp.path}/run.sh')..writeAsStringSync(harnessText);
    await Process.run('chmod', <String>['700', runnerHarness.path]);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<Map<String, String>> runScenario({
    String? secret = testSecret,
    String agentMode = 'connected',
    String apiMode = 'success',
    int httpStatus = 200,
    String body = '{"status":"success","data":{"agent_id":"agent-test","tunnels":[]}}',
    int agentExitCode = 37,
  }) async {
    final Map<String, String> environment = <String, String>{
      'PATH': '${bin.path}:/usr/bin:/bin',
      'MOCK_AGENT_FILE': fakeAgent.path,
      'MOCK_AGENT_MODE': agentMode,
      'MOCK_AGENT_EXIT_CODE': '$agentExitCode',
      'MOCK_EXPECTED_SECRET': secret ?? '',
      'MOCK_API_MODE': apiMode,
      'MOCK_PLAYIT_HTTP_STATUS': '$httpStatus',
      'MOCK_PLAYIT_BODY': body,
    };
    if (secret != null) environment['PLAYIT_SECRET_KEY'] = secret;
    final ProcessResult result = await Process.run('bash', <String>[runnerHarness.path], environment: environment);
    expect(result.exitCode, 0, reason: result.stderr);
    final Map<String, String> fields = <String, String>{};
    for (final String line in result.stdout.split('\n')) {
      if (!line.startsWith('__RESULT__')) continue;
      final int equals = line.indexOf('=');
      if (equals > 10) fields[line.substring(10, equals)] = line.substring(equals + 1);
    }
    return fields;
  }

  group('Runner launch order and secret delivery', () {
    test('Minecraft protocol check precedes the single official Agent start', () {
      final String runner = WorkflowTemplates.runnerScript;
      final int localProbe = runner.indexOf(r'probe_tunnel "127.0.0.1:$GAME_PORT" false');
      final int startCall = runner.indexOf('  start_playit\n  LAST_TUNNEL_REFRESH', localProbe);
      final int publicProbe = runner.indexOf(r'probe_tunnel "$TUNNEL_ADDR" true');
      expect(localProbe, greaterThan(0));
      expect(startCall, greaterThan(localProbe));
      expect(publicProbe, greaterThan(startCall));
      expect(RegExp(r'--secret-path').allMatches(runner), hasLength(1));
      expect(runner, contains(r'mktemp -d "$runner_temp/nova-playit-${run_tag}.XXXXXX"'));
      expect(runner, contains(r'rm -rf -- "$PLAYIT_TEMP_DIR"'));
      expect(WorkflowTemplates.serverWorkflow('server-test'), contains(r'PLAYIT_SECRET_KEY: ${{ secrets.PLAYIT_SECRET_KEY }}'));
      expect(runner, isNot(contains('/v1/tunnels/create')));
    });

    test('a missing secret does not start the Agent and does not clear local Minecraft readiness', () async {
      final Map<String, String> result = await runScenario(secret: null);
      expect(result['secretStatus'], 'missing');
      expect(result['agentStatus'], 'not_started');
      expect(result['agentDiagnostic'], 'secret_missing');
      expect(result['tunnelAddress'], isEmpty);
      expect(result['serverPortStatus'], 'listening');
    });

    test('a malformed saved key is reported without launching a second path or printing it', () async {
      final Map<String, String> result = await runScenario(secret: 'not-a-hex-key');
      expect(result['secretStatus'], 'saved');
      expect(result['agentStatus'], 'failed');
      expect(result['agentDiagnostic'], 'invalid_secret_format');
      expect(result['serverPortStatus'], 'listening');
    });
  });

  group('Agent, API and Tunnel failure separation', () {
    test('an Agent network failure remains starting while the daemon retries', () async {
      final Map<String, String> result = await runScenario(agentMode: 'network');
      expect(result['agentStatus'], 'starting');
      expect(result['agentDiagnostic'], 'network_unreachable');
      expect(result['tunnelDiagnostic'], 'agent_network_unreachable');
      expect(result['serverPortStatus'], 'listening');
    });

    test('an explicit invalid-key Agent log is distinct from a network retry', () async {
      final Map<String, String> result = await runScenario(agentMode: 'invalid');
      expect(result['agentStatus'], 'failed');
      expect(result['agentDiagnostic'], 'invalid_secret');
      expect(result['tunnelStatus'], 'error');
      expect(result['tunnelDiagnostic'], 'agent_invalid_secret');
      expect(result['tunnelAddress'], isEmpty);
      expect(result['serverPortStatus'], 'listening');
    });

    test('an API transport failure leaves the log-confirmed Agent connected and reports curl code', () async {
      final Map<String, String> result = await runScenario(apiMode: 'network');
      expect(result['agentStatus'], 'connected');
      expect(result['agentDiagnostic'], 'connected');
      expect(result['tunnelStatus'], 'error');
      expect(result['tunnelDiagnostic'], 'rundata_network_error');
      expect(result['tunnelMessage'], contains('curl exit 7'));
      expect(result['serverPortStatus'], 'listening');
    });

    test('a real HTTP 401 from rundata is distinguished as a rejected key', () async {
      final Map<String, String> result = await runScenario(httpStatus: 401, body: '{"error":"unauthorized"}');
      expect(result['agentStatus'], 'failed');
      expect(result['agentDiagnostic'], 'invalid_secret');
      expect(result['tunnelStatus'], 'error');
      expect(result['tunnelDiagnostic'], 'rundata_unauthorized');
      expect(result['tunnelMessage'], contains('HTTP 401'));
      expect(result['serverPortStatus'], 'listening');
    });

    test('HTTP 403 is not mislabeled as an invalid key', () async {
      final Map<String, String> result = await runScenario(httpStatus: 403, body: '{"error":"forbidden"}');
      expect(result['agentStatus'], 'connected');
      expect(result['tunnelStatus'], 'error');
      expect(result['tunnelDiagnostic'], 'rundata_forbidden');
      expect(result['tunnelAddress'], isEmpty);
    });

    test('malformed HTTP 200 rundata is an API parse error, not a missing Tunnel', () async {
      final Map<String, String> result = await runScenario(body: '{not-json');
      expect(result['agentStatus'], 'connected');
      expect(result['tunnelStatus'], 'error');
      expect(result['tunnelDiagnostic'], 'rundata_invalid_json');
      expect(result['tunnelMessage'], contains('not valid JSON'));
      expect(result['tunnelAddress'], isEmpty);
    });

    test('a connected Agent with no reported Tunnel never receives a made-up address', () async {
      final Map<String, String> result = await runScenario();
      expect(result['agentStatus'], 'connected');
      expect(result['tunnelStatus'], 'not_created');
      expect(result['tunnelDiagnostic'], 'not_created');
      expect(result['tunnelAddress'], isEmpty);
      expect(result['tunnelMessage'], contains('Create one manually'));
    });

    test('Minecraft protocol readiness remains true when the Agent process exits with a real code', () async {
      final Map<String, String> result = await runScenario(agentMode: 'exit', agentExitCode: 37);
      expect(result['agentStatus'], 'failed');
      expect(result['agentDiagnostic'], 'process_exited');
      expect(result['agentExitCode'], '37');
      expect(result['tunnelStatus'], 'error');
      expect(result['serverPortStatus'], 'listening');
      expect(result['tunnelAddress'], isEmpty);
    });

    test('the actual status serializer redacts raw keys and authorization headers', () async {
      const String fakeKey = '0123456789abcdef0123456789abcdef';
      await File('${workspace.path}/nova-craft/server.json').writeAsString(jsonEncode(<String, dynamic>{'id': 'server-test'}));
      final File agentLog = File('${temp.path}/agent.log')
        ..writeAsStringSync('key=$fakeKey\nAuthorization: Agent-Key $fakeKey\nsecret_key=$fakeKey\n');
      final String runner = WorkflowTemplates.runnerScript;
      final int cycle = runner.indexOf('publish_cycle_end() {');
      final int pythonMarker = runner.indexOf("<<'PY'\n", cycle);
      final int pythonStart = pythonMarker + "<<'PY'\n".length;
      final int pythonEnd = runner.indexOf('\nPY\n)', pythonStart);
      expect(cycle, greaterThanOrEqualTo(0));
      expect(pythonMarker, greaterThan(cycle));
      expect(pythonEnd, greaterThan(pythonStart));
      final File serializer = File('${temp.path}/status.py')..writeAsStringSync(runner.substring(pythonStart, pythonEnd));
      final ProcessResult result = await Process.run(
        'python3',
        <String>[serializer.path, 'success', 'cycle-finished', 'test-version', '1792324800'],
        workingDirectory: workspace.path,
        environment: <String, String>{
          'PLAYIT_SECRET_KEY': fakeKey,
          'PLAYIT_LOG_PATH': agentLog.path,
          'PLAYIT_AGENT_STATUS': 'connected',
          'PLAYIT_SECRET_STATUS': 'saved',
          'SERVER_PORT_STATUS': 'listening',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, isNot(contains(fakeKey)));
      final Map<String, dynamic> status = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(status['agentLogTail'], contains('[REDACTED]'));
      expect(status['agentLogTail'], isNot(contains(fakeKey)));
    });
  });
}
