import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import 'cancellation.dart';
import 'github_api.dart';
import 'models.dart';
import 'modrinth_api.dart';
import 'provisioner.dart';

/// Installer stages are included in diagnostics and user-visible failures.
enum ModrinthInstallStage { versionLookup, configuration, compatibility, download, validation, upload, repositoryVerification }

class ModrinthInstallException implements Exception {
  const ModrinthInstallException(this.stage, this.message, {this.cause});

  final ModrinthInstallStage stage;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class ModrinthInstallReceipt {
  const ModrinthInstallReceipt({
    required this.path,
    required this.fileName,
    required this.size,
    required this.gitBlobSha,
    required this.gameVersion,
    required this.software,
  });

  final String path;
  final String fileName;
  final int size;
  final String gitBlobSha;
  final String gameVersion;
  final String software;
}

typedef ModrinthInstallLogSink = void Function(String event, Map<String, Object?> fields);

/// Coordinates a real Modrinth download and a verified GitHub repository write.
/// A downloaded JAR is never reported as installed until the exact Git blob is
/// visible under the server's configured plugins directory.
class ModrinthInstaller {
  ModrinthInstaller({
    required this.modrinth,
    required this.github,
    ModrinthInstallLogSink? logSink,
  }) : _logSink = logSink;

  final ModrinthApi modrinth;
  final GitHubApi github;
  final ModrinthInstallLogSink? _logSink;

  static const int _uploadAttempts = 2;

