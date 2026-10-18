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

  /// Repository default branch cache. Every write and read has to target the
  /// branch that actually exists; assuming `main` breaks older accounts (and
  /// any repository whose default branch is `master` or custom).
  final Map<String, String> _defaultBranches = <String, String>{};

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
    final String lower = message.toLowerCase();
    if (response.statusCode == 403 &&
        (lower.contains('resource not accessible') || lower.contains('integration') || lower.contains('must have'))) {
      message = 'GitHub refused the request: the NOVA CRAFT app needs to be installed on this repository '
          'with Contents, Actions, Workflows and Secrets access. Open the install page, grant access to the repository, '
          'then try again. ($message)';
    } else if (response.statusCode == 404 && lower == 'not found') {
      message = 'GitHub returned “Not found”. The repository, branch or file does not exist, '
          'or the app has no access to it.';
    }
    throw ApiException(response.statusCode, message);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) _throwFor(response);
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// Fetches every page of a REST collection. GitHub's default is 30 and
  /// silently returning only the first page hid repositories/releases for
  /// larger accounts.
  Future<List<dynamic>> _getAllPages(String url, {String? arrayKey}) async {
    final Uri base = Uri.parse(url);
    final List<dynamic> all = <dynamic>[];
    for (int page = 1; page <= 100; page++) {
      final Map<String, String> query = <String, String>{
        ...base.queryParameters,
        'per_page': '100',
        'page': '$page',
      };
      final dynamic data = _decode(await _send('GET', base.replace(queryParameters: query).toString()));
      final List<dynamic>? values = data is List
          ? data
          : data is Map && data[arrayKey] is List
              ? data[arrayKey] as List<dynamic>
              : null;
      if (values == null) break;
      all.addAll(values);
      if (values.length < 100) break;
    }
    return all;
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
    final List<dynamic> data = await _getAllPages('${AppConfig.githubApi}/user/installations', arrayKey: 'installations');
    final List<GhInstallation> out = <GhInstallation>[];
    for (final dynamic raw in data) {
      if (raw is Map) {
        final Map<String, dynamic> account = raw['account'] is Map ? Map<String, dynamic>.from(raw['account'] as Map) : <String, dynamic>{};
        out.add(GhInstallation(
          (raw['id'] as num?)?.toInt() ?? 0,
          account['login']?.toString() ?? '',
          account['type']?.toString() ?? '',
        ));
      }
    }
    return out;
  }

  Future<List<GhRepo>> listInstallationRepos(int installationId) async {
    final List<dynamic> data = await _getAllPages(
      '${AppConfig.githubApi}/user/installations/$installationId/repositories',
      arrayKey: 'repositories',
    );
    return data.whereType<Map>().map((Map raw) => GhRepo.fromJson(Map<String, dynamic>.from(raw))).toList();
  }

  Future<List<GhRepo>> listUserRepos() async {
    final List<dynamic> data = await _getAllPages(
      '${AppConfig.githubApi}/user/repos?sort=updated&affiliation=owner,collaborator',
    );
    return data.whereType<Map>().map((Map raw) => GhRepo.fromJson(Map<String, dynamic>.from(raw))).toList();
  }

  Future<GhRepo> createRepo(String name, bool isPrivate, String description) async {
    dynamic data = _decode(await _send(
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
    final GhRepo created = GhRepo.fromJson(Map<String, dynamic>.from(data));
    // A brand new repository can 404 for a moment (repository creation is
    // asynchronous). Wait until it is readable before provisioning files.
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        await defaultBranchOf(created.owner, created.name);
        break;
      } on ApiException {
        await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }
    rememberBranch(created.owner, created.name, created.defaultBranch);
    return created;
  }

  Future<GhRepo> getRepo(String owner, String repo) async {
    final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo'));
    if (data is! Map) throw ApiException(500, 'Unexpected repository response');
    return GhRepo.fromJson(Map<String, dynamic>.from(data));
  }

  // --------------------------------------------------------------- contents
  Future<List<DirEntry>> listDir(String owner, String repo, String path, {String? branch}) async {
    final String clean = _cleanPath(path);
    final String ref = branch ?? await defaultBranchOf(owner, repo);
    final Uri uri = Uri.parse('${AppConfig.githubApi}/repos/$owner/$repo/contents$clean').replace(
      queryParameters: <String, String>{'ref': ref},
    );
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

  Future<Map<String, dynamic>> _contentMeta(String owner, String repo, String path, {String? branch}) async {
    final String ref = branch ?? await defaultBranchOf(owner, repo);
    final Uri uri = Uri.parse('${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}').replace(
      queryParameters: <String, String>{'ref': ref},
    );
    final dynamic data = _decode(await _send('GET', uri.toString()));
    if (data is! Map) throw ApiException(400, 'Not a file');
    return Map<String, dynamic>.from(data);
  }

  Future<String> getFileText(String owner, String repo, String path, {String? branch}) async {
    final Map<String, dynamic> meta = await _contentMeta(owner, repo, path, branch: branch);
    final String? content = meta['content']?.toString();
    if (content == null || content.isEmpty) {
      return utf8.decode(await getFileBytes(owner, repo, path, branch: branch), allowMalformed: true);
    }
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  Future<Uint8List> getFileBytes(String owner, String repo, String path, {String? branch}) async {
    final Map<String, dynamic> meta = await _contentMeta(owner, repo, path, branch: branch);
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

  Future<String?> fileSha(String owner, String repo, String path, {String? branch}) async {
    try {
      final Map<String, dynamic> meta = await _contentMeta(owner, repo, path, branch: branch);
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
    String? branch,
  }) async {
    final String target = branch ?? await defaultBranchOf(owner, repo);
    if (bytes.length <= 1000000) {
      final Map<String, dynamic> body = <String, dynamic>{
        'message': message,
        'content': base64Encode(bytes),
        if (sha != null) 'sha': sha,
        'branch': target,
      };
      _decode(await _send('PUT', '${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}', jsonBody: body));
      return;
    }
    await uploadViaGitData(owner, repo, path, bytes, message, branch: target);
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
    String? branch,
  }) async {
    final String target = branch ?? await defaultBranchOf(owner, repo);
    _decode(await _send(
      'DELETE',
      '${AppConfig.githubApi}/repos/$owner/$repo/contents${_cleanPath(path)}',
      jsonBody: <String, dynamic>{'message': message, 'sha': sha, 'branch': target},
    ));
  }

  /// Commit date for a single path, used by the Files browser "date" sort.
  /// Returns null when GitHub has no commit for that path.
  Future<DateTime?> lastCommitDate(String owner, String repo, String path, {String? branch}) async {
    try {
      final String ref = branch ?? await defaultBranchOf(owner, repo);
      final dynamic data = await _send(
        'GET',
        '${AppConfig.githubApi}/repos/$owner/$repo/commits?path=${Uri.encodeQueryComponent(path)}&sha=$ref&per_page=1',
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
    String? branch,
  }) async {
    final String base = '${AppConfig.githubApi}/repos/$owner/$repo';
    final String target = branch ?? await defaultBranchOf(owner, repo);
    final dynamic blob = _decode(await _send(
      'POST',
      '$base/git/blobs',
      jsonBody: <String, dynamic>{'content': base64Encode(bytes), 'encoding': 'base64'},
    ));
    if (blob is! Map) throw ApiException(500, 'Blob upload failed');
    final dynamic ref = _decode(await _send('GET', '$base/git/ref/heads/$target'));
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
      '$base/git/refs/heads/$target',
      jsonBody: <String, dynamic>{'sha': newCommit['sha']},
    ));
  }

  // ---------------------------------------------------------------- actions
  Future<void> dispatch(String owner, String repo, String workflow, {Map<String, String> inputs = const <String, String>{}}) async {
    final String ref = await defaultBranchOf(owner, repo);
    _decode(await _send(
      'POST',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/workflows/$workflow/dispatches',
      jsonBody: <String, dynamic>{'ref': ref, 'inputs': inputs},
    ));
  }

  /// The repository's real default branch, cached for the session.
  Future<String> defaultBranchOf(String owner, String repo) async {
    final String key = '$owner/$repo';
    final String? cached = _defaultBranches[key];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final dynamic data = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo'));
      if (data is Map) {
        final String branch = data['default_branch']?.toString() ?? '';
        if (branch.isNotEmpty) {
          _defaultBranches[key] = branch;
          return branch;
        }
      }
    } on ApiException catch (error) {
      if (error.status == 404) {
        throw ApiException(404, 'Repository $key was not found, or the GitHub App is not installed on it.');
      }
      rethrow;
    }
    return 'main';
  }

  void rememberBranch(String owner, String repo, String branch) {
    if (branch.trim().isNotEmpty) _defaultBranches['$owner/$repo'] = branch.trim();
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
    final List<dynamic> data = await _getAllPages('${AppConfig.githubApi}/repos/$owner/$repo/releases');
    return data.whereType<Map>().map((Map raw) => ReleaseInfo.fromJson(Map<String, dynamic>.from(raw))).toList();
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

  Future<void> deleteSecret(String owner, String repo, String name) async {
    final http.Response response = await _send(
      'DELETE',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets/${Uri.encodeComponent(name)}',
    );
    if (response.statusCode == 404) return;
    _decode(response);
  }

  /// Encrypts with the repository public key using libsodium's sealed box
  /// scheme (X25519 + XSalsa20-Poly1305), exactly what the Actions API expects.
  ///
  /// The write is verified: the secret list is re-read and the name must be
  /// present before this returns. GitHub only returns 201/204 for a successful
  /// write, so an unverifiable write is reported as a failure instead of a
  /// silent "saved".
  Future<SecretWriteResult> putSecret(String owner, String repo, String name, String value) async {
    if (value.trim().isEmpty) {
      throw ApiException(400, 'The secret value is empty');
    }
    dynamic keyData;
    try {
      keyData = _decode(await _send('GET', '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets/public-key'));
    } on ApiException catch (error) {
      if (error.status == 403) {
        throw ApiException(403, 'The GitHub App needs the “Secrets: write” permission for this repository.');
      }
      rethrow;
    }
    if (keyData is! Map) throw ApiException(500, 'Missing public key');
    final String? keyId = keyData['key_id']?.toString();
    final String? encodedKey = keyData['key']?.toString();
    if (keyId == null || encodedKey == null) throw ApiException(500, 'Malformed public key response');
    final Uint8List publicKey;
    try {
      publicKey = Uint8List.fromList(base64Decode(encodedKey));
    } catch (_) {
      throw ApiException(500, 'The repository public key is not valid base64');
    }
    if (publicKey.length != 32) throw ApiException(500, 'Invalid repository public key');
    final Uint8List sealed = SealedBox(PublicKey(publicKey)).encrypt(Uint8List.fromList(utf8.encode(value)));
    final http.Response response = await _send(
      'PUT',
      '${AppConfig.githubApi}/repos/$owner/$repo/actions/secrets/$name',
      jsonBody: <String, dynamic>{
        'encrypted_value': base64Encode(sealed),
        'key_id': keyId,
      },
    );
    if (response.statusCode != 201 && response.statusCode != 204) {
      _throwFor(response);
    }
    final List<String> names = await listSecretNames(owner, repo);
    if (!names.contains(name)) {
      throw ApiException(500, 'GitHub accepted the request but the secret is not listed; check the App permissions.');
    }
    return SecretWriteResult(name: name, keyId: keyId, verified: true);
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
