import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

const Set<String> _textExtensions = <String>{
  'txt', 'properties', 'yml', 'yaml', 'json', 'toml', 'cfg', 'conf', 'ini', 'log',
  'md', 'sh', 'bat', 'xml', 'html', 'css', 'js', 'ts', 'py', 'java', 'kt', 'dart',
  'csv', 'mcmeta', 'snbt', 'list', 'env', 'gitignore',
};

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key, required this.active, required this.onPickServer});

  final bool active;
  final VoidCallback onPickServer;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final ServerConfig? server = state.selected;
    if (server == null) {
      return SafeArea(
        bottom: false,
        child: EmptyState(
          title: L10n.t('noServerSelected'),
          body: L10n.t('emptyFilesTitle'),
          icon: Icons.folder_copy_rounded,
          actionLabel: L10n.t('homeServerSwitcher'),
          onAction: onPickServer,
          artAsset: 'assets/images/art_island.jpg',
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: FileBrowser(config: server, active: active),
    );
  }
}

class FileBrowser extends StatefulWidget {
  const FileBrowser({
    super.key,
    required this.config,
    this.active = true,
    this.embedded = false,
  });

  final ServerConfig config;
  final bool active;
  final bool embedded;

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _newName = TextEditingController();

  String _path = '';
  List<DirEntry> _entries = <DirEntry>[];
  bool _loading = true;
  String? _error;
  String _sort = 'name';
  String _branch = 'main';
  String? _busyPath;
  DateTime? _loadedAt;
  final Map<String, DateTime?> _dates = <String, DateTime?>{};
  bool _loadingDates = false;

