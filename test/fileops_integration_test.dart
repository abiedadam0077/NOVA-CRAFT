import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/workflow_templates.dart';

void main() {
  late Directory temp;
  late File fileops;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nova-fileops-integration-');
    fileops = File('${temp.path}/fileops.py')..writeAsStringSync(WorkflowTemplates.fileOpsScript);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<ProcessResult> runFileOps(List<String> args) => Process.run('python3', <String>[fileops.path, ...args]);

  Future<Map<String, dynamic>> request(Directory root, Map<String, dynamic> body) async {
    final File input = File('${temp.path}/request.json')..writeAsStringSync(jsonEncode(body));
    final File output = File('${temp.path}/response.json');
    final ProcessResult result = await runFileOps(<String>['request', root.path, input.path, output.path]);
    expect(result.exitCode, 0, reason: '${result.stderr} ${result.stdout}');
    return jsonDecode(await output.readAsString()) as Map<String, dynamic>;
  }

  test('manifest creates a missing output parent and lists real files and nested folders', () async {
    final Directory root = Directory('${temp.path}/server')..createSync();
    Directory('${root.path}/world/region').createSync(recursive: true);
    File('${root.path}/server.properties').writeAsStringSync('server-port=25565\n');
    File('${root.path}/world/level.dat').writeAsStringSync('world-data');
    File('${root.path}/world/region/r.0.0.mca').writeAsStringSync('region-data');
    final File out = File('${temp.path}/worktree/nova-craft/files/manifest.json');

    final ProcessResult result = await runFileOps(<String>['manifest', root.path, out.path]);
    expect(result.exitCode, 0, reason: '${result.stderr} ${result.stdout}');
    expect(await out.exists(), isTrue);
    expect(await File('${out.path}.tmp').exists(), isFalse);
    final Map<String, dynamic> manifest = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
    expect((manifest['files'] as List).map((dynamic entry) => (entry as Map)['path']), containsAll(<String>[
      'server.properties',
      'world/level.dat',
      'world/region/r.0.0.mca',
    ]));
    expect(manifest['dirs'], containsAll(<String>['world', 'world/region']));
    expect(DateTime.tryParse(manifest['generatedAt'] as String), isNotNull);
  });

  test('file, folder, nested-folder creation and updates are reflected in manifest', () async {
    final Directory root = Directory('${temp.path}/server')..createSync();
    final Map<String, dynamic> folder = await request(root, <String, dynamic>{'id': 'mkdir-1', 'op': 'mkdir', 'path': 'plugins/example'});
    expect(folder['ok'], isTrue);
    expect(await Directory('${root.path}/plugins/example').exists(), isTrue);

    final Map<String, dynamic> write = await request(root, <String, dynamic>{
      'id': 'write-1',
      'op': 'write',
      'path': 'plugins/example/config.json',
      'content': base64Encode(utf8.encode('{"enabled":false}')),
    });
    expect(write['ok'], isTrue);
    expect(await File('${root.path}/plugins/example/config.json').readAsString(), '{"enabled":false}');

    final Map<String, dynamic> update = await request(root, <String, dynamic>{
      'id': 'write-2',
      'op': 'write',
      'path': 'plugins/example/config.json',
      'content': base64Encode(utf8.encode('{"enabled":true}')),
    });
    expect(update['ok'], isTrue);
    expect(await File('${root.path}/plugins/example/config.json').readAsString(), '{"enabled":true}');

    final File out = File('${temp.path}/nova-craft/files/manifest.json');
    final ProcessResult manifestResult = await runFileOps(<String>['manifest', root.path, out.path]);
    expect(manifestResult.exitCode, 0, reason: '${manifestResult.stderr}');
    final Map<String, dynamic> manifest = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
    expect(manifest['dirs'], containsAll(<String>['plugins', 'plugins/example']));
    expect((manifest['files'] as List).map((dynamic entry) => (entry as Map)['path']), contains('plugins/example/config.json'));

    final Map<String, dynamic> listing = await request(root, <String, dynamic>{'id': 'list-1', 'op': 'list', 'path': 'plugins/example'});
    expect(listing['ok'], isTrue);
    expect(((listing['files'] as List).single as Map)['path'], 'plugins/example/config.json');
  });

  test('traversal and symlink escapes are rejected without writing outside server data', () async {
    final Directory root = Directory('${temp.path}/server')..createSync();
    final Directory outside = Directory('${temp.path}/outside')..createSync();
    final File secret = File('${outside.path}/keep.txt')..writeAsStringSync('do not change');

    final Map<String, dynamic> traversal = await request(root, <String, dynamic>{
      'id': 'escape-1',
      'op': 'write',
      'path': '../outside/escaped.txt',
      'content': base64Encode(utf8.encode('escaped')),
    });
    expect(traversal['ok'], isFalse);
    expect(traversal['error'], 'path-outside-root');
    expect(await File('${outside.path}/escaped.txt').exists(), isFalse);

    for (final String unsafePath in <String>['${outside.path}/absolute.txt', r'world\..\escape.txt']) {
      final Map<String, dynamic> invalid = await request(root, <String, dynamic>{
        'id': 'escape-invalid',
        'op': 'write',
        'path': unsafePath,
        'content': base64Encode(utf8.encode('escaped')),
      });
      expect(invalid['ok'], isFalse);
      expect(invalid['error'], 'path-outside-root');
    }

    // A deterministic temp name is unsafe even if the final destination is
    // inside root: a pre-existing symlink could make open(..., 'wb') truncate
    // an outside file before os.replace. The writer must use O_EXCL temp files.
    await Link('${root.path}/safe.txt.nova-tmp').create(secret.path);
    final Map<String, dynamic> tempSymlink = await request(root, <String, dynamic>{
      'id': 'escape-temp-link',
      'op': 'write',
      'path': 'safe.txt',
      'content': base64Encode(utf8.encode('safe in-root data')),
    });
    expect(tempSymlink['ok'], isTrue);
    expect(await secret.readAsString(), 'do not change');
    expect(await File('${root.path}/safe.txt').readAsString(), 'safe in-root data');

    final Link link = Link('${root.path}/escape');
    await link.create(outside.path);
    final Map<String, dynamic> symlink = await request(root, <String, dynamic>{
      'id': 'escape-2',
      'op': 'write',
      'path': 'escape/changed.txt',
      'content': base64Encode(utf8.encode('escaped')),
    });
    expect(symlink['ok'], isFalse);
    expect(symlink['error'], 'path-outside-root');
    expect(await secret.readAsString(), 'do not change');
    expect(await File('${outside.path}/changed.txt').exists(), isFalse);

    final Link rootLink = Link('${temp.path}/server-root-link');
    await rootLink.create(outside.path);
    final File linkedManifest = File('${temp.path}/linked-manifest.json');
    final ProcessResult linkedRootManifest = await runFileOps(<String>['manifest', rootLink.path, linkedManifest.path]);
    final File linkedSnapshot = File('${temp.path}/linked-snapshot.json');
    final ProcessResult linkedRootSnapshot = await runFileOps(<String>['snapshot', rootLink.path, linkedSnapshot.path]);
    expect(linkedRootManifest.exitCode, isNot(0));
    expect(linkedRootSnapshot.exitCode, isNot(0));
    expect(await linkedManifest.exists(), isFalse);
    expect(await linkedSnapshot.exists(), isFalse);
  });

  test('apply-snapshot rejects traversal and atomically updates only server-root files', () async {
    final Directory root = Directory('${temp.path}/server')..createSync();
    final Directory outside = Directory('${temp.path}/outside')..createSync();
    final File secret = File('${outside.path}/private.txt')..writeAsStringSync('private');
    final File inside = File('${root.path}/server.properties')..writeAsStringSync('old=true');
    final File validSnapshot = File('${temp.path}/valid-snapshot.json')
      ..writeAsStringSync(jsonEncode(<String, dynamic>{
        'files': <String, String>{'server.properties': base64Encode(utf8.encode('new=true'))},
      }));

    final ProcessResult valid = await runFileOps(<String>['apply-snapshot', root.path, validSnapshot.path]);
    expect(valid.exitCode, 0, reason: '${valid.stderr} ${valid.stdout}');
    expect(await inside.readAsString(), 'new=true');

    final File maliciousSnapshot = File('${temp.path}/malicious-snapshot.json')
      ..writeAsStringSync(jsonEncode(<String, dynamic>{
        'files': <String, String>{'../outside/private.txt': base64Encode(utf8.encode('overwritten'))},
      }));
    final ProcessResult malicious = await runFileOps(<String>['apply-snapshot', root.path, maliciousSnapshot.path]);
    expect(malicious.exitCode, isNot(0));
    expect(await secret.readAsString(), 'private');
  });

  test('the Runner publish_files function publishes a freshly generated manifest', () async {
    final String runner = WorkflowTemplates.runnerScript;
    const String startMarker = 'publish_files() {';
    const String endMarker = '\n}\n\n# File operations requested from the app.';
    final int start = runner.indexOf(startMarker);
    final int end = runner.indexOf(endMarker, start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final String publishFunction = runner.substring(start, end + 2);

    final Directory workspace = Directory('${temp.path}/workspace')..createSync();
    final Directory data = Directory('${temp.path}/server')..createSync();
    Directory('${workspace.path}/nova-craft').createSync(recursive: true);
    Directory('${data.path}/world/region').createSync(recursive: true);
    File('${data.path}/server.properties').writeAsStringSync('server-port=25565\n');
    File('${data.path}/world/region/r.0.0.mca').writeAsStringSync('actual-world');
    File('${workspace.path}/nova-craft/fileops.py').writeAsStringSync(WorkflowTemplates.fileOpsScript);

    final String harnessText = <String>[
      r'''#!/usr/bin/env bash
set -euo pipefail
WORKSPACE_ABS="$WORKSPACE_PATH"
DATA_ABS="${DATA_ABS_OVERRIDE:-$DATA_PATH}"
FILES_MANIFEST_STATUS=unknown
FILES_SNAPSHOT_STATUS=unknown
log() { printf '%s' "$*" >> "$TEST_TMP/runner.log"; }
put_file() {
  local path="$1" text="$2"
  if [ "${PUT_FAIL:-0}" = "1" ]; then return 1; fi
  mkdir -p "$TEST_TMP/published/$(dirname "$path")"
  printf '%s' "$text" > "$TEST_TMP/published/$path"
  return 0
}
''',
      publishFunction,
      r'''
publish_files
printf '__FILES__manifest=%s snapshot=%s\n' "$FILES_MANIFEST_STATUS" "$FILES_SNAPSHOT_STATUS"
''',
    ].join();
    final File harness = File('${temp.path}/publish.sh')..writeAsStringSync(harnessText);
    final Map<String, String> harnessEnvironment = <String, String>{
      'WORKSPACE_PATH': workspace.path,
      'DATA_PATH': data.path,
      'TEST_TMP': temp.path,
    };
    final ProcessResult syntax = await Process.run('bash', <String>['-n', harness.path], environment: harnessEnvironment);
    expect(syntax.exitCode, 0, reason: '${syntax.stderr}\n$harnessText');
    final ProcessResult result = await Process.run('bash', <String>[harness.path], environment: harnessEnvironment);
    expect(result.exitCode, 0, reason: '${result.stderr} ${result.stdout}');

    final File published = File('${temp.path}/published/nova-craft/files/manifest.json');
    expect(await published.exists(), isTrue);
    final Map<String, dynamic> manifest = jsonDecode(await published.readAsString()) as Map<String, dynamic>;
    expect((manifest['files'] as List).map((dynamic entry) => (entry as Map)['path']), containsAll(<String>[
      'server.properties',
      'world/region/r.0.0.mca',
    ]));
    expect(await File('${temp.path}/published/nova-craft/snapshot.json').exists(), isTrue);
    expect(result.stdout, contains('__FILES__manifest=published snapshot=published'));

    final ProcessResult publishFailure = await Process.run(
      'bash',
      <String>[harness.path],
      environment: <String, String>{...harnessEnvironment, 'PUT_FAIL': '1'},
    );
    expect(publishFailure.exitCode, 0, reason: publishFailure.stderr);
    expect(publishFailure.stdout, contains('__FILES__manifest=publish_failed snapshot=publish_failed'));
    final String publishLog = await File('${temp.path}/runner.log').readAsString();
    expect(publishLog, contains('generated file manifest could not be published'));
    expect(publishLog, contains('generated editable snapshot could not be published'));

    final File invalidData = File('${temp.path}/not-a-directory')..writeAsStringSync('not a directory');
    final ProcessResult generationFailure = await Process.run(
      'bash',
      <String>[harness.path],
      environment: <String, String>{...harnessEnvironment, 'DATA_ABS_OVERRIDE': invalidData.path},
    );
    expect(generationFailure.exitCode, 0, reason: generationFailure.stderr);
    expect(generationFailure.stdout, contains('__FILES__manifest=generation_failed snapshot=generation_failed'));
    final String generationLog = await File('${temp.path}/runner.log').readAsString();
    expect(generationLog, contains('manifest generation failed'));
    expect(generationLog, contains('config snapshot generation failed'));
  });
}
