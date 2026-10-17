import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/minecraft_api.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/workflow_templates.dart';

void main() {
  group('Java compatibility matrix', () {
    final MinecraftApi api = MinecraftApi();

    test('legacy versions use Java 8', () {
      expect(api.javaForMc('1.8.9'), 8);
      expect(api.javaForMc('1.12.2'), 8);
      expect(api.javaForMc('1.16.5'), 8);
    });

    test('1.17 needs Java 16', () {
      expect(api.javaForMc('1.17'), 16);
      expect(api.javaForMc('1.17.1'), 16);
    });

    test('1.18 to 1.20.4 need Java 17', () {
      expect(api.javaForMc('1.18'), 17);
      expect(api.javaForMc('1.19.4'), 17);
      expect(api.javaForMc('1.20.4'), 17);
    });

    test('1.20.5 and newer use Java 21', () {
      expect(api.javaForMc('1.20.5'), 21);
      expect(api.javaForMc('1.21'), 21);
      expect(api.javaForMc('1.21.4'), 21);
    });

    test('the 2026 versioning needs Java 25', () {
      expect(api.javaForMc('26.1'), 25);
      expect(api.javaForMc('26.3'), 25);
    });
  });

  group('ServerRuntime', () {
    test('parses the runner status contract', () {
      final ServerRuntime runtime = ServerRuntime.fromJson(<String, dynamic>{
        'phase': 'ready',
        'ready': true,
        'playersOnline': 3,
        'playersMax': 20,
        'tunnelStatus': 'connected',
        'tunnelAddress': 'aurora.playit.gg:25565',
        'rssMb': 812,
        'updatedAt': '2026-10-17T10:00:00Z',
      });
      expect(runtime.online, isTrue);
      expect(runtime.tunnelConnected, isTrue);
      expect(runtime.tunnelAddress, 'aurora.playit.gg:25565');
      expect(runtime.rssMb, 812);
      expect(runtime.playersOnline, 3);
    });

    test('an unknown payload never claims to be online', () {
      final ServerRuntime runtime = ServerRuntime.fromJson(<String, dynamic>{});
      expect(runtime.online, isFalse);
      expect(runtime.ready, isFalse);
      expect(runtime.tunnelConnected, isFalse);
      expect(runtime.tunnelAddress, isEmpty);
    });
  });

  group('EULA handling', () {
    const ServerConfig base = ServerConfig(id: '1', name: 's', repoOwner: 'o', repoName: 'r');

    test('is opt-in and off by default', () {
      expect(base.eulaAccepted, isFalse);
      expect(base.copyWith(eulaAccepted: true).eulaAccepted, isTrue);
    });

    test('properties never contain eula alongside the config', () {
      // eula.txt is written by the provisioner, not baked into server.properties
      final String props = WorkflowTemplates.javaProperties(base);
      expect(props.contains('eula'), isFalse);
    });
  });

  group('Runner script', () {
    test('contains real safety steps and never accepts the EULA silently', () {
      const String script = WorkflowTemplates.runnerScript;
      expect(script.contains('eula-not-accepted'), isTrue);
      expect(script.contains('save-off'), isTrue);
      expect(script.contains('save-all flush'), isTrue);
      expect(script.contains('world-backup.zip'), isTrue);
      expect(script.contains('sha256sum'), isTrue);
      expect(script.contains('tunnelAddress'), isTrue);
      expect(script.contains('Server started'), isTrue);
      expect(script.contains('Done ('), isTrue);
      expect(script.contains('gh release create'), isTrue);
      expect(script.contains('PLAYIT_SECRET_KEY'), isTrue);
      expect(script.contains('echo "eula=true"'), isTrue);
    });

    test('never prints the Playit secret', () {
      expect(WorkflowTemplates.runnerScript.contains(r'echo "$PLAYIT_SECRET_KEY"'), isFalse);
      expect(WorkflowTemplates.runnerScript.contains('set -x'), isFalse);
    });

    test('publishes a live log and a status file', () {
      expect(WorkflowTemplates.runnerScript.contains('nova-craft/live.log'), isTrue);
      expect(WorkflowTemplates.runnerScript.contains('nova-craft/status.json'), isTrue);
    });
  });
}
