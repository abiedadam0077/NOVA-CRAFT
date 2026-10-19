import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

bool _isSafeServerRelativePath(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.startsWith('/') ||
      value.contains(String.fromCharCode(92)) ||
      value.codeUnits.any((int code) => code < 0x20 || code == 0x7f)) {
    return false;
  }
  return value.split('/').every((String part) => part.isNotEmpty && part != '.' && part != '..');
}

/// One entry of the runner's file manifest.
class ServerFileEntry {
  const ServerFileEntry({required this.path, required this.size, required this.modified, required this.isDir});

  final String path;
  final int size;
  final DateTime? modified;
  final bool isDir;

  String get name => path.contains('/') ? path.split('/').last : path;

  factory ServerFileEntry.fromJson(Map<String, dynamic> o, {required bool isDir}) {
    final dynamic rawPath = o['path'];
    final dynamic rawSize = o['size'];
    final dynamic rawModified = o['modified'];
    if (rawPath is! String || rawPath.isEmpty || rawSize is! int || rawSize < 0) {
      throw const FormatException('Manifest file entry is missing a valid path or size');
    }
    DateTime? modified;
    if (rawModified is num && rawModified.isFinite && rawModified >= 0) {
      if (rawModified > 8640000000000 || rawModified != rawModified.roundToDouble()) {
        throw const FormatException('Manifest file timestamp is outside the supported range');
      }
      try {
        modified = DateTime.fromMillisecondsSinceEpoch(rawModified.toInt() * 1000).toLocal();
      } on ArgumentError {
        throw const FormatException('Manifest file timestamp is outside the supported range');
      }
    } else if (rawModified is String) {
      modified = DateTime.tryParse(rawModified)?.toLocal();
      if (modified == null) throw const FormatException('Manifest file timestamp is invalid');
    } else if (rawModified != null) {
      throw const FormatException('Manifest file timestamp has an unexpected type');
    }
    return ServerFileEntry(
      path: rawPath,
      size: rawSize.toInt(),
      modified: modified,
      isDir: isDir,
    );
  }
}

/// Parsed `nova-craft/files/manifest.json`.
class ServerFileManifest {
  const ServerFileManifest({required this.entries, required this.generatedAt, this.truncated = false});

  final List<ServerFileEntry> entries;
  final DateTime? generatedAt;
  final bool truncated;

  bool get isEmpty => entries.isEmpty;

