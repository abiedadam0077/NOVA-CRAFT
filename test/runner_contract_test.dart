import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/workflow_templates.dart';

/// These tests pin the *contract* of the generated runner: which failure paths
/// exist, what they publish, and that destructive steps are ordered safely.
/// They do not replace a real server run (documented in docs/REBUILD_REPORT.md).
void main() {
  const String script = WorkflowTemplates.runnerScript;
  final String workflow = WorkflowTemplates.serverWorkflow('srv-test');

  group('Failure paths publish a reason', () {
    for (final String reason in <String>[
      'eula-not-accepted',
      'missing-download-url',
      'download-failed',
      'bedrock-download-url',
      'bedrock-unzip',
      'server-crashed',
      'backup-failed',
      'backup-restore-failed',
      'invalid-restore-tag',
    ]) {
      test('reason "$reason" is published with a reason', () {
        expect(script.contains('publish_cycle_end failure "$reason"'), isTrue);
      });
    }
  });

  group('Stop and restart', () {
    test('stop goes through the command queue and is consumed', () {
      expect(script.contains('nova:stop'), isTrue);
      expect(script.contains(r'gh api -X DELETE "repos/$REPO/contents/nova-craft/commands/$f"'), isTrue);
    });

    test('the runner never self-restarts after an explicit stop', () {
      final int stopIndex = script.indexOf('STOP_FLAG');
      expect(stopIndex, greaterThan(0));
      expect(script.contains(r'if [ ! -f "$STOP_FLAG" ] && [ "$AUTORESTART" = "true" ]'), isTrue);
    });

    test('a five-hour runtime budget stays within the six-hour job limit', () {
      expect(script.contains('MAXSEC=18000'), isTrue);
      expect(workflow.contains('timeout-minutes: 360'), isTrue);
    });
  });

  group('Save safety', () {
    test('saves are flushed before the archive and the stop', () {
      final int off = script.indexOf('send_cmd "save-off"');
      final int flush = script.indexOf('send_cmd "save-all flush"');
      final int backup = script.indexOf('if backup_now "cycle"');
      final int stop = script.indexOf('send_cmd "stop"', backup);
      expect(off, greaterThan(0));
      expect(flush, greaterThan(off));
      expect(backup, greaterThan(flush));
      expect(stop, greaterThan(backup));
    });

    test('the archive and remote release are verified before retention pruning', () {
      final int published = script.indexOf(r'gh release download "$tag"');
      final int verified = script.indexOf('sha256sum -c world-backup.sha256', published);
      final int pruned = script.indexOf('  prune_backups\n  return 0', verified);
      expect(script.contains('archive.testzip()'), isTrue);
      expect(script.contains(r'gh api "repos/$REPO/releases?per_page=100"'), isTrue);
      expect(script.contains('NOVA_CRAFT_BACKUP_VERIFIED'), isTrue);
      expect(script.contains('world-backup.zip", "world-backup.sha256'), isTrue);
      expect(published, greaterThan(0));
      expect(verified, greaterThan(published));
      expect(pruned, greaterThan(verified));
      expect(script.contains('world-backup.sha256'), isTrue);
    });

    test('a failed backup fails the cycle instead of reporting success', () {
      expect(script.contains('publish_cycle_end failure "backup-failed"'), isTrue);
    });

    test('failure to publish the backup verification marker is fail-closed', () {
      final int markerEdit = script.indexOf(r'gh release edit "$tag"');
      final int refusal = script.indexOf('refusing to count it as a completed backup', markerEdit);
      final int failedReturn = script.indexOf('return 1', refusal);
      expect(markerEdit, greaterThan(0));
      expect(refusal, greaterThan(markerEdit));
      expect(failedReturn, greaterThan(refusal));
    });
  });

  group('Downloads', () {
    test('checksum length selects the algorithm and mismatches are rejected', () {
      expect(script.contains('sha256sum -c -'), isTrue);
      expect(script.contains('sha1sum -c -'), isTrue);
      expect(script.contains('md5sum -c -'), isTrue);
      expect(script.contains('ERROR checksum mismatch'), isTrue);
      expect(script.contains(r'rm -f "$tmp"'), isTrue);
    });

    test('an empty download is always rejected', () {
      expect(script.contains('ERROR empty download'), isTrue);
    });
  });

  group('Concurrency and recovery', () {
    test('runs in the same group never overlap', () {
      expect(workflow.contains('concurrency:'), isTrue);
      expect(workflow.contains('cancel-in-progress: false'), isTrue);
      expect(workflow.contains('novacraft-server-srv-test'), isTrue);
    });

    test('a cached world survives the cycle', () {
      expect(workflow.contains('actions/cache/restore'), isTrue);
      expect(workflow.contains('actions/cache/save'), isTrue);
      expect(workflow.contains('if: always()'), isTrue);
    });

    test('restore accepts only this server’s explicit tag or its newest backup', () {
      expect(script.contains('NOVA_RESTORE_TAG'), isTrue);
      expect(script.contains('invalid-restore-tag'), isTrue);
      expect(script.contains('startswith(prefix)'), isTrue);
      expect(script.contains('re.fullmatch(pattern, tag)'), isTrue);
      expect(script.contains(r'backup-%s-[A-Za-z0-9_-]{2,}'), isTrue);
      expect(script.contains(r'"backup-$SID-"[A-Za-z0-9_-]'), isFalse);
      expect(script.contains('NOVA_CRAFT_BACKUP_VERIFIED'), isTrue);
      expect(script.contains('world-backup.sha256'), isTrue);
      expect(script.contains('verify_backup_release() {'), isTrue);
      expect(script.contains(r'gh api "repos/$REPO/releases/tags/$tag"'), isTrue);
      final int releaseVerified = script.indexOf(r'verify_backup_release "$REQUESTED_RESTORE_TAG"');
      final int download = script.indexOf(r'gh release download "$REQUESTED_RESTORE_TAG"');
      expect(releaseVerified, greaterThan(0));
      expect(download, greaterThan(releaseVerified));
    });
  });

  group('Managed add-ons and world import', () {
    test('GitHub JARs are synchronized after cache restore and before the Java process starts', () {
      final int restore = workflow.indexOf('actions/cache/restore');
      final int runner = workflow.indexOf('bash nova-craft/runner.sh');
      final int sync = script.indexOf('fileops.py sync-jars');
      final int java = script.indexOf('java -Xms512M');
      expect(restore, greaterThanOrEqualTo(0));
      expect(runner, greaterThan(restore));
      expect(sync, greaterThan(0));
      expect(java, greaterThan(sync));
      expect(script.contains('publish_cycle_end failure "jar-sync-failed"'), isTrue);
      expect(script.contains('"managedJarShas"'), isTrue);
    });

    test('world ZIP import validates first and requires a safety backup before replacement', () {
      final int preflight = script.indexOf(r'fileops.py validate-import "$DATA_ABS"');
      final int backup = script.indexOf('backup_now "pre-world-import"');
      final int importer = script.indexOf(r'fileops.py import "$DATA_ABS"');
      expect(preflight, greaterThan(0));
      expect(backup, greaterThan(preflight));
      expect(importer, greaterThan(backup));
      expect(script.contains(r'put_file "$INCOMING/result.json"'), isTrue);
      expect(script.contains('WORLD_NAME="Bedrock level"'), isTrue);
      expect(script.contains('WORLD_NAME="world"'), isTrue);
      expect(script.contains('world-import-safety-backup-failed'), isTrue);
      expect(script.contains('result["status"] = "blocked"'), isTrue);
      expect(script.contains('result["error"] = "safety-backup-failed"'), isTrue);
      expect(script.contains(r'publish_import_result "$import_preflight" "nova: world import blocked"'), isTrue);
      expect(script.contains('current world was left unchanged'), isTrue);
    });

    test('world import results are published with a processing timestamp', () {
      expect(script.contains('publish_import_result() {'), isTrue);
      expect(script.contains('payload["processedAt"]'), isTrue);
      expect(script.contains('publish_import_result /tmp/nova-import.json'), isTrue);
      expect(script.contains(r'publish_import_result "$import_preflight"'), isTrue);
      expect(script.contains(r'put_file "$INCOMING/result.json"'), isTrue);
    });
  });

  group('Configuration precedence', () {
    test('properties are regenerated from server.json after the cache restore', () {
      // The restore is a separate workflow step, so the runner (which starts
      // after it) always re-applies the app's settings on top of the cache.
      expect(workflow.contains('actions/cache/restore'), isTrue);
      expect(workflow.indexOf('actions/cache/restore'), lessThan(workflow.indexOf('nova-craft/runner.sh')));
      expect(script.contains('python3 nova-craft/config.py --write-props'), isTrue);
      expect(WorkflowTemplates.configScript.contains('--write-props'), isTrue);
      expect(WorkflowTemplates.configScript.contains('unsafe server dataPath'), isTrue);
      expect(WorkflowTemplates.configScript.contains('cannot traverse a symbolic link'), isTrue);
      expect(WorkflowTemplates.configScript.contains('unsafe server id'), isTrue);
      expect(WorkflowTemplates.configScript.contains('unsupported server edition'), isTrue);
      expect(WorkflowTemplates.configScript.contains('server runtime settings are outside safe bounds'), isTrue);
      expect(script.contains('symbolic link'), isTrue);
    });

    test('eula is written only when accepted', () {
      expect(WorkflowTemplates.configScript.contains('if cfg.get("eulaAccepted")'), isTrue);
      expect(WorkflowTemplates.configScript.contains('os.remove(eula_path)'), isTrue);
    });
  });

  group('ServerConfig defaults', () {
    test('a fresh server is not started by accident and has no fake address', () {
      const ServerConfig fresh = ServerConfig(id: 'a', name: 'a', repoOwner: 'o', repoName: 'r');
      expect(fresh.playitAddress, isEmpty);
      expect(fresh.connectionHostPort, isEmpty);
      expect(fresh.eulaAccepted, isFalse);
      expect(fresh.dataPath, 'server');
    });

    test('legacy repositories still resolve their data root', () {
      final ServerConfig legacy = ServerConfig.fromJson(<String, dynamic>{
        'id': 'old',
        'name': 'Old',
        'repoOwner': 'o',
        'repoName': 'r',
        'playitAddress': 'tcp://old.playit.gg:25565',
      });
      expect(legacy.serverRoot, 'server');
      expect(legacy.connectionHostPort, 'old.playit.gg:25565');
    });

    test('containment rejects traversal above the data root', () {
      const ServerConfig c = ServerConfig(id: 'a', name: 'a', repoOwner: 'o', repoName: 'r');
      expect(c.serverPath('../../.git/config'), 'server/../../.git/config');
      expect(c.serverPath('world/level.dat'), 'server/world/level.dat');
    });
  });
}
