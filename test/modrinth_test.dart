import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/modrinth_api.dart';

ModrinthVersion _version({
  List<String> loaders = const <String>['fabric'],
  List<String> gameVersions = const <String>['1.21.4'],
  List<ModrinthVersionFile> files = const <ModrinthVersionFile>[],
}) {
  return ModrinthVersion(
    id: 'ver-1',
    versionNumber: '1.2.3',
    name: 'Example 1.2.3',
    gameVersions: gameVersions,
    loaders: loaders,
    files: files,
    datePublished: '2026-01-02T00:00:00Z',
  );
}

void main() {
  group('Modrinth loader families', () {
    test('fabric and quilt mods are allowed on a fabric server', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: false, serverLoader: 'fabric');
      expect(allowed, <String>['fabric', 'quilt']);
      expect(modrinthLoaderMatches(_version(loaders: <String>['fabric']), allowed), isTrue);
      expect(modrinthLoaderMatches(_version(loaders: <String>['quilt']), allowed), isTrue);
    });

    test('a paper plugin is rejected on a modded server instead of being installed', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: false, serverLoader: 'fabric');
      expect(modrinthLoaderMatches(_version(loaders: <String>['paper']), allowed), isFalse);
    });

    test('paper, purpur, spigot and bukkit plugins are accepted on paper', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: true, serverLoader: 'paper');
      for (final String loader in <String>['paper', 'purpur', 'spigot', 'bukkit']) {
        expect(modrinthLoaderMatches(_version(loaders: <String>[loader]), allowed), isTrue, reason: loader);
      }
      expect(modrinthLoaderMatches(_version(loaders: <String>['fabric']), allowed), isFalse);
    });

    test('purpur accepts its whole plugin family and rejects mods', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: true, serverLoader: 'purpur');
      expect(allowed, containsAll(<String>['purpur', 'paper', 'spigot', 'bukkit']));
      expect(modrinthLoaderMatches(_version(loaders: <String>['quilt']), allowed), isFalse);
    });

    test('an unknown plugin platform still only allows the plugin family', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: true, serverLoader: null);
      expect(allowed, isNot(contains('fabric')));
      expect(allowed, contains('paper'));
    });
  });

  group('Modrinth version filtering', () {
    test('a jar for another Minecraft version never matches', () {
      final ModrinthVersion version = _version(gameVersions: <String>['1.20.1']);
      expect(modrinthVersionMatches(version, '1.21.4'), isFalse);
    });

    test('a jar listing several game versions matches any of them', () {
      final ModrinthVersion version = _version(gameVersions: <String>['1.20.1', '1.21.4']);
      expect(modrinthVersionMatches(version, '1.21.4'), isTrue);
    });

    test('an unknown server version accepts instead of guessing a mismatch', () {
      expect(modrinthVersionMatches(_version(gameVersions: <String>['1.20.1']), ''), isTrue);
    });

    test('compatibility requires both the loader and the game version', () {
      final List<String> allowed = modrinthAllowedLoaders(plugins: false, serverLoader: 'fabric');
      final ModrinthVersion good = _version();
      final ModrinthVersion wrongVersion = _version(gameVersions: <String>['1.19.4']);
      final ModrinthVersion wrongLoader = _version(loaders: <String>['paper']);
      expect(modrinthCompatible(good, allowedLoaders: allowed, gameVersion: '1.21.4'), isTrue);
      expect(modrinthCompatible(wrongVersion, allowedLoaders: allowed, gameVersion: '1.21.4'), isFalse);
      expect(modrinthCompatible(wrongLoader, allowedLoaders: allowed, gameVersion: '1.21.4'), isFalse);
    });
  });

  group('Modrinth install folders', () {
    test('mods and plugins go under the server data root, never the repo root', () {
      expect(modrinthInstallFolder(plugins: false, serverRoot: 'server'), 'server/mods');
      expect(modrinthInstallFolder(plugins: true, serverRoot: 'server'), 'server/plugins');
    });

    test('a custom data root is honoured', () {
      expect(modrinthInstallFolder(plugins: true, serverRoot: 'data/mc'), 'data/mc/plugins');
      expect(modrinthInstallFolder(plugins: false, serverRoot: 'data/mc'), startsWith('data/mc/'));
    });
  });

  group('Modrinth version parsing', () {
    test('a real version payload keeps files, loaders and game versions', () {
      final ModrinthVersion version = ModrinthVersion.fromJson(<String, dynamic>{
        'id': 'abc123',
        'version_number': '2.0.1',
        'name': 'Sodium 2.0.1',
        'game_versions': <String>['1.21.4'],
        'loaders': <String>['fabric'],
        'date_published': '2026-02-03T10:00:00Z',
        'files': <Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://cdn.modrinth.com/data/abc/versions/def/sodium.jar',
            'filename': 'sodium.jar',
            'size': 123456,
          },
        ],
      });
      expect(version.id, 'abc123');
      expect(version.loaders, <String>['fabric']);
      expect(version.gameVersions, <String>['1.21.4']);
      expect(version.primaryFile?.filename, 'sodium.jar');
      expect(version.primaryFile?.size, 123456);
      expect(version.supports('fabric', '1.21.4'), isTrue);
      expect(version.supports('paper', '1.21.4'), isFalse);
    });

    test('a version without files is never considered installable', () {
      final ModrinthVersion version = ModrinthVersion.fromJson(<String, dynamic>{
        'id': 'x',
        'version_number': '1',
      });
      expect(version.primaryFile, isNull);
      expect(version.gameVersions, isEmpty);
      expect(version.loaders, isEmpty);
    });
  });
}
