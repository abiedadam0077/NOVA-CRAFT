import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Server software we can actually provision end-to-end.
enum ServerSoftware { vanilla, paper, purpur, fabric }

extension ServerSoftwareInfo on ServerSoftware {
  String get id {
    switch (this) {
      case ServerSoftware.vanilla:
        return 'VANILLA';
      case ServerSoftware.paper:
        return 'PAPER';
      case ServerSoftware.purpur:
        return 'PURPUR';
      case ServerSoftware.fabric:
        return 'FABRIC';
    }
  }

  String get label {
    switch (this) {
      case ServerSoftware.vanilla:
        return 'Vanilla';
      case ServerSoftware.paper:
        return 'Paper';
      case ServerSoftware.purpur:
        return 'Purpur';
      case ServerSoftware.fabric:
        return 'Fabric';
    }
  }

  static ServerSoftware fromId(String id) {
    switch (id.toUpperCase()) {
      case 'PAPER':
        return ServerSoftware.paper;
      case 'PURPUR':
        return ServerSoftware.purpur;
      case 'FABRIC':
        return ServerSoftware.fabric;
      default:
        return ServerSoftware.vanilla;
    }
  }
}

/// One concrete downloadable server build.
class ServerBuild {
  const ServerBuild({
    required this.software,
    required this.mcVersion,
    required this.url,
    required this.hash,
    required this.hashKind,
    required this.javaMajor,
    required this.label,
    this.buildId = '',
  });

  final ServerSoftware software;
  final String mcVersion;
  final String url;
  final String hash;
  final String hashKind; // sha256 | sha1 | md5 | ''
  final int javaMajor;
  final String label;
  final String buildId;

  ResolvedDownload toDownload() => ResolvedDownload(
        url: url,
        sha: hash,
        javaMajor: javaMajor,
        label: label,
      );
}

/// Live version and software resolution from the official Mojang metadata and
/// the official project APIs (PaperMC Fill v3, PurpurMC v2, Fabric meta).
///
/// Nothing in the picker is invented: a version/software combination is only
/// offered when the upstream API really serves a downloadable build for it, and
/// every resolved URL is validated before a repository is written.
class MinecraftApi {
  MinecraftApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _manifestUrl = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
  static const String _fillApi = 'https://fill.papermc.io/v3';
  static const String _purpurApi = 'https://api.purpurmc.org/v2/purpur';
  static const String _fabricMeta = 'https://meta.fabricmc.net/v2';

  Map<String, String> get _headers => <String, String>{
        'User-Agent': AppConfig.userAgent,
        'Accept': 'application/json',
      };

  Future<dynamic> _getJson(String url) async {
    final http.Response response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'HTTP ${response.statusCode} for $url');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ---------------------------------------------------------------- Mojang --

  /// All released Minecraft Java versions, newest first.
  Future<List<McVersion>> javaReleases() async {
    final dynamic data = await _getJson(_manifestUrl);
    final List<McVersion> out = <McVersion>[];
    if (data is Map && data['versions'] is List) {
      for (final dynamic raw in data['versions'] as List) {
        if (raw is Map && raw['type'] == 'release') {
          final String id = raw['id'].toString();
          if (_isReleaseId(id)) out.add(McVersion(id, 'release'));
        }
      }
    }
    return out;
  }

  /// Filters out pre-releases, release candidates and old alpha/beta ids.
  static bool _isReleaseId(String id) {
    if (!RegExp(r'^[0-9]+(\.[0-9]+)+$').hasMatch(id)) return false;
    return true;
  }

