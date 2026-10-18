import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/logs.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/workflow_templates.dart';

void main() {
  group('ServerConfig', () {
    const ServerConfig config = ServerConfig(
      id: 'srv1',
      name: 'Island',
      repoOwner: 'octocat',
      repoName: 'nova-island',
      repoPrivate: true,
      edition: 'JAVA',
      mcVersion: '1.21.4',
      software: 'PAPER',
      maxPlayers: 30,
      memoryMb: 6144,
      playitAddress: 'tcp://island.playit.gg:25570',
      playitTunnelId: 'java-a',
      allowCommands: false,
      backupRetention: 5,
    );

    test('connection address strips schemes', () {
      expect(config.connectionHostPort, 'island.playit.gg:25570');
      expect(config.localPort, 25565);
      expect(config.supportsPlugins, isTrue);
      expect(config.supportsMods, isFalse);
      expect(config.modsFolder, 'plugins');
      expect(config.serverPath('plugins'), 'server/plugins');
    });

    test('bedrock servers expose the bedrock defaults', () {
      const ServerConfig bedrock = ServerConfig(
        id: 'b1',
        name: 'Bedrock',
        repoOwner: 'octocat',
        repoName: 'nova-bedrock',
        edition: 'BEDROCK',
        mcVersion: '1.21.50',
        software: 'BDS',
      );
      expect(bedrock.isBedrock, isTrue);
      expect(bedrock.localPort, 19132);
      expect(bedrock.supportsPlugins, isFalse);
      expect(bedrock.modsFolder, 'behavior_packs');
      expect(bedrock.serverPath('behavior_packs'), 'server/behavior_packs');
    });

    test('json round trip preserves every field', () {
      final Map<String, dynamic> json = jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      final ServerConfig copy = ServerConfig.fromJson(json);
      expect(copy.toJson(), config.toJson());
      expect(copy.id, config.id);
      expect(copy.playitAddress, config.playitAddress);
      expect(copy.playitTunnelId, 'java-a');
      expect(copy.allowCommands, isFalse);
      expect(copy.backupRetention, 5);
    });

    test('copyWith only replaces named fields', () {
      final ServerConfig copy = config.copyWith(name: 'Renamed', memoryMb: 2048);
      expect(copy.name, 'Renamed');
      expect(copy.memoryMb, 2048);
      expect(copy.repoFull, 'octocat/nova-island');
      expect(copy.mcVersion, config.mcVersion);
    });

    test('fabric servers support mods and not plugins', () {
      final ServerConfig fabric = config.copyWith(software: 'FABRIC');
      expect(fabric.supportsMods, isTrue);
      expect(fabric.supportsPlugins, isFalse);
      expect(fabric.modsFolder, 'mods');
      expect(fabric.serverPath('mods'), 'server/mods');
    });
  });

  group('ReleaseInfo backup assets', () {
    test('backup is eligible only when both archive and checksum exist', () {
      const ReleaseInfo archiveOnly = ReleaseInfo(
        id: 1,
        tag: 'backup-server-1',
        name: 'Backup',
        createdAt: '',
        assets: <ReleaseAsset>[ReleaseAsset(1, 'world-backup.zip', 10, 'https://example.test/archive.zip')],
        prerelease: false,
        isDraft: false,
      );
      const ReleaseInfo unverified = ReleaseInfo(
        id: 4,
        tag: 'backup-server-a-legacy',
        name: 'Legacy backup',
        createdAt: '',
        assets: <ReleaseAsset>[
          ReleaseAsset(4, 'world-backup.zip', 10, 'https://example.test/archive.zip'),
          ReleaseAsset(5, 'world-backup.sha256', 64, 'https://example.test/archive.sha256'),
        ],
        prerelease: false,
        isDraft: false,
        body: 'Legacy backup created before the verification marker existed.',
      );
      const ReleaseInfo draft = ReleaseInfo(
        id: 6,
        tag: 'backup-server-a-draft',
        name: 'Draft backup',
        createdAt: '',
        assets: <ReleaseAsset>[
          ReleaseAsset(6, 'world-backup.zip', 10, 'https://example.test/archive.zip'),
          ReleaseAsset(7, 'world-backup.sha256', 64, 'https://example.test/archive.sha256'),
        ],
        prerelease: false,
        isDraft: true,
        body: 'NOVA_CRAFT_BACKUP_VERIFIED',
      );
      const ReleaseInfo complete = ReleaseInfo(
        id: 2,
        tag: 'backup-server-a-20261018T120000000000Z',
        name: 'Backup',
        createdAt: '',
        assets: <ReleaseAsset>[
          ReleaseAsset(2, 'world-backup.zip', 10, 'https://example.test/archive.zip'),
          ReleaseAsset(3, 'world-backup.sha256', 64, 'https://example.test/archive.sha256'),
        ],
        prerelease: false,
        isDraft: false,
        body: 'NOVA_CRAFT_BACKUP_VERIFIED',
      );
      expect(archiveOnly.hasBackupAssets, isFalse);
      expect(complete.hasBackupAssets, isTrue);
      expect(unverified.isVerifiedBackup, isFalse);
      expect(unverified.isBackupFor('server-a'), isTrue);
      expect(complete.isVerifiedBackup, isTrue);
      expect(complete.backupArchive?.name, 'world-backup.zip');
      expect(complete.backupChecksum?.name, 'world-backup.sha256');
      expect(complete.isBackupFor('server-a'), isTrue);
      expect(complete.isBackupFor('server-b'), isFalse);
      expect(archiveOnly.isBackupFor('server-1'), isFalse);
      expect(draft.isBackupFor('server-a'), isFalse);
    });
  });

  group('LogParser', () {
    test('detects levels and timestamps', () {
      final LogEntry error = LogParser.parse('[12:00:01] [Server thread/ERROR]: Something failed');
      expect(error.level, LogLevel.error);
      expect(error.timestamp, '12:00:01');

      final LogEntry warn = LogParser.parse('[12:00:02] [Server thread/WARN]: Can\'t keep up');
      expect(warn.level, LogLevel.warn);

      final LogEntry done = LogParser.parse('[12:00:03] [Server thread/INFO]: Done (4.125s)! For help, type "help"');
      expect(done.level, LogLevel.success);

      final LogEntry command = LogParser.parse('[nova] command picked up: say hi');
      expect(command.level, LogLevel.command);
    });

    test('fromText skips blank lines', () {
      final List<LogEntry> entries = LogParser.fromText('line one\n\n line two \n');
      expect(entries.length, 2);
      expect(entries.first.text, 'line one');
    });

    test('fromJobs renders steps with marks', () {
      const WorkflowJob job = WorkflowJob(
        1,
        'start',
        'completed',
        'success',
        <JobStep>[
          JobStep('boot', 1, 'completed', 'success'),
          JobStep('playit', 2, 'completed', 'failure'),
        ],
        null,
      );
      final List<LogEntry> entries = LogParser.fromJobs(<WorkflowJob>[job]);
      expect(entries.length, 3);
      expect(entries[1].level, LogLevel.success);
      expect(entries[2].level, LogLevel.error);
    });
  });

  group('Workflow template', () {
    test('is generated with server settings and no placeholder leaks', () {
      final String yaml = WorkflowTemplates.serverWorkflow('srv-42');
      expect(yaml.contains('__SID__'), isFalse);
      expect(yaml.contains('srv-42'), isTrue);
      expect(yaml.contains('restore_tag'), isTrue);
      expect(yaml.contains('PLAYIT_SECRET_KEY'), isTrue);
      expect(yaml.contains('nova-craft/runner.sh'), isTrue);
      expect(yaml.contains('nova-craft/config.py'), isTrue);
      expect(yaml.contains('concurrency'), isTrue);
      expect(yaml.contains('timeout-minutes: 360'), isTrue);
      expect(yaml.contains('restore-keys'), isTrue);
      expect(yaml.contains('actions/cache/restore'), isTrue);
    });

    test('java properties reflect the server config', () {
      const ServerConfig config = ServerConfig(
        id: 'x',
        name: 'Test',
        repoOwner: 'o',
        repoName: 'r',
        mcVersion: '1.21.4',
        maxPlayers: 42,
        motd: 'Hello NOVA',
        gamemode: 'creative',
        difficulty: 'hard',
        viewDistance: 12,
        simulationDistance: 8,
        memoryMb: 3072,
        playitJavaPort: 25570,
      );
      final String props = WorkflowTemplates.javaProperties(config);
      expect(props.contains('max-players=42'), isTrue);
      expect(props.contains('motd=Hello NOVA'), isTrue);
      expect(props.contains('gamemode=creative'), isTrue);
      expect(props.contains('difficulty=hard'), isTrue);
      expect(props.contains('view-distance=12'), isTrue);
      expect(props.contains('simulation-distance=8'), isTrue);
      expect(props.contains('server-port=25565'), isTrue);
      expect(props.contains('eula') || props.contains('online-mode'), isTrue);
    });
  });
}
