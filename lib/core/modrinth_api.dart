import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import 'cancellation.dart';
import 'config.dart';
import 'models.dart';

typedef ModrinthDownloadProgress = void Function(int receivedBytes, int totalBytes, bool complete);

class ModrinthDownloadLimitException implements Exception {
  const ModrinthDownloadLimitException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Modrinth file exceeds the ${maxBytes ~/ (1024 * 1024)} MiB installation limit';
}

/// Live Modrinth catalog. Browsing and installing use the public API, so no
/// placeholder entries are ever shown: an empty or failed response is rendered
/// as an error or empty state.
class ModrinthApi {
  ModrinthApi({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 25),
    this.downloadTimeout = const Duration(seconds: 90),
    this.retryDelay = const Duration(milliseconds: 350),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration requestTimeout;
  final Duration downloadTimeout;
  final Duration retryDelay;

  static const int _maxAttempts = 3;
  static const int maxDownloadBytes = 45 * 1024 * 1024;
  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'NOVA-CRAFT/1.0.0 (github.com/abiedadam0077/NOVA-CRAFT)',
    'Accept': 'application/json',
  };

  Future<dynamic> _get(
    String url, {
    required String operation,
    CancellationToken? cancellation,
  }) async {
    final Uri uri = Uri.parse(url);
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      cancellation?.throwIfCancelled();
      _log('event=request.start operation=$operation attempt=$attempt host=${uri.host}');
      try {
        final http.Response response = await _sendGet(
          uri,
          headers: _headers,
          timeout: requestTimeout,
          cancellation: cancellation,
        );
        _log('event=request.response operation=$operation status=${response.statusCode} bytes=${response.bodyBytes.length}');
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ModrinthHttpException(
            response.statusCode,
            _httpFailure('Modrinth', response.statusCode, response.body),
          );
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      } catch (error, stackTrace) {
        if (cancellation?.isCancelled == true) {
          _log('event=request.cancelled operation=$operation');
          throw const OperationCancelledException();
        }
        if (!_isRetryable(error) || attempt == _maxAttempts) {
          _log('event=request.failed operation=$operation attempt=$attempt error=${_safeError(error)}', error: error, stackTrace: stackTrace);
          rethrow;
        }
        _log('event=request.retry operation=$operation attempt=$attempt error=${_safeError(error)}');
        await _waitBeforeRetry(cancellation, attempt);
      }
    }
    throw StateError('Unreachable Modrinth request retry state');
  }

  Future<http.Response> _sendGet(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    CancellationToken? cancellation,
  }) async {
    final Completer<void> abort = Completer<void>();
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    if (cancellation != null) {
      if (cancellation.isCancelled) {
        abortRequest();
      } else {
        unawaited(cancellation.whenCancelled.then<void>((_) => abortRequest()));
      }
    }

    final http.AbortableRequest request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);

    try {
      final Future<http.Response> response = _client.send(request).then(http.Response.fromStream);
      return await response.timeout(timeout, onTimeout: () {
        abortRequest();
        throw TimeoutException('HTTP GET timed out after ${timeout.inSeconds}s (${uri.host})');
      });
    } catch (_) {
      if (cancellation?.isCancelled == true) throw const OperationCancelledException();
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendStreamGet(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required CancellationToken? cancellation,
    required Completer<void> abort,
  }) async {
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    if (cancellation != null) {
      if (cancellation.isCancelled) {
        abortRequest();
      } else {
        unawaited(cancellation.whenCancelled.then<void>((_) => abortRequest()));
      }
    }

    final http.AbortableRequest request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);

    try {
      return await _client.send(request).timeout(timeout, onTimeout: () {
        abortRequest();
        throw TimeoutException('HTTP GET timed out after ${timeout.inSeconds}s (${uri.host})');
      });
    } catch (_) {
      if (cancellation?.isCancelled == true) throw const OperationCancelledException();
      rethrow;
    }
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
    final dynamic data = await _get(uri.toString(), operation: 'search');
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
    CancellationToken? cancellation,
  }) async {
    final Map<String, String> params = <String, String>{};
    if (loader != null && loader.isNotEmpty) params['loaders'] = jsonEncode(<String>[loader]);
    if (gameVersion != null && gameVersion.isNotEmpty) params['game_versions'] = jsonEncode(<String>[gameVersion]);
    final Uri uri = Uri.parse('${AppConfig.modrinthApi}/project/$projectId/version').replace(queryParameters: params);
    final dynamic data = await _get(uri.toString(), operation: 'versions', cancellation: cancellation);
    final List<ModrinthVersion> out = <ModrinthVersion>[];
    if (data is List) {
      for (final dynamic raw in data) {
        if (raw is Map) out.add(ModrinthVersion.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  /// Streams a Modrinth version file, reports byte progress, validates its
  /// advertised size/hash, and retries only transport failures or truncation.
  /// Invalid or partial bytes are never returned to the caller for upload.
  Future<Uint8List> download(
    ModrinthVersionFile file, {
    CancellationToken? cancellation,
    ModrinthDownloadProgress? onProgress,
  }) async {
    if (file.size > maxDownloadBytes) throw const ModrinthDownloadLimitException(maxDownloadBytes);
    final Uri uri = _validatedFileUri(file.url);
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      cancellation?.throwIfCancelled();
      _log('event=download.start attempt=$attempt host=${uri.host} file=${file.filename} expectedBytes=${file.size}');
      final Stopwatch elapsed = Stopwatch()..start();
      final Completer<void> abort = Completer<void>();
      void abortRequest() {
        if (!abort.isCompleted) abort.complete();
      }
      try {
        final http.StreamedResponse response = await _sendStreamGet(
          uri,
          headers: const <String, String>{'User-Agent': 'NOVA-CRAFT/1.0.0'},
          timeout: downloadTimeout,
          cancellation: cancellation,
          abort: abort,
        );
        _log('event=download.response attempt=$attempt status=${response.statusCode} file=${file.filename}');
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final String body = await _readErrorBody(
            response.stream,
            _remainingDownloadTime(elapsed, uri),
            abortRequest,
          );
          throw ModrinthHttpException(
            response.statusCode,
            _httpFailure('Modrinth file download', response.statusCode, body),
          );
        }

        final int expectedBytes = file.size > 0 ? file.size : (response.contentLength ?? 0);
        if (expectedBytes > maxDownloadBytes) throw const ModrinthDownloadLimitException(maxDownloadBytes);
        onProgress?.call(0, expectedBytes, false);
        final BytesBuilder builder = BytesBuilder(copy: false);
        int receivedBytes = 0;
        final Future<Uint8List> collect = () async {
          await for (final List<int> chunk in response.stream) {
            cancellation?.throwIfCancelled();
            receivedBytes += chunk.length;
            if (receivedBytes > maxDownloadBytes) throw const ModrinthDownloadLimitException(maxDownloadBytes);
            if (expectedBytes > 0 && receivedBytes > expectedBytes) {
              throw ModrinthIncompleteDownloadException(
                expectedBytes: expectedBytes,
                receivedBytes: receivedBytes,
              );
            }
            builder.add(chunk);
            onProgress?.call(receivedBytes, expectedBytes, false);
          }
          return builder.takeBytes();
        }();
        final Uint8List bytes = await collect.timeout(
          _remainingDownloadTime(elapsed, uri),
          onTimeout: () {
            abortRequest();
            throw TimeoutException('Modrinth download timed out after ${downloadTimeout.inSeconds}s');
          },
        );
        cancellation?.throwIfCancelled();
        if (bytes.isEmpty || (expectedBytes > 0 && bytes.length != expectedBytes)) {
          throw ModrinthIncompleteDownloadException(
            expectedBytes: expectedBytes,
            receivedBytes: bytes.length,
          );
        }
        _verifyHashes(file, bytes);
        onProgress?.call(bytes.length, expectedBytes, true);
        _log('event=download.verified file=${file.filename} bytes=${bytes.length} hash=${_verifiedHashName(file)}');
        return bytes;
      } catch (error, stackTrace) {
        abortRequest();
        if (cancellation?.isCancelled == true || error is OperationCancelledException) {
          _log('event=download.cancelled file=${file.filename}');
          throw const OperationCancelledException();
        }
        if (!_isRetryable(error) || attempt == _maxAttempts) {
          _log('event=download.failed attempt=$attempt file=${file.filename} error=${_safeError(error)}', error: error, stackTrace: stackTrace);
          rethrow;
        }
        _log('event=download.retry attempt=$attempt file=${file.filename} error=${_safeError(error)}');
        await _waitBeforeRetry(cancellation, attempt);
      }
    }
    throw StateError('Unreachable Modrinth download retry state');
  }

  Duration _remainingDownloadTime(Stopwatch elapsed, Uri uri) {
    final Duration remaining = downloadTimeout - elapsed.elapsed;
    if (remaining.compareTo(Duration.zero) <= 0) {
      throw TimeoutException('Modrinth download timed out after ${downloadTimeout.inSeconds}s (${uri.host})');
    }
    return remaining;
  }

  Future<String> _readErrorBody(
    Stream<List<int>> stream,
    Duration timeout,
    void Function() abortRequest,
  ) async {
    final StreamIterator<List<int>> iterator = StreamIterator<List<int>>(stream);
    final BytesBuilder builder = BytesBuilder(copy: false);
    const int maxErrorBytes = 64 * 1024;
    int collected = 0;
    final Future<String> read = () async {
      while (collected < maxErrorBytes && await iterator.moveNext()) {
        final List<int> chunk = iterator.current;
        final int take = chunk.length < maxErrorBytes - collected ? chunk.length : maxErrorBytes - collected;
        builder.add(chunk.sublist(0, take));
        collected += take;
      }
      return utf8.decode(builder.takeBytes(), allowMalformed: true);
    }();
    try {
      return await read.timeout(timeout, onTimeout: () {
        abortRequest();
        throw TimeoutException('Modrinth error response timed out');
      });
    } finally {
      await iterator.cancel();
    }
  }

  static Uri _validatedFileUri(String raw) {
    final Uri uri = Uri.tryParse(raw) ?? Uri();
    if (uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'cdn.modrinth.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Modrinth returned an invalid or untrusted download URL');
    }
    return uri;
  }

  static void _verifyHashes(ModrinthVersionFile file, Uint8List bytes) {
    final Map<String, String Function()> actual = <String, String Function()>{
      'sha512': () => crypto.sha512.convert(bytes).toString(),
      'sha256': () => crypto.sha256.convert(bytes).toString(),
      'sha1': () => crypto.sha1.convert(bytes).toString(),
      'md5': () => crypto.md5.convert(bytes).toString(),
    };
    for (final String algorithm in <String>['sha512', 'sha256', 'sha1', 'md5']) {
      final String? expected = file.hashes[algorithm];
      if (expected == null || expected.isEmpty) continue;
      if (actual[algorithm]!().toLowerCase() != expected.toLowerCase()) {
        throw ModrinthIntegrityException('The downloaded JAR failed its Modrinth $algorithm checksum.');
      }
      return;
    }
  }

  static String _verifiedHashName(ModrinthVersionFile file) {
    for (final String algorithm in <String>['sha512', 'sha256', 'sha1', 'md5']) {
      if (file.hashes[algorithm]?.isNotEmpty == true) return algorithm;
    }
    return 'size-only';
  }

  static bool _isRetryable(Object error) {
    if (error is ModrinthIncompleteDownloadException ||
        error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException) {
      return true;
    }
    if (error is ApiException) {
      return const <int>{408, 425, 429, 500, 502, 503, 504}.contains(error.status);
    }
    return false;
  }

  Future<void> _waitBeforeRetry(CancellationToken? cancellation, int attempt) async {
    final Duration delay = retryDelay * attempt;
    if (cancellation == null) {
      await Future<void>.delayed(delay);
    } else {
      await cancellation.waitOrCancel(delay);
    }
  }

  static String _httpFailure(String service, int status, String body) {
    String detail = '';
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map) {
        detail = (decoded['description'] ?? decoded['error'] ?? decoded['message'] ?? '').toString();
      }
    } catch (_) {
      // Do not include arbitrary HTML/response bodies in user-facing errors.
    }
    if (detail.length > 180) detail = '${detail.substring(0, 180)}…';
    return '$service returned HTTP $status${detail.isEmpty ? '' : ': $detail'}';
  }

  static String _safeError(Object error) {
    if (error is ApiException) return 'HTTP ${error.status}: ${error.message}';
    if (error is TimeoutException) return 'timeout: ${error.message ?? 'request timed out'}';
    if (error is ModrinthIntegrityException || error is ModrinthIncompleteDownloadException) return error.toString();
    if (error is http.ClientException) return 'network: ${error.message}';
    if (error is SocketException) return 'network: ${error.message}';
    return error.runtimeType.toString();
  }

  static void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'NOVA_CRAFT.ModrinthInstall',
      level: error == null ? 800 : 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void dispose() => _client.close();
}