  Future<List<ModrinthVersion>> requestVersions(
    ModrinthProject project, {
    required ServerConfig server,
    required CancellationToken cancellation,
  }) async {
    _log('versions.request.start', <String, Object?>{
      'project': project.slug,
      'projectId': project.id,
      'loader': server.software.toLowerCase(),
      'gameVersion': server.mcVersion,
    });
    try {
      final List<ModrinthVersion> versions = await modrinth.versions(
        project.id,
        cancellation: cancellation,
      );
      _log('versions.request.success', <String, Object?>{
        'project': project.slug,
        'count': versions.length,
      });
      return versions;
    } on OperationCancelledException {
      _log('versions.request.cancelled', <String, Object?>{'project': project.slug});
      rethrow;
    } catch (error, stackTrace) {
      _log('versions.request.failure', <String, Object?>{
        'project': project.slug,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
      throw ModrinthInstallException(
        ModrinthInstallStage.versionLookup,
        _describe(error),
        cause: error,
      );
    }
  }

  Future<ModrinthInstallReceipt> install({
    required ModrinthProject project,
    required ModrinthVersion version,
    required ServerConfig expectedServer,
    required String branch,
    required CancellationToken cancellation,
    ModrinthDownloadProgress? onDownloadProgress,
  }) async {
    final ServerConfig server = await _readRepositoryConfig(expectedServer, branch, cancellation);
    cancellation.throwIfCancelled();

    _log('compatibility.check.start', <String, Object?>{
      'project': project.slug,
      'version': version.versionNumber,
      'serverId': server.id,
      'software': server.software,
      'gameVersion': server.mcVersion,
      'loaders': version.loaders.join(','),
      'declaredGameVersions': version.gameVersions.join(','),
    });
    if (!modrinthCompatibleWithServer(project, version, server)) {
      _log('compatibility.check.failure', <String, Object?>{
        'project': project.slug,
        'version': version.versionNumber,
        'software': server.software,
        'gameVersion': server.mcVersion,
        'loaders': version.loaders.join(','),
        'declaredGameVersions': version.gameVersions.join(','),
      });
      throw ModrinthInstallException(
        ModrinthInstallStage.compatibility,
        'The selected Modrinth release does not match the repository server type and Minecraft version.',
      );
    }
    _log('compatibility.check.success', <String, Object?>{
      'software': server.software,
      'gameVersion': server.mcVersion,
    });

    final ModrinthVersionFile? file = version.primaryFile;
    if (file == null) {
      _log('jar.selection.failure', <String, Object?>{
        'project': project.slug,
        'version': version.versionNumber,
        'fileCount': version.files.length,
      });
      throw const ModrinthInstallException(
        ModrinthInstallStage.validation,
        'Modrinth did not provide one unambiguous primary file for this version.',
      );
    }
    final String fileName = file.filename;
    if (!_isSafeJarName(fileName)) {
      _log('jar.selection.failure', <String, Object?>{
        'project': project.slug,
        'version': version.versionNumber,
        'file': fileName,
      });
      throw ModrinthInstallException(
        ModrinthInstallStage.validation,
        'Modrinth selected an invalid plugin filename: $fileName',
      );
    }

    final String targetPath;
    try {
      targetPath = _pluginTargetPath(server, fileName);
    } catch (error) {
      _log('plugin.path.validation.failure', <String, Object?>{
        'serverRoot': server.serverRoot,
        'error': _describe(error),
      }, error: error);
      throw ModrinthInstallException(ModrinthInstallStage.configuration, _describe(error), cause: error);
    }

    final Uint8List bytes;
    _log('jar.download.start', <String, Object?>{
      'project': project.slug,
      'version': version.versionNumber,
      'file': fileName,
      'expectedBytes': file.size,
      'hashes': file.hashes.keys.join(','),
    });
    try {
      bytes = await modrinth.download(
        file,
        cancellation: cancellation,
        onProgress: onDownloadProgress,
      );
    } on OperationCancelledException {
      _log('jar.download.cancelled', <String, Object?>{'file': fileName});
      rethrow;
    } catch (error, stackTrace) {
      _log('jar.download.failure', <String, Object?>{
        'file': fileName,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
      throw ModrinthInstallException(
        ModrinthInstallStage.download,
        _describe(error),
        cause: error,
      );
    }

    final String localSha256;
    try {
      cancellation.throwIfCancelled();
      _validateJar(fileName, bytes);
      localSha256 = crypto.sha256.convert(bytes).toString();
      _log('jar.download.verified', <String, Object?>{
        'file': fileName,
        'bytes': bytes.length,
        'sha256': localSha256,
        'modrinthHash': _hashAlgorithm(file),
      });
    } catch (error, stackTrace) {
      if (error is OperationCancelledException) rethrow;
      _log('jar.validation.failure', <String, Object?>{
        'file': fileName,
        'bytes': bytes.length,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
      throw ModrinthInstallException(
        ModrinthInstallStage.validation,
        _describe(error),
        cause: error,
      );
    }

    cancellation.throwIfCancelled();
    final String expectedGitSha = _gitBlobSha(bytes);
    Future<ModrinthInstallReceipt> confirmedReceipt({String? recoveredFrom}) async {
      if (recoveredFrom != null) {
        _log('github.upload.recovered', <String, Object?>{'path': targetPath, 'reason': recoveredFrom});
      }
      await _removeReplacedPluginJars(server, project, branch, targetPath);
      _log('github.repository.verify.success', <String, Object?>{
        'path': targetPath,
        'bytes': bytes.length,
        'gitBlobSha': expectedGitSha,
      });
      _log('plugin.install.success', <String, Object?>{
        'project': project.slug,
        'version': version.versionNumber,
        'path': targetPath,
        'bytes': bytes.length,
        'gitBlobSha': expectedGitSha,
      });
      return ModrinthInstallReceipt(
        path: targetPath,
        fileName: fileName,
        size: bytes.length,
        gitBlobSha: expectedGitSha,
        gameVersion: server.mcVersion,
        software: server.software,
      );
    }

    _log('github.upload.start', <String, Object?>{
      'repository': '${server.repoOwner}/${server.repoName}',
      'branch': branch,
      'path': targetPath,
      'bytes': bytes.length,
      'attempts': _uploadAttempts,
      'sha256': localSha256,
    });

    String? existingSha;
    try {
      existingSha = await github.fileSha(
        server.repoOwner,
        server.repoName,
        targetPath,
        branch: branch,
        abortTrigger: cancellation.whenCancelled,
      );
    } catch (error, stackTrace) {
      if (cancellation.isCancelled) {
        _log('github.upload.preflight.cancelled', <String, Object?>{'path': targetPath});
        throw const OperationCancelledException();
      }
      _log('github.upload.preflight.failure', <String, Object?>{
        'path': targetPath,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
      throw ModrinthInstallException(ModrinthInstallStage.upload, _describe(error), cause: error);
    }
    _log('github.upload.preflight.success', <String, Object?>{
      'path': targetPath,
      'existingGitBlobSha': existingSha ?? 'missing',
    });

    if (existingSha?.toLowerCase() == expectedGitSha) {
      final bool alreadyPresent = await _isExactFilePresent(
        server.repoOwner,
        server.repoName,
        branch,
        targetPath,
        bytes.length,
        expectedGitSha,
      );
      if (alreadyPresent) return await confirmedReceipt(recoveredFrom: 'already_present');
    }

    for (int attempt = 1; attempt <= _uploadAttempts; attempt++) {
      cancellation.throwIfCancelled();
      try {
        _log('github.upload.request.start', <String, Object?>{'path': targetPath, 'attempt': attempt});
        await github.putFile(
          server.repoOwner,
          server.repoName,
          targetPath,
          bytes,
          'nova: install ${project.slug} ${version.versionNumber}',
          sha: existingSha,
          branch: branch,
          abortTrigger: cancellation.whenCancelled,
        );
        _log('github.upload.request.success', <String, Object?>{'path': targetPath, 'attempt': attempt});
      } catch (error, stackTrace) {
        if (cancellation.isCancelled) {
          bool committed = await _isExactFilePresent(
            server.repoOwner,
            server.repoName,
            branch,
            targetPath,
            bytes.length,
            expectedGitSha,
          );
          if (!committed) {
            // The server may already have accepted the write when the client
            // aborted its wait. Reconcile once after a brief settle interval.
            await Future<void>.delayed(const Duration(milliseconds: 500));
            committed = await _isExactFilePresent(
              server.repoOwner,
              server.repoName,
              branch,
              targetPath,
              bytes.length,
              expectedGitSha,
            );
          }
          if (committed) return await confirmedReceipt(recoveredFrom: 'cancelled_after_commit');
          _log('github.upload.cancelled', <String, Object?>{'path': targetPath});
          throw const OperationCancelledException();
        }

        _log('github.upload.request.failure', <String, Object?>{
          'path': targetPath,
          'attempt': attempt,
          'error': _describe(error),
        }, error: error, stackTrace: stackTrace);

        // Any failed/ambiguous write gets read back first. A successful exact
        // match is safe to report even if the response itself was malformed;
        // a retry is still restricted to explicitly transient errors below.
        final bool committed = await _isExactFilePresent(
          server.repoOwner,
          server.repoName,
          branch,
          targetPath,
          bytes.length,
          expectedGitSha,
        );
        if (committed) return await confirmedReceipt(recoveredFrom: 'write_error_reconciled');
        if (!_isTransientNetworkError(error)) {
          throw ModrinthInstallException(ModrinthInstallStage.upload, _describe(error), cause: error);
        }

        // A timed-out PATCH may have reached GitHub. Verify before retrying so
        // the app never creates duplicate commits or uploads invalid bytes.
        // Let any accepted GitHub request settle, then reconcile a second time
        // before considering another write. This avoids duplicate commits when
        // the first response was merely delayed or the contents listing lagged.
        await cancellation.waitOrCancel(const Duration(milliseconds: 500));
        final bool committedAfterSettle = await _isExactFilePresent(
          server.repoOwner,
          server.repoName,
          branch,
          targetPath,
          bytes.length,
          expectedGitSha,
        );
        if (committedAfterSettle) return await confirmedReceipt(recoveredFrom: 'delayed_response');
        if (attempt == _uploadAttempts) {
          throw ModrinthInstallException(
            ModrinthInstallStage.upload,
            'GitHub did not confirm the upload after a temporary network failure. Check the repository before retrying.',
            cause: error,
          );
        }
        try {
          existingSha = await github.fileSha(
            server.repoOwner,
            server.repoName,
            targetPath,
            branch: branch,
            abortTrigger: cancellation.whenCancelled,
          );
        } catch (refreshError, refreshStackTrace) {
          if (cancellation.isCancelled) {
            _log('github.upload.retry_preflight.cancelled', <String, Object?>{'path': targetPath});
            throw const OperationCancelledException();
          }
          _log('github.upload.preflight.failure', <String, Object?>{
            'path': targetPath,
            'error': _describe(refreshError),
          }, error: refreshError, stackTrace: refreshStackTrace);
          throw ModrinthInstallException(
            ModrinthInstallStage.upload,
            'Could not safely prepare a retry because GitHub could not confirm the current file state: ${_describe(refreshError)}',
            cause: refreshError,
          );
        }
        continue;
      }

      try {
        final bool verified = await _isExactFilePresent(
          server.repoOwner,
          server.repoName,
          branch,
          targetPath,
          bytes.length,
          expectedGitSha,
        );
        if (!verified) {
          if (cancellation.isCancelled) throw const OperationCancelledException();
          _log('github.repository.verify.failure', <String, Object?>{
            'path': targetPath,
            'error': 'file, size, or Git blob SHA did not match the verified download',
          });
          throw const ModrinthInstallException(
            ModrinthInstallStage.repositoryVerification,
            'GitHub accepted the upload request but the expected JAR was not present with the expected size and content hash.',
          );
        }
        return await confirmedReceipt();
      } catch (error, stackTrace) {
        if (error is OperationCancelledException || error is ModrinthInstallException) rethrow;
        _log('github.repository.verify.failure', <String, Object?>{
          'path': targetPath,
          'error': _describe(error),
        }, error: error, stackTrace: stackTrace);
        throw ModrinthInstallException(
          ModrinthInstallStage.repositoryVerification,
          _describe(error),
          cause: error,
        );
      }
    }

    throw const ModrinthInstallException(
      ModrinthInstallStage.upload,
      'GitHub upload could not be confirmed.',
    );
  }

  Future<ServerConfig> _readRepositoryConfig(
    ServerConfig expectedServer,
    String branch,
    CancellationToken cancellation,
  ) async {
    _log('server.config.read.start', <String, Object?>{
      'repository': '${expectedServer.repoOwner}/${expectedServer.repoName}',
      'path': Provisioner.configPath,
    });
    try {
      final String text = await github.getFileText(
        expectedServer.repoOwner,
        expectedServer.repoName,
        Provisioner.configPath,
        branch: branch,
        abortTrigger: cancellation.whenCancelled,
      );
      cancellation.throwIfCancelled();
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Server configuration is not a JSON object');
      final ServerConfig actual = ServerConfig.fromJson(Map<String, dynamic>.from(decoded));
      if (actual.id != expectedServer.id ||
          actual.repoOwner.toLowerCase() != expectedServer.repoOwner.toLowerCase() ||
          actual.repoName.toLowerCase() != expectedServer.repoName.toLowerCase()) {
        throw const FormatException('Repository server identity does not match the selected server');
      }
      _log('server.config.read.success', <String, Object?>{
        'serverId': actual.id,
        'software': actual.software,
        'gameVersion': actual.mcVersion,
      });
      return actual;
    } on OperationCancelledException {
      _log('server.config.read.cancelled', <String, Object?>{'path': Provisioner.configPath});
      rethrow;
    } catch (error, stackTrace) {
      if (cancellation.isCancelled) {
        _log('server.config.read.cancelled', <String, Object?>{'path': Provisioner.configPath});
        throw const OperationCancelledException();
      }
      _log('server.config.read.failure', <String, Object?>{'error': _describe(error)}, error: error, stackTrace: stackTrace);
      throw ModrinthInstallException(
        ModrinthInstallStage.configuration,
        'Could not verify the current server settings in nova-craft/server.json: ${_describe(error)}',
        cause: error,
      );
    }
  }

  Future<void> _removeReplacedPluginJars(
    ServerConfig server,
    ModrinthProject project,
    String branch,
    String targetPath,
  ) async {
    final int slash = targetPath.lastIndexOf('/');
    final String directory = slash < 0 ? '' : targetPath.substring(0, slash);
    try {
      final List<DirEntry> entries = await github.listDir(
        server.repoOwner,
        server.repoName,
        directory,
        branch: branch,
      );
      final String slug = project.slug.toLowerCase();
      final String id = project.id.toLowerCase();
      if (slug.isEmpty && id.isEmpty) return;
      for (final DirEntry entry in entries) {
        final String name = entry.name.toLowerCase();
        final bool matchesProject = (slug.isNotEmpty && name.contains(slug)) || (id.isNotEmpty && name.contains(id));
        if (!entry.isFile ||
            !name.endsWith('.jar') ||
            entry.path == targetPath ||
            !matchesProject ||
            entry.sha.isEmpty) {
          continue;
        }
        _log('github.cleanup.start', <String, Object?>{'path': entry.path});
        try {
          await github.deleteFile(
            server.repoOwner,
            server.repoName,
            entry.path,
            entry.sha,
            'nova: replace ${entry.name} with ${project.slug}',
            branch: branch,
          );
          _log('github.cleanup.success', <String, Object?>{'path': entry.path});
        } catch (error, stackTrace) {
          // Keep the original behavior: a verified new JAR is installed even
          // if best-effort removal of the old version needs manual cleanup.
          _log('github.cleanup.failure', <String, Object?>{
            'path': entry.path,
            'error': _describe(error),
          }, error: error, stackTrace: stackTrace);
        }
        break;
      }
    } catch (error, stackTrace) {
      _log('github.cleanup.list_failure', <String, Object?>{
        'directory': directory,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
    }
  }

  Future<bool> _isExactFilePresent(
    String owner,
    String repo,
    String branch,
    String targetPath,
    int expectedBytes,
    String expectedGitSha,
  ) async {
    _log('github.repository.verify.start', <String, Object?>{
      'path': targetPath,
      'expectedBytes': expectedBytes,
    });
    try {
      final int slash = targetPath.lastIndexOf('/');
      final String directory = slash < 0 ? '' : targetPath.substring(0, slash);
      final String fileName = slash < 0 ? targetPath : targetPath.substring(slash + 1);
      final List<DirEntry> entries;
      try {
        entries = await github.listDir(owner, repo, directory, branch: branch);
      } catch (listError, listStackTrace) {
        _log('github.repository.verify.list_failure', <String, Object?>{
          'path': targetPath,
          'error': _describe(listError),
        }, error: listError, stackTrace: listStackTrace);
        final String? fallbackSha = await github.fileSha(owner, repo, targetPath, branch: branch);
        final bool fallbackVerified = fallbackSha?.toLowerCase() == expectedGitSha;
        _log(fallbackVerified ? 'github.repository.verify.sha_match' : 'github.repository.verify.not_confirmed', <String, Object?>{
          'path': targetPath,
          'directSha': fallbackSha ?? 'missing',
          'fallback': 'contents_endpoint',
        });
        return fallbackVerified;
      }
      for (final DirEntry entry in entries) {
        if (entry.name == fileName && entry.path == targetPath) {
          if (entry.isFile && entry.size == expectedBytes && entry.sha.toLowerCase() == expectedGitSha) return true;
          break;
        }
      }
      // On an ambiguous upload response, Contents listing may lag the branch
      // update. A direct file SHA is still a cryptographic confirmation of the
      // exact downloaded blob and avoids a duplicate commit.
      final String? directSha = await github.fileSha(owner, repo, targetPath, branch: branch);
      final bool verified = directSha?.toLowerCase() == expectedGitSha;
      _log(verified ? 'github.repository.verify.sha_match' : 'github.repository.verify.not_confirmed', <String, Object?>{
        'path': targetPath,
        'directSha': directSha ?? 'missing',
      });
      return verified;
    } catch (error, stackTrace) {
      _log('github.repository.verify.failure', <String, Object?>{
        'path': targetPath,
        'error': _describe(error),
      }, error: error, stackTrace: stackTrace);
      if (error is ModrinthInstallException) rethrow;
      throw ModrinthInstallException(
        ModrinthInstallStage.repositoryVerification,
        _describe(error),
        cause: error,
      );
    }
  }

  static String _pluginTargetPath(ServerConfig server, String fileName) {
    final String root = server.serverRoot;
    if (root.isEmpty ||
        root.startsWith('/') ||
        root.contains('\\') ||
        root.split('/').any((String segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw const FormatException('The repository server data path is unsafe');
    }
    final String path = server.serverPath('plugins/$fileName');
    if (path.startsWith('/') || path.split('/').any((String segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw const FormatException('The plugin target path escaped the server data directory');
    }
    return path;
  }

  static bool _isSafeJarName(String fileName) =>
      fileName.isNotEmpty &&
      fileName == fileName.trim() &&
      fileName == fileName.split('/').last &&
      !fileName.contains('\\') &&
      !RegExp(r'[\x00-\x1F\x7F]').hasMatch(fileName) &&
      !fileName.contains('..') &&
      fileName.toLowerCase().endsWith('.jar');

  static void _validateJar(String fileName, Uint8List bytes) {
    if (!_isSafeJarName(fileName)) throw const FormatException('The selected file is not a safe .jar filename');
    if (bytes.length < 4) throw const FormatException('The downloaded JAR is empty or truncated');
    final bool zipHeader = bytes[0] == 0x50 && bytes[1] == 0x4b &&
        ((bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06));
    if (!zipHeader) throw const FormatException('The downloaded file is not a valid JAR/ZIP archive');
  }

  static String _gitBlobSha(Uint8List bytes) {
    final Uint8List prefix = Uint8List.fromList(utf8.encode('blob ${bytes.length}\u0000'));
    final Uint8List gitObject = Uint8List(prefix.length + bytes.length)
      ..setRange(0, prefix.length, prefix)
      ..setRange(prefix.length, prefix.length + bytes.length, bytes);
    return crypto.sha1.convert(gitObject).toString();
  }

  static bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException) {
      return true;
    }
    if (error is ApiException) {
      return const <int>{408, 425, 429, 500, 502, 503, 504}.contains(error.status);
    }
    return false;
  }

  static String _hashAlgorithm(ModrinthVersionFile file) {
    for (final String algorithm in <String>['sha512', 'sha256', 'sha1', 'md5']) {
      if (file.hashes[algorithm]?.isNotEmpty == true) return algorithm;
    }
    return 'size-only';
  }

  static String _describe(Object error) {
    if (error is ApiException) return 'HTTP ${error.status}: ${error.message}';
    if (error is TimeoutException) return 'Network timeout';
    if (error is SocketException) return 'Network connection failed: ${error.message}';
    if (error is http.ClientException) return 'Network request failed: ${error.message}';
    if (error is ModrinthIntegrityException || error is ModrinthIncompleteDownloadException) return error.toString();
    if (error is FormatException) return error.message;
    if (error is ModrinthInstallException) return error.message;
    return error.toString();
  }

  void _log(String event, Map<String, Object?> fields, {Object? error, StackTrace? stackTrace}) {
    final ModrinthInstallLogSink? sink = _logSink;
    if (sink != null) {
      sink(event, fields);
      return;
    }
    final String values = fields.entries.map((MapEntry<String, Object?> entry) => '${entry.key}=${entry.value}').join(' ');
    developer.log(
      '$event $values',
      name: 'NOVA_CRAFT.PluginInstall',
      level: error == null ? 800 : 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
