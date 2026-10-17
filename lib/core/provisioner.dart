import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'github_api.dart';
import 'models.dart';
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

  static Future<void> _putText(GitHubApi api, ServerConfig c, String path, String text, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path);
    await api.putText(c.repoOwner, c.repoName, path, text, message, sha: sha);
  }

  static Future<void> _putBytes(GitHubApi api, ServerConfig c, String path, Uint8List bytes, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path);
    await api.putFile(c.repoOwner, c.repoName, path, bytes, message, sha: sha);
  }

  static Future<void> _deleteIfPresent(GitHubApi api, ServerConfig c, String path, String message) async {
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, path);
    if (sha != null) await api.deleteFile(c.repoOwner, c.repoName, path, sha, message);
  }

  /// Full provisioning: repository metadata, runner, workflow, properties,
  /// and — only when explicitly chosen — the EULA marker.
  static Future<void> writeServerFiles(GitHubApi api, ServerConfig c, Uint8List? iconPng) async {
    await _putText(api, c, configPath, const JsonEncoder.withIndent('  ').convert(c.toJson()), 'nova: server config');
    await _putText(api, c, configScriptPath, WorkflowTemplates.configScript, 'nova: runner config bridge');
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

  static Future<void> sendCommand(GitHubApi api, ServerConfig c, String command) async {
    final String trimmed = command.trim();
    if (trimmed.isEmpty || trimmed.length > 512) {
      throw ApiException(400, 'Command is empty or too long');
    }
    final String name = '$commandsPath/${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}.txt';
    final String? sha = await api.fileSha(c.repoOwner, c.repoName, name);
    await api.putText(c.repoOwner, c.repoName, name, trimmed, 'nova: queue command', sha: sha);
  }

  /// Stops gracefully: the runner flushes saves, uploads a backup, then exits.
  static Future<void> stopServer(GitHubApi api, ServerConfig c) async {
    await sendCommand(api, c, 'nova:stop');
  }

  /// A stop request makes the runner skip its self-restart; the explicit
  /// dispatch below then starts a fresh cycle. GitHub `concurrency` serialises
  /// the two runs instead of racing them.
  static Future<void> restartServer(GitHubApi api, ServerConfig c, {required bool activeRun}) async {
    if (activeRun) {
      await sendCommand(api, c, 'nova:stop');
    }
    await startServer(api, c);
  }

  /// Queues a world archive; the runner extracts it into the data folder, then
  /// deletes the upload so the repository does not grow without bound.
  static Future<void> uploadWorldImport(GitHubApi api, ServerConfig c, Uint8List zipBytes) async {
    await _putBytes(api, c, 'nova-craft/import/world.zip', zipBytes, 'nova: import world');
  }

  static Future<void> writePlayitSecret(GitHubApi api, ServerConfig c, String secret) {
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
