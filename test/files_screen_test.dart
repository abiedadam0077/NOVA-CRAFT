import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_craft/core/github_api.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/provisioner.dart';
import 'package:nova_craft/core/server_file_manifest.dart';
import 'package:nova_craft/core/strings.dart';
import 'package:nova_craft/design/theme.dart';
import 'package:nova_craft/design/tokens.dart';
import 'package:nova_craft/features/files/files_screen.dart';
import 'package:nova_craft/state/app_state.dart';

const ServerConfig _config = ServerConfig(
  id: 'server-test',
  name: 'Test server',
  repoOwner: 'owner',
  repoName: 'repo',
  defaultBranch: 'main',
);

http.Response _content(String text) => http.Response(
      jsonEncode(<String, dynamic>{'content': base64Encode(utf8.encode(text)), 'size': text.length, 'sha': 'blob-sha'}),
      200,
    );

Map<String, dynamic> _manifest({List<Map<String, dynamic>>? files, List<String>? dirs}) => <String, dynamic>{
      'schema': 1,
      'generatedAt': '2026-10-18T12:00:00Z',
      'truncated': false,
      'files': files ?? <Map<String, dynamic>>[],
      'dirs': dirs ?? <String>[],
    };

Map<String, dynamic> _run({
  int id = 7,
  String status = 'completed',
  String? conclusion = 'success',
}) => <String, dynamic>{
      'id': id,
      'name': 'NOVA CRAFT Server',
      'status': status,
      'conclusion': conclusion,
      'created_at': '2026-10-18T12:00:00Z',
      'updated_at': '2026-10-18T12:01:00Z',
      'html_url': 'https://github.com/owner/repo/actions/runs/$id',
      'event': 'workflow_dispatch',
      'run_started_at': '2026-10-18T12:00:01Z',
      'head_sha': 'abc123',
    };

class _TimeoutGitHubApi extends GitHubApi {
  _TimeoutGitHubApi(http.Client client) : super(client: client);

  @override
  Future<String> getFileText(
    String owner,
    String repo,
    String path, {
    String? branch,
    Future<void>? abortTrigger,
  }) => Future<String>.error(TimeoutException('mock request timed out'));
}

