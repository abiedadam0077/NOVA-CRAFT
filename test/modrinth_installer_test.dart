import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_craft/core/cancellation.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/modrinth_api.dart';
import 'package:nova_craft/core/modrinth_installer.dart';
import 'package:nova_craft/core/provisioner.dart';

const ServerConfig _server = ServerConfig(
  id: 'server-123',
  name: 'Paper test server',
  repoOwner: 'owner',
  repoName: 'repo',
  defaultBranch: 'main',
  edition: 'JAVA',
  mcVersion: '1.21.11',
  software: 'PAPER',
  dataPath: 'server',
);

const ModrinthProject _project = ModrinthProject(
  id: 'geyser-project',
  slug: 'geyser',
  title: 'Geyser',
  description: 'A test plugin',
  iconUrl: '',
  downloads: 1000,
  author: 'GeyserMC',
  categories: <String>[],
  projectType: 'plugin',
);

final Uint8List _jar = Uint8List.fromList(<int>[
  0x50, 0x4b, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00,
  0x2a, 0x00, 0x00, 0x00,
]);

String _gitBlobSha(List<int> bytes) {
  final List<int> header = utf8.encode('blob ${bytes.length}\u0000');
  return crypto.sha1.convert(<int>[...header, ...bytes]).toString();
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );

class _Fixture {
  _Fixture({
    this.actualServer = _server,
    this.advertisedSize,
    this.advertisedSha512,
    this.ambiguousPutResponse = false,
    int transientPutFailures = 0,
  }) {
    transientPutFailuresRemaining = transientPutFailures;
    client = MockClient(_handle);
    modrinth = ModrinthApi(client: client, retryDelay: Duration.zero);
    github = GitHubApi(client: client);
    installer = ModrinthInstaller(
      modrinth: modrinth,
      github: github,
      logSink: (String event, Map<String, Object?> fields) => logs.add(event),
    );
  }

  final ServerConfig actualServer;
  final int? advertisedSize;
  final String? advertisedSha512;
  final bool ambiguousPutResponse;
  final List<String> logs = <String>[];
  late final MockClient client;
  late final ModrinthApi modrinth;
  late final GitHubApi github;
  late final ModrinthInstaller installer;
  int versionRequests = 0;
  int downloadRequests = 0;
  int putAttempts = 0;
  int transientPutFailuresRemaining = 0;
  Uint8List? uploadedBytes;
  String? uploadedPath;

