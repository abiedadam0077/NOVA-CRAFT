import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' show PublicKey, SealedBox;

import 'config.dart';
import 'models.dart';

/// Thin GitHub REST client. Only public identifiers are used for the OAuth
/// Device Flow: no client secret, no private key, no redirect URI.
class GitHubApi {
  GitHubApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? accessToken;
  String? lastRateLimitRemaining;

  static const Duration _timeout = Duration(seconds: 40);

  Map<String, String> _headers({bool json = true, String? token, bool acceptRaw = false}) {
    final Map<String, String> headers = <String, String>{
      'User-Agent': AppConfig.userAgent,
      if (json) 'Accept': 'application/vnd.github+json',
      if (acceptRaw) 'Accept': 'application/octet-stream',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    final String? effective = token ?? accessToken;
    if (effective != null && effective.isNotEmpty) {
      headers['Authorization'] = 'Bearer $effective';
    }
    return headers;
  }

  Future<http.Response> _send(
    String method,
    String url, {
    Object? jsonBody,
    Map<String, String>? headers,
    bool follow = true,
  }) async {
    final http.Request request = http.Request(method, Uri.parse(url));
    request.headers.addAll(headers ?? _headers());
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }
    request.followRedirects = follow;
    final http.StreamedResponse streamed = await _client.send(request).timeout(_timeout);
    final http.Response response = await http.Response.fromStream(streamed).timeout(_timeout);
    lastRateLimitRemaining = response.headers['x-ratelimit-remaining'];
    return response;
  }