  static ServerFileManifest fromJson(Map<String, dynamic> o) {
    final dynamic rawFiles = o['files'];
    final dynamic rawDirs = o['dirs'];
    if (rawFiles is! List || (rawDirs != null && rawDirs is! List)) {
      throw const FormatException('File manifest has no valid files/dirs arrays');
    }

    final List<ServerFileEntry> entries = <ServerFileEntry>[];
    final Set<String> seen = <String>{};
    for (final dynamic raw in (rawDirs as List? ?? <dynamic>[])) {
      if (raw is! String || !_isSafeServerRelativePath(raw) || !seen.add(raw)) {
        throw const FormatException('File manifest contains an unsafe or duplicate directory path');
      }
      entries.add(ServerFileEntry(path: raw, size: 0, modified: null, isDir: true));
    }
    for (final dynamic raw in rawFiles) {
      if (raw is! Map) throw const FormatException('File manifest contains a malformed file entry');
      final ServerFileEntry entry = ServerFileEntry.fromJson(Map<String, dynamic>.from(raw), isDir: false);
      if (!_isSafeServerRelativePath(entry.path) || !seen.add(entry.path)) {
        throw const FormatException('File manifest contains an unsafe or duplicate file path');
      }
      entries.add(entry);
    }
    final Set<String> filePaths = entries.where((ServerFileEntry entry) => !entry.isDir).map((ServerFileEntry entry) => entry.path).toSet();
    final Set<String> dirPaths = entries.where((ServerFileEntry entry) => entry.isDir).map((ServerFileEntry entry) => entry.path).toSet();
    if (dirPaths.any(filePaths.contains)) {
      throw const FormatException('Manifest declares one path as both a file and directory');
    }
    for (final String path in filePaths) {
      int slash = path.lastIndexOf('/');
      while (slash >= 0) {
        if (filePaths.contains(path.substring(0, slash))) {
          throw const FormatException('Manifest file path is nested below another file');
        }
        slash = path.lastIndexOf('/', slash - 1);
      }
    }
    entries.sort((ServerFileEntry a, ServerFileEntry b) => a.path.compareTo(b.path));
    final dynamic schema = o['schema'];
    if (schema != null && schema != 1) throw const FormatException('Unsupported file manifest schema');
    if (o['truncated'] != null && o['truncated'] is! bool) {
      throw const FormatException('Manifest truncated flag is invalid');
    }
    final dynamic stamp = o['generatedAt'];
    final DateTime? generatedAt = stamp == null ? null : DateTime.tryParse(stamp.toString())?.toLocal();
    if (stamp != null && generatedAt == null) {
      throw const FormatException('File manifest generatedAt is not a valid timestamp');
    }
    return ServerFileManifest(entries: entries, generatedAt: generatedAt, truncated: o['truncated'] == true);
  }
}

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key, required this.active, required this.onPickServer});

  final bool active;
  final VoidCallback onPickServer;

  @override
  Widget build(BuildContext context) {
    final ServerConfig? server = AppScope.of(context).selected;
    if (server == null) {
      return SafeArea(
        bottom: false,
        child: EmptyState(
          title: L10n.t('noServersYet'),
          body: L10n.t('firstServerBody'),
          icon: Icons.folder_copy_rounded,
          actionLabel: L10n.t('homeServerSwitcher'),
          onAction: onPickServer,
          artAsset: 'assets/images/art_island.jpg',
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: ServerFilesView(config: server, active: active),
    );
  }
}

/// Server-data-only file browser.
///
/// Everything shown here comes from `nova-craft/files/manifest.json`, which the
/// runner generates from the real server data folder on the runner. Repository
/// files (workflow YAML, source code, credentials) can never appear because the
/// runner never lists them, and every write request is applied by the runner
/// through `fileops.py`, which rejects paths outside the data root.
class ServerFilesView extends StatefulWidget {
  const ServerFilesView({super.key, required this.config, this.active = true});

  final ServerConfig config;
  final bool active;

  @override
  State<ServerFilesView> createState() => _ServerFilesViewState();
}

enum _FilesIssueKind {
  workflowRunning,
  serverNotStarted,
  manifestMissingAfterSuccess,
  workflowFailed,
  workflowUnavailable,
  contentsDenied,
  actionsDenied,
  authRequired,
  rateLimit,
  networkError,
  timeout,
  invalidManifest,
  apiError,
}

class _FilesIssue {
  const _FilesIssue(this.kind, {this.run, this.status, this.detail = ''});

  final _FilesIssueKind kind;
  final WorkflowRun? run;
  final int? status;
  final String detail;
}

class _ServerFilesViewState extends State<ServerFilesView> {
  final TextEditingController _search = TextEditingController();
  String _path = '';
  String _sort = 'name';
  bool _ascending = true;

  ServerFileManifest? _manifest;
  Map<String, String> _snapshot = <String, String>{}; // path -> base64 contents
  bool _loading = true;
  bool _refreshing = false;
  _FilesIssue? _problem;
  String? _snapshotWarning;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant ServerFilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool serverChanged = oldWidget.config.id != widget.config.id ||
        oldWidget.config.repoOwner != widget.config.repoOwner ||
        oldWidget.config.repoName != widget.config.repoName ||
        oldWidget.config.defaultBranch != widget.config.defaultBranch;
    if (serverChanged) {
      _path = '';
      _manifest = null;
      _snapshot = <String, String>{};
      _problem = null;
      _snapshotWarning = null;
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(withSnapshot: true);
      });
    } else if (oldWidget.active != widget.active && widget.active && _manifest == null) {
      _load(withSnapshot: true);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool withSnapshot = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = _manifest == null;
      _refreshing = true;
      _problem = null;
      _snapshotWarning = null;
    });
    final AppState state = AppScope.read(context);
    try {
      final String text = await state.api.getFileText(
        widget.config.repoOwner,
        widget.config.repoName,
        Provisioner.manifestPath,
        branch: widget.config.defaultBranch,
      );
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Manifest response is not a JSON object');
      final ServerFileManifest manifest = ServerFileManifest.fromJson(Map<String, dynamic>.from(decoded));
      Map<String, String> snapshot = _snapshot;
      if (withSnapshot || snapshot.isEmpty) snapshot = await _readSnapshot();
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _snapshot = snapshot;
        _loading = false;
        _problem = null;
      });
    } on ApiException catch (error) {
      final _FilesIssue issue = error.status == 404
          ? await _diagnoseMissingManifest(state)
          : _issueFor(error, workflowCheck: false);
      if (!mounted) return;
      setState(() {
        _problem = issue;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _problem = const _FilesIssue(_FilesIssueKind.timeout);
        _loading = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _problem = const _FilesIssue(_FilesIssueKind.networkError);
        _loading = false;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _problem = const _FilesIssue(_FilesIssueKind.invalidManifest);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _problem = _issueFor(error, workflowCheck: false);
        _loading = false;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<_FilesIssue> _diagnoseMissingManifest(AppState state) async {
    try {
      final List<WorkflowRun> runs = await state.api.listRuns(
        widget.config.repoOwner,
        widget.config.repoName,
        workflow: Provisioner.workflowFile,
      );
      runs.sort((WorkflowRun a, WorkflowRun b) => b.createdAt.compareTo(a.createdAt));
      for (final WorkflowRun run in runs) {
        if (run.isActive) return _FilesIssue(_FilesIssueKind.workflowRunning, run: run);
      }
      if (runs.isEmpty) return const _FilesIssue(_FilesIssueKind.serverNotStarted);
      final WorkflowRun latest = runs.first;
      if (latest.isCompleted && latest.conclusion == 'success') {
        return _FilesIssue(_FilesIssueKind.manifestMissingAfterSuccess, run: latest);
      }
      if (latest.isCompleted) return _FilesIssue(_FilesIssueKind.workflowFailed, run: latest);
      return _FilesIssue(_FilesIssueKind.workflowRunning, run: latest);
    } catch (error) {
      return _issueFor(error, workflowCheck: true);
    }
  }

  _FilesIssue _issueFor(Object error, {required bool workflowCheck}) {
    if (error is ApiException) {
      if (error.status == 401) return const _FilesIssue(_FilesIssueKind.authRequired, status: 401);
      if (error.status == 403 && error.message.toLowerCase().contains('rate limit')) {
        return _FilesIssue(_FilesIssueKind.rateLimit, status: 403, detail: error.message);
      }
      if (error.status == 403) {
        return _FilesIssue(
          workflowCheck ? _FilesIssueKind.actionsDenied : _FilesIssueKind.contentsDenied,
          status: 403,
        );
      }
      if (error.status == 404 && workflowCheck) {
        return _FilesIssue(_FilesIssueKind.workflowUnavailable, status: 404);
      }
      return _FilesIssue(_FilesIssueKind.apiError, status: error.status, detail: error.message);
    }
    if (error is TimeoutException) return const _FilesIssue(_FilesIssueKind.timeout);
    if (error is SocketException) return const _FilesIssue(_FilesIssueKind.networkError);
    if (error is FormatException) return const _FilesIssue(_FilesIssueKind.invalidManifest);
    return _FilesIssue(_FilesIssueKind.apiError, detail: Fmt.error(error));
  }

  String _issueTitle(_FilesIssue issue) {
    switch (issue.kind) {
      case _FilesIssueKind.workflowRunning:
        return L10n.t('filesWorkflowRunningTitle');
      case _FilesIssueKind.serverNotStarted:
        return L10n.t('filesServerNotStartedTitle');
      case _FilesIssueKind.manifestMissingAfterSuccess:
        return L10n.t('filesManifestMissingTitle');
      case _FilesIssueKind.workflowFailed:
        return L10n.t('filesWorkflowFailedTitle');
      case _FilesIssueKind.workflowUnavailable:
        return L10n.t('filesWorkflowUnavailableTitle');
      case _FilesIssueKind.contentsDenied:
      case _FilesIssueKind.actionsDenied:
        return L10n.t('filesPermissionDeniedTitle');
      case _FilesIssueKind.authRequired:
        return L10n.t('filesAuthRequiredTitle');
      case _FilesIssueKind.rateLimit:
        return L10n.t('filesRateLimitTitle');
      case _FilesIssueKind.networkError:
        return L10n.t('filesNetworkErrorTitle');
      case _FilesIssueKind.timeout:
        return L10n.t('filesTimeoutTitle');
      case _FilesIssueKind.invalidManifest:
        return L10n.t('filesInvalidManifestTitle');
      case _FilesIssueKind.apiError:
        return L10n.t('filesApiErrorTitle');
    }
  }

  String _issueBody(_FilesIssue issue) {
    final WorkflowRun? run = issue.run;
    switch (issue.kind) {
      case _FilesIssueKind.workflowRunning:
        return L10n.f('filesWorkflowRunningBody', <String, String>{
          'run': run == null ? '—' : '#${run.id}',
          'status': run?.status ?? 'unknown',
        });
      case _FilesIssueKind.serverNotStarted:
        return L10n.t('filesServerNotStartedBody');
      case _FilesIssueKind.manifestMissingAfterSuccess:
        return L10n.f('filesManifestMissingAfterSuccessBody', <String, String>{
          'run': run == null ? '—' : '#${run.id}',
          'status': run?.conclusion ?? 'success',
        });
      case _FilesIssueKind.workflowFailed:
        return L10n.f('filesWorkflowFailedBody', <String, String>{
          'run': run == null ? '—' : '#${run.id}',
          'status': run?.conclusion ?? run?.status ?? 'unknown',
        });
      case _FilesIssueKind.workflowUnavailable:
        return L10n.t('filesWorkflowUnavailableBody');
      case _FilesIssueKind.contentsDenied:
        return L10n.t('filesContentsPermissionBody');
      case _FilesIssueKind.actionsDenied:
        return L10n.t('filesActionsPermissionBody');
      case _FilesIssueKind.authRequired:
        return L10n.t('filesAuthRequiredBody');
      case _FilesIssueKind.rateLimit:
        return L10n.t('filesRateLimitBody');
      case _FilesIssueKind.networkError:
        return L10n.t('filesNetworkErrorBody');
      case _FilesIssueKind.timeout:
        return L10n.t('filesTimeoutBody');
      case _FilesIssueKind.invalidManifest:
        return L10n.t('filesInvalidManifestBody');
      case _FilesIssueKind.apiError:
        return L10n.f('filesApiErrorBody', <String, String>{
          'status': issue.status?.toString() ?? '—',
          'detail': issue.detail.isEmpty ? L10n.t('unknown') : issue.detail,
        });
    }
  }

  Widget _issueWidget(_FilesIssue issue) {
    final String body = _issueBody(issue);
    if (issue.kind == _FilesIssueKind.workflowRunning || issue.kind == _FilesIssueKind.serverNotStarted) {
      return EmptyState(
        title: _issueTitle(issue),
        body: body,
        icon: issue.kind == _FilesIssueKind.workflowRunning ? Icons.sync_rounded : Icons.dns_rounded,
        actionLabel: L10n.t('retry'),
        onAction: () => _load(withSnapshot: true),
        compact: true,
      );
    }
    return ErrorState(
      title: _issueTitle(issue),
      message: body,
      onRetry: () => _load(withSnapshot: true),
      retryLabel: L10n.t('retry'),
    );
  }

  Future<Map<String, String>> _readSnapshot() async {
    final AppState state = AppScope.read(context);
    try {
      final String text = await state.api.getFileText(
        widget.config.repoOwner,
        widget.config.repoName,
        'nova-craft/snapshot.json',
        branch: widget.config.defaultBranch,
      );
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map || decoded['schema'] != 1 || decoded['files'] is! Map || decoded['truncated'] is! bool) {
        throw const FormatException('Snapshot response does not match the supported schema');
      }
      final dynamic generatedAt = decoded['generatedAt'];
      if (generatedAt is! String || DateTime.tryParse(generatedAt) == null) {
        throw const FormatException('Snapshot generation timestamp is invalid');
      }
      final Map<String, String> out = <String, String>{};
      int totalEncodedBytes = 0;
      (decoded['files'] as Map).forEach((dynamic key, dynamic value) {
        if (key is! String || key.length > 4096 || value is! String || !_isSafeServerRelativePath(key)) {
          throw const FormatException('Snapshot contains an unsafe path or invalid content');
        }
        if (out.length >= 150 || value.length > 87384 || totalEncodedBytes + value.length > 4 * 1024 * 1024) {
          throw const FormatException('Snapshot exceeds the supported file count or size');
        }
        final List<int> bytes = base64Decode(value);
        if (bytes.length > 64 * 1024) throw const FormatException('Snapshot file exceeds the supported size');
        totalEncodedBytes += value.length;
        out[key] = value;
      });
      _snapshotWarning = decoded['truncated'] == true ? 'filesSnapshotTruncated' : null;
      return out;
    } on ApiException catch (error) {
      _snapshotWarning = error.status == 404
          ? 'filesSnapshotMissing'
          : (error.status == 401 ? 'filesSnapshotAuthRequired' : (error.status == 403 ? 'filesSnapshotPermission' : 'filesSnapshotUnavailable'));
    } on TimeoutException {
      _snapshotWarning = 'filesSnapshotTimeout';
    } on SocketException {
      _snapshotWarning = 'filesSnapshotNetwork';
    } on FormatException {
      _snapshotWarning = 'filesSnapshotMalformed';
    } catch (_) {
      _snapshotWarning = 'filesSnapshotUnavailable';
    }
    return <String, String>{};
  }

  List<ServerFileEntry> get _children {
    final String prefix = _path.isEmpty ? '' : '$_path/';
    final Map<String, ServerFileEntry> seen = <String, ServerFileEntry>{};
    for (final ServerFileEntry entry in _manifest?.entries ?? <ServerFileEntry>[]) {
      if (!entry.path.startsWith(prefix) || entry.path == _path) continue;
      final String remainder = entry.path.substring(prefix.length);
      if (remainder.isEmpty) continue;
      final int slash = remainder.indexOf('/');
      if (slash < 0) {
        seen[entry.path] = entry;
      } else {
        final String dir = '$prefix${remainder.substring(0, slash)}';
        seen.putIfAbsent(dir, () => ServerFileEntry(path: dir, size: 0, modified: null, isDir: true));
      }
    }
    final List<ServerFileEntry> list = seen.values.toList();
    final String query = _search.text.trim().toLowerCase();
    list.removeWhere((ServerFileEntry e) => query.isNotEmpty && !e.name.toLowerCase().contains(query));
    list.sort((ServerFileEntry a, ServerFileEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int value;
      switch (_sort) {
        case 'size':
          value = a.size.compareTo(b.size);
          break;
        case 'date':
          final DateTime x = a.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime y = b.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          value = x.compareTo(y);
          break;
        default:
          value = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _ascending ? value : -value;
    });
    return list;
  }

  bool _isText(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    const Set<String> textExtensions = <String>{
      'txt', 'properties', 'json', 'yml', 'yaml', 'toml', 'cfg', 'conf', 'ini', 'log',
      'md', 'sh', 'xml', 'csv', 'mcmeta', 'snbt', 'list', 'html', 'js', 'py', 'java',
    };
    final String ext = path.substring(dot + 1).toLowerCase();
    return textExtensions.contains(ext);
  }

  String _decodeContent(String base64Text) {
    try {
      return utf8.decode(base64Decode(base64Text), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<void> _openEntry(ServerFileEntry entry) async {
    if (entry.isDir) {
      setState(() => _path = entry.path);
      return;
    }
    if (!_isText(entry.path)) {
      showNovaToast(context, L10n.t('filesBinaryNote'), kind: ToastKind.info);
      return;
    }
    await _openEditor(entry.path, entry.name);
  }

  Future<void> _openEditor(String path, String name) async {
    final String? encoded = _snapshot[path];
    if (encoded == null) {
      final bool live = await _requestRead(path, name);
      if (!mounted) return;
      if (!live) {
        showNovaToast(context, L10n.t('filesOfflineSnapshotNote'), kind: ToastKind.warning);
      }
      return;
    }
    final String initial = _decodeContent(encoded);
    if (!mounted) return;
    final String? next = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => FileEditorScreen(
          title: name,
          path: path,
          initialText: initial,
          project: widget.config,
          readOnly: false,
        ),
      ),
    );
    if (next == null || !mounted) return;
    await _saveSnapshotFile(path, next);
  }

  /// While the server runs, the runner can read a file immediately.
  Future<bool> _requestRead(String path, String name) async {
    final AppState state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await Provisioner.queueFileOp(state.api, widget.config, <String, dynamic>{'op': 'read', 'path': path});
      if (!mounted) return true;
      showNovaToast(context, L10n.t('fileReadQueued'), kind: ToastKind.success);
      return true;
    } catch (error) {
      if (mounted) showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stopped-server edits go through the published snapshot, which the runner
  /// re-applies before the next start.
  Future<void> _saveSnapshotFile(String path, String content) async {
    if (!_isSafeServerRelativePath(path)) {
      showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
      return;
    }
    final AppState state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final String? sha = await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, 'nova-craft/snapshot.json');
      final Map<String, dynamic> payload = <String, dynamic>{
        'schema': 1,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'truncated': false,
        'files': <String, String>{
          ..._snapshot,
          path: base64Encode(utf8.encode(content)),
        },
      };
      await state.api.putText(
        widget.config.repoOwner,
        widget.config.repoName,
        'nova-craft/snapshot.json',
        jsonEncode(payload),
        'nova: edit $path',
        sha: sha,
      );
      // The runner applies the same file immediately when it is running.
      await Provisioner.queueFileOp(state.api, widget.config, <String, dynamic>{
        'op': 'write',
        'path': path,
        'content': base64Encode(utf8.encode(content)),
      });
      if (!mounted) return;
      setState(() => _snapshot = <String, String>{..._snapshot, path: base64Encode(utf8.encode(content))});
      showNovaToast(context, L10n.t('savedFile'), kind: ToastKind.success);
    } catch (error) {
      if (mounted) showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ServerFileEntry entry) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('deleteFileTitle'),
      body: entry.isDir ? L10n.t('deleteFolderNote') : L10n.f('deleteFileBody', <String, String>{'name': entry.name}),
      confirmLabel: L10n.t('delete'),
      danger: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    await _queue(<String, dynamic>{'op': 'delete', 'path': entry.path});
  }

  Future<void> _rename(ServerFileEntry entry) async {
    final TextEditingController controller = TextEditingController(text: entry.name);
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        final p = ctx.nova;
        return AlertDialog(
          backgroundColor: p.cardHigh,
          shape: RoundedRectangleBorder(borderRadius: NovaRadii.rLg),
          title: Text(L10n.t('rename'), style: NovaTextStyles.title(p.text)),
          content: NovaField(controller: controller, autofocus: true),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.t('cancel'))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text(L10n.t('save'))),
          ],
        );
      },
    );
    final String parent = entry.path.contains('/') ? entry.path.substring(0, entry.path.lastIndexOf('/')) : '';
    if (next == null || next.isEmpty || next == entry.name || !mounted) return;
    if (next.contains('/') || next.contains(String.fromCharCode(92)) || next == '.' || next == '..') {
      showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
      return;
    }
    await _queue(<String, dynamic>{
      'op': 'rename',
      'path': entry.path,
      'dest': parent.isEmpty ? next : '$parent/$next',
    });
  }

  Future<void> _newFolder() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        final p = ctx.nova;
        return AlertDialog(
          backgroundColor: p.cardHigh,
          shape: RoundedRectangleBorder(borderRadius: NovaRadii.rLg),
          title: Text(L10n.t('newFolder'), style: NovaTextStyles.title(p.text)),
          content: NovaField(controller: controller, autofocus: true, hint: 'config'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(L10n.t('cancel'))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text(L10n.t('save'))),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (name.contains('/') || name.contains(String.fromCharCode(92)) || name == '.' || name == '..') {
      showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
      return;
    }
    await _queue(<String, dynamic>{
      'op': 'mkdir',
      'path': _path.isEmpty ? name : '$_path/$name',
    });
  }

  Future<void> _upload() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || !mounted) return;
    final PlatformFile file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    if (bytes.length > 20 * 1024 * 1024) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    final String safeName = Validation.sanitizeFileUploadName(file.name);
    if (!_isSafeServerRelativePath(safeName) || safeName.contains('/')) {
      showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
      return;
    }
    final String target = _path.isEmpty ? safeName : '$_path/$safeName';
    await _queue(<String, dynamic>{
      'op': 'write',
      'path': target,
      'content': base64Encode(bytes),
    });
  }

  Future<void> _queue(Map<String, dynamic> op) async {
    for (final String key in <String>['path', 'dest']) {
      final dynamic value = op[key];
      if (value is String && !_isSafeServerRelativePath(value)) {
        showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
        return;
      }
    }
    final AppState state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await Provisioner.queueFileOp(state.api, widget.config, op);
      if (!mounted) return;
      showNovaToast(context, L10n.t('fileOpQueued'), kind: ToastKind.success);
      await _load(withSnapshot: true);
    } catch (error) {
      if (mounted) showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDetails(ServerFileEntry entry) async {
    final p = context.nova;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: p.stroke)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill))),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(entry.isDir ? Icons.folder_rounded : Icons.description_rounded, color: p.primaryBright),
                const SizedBox(width: 10),
                Expanded(child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text))),
              ],
            ),
            const SizedBox(height: 12),
            InfoRow(label: L10n.t('pathBreadcrumb'), value: '/${entry.path}', monospace: true),
            InfoRow(label: L10n.t('fileSize'), value: entry.isDir ? '—' : Fmt.bytes(entry.size)),
            InfoRow(label: L10n.t('fileModified'), value: Fmt.relative(entry.modified)),
            const SizedBox(height: 12),
            if (!entry.isDir)
              NovaButton(
                label: L10n.t('fileEdit'),
                icon: Icons.edit_note_rounded,
                variant: NovaButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openEntry(entry);
                },
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: NovaButton(
                    label: L10n.t('rename'),
                    icon: Icons.drive_file_rename_outline_rounded,
                    variant: NovaButtonVariant.ghost,
                    height: 46,
                    size: NovaButtonSize.compact,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _rename(entry);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NovaButton(
                    label: L10n.t('delete'),
                    icon: Icons.delete_outline_rounded,
                    variant: NovaButtonVariant.danger,
                    height: 46,
                    size: NovaButtonSize.compact,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _delete(entry);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerFileManifest? manifest = _manifest;
    final List<ServerFileEntry> children = _children;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(L10n.t('navFiles'), style: NovaTextStyles.heading(22, p.text)),
                    if (manifest?.generatedAt != null)
                      Text(
                        L10n.f('filesSyncedAt', <String, String>{'time': Fmt.relative(manifest!.generatedAt)}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTextStyles.caption(p.textDim),
                      )
                    else if (_problem == null)
                      Text(
                        L10n.t('filesWaitingForRun'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTextStyles.caption(p.textDim),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                decoration: BoxDecoration(
                  color: p.cardSoft.withValues(alpha: 0.8),
                  borderRadius: NovaRadii.rMd,
                  border: Border.all(color: p.stroke),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_busy || _refreshing)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      NovaIconButton(icon: Icons.refresh_rounded, size: 34, iconSize: 17, tooltip: L10n.t('refresh'), onTap: () => _load(withSnapshot: true)),
                    const SizedBox(width: 4),
                    NovaIconButton(icon: Icons.create_new_folder_rounded, size: 34, iconSize: 17, tooltip: L10n.t('newFolder'), onTap: _newFolder),
                    const SizedBox(width: 4),
                    NovaIconButton(icon: Icons.upload_rounded, size: 34, iconSize: 17, filled: true, tooltip: L10n.t('uploadFile'), onTap: _upload),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NovaSpace.page),
          child: NovaSearchField(
            controller: _search,
            hint: L10n.t('searchFiles'),
            onChanged: (_) => setState(() {}),
            onClear: () => setState(_search.clear),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NovaSpace.page),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                NovaChip(label: L10n.t('sortName'), selected: _sort == 'name', onTap: () => setState(() => _sort = 'name')),
                const SizedBox(width: 6),
                NovaChip(label: L10n.t('fileSize'), selected: _sort == 'size', onTap: () => setState(() => _sort = 'size')),
                const SizedBox(width: 6),
                NovaChip(label: L10n.t('fileModified'), selected: _sort == 'date', onTap: () => setState(() => _sort = 'date')),
                const SizedBox(width: 6),
                NovaChip(
                  label: _ascending ? L10n.t('ascending') : L10n.t('descending'),
                  icon: _ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  onTap: () => setState(() => _ascending = !_ascending),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NovaSpace.page),
          child: _BreadcrumbBar(
            segments: _path.isEmpty ? <String>[] : _path.split('/'),
            onRoot: () => setState(() => _path = ''),
            onSegment: (int i) => setState(() {
              final List<String> parts = _path.split('/');
              _path = parts.take(i + 1).join('/');
            }),
          ),
        ),
        const SizedBox(height: 8),
        if (manifest != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NovaSpace.page),
            child: Text(L10n.t('filesStorageNotice'), style: NovaTextStyles.caption(p.textDim)),
          ),
        if (manifest?.truncated == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(NovaSpace.page, 6, NovaSpace.page, 0),
            child: InfoBanner(body: L10n.t('filesManifestTruncated'), icon: Icons.warning_amber_rounded, color: p.warning, dense: true),
          ),
        if (_snapshotWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(NovaSpace.page, 6, NovaSpace.page, 0),
            child: InfoBanner(body: L10n.t(_snapshotWarning!), icon: Icons.info_outline_rounded, color: p.warning, dense: true),
          ),
        if (_problem != null && manifest != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(NovaSpace.page, 6, NovaSpace.page, 0),
            child: InfoBanner(
              title: _issueTitle(_problem!),
              body: L10n.f('filesStaleManifestBody', <String, String>{
                'time': Fmt.relative(manifest.generatedAt),
                'detail': _issueBody(_problem!),
              }),
              icon: Icons.cloud_off_rounded,
              color: p.warning,
              actionLabel: L10n.t('retry'),
              onAction: () => _load(withSnapshot: true),
              dense: true,
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? ListView(
                  padding: const EdgeInsets.all(NovaSpace.page),
                  children: const <Widget>[SkeletonList(count: 6, cardHeight: 54)],
                )
              : _problem != null && manifest == null
                  ? _issueWidget(_problem!)
                  : manifest == null
                      ? EmptyState(
                          title: L10n.t('filesUnavailableShort'),
                          body: L10n.t('filesServerNotStartedBody'),
                          icon: Icons.folder_open_rounded,
                          actionLabel: L10n.t('retry'),
                          onAction: () => _load(withSnapshot: true),
                          compact: true,
                        )
                      : children.isEmpty
                          ? EmptyState(
                              title: _search.text.trim().isNotEmpty
                                  ? L10n.t('filesNoMatchesTitle')
                                  : (_path.isEmpty ? L10n.t('filesEmptyTitle') : L10n.t('filesFolderEmptyTitle')),
                              body: _search.text.trim().isNotEmpty
                                  ? L10n.t('filesNoMatchesBody')
                                  : (_path.isEmpty ? L10n.t('filesEmptyBody') : L10n.t('filesFolderEmptyBody')),
                              icon: _search.text.trim().isNotEmpty ? Icons.search_off_rounded : Icons.folder_open_rounded,
                              actionLabel: _path.isEmpty ? null : L10n.t('filesBackToServerData'),
                              onAction: _path.isEmpty ? null : () => setState(() => _path = ''),
                              compact: true,
                            )
                          : RefreshIndicator(
                              color: p.primaryBright,
                              backgroundColor: p.cardHigh,
                              onRefresh: () => _load(withSnapshot: true),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 0, NovaSpace.page, 130),
                                itemCount: children.length,
                                separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 6),
                                itemBuilder: (BuildContext context, int index) {
                                  final ServerFileEntry entry = children[index];
                                  return _FileRow(
                                    entry: entry,
                                    onTap: () => _openEntry(entry),
                                    onLongPress: () => _showDetails(entry),
                                  );
                                },
                              ),
                            ),
        ),
        if (manifest != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(NovaSpace.page, 0, NovaSpace.page, 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, size: 12, color: p.textDim),
                const SizedBox(width: 6),
                Expanded(child: Text(L10n.t('serverDataOnly'), style: NovaTextStyles.caption(p.textDim))),
              ],
            ),
          ),
      ],
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.segments, required this.onRoot, required this.onSegment});

  final List<String> segments;
  final VoidCallback onRoot;
  final ValueChanged<int> onSegment;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final List<Widget> children = <Widget>[
      GestureDetector(
        onTap: onRoot,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: segments.isEmpty ? p.primary.withValues(alpha: 0.14) : p.cardSoft,
            borderRadius: NovaRadii.rXs,
            border: Border.all(color: segments.isEmpty ? p.primary.withValues(alpha: 0.35) : p.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.dns_rounded, size: 13, color: segments.isEmpty ? p.primaryBright : p.textMuted),
              const SizedBox(width: 5),
              Text(L10n.t('serverData'), style: NovaTextStyles.caption(segments.isEmpty ? p.primaryBright : p.textMuted)),
            ],
          ),
        ),
      ),
    ];
    for (int i = 0; i < segments.length; i++) {
      final bool last = i == segments.length - 1;
      children.add(Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Icon(context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 14, color: p.textDim),
      ));
      children.add(GestureDetector(
        onTap: () => onSegment(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: last ? p.primary.withValues(alpha: 0.14) : p.cardSoft,
            borderRadius: NovaRadii.rXs,
            border: Border.all(color: last ? p.primary.withValues(alpha: 0.35) : p.stroke),
          ),
          child: Text(segments[i], style: NovaTextStyles.caption(last ? p.primaryBright : p.textMuted)),
        ),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.entry, required this.onTap, required this.onLongPress});

  final ServerFileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: p.cardSoft,
          borderRadius: NovaRadii.rMd,
          border: Border.all(color: p.stroke),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (entry.isDir ? p.violet : p.primary).withValues(alpha: 0.12),
                borderRadius: NovaRadii.rXs,
              ),
              child: Icon(
                entry.isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                size: 17,
                color: entry.isDir ? p.violet : p.primaryBright,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.bodyStrong(p.text)),
                  Text(
                    entry.isDir ? L10n.t('folderLabel') : '${Fmt.bytes(entry.size)} · ${Fmt.relative(entry.modified)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.caption(p.textDim),
                  ),
                ],
              ),
            ),
            Icon(entry.isDir ? (context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded) : Icons.more_horiz_rounded, color: p.textDim, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Full-screen text editor used for real server configuration files.
class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({
    super.key,
    required this.title,
    required this.path,
    required this.initialText,
    this.project,
    this.readOnly = false,
  });

  final String title;
  final String path;
  final String initialText;
  final ServerConfig? project;
  final bool readOnly;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText);
  bool _dirty = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('discardChanges'),
      body: L10n.t('discardChangesBody'),
      confirmLabel: L10n.t('discard'),
      danger: true,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _close),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: NovaTextStyles.title(p.text)),
            Text('/${widget.path}', maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.caption(p.textDim)),
          ],
        ),
        actions: <Widget>[
          if (!widget.readOnly)
            TextButton(
              onPressed: _dirty ? () => Navigator.of(context).pop(_text.text) : null,
              child: Text(L10n.t('save')),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(NovaSpace.page),
          child: TextField(
            controller: _text,
            readOnly: widget.readOnly,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() => _dirty = true),
            style: NovaTextStyles.mono(12.5, p.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: p.cardSoft,
              border: OutlineInputBorder(borderRadius: NovaRadii.rMd, borderSide: BorderSide(color: p.stroke)),
              enabledBorder: OutlineInputBorder(borderRadius: NovaRadii.rMd, borderSide: BorderSide(color: p.stroke)),
              focusedBorder: OutlineInputBorder(borderRadius: NovaRadii.rMd, borderSide: BorderSide(color: p.primary)),
            ),
          ),
        ),
      ),
    );
  }
}
