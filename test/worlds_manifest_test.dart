import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/provisioner.dart';
import 'package:nova_craft/core/server_file_manifest.dart';

void main() {
  group('World discovery from Runner manifests', () {
    const int stamp = 1792324800;

    test('import result path matches the Runner publication path', () {
      expect(Provisioner.importResultPath, 'nova-craft/import/result.json');
    });

    test('an empty Runner manifest contains no assumed current world', () {
      final ServerFileManifest manifest = ServerFileManifest.fromJson(<String, dynamic>{
        'schema': 1,
        'generatedAt': '2026-10-18T12:00:00Z',
        'truncated': false,
        'dirs': <String>[],
        'files': <Map<String, dynamic>>[],
      });
      expect(discoverServerWorlds(manifest, isBedrock: false), isEmpty);
      expect(discoverServerWorlds(manifest, isBedrock: true), isEmpty);
    });

    test('finds Java world folders only at the server data root', () {
      final ServerFileManifest manifest = ServerFileManifest.fromJson(<String, dynamic>{
        'schema': 1,
        'generatedAt': '2026-10-18T12:00:00Z',
        'truncated': false,
        'dirs': <String>['world', 'world/region', 'custom', 'custom/region', 'worlds/Bedrock level'],
        'files': <Map<String, dynamic>>[
          <String, dynamic>{'path': 'world/level.dat', 'size': 12, 'modified': stamp},
          <String, dynamic>{'path': 'world/region/r.0.0.mca', 'size': 100, 'modified': stamp},
          <String, dynamic>{'path': 'custom/level.dat', 'size': 8, 'modified': stamp},
          <String, dynamic>{'path': 'worlds/Bedrock level/level.dat', 'size': 14, 'modified': stamp},
        ],
      });

      final List<ServerWorldInfo> worlds = discoverServerWorlds(manifest, isBedrock: false);
      expect(worlds.map((ServerWorldInfo world) => world.path), <String>['custom', 'world']);
      expect(worlds.last.name, 'world');
      expect(worlds.last.size, 112);
      expect(worlds.last.fileCount, 2);
    });

    test('finds Bedrock worlds only below the worlds folder', () {
      final ServerFileManifest manifest = ServerFileManifest.fromJson(<String, dynamic>{
        'schema': 1,
        'generatedAt': '2026-10-18T12:00:00Z',
        'truncated': false,
        'dirs': <String>['worlds', 'worlds/Bedrock level', 'worlds/Bedrock level/db', 'world'],
        'files': <Map<String, dynamic>>[
          <String, dynamic>{'path': 'worlds/Bedrock level/level.dat', 'size': 16, 'modified': stamp},
          <String, dynamic>{'path': 'worlds/Bedrock level/db/CURRENT', 'size': 4, 'modified': stamp},
          <String, dynamic>{'path': 'worlds/incomplete/level.dat', 'size': 3, 'modified': stamp},
          <String, dynamic>{'path': 'world/level.dat', 'size': 10, 'modified': stamp},
          <String, dynamic>{'path': 'Bedrock level/level.dat', 'size': 99, 'modified': stamp},
        ],
      });

      final List<ServerWorldInfo> worlds = discoverServerWorlds(manifest, isBedrock: true);
      expect(worlds, hasLength(1));
      expect(worlds.single.name, 'Bedrock level');
      expect(worlds.single.path, 'worlds/Bedrock level');
      expect(worlds.single.size, 20);
    });
  });
}
