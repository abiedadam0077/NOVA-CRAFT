import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/workflow_templates.dart';

/// Contract tests for the runner-side helpers added for files, add-ons and
/// Playit. They pin the safety properties that must never regress.
void main() {
  const String runner = WorkflowTemplates.runnerScript;
  const String fileops = WorkflowTemplates.fileOpsScript;
  const String playit = WorkflowTemplates.playitScript;

  group('File operations stay inside the server data folder', () {
    test('paths are resolved against the root and rejects escapes', () {
      expect(fileops.contains('def safe_path(root, rel):'), isTrue);
      expect(fileops.contains('path-outside-root'), isTrue);
      expect(fileops.contains('os.path.realpath'), isTrue);
    });

    test('archives are checked entry by entry', () {
      expect(fileops.contains('unsafe-archive-entry'), isTrue);
      expect(fileops.contains('_zip_safe'), isTrue);
    });

    test('the manifest is generated from the data root only', () {
      expect(fileops.contains('def manifest(root):'), isTrue);
      expect(fileops.contains('"dirs"'), isTrue);
      expect(fileops.contains('truncated'), isTrue);
    });

    test('snapshots are bounded and text-only', () {
      expect(fileops.contains('SNAPSHOT_MAX_FILES'), isTrue);
      expect(fileops.contains('SNAPSHOT_MAX_BYTES'), isTrue);
      expect(fileops.contains('TEXT_EXT'), isTrue);
      expect(fileops.contains('apply-snapshot'), isTrue);
    });

    test('file operations are applied while the server is running', () {
      expect(runner.contains('apply_file_request'), isTrue);
      expect(runner.contains('nova-craft/files/request.json'), isTrue);
      expect(runner.contains('publish_files'), isTrue);
      expect(runner.contains('snapshot.json'), isTrue);
    });

    test('managed Git JARs are reconciled into the runner data root', () {
      expect(fileops.contains('def sync_managed_jars'), isTrue);
      expect(fileops.contains('git ls-tree'), isTrue);
      expect(fileops.contains('"cat-file", "blob", object_sha'), isTrue);
      expect(fileops.contains('managed JAR blob hash did not match Git'), isTrue);
      expect(runner.contains('fileops.py sync-jars'), isTrue);
      expect(runner.contains('jarSyncStatus'), isTrue);
    });

    test('world imports stage validated files before replacing the active folder', () {
      expect(fileops.contains('def _validated_zip_members'), isTrue);
      expect(fileops.contains('archive-contains-a-link-or-special-file'), isTrue);
      expect(fileops.contains('def _select_world_members'), isTrue);
      expect(fileops.contains('os.replace(extracted, target)'), isTrue);
      expect(fileops.contains('missing-world-db'), isTrue);
      expect(runner.contains('backup_now "pre-world-import"'), isTrue);
    });
  });

  group('Bedrock add-ons', () {
    test('the add-on installer writes real world pack manifests', () {
      expect(fileops.contains('world_%s_packs.json'), isTrue);
      expect(fileops.contains('behavior_packs'), isTrue);
      expect(fileops.contains('resource_packs'), isTrue);
      expect(fileops.contains('.mcaddon'), isTrue);
    });

    test('the runner installs add-ons before the server starts', () {
      final int addons = runner.indexOf('fileops.py addons');
      final int start = runner.indexOf('bedrock_server');
      expect(addons, greaterThan(0));
      expect(start, greaterThan(addons));
    });
  });

  group('Playit', () {
    test('the official daemon receives the key by protected file, not argv or logs', () {
      expect(runner.contains('header = "Authorization: Agent-Key %s"'), isTrue);
      expect(runner.contains(r'--secret-path "$PLAYIT_SECRET_FILE"'), isTrue);
      expect(runner.contains(r'--socket-path "$PLAYIT_TEMP_DIR/playit.sock"'), isTrue);
      expect(runner.contains(r'chmod 600 "$PLAYIT_SECRET_FILE"'), isTrue);
      expect(runner.contains('unset PLAYIT_SECRET_KEY'), isTrue);
      expect(runner.contains('::add-mask::%s'), isTrue);
      expect(runner.contains('safe_agent_log_tail'), isTrue);
      expect(playit.contains('never prints the agent secret'), isTrue);
      expect(playit.contains('print(secret'), isFalse);
      expect(playit.contains('print(key'), isFalse);
      expect(runner.contains(r'echo "$PLAYIT_SECRET_KEY"'), isFalse);
    });

    test('the official Agent starts exactly once and connectivity is log-confirmed', () {
      expect(RegExp(r'--secret-path').allMatches(runner), hasLength(1));
      expect(RegExp(r'--socket-path').allMatches(runner), hasLength(1));
      expect(runner.contains(r'nohup "$WORKSPACE_ABS/playitd" --secret-path'), isTrue);
      expect(runner.contains('--platform-docker'), isTrue);
      expect(runner.contains("grep -Fiq 'playit connected; tunnels loaded'"), isTrue);
      expect(runner.contains(r'kill -0 "$PLAYIT_PID"'), isTrue);
      expect(runner.contains('PLAYIT_AGENT_CONNECTED:'), isTrue);
      expect(runner.contains('PLAYIT_AGENT_FAILED'), isTrue);
      expect(runner.contains('PLAYIT_AGENT_STILL_STARTING'), isTrue);
    });

    test('the runner probes only a Playit-reported address with the game protocol', () {
      expect(runner.contains(r'probe_tunnel "$TUNNEL_ADDR"'), isTrue);
      expect(runner.contains(r'${TUNNEL_ADDR:-$TUNNEL}'), isFalse);
      expect(playit.contains('Java Server List Ping over TCP'), isTrue);
      expect(playit.contains('RakNet unconnected ping over UDP'), isTrue);
      expect(runner.contains('playit.py'), isTrue);
      expect(runner.contains('TUNNEL_OFFLINE'), isFalse);
      expect(runner.contains('once per minute'), isTrue);
      expect(runner.contains('if refresh_tunnel; then'), isTrue);
    });

    test('the app and runner never create a Playit Tunnel', () {
      expect(runner.contains('/v1/tunnels/create'), isFalse);
      expect(playit.contains('tunnels/create'), isFalse);
      expect(runner.contains('TUNNEL_ADDR=""'), isTrue);
      expect(runner.contains('Create one manually in the Playit dashboard'), isTrue);
      expect(playit.contains('select one in NOVA CRAFT'), isTrue);
    });

    test('only the selected or unambiguous edition-matching Tunnel is reported', () {
      expect(playit.contains('requested_id'), isTrue);
      expect(playit.contains('len(compatible) == 1'), isTrue);
      expect(playit.contains('Several matching Playit Tunnels exist'), isTrue);
      expect(playit.contains('Tunnel type unsupported'), isTrue);
      expect(playit.contains('not_created'), isTrue);
      expect(playit.contains('address_unavailable'), isTrue);
      expect(playit.contains('TUNNEL_LOCAL_IP'), isTrue);
      expect(playit.contains('TUNNEL_LOCAL_PORT'), isTrue);
      expect(playit.contains('TUNNEL_ID'), isTrue);
    });

    test('the injected secret is recorded as saved even if a later startup step fails', () {
      final int injectedStatus = runner.indexOf('PLAYIT_SECRET_STATUS=saved');
      final int download = runner.indexOf('PLAYIT_API_HTTP_STATUS');
      expect(injectedStatus, greaterThan(0));
      expect(download, greaterThan(injectedStatus));
      expect(runner.contains('PLAYIT_SECRET_STATUS=missing'), isTrue);
      expect(runner.contains('secure_temp_directory_failed'), isTrue);
      expect(runner.contains('secure_temp_files_failed'), isTrue);
      expect(runner.contains(r'umask "$previous_umask"'), isTrue);
    });

    test('runner status includes separate secret, Agent, local-port and redacted-log fields', () {
      for (final String key in <String>[
        'agentStatus',
        'agentDiagnostic',
        'playitSecretStatus',
        'serverPortStatus',
        'gamePort',
        'agentLogTail',
      ]) {
        expect(runner.contains('"$key"'), isTrue, reason: key);
      }
      expect(runner.contains('text.replace(secret, "[REDACTED]")'), isTrue);
      expect(runner.contains('with open(secret_path'), isTrue);
      expect(runner.contains('PLAYIT_AGENT_CONNECTED'), isTrue);
      expect(playit.contains('Server List Ping'), isTrue);
      expect(runner.contains('server_port_not_listening'), isTrue);
      expect(runner.contains('origin_mismatch'), isTrue);
      expect(runner.contains('connection ready'), isFalse);
    });
  });

  group('Backup and runtime-cycle safety', () {
    test('five-hour runtime stays inside a six-hour Actions job', () {
      final String workflow = WorkflowTemplates.serverWorkflow('contract');
      expect(runner.contains('MAXSEC=18000'), isTrue);
      expect(workflow.contains('timeout-minutes: 360'), isTrue);
      expect(runner.contains(r'JOB_STARTED=$(date +%s)'), isTrue);
    });

    test('a backup is verified remotely before retention pruning', () {
      final int published = runner.indexOf(r'gh release download "$tag"');
      final int verify = runner.indexOf('sha256sum -c world-backup.sha256', published);
      final int prune = runner.indexOf('  prune_backups\n  return 0', verify);
      expect(published, greaterThan(0));
      final int verifiedMarker = runner.indexOf('NOVA_CRAFT_BACKUP_VERIFIED', verify);
      expect(verify, greaterThan(published));
      expect(verifiedMarker, greaterThan(verify));
      expect(prune, greaterThan(verifiedMarker));
      expect(runner.contains(r'gh release edit "$tag"'), isTrue);
      expect(runner.contains('archive.testzip()'), isTrue);
      expect(runner.contains(r'backup-$SID-'), isTrue);
      expect(runner.contains('BACKUP_RETENTION'), isTrue);
      expect(runner.contains(r'work_dir="$(mktemp -d)"'), isTrue);
      expect(runner.contains('exceeds GitHub\'s 2 GiB release-asset limit'), isTrue);
      expect(runner.contains('backup exceeds the restore size limit'), isTrue);
      expect(runner.contains('moved_old = []'), isTrue);
      expect(runner.contains('installed_new = []'), isTrue);
      expect(runner.contains('os.replace(previous, target)'), isTrue);
    });

    test('backups are never archived until Minecraft confirms that saves finished', () {
      final int waiter = runner.indexOf('wait_for_save() {');
      final int manual = runner.indexOf('perform_manual_backup() {');
      final int ack = runner.indexOf(r'if wait_for_save "$save_log_offset"', manual);
      final int backup = runner.indexOf('backup_now "manual"', ack);
      final int refusal = runner.indexOf('refusing to archive a possibly changing world', manual);
      expect(waiter, greaterThan(0));
      expect(ack, greaterThan(manual));
      expect(backup, greaterThan(ack));
      expect(refusal, greaterThan(ack));
      expect(runner.contains('Data saved'), isTrue);
      expect(runner.contains('Files are now ready to be copied'), isTrue);
    });

    test('manual backups are handled by the active runner', () {
      expect(runner.contains('nova:backup'), isTrue);
      expect(runner.contains('perform_manual_backup'), isTrue);
      expect(runner.contains('save-all flush'), isTrue);
      expect(runner.contains('save hold'), isTrue);
    });

    test('snapshot mode never restores a stale release over the cached world', () {
      final int snapshotGuard = runner.indexOf('snapshot actions cannot include a restore tag');
      final int automaticLookup = runner.indexOf(r'gh api "repos/$REPO/releases?per_page=100"', snapshotGuard);
      final int snapshotAction = runner.indexOf(r'if [ "$ACTION" = "snapshot" ]; then', automaticLookup);
      expect(snapshotGuard, greaterThan(0));
      expect(automaticLookup, greaterThan(snapshotGuard));
      expect(snapshotAction, greaterThan(automaticLookup));
      expect(runner.contains('backup-restore-failed'), isTrue);
      expect(runner.contains('refusing to start from an older cached world'), isTrue);
    });

    test('the runner rejects manual console commands when disabled', () {
      expect(runner.contains('ALLOW_COMMANDS'), isTrue);
      expect(runner.contains('manual command rejected: console commands are disabled'), isTrue);
    });
  });

  group('Runtime status', () {
    test('the structured tunnel fields are parsed', () {
      final ServerRuntime runtime = ServerRuntime.fromJson(<String, dynamic>{
        'phase': 'ready',
        'ready': true,
        'tunnelStatus': 'connected',
        'tunnelAddress': 'example.playit.gg:25565',
        'tunnelName': 'NOVA srv',
        'tunnelProtocol': 'tcp',
        'tunnelOfflineReasons': <String>['agent-offline'],
        'tunnelLocalIp': '127.0.0.1',
        'tunnelLocalPort': 25565,
        'agentId': 'agent-123',
        'agentStatus': 'connected',
        'agentDiagnostic': 'connected',
        'playitSecretStatus': 'saved',
        'serverPortStatus': 'listening',
        'gamePort': 25565,
        'agentLogTail': 'playit connected; tunnels loaded',
      });
      expect(runtime.online, isTrue);
      expect(runtime.tunnelConnected, isTrue);
      expect(runtime.tunnelAddress, 'example.playit.gg:25565');
      expect(runtime.tunnelName, 'NOVA srv');
      expect(runtime.tunnelProtocol, 'tcp');
      expect(runtime.tunnelOfflineReasons, <String>['agent-offline']);
      expect(runtime.tunnelLocalIp, '127.0.0.1');
      expect(runtime.tunnelLocalPort, 25565);
      expect(runtime.agentId, 'agent-123');
      expect(runtime.agentConnected, isTrue);
      expect(runtime.agentDiagnostic, 'connected');
      expect(runtime.playitSecretStatus, 'saved');
      expect(runtime.serverPortStatus, 'listening');
      expect(runtime.gamePort, 25565);
      expect(runtime.agentLogTail, 'playit connected; tunnels loaded');
    });

    test('an offline runtime never reports the server as online', () {
      const ServerRuntime runtime = ServerRuntime(phase: 'failed', ready: false);
      expect(runtime.online, isFalse);
      expect(runtime.tunnelConnected, isFalse);
      expect(runtime.tunnelAddress, isEmpty);
    });

    test('negative Agent and tunnel states stay distinct from ready', () {
      final ServerRuntime runtime = ServerRuntime.fromJson(<String, dynamic>{
        'phase': 'ready',
        'ready': true,
        'agentStatus': 'failed',
        'agentDiagnostic': 'invalid_secret',
        'tunnelStatus': 'unsupported',
        'playitSecretStatus': 'saved',
        'serverPortStatus': 'listening',
      });
      expect(runtime.online, isTrue);
      expect(runtime.agentConnected, isFalse);
      expect(runtime.agentStatus, 'failed');
      expect(runtime.agentDiagnostic, 'invalid_secret');
      expect(runtime.tunnelConnected, isFalse);
      expect(runtime.tunnelStatus, 'unsupported');
      expect(runtime.playitSecretStatus, 'saved');
      expect(runtime.serverPortStatus, 'listening');
    });
  });
}