  Future<ResolvedDownload> resolveVanilla(String version) async {
    final dynamic manifest = await _getJson(_manifestUrl);
    String? detailUrl;
    if (manifest is Map && manifest['versions'] is List) {
      for (final dynamic raw in manifest['versions'] as List) {
        if (raw is Map && raw['id'] == version) {
          detailUrl = raw['url']?.toString();
          break;
        }
      }
    }
    if (detailUrl == null) throw ApiException(404, 'Minecraft $version is not in the official manifest');
    final dynamic detail = await _getJson(detailUrl);
    final Map<String, dynamic> downloads = detail is Map && detail['downloads'] is Map
        ? Map<String, dynamic>.from(detail['downloads'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> server = downloads['server'] is Map
        ? Map<String, dynamic>.from(downloads['server'] as Map)
        : <String, dynamic>{};
    final String url = server['url']?.toString() ?? '';
    if (url.isEmpty) throw ApiException(404, 'Minecraft $version has no dedicated server download');
    final int javaMajor = detail is Map && detail['javaVersion'] is Map
        ? ((detail['javaVersion'] as Map)['majorVersion'] as num?)?.toInt() ?? javaForMc(version)
        : javaForMc(version);
    return ResolvedDownload(
      url: url,
      sha: server['sha1']?.toString() ?? '',
      javaMajor: javaMajor,
      label: 'Vanilla $version',
    );
  }

  // --------------------------------------------------------------- PaperMC --

  /// Paper versions, newest first. The old `api.papermc.io/v2` endpoint stopped
  /// receiving builds on 2025-12-31 and is disabled since 2026-07-01, so the
  /// Fill v3 API is the only source used here.
  Future<List<String>> paperVersions() async {
    final dynamic data = await _getJson('$_fillApi/projects/paper');
    final List<String> out = <String>[];
    if (data is Map && data['versions'] is Map) {
      final Map<String, dynamic> groups = Map<String, dynamic>.from(data['versions'] as Map);
      for (final dynamic value in groups.values) {
        if (value is List) {
          for (final dynamic v in value) {
            final String id = v.toString();
            if (_isReleaseId(id) && !out.contains(id)) out.add(id);
          }
        }
      }
    }
    return out;
  }

  Future<ResolvedDownload> resolvePaper(String version) async {
    Map<String, dynamic>? chosen;
    try {
      final dynamic data = await _getJson('$_fillApi/projects/paper/versions/$version/builds');
      final dynamic list = data is Map ? data['builds'] : data;
      if (list is List) {
        for (final dynamic raw in list) {
          if (raw is! Map) continue;
          final Map<String, dynamic> build = Map<String, dynamic>.from(raw);
          final String channel = build['channel']?.toString().toUpperCase() ?? '';
          if (channel == 'STABLE' || channel == 'RECOMMENDED') {
            chosen = build;
            break;
          }
        }
      }
    } on ApiException {
      chosen = null;
    }
    if (chosen == null) {
      // Some projects answer the version's build list with a single object.
      try {
        final dynamic latest = await _getJson('$_fillApi/projects/paper/versions/$version/builds/latest');
        if (latest is Map) {
          final Map<String, dynamic> build = Map<String, dynamic>.from(latest);
          final String channel = build['channel']?.toString().toUpperCase() ?? '';
          if (channel == 'STABLE' || channel == 'RECOMMENDED') chosen = build;
        }
      } on ApiException {
        chosen = null;
      }
    }
    if (chosen == null) {
      throw ApiException(404, 'Paper has no stable build for $version (experimental builds are not used)');
    }
    final Map<String, dynamic> downloads = chosen['downloads'] is Map
        ? Map<String, dynamic>.from(chosen['downloads'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> server = downloads['server:default'] is Map
        ? Map<String, dynamic>.from(downloads['server:default'] as Map)
        : <String, dynamic>{};
    final String url = server['url']?.toString() ?? '';
    if (url.isEmpty) throw ApiException(404, 'Paper build for $version has no server download');
    final Map<String, dynamic> checksums = server['checksums'] is Map
        ? Map<String, dynamic>.from(server['checksums'] as Map)
        : <String, dynamic>{};
    final int buildId = (chosen['id'] as num?)?.toInt() ?? 0;
    return ServerBuild(
      software: ServerSoftware.paper,
      mcVersion: version,
      url: url,
      hash: checksums['sha256']?.toString() ?? '',
      hashKind: 'sha256',
      javaMajor: javaForMc(version),
      label: 'Paper $version #$buildId',
      buildId: '$buildId',
    ).toDownload();
  }

  // ------------------------------------------------------------- PurpurMC --

  Future<List<String>> purpurVersions() async {
    final dynamic data = await _getJson(_purpurApi);
    final List<String> out = <String>[];
    if (data is Map && data['versions'] is List) {
      for (final dynamic v in data['versions'] as List) {
        final String id = v.toString();
        if (_isReleaseId(id)) out.add(id);
      }
    }
    out.sort(_compareMcVersions);
    return out.reversed.toList();
  }

  Future<ServerBuild> resolvePurpurBuild(String version) async {
    final dynamic data = await _getJson('$_purpurApi/$version');
    if (data is! Map) throw ApiException(404, 'Purpur has no metadata for $version');
    final dynamic builds = data['builds'];
    String? latest;
    if (builds is Map) latest = builds['latest']?.toString();
    if (latest == null || latest.isEmpty) throw ApiException(404, 'Purpur has no builds for $version');
    String md5 = '';
    try {
      final dynamic detail = await _getJson('$_purpurApi/$version/$latest');
      if (detail is Map) md5 = detail['md5']?.toString() ?? '';
    } catch (_) {
      md5 = '';
    }
    return ServerBuild(
      software: ServerSoftware.purpur,
      mcVersion: version,
      url: '$_purpurApi/$version/$latest/download',
      hash: md5,
      hashKind: 'md5',
      javaMajor: javaForMc(version),
      label: 'Purpur $version #$latest',
      buildId: latest,
    );
  }

  Future<ResolvedDownload> resolvePurpur(String version) async => (await resolvePurpurBuild(version)).toDownload();

  // --------------------------------------------------------------- Fabric --

  Future<List<String>> fabricLoaders(String mcVersion) async {
    try {
      final dynamic data = await _getJson('$_fabricMeta/versions/loader/$mcVersion');
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
    } on ApiException {
      return <String>[];
    }
  }

  Future<ServerBuild> resolveFabricBuild(String mcVersion) async {
    final List<String> loaders = await fabricLoaders(mcVersion);
    if (loaders.isEmpty) throw ApiException(404, 'Fabric has no stable loader for Minecraft $mcVersion');
    final ResolvedDownload vanilla = await resolveVanilla(mcVersion);
    final String loader = loaders.first;
    return ServerBuild(
      software: ServerSoftware.fabric,
      mcVersion: mcVersion,
      url: '$_fabricMeta/versions/loader/$mcVersion/$loader/server/jar',
      hash: '',
      hashKind: '',
      javaMajor: vanilla.javaMajor,
      label: 'Fabric $loader for Minecraft $mcVersion',
      buildId: loader,
    );
  }

  Future<ResolvedDownload> resolveFabric(String mcVersion) async => (await resolveFabricBuild(mcVersion)).toDownload();

  // ------------------------------------------------------------ Aggregate --

  /// Resolves a build for every supported software so the wizard can grey out
  /// combinations that would fail later. Never throws for a single software.
  Future<Map<ServerSoftware, String?>> availability(String mcVersion) async {
    final Map<ServerSoftware, String?> result = <ServerSoftware, String?>{};
    for (final ServerSoftware software in ServerSoftware.values) {
      try {
        await resolveBuild(software, mcVersion);
        result[software] = null;
      } catch (error) {
        result[software] = error is ApiException ? error.message : error.toString();
      }
    }
    return result;
  }

  Future<ServerBuild> resolveBuild(ServerSoftware software, String mcVersion) async {
    switch (software) {
      case ServerSoftware.paper:
        final ResolvedDownload d = await resolvePaper(mcVersion);
        return ServerBuild(
          software: software,
          mcVersion: mcVersion,
          url: d.url,
          hash: d.sha,
          hashKind: 'sha256',
          javaMajor: d.javaMajor,
          label: d.label,
        );
      case ServerSoftware.purpur:
        return resolvePurpurBuild(mcVersion);
      case ServerSoftware.fabric:
        return resolveFabricBuild(mcVersion);
      case ServerSoftware.vanilla:
        final ResolvedDownload d = await resolveVanilla(mcVersion);
        return ServerBuild(
          software: software,
          mcVersion: mcVersion,
          url: d.url,
          hash: d.sha,
          hashKind: 'sha1',
          javaMajor: d.javaMajor,
          label: d.label,
        );
    }
  }

  /// Verifies the build URL really answers before the repository is written.
  Future<void> verifyBuild(ServerBuild build) async {
    final http.Response response = await _client
        .head(Uri.parse(build.url), headers: <String, String>{'User-Agent': AppConfig.userAgent})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw ApiException(response.statusCode, 'Download is not available (HTTP ${response.statusCode})');
    }
    final String? length = response.headers['content-length'];
    if (length != null && int.tryParse(length) == 0) {
      throw ApiException(502, 'Download endpoint returned an empty file');
    }
  }

  /// Minecraft's required Java major, based on Mojang's own metadata where
  /// possible. The 2026 "26.x" versioning requires Java 25, 1.20.5+ and 1.21.x
  /// require 21, 1.18+ require 17 and 1.17 requires 16.
  int javaForMc(String version) {
    final List<int> parts = version.split('.').map((String p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    if (parts.isNotEmpty && parts.first >= 26) return 25;
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

  static int _compareMcVersions(String a, String b) {
    final List<int> pa = a.split('.').map((String p) => int.tryParse(p) ?? 0).toList();
    final List<int> pb = b.split('.').map((String p) => int.tryParse(p) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final int va = i < pa.length ? pa[i] : 0;
      final int vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
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