  @override
  void initState() {
    super.initState();
    // The browser is rooted at the server data folder. Repository files can
    // never be listed, opened or written through this screen.
    _path = widget.config.serverRoot;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  String get _root => widget.config.serverRoot;

  bool _insideRoot(String path) => path == _root || path.startsWith('$_root/');

  @override
  void didUpdateWidget(FileBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      final DateTime? at = _loadedAt;
      if (at == null || DateTime.now().difference(at).inSeconds > 20) _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final AppState state = AppScope.read(context);
    try {
      final GhRepo repo = await state.api.getRepo(widget.config.repoOwner, widget.config.repoName);
      _branch = repo.defaultBranch.isEmpty ? 'main' : repo.defaultBranch;
    } catch (_) {
      _branch = 'main';
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<DirEntry> entries = await state.api.listDir(widget.config.repoOwner, widget.config.repoName, _path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadedAt = DateTime.now();
        _dates.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDatesIfNeeded() async {
    if (_loadingDates) return;
    final List<DirEntry> missing = _entries.where((DirEntry e) => !_dates.containsKey(e.path)).toList();
    if (missing.isEmpty) return;
    _loadingDates = true;
    final AppState state = AppScope.read(context);
    for (final DirEntry entry in missing) {
      final DateTime? date = await state.api.lastCommitDate(
        widget.config.repoOwner,
        widget.config.repoName,
        entry.path,
        branch: _branch,
      );
      if (!mounted) return;
      _dates[entry.path] = date;
    }
    if (mounted) {
      setState(() => _loadingDates = false);
    } else {
      _loadingDates = false;
    }
  }

  void _navigate(String path) {
    if (!_insideRoot(path)) {
      showNovaToast(context, L10n.t('pathOutsideRoot'), kind: ToastKind.error);
      return;
    }
    setState(() => _path = path);
    _load();
  }

  List<DirEntry> get _visible {
    final String q = _search.text.trim().toLowerCase();
    final List<DirEntry> out = _entries.where((DirEntry e) => q.isEmpty || e.name.toLowerCase().contains(q)).toList();
    out.sort((DirEntry a, DirEntry b) {
      if (_sort == 'size') return b.size.compareTo(a.size);
      if (_sort == 'date') {
        final DateTime? da = _dates[a.path];
        final DateTime? db = _dates[b.path];
        if (da == null && db == null) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      }
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  List<String> get _breadcrumbs {
    if (_path == _root) return <String>[];
    final String relative = _path.substring((_root.length + 1).clamp(0, _path.length));
    return relative.isEmpty ? <String>[] : relative.split('/');
  }

  String _pathUpTo(int index) => '$_root/${_breadcrumbs.take(index + 1).join('/')}';

  String _iconFor(String name) {
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'json':
      case 'yml':
      case 'yaml':
      case 'properties':
      case 'toml':
        return 'config';
      case 'jar':
        return 'jar';
      case 'zip':
      case 'gz':
      case 'tar':
        return 'zip';
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
        return 'image';
      case 'log':
      case 'txt':
        return 'text';
      default:
        return 'file';
    }
  }

  _FileStyle _styleFor(DirEntry entry) {
    final p = context.nova;
    if (entry.isDir) return _FileStyle(Icons.folder_rounded, p.warning);
    switch (_iconFor(entry.name)) {
      case 'config':
        return _FileStyle(Icons.tune_rounded, p.cyan);
      case 'jar':
        return _FileStyle(Icons.extension_rounded, p.violet);
      case 'zip':
        return _FileStyle(Icons.archive_rounded, p.warning);
      case 'image':
        return _FileStyle(Icons.image_rounded, p.successBright);
      case 'text':
        return _FileStyle(Icons.description_rounded, p.primaryBright);
      default:
        return _FileStyle(Icons.insert_drive_file_rounded, p.textMuted);
    }
  }

  bool _isText(DirEntry entry) {
    final int dot = entry.name.lastIndexOf('.');
    final String ext = dot >= 0 ? entry.name.substring(dot + 1).toLowerCase() : '';
    if (_textExtensions.contains(ext)) return true;
    if (entry.name == 'eula.txt' || entry.name == 'server.properties') return true;
    return false;
  }

  Future<void> _open(DirEntry entry) async {
    if (entry.isDir) {
      _navigate(entry.path);
      return;
    }
    if (_isText(entry) && entry.size <= 900000) {
      _edit(entry);
      return;
    }
    await _openExternal(entry);
  }

  Future<void> _openExternal(DirEntry entry) async {
    final String url = entry.downloadUrl ?? 'https://github.com/${widget.config.repoFull}/blob/$_branch/${entry.path}';
    final bool ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showNovaToast(context, L10n.t('errorGeneric'), kind: ToastKind.error);
    }
  }

  Future<void> _edit(DirEntry entry) async {
    final AppState state = AppScope.read(context);
    setState(() => _busyPath = entry.path);
    try {
      final String text = await state.api.getFileText(widget.config.repoOwner, widget.config.repoName, entry.path);
      if (!mounted) return;
      final String? next = await Navigator.of(context).push<String>(MaterialPageRoute<String>(
        builder: (_) => FileEditorScreen(
          title: entry.name,
          path: entry.path,
          initialText: text,
        ),
      ));
      if (next == null || !mounted) return;
      final String? sha = await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, entry.path);
      await state.api.putText(
        widget.config.repoOwner,
        widget.config.repoName,
        entry.path,
        next,
        'nova: edit ${entry.name}',
        sha: sha,
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(context, L10n.t('savedFile'), kind: ToastKind.success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  Future<void> _delete(DirEntry entry) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('deleteFileTitle'),
      body: entry.isDir ? L10n.t('deleteFolderNote') : L10n.f('deleteFileBody', <String, String>{'name': entry.name}),
      confirmLabel: L10n.t('delete'),
      danger: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyPath = entry.path);
    try {
      final AppState state = AppScope.read(context);
      await state.api.deleteFile(
        widget.config.repoOwner,
        widget.config.repoName,
        entry.path,
        entry.sha,
        'nova: delete ${entry.path}',
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(context, L10n.t('backupDeleted'), kind: ToastKind.success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
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
    if (bytes.length > 30 * 1024 * 1024) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    final String target = '$_path/${file.name}';
    setState(() => _busyPath = target);
    try {
      final AppState state = AppScope.read(context);
      final String? sha = await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, target);
      await state.api.putFile(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        bytes,
        'nova: upload ${file.name}',
        sha: sha,
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(context, L10n.t('uploadedFile'), kind: ToastKind.success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  Future<void> _create(bool folder) async {
    _newName.clear();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final p = ctx.nova;
        return AlertDialog(
          backgroundColor: p.cardHigh,
          shape: RoundedRectangleBorder(borderRadius: NovaRadii.rLg),
          title: Text(folder ? L10n.t('newFolder') : L10n.t('newFile'), style: NovaTextStyles.title(p.text)),
          content: NovaField(
            controller: _newName,
            autofocus: true,
            hint: folder ? 'new-folder' : 'notes.txt',
            prefixIcon: folder ? Icons.create_new_folder_rounded : Icons.note_add_rounded,
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(L10n.t('cancel'))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(L10n.t('save'))),
          ],
        );
      },
    );
    final String name = _newName.text.trim();
    if (ok != true || name.isEmpty || !mounted) return;
    final String target = folder ? '$_path/$name/.gitkeep' : '$_path/$name';
    setState(() => _busyPath = target);
    try {
      final AppState state = AppScope.read(context);
      await state.api.putText(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        folder ? '' : '',
        folder ? 'nova: new folder' : 'nova: new file',
        sha: await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, target),
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(context, L10n.t('savedFile'), kind: ToastKind.success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  Future<void> _showActions(DirEntry entry) async {
    final p = context.nova;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: p.stroke)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 38, height: 4, decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill)),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Icon(_styleFor(entry).icon, color: _styleFor(entry).color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text)),
                        Text(
                          entry.isDir ? L10n.t('fileType') : Fmt.bytes(entry.size),
                          style: NovaTextStyles.small(p.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SoftDivider(),
              if (entry.isFile)
                _ActionTile(
                  icon: Icons.edit_note_rounded,
                  label: L10n.t('fileEdit'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _edit(entry);
                  },
                ),
              if (entry.isFile)
                _ActionTile(
                  icon: Icons.download_rounded,
                  label: L10n.t('download'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openExternal(entry);
                  },
                ),
              _ActionTile(
                icon: Icons.content_copy_rounded,
                label: L10n.t('copy'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: entry.path));
                  showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
                },
              ),
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: L10n.t('delete'),
                danger: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _delete(entry);
                },
              ),
              const SizedBox(height: 8),
              NovaButton(label: L10n.t('close'), variant: NovaButtonVariant.ghost, onPressed: () => Navigator.of(ctx).pop()),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final List<DirEntry> visible = _visible;
    if (_sort == 'date' && !_loadingDates) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDatesIfNeeded());
    }

    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(NovaSpace.page, widget.embedded ? 4 : 10, NovaSpace.page, widget.embedded ? 24 : 130),
        children: <Widget>[
          if (!widget.embedded)
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(L10n.t('filesTitle'), style: NovaTextStyles.display(26, p.text)),
                      const SizedBox(height: 2),
                      Text(widget.config.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.small(p.textMuted)),
                    ],
                  ),
                ),
                NovaIconButton(
                  icon: Icons.create_new_folder_rounded,
                  tooltip: L10n.t('newFolder'),
                  onTap: () => _create(true),
                ),
                const SizedBox(width: 6),
                NovaIconButton(
                  icon: Icons.note_add_rounded,
                  tooltip: L10n.t('newFile'),
                  onTap: () => _create(false),
                ),
                const SizedBox(width: 6),
                NovaIconButton(
                  icon: Icons.upload_rounded,
                  filled: true,
                  tooltip: L10n.t('uploadFile'),
                  onTap: _upload,
                ),
              ],
            ),
          if (widget.embedded)
            Row(
              children: <Widget>[
                Expanded(child: Text(L10n.t('filesTitle'), style: NovaTextStyles.title(p.text))),
                NovaIconButton(icon: Icons.create_new_folder_rounded, size: 34, iconSize: 17, tooltip: L10n.t('newFolder'), onTap: () => _create(true)),
                const SizedBox(width: 4),
                NovaIconButton(icon: Icons.upload_rounded, size: 34, iconSize: 17, filled: true, tooltip: L10n.t('uploadFile'), onTap: _upload),
                const SizedBox(width: 4),
                NovaIconButton(icon: Icons.refresh_rounded, size: 34, iconSize: 17, onTap: _load, tooltip: L10n.t('refresh')),
              ],
            ),
          const SizedBox(height: 10),
          _Breadcrumbs(
            repo: widget.config.repoName,
            segments: _breadcrumbs,
            onRoot: () => _navigate(widget.config.serverRoot),
            onSegment: (int i) => _navigate(_pathUpTo(i)),
          ),
          const SizedBox(height: 10),
          NovaSearchField(
            controller: _search,
            hint: L10n.t('searchFiles'),
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() => _search.clear()),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: 12, color: p.textDim),
              const SizedBox(width: 6),
              Expanded(child: Text(L10n.t('serverDataOnly'), style: NovaTextStyles.caption(p.textDim))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              NovaChip(label: L10n.t('sortName'), selected: _sort == 'name', onTap: () => setState(() => _sort = 'name')),
              const SizedBox(width: 6),
              NovaChip(label: L10n.t('fileSize'), selected: _sort == 'size', onTap: () => setState(() => _sort = 'size')),
              const SizedBox(width: 6),
              NovaChip(label: L10n.t('fileModified'), selected: _sort == 'date', onTap: () => setState(() => _sort = 'date')),
              const Spacer(),
              if (_loadingDates)
                const SizedBox(width: 14, height: 14, child: NovaLoader(size: 14, stroke: 1.6))
              else
                Text('${visible.length}', style: NovaTextStyles.caption(p.textDim)),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading && _entries.isEmpty)
            const SkeletonList(count: 6, cardHeight: 56)
          else if (_error != null)
            ErrorState(message: _error!, onRetry: _load, compact: true)
          else if (visible.isEmpty)
            EmptyState(
              title: _search.text.isEmpty ? L10n.t('folderEmpty') : L10n.t('noResults'),
              body: L10n.t('filesSubtitle'),
              icon: Icons.folder_open_rounded,
              compact: true,
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: NovaGradients.card(p),
                borderRadius: NovaRadii.rLg,
                border: Border.all(color: p.stroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: List<Widget>.generate(visible.length, (int i) {
                  final DirEntry entry = visible[i];
                  final _FileStyle style = _styleFor(entry);
                  final IconData icon = style.icon;
                  final Color color = style.color;
                  final DateTime? date = _dates[entry.path];
                  final bool busy = _busyPath == entry.path;
                  return Column(
                    children: <Widget>[
                      if (i > 0) SoftDivider(),
                      InkWell(
                        onTap: () => _open(entry),
                        onLongPress: () => _showActions(entry),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: NovaRadii.rXs,
                                  border: Border.all(color: color.withValues(alpha: 0.24)),
                                ),
                                child: Icon(icon, size: 17, color: color),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      entry.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: NovaTextStyles.bodyStrong(p.text).copyWith(fontSize: 13.5),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      entry.isDir ? L10n.t('folderLabel') : Fmt.bytes(entry.size),
                                      style: NovaTextStyles.caption(p.textDim),
                                    ),
                                  ],
                                ),
                              ),
                              if (date != null)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 6),
                                  child: Text(Fmt.relative(date), style: NovaTextStyles.caption(p.textDim)),
                                ),
                              if (busy)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: SizedBox(width: 15, height: 15, child: NovaLoader(size: 15, stroke: 1.8)),
                                )
                              else
                                NovaIconButton(
                                  icon: Icons.more_vert_rounded,
                                  size: 32,
                                  iconSize: 16,
                                  onTap: () => _showActions(entry),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(Icons.lock_rounded, size: 12, color: p.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${L10n.t('pathBreadcrumb')}: /${_breadcrumbs.join('/')}',
                  style: NovaTextStyles.caption(p.textDim),
                ),
              ),
              Text(_branch, style: NovaTextStyles.mono(10, p.textDim)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileStyle {
  const _FileStyle(this.icon, this.color);

  final IconData icon;
  final Color color;
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.repo, required this.segments, required this.onRoot, required this.onSegment});

  final String repo;
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
              Icon(Icons.home_rounded, size: 13, color: segments.isEmpty ? p.primaryBright : p.textMuted),
              const SizedBox(width: 5),
              Text(repo, style: NovaTextStyles.caption(segments.isEmpty ? p.primaryBright : p.textMuted)),
            ],
          ),
        ),
      ),
    ];
    for (int i = 0; i < segments.length; i++) {
      final bool last = i == segments.length - 1;
      children.add(Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Icon(Icons.chevron_right_rounded, size: 14, color: p.textDim),
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
          child: Text(
            segments[i],
            style: NovaTextStyles.caption(last ? p.primaryBright : p.textMuted),
          ),
        ),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: Directionality.of(context) == TextDirection.rtl,
      child: Row(children: children),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color color = danger ? p.danger : p.text;
    return InkWell(
      onTap: onTap,
      borderRadius: NovaRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: danger ? p.danger : p.primaryBright),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: NovaTextStyles.body(color))),
          ],
        ),
      ),
    );
  }
}

class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({super.key, required this.title, required this.path, required this.initialText});

  final String title;
  final String path;
  final String initialText;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: p.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text)),
            Text(widget.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.caption(p.textDim)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text(L10n.t('save'), style: NovaTextStyles.smallStrong(p.primaryBright)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_dirty)
              Container(
                width: double.infinity,
                color: p.warning.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: Text(L10n.t('fileEdit'), style: NovaTextStyles.caption(p.warning)),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(fontFamily: 'PlexMono', fontSize: 12, height: 1.5, color: p.text),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintText: L10n.t('fileEdit'),
                  hintStyle: TextStyle(fontFamily: 'PlexMono', fontSize: 12, color: p.textDim),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: p.cardSoft,
                border: Border(top: BorderSide(color: p.stroke)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.code_rounded, size: 13, color: p.textDim),
                  const SizedBox(width: 6),
                  Text('${_controller.text.length}', style: NovaTextStyles.mono(10, p.textDim)),
                  const Spacer(),
                  Text('NOVA CRAFT', style: NovaTextStyles.caption(p.textDim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
