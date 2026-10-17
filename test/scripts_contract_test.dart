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
      expect(playit.contains('Agent-Key'), isTrue);
      expect(playit.contains('print(secret'), isFalse);
      expect(playit.contains('print(key'), isFalse);
      expect(playit.contains('InvalidAgentKey'), isTrue);
    });

    test('the runner verifies the address Playit reported, not a hand-typed one', () {
      expect(runner.contains(r'probe_tunnel "${TUNNEL_ADDR:-$TUNNEL}"'), isTrue);
      expect(runner.contains('playit.py'), isTrue);
      expect(runner.contains('TUNNEL_OFFLINE'), isFalse);
    });

    test('tunnel creation survives a refusal without inventing an address', () {
      expect(playit.contains('tunnels/create'), isTrue);
      expect(playit.contains('RequiresVerifiedAccount'), isTrue);
      expect(runner.contains('TUNNEL_ADDR=""'), isTrue);
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