class ModrinthHttpException extends ApiException {
  ModrinthHttpException(super.status, super.message);
}

class ModrinthIncompleteDownloadException implements Exception {
  const ModrinthIncompleteDownloadException({required this.expectedBytes, required this.receivedBytes});

  final int expectedBytes;
  final int receivedBytes;

  @override
  String toString() => 'Incomplete download: expected $expectedBytes bytes, received $receivedBytes';
}

class ModrinthIntegrityException implements Exception {
  const ModrinthIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
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

/// Install-time check uses repository configuration, not a displayed label.
bool modrinthCompatibleWithServer(
  ModrinthProject project,
  ModrinthVersion version,
  ServerConfig server,
) {
  if (project.projectType.toLowerCase() != 'plugin' || !server.isJava || !server.supportsPlugins) return false;
  final String gameVersion = server.mcVersion.trim();
  if (gameVersion.isEmpty) return false;
  final List<String> loaders = modrinthAllowedLoaders(
    plugins: true,
    serverLoader: server.software.toLowerCase(),
  );
  return modrinthCompatible(version, allowedLoaders: loaders, gameVersion: gameVersion);
}

/// Folder a jar must be written to, relative to the repository root. This is
/// always inside the server data root, never the repository root itself.
String modrinthInstallFolder({required bool plugins, required String serverRoot}) =>
    '$serverRoot/${plugins ? 'plugins' : 'mods'}';

class ModrinthVersionFile {
  const ModrinthVersionFile({
    required this.url,
    required this.filename,
    required this.size,
    this.primary = false,
    this.hashes = const <String, String>{},
  });