  Future<http.Response> _handle(http.Request request) async {
    final Uri uri = request.url;
    if (uri.host == 'api.modrinth.com' && uri.path == '/v2/project/geyser-project/version') {
      versionRequests++;
      return _json(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'version-1',
          'version_number': '2.0.0',
          'name': 'Geyser 2.0.0',
          'game_versions': <String>['1.21.11'],
          'loaders': <String>['paper'],
          'date_published': '2026-10-18T12:00:00Z',
          'files': <Map<String, Object?>>[
            <String, Object?>{
              'url': 'https://cdn.modrinth.com/data/geyser/versions/version-1/Geyser.jar',
              'filename': 'Geyser.jar',
              'size': advertisedSize ?? _jar.length,
              'primary': true,
              'hashes': <String, String>{'sha512': advertisedSha512 ?? crypto.sha512.convert(_jar).toString()},
            },
          ],
        },
      ]);
    }
    if (uri.host == 'cdn.modrinth.com' && uri.path.endsWith('/Geyser.jar')) {
      downloadRequests++;
      return http.Response.bytes(_jar, 200, headers: <String, String>{'content-type': 'application/java-archive'});
    }

    if (uri.host == 'api.github.com' && uri.path == '/repos/owner/repo/contents/${Provisioner.configPath}' && request.method == 'GET') {
      final String configText = const JsonEncoder.withIndent('  ').convert(actualServer.toJson());
      final List<int> configBytes = utf8.encode(configText);
      return _json(<String, Object?>{
        'name': 'server.json',
        'path': Provisioner.configPath,
        'type': 'file',
        'size': configBytes.length,
        'sha': 'config-blob-sha',
        'content': base64Encode(configBytes),
        'encoding': 'base64',
      });
    }

    if (uri.host == 'api.github.com' && uri.path == '/repos/owner/repo/contents/server/plugins/Geyser.jar') {
      if (request.method == 'GET') return _json(<String, String>{'message': 'Not Found'}, status: 404);
      if (request.method == 'PUT') {
        putAttempts++;
        if (transientPutFailuresRemaining > 0) {
          transientPutFailuresRemaining--;
          throw http.ClientException('temporary upload network failure', uri);
        }
        final Map<String, dynamic> body = jsonDecode(request.body) as Map<String, dynamic>;
        uploadedBytes = Uint8List.fromList(base64Decode(body['content'] as String));
        uploadedPath = uri.path.substring('/repos/owner/repo/contents/'.length);
        if (ambiguousPutResponse) {
          // Simulate GitHub saving the blob while the client loses the response.
          throw http.ClientException('simulated transport response loss', uri);
        }
        return _json(<String, Object?>{
          'content': <String, Object?>{
            'path': uploadedPath,
            'size': uploadedBytes!.length,
            'sha': _gitBlobSha(uploadedBytes!),
          },
          'commit': <String, String>{'sha': 'commit-sha'},
        }, status: 201);
      }
    }

    if (uri.host == 'api.github.com' && uri.path == '/repos/owner/repo/contents/server/plugins' && request.method == 'GET') {
      final Uint8List? bytes = uploadedBytes;
      if (bytes == null) return _json(<Object?>[]);
      return _json(<Map<String, Object?>>[
        <String, Object?>{
          'name': 'Geyser.jar',
          'path': 'server/plugins/Geyser.jar',
          'type': 'file',
          'size': bytes.length,
          'sha': _gitBlobSha(bytes),
          'download_url': 'https://raw.githubusercontent.com/owner/repo/main/server/plugins/Geyser.jar',
        },
      ]);
    }
    throw StateError('Unexpected mock request: ${request.method} $uri');
  }

  void dispose() {
    // Both API wrappers intentionally share this single routed mock client.
    client.close();
  }
}

