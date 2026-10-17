import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Live version and software resolution from the official Mojang metadata and
/// primary project APIs. Nothing in the picker is invented: if an API fails the
/// UI shows an error instead of a hard-coded list.
class MinecraftApi {
  MinecraftApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<dynamic> _getJson(String url) async {
    final http.Response response = await _client.get(
      Uri.parse(url),
      headers: <String, String>{'User-Agent': AppConfig.userAgent, 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'HTTP ${response.statusCode} for $url');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<McVersion>> javaReleases() async {
    final dynamic data = await _getJson('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json');
    final List<McVersion> out = <McVersion>[];
    if (data is Map && data['versions'] is List) {
      for (final dynamic raw in data['versions'] as List) {
        if (raw is Map && raw['type'] == 'release') {
          out.add(McVersion(raw['id'].toString(), 'release'));
        }
      }
    }
    return out;
  }

  Future<ResolvedDownload> resolveVanilla(String version) async {
    final dynamic manifest = await _getJson('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json');
    String? detailUrl;
    if (manifest is Map && manifest['versions'] is List) {
      for (final dynamic raw in manifest['versions'] as List) {
        if (raw is Map && raw['id'] == version) {
          detailUrl = raw['url']?.toString();
          break;
        }
      }
    }
    if (detailUrl == null) throw ApiException(404, 'Version $version not found');
    final dynamic detail = await _getJson(detailUrl);
    final Map<String, dynamic> downloads = detail is Map && detail['downloads'] is Map
        ? Map<String, dynamic>.from(detail['downloads'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> server = downloads['server'] is Map
        ? Map<String, dynamic>.from(downloads['server'] as Map)
        : <String, dynamic>{};
    final String url = server['url']?.toString() ?? '';
    if (url.isEmpty) throw ApiException(404, 'No server download for $version');
    final int javaMajor = detail is Map && detail['javaVersion'] is Map
        ? ((detail['javaVersion'] as Map)['majorVersion'] as num?)?.toInt() ?? 21
        : 21;
    return ResolvedDownload(
      url: url,
      sha: server['sha1']?.toString() ?? '',
      javaMajor: javaMajor,
      label: 'Vanilla $version',
    );
  }

  Future<List<String>> paperVersions() async {
    final dynamic data = await _getJson('https://api.papermc.io/v2/projects/paper');
    final List<String> out = <String>[];
    if (data is Map && data['versions'] is List) {
      for (final dynamic v in data['versions'] as List) {
        out.add(v.toString());
      }
    }
    return out.reversed.toList();
  }

  Future<ResolvedDownload> resolvePaper(String version) async {
    final dynamic data = await _getJson('https://api.papermc.io/v2/projects/paper/versions/$version/builds');
    final List<dynamic> builds = data is Map && data['builds'] is List ? data['builds'] as List : <dynamic>[];
    if (builds.isEmpty) throw ApiException(404, 'No Paper build for $version');
    Map<String, dynamic>? chosen;
    for (int i = builds.length - 1; i >= 0; i--) {
      final dynamic raw = builds[i];
      if (raw is Map && raw['channel']?.toString() == 'default') {
        chosen = Map<String, dynamic>.from(raw);
        break;
      }
    }
    final Map<String, dynamic> build = chosen ?? Map<String, dynamic>.from(builds.last as Map);
    final Map<String, dynamic> downloads = Map<String, dynamic>.from(build['downloads'] as Map);
    final Map<String, dynamic> application = Map<String, dynamic>.from(downloads['application'] as Map);
    final String name = application['name'].toString();
    final int buildNumber = (build['build'] as num?)?.toInt() ?? 0;
    return ResolvedDownload(
      url: 'https://api.papermc.io/v2/projects/paper/versions/$version/builds/$buildNumber/downloads/$name',
      sha: application['sha256']?.toString() ?? '',
      javaMajor: javaForMc(version),
      label: 'Paper $version #$buildNumber',
    );
  }

  Future<List<String>> purpurVersions() async {
    final dynamic data = await _getJson('https://api.purpurmc.org/v2/purpur');
    final List<String> out = <String>[];
    if (data is Map && data['versions'] is List) {
      for (final dynamic v in data['versions'] as List) {
        out.add(v.toString());
      }
    }
    return out.reversed.toList();
  }

  Future<ResolvedDownload> resolvePurpur(String version) async {
    return ResolvedDownload(
      url: 'https://api.purpurmc.org/v2/purpur/$version/latest/download',
      sha: '',
      javaMajor: javaForMc(version),
      label: 'Purpur $version (latest)',
    );
  }

  Future<List<String>> fabricLoaders(String mcVersion) async {
    try {
      final dynamic data = await _getJson('https://meta.fabricmc.net/v2/versions/loader/$mcVersion');
      final List<String> out = <String>[];
      if (data is List) {
        for (final dynamic raw in data) {
          if (raw is Map && raw['loader'] is Map) {
            final Map<String, dynamic> loader = Map<String, dynamic>.from(raw['loader'] as Map);
            if (loader['stable'] == true) out.add(loader['version'].toString());
          }
        }
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  Future<ResolvedDownload> resolveFabric(String mcVersion) async {
    final List<String> loaders = await fabricLoaders(mcVersion);
    if (loaders.isEmpty) throw ApiException(404, 'No stable Fabric loader for $mcVersion');
    final ResolvedDownload vanilla = await resolveVanilla(mcVersion);
    return ResolvedDownload(
      url: 'https://meta.fabricmc.net/v2/versions/loader/$mcVersion/${loaders.first}/1.0.1/server/jar',
      sha: '',
      javaMajor: vanilla.javaMajor,
      label: 'Fabric ${loaders.first} for $mcVersion',
    );
  }

  int javaForMc(String version) {
    final List<int> parts = version.split('.').map((String p) => int.tryParse(p) ?? 0).toList();
    if (parts.length >= 2) {
      final int minor = parts[1];
      final int patch = parts.length > 2 ? parts[2] : 0;
      if (minor > 20 || (minor == 20 && patch >= 5)) return 21;
      if (minor >= 18) return 17;
      if (minor == 17) return 16;
      return 8;
    }
    return 21;
  }

  /// Bedrock has no public version-picker API; the workflow resolves the
  /// official Linux ZIP at run time.
  ResolvedDownload bedrockPlaceholder() => const ResolvedDownload(
        url: 'https://www.minecraft.net/en-us/download/server/bedrock',
        sha: '',
        javaMajor: 0,
        label: 'Bedrock Dedicated Server (latest official)',
      );

  void dispose() => _client.close();
}