  final String url;
  final String filename;
  final int size;
  final bool primary;
  final Map<String, String> hashes;

  factory ModrinthVersionFile.fromJson(Map<String, dynamic> o) => ModrinthVersionFile(
        url: o['url']?.toString() ?? '',
        filename: o['filename']?.toString() ?? '',
        size: (o['size'] as num?)?.toInt() ?? 0,
        primary: o['primary'] == true,
        hashes: o['hashes'] is Map
            ? Map<String, String>.fromEntries(
                (o['hashes'] as Map).entries.map((MapEntry<dynamic, dynamic> entry) =>
                    MapEntry<String, String>(entry.key.toString().toLowerCase(), entry.value.toString())),
              )
            : const <String, String>{},
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

  /// Select Modrinth's explicitly primary file. If older metadata omits the
  /// flag, accept an unambiguous single file or a single JAR; never guess when
  /// multiple artifacts are present.
  ModrinthVersionFile? get primaryFile {
    final List<ModrinthVersionFile> declared = files.where((ModrinthVersionFile file) => file.primary).toList();
    if (declared.length == 1) return declared.single;
    if (declared.length > 1) return null;
    if (files.length == 1) return files.single;
    final List<ModrinthVersionFile> jars = files
        .where((ModrinthVersionFile file) => file.filename.toLowerCase().endsWith('.jar'))
        .toList();
    return jars.length == 1 ? jars.single : null;
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
