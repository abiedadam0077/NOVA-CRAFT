import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Live Modrinth catalog. Browsing and installing use the public API, so no
/// placeholder entries are ever shown: an empty or failed response is rendered
/// as an error or empty state.
class ModrinthApi {
  ModrinthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'NOVA-CRAFT/1.0.0 (github.com/abiedadam0077/NOVA-CRAFT)',
    'Accept': 'application/json',
  };

  Future<dynamic> _get(String url) async {
    final http.Response response = await _client.get(
      Uri.parse(url),
      headers: _headers,
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Modrinth HTTP ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<ModrinthProject>> search({
    required String query,
    required String projectType,
    String? loader,
    String? gameVersion,
    int limit = 20,
    int offset = 0,
  }) async {
    final List<String> facets = <String>['["project_type:$projectType"]'];
    if (loader != null && loader.isNotEmpty) facets.add('["categories:$loader"]');
    if (gameVersion != null && gameVersion.isNotEmpty) facets.add('["versions:$gameVersion"]');
    final String facet = '[${facets.join(',')}]';
    final Uri uri = Uri.parse('${AppConfig.modrinthApi}/search').replace(queryParameters: <String, String>{
      'query': query,
      'facets': facet,
      'limit': '$limit',
      'offset': '$offset',
      'index': 'relevance',
    });
    final dynamic data = await _get(uri.toString());
    final List<ModrinthProject> out = <ModrinthProject>[];
    if (data is Map && data['hits'] is List) {
      for (final dynamic raw in data['hits'] as List) {
        if (raw is Map) out.add(ModrinthProject.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<List<ModrinthVersion>> versions(
    String projectId, {
    String? loader,
    String? gameVersion,
  }) async {
    final Map<String, String> params = <String, String>{};
    if (loader != null && loader.isNotEmpty) params['loaders'] = jsonEncode(<String>[loader]);
    if (gameVersion != null && gameVersion.isNotEmpty) params['game_versions'] = jsonEncode(<String>[gameVersion]);
    final Uri uri = Uri.parse('${AppConfig.modrinthApi}/project/$projectId/version').replace(queryParameters: params);
    final dynamic data = await _get(uri.toString());
    final List<ModrinthVersion> out = <ModrinthVersion>[];
    if (data is List) {
      for (final dynamic raw in data) {
        if (raw is Map) out.add(ModrinthVersion.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<Uint8List> download(String url) async {
    final http.Response response = await _client.get(
      Uri.parse(url),
      headers: const <String, String>{'User-Agent': 'NOVA-CRAFT/1.0.0'},
    ).timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Download failed (HTTP ${response.statusCode})');
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  void dispose() => _client.close();
}

class ModrinthProject {
  const ModrinthProject({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.iconUrl,
    required this.downloads,
    required this.author,
    required this.categories,
    required this.projectType,
  });

  final String id;
  final String slug;
  final String title;
  final String description;
  final String iconUrl;
  final int downloads;
  final String author;
  final List<String> categories;
  final String projectType;

  factory ModrinthProject.fromJson(Map<String, dynamic> o) {
    return ModrinthProject(
      id: o['project_id']?.toString() ?? o['id']?.toString() ?? '',
      slug: o['slug']?.toString() ?? '',
      title: o['title']?.toString() ?? '',
      description: o['description']?.toString() ?? '',
      iconUrl: o['icon_url']?.toString() ?? '',
      downloads: (o['downloads'] as num?)?.toInt() ?? 0,
      author: o['author']?.toString() ?? '',
      categories: (o['categories'] as List?)?.map((dynamic e) => e.toString()).toList() ?? <String>[],
      projectType: o['project_type']?.toString() ?? 'mod',
    );
  }
}

/// Loader families accepted for a Java target. `plugins` means a server-side
/// plugin platform (Paper family); otherwise client/server mods (Fabric family).
/// Modrinth returns loader names in lowercase, so the comparison is exact.
List<String> modrinthAllowedLoaders({required bool plugins, String? serverLoader}) {
  if (!plugins) return const <String>['fabric', 'quilt'];
  switch (serverLoader) {
    case 'spigot':
      return const <String>['spigot', 'bukkit', 'paper', 'purpur'];
    case 'purpur':
      return const <String>['purpur', 'paper', 'spigot', 'bukkit'];
    default:
      return const <String>['paper', 'purpur', 'spigot', 'bukkit'];
  }
}

/// True when at least one loader the version declares is accepted here.
bool modrinthLoaderMatches(ModrinthVersion version, List<String> allowedLoaders) =>
    version.loaders.any((String loader) => allowedLoaders.contains(loader));

/// True when the version supports the target game version. An empty target
/// (unknown server version) accepts any version instead of guessing.
bool modrinthVersionMatches(ModrinthVersion version, String gameVersion) =>
    gameVersion.isEmpty || version.gameVersions.contains(gameVersion);

/// Full compatibility gate used before a jar is ever downloaded or written.
bool modrinthCompatible(
  ModrinthVersion version, {
  required List<String> allowedLoaders,
  required String gameVersion,
}) =>
    modrinthLoaderMatches(version, allowedLoaders) &&
    modrinthVersionMatches(version, gameVersion);

/// Folder a jar must be written to, relative to the repository root. This is
/// always inside the server data root, never the repository root itself.
String modrinthInstallFolder({required bool plugins, required String serverRoot}) =>
    '$serverRoot/${plugins ? 'plugins' : 'mods'}';

class ModrinthVersionFile {
  const ModrinthVersionFile({required this.url, required this.filename, required this.size});

  final String url;
  final String filename;
  final int size;

  factory ModrinthVersionFile.fromJson(Map<String, dynamic> o) => ModrinthVersionFile(
        url: o['url']?.toString() ?? '',
        filename: o['filename']?.toString() ?? '',
        size: (o['size'] as num?)?.toInt() ?? 0,
      );
}

class ModrinthVersion {
  const ModrinthVersion({
    required this.id,
    required this.versionNumber,
    required this.name,
    required this.gameVersions,
    required this.loaders,
    required this.files,
    required this.datePublished,
  });

  final String id;
  final String versionNumber;
  final String name;
  final List<String> gameVersions;
  final List<String> loaders;
  final List<ModrinthVersionFile> files;
  final String datePublished;

  ModrinthVersionFile? get primaryFile {
    if (files.isEmpty) return null;
    return files.first;
  }

  bool supports(String loader, String gameVersion) {
    return loaders.contains(loader) && gameVersions.contains(gameVersion);
  }

  factory ModrinthVersion.fromJson(Map<String, dynamic> o) {
    final List<ModrinthVersionFile> parsedFiles = <ModrinthVersionFile>[];
    if (o['files'] is List) {
      for (final dynamic raw in o['files'] as List) {
        if (raw is Map) parsedFiles.add(ModrinthVersionFile.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return ModrinthVersion(
      id: o['id']?.toString() ?? '',
      versionNumber: o['version_number']?.toString() ?? '',
      name: o['name']?.toString() ?? '',
      gameVersions: (o['game_versions'] as List?)?.map((dynamic e) => e.toString()).toList() ?? <String>[],
      loaders: (o['loaders'] as List?)?.map((dynamic e) => e.toString()).toList() ?? <String>[],
      files: parsedFiles,
      datePublished: o['date_published']?.toString() ?? '',
    );
  }
}
