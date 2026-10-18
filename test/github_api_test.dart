import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_craft/core/github_api.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/provisioner.dart';
import 'package:pinenacl/x25519.dart';

/// These tests exercise the real request/response contract against a fake
/// transport. They cover the failures that used to look like "GitHub auth is
/// broken": writes to the wrong branch, dispatch against a hard-coded `main`,
/// unverified secret writes and unhelpful 403 messages.
void main() {
  group('Repository branch handling', () {
    test('putFile writes to the repository default branch, not hard-coded main', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        if (request.method == 'GET' && request.url.path == '/repos/owner/repo') {
          return http.Response(jsonEncode(<String, dynamic>{'default_branch': 'develop'}), 200);
        }
        if (request.method == 'PUT' && request.url.path.contains('/contents/')) {
          return http.Response('{}', 201);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final GitHubApi api = GitHubApi(client: client);
      await api.putFile('owner', 'repo', 'nova-craft/a.txt', Uint8List.fromList(<int>[1, 2, 3]), 'nova: test');
      final http.Request put = seen.last;
      expect(put.method, 'PUT');
      expect(jsonDecode(put.body)['branch'], 'develop');
    });

    test('reads target the default branch', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        if (request.url.path == '/repos/owner/repo') {
          return http.Response(jsonEncode(<String, dynamic>{'default_branch': 'trunk'}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'content': base64Encode(utf8.encode('hello')),
          'sha': 'sha1',
          'size': 5,
        }), 200);
      });
      final GitHubApi api = GitHubApi(client: client);
      expect(await api.getFileText('owner', 'repo', 'a.txt'), 'hello');
      expect(seen.last.url.queryParameters['ref'], 'trunk');
    });

    test('the default branch is cached for the session', () async {
      int repoLookups = 0;
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path == '/repos/owner/repo') {
          repoLookups++;
          return http.Response(jsonEncode(<String, dynamic>{'default_branch': 'main'}), 200);
        }
        return http.Response('{}', 200);
      });
      final GitHubApi api = GitHubApi(client: client);
      await api.defaultBranchOf('owner', 'repo');
      await api.defaultBranchOf('owner', 'repo');
      expect(repoLookups, 1);
    });

    test('dispatch uses the real default branch', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        if (request.url.path == '/repos/owner/repo') {
          return http.Response(jsonEncode(<String, dynamic>{'default_branch': 'master'}), 200);
        }
        return http.Response('{}', 204);
      });
      final GitHubApi api = GitHubApi(client: client);
      await api.dispatch('owner', 'repo', 'novacraft-server.yml', inputs: <String, String>{'action': 'start'});
      final http.Request post = seen.last;
      expect(post.method, 'POST');
      expect(jsonDecode(post.body)['ref'], 'master');
    });

    test('repository listing follows every API page', () async {
      final List<http.Request> seen = <http.Request>[];
      Map<String, dynamic> repo(int id) => <String, dynamic>{
            'id': id,
            'name': 'repo-$id',
            'owner': <String, String>{'login': 'owner'},
            'private': true,
            'default_branch': 'main',
            'permissions': <String, bool>{'push': true},
          };
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        final List<Map<String, dynamic>> page = request.url.queryParameters['page'] == '1'
            ? List<Map<String, dynamic>>.generate(100, (int index) => repo(index))
            : <Map<String, dynamic>>[repo(100)];
        return http.Response(jsonEncode(page), 200);
      });
      final GitHubApi api = GitHubApi(client: client);
      final List<GhRepo> repos = await api.listUserRepos();
      expect(repos, hasLength(101));
      expect(seen.map((http.Request r) => r.url.queryParameters['page']), <String?>['1', '2']);
      expect(seen.every((http.Request r) => r.url.queryParameters['per_page'] == '100'), isTrue);
    });
  });

  group('Repository secrets', () {
    late PrivateKey keyPair;
    setUp(() => keyPair = PrivateKey.generate());

    http.Client secretClient({
      required List<http.Request> seen,
      required bool listAfterWrite,
    }) {
      return MockClient((http.Request request) async {
        seen.add(request);
        if (request.url.path == '/repos/owner/repo/actions/secrets/public-key') {
          return http.Response(jsonEncode(<String, dynamic>{
            'key_id': 'key-1',
            'key': base64Encode(keyPair.publicKey.asTypedList),
          }), 200);
        }
        if (request.method == 'PUT' && request.url.path == '/repos/owner/repo/actions/secrets/PLAYIT_SECRET_KEY') {
          return http.Response('{}', 201);
        }
        if (request.url.path == '/repos/owner/repo/actions/secrets') {
          return http.Response(jsonEncode(<String, dynamic>{
            'secrets': <Map<String, String>>[
              if (listAfterWrite) <String, String>{'name': 'PLAYIT_SECRET_KEY'},
            ],
          }), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
    }

    test('a secret is sealed, written and verified', () async {
      final List<http.Request> seen = <http.Request>[];
      final GitHubApi api = GitHubApi(client: secretClient(seen: seen, listAfterWrite: true));
      final SecretWriteResult result = await api.putSecret('owner', 'repo', 'PLAYIT_SECRET_KEY', 'agent-secret-value');
      expect(result.verified, isTrue);
      final http.Request put = seen.firstWhere((http.Request r) => r.method == 'PUT');
      final Map<String, dynamic> body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['key_id'], 'key-1');
      final Uint8List sealed = base64Decode(body['encrypted_value'] as String);
      // libsodium sealed box: 32-byte ephemeral public key, 16-byte MAC, then
      // the plaintext — GitHub decrypts it with its private key.
      expect(sealed.length, 32 + 16 + 'agent-secret-value'.length);
    });

    test('an unverified write is reported as a failure, never as saved', () async {
      final List<http.Request> seen = <http.Request>[];
      final GitHubApi api = GitHubApi(client: secretClient(seen: seen, listAfterWrite: false));
      await expectLater(
        api.putSecret('owner', 'repo', 'PLAYIT_SECRET_KEY', 'agent-secret-value'),
        throwsA(isA<ApiException>()),
      );
    });

    test('empty secrets are rejected before any request', () async {
      final List<http.Request> seen = <http.Request>[];
      final GitHubApi api = GitHubApi(client: secretClient(seen: seen, listAfterWrite: true));
      await expectLater(
        api.putSecret('owner', 'repo', 'PLAYIT_SECRET_KEY', '   '),
        throwsA(isA<ApiException>()),
      );
      expect(seen, isEmpty);
    });
  });

  group('Backup restore safety', () {
    test('a release from another server is rejected before dispatch', () {
      final List<http.Request> seen = <http.Request>[];
      final GitHubApi api = GitHubApi(
        client: MockClient((http.Request request) async {
          seen.add(request);
          return http.Response('{}', 204);
        }),
      );
      const ServerConfig config = ServerConfig(
        id: 'server-a',
        name: 'Server A',
        repoOwner: 'owner',
        repoName: 'repo',
      );
      expect(
        () => Provisioner.restoreBackup(api, config, 'backup-server-b-20261018T120000000000Z'),
        throwsA(isA<ApiException>()),
      );
      expect(seen, isEmpty);
    });
  });

  group('Actionable errors', () {
    test('a permission 403 explains the app installation requirement', () async {
      final http.Client client = MockClient((http.Request request) async {
        return http.Response('{"message":"Resource not accessible by integration"}', 403);
      });
      final GitHubApi api = GitHubApi(client: client);
      try {
        await api.getRepo('owner', 'repo');
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.status, 403);
        expect(error.message.toLowerCase(), contains('install'));
      }
    });

    test('a repository 404 explains the missing access', () async {
      final http.Client client = MockClient((http.Request request) async {
        return http.Response('{"message":"Not Found"}', 404);
      });
      final GitHubApi api = GitHubApi(client: client);
      try {
        await api.defaultBranchOf('owner', 'repo');
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.message, contains('not installed'));
      }
    });
  });
}
