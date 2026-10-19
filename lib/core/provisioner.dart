import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'github_api.dart';
import 'models.dart';
import 'validation.dart';
import 'workflow_templates.dart';

/// Writes the files that turn a repository into a NOVA CRAFT server, and
/// exposes only the operations the UI is allowed to trigger.
///
/// Server data always lives under [ServerConfig.serverRoot]; repository files
/// (source code, CI, docs) are never touched by the file browser.
class Provisioner {
  const Provisioner._();

  static const String configPath = 'nova-craft/server.json';
  static const String statusPath = 'nova-craft/status.json';
  static const String liveLogPath = 'nova-craft/live.log';
  static const String commandsPath = 'nova-craft/commands';
  static const String workflowFile = 'novacraft-server.yml';
  static const String runnerPath = 'nova-craft/runner.sh';
  static const String configScriptPath = 'nova-craft/config.py';
  static const String fileOpsPath = 'nova-craft/fileops.py';
  static const String playitScriptPath = 'nova-craft/playit.py';
  static const String fileOpsRequestPath = 'nova-craft/files/request.json';
  static const String fileOpsResponsePath = 'nova-craft/files/response.json';
  static const String manifestPath = 'nova-craft/files/manifest.json';
  static const String addonsPath = 'nova-craft/addons';
  static const String addonStatePath = 'nova-craft/addons/state.json';
  static const String addonResultPath = 'nova-craft/addons/result.json';
  static const String importResultPath = 'nova-craft/import/result.json';

