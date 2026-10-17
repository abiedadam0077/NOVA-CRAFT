import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// One entry of the runner's file manifest.
class ServerFileEntry {
  const ServerFileEntry({required this.path, required this.size, required this.modified, required this.isDir});

  final String path;
  final int size;
  final DateTime? modified;
  final bool isDir;

  String get name => path.contains('/') ? path.split('/').last : path;

  factory ServerFileEntry.fromJson(Map<String, dynamic> o, {required bool isDir}) => ServerFileEntry(
        path: o['path']?.toString() ?? '',
        size: (o['size'] as num?)?.toInt() ?? 0,
        modified: DateTime.tryParse(o['modified']?.toString() ?? '')?.toLocal() ??
            ((o['modified'] is num)
                ? DateTime.fromMillisecondsSinceEpoch(((o['modified'] as num).toInt()) * 1000)
                : null),
        isDir: isDir,
      );
}

/// Parsed `nova-craft/files/manifest.json`.
class ServerFileManifest {
  const ServerFileManifest({required this.entries, required this.generatedAt, this.truncated = false});

  final List<ServerFileEntry> entries;
  final DateTime? generatedAt;
  final bool truncated;

  bool get isEmpty => entries.isEmpty;

  static ServerFileManifest fromJson(Map<String, dynamic> o) {
    final List<ServerFileEntry> entries = <ServerFileEntry>[];
    for (final dynamic raw in (o['dirs'] as List? ?? <dynamic>[])) {
      if (raw is String) {
        entries.add(ServerFileEntry(path: raw, size: 0, modified: null, isDir: true));
      }
    }
    for (final dynamic raw in (o['files'] as List? ?? <dynamic>[])) {
      if (raw is Map) {
        entries.add(ServerFileEntry.fromJson(Map<String, dynamic>.from(raw), isDir: false));
      }
    }
    entries.sort((ServerFileEntry a, ServerFileEntry b) => a.path.compareTo(b.path));
    final dynamic stamp = o['generatedAt'];
    return ServerFileManifest(
      entries: entries,
      generatedAt: stamp == null ? null : DateTime.tryParse(stamp.toString())?.toLocal(),
      truncated: o['truncated'] == true,
    );
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

class _ServerFilesViewState extends State<ServerFilesView> {
  final TextEditingController _search = TextEditingController();
  String _path = '';
  String _sort = 'name';
  bool _ascending = true;

  ServerFileManifest? _manifest;
  Map<String, String> _snapshot = <String, String>{}; // path -> base64 contents
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant ServerFilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active && widget.active && _manifest == null) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool withSnapshot = false}) async {
    setState(() {
      _loading = _manifest == null;
      _error = null;
    });
    final AppState state = AppScope.read(context);
    try {
      final String text = await state.api.getFileText(widget.config.repoOwner, widget.config.repoName, Provisioner.manifestPath);
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) throw ApiException(500, L10n.t('filesUnavailableShort'));
      final ServerFileManifest manifest = ServerFileManifest.fromJson(Map<String, dynamic>.from(decoded));
      Map<String, String> snapshot = _snapshot;
      if (withSnapshot || snapshot.isEmpty) {
        snapshot = await _readSnapshot();
      }
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _snapshot = snapshot;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.status == 404 ? L10n.t('filesNoManifestYet') : Fmt.error(error);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = Fmt.error(error);
        _loading = false;
      });
    }
  }

  Future<Map<String, String>> _readSnapshot() async {
    final AppState state = AppScope.read(context);
    try {
      final String text = await state.api.getFileText(widget.config.repoOwner, widget.config.repoName, 'nova-craft/snapshot.json');
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map && decoded['files'] is Map) {
        final Map<String, String> out = <String, String>{};
        (decoded['files'] as Map).forEach((dynamic key, dynamic value) {
          out[key.toString()] = value.toString();
        });
        return out;
      }
    } catch (_) {
      // No snapshot yet (fresh server) — editing stays unavailable until the
      // runner publishes one, and the UI says so.
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
    final String target = _path.isEmpty ? file.name : '$_path/${file.name}';
    await _queue(<String, dynamic>{
      'op': 'write',
      'path': target,
      'content': base64Encode(bytes),
    });
  }

  Future<void> _queue(Map<String, dynamic> op) async {
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
                    Text(
                      manifest?.generatedAt == null
                          ? L10n.t('filesWaitingForRun')
                          : L10n.f('filesSyncedAt', <String, String>{'time': Fmt.relative(manifest!.generatedAt)}),
                      style: NovaTextStyles.caption(p.textDim),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                NovaIconButton(icon: Icons.refresh_rounded, size: 34, iconSize: 17, tooltip: L10n.t('refresh'), onTap: () => _load(withSnapshot: true)),
              const SizedBox(width: 6),
              NovaIconButton(icon: Icons.create_new_folder_rounded, size: 34, iconSize: 17, tooltip: L10n.t('newFolder'), onTap: _newFolder),
              const SizedBox(width: 6),
              NovaIconButton(icon: Icons.upload_rounded, size: 34, iconSize: 17, filled: true, tooltip: L10n.t('uploadFile'), onTap: _upload),
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
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(NovaSpace.page), child: SkeletonList(count: 6, cardHeight: 54))
              : _error != null
                  ? ErrorState(message: _error!, onRetry: () => _load(withSnapshot: true))
                  : manifest == null || children.isEmpty
                      ? EmptyState(
                          title: L10n.t('filesEmptyTitle'),
                          body: L10n.t('filesEmptyBody'),
                          icon: Icons.folder_open_rounded,
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