Future<AppState> _pumpFiles(
  WidgetTester tester,
  http.Client client, {
  String language = 'en',
  Duration timeout = const Duration(seconds: 1),
  GitHubApi? apiOverride,
}) async {
  final String previousLanguage = L10n.lang;
  L10n.lang = language;
  addTearDown(() => L10n.lang = previousLanguage);
  addTearDown(client.close);
  final AppState state = AppState(api: apiOverride ?? GitHubApi(client: client, timeout: timeout));
  state.language = language;
  await tester.pumpWidget(
    NovaTheme(
      palette: NovaPalette.dark,
      child: AppScope(
        state: state,
        child: MaterialApp(
          locale: Locale(language),
          home: Scaffold(body: ServerFilesView(key: ObjectKey(state.api), config: _config)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 20));
  return state;
}

http.Response _snapshotResponse() => _content(jsonEncode(<String, dynamic>{
      'schema': 1,
      'generatedAt': '2026-10-18T12:00:00Z',
      'truncated': false,
      'files': <String, String>{},
    }));

void main() {
  group('ServerFileManifest validation', () {
    test('parses a real file, directory and nested paths', () {
      final ServerFileManifest manifest = ServerFileManifest.fromJson(_manifest(
        dirs: <String>['world', 'world/region'],
        files: <Map<String, dynamic>>[
          <String, dynamic>{'path': 'server.properties', 'size': 22, 'modified': 1792324800},
          <String, dynamic>{'path': 'world/level.dat', 'size': 128, 'modified': 1792324800},
          <String, dynamic>{'path': 'world/region/r.0.0.mca', 'size': 512, 'modified': 1792324800},
        ],
      ));
      expect(manifest.entries.map((ServerFileEntry entry) => entry.path), <String>[
        'server.properties',
        'world',
        'world/level.dat',
        'world/region',
        'world/region/r.0.0.mca',
      ]);
      expect(manifest.generatedAt, isNotNull);
      expect(manifest.isEmpty, isFalse);
    });

    test('an actual empty manifest remains an empty state', () {
      expect(ServerFileManifest.fromJson(_manifest()).isEmpty, isTrue);
    });

    test('rejects out-of-range timestamps and non-integer sizes', () {
      expect(
        () => ServerFileEntry.fromJson(<String, dynamic>{'path': 'server.properties', 'size': 1, 'modified': 1e100}, isDir: false),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ServerFileEntry.fromJson(<String, dynamic>{'path': 'server.properties', 'size': 1.5, 'modified': 1792324800}, isDir: false),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects path traversal, absolute paths, backslashes and duplicates', () {
      for (final String path in <String>['../.git/config', '/etc/passwd', r'world\..\secret', 'world//file']) {
        expect(
          () => ServerFileManifest.fromJson(_manifest(files: <Map<String, dynamic>>[
            <String, dynamic>{'path': path, 'size': 1, 'modified': 1792324800},
          ])),
          throwsA(isA<FormatException>()),
          reason: path,
        );
      }
      expect(
        () => ServerFileManifest.fromJson(_manifest(dirs: <String>['world'], files: <Map<String, dynamic>>[
          <String, dynamic>{'path': 'world', 'size': 1, 'modified': 1792324800},
        ])),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ServerFileManifest.fromJson(_manifest(dirs: <String>['world/region'], files: <Map<String, dynamic>>[
          <String, dynamic>{'path': 'world', 'size': 1, 'modified': 1792324800},
          <String, dynamic>{'path': 'world/region/file.dat', 'size': 1, 'modified': 1792324800},
        ])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Files screen repository and workflow states', () {
    testWidgets('shows manifest-backed files and navigates real nested folders', (WidgetTester tester) async {
      final String manifestText = jsonEncode(_manifest(
        dirs: <String>['world', 'world/region'],
        files: <Map<String, dynamic>>[
          <String, dynamic>{'path': 'server.properties', 'size': 22, 'modified': 1792324800},
          <String, dynamic>{'path': 'world/level.dat', 'size': 128, 'modified': 1792324800},
          <String, dynamic>{'path': 'world/region/r.0.0.mca', 'size': 512, 'modified': 1792324800},
        ],
      ));
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return _content(manifestText);
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);

      expect(find.text('server.properties'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
      expect(find.textContaining('temporary Runner'), findsOneWidget);

      await tester.tap(find.text('world'));
      await tester.pumpAndSettle();
      expect(find.text('level.dat'), findsOneWidget);
      expect(find.text('region'), findsOneWidget);

      await tester.tap(find.text('region'));
      await tester.pumpAndSettle();
      expect(find.text('r.0.0.mca'), findsOneWidget);
    });

    testWidgets('shows a genuine empty manifest without fabricating files', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return _content(jsonEncode(_manifest()));
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('No files yet'), findsOneWidget);
      expect(find.text('server.properties'), findsNothing);
    });

    testWidgets('shows an actually empty nested folder and returns to server data', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return _content(jsonEncode(_manifest(dirs: <String>['empty'])));
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      await tester.tap(find.text('empty'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is empty'), findsOneWidget);
      expect(find.text('Back to server data'), findsOneWidget);
      await tester.tap(find.text('Back to server data'));
      await tester.pumpAndSettle();
      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the old manifest marked stale with its real age', (WidgetTester tester) async {
      int manifestReads = 0;
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
          manifestReads++;
          if (manifestReads > 1) throw const SocketException('refresh network failure');
          return _content(jsonEncode(_manifest(files: <Map<String, dynamic>>[
            <String, dynamic>{'path': 'alpha.txt', 'size': 5, 'modified': 1792324800},
          ])));
        }
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('alpha.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(manifestReads, 2);
      expect(find.text('alpha.txt'), findsOneWidget);
      expect(find.textContaining('last successful manifest'), findsOneWidget);
      expect(find.textContaining('Could not connect to GitHub'), findsOneWidget);
    });

    testWidgets('the retry action re-requests a missing manifest instead of inventing a list', (WidgetTester tester) async {
      int reads = 0;
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
          reads++;
          if (reads == 1) throw const SocketException('first request unavailable');
          return _content(jsonEncode(_manifest(files: <Map<String, dynamic>>[
            <String, dynamic>{'path': 'retried.txt', 'size': 3, 'modified': 1792324800},
          ])));
        }
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('Could not connect to GitHub'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('retried.txt'), findsOneWidget);
    });

    testWidgets('404 plus active Workflow is reported as in progress', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
          return http.Response('{"message":"Not Found"}', 404);
        }
        if (request.url.path.contains('/actions/workflows/${Provisioner.workflowFile}/runs')) {
          return http.Response(jsonEncode(<String, dynamic>{'workflow_runs': <Map<String, dynamic>>[_run(status: 'in_progress', conclusion: null)]}), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('The server workflow is still running'), findsOneWidget);
      expect(find.textContaining('run #7'), findsOneWidget);
      expect(find.textContaining('in_progress'), findsOneWidget);
    });

    testWidgets('404 with no NOVA run explains that the server was not started', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return http.Response('{"message":"Not Found"}', 404);
        if (request.url.path.contains('/actions/workflows/${Provisioner.workflowFile}/runs')) {
          return http.Response(jsonEncode(<String, dynamic>{'workflow_runs': <dynamic>[]}), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('The server has not started yet'), findsOneWidget);
      expect(find.textContaining('No NOVA CRAFT server manifest'), findsOneWidget);
    });

    testWidgets('successful Workflow with missing manifest is diagnosed, not shown as empty', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return http.Response('{"message":"Not Found"}', 404);
        if (request.url.path.contains('/actions/workflows/${Provisioner.workflowFile}/runs')) {
          return http.Response(jsonEncode(<String, dynamic>{'workflow_runs': <Map<String, dynamic>>[_run(id: 9)]}), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('Workflow completed but the manifest is missing'), findsOneWidget);
      expect(find.textContaining('#9'), findsOneWidget);
      expect(find.textContaining('Contents: write'), findsOneWidget);
      expect(find.text('No files yet'), findsNothing);
    });

    testWidgets('failed Workflow includes its real conclusion', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return http.Response('{"message":"Not Found"}', 404);
        if (request.url.path.contains('/actions/workflows/${Provisioner.workflowFile}/runs')) {
          return http.Response(jsonEncode(<String, dynamic>{'workflow_runs': <Map<String, dynamic>>[_run(id: 10, conclusion: 'failure')]}), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('The file list could not be generated'), findsOneWidget);
      expect(find.textContaining('failure'), findsOneWidget);
    });

    testWidgets('manifest 403 reports Contents permission', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async =>
          http.Response('{"message":"Resource not accessible by integration"}', 403));
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('GitHub permission is insufficient'), findsOneWidget);
      expect(find.textContaining('Contents: read'), findsOneWidget);
    });

    testWidgets('missing manifest plus run-list 403 reports Actions permission', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return http.Response('{"message":"Not Found"}', 404);
        return http.Response('{"message":"Resource not accessible by integration"}', 403);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('GitHub permission is insufficient'), findsOneWidget);
      expect(find.textContaining('Actions: read'), findsOneWidget);
    });

    testWidgets('network errors and timeouts have distinct retry states', (WidgetTester tester) async {
      final AppState networkState = await _pumpFiles(
        tester,
        MockClient((http.Request request) async => throw const SocketException('mock network unavailable')),
      );
      addTearDown(networkState.dispose);
      expect(find.text('Could not connect to GitHub'), findsOneWidget);

      final http.Client timeoutClient = MockClient((http.Request request) async => http.Response('{}', 200));
      final AppState timeoutState = await _pumpFiles(
        tester,
        timeoutClient,
        apiOverride: _TimeoutGitHubApi(timeoutClient),
      );
      addTearDown(timeoutState.dispose);
      expect(find.text('The file request timed out'), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets('a missing snapshot is reported while the real manifest remains browsable', (WidgetTester tester) async {
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
          return _content(jsonEncode(_manifest(files: <Map<String, dynamic>>[
            <String, dynamic>{'path': 'server.properties', 'size': 22, 'modified': 1792324800},
          ])));
        }
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('server.properties'), findsOneWidget);
      expect(find.textContaining('editable snapshot was not published'), findsOneWidget);
      expect(find.textContaining('no permanent file-list Artifact'), findsOneWidget);
    });

    testWidgets('a truncated editable snapshot reports the missing portion without inventing files', (WidgetTester tester) async {
      final String snapshot = jsonEncode(<String, dynamic>{
        'schema': 1,
        'generatedAt': '2026-10-18T12:00:00Z',
        'truncated': true,
        'files': <String, String>{},
      });
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return _content(jsonEncode(_manifest()));
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _content(snapshot);
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('No files yet'), findsOneWidget);
      expect(find.textContaining('files omitted'), findsOneWidget);
      expect(find.text('server.properties'), findsNothing);
    });

    testWidgets('unsafe snapshot paths are rejected without hiding the real manifest', (WidgetTester tester) async {
      final String maliciousSnapshot = jsonEncode(<String, dynamic>{
        'schema': 1,
        'generatedAt': '2026-10-18T12:00:00Z',
        'truncated': false,
        'files': <String, String>{'../.git/config': base64Encode(utf8.encode('fake'))},
      });
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
          return _content(jsonEncode(_manifest(files: <Map<String, dynamic>>[
            <String, dynamic>{'path': 'server.properties', 'size': 22, 'modified': 1792324800},
          ])));
        }
        if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _content(maliciousSnapshot);
        return http.Response('{"message":"Not Found"}', 404);
      });
      final AppState state = await _pumpFiles(tester, client);
      addTearDown(state.dispose);
      expect(find.text('server.properties'), findsOneWidget);
      expect(find.textContaining('unsafe path'), findsOneWidget);
      expect(find.text('../.git/config'), findsNothing);
    });

    testWidgets('invalid JSON and traversal paths are rejected instead of rendered empty', (WidgetTester tester) async {
      final AppState invalidJsonState = await _pumpFiles(
        tester,
        MockClient((http.Request request) async {
          if (request.url.path.endsWith('/${Provisioner.manifestPath}')) return _content('{not-json');
          if (request.url.path.endsWith('/nova-craft/snapshot.json')) return _snapshotResponse();
          return http.Response('{"message":"Not Found"}', 404);
        }),
      );
      addTearDown(invalidJsonState.dispose);
      expect(find.text('The file manifest is invalid'), findsOneWidget);

      final AppState unsafeState = await _pumpFiles(
        tester,
        MockClient((http.Request request) async {
          if (request.url.path.endsWith('/${Provisioner.manifestPath}')) {
            return _content(jsonEncode(_manifest(files: <Map<String, dynamic>>[
              <String, dynamic>{'path': '../.git/config', 'size': 5, 'modified': 1792324800},
            ])));
          }
          return _snapshotResponse();
        }),
      );
      addTearDown(unsafeState.dispose);
      expect(find.text('The file manifest is invalid'), findsOneWidget);
      expect(find.text('../.git/config'), findsNothing);
    });
  });
}