  Never _throwFor(http.Response response) {
    String message = '';
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        message = decoded['message'].toString();
      }
    } catch (_) {
      // Non-JSON error body: keep a generic message, never echo secrets.
    }
    if (response.statusCode == 403 && response.headers['x-ratelimit-remaining'] == '0') {
      final String? reset = response.headers['x-ratelimit-reset'];
      final int? epoch = reset == null ? null : int.tryParse(reset);
      final String when = epoch == null
          ? ''
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal().toString().substring(11, 16);
      throw ApiException(403, 'GitHub rate limit reached${when.isEmpty ? '' : ' (resets $when)'}.');
    }
    if (message.isEmpty) message = 'GitHub ${response.statusCode}';
    throw ApiException(response.statusCode, message);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) _throwFor(response);
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ------------------------------------------------------------ Device Flow
  Future<DeviceCode> requestDeviceCode(String clientId) async {
    final http.Response response = await _client.post(
      Uri.parse(AppConfig.deviceCodeUrl),
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': AppConfig.userAgent,
      },
      body: <String, String>{'client_id': clientId, 'scope': 'offline_access'},
    ).timeout(_timeout);
    final dynamic data = _decode(response);
    if (data is! Map) throw ApiException(response.statusCode, 'Unexpected device code response');
    return DeviceCode(
      deviceCode: data['device_code']?.toString() ?? '',
      userCode: data['user_code']?.toString() ?? '',
      verificationUri: data['verification_uri']?.toString() ?? AppConfig.deviceVerificationUrl,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 900,
      interval: (data['interval'] as num?)?.toInt() ?? 5,
    );
  }

  Future<TokenPoll> pollDeviceToken(String clientId, String deviceCode) async {
    try {
      final http.Response response = await _client.post(
        Uri.parse(AppConfig.accessTokenUrl),
        headers: <String, String>{
          'Accept': 'application/json',
          'User-Agent': AppConfig.userAgent,
        },
        body: <String, String>{
          'client_id': clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      ).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return TokenPoll.failure('GitHub HTTP ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      if (data is! Map) return TokenPoll.failure('Unexpected token response');
      final String? error = data['error']?.toString();
      if (error != null && error.isNotEmpty) {
        if (error == 'authorization_pending' || error == 'slow_down') return TokenPoll.pending(error);
        return TokenPoll.failure(data['error_description']?.toString() ?? error);
      }
      final String? token = data['access_token']?.toString();
      if (token == null || token.isEmpty) return TokenPoll.failure('Empty token response');
      return TokenPoll.success(
        token,
        data['refresh_token']?.toString(),
        (data['expires_in'] as num?)?.toInt(),
      );
    } on TimeoutException {
      return TokenPoll.failure('timeout');
    } catch (error) {
      return TokenPoll.failure(error.toString());
    }
  }

  Future<TokenPoll> refreshUserToken(String clientId, String refreshToken) async {
    try {
      final http.Response response = await _client.post(
        Uri.parse(AppConfig.accessTokenUrl),
        headers: <String, String>{'Accept': 'application/json', 'User-Agent': AppConfig.userAgent},
        body: <String, String>{
          'client_id': clientId,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      ).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return TokenPoll.failure('GitHub HTTP ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      if (data is! Map) return TokenPoll.failure('Unexpected refresh response');
      final String? error = data['error']?.toString();
      if (error != null && error.isNotEmpty) return TokenPoll.failure(error);
      final String? token = data['access_token']?.toString();
      if (token == null || token.isEmpty) return TokenPoll.failure('Empty refresh response');
      return TokenPoll.success(token, data['refresh_token']?.toString(), (data['expires_in'] as num?)?.toInt());
    } catch (error) {
      return TokenPoll.failure(error.toString());
    }
  }

  // ------------------------------------------------------- user & accounts
  Future<GhUser> getUser() async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/user'));
    if (data is! Map) throw ApiException(500, 'Unexpected user response');
    return GhUser.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<GhInstallation>> listInstallations() async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/user/installations?per_page=100'));
    final List<GhInstallation> out = <GhInstallation>[];
    if (data is Map && data['installations'] is List) {
      for (final dynamic raw in data['installations'] as List) {
        if (raw is Map) {
          final Map<String, dynamic> account = raw['account'] is Map ? Map<String, dynamic>.from(raw['account'] as Map) : <String, dynamic>{};
          out.add(GhInstallation(
            (raw['id'] as num?)?.toInt() ?? 0,
            account['login']?.toString() ?? '',
            account['type']?.toString() ?? '',
          ));
        }
      }
    }
    return out;
  }

  Future<List<GhRepo>> listInstallationRepos(int installationId) async {
    final dynamic data = _decode(
      await _send('GET', '${AppConfig.githubApi}/user/installations/$installationId/repositories?per_page=100'),
    );
    final List<GhRepo> out = <GhRepo>[];
    if (data is Map && data['repositories'] is List) {
      for (final dynamic raw in data['repositories'] as List) {
        if (raw is Map) out.add(GhRepo.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<List<GhRepo>> listUserRepos() async {
    final dynamic data = _decode(
      await _send('GET', '${AppConfig.githubApi}/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator'),
    );
    final List<GhRepo> out = <GhRepo>[];
    if (data is List) {
      for (final dynamic raw in data) {
        if (raw is Map) out.add(GhRepo.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<GhRepo> createRepo(String name, bool isPrivate, String description) async {
    final dynamic data = _decode(await _send(
      'POST',
      '${AppConfig.githubApi}/user/repos',
      jsonBody: <String, dynamic>{
        'name': name,
        'private': isPrivate,
        'description': description,
        'auto_init': true,
      },
    ));
    if (data is! Map) throw ApiException(500, 'Unexpected repository response');
    return GhRepo.fromJson(Map<String, dynamic>.from(data));
  }

  Future<GhRepo> getRepo(String owner, String repo) async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo'));
    if (data is! Map) throw ApiException(500, 'Unexpected repository response');
    return GhRepo.fromJson(Map<String, dynamic>.from(data));
  }

  // --------------------------------------------------------------- contents
  Future<List<DirEntry>> listDir(String owner, String repo, String path) async {
    final String clean = _cleanPath(path);
    final Uri uri = Uri.parse('${AppConfig.githubApi}/repos/$owner/$repo/contents$clean');
    final http.Response response = await _send('GET', uri.toString());
    if (response.statusCode == 404) return <DirEntry>[];
    final dynamic data = _decode(response);
    final List<DirEntry> out = <DirEntry>[];
    if (data is List) {
      for (final dynamic raw in data) {
        if (raw is Map) out.add(DirEntry.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    out.sort((DirEntry a, DirEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<Map<String, dynamic>> _contentMeta(String owner, String repo, String path) async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}'));
    if (data is! Map) throw ApiException(400, 'Not a file');
    return Map<String, dynamic>.from(data);
  }

  Future<String> getFileText(String owner, String repo, String path) async {
    final Map<String, dynamic> meta = await _contentMeta(owner, repo, path);
    final String? content = meta['content']?.toString();
    if (content == null || content.isEmpty) {
      return utf8.decode(await getFileBytes(owner, repo, path), allowMalformed: true);
    }
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  Future<Uint8List> getFileBytes(String owner, String repo, String path) async {
    final Map<String, dynamic> meta = await _contentMeta(owner, repo, path);
    final int size = (meta['size'] as num?)?.toInt() ?? 0;
    if (size > 1000000 && meta['git_url'] != null) {
      final dynamic blob = _decode(await _send('GET', meta['git_url'].toString()));
      if (blob is Map) {
        final String? content = blob['content']?.toString();
        if (content != null) return Uint8List.fromList(base64Decode(content.replaceAll('\n', '')));
      }
    }
    final String? content = meta['content']?.toString();
    if (content == null) throw ApiException(415, 'File content is not available');
    return Uint8List.fromList(base64Decode(content.replaceAll('\n', '')));
  }

  Future<String?> fileSha(String owner, String repo, String path) async {
    try {
      final Map<String, dynamic> meta = await _contentMeta(owner, repo, path);
      return meta['sha']?.toString();
    } on ApiException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<void> putFile(
    String owner,
    String repo,
    String path,
    Uint8List bytes,
    String message, {
    String? sha,
    String branch = 'main',
  }) async {
    if (bytes.length <= 1000000) {
      final Map<String, dynamic> body = <String, dynamic>{
        'message': message,
        'content': base64Encode(bytes),
        if (sha != null) 'sha': sha,
        'branch': branch,
      };
      _decode(await _send('PUT', '${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}', jsonBody: body));
      return;
    }
    await uploadViaGitData(owner, repo, path, bytes, message, branch: branch);
  }

  Future<void> putText(
    String owner,
    String repo,
    String path,
    String text,
    String message, {
    String? sha,
    String branch = 'main',
  }) {
    return putFile(owner, repo, path, Uint8List.fromList(utf8.encode(text)), message, sha: sha, branch: branch);
  }

  Future<void> deleteFile(
    String owner,
    String repo,
    String path,
    String sha,
    String message, {
    String branch = 'main',
  }) async {
    _decode(await _send(
      'DELETE',
      '${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}',
      jsonBody: <String, dynamic>{'message': message, 'sha': sha, 'branch': branch},
    ));
  }

  /// Commit date for a single path, used by the Files browser "date" sort.
  /// Returns null when GitHub has no commit for that path.
  Future<DateTime?> lastCommitDate(String owner, String repo, String path, {String branch = 'main'}) async {
    try {
      final dynamic data = await _send(
        'GET',
        '${AppConfig.githubApi}/repos/$owner/$repo/commits?path=${Uri.encodeQueryComponent(path)}&sha=$branch&per_page=1',
      );
      final dynamic decoded = _decode(data);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final Map<String, dynamic> first = Map<String, dynamic>.from(decoded.first as Map);
        final dynamic commit = first['commit'];
        if (commit is Map) {
          final dynamic committer = commit['committer'];
          if (committer is Map) return DateTime.tryParse(committer['date']?.toString() ?? '');
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Large-file path: blob → tree → commit → ref update.
  Future<void> uploadViaGitData(
    String owner,
    String repo,
    String path,
    Uint8List bytes,
    String message, {
    String branch = 'main',
  }) async {
    final String base = '${AppConfig.githubApi}/repos/$owner/$repo';
    final dynamic blob = _decode(await _send(
      'POST',
      '$base/git/blobs',
      jsonBody: <String, dynamic>{'content': base64Encode(bytes), 'encoding': 'base64'},
    ));
    if (blob is! Map) throw ApiException(500, 'Blob upload failed');
    final dynamic ref = _decode(await _send('GET', '$base/git/ref/heads/$branch'));
    if (ref is! Map) throw ApiException(500, 'Could not read branch');
    final String commitSha = (ref['object'] as Map)['sha'].toString();
    final dynamic commit = _decode(await _send('GET', '$base/git/commits/$commitSha'));
    if (commit is! Map) throw ApiException(500, 'Could not read commit');
    final String treeSha = (commit['tree'] as Map)['sha'].toString();
    final dynamic tree = _decode(await _send(
      'POST',
      '$base/git/trees',
      jsonBody: <String, dynamic>{
        'base_tree': treeSha,
        'tree': <Map<String, dynamic>>[
          <String, dynamic>{
            'path': _cleanPath(path).substring(1),
            'mode': '100644',
            'type': 'blob',
            'sha': blob['sha'],
          }
        ],
      },
    ));
    if (tree is! Map) throw ApiException(500, 'Tree creation failed');
    final dynamic newCommit = _decode(await _send(
      'POST',
      '$base/git/commits',
      jsonBody: <String, dynamic>{
        'message': message,
        'tree': tree['sha'],
        'parents': <String>[commitSha],
      },
    ));
    if (newCommit is! Map) throw ApiException(500, 'Commit creation failed');
    _decode(await _send(
      'PATCH',
      '$base/git/refs/heads/$branch',
      jsonBody: <String, dynamic>{'sha': newCommit['sha']},
    ));
  }

  // ---------------------------------------------------------------- actions
  Future<void> dispatch(String owner, String repo, String workflow, {Map<String, String> inputs = const <String, String>{}}) async {
    _decode(await _send(
      'POST',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/workflows/$workflow/dispatches',
      jsonBody: <String, dynamic>{'ref': 'main', 'inputs': inputs},
    ));
  }

  Future<List<WorkflowRun>> listRuns(String owner, String repo, {String? workflow}) async {
    final String url = workflow == null
        ? '${AppConfig.githubApi}/repos/$owner/$repo/actions/runs?per_page=20'
        : '${AppConfig.githubApi}/repos/$owner/$repo/actions/workflows/$workflow/runs?per_page=20';
    final dynamic data = _decode(await _send('GET', url));
    final List<WorkflowRun> out = <WorkflowRun>[];
    if (data is Map && data['workflow_runs'] is List) {
      for (final dynamic raw in data['workflow_runs'] as List) {
        if (raw is Map) out.add(WorkflowRun.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<List<WorkflowJob>> listJobs(String owner, String repo, int runId) async {
    final dynamic data = _decode(await _send(
      'GET',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/runs/$runId/jobs?per_page=50',
    ));
    final List<WorkflowJob> out = <WorkflowJob>[];
    if (data is Map && data['jobs'] is List) {
      for (final dynamic raw in data['jobs'] as List) {
        if (raw is Map) out.add(WorkflowJob.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  /// Downloads and concatenates the run log archive. GitHub returns a 302 to a
  /// storage host; the redirect is followed without forwarding the token.
  Future<String> downloadRunLogs(String owner, String repo, int runId) async {
    final String url = '${AppConfig.githubApi}/repos/$owner/$repo/actions/runs/$runId/logs';
    http.Response response = await _send('GET', url, follow: false);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final String? location = response.headers['location'];
      if (location == null) throw ApiException(response.statusCode, 'Log redirect missing');
      final http.Response direct = await _client.get(
        Uri.parse(location),
        headers: <String, String>{'User-Agent': AppConfig.userAgent},
      ).timeout(const Duration(seconds: 60));
      response = direct;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Logs are not available yet (HTTP ${response.statusCode})');
    }
    final Uint8List bytes = Uint8List.fromList(response.bodyBytes);
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final List<ArchiveFile> files = archive.files.where((ArchiveFile f) => f.isFile).toList()
      ..sort((ArchiveFile a, ArchiveFile b) => a.name.compareTo(b.name));
    final StringBuffer buffer = StringBuffer();
    for (final ArchiveFile file in files) {
      buffer.writeln('===== ${file.name} =====');
      final List<int> content = file.content as List<int>;
      final String text = utf8.decode(content, allowMalformed: true);
      if (buffer.length + text.length > 900000) {
        buffer.writeln(text.substring(0, 900000 - buffer.length));
        break;
      }
      buffer.writeln(text);
    }
    return buffer.toString();
  }

  Future<void> cancelRun(String owner, String repo, int runId) async {
    _decode(await _send('POST', '${AppConfig.githubApi}/repos/$owner/$repo/actions/runs/$runId/cancel', jsonBody: <String, dynamic>{}));
  }

  Future<void> rerunRun(String owner, String repo, int runId) async {
    _decode(await _send('POST', '${AppConfig.githubApi}/repos/$owner/$repo/actions/runs/$runId/rerun', jsonBody: <String, dynamic>{}));
  }

  // --------------------------------------------------------------- releases
  Future<List<ReleaseInfo>> listReleases(String owner, String repo) async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo/releases?per_page=50'));
    final List<ReleaseInfo> out = <ReleaseInfo>[];
    if (data is List) {
      for (final dynamic raw in data) {
        if (raw is Map) out.add(ReleaseInfo.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  Future<void> deleteRelease(String owner, String repo, int releaseId) async {
    _decode(await _send('DELETE', '${AppConfig.githubApi}/repos/$owner/$repo/releases/$releaseId', jsonBody: <String, dynamic>{}));
  }

  Future<Uint8List> downloadAsset(String owner, String repo, int assetId) async {
    final String url = '${AppConfig.githubApi}/repos/$owner/$repo/releases/assets/$assetId';
    http.Response response = await _send(
      'GET',
      url,
      headers: _headers(json: false, acceptRaw: true),
      follow: false,
    );
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final String? location = response.headers['location'];
      if (location == null) throw ApiException(response.statusCode, 'Asset redirect missing');
      response = await _client.get(
        Uri.parse(location),
        headers: <String, String>{'User-Agent': AppConfig.userAgent},
      ).timeout(const Duration(seconds: 120));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Asset download failed');
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  // ---------------------------------------------------------------- secrets
  Future<List<String>> listSecretNames(String owner, String repo) async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets?per_page=100'));
    final List<String> out = <String>[];
    if (data is Map && data['secrets'] is List) {
      for (final dynamic raw in data['secrets'] as List) {
        if (raw is Map && raw['name'] != null) out.add(raw['name'].toString());
      }
    }
    return out;
  }

  /// Encrypts with the repository public key using libsodium's sealed box
  /// scheme (X25519 + XSalsa20-Poly1305), exactly what the Actions API expects.
  Future<void> putSecret(String owner, String repo, String name, String value) async {
    final dynamic keyData = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets/public-key'));
    if (keyData is! Map) throw ApiException(500, 'Missing public key');
    final String keyId = keyData['key_id'].toString();
    final Uint8List publicKey = Uint8List.fromList(base64Decode(keyData['key'].toString()));
    if (publicKey.length != 32) throw ApiException(500, 'Invalid repository public key');
    final Uint8List sealed = SealedBox(PublicKey(publicKey)).encrypt(Uint8List.fromList(utf8.encode(value)));
    _decode(await _send(
      'PUT',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets/$name',
      jsonBody: <String, dynamic>{
        'encrypted_value': base64Encode(sealed),
        'key_id': keyId,
      },
    ));
  }

  String _cleanPath(String path) {
    final String clean = path.trim();
    if (clean.isEmpty || clean == '/') return '';
    final String withoutLeading = clean.replaceFirst(RegExp(r'^/+'), '');
    return '/${withoutLeading.split('/').map(Uri.encodeComponent).join('/')}';
  }

  void dispose() {
    _client.close();
  }
}
