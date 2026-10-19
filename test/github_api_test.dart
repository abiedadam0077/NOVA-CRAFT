import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_craft/core/github_api.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/provisioner.dart';
import 'package:nova_craft/core/workflow_templates.dart';
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

  group('Large Git Data uploads', () {
    test('mod and plugin JAR writes survive a Runner branch update and keep raw paths', () async {
      final Uint8List bytes = Uint8List.fromList(List<int>.generate(1000001, (int i) => i & 0xff));

      Future<void> uploadWithConcurrentRunnerCommit(String path) async {
        String headSha = 'initial-commit';
        int treeRequests = 0;
        int commitRequests = 0;
        int refUpdates = 0;
        int blobRequests = 0;
        final List<Map<String, dynamic>> treeBodies = <Map<String, dynamic>>[];
        final List<Map<String, dynamic>> commitBodies = <Map<String, dynamic>>[];
        final http.Client client = MockClient((http.Request request) async {
          final Uri uri = request.url;
          if (request.method == 'POST' && uri.path == '/repos/owner/repo/git/blobs') {
            blobRequests++;
            final Map<String, dynamic> body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['encoding'], 'base64');
            expect(base64Decode(body['content'] as String), orderedEquals(bytes));
            return http.Response('{"sha":"jar-blob-sha"}', 201);
          }
          if (request.method == 'GET' && uri.path == '/repos/owner/repo/git/ref/heads/main') {
            return http.Response(jsonEncode(<String, Object?>{
              'object': <String, String>{'sha': headSha},
            }), 200);
          }
          if (request.method == 'GET' && uri.path == '/repos/owner/repo/git/commits/$headSha') {
            final String treeSha = headSha == 'runner-commit' ? 'runner-tree' : 'tree-$headSha';
            return http.Response(jsonEncode(<String, Object?>{
              'tree': <String, String>{'sha': treeSha},
            }), 200);
          }
          if (request.method == 'POST' && uri.path == '/repos/owner/repo/git/trees') {
            treeRequests++;
            treeBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('{"sha":"upload-tree-$treeRequests"}', 201);
          }
          if (request.method == 'POST' && uri.path == '/repos/owner/repo/git/commits') {
            commitRequests++;
            commitBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('{"sha":"upload-commit-$commitRequests"}', 201);
          }
          if (request.method == 'PATCH' && uri.path == '/repos/owner/repo/git/refs/heads/main') {
            refUpdates++;
            if (refUpdates == 1) {
              // Simulate the server Runner committing status.json after our
              // upload read the old head but before the ref update.
              headSha = 'runner-commit';
              return http.Response('{"message":"Update is not a fast forward"}', 422);
            }
            headSha = 'upload-commit-$commitRequests';
            return http.Response('{"ref":"refs/heads/main"}', 200);
          }
          throw StateError('Unexpected mock request: ${request.method} $uri');
        });
        final GitHubApi api = GitHubApi(client: client);
        addTearDown(api.dispose);

        await api.putFile('owner', 'repo', path, bytes, 'nova: install test JAR', branch: 'main');

        expect(blobRequests, 1, reason: 'the immutable JAR blob should not be retransmitted on a branch race');
        expect(refUpdates, 2);
        expect(treeRequests, 2);
        expect(treeBodies.first['tree'][0]['path'], path, reason: 'Git tree paths must not be URL-encoded');
        expect(treeBodies[1]['base_tree'], 'runner-tree', reason: 'retry must include the Runner commit');
        expect(commitBodies.first['parents'], <String>['initial-commit']);
        expect(commitBodies[1]['parents'], <String>['runner-commit']);
      }

      await uploadWithConcurrentRunnerCommit('server/mods/Example Mod.jar');
      await uploadWithConcurrentRunnerCommit('server/plugins/Example Plugin.jar');
    });
  });

  group('Workflow run diagnostics', () {
    test('listRuns checks only the requested NOVA workflow and parses its status', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        return http.Response(jsonEncode(<String, dynamic>{
          'workflow_runs': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 42,
              'name': 'NOVA CRAFT Server',
              'status': 'in_progress',
              'conclusion': null,
              'created_at': '2026-10-18T12:00:00Z',
              'updated_at': '2026-10-18T12:01:00Z',
              'html_url': 'https://github.com/owner/repo/actions/runs/42',
              'event': 'workflow_dispatch',
              'run_started_at': '2026-10-18T12:00:01Z',
              'head_sha': 'abc123',
            },
          ],
        }), 200);
      });
      final GitHubApi api = GitHubApi(client: client);
      final List<WorkflowRun> runs = await api.listRuns('owner', 'repo', workflow: Provisioner.workflowFile);
      expect(runs, hasLength(1));
      expect(runs.single.id, 42);
      expect(runs.single.isActive, isTrue);
      expect(seen.single.url.path, contains('/actions/workflows/novacraft-server.yml/runs'));
    });

    test('a non-map workflow run is rejected as malformed data', () async {
      final GitHubApi api = GitHubApi(
        client: MockClient((http.Request request) async => http.Response('{"workflow_runs":[null]}', 200)),
      );
      await expectLater(api.listRuns('owner', 'repo', workflow: Provisioner.workflowFile), throwsA(isA<ApiException>()));
    });

    test('GitHub requests use the injected timeout instead of waiting for the 40-second default', () async {
      final GitHubApi api = GitHubApi(
        client: MockClient((http.Request request) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        api.getFileText('owner', 'repo', 'nova-craft/files/manifest.json'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a malformed run-list response is an API error, not an empty workflow history', () async {
      final GitHubApi api = GitHubApi(
        client: MockClient((http.Request request) async => http.Response('{"message":"unexpected"}', 200)),
      );
      await expectLater(api.listRuns('owner', 'repo', workflow: Provisioner.workflowFile), throwsA(isA<ApiException>()));
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

  group('Existing server runner upgrades', () {
    test('updates only generated workflow helpers, not world data, properties, config or secrets', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        if (request.method == 'GET' && request.url.path.contains('/contents/')) {
          return http.Response('{"message":"Not Found"}', 404);
        }
        if (request.method == 'PUT' && request.url.path.contains('/contents/')) return http.Response('{}', 201);
        return http.Response('{"message":"Not Found"}', 404);
      });
      final GitHubApi api = GitHubApi(client: client);
      const ServerConfig config = ServerConfig(
        id: 'server-a',
        name: 'Server A',
        repoOwner: 'owner',
        repoName: 'repo',
        defaultBranch: 'main',
      );
      await Provisioner.updateRunnerFiles(api, config);
      final List<http.Request> updates = seen.where((http.Request request) => request.method == 'PUT').toList();
      final Set<String> paths = updates.map((http.Request request) => request.url.path).toSet();
      expect(paths, containsAll(<String>[
        '/repos/owner/repo/contents/nova-craft/config.py',
        '/repos/owner/repo/contents/nova-craft/fileops.py',
        '/repos/owner/repo/contents/nova-craft/playit.py',
        '/repos/owner/repo/contents/nova-craft/runner.sh',
        '/repos/owner/repo/contents/.github/workflows/novacraft-server.yml',
        '/repos/owner/repo/contents/nova-craft/commands/.gitkeep',
      ]));
      expect(paths, isNot(contains('/repos/owner/repo/contents/nova-craft/server.json')));
      expect(paths, isNot(contains('/repos/owner/repo/contents/server_data/server.properties')));
      expect(updates.every((http.Request request) => jsonDecode(request.body)['branch'] == 'main'), isTrue);
      final http.Request runner = updates.firstWhere((http.Request request) => request.url.path.endsWith('/nova-craft/runner.sh'));
      expect(utf8.decode(base64Decode(jsonDecode(runner.body)['content'] as String)), WorkflowTemplates.runnerScript);
      final http.Request fileops = updates.firstWhere((http.Request request) => request.url.path.endsWith('/nova-craft/fileops.py'));
      expect(utf8.decode(base64Decode(jsonDecode(fileops.body)['content'] as String)), WorkflowTemplates.fileOpsScript);
      expect(updates.length, 6);
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
