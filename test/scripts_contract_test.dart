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
    test('the agent key is sent as a header and never echoed', () {
      expect(runner.contains(r'Authorization: Agent-Key $PLAYIT_SECRET_KEY'), isTrue);
      expect(playit.contains('Agent-Key'), isTrue); // documented in the contract
      expect(playit.contains('print(secret'), isFalse);
      expect(playit.contains('print(key'), isFalse);
      expect(runner.contains(r'echo "$PLAYIT_SECRET_KEY"'), isFalse);
    });

    test('the runner probes only a Playit-reported address with the game protocol', () {
      expect(runner.contains('probe_tunnel "$TUNNEL_ADDR"'), isTrue);
      expect(runner.contains(r'${TUNNEL_ADDR:-$TUNNEL}'), isFalse);
      expect(runner.contains('Java Server List Ping'), isTrue);
      expect(runner.contains('Bedrock RakNet ping'), isTrue);
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
      expect(playit.contains('len(matching) == 1'), isTrue);
      expect(playit.contains('Several matching Playit Tunnels exist'), isTrue);
      expect(playit.contains('TUNNEL_ID'), isTrue);
    });
  });

  group('Backup and runtime-cycle safety', () {
    test('five-hour runtime stays inside a six-hour Actions job', () {
      final String workflow = WorkflowTemplates.serverWorkflow('contract');
      expect(runner.contains('MAXSEC=18000'), isTrue);
      expect(workflow.contains('timeout-minutes: 360'), isTrue);
      expect(runner.contains('JOB_STARTED=$(date +%s)'), isTrue);
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
      expect(runner.contains('work_dir="$(mktemp -d)"'), isTrue);
      expect(runner.contains('exceeds GitHub\'s 2 GiB release-asset limit'), isTrue);
      expect(runner.contains('backup exceeds the restore size limit'), isTrue);
      expect(runner.contains('moved_old = []'), isTrue);
      expect(runner.contains('installed_new = []'), isTrue);
      expect(runner.contains('os.replace(previous, target)'), isTrue);
    });

    test('backups are never archived until Minecraft confirms that saves finished', () {
      final int waiter = runner.indexOf('wait_for_save() {');
      final int manual = runner.indexOf('perform_manual_backup() {');
      final int ack = runner.indexOf('if wait_for_save "$save_log_offset"', manual);
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
      final int automaticLookup = runner.indexOf('gh release list', snapshotGuard);
      final int snapshotAction = runner.indexOf('if [ "$ACTION" = "snapshot" ]; then', automaticLookup);
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
        'agentId': 'agent-123',
      });
      expect(runtime.online, isTrue);
      expect(runtime.tunnelConnected, isTrue);
      expect(runtime.tunnelAddress, 'example.playit.gg:25565');
      expect(runtime.tunnelName, 'NOVA srv');
      expect(runtime.tunnelProtocol, 'tcp');
      expect(runtime.tunnelOfflineReasons, <String>['agent-offline']);
      expect(runtime.agentId, 'agent-123');
    });

    test('an offline runtime never reports the server as online', () {
      const ServerRuntime runtime = ServerRuntime(phase: 'failed', ready: false);
      expect(runtime.online, isFalse);
      expect(runtime.tunnelConnected, isFalse);
      expect(runtime.tunnelAddress, isEmpty);
    });
  });
}