  static Future<void> _putText(GitHubApi api, ServerConfig c, String path, String text, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path, branch: c.defaultBranch);
    await api.putText(c.repoOwner, c.repoName, path, text, message, sha: sha, branch: c.defaultBranch);
  }

  static Future<void> _putBytes(GitHubApi api, ServerConfig c, String path, Uint8List bytes, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path, branch: c.defaultBranch);
    await api.putFile(c.repoOwner, c.repoName, path, bytes, message, sha: sha, branch: c.defaultBranch);
  }

  static Future<void> _deleteIfPresent(GitHubApi api, ServerConfig c, String path, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path, branch: c.defaultBranch);
    if (sha != null) await api.deleteFile(c.repoOwner, c.repoName, path, sha, message, branch: c.defaultBranch);
  }

  /// Full provisioning: repository metadata, runner, workflow, properties,
  /// and — only when explicitly chosen — the EULA marker.
  static Future<void> writeServerFiles(GitHubApi api, ServerConfig c, Uint8List? iconPng) async {
    await _putText(api, c, configPath, const JsonEncoder.withIndent('  ').convert(c.toJson()), 'nova: server config');
    await _putText(api, c, configScriptPath, WorkflowTemplates.configScript, 'nova: runner config bridge');
    await _putText(api, c, fileOpsPath, WorkflowTemplates.fileOpsScript, 'nova: server file operations');
    await _putText(api, c, playitScriptPath, WorkflowTemplates.playitScript, 'nova: playit helper');
    await _putText(api, c, runnerPath, WorkflowTemplates.runnerScript, 'nova: runner');
    await _putText(api, c, '.github/workflows/$workflowFile', WorkflowTemplates.serverWorkflow(c.id), 'nova: server workflow');
    await _putText(api, c, '$commandsPath/.gitkeep', '', 'nova: commands queue');

    final String root = c.serverRoot;
    if (c.isBedrock) {
      await _putText(api, c, '$root/server.properties', WorkflowTemplates.bedrockProperties(c), 'nova: bedrock properties');
    } else {
      await _putText(api, c, '$root/server.properties', WorkflowTemplates.javaProperties(c), 'nova: java properties');
      if (c.eulaAccepted) {
        await _putText(api, c, '$root/eula.txt', 'eula=true\n', 'nova: accept eula');
      } else {
        // Never leave an accepted marker behind when the user did not agree.
        await _deleteIfPresent(api, c, '$root/eula.txt', 'nova: eula not accepted');
      }
    }

    if (iconPng != null) {
      await _putBytes(api, c, '$root/server-icon.png', iconPng, 'nova: server icon');
    }
  }

  /// Upgrades only NOVA CRAFT's generated workflow/helpers for an existing
  /// server repository. It deliberately leaves server.json, game properties,
  /// the world, backups and repository Secrets untouched.
  static Future<void> updateRunnerFiles(GitHubApi api, ServerConfig c) async {
    await _putText(api, c, configScriptPath, WorkflowTemplates.configScript, 'nova: update runner config bridge');
    await _putText(api, c, fileOpsPath, WorkflowTemplates.fileOpsScript, 'nova: update runner file operations');
    await _putText(api, c, playitScriptPath, WorkflowTemplates.playitScript, 'nova: update Playit diagnostics');
    await _putText(api, c, runnerPath, WorkflowTemplates.runnerScript, 'nova: update server runner');
    await _putText(api, c, '.github/workflows/$workflowFile', WorkflowTemplates.serverWorkflow(c.id), 'nova: update server workflow');
    await _putText(api, c, '$commandsPath/.gitkeep', '', 'nova: update command queue');
  }

  /// Writes settings without touching the EULA flag or the download pin.
  static Future<void> updateConfig(GitHubApi api, ServerConfig c) async {
    await _putText(api, c, configPath, const JsonEncoder.withIndent('  ').convert(c.toJson()), 'nova: update config');
    final String root = c.serverRoot;
    if (c.isBedrock) {
      await _putText(api, c, '$root/server.properties', WorkflowTemplates.bedrockProperties(c), 'nova: update properties');
    } else {
      await _putText(api, c, '$root/server.properties', WorkflowTemplates.javaProperties(c), 'nova: update properties');
      if (c.eulaAccepted) {
        await _putText(api, c, '$root/eula.txt', 'eula=true\n', 'nova: accept eula');
      } else {
        await _deleteIfPresent(api, c, '$root/eula.txt', 'nova: eula withdrawn');
      }
    }
  }

  static Future<void> startServer(GitHubApi api, ServerConfig c) {
    return api.dispatch(c.repoOwner, c.repoName, workflowFile, inputs: <String, String>{'action': 'start'});
  }

  static Future<void> snapshot(GitHubApi api, ServerConfig c) {
    return api.dispatch(c.repoOwner, c.repoName, workflowFile, inputs: <String, String>{'action': 'snapshot'});
  }

  static Future<void> restoreBackup(GitHubApi api, ServerConfig c, String tag) {
    if (!tag.startsWith('backup-${c.id}-') || !RegExp(r'^backup-[A-Za-z0-9_-]+$').hasMatch(tag)) {
      throw ApiException(400, 'Backup tag does not belong to this server');
    }
    return api.dispatch(
      c.repoOwner,
      c.repoName,
      workflowFile,
      inputs: <String, String>{'action': 'start', 'restore_tag': tag},
    );
  }

  static Future<void> cancelRun(GitHubApi api, ServerConfig c, int runId) {
    return api.cancelRun(c.repoOwner, c.repoName, runId);
  }

  static Future<void> sendCommand(
    GitHubApi api,
    ServerConfig c,
    String command, {
    bool confirmedDangerous = false,
    bool system = false,
  }) async {
    final String trimmed = command.trim();
    if (!Validation.isSafeConsoleCommand(trimmed)) {
      throw ApiException(400, 'Command is empty, too long, or contains control characters');
    }
    final String commandRoot = trimmed.toLowerCase().replaceFirst(RegExp(r'^/'), '');
    if (!system && commandRoot.startsWith('nova:')) {
      throw ApiException(400, 'The nova: command namespace is reserved for the system');
    }
    if (!system && !c.allowCommands) {
      throw ApiException(403, 'Console commands are disabled in this server configuration');
    }
    if (!system && Validation.isDangerousCommand(trimmed) && !confirmedDangerous) {
      throw ApiException(400, 'This command requires explicit confirmation');
    }
    final String name = '$commandsPath/${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}.txt';
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, name);
    await api.putText(c.repoOwner, c.repoName, name, trimmed, 'nova: queue command', sha: sha);
  }

  /// Stops gracefully; the system stop signal is allowed even when user
  /// console commands are disabled.
  static Future<void> stopServer(GitHubApi api, ServerConfig c) async {
    await sendCommand(api, c, 'nova:stop', system: true);
  }

  static Future<void> requestBackup(GitHubApi api, ServerConfig c) async {
    await sendCommand(api, c, 'nova:backup', system: true);
  }

  /// A stop request makes the runner skip its self-restart; the explicit
  /// dispatch below then starts a fresh cycle. GitHub `concurrency` serialises
  /// the two runs instead of racing them.
  static Future<void> restartServer(GitHubApi api, ServerConfig c, {required bool activeRun}) async {
    if (activeRun) {
      await sendCommand(api, c, 'nova:stop', system: true);
    }
    await startServer(api, c);
  }

  /// Queues a world archive; the runner extracts it into the data folder, then
  /// deletes the upload so the repository does not grow without bound.
  static Future<void> uploadWorldImport(GitHubApi api, ServerConfig c, Uint8List zipBytes, {String? name}) async {
    final String activeWorldName = name ?? (c.isBedrock ? 'Bedrock level' : 'world');
    await _putBytes(api, c, 'nova-craft/import/world.zip', zipBytes, 'nova: import world');
    await _putText(
      api,
      c,
      'nova-craft/import/world.json',
      jsonEncode(<String, dynamic>{'name': activeWorldName, 'uploadedAt': DateTime.now().toUtc().toIso8601String()}),
      'nova: import world metadata',
    );
  }

  /// Queues a file operation for the next runner cycle. Files are only ever
  /// touched on the runner, inside the server data folder.
  static Future<void> queueFileOp(
    GitHubApi api,
    ServerConfig c,
    Map<String, dynamic> op,
  ) async {
    final String id = '${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': id,
      'issuedAt': DateTime.now().toUtc().toIso8601String(),
      ...op,
    };
    await _putText(api, c, fileOpsRequestPath, jsonEncode(payload), 'nova: file operation $id');
  }

  /// Uploads a Bedrock add-on package (`.mcpack`, `.mcaddon`, `.mcworld`) and
  /// records it in the add-on state the runner applies on the next start.
  static Future<void> uploadAddon(
    GitHubApi api,
    ServerConfig c,
    String fileName,
    Uint8List bytes, {
    required bool enabled,
  }) async {
    final String safeName = _safeFileName(fileName);
    if (safeName.isEmpty) throw ApiException(400, 'Invalid add-on file name');
    final String path = '$addonsPath/$safeName';
    await _putBytes(api, c, path, bytes, 'nova: add-on $safeName');
    final String stateText = await _readOrDefault(api, c, addonStatePath, '{"schema":1,"packs":[]}');
    final Map<String, dynamic> state = _decodeState(stateText);
    final List<dynamic> packs = List<dynamic>.from(state['packs'] as List? ?? <dynamic>[]);
    final int index = packs.indexWhere((dynamic p) => p is Map && p['file'] == path);
    final Map<String, dynamic> entry = <String, dynamic>{
      'file': path,
      'name': safeName,
      'enabled': enabled,
      'addedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (index >= 0) {
      packs[index] = entry;
    } else {
      packs.add(entry);
    }
    state['schema'] = 1;
    state['packs'] = packs;
    await _putText(api, c, addonStatePath, const JsonEncoder.withIndent('  ').convert(state), 'nova: add-on state');
  }

  /// Enables or disables an already uploaded add-on. The runner rewrites the
  /// world pack manifests, so this changes real behaviour.
  static Future<void> setAddonEnabled(GitHubApi api, ServerConfig c, String file, bool enabled) async {
    final String stateText = await _readOrDefault(api, c, addonStatePath, '{"schema":1,"packs":[]}');
    final Map<String, dynamic> state = _decodeState(stateText);
    final List<dynamic> packs = List<dynamic>.from(state['packs'] as List? ?? <dynamic>[]);
    bool found = false;
    for (int i = 0; i < packs.length; i++) {
      final dynamic entry = packs[i];
      if (entry is Map && entry['file'] == file) {
        packs[i] = <String, dynamic>{...Map<String, dynamic>.from(entry), 'enabled': enabled};
        found = true;
      }
    }
    if (!found) throw ApiException(404, 'Add-on not found in this server');
    state['packs'] = packs;
    await _putText(api, c, addonStatePath, const JsonEncoder.withIndent('  ').convert(state), 'nova: toggle add-on');
  }

  static Future<void> removeAddon(GitHubApi api, ServerConfig c, String file) async {
    final String stateText = await _readOrDefault(api, c, addonStatePath, '{"schema":1,"packs":[]}');
    final Map<String, dynamic> state = _decodeState(stateText);
    final List<dynamic> packs = List<dynamic>.from(state['packs'] as List? ?? <dynamic>[]);
    packs.removeWhere((dynamic entry) => entry is Map && entry['file'] == file);
    state['packs'] = packs;
    await _putText(api, c, addonStatePath, const JsonEncoder.withIndent('  ').convert(state), 'nova: remove add-on');
    await _deleteIfPresent(api, c, file, 'nova: delete add-on package');
  }

  static Future<String> _readOrDefault(GitHubApi api, ServerConfig c, String path, String fallback) async {
    try {
      final String text = await api.getFileText(c.repoOwner, c.repoName, path);
      if (text.trim().isEmpty) return fallback;
      return text;
    } catch (_) {
      return fallback;
    }
  }

  static Map<String, dynamic> _decodeState(String text) {
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Corrupt state is replaced rather than crashing the screen.
    }
    return <String, dynamic>{'schema': 1, 'packs': <dynamic>[]};
  }

  static String _safeFileName(String value) {
    final int slash = value.lastIndexOf('/');
    final int backslash = value.lastIndexOf(r'\');
    final String base = value.substring((slash > backslash ? slash : backslash) + 1).trim();
    final String cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return '';
    return cleaned.length > 120 ? cleaned.substring(cleaned.length - 120) : cleaned;
  }

  static Future<SecretWriteResult> writePlayitSecret(GitHubApi api, ServerConfig c, String secret) {
    return api.putSecret(c.repoOwner, c.repoName, 'PLAYIT_SECRET_KEY', secret.trim());
  }

  static Future<List<ServerConfig>> discoverServers(GitHubApi api) async {
    final List<GhInstallation> installations = await api.listInstallations();
    final List<GhRepo> repos = <GhRepo>[];
    for (final GhInstallation installation in installations) {
      final List<GhRepo> found = await api.listInstallationRepos(installation.id);
      repos.addAll(found);
    }
    final Map<String, ServerConfig> byRepo = <String, ServerConfig>{};
    const int concurrency = 4;
    for (int i = 0; i < repos.length; i += concurrency) {
      final List<GhRepo> slice = repos.sublist(i, min(i + concurrency, repos.length));
      final List<ServerConfig?> results = await Future.wait(slice.map((GhRepo repo) async {
        try {
          final String text = await api.getFileText(repo.owner, repo.name, configPath);
          final dynamic decoded = jsonDecode(text);
          if (decoded is! Map) return null;
          final ServerConfig config = ServerConfig.fromJson(Map<String, dynamic>.from(decoded));
          return config.copyWith(
            repoOwner: repo.owner,
            repoName: repo.name,
            repoPrivate: repo.private,
            defaultBranch: repo.defaultBranch.isEmpty ? config.defaultBranch : repo.defaultBranch,
            name: config.name.isEmpty ? repo.name : config.name,
          );
        } catch (_) {
          // Not a NOVA CRAFT repository (or the app cannot read it).
          return null;
        }
      }));
      for (final ServerConfig? config in results) {
        if (config != null) byRepo[config.repoFull] = config;
      }
    }
    final List<ServerConfig> servers = byRepo.values.toList()
      ..sort((ServerConfig a, ServerConfig b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return servers;
  }

  static String _randomSuffix() {
    const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final Random random = Random.secure();
    return List<String>.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