void main() {
  test('cancelling a Modrinth request aborts the HTTP request and surfaces cancellation', () async {
    final MockClient client = MockClient.streaming((http.BaseRequest request, Stream<List<int>> _) async {
      final Future<void>? abortTrigger = (request as http.Abortable).abortTrigger;
      if (abortTrigger != null) await abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    final ModrinthApi api = ModrinthApi(client: client, retryDelay: Duration.zero);
    addTearDown(api.dispose);
    final CancellationToken cancellation = CancellationToken();
    final Future<List<ModrinthVersion>> pending = api.versions('project', cancellation: cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();

    await expectLater(pending, throwsA(isA<OperationCancelledException>()));
  });

  test('Modrinth file download streams byte progress before integrity verification completes', () async {
    final MockClient client = MockClient.streaming((http.BaseRequest request, Stream<List<int>> _) async {
      expect(request.url.host, 'cdn.modrinth.com');
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          _jar.sublist(0, 4),
          _jar.sublist(4),
        ]),
        200,
        contentLength: _jar.length,
        request: request,
      );
    });
    final ModrinthApi api = ModrinthApi(client: client);
    addTearDown(api.dispose);
    final List<int> received = <int>[];
    final List<bool> complete = <bool>[];
    final ModrinthVersionFile file = ModrinthVersionFile(
      url: 'https://cdn.modrinth.com/data/test/version-1/Test.jar',
      filename: 'Test.jar',
      size: _jar.length,
      primary: true,
      hashes: <String, String>{'sha512': crypto.sha512.convert(_jar).toString()},
    );

    final Uint8List downloaded = await api.download(
      file,
      onProgress: (int receivedBytes, int totalBytes, bool isComplete) {
        received.add(receivedBytes);
        complete.add(isComplete);
        expect(totalBytes, _jar.length);
      },
    );

    expect(downloaded, orderedEquals(_jar));
    expect(received, <int>[0, 4, _jar.length, _jar.length]);
    expect(complete.last, isTrue);
  });

  test('oversized Modrinth artifacts are rejected before a network request', () async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount++;
      return http.Response.bytes(_jar, 200);
    });
    final ModrinthApi api = ModrinthApi(client: client);
    addTearDown(api.dispose);
    final ModrinthVersionFile file = ModrinthVersionFile(
      url: 'https://cdn.modrinth.com/data/test/version-1/Large.jar',
      filename: 'Large.jar',
      size: ModrinthApi.maxDownloadBytes + 1,
    );

    await expectLater(api.download(file), throwsA(isA<ModrinthDownloadLimitException>()));
    expect(requestCount, 0);
  });

  test('cancelling a streamed Modrinth download aborts its response body', () async {
    final Completer<void> requestStarted = Completer<void>();
    late StreamController<List<int>> responseBody;
    final MockClient client = MockClient.streaming((http.BaseRequest request, Stream<List<int>> _) async {
      requestStarted.complete();
      responseBody = StreamController<List<int>>();
      final Future<void>? abortTrigger = (request as http.Abortable).abortTrigger;
      if (abortTrigger != null) {
        unawaited(abortTrigger.then<void>((_) {
          if (responseBody.isClosed) return;
          responseBody.addError(http.RequestAbortedException(request.url));
          unawaited(responseBody.close());
        }));
      }
      return http.StreamedResponse(responseBody.stream, 200, contentLength: _jar.length + 1, request: request);
    });
    final ModrinthApi api = ModrinthApi(client: client, retryDelay: Duration.zero);
    addTearDown(api.dispose);
    final CancellationToken cancellation = CancellationToken();
    final ModrinthVersionFile file = ModrinthVersionFile(
      url: 'https://cdn.modrinth.com/data/test/version-1/Test.jar',
      filename: 'Test.jar',
      size: _jar.length + 1,
    );

    final Future<Uint8List> pending = api.download(file, cancellation: cancellation);
    await requestStarted.future;
    cancellation.cancel();
    await expectLater(pending, throwsA(isA<OperationCancelledException>()));
  });

  group('Modrinth plugin installation flow', () {
    test('selects a compatible release, downloads it and verifies the plugins repository path', () async {
      final _Fixture fixture = _Fixture();
      addTearDown(fixture.dispose);
      final CancellationToken cancellation = CancellationToken();
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: cancellation,
      );
      final ModrinthVersion selected = versions.singleWhere(
        (ModrinthVersion version) => modrinthCompatibleWithServer(_project, version, _server),
      );

      final List<int> receivedBytes = <int>[];
      final List<bool> completedStates = <bool>[];
      final ModrinthInstallReceipt receipt = await fixture.installer.install(
        project: _project,
        version: selected,
        expectedServer: _server,
        branch: 'main',
        cancellation: cancellation,
        onDownloadProgress: (int received, int total, bool complete) {
          receivedBytes.add(received);
          completedStates.add(complete);
          expect(total, _jar.length);
        },
      );

      expect(fixture.versionRequests, 1);
      expect(fixture.downloadRequests, 1);
      expect(fixture.putAttempts, 1);
      expect(fixture.uploadedPath, 'server/plugins/Geyser.jar');
      expect(fixture.uploadedBytes, orderedEquals(_jar));
      expect(receipt.path, 'server/plugins/Geyser.jar');
      expect(receipt.fileName, 'Geyser.jar');
      expect(receipt.size, _jar.length);
      expect(receipt.gitBlobSha, _gitBlobSha(_jar));
      expect(fixture.logs, contains('github.repository.verify.success'));
      expect(fixture.logs, contains('plugin.install.success'));
    });

    test('does not upload when the Modrinth checksum is invalid', () async {
      final _Fixture fixture = _Fixture(advertisedSha512: List<String>.filled(128, '0').join());
      addTearDown(fixture.dispose);
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: CancellationToken(),
      );

      await expectLater(
        fixture.installer.install(
          project: _project,
          version: versions.single,
          expectedServer: _server,
          branch: 'main',
          cancellation: CancellationToken(),
        ),
        throwsA(isA<ModrinthInstallException>().having(
          (ModrinthInstallException error) => error.stage,
          'stage',
          ModrinthInstallStage.download,
        )),
      );

      expect(fixture.downloadRequests, 1, reason: 'checksum failures are invalid data, not retryable network failures');
      expect(fixture.putAttempts, 0);
      expect(fixture.logs, isNot(contains('plugin.install.success')));
    });

    test('retries a truncated Modrinth response but never uploads it', () async {
      final _Fixture fixture = _Fixture(advertisedSize: _jar.length + 1);
      addTearDown(fixture.dispose);
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: CancellationToken(),
      );

      await expectLater(
        fixture.installer.install(
          project: _project,
          version: versions.single,
          expectedServer: _server,
          branch: 'main',
          cancellation: CancellationToken(),
        ),
        throwsA(isA<ModrinthInstallException>().having(
          (ModrinthInstallException error) => error.stage,
          'stage',
          ModrinthInstallStage.download,
        )),
      );

      expect(fixture.downloadRequests, 3, reason: 'truncation is retried with a bounded attempt count');
      expect(fixture.putAttempts, 0);
      expect(fixture.logs, isNot(contains('plugin.install.success')));
    });

    test('rechecks repository server.json and rejects an incompatible server before download', () async {
      final ServerConfig vanilla = _server.copyWith(software: 'VANILLA');
      final _Fixture fixture = _Fixture(actualServer: vanilla);
      addTearDown(fixture.dispose);
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: CancellationToken(),
      );

      await expectLater(
        fixture.installer.install(
          project: _project,
          version: versions.single,
          expectedServer: _server,
          branch: 'main',
          cancellation: CancellationToken(),
        ),
        throwsA(isA<ModrinthInstallException>().having(
          (ModrinthInstallException error) => error.stage,
          'stage',
          ModrinthInstallStage.compatibility,
        )),
      );

      expect(fixture.downloadRequests, 0);
      expect(fixture.putAttempts, 0);
    });

    test('retries one transient upload failure only after reconciling repository state', () async {
      final _Fixture fixture = _Fixture(transientPutFailures: 1);
      addTearDown(fixture.dispose);
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: CancellationToken(),
      );

      final ModrinthInstallReceipt receipt = await fixture.installer.install(
        project: _project,
        version: versions.single,
        expectedServer: _server,
        branch: 'main',
        cancellation: CancellationToken(),
      );

      expect(receipt.path, 'server/plugins/Geyser.jar');
      expect(fixture.putAttempts, 2);
      expect(fixture.uploadedBytes, orderedEquals(_jar));
      expect(fixture.logs, contains('github.upload.request.failure'));
      expect(fixture.logs, contains('plugin.install.success'));
    });

    test('does not repeat an upload when GitHub saved it but its response was lost', () async {
      final _Fixture fixture = _Fixture(ambiguousPutResponse: true);
      addTearDown(fixture.dispose);
      final List<ModrinthVersion> versions = await fixture.installer.requestVersions(
        _project,
        server: _server,
        cancellation: CancellationToken(),
      );

      final ModrinthInstallReceipt receipt = await fixture.installer.install(
        project: _project,
        version: versions.single,
        expectedServer: _server,
        branch: 'main',
        cancellation: CancellationToken(),
      );

      expect(receipt.path, 'server/plugins/Geyser.jar');
      expect(fixture.putAttempts, 1, reason: 'the exact remote Git blob is verified before considering a retry');
      expect(fixture.logs, contains('github.upload.recovered'));
      expect(fixture.logs, contains('plugin.install.success'));
    });
  });
}
