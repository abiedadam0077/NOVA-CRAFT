import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'github_api.dart';
import 'models.dart';
import 'workflow_templates.dart';

/// Writes the files that make a repository a NOVA CRAFT server, and exposes the
/// real operations the UI is allowed to trigger.
class Provisioner {
  const Provisioner._();

  static const String configPath = 'nova-craft/server.json';
  static const String statusPath = 'nova-craft/status.json';
  static const String commandsPath = 'nova-craft/commands';
  static const String workflowFile = 'novacraft-server.yml';

  static Future<void> _putText(GitHubApi api, ServerConfig c, String path, String text, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path);
    await api.putText(c.repoOwner, c.repoName, path, text, message, sha: sha);
  }

  static Future<void> _putBytes(GitHubApi api, ServerConfig c, String path, Uint8List bytes, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path);
    await api.putFile(c.repoOwner, c.repoName, path, bytes, message, sha: sha);
  }

  static Future<void> writeServerFiles(GitHubApi api, ServerConfig c, Uint8List? iconPng) async {
    await _putText(api, c, configPath, const JsonEncoder.withIndent('  ').convert(c.toJson()), 'nova: server config');
    await _putText(api, c, '$commandsPath/.gitkeep', '', 'nova: commands queue');
    if (c.edition == 'BEDROCK') {
      await _putText(api, c, 'server/server.properties', WorkflowTemplates.bedrockProperties(c), 'nova: bedrock properties');
    } else {
      await _putText(api, c, 'server/server.properties', WorkflowTemplates.javaProperties(c), 'nova: java properties');
      await _putText(api, c, 'server/eula.txt', 'eula=true\n', 'nova: accept eula');
    }
    await _putText(api, c, '.github/workflows/$workflowFile', WorkflowTemplates.serverWorkflow(c.id), 'nova: server workflow');
    if (iconPng != null) {
      await _putBytes(api, c, 'server/server-icon.png', iconPng, 'nova: server icon');
    }
  }

  static Future<void> updateConfig(GitHubApi api, ServerConfig c) async {
    await _putText(api, c, configPath, const JsonEncoder.withIndent('  ').convert(c.toJson()), 'nova: update config');
    if (c.edition == 'BEDROCK') {
      await _putText(api, c, 'server/server.properties', WorkflowTemplates.bedrockProperties(c), 'nova: update properties');
    } else {
      await _putText(api, c, 'server/server.properties', WorkflowTemplates.javaProperties(c), 'nova: update properties');
    }
  }

  static Future<void> startServer(GitHubApi api, ServerConfig c) {
    return api.dispatch(c.repoOwner, c.repoName, workflowFile, inputs: <String, String>{'action': 'start'});
  }

  static Future<void> snapshot(GitHubApi api, ServerConfig c) {
    return api.dispatch(c.repoOwner, c.repoName, workflowFile, inputs: <String, String>{'action': 'snapshot'});
  }

  static Future<void> restoreBackup(GitHubApi api, ServerConfig c, String tag) {
    return api.dispatch(
      c.repoOwner,
      c.repoName,
      workflowFile,
      inputs: <String, String>{'action': 'start', 'restore_tag': tag},
    );
  }

  static Future<void> sendCommand(GitHubApi api, ServerConfig c, String command) async {
    final String name = '$commandsPath/${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}.txt';
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, name);
    await api.putText(c.repoOwner, c.repoName, name, command, 'nova: queue command', sha: sha);
  }

  /// Stops gracefully (the workflow saves and backs up first). When a run is
  /// active the stop command is picked up within ~12s.
  static Future<void> stopServer(GitHubApi api, ServerConfig c) async {
    await sendCommand(api, c, 'nova:stop');
  }

  /// A stop request makes the workflow skip its self-restart, so an explicit
  /// restart also dispatches a new cycle. GitHub `concurrency` serialises it.
  static Future<void> restartServer(GitHubApi api, ServerConfig c, {required bool activeRun}) async {
    if (activeRun) {
      await sendCommand(api, c, 'nova:stop');
    }
    await startServer(api, c);
  }

  static Future<void> uploadWorldImport(GitHubApi api, ServerConfig c, Uint8List zipBytes) async {
    await _putBytes(api, c, 'nova-craft/import/world.zip', zipBytes, 'nova: import world');
  }

  static Future<void> writePlayitSecret(GitHubApi api, ServerConfig c, String secret) {
    return api.putSecret(c.repoOwner, c.repoName, 'PLAYIT_SECRET_KEY', secret);
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
