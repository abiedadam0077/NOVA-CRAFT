import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/cancellation.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/modrinth_api.dart';
import '../../core/modrinth_installer.dart';
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

class ModsView extends StatefulWidget {
  const ModsView({super.key, required this.config, this.active = true});

  final ServerConfig config;
  final bool active;

  @override
  State<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends State<ModsView> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  int _tab = 0;
  bool _browse = true;
  String? _loader;
  List<ModrinthProject> _results = <ModrinthProject>[];
  bool _searching = false;
  String? _searchError;
  int _searchGeneration = 0;
  List<DirEntry> _installed = <DirEntry>[];
  ServerRuntime? _runtime;
  int _installedGeneration = 0;
  bool _loadingInstalled = false;
  String? _installedError;
  String _branch = 'main';
  String? _busyId;
  String? _installProjectId;
  CancellationToken? _installCancellation;
  bool _downloadStarted = false;
  bool _downloadComplete = false;
  int _downloadReceivedBytes = 0;
  int _downloadTotalBytes = 0;
  DateTime? _lastDownloadProgressPaint;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _tab = !widget.config.supportsMods && widget.config.supportsPlugins ? 1 : 0;
    _loader = _defaultLoader(_tab);
    _branch = widget.config.defaultBranch.isEmpty ? 'main' : widget.config.defaultBranch;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadBranch();
      if (!mounted) return;
      await _refreshInstalled();
      await _search();
    });
  }

  @override
  void didUpdateWidget(ModsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool serverChanged = oldWidget.config.id != widget.config.id ||
        oldWidget.config.repoOwner != widget.config.repoOwner ||
        oldWidget.config.repoName != widget.config.repoName ||
        oldWidget.config.serverRoot != widget.config.serverRoot ||
        oldWidget.config.defaultBranch != widget.config.defaultBranch ||
        oldWidget.config.edition != widget.config.edition ||
        oldWidget.config.software != widget.config.software ||
        oldWidget.config.mcVersion != widget.config.mcVersion;
    if (serverChanged) {
      _installCancellation?.cancel();
      _installCancellation = null;
      _installProjectId = null;
      _busyId = null;
      _downloadStarted = false;
      _downloadComplete = false;
      _downloadReceivedBytes = 0;
      _downloadTotalBytes = 0;
      _lastDownloadProgressPaint = null;
      _debounce?.cancel();
      ++_searchGeneration;
      ++_installedGeneration;
      _tab = !widget.config.supportsMods && widget.config.supportsPlugins ? 1 : 0;
      _loader = _defaultLoader(_tab);
      _branch = widget.config.defaultBranch.isEmpty ? 'main' : widget.config.defaultBranch;
      _browse = true;
      _results = <ModrinthProject>[];
      _installed = <DirEntry>[];
      _runtime = null;
      _searching = false;
      _searchError = null;
      _installedError = null;
      _loadedOnce = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _loadBranch();
        if (!mounted) return;
        await _refreshInstalled();
        await _search();
      });
      return;
    }
    if (!oldWidget.active && widget.active && _loadedOnce) {
      _refreshInstalled();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _installCancellation?.cancel();
    _query.dispose();
    super.dispose();
  }

  String _defaultLoader(int tab) {
    if (tab == 0) return 'fabric';
    switch (widget.config.software) {
      case 'PURPUR':
        return 'purpur';
      case 'SPIGOT':
        return 'spigot';
      default:
        return 'paper';
    }
  }

  String get _folder =>
      modrinthInstallFolder(plugins: _tab == 1, serverRoot: widget.config.serverRoot);

  String get _projectType => _tab == 0 ? 'mod' : 'plugin';

  bool get _supported => widget.config.isJava && (_tab == 0 ? widget.config.supportsMods : widget.config.supportsPlugins);

  Future<void> _loadBranch() async {
    final ServerConfig config = widget.config;
    String branch = config.defaultBranch.isEmpty ? 'main' : config.defaultBranch;
    try {
      final AppState state = AppScope.read(context);
      final GhRepo repo = await state.api.getRepo(config.repoOwner, config.repoName);
      if (repo.defaultBranch.isNotEmpty) branch = repo.defaultBranch;
    } catch (_) {
      // Use this server's saved branch if the repository cannot be queried.
    }
    if (!mounted ||
        config.id != widget.config.id ||
        config.repoFull != widget.config.repoFull ||
        config.defaultBranch != widget.config.defaultBranch) {
      return;
    }
    _branch = branch;
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    ++_searchGeneration;
    setState(() {
      _searchError = null;
      _searching = false;
    });
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    if (!_supported) return;
    final int generation = ++_searchGeneration;
    final String query = _query.text.trim();
    final String projectType = _projectType;
    final String? loader = _loader;
    final String? gameVersion = widget.config.mcVersion.isEmpty ? null : widget.config.mcVersion;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<ModrinthProject> hits = await state.modrinth.search(
        query: query,
        projectType: projectType,
        loader: loader,
        gameVersion: gameVersion,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = hits;
        _loadedOnce = true;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searchError = Fmt.error(error));
    } finally {
      if (mounted && generation == _searchGeneration) setState(() => _searching = false);
    }
  }

  Future<ServerRuntime?> _loadRunnerRuntime(AppState state) async {
    try {
      final String text = await state.api.getFileText(
        widget.config.repoOwner,
        widget.config.repoName,
        Provisioner.statusPath,
        branch: _branch,
      );
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);
      if (json['serverId']?.toString() != widget.config.id) return null;
      return ServerRuntime.fromJson(json);
    } catch (_) {
      // An old runner or a missing status file is unknown, never proof of install.
      return null;
    }
  }

  Future<void> _refreshInstalled() async {
    if (!_supported) return;
    final int generation = ++_installedGeneration;
    setState(() {
      _loadingInstalled = true;
      _installedError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      unawaited(_loadRunnerRuntime(state).then((ServerRuntime? runtime) {
        if (!mounted || generation != _installedGeneration) return;
        setState(() => _runtime = runtime);
      }));
      final List<DirEntry> entries = await state.api.listDir(
        widget.config.repoOwner,
        widget.config.repoName,
        _folder,
        branch: _branch,
      );
      if (!mounted || generation != _installedGeneration) return;
      setState(() => _installed = entries.where((DirEntry e) => e.name.toLowerCase().endsWith('.jar')).toList());
    } catch (error) {
      if (!mounted || generation != _installedGeneration) return;
      setState(() => _installedError = Fmt.error(error));
    } finally {
      if (mounted && generation == _installedGeneration) setState(() => _loadingInstalled = false);
    }
  }

  String _runtimePath(DirEntry entry) {
    final String prefix = '${widget.config.serverRoot}/';
    return entry.path.startsWith(prefix) ? entry.path.substring(prefix.length) : entry.path;
  }

  bool _isSyncedToRunner(DirEntry entry) {
    final ServerRuntime? runtime = _runtime;
    if (runtime == null || runtime.jarSyncStatus != 'synced') return false;
    return runtime.managedJarShas[_runtimePath(entry)] == entry.sha.toLowerCase();
  }

  String _syncLabel(DirEntry entry) {
    if (_isSyncedToRunner(entry)) return 'modSyncedRunner';
    if (_runtime?.jarSyncStatus == 'failed') return 'modSyncFailed';
    if (_runtime?.jarSyncStatus == 'synced') return 'modSyncPending';
    return 'modSyncUnknown';
  }

  DirEntry? _installedEntry(ModrinthProject project) {
    final String slug = project.slug.toLowerCase();
    for (final DirEntry entry in _installed) {
      final String name = entry.name.toLowerCase();
      if (name.contains(slug) || name.contains(project.id.toLowerCase())) return entry;
    }
    return null;
  }

  List<String> get _allowedLoaders =>
      modrinthAllowedLoaders(plugins: _tab == 1, serverLoader: _loader);

  /// Human-readable reason a concrete version cannot be installed here.
  String _rejectionReason(ModrinthVersion version) {
    final bool loaderOk = modrinthLoaderMatches(version, _allowedLoaders);
    final bool versionOk = modrinthVersionMatches(version, widget.config.mcVersion);
    if (!loaderOk) {
      return L10n.f('modRejectLoaders', <String, String>{
        'loaders': version.loaders.isEmpty ? '—' : version.loaders.join(', '),
        'current': _loader ?? '',
      });
    }
    if (!versionOk) {
      return L10n.f('modRejectVersions', <String, String>{
        'versions': version.gameVersions.take(5).join(', '),
        'current': widget.config.mcVersion,
      });
    }
    return L10n.t('modIncompatibleShort');
  }

  bool _compatible(ModrinthVersion version) => modrinthCompatible(
        version,
        allowedLoaders: _allowedLoaders,
        gameVersion: widget.config.mcVersion,
      );

  Future<void> _install(ModrinthProject project) async {
    if (_busyId != null) return;
    final CancellationToken cancellation = CancellationToken();
    setState(() {
      _busyId = project.id;
      _installProjectId = project.id;
      _installCancellation = cancellation;
      _downloadStarted = false;
      _downloadComplete = false;
      _downloadReceivedBytes = 0;
      _downloadTotalBytes = 0;
      _lastDownloadProgressPaint = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<ModrinthVersion> versions = _tab == 1
          ? await state.installer.requestVersions(
              project,
              server: widget.config,
              cancellation: cancellation,
            )
          : await state.modrinth.versions(project.id, cancellation: cancellation);
      cancellation.throwIfCancelled();
      final List<ModrinthVersion> compatible = versions.where(_compatible).toList();
      final List<ModrinthVersion> rejected = versions.where((ModrinthVersion v) => !_compatible(v)).toList();
      if (!mounted) return;
      if (compatible.isEmpty) {
        // Never install a mismatched jar: show exactly why every version was
        // rejected instead of a generic toast.
        await _showNoCompatible(project, versions);
        return;
      }
      final ModrinthVersion? choice = await _pickVersion(project, compatible, rejected);
      if (choice == null || !mounted) return;
      cancellation.throwIfCancelled();

      if (_tab == 1) {
        // The plugin installer re-reads server.json before downloading, then
        // verifies the exact size and Git blob hash inside the plugins folder.
        await state.installer.install(
          project: project,
          version: choice,
          expectedServer: widget.config,
          branch: _branch,
          cancellation: cancellation,
          onDownloadProgress: _onDownloadProgress,
        );
      } else {
        // Keep the existing mods installation behavior; the shared download
        // API now additionally validates Modrinth's advertised size and hash.
        await _installModVersion(
          state,
          project,
          choice,
          cancellation,
          onDownloadProgress: _onDownloadProgress,
        );
      }
      if (!mounted) return;
      showNovaToast(
        context,
        L10n.f('modQueuedSuccess', <String, String>{'name': project.title}),
        kind: ToastKind.success,
      );
      await _refreshInstalled();
      if (!mounted) return;
      setState(() => _browse = false);
    } on OperationCancelledException {
      if (mounted) showNovaToast(context, L10n.t('modInstallCancelled'), kind: ToastKind.info);
    } on ModrinthInstallException catch (error) {
      if (!mounted) return;
      final String message = error.cause is ModrinthDownloadLimitException ? L10n.t('modDownloadTooLarge') : error.message;
      final String details = '${L10n.t(_installStageKey(error.stage))}: $message';
      showNovaToast(context, L10n.f('modInstallFailed', <String, String>{'error': details}), kind: ToastKind.error);
    } catch (error) {
      if (!mounted) return;
      final String message = error is ModrinthDownloadLimitException ? L10n.t('modDownloadTooLarge') : Fmt.error(error);
      showNovaToast(
        context,
        L10n.f('modInstallFailed', <String, String>{'error': message}),
        kind: ToastKind.error,
      );
    } finally {
      if (mounted && identical(_installCancellation, cancellation)) {
        setState(() {
          _busyId = null;
          _installProjectId = null;
          _installCancellation = null;
          _downloadStarted = false;
          _downloadComplete = false;
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = 0;
          _lastDownloadProgressPaint = null;
        });
      }
    }
  }

  Future<void> _installModVersion(
    AppState state,
    ModrinthProject project,
    ModrinthVersion version,
    CancellationToken cancellation, {
    ModrinthDownloadProgress? onDownloadProgress,
  }) async {
    final ModrinthVersionFile? file = version.primaryFile;
    if (file == null ||
        !file.filename.toLowerCase().endsWith('.jar') ||
        file.filename.contains('/') ||
        file.filename.contains('\\')) {
      throw const ModrinthInstallException(
        ModrinthInstallStage.validation,
        'Modrinth did not provide one safe JAR file for this version.',
      );
    }
    final Uint8List bytes = await state.modrinth.download(
      file,
      cancellation: cancellation,
      onProgress: onDownloadProgress,
    );
    cancellation.throwIfCancelled();
    final String target = '$_folder/${file.filename}';
    final String? existingSha;
    try {
      existingSha = await state.api.fileSha(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        branch: _branch,
        abortTrigger: cancellation.whenCancelled,
      );
    } catch (error) {
      if (cancellation.isCancelled) throw const OperationCancelledException();
      rethrow;
    }
    try {
      await state.api.putFile(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        bytes,
        'nova: install ${project.slug} ${version.versionNumber}',
        sha: existingSha,
        branch: _branch,
        abortTrigger: cancellation.whenCancelled,
      );
    } catch (error) {
      if (cancellation.isCancelled) throw const OperationCancelledException();
      rethrow;
    }
    final DirEntry? previous = _installedEntry(project);
    if (previous != null && previous.path != target && previous.name != file.filename) {
      try {
        await state.api.deleteFile(
          widget.config.repoOwner,
          widget.config.repoName,
          previous.path,
          previous.sha,
          'nova: replace ${previous.name}',
          branch: _branch,
        );
      } catch (_) {
        // Preserve the existing best-effort replacement behavior for mods.
      }
    }
  }

  String _installStageKey(ModrinthInstallStage stage) {
    switch (stage) {
      case ModrinthInstallStage.versionLookup:
        return 'modInstallStageVersions';
      case ModrinthInstallStage.configuration:
        return 'modInstallStageConfig';
      case ModrinthInstallStage.compatibility:
        return 'modInstallStageCompatibility';
      case ModrinthInstallStage.download:
        return 'modInstallStageDownload';
      case ModrinthInstallStage.validation:
        return 'modInstallStageValidation';
      case ModrinthInstallStage.upload:
        return 'modInstallStageUpload';
      case ModrinthInstallStage.repositoryVerification:
        return 'modInstallStageVerify';
    }
  }

  void _cancelInstall() {
    final CancellationToken? cancellation = _installCancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    cancellation.cancel();
    setState(() {});
  }

  void _onDownloadProgress(int receivedBytes, int totalBytes, bool complete) {
    if (!mounted || _installCancellation?.isCancelled == true) return;
    final DateTime now = DateTime.now();
    final DateTime? lastPaint = _lastDownloadProgressPaint;
    if (_downloadStarted && !complete && receivedBytes != 0 && lastPaint != null && now.difference(lastPaint).inMilliseconds < 100) {
      return;
    }
    _lastDownloadProgressPaint = now;
    setState(() {
      _downloadStarted = true;
      _downloadComplete = complete;
      _downloadReceivedBytes = receivedBytes;
      _downloadTotalBytes = totalBytes;
    });
  }

  Widget _downloadProgressPanel() {
    final p = context.nova;
    final double? progress = _downloadComplete
        ? 1
        : (_downloadTotalBytes > 0 ? _downloadReceivedBytes / _downloadTotalBytes : null);
    final String label;
    if (_downloadComplete) {
      label = L10n.f('modDownloadComplete', <String, String>{'size': Fmt.bytes(_downloadReceivedBytes)});
    } else if (_downloadTotalBytes > 0) {
      final int percent = (_downloadReceivedBytes * 100 ~/ _downloadTotalBytes).clamp(0, 100).toInt();
      label = L10n.f('modDownloadProgress', <String, String>{
        'received': Fmt.bytes(_downloadReceivedBytes),
        'total': Fmt.bytes(_downloadTotalBytes),
        'percent': '$percent',
      });
    } else {
      label = L10n.f('modDownloadProgressUnknown', <String, String>{'received': Fmt.bytes(_downloadReceivedBytes)});
    }
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: p.cardSoft,
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: p.primaryBright.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_downloadComplete ? Icons.download_done_rounded : Icons.download_rounded, size: 16, color: p.primaryBright),
              const SizedBox(width: 7),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.caption(p.text))),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: p.stroke,
              valueColor: AlwaysStoppedAnimation<Color>(p.primaryBright),
            ),
          ),
        ],
      ),
    );
  }

  /// Lists every incompatible version with its concrete rejection reason.
  Future<void> _showNoCompatible(ModrinthProject project, List<ModrinthVersion> versions) {
    final p = context.nova;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.78),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: p.stroke)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill))),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Icon(Icons.block_rounded, size: 20, color: p.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(L10n.t('modNoCompatibleTitle'), style: NovaTextStyles.title(p.text))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                L10n.f('modNoCompatibleBody', <String, String>{
                  'loader': _loader ?? '',
                  'version': widget.config.mcVersion,
                  'count': '${versions.length}',
                }),
                style: NovaTextStyles.small(p.textMuted),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: versions.isEmpty
                    ? Text(L10n.t('modNoVersionsAtAll'), style: NovaTextStyles.small(p.textDim))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: versions.length,
                        separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 7),
                        itemBuilder: (BuildContext c, int i) => _RejectedVersionTile(
                          version: versions[i],
                          reason: _rejectionReason(versions[i]),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              NovaButton(
                label: L10n.t('close'),
                variant: NovaButtonVariant.secondary,
                height: 46,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<ModrinthVersion?> _pickVersion(
    ModrinthProject project,
    List<ModrinthVersion> versions,
    List<ModrinthVersion> rejected,
  ) {
    final p = context.nova;
    return showModalBottomSheet<ModrinthVersion>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.78),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: p.stroke)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill))),
                const SizedBox(height: 14),
                Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text)),
                const SizedBox(height: 3),
                Text(
                  L10n.f('modPickVersionFor', <String, String>{
                    'loader': _loader ?? '',
                    'version': widget.config.mcVersion,
                  }),
                  style: NovaTextStyles.small(p.textDim),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      ...versions.map((ModrinthVersion v) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _VersionTile(
                              version: v,
                              onTap: () => Navigator.of(ctx).pop(v),
                            ),
                          )),
                      if (rejected.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          L10n.f('modIncompatibleVersions', <String, String>{
                            'count': '${rejected.length}',
                            'loader': _loader ?? '',
                            'version': widget.config.mcVersion,
                          }),
                          style: NovaTextStyles.caption(p.textDim),
                        ),
                        const SizedBox(height: 8),
                        ...rejected.take(12).map((ModrinthVersion v) => Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: _RejectedVersionTile(version: v, reason: _rejectionReason(v)),
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _remove(DirEntry entry) async {
    if (_busyId != null) return;
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('modRemoveTitle'),
      body: L10n.f('modRemoveBody', <String, String>{'name': entry.name}),
      confirmLabel: L10n.t('remove'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted || _busyId != null) return;
    setState(() => _busyId = entry.path);
    try {
      final AppState state = AppScope.read(context);
      await state.api.deleteFile(
        widget.config.repoOwner,
        widget.config.repoName,
        entry.path,
        entry.sha,
        'nova: remove ${entry.name}',
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(context, L10n.t('remove'), kind: ToastKind.success);
      await _refreshInstalled();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(L10n.t('navMods'), style: NovaTextStyles.heading(22, p.text)),
                    Text(
                      '${widget.config.softwareLabel} ${widget.config.mcVersion}',
                      style: NovaTextStyles.caption(p.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.config.supportsMods && widget.config.supportsPlugins)
          NovaSegmented(
            labels: <String>[L10n.t('modsTab'), L10n.t('pluginsTab')],
            index: _tab,
            onChanged: (int i) {
              if (_busyId != null) return;
              setState(() {
                _tab = i;
                _loader = _defaultLoader(i);
                _results = <ModrinthProject>[];
                _installed = <DirEntry>[];
                _loadedOnce = false;
                _browse = true;
              });
              _refreshInstalled();
              _search();
            },
            icons: const <IconData>[Icons.extension_rounded, Icons.widgets_rounded],
          )
        else if (widget.config.supportsMods || widget.config.supportsPlugins)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(color: p.cardSoft, borderRadius: NovaRadii.rMd),
            child: Row(
              children: <Widget>[
                Icon(widget.config.supportsMods ? Icons.extension_rounded : Icons.widgets_rounded, color: p.violet, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.config.supportsMods ? L10n.t('modsTab') : L10n.t('pluginsTab'), style: NovaTextStyles.bodyStrong(p.text))),
              ],
            ),
          )
        else
          const SizedBox(),
        const SizedBox(height: 10),
        Expanded(
          child: !_supported
              ? _unsupportedState()
              : _browse
                  ? _browseBody()
                  : _installedBody(),
        ),
      ],
    );
  }

  Widget _unsupportedState() {
    final bool bedrock = widget.config.isBedrock;
    final String body;
    if (bedrock) {
      body = L10n.t('modBedrockBody');
    } else if (_tab == 1) {
      body = L10n.t('pluginsOnly');
    } else {
      body = L10n.t('modsOnly');
    }
    return EmptyState(
      title: bedrock ? L10n.t('modBedrockTitle') : L10n.t('modVanillaTitle'),
      body: body,
      icon: Icons.extension_off_rounded,
      compact: true,
    );
  }

  /// Uploads a local .jar straight into the correct server folder. The file is
  /// never modified or renamed beyond its own name, and it is rejected when the
  /// server type cannot load it.
  Future<void> _uploadJar() async {
    if (!_supported || _busyId != null) return;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jar'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final PlatformFile file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    if (bytes.length > 45 * 1024 * 1024) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    final String target = '$_folder/${file.name}';
    setState(() => _busyId = target);
    try {
      final AppState state = AppScope.read(context);
      await state.api.putFile(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        bytes,
        'nova: upload ${file.name}',
        sha: await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, target),
        branch: _branch,
      );
      if (!mounted) return;
      showNovaToast(
        context,
        L10n.f('modQueuedSuccess', <String, String>{'name': file.name}),
        kind: ToastKind.success,
      );
      await _refreshInstalled();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _browseBody() {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NovaSearchField(
          controller: _query,
          hint: L10n.t('modSearchHint'),
          onChanged: (_) => _onQueryChanged(),
          onClear: () => setState(() {
            _query.clear();
            _search();
          }),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              Pill(
                label: widget.config.mcVersion.isEmpty ? L10n.t('unknown') : widget.config.mcVersion,
                tone: PillTone.primary,
                icon: Icons.sports_esports_rounded,
                dense: true,
              ),
              const SizedBox(width: 6),
              ..._loadersForTab().map((String loader) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: NovaChip(
                      label: Fmt.titleCase(loader),
                      selected: _loader == loader,
                      onTap: () {
                        setState(() => _loader = loader);
                        _search();
                      },
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            NovaChip(
              label: L10n.t('browseTab'),
              selected: _browse,
              onTap: () {},
              icon: Icons.travel_explore_rounded,
            ),
            const SizedBox(width: 6),
            NovaChip(
              label: L10n.f('modRepoFilesCount', <String, String>{'count': '${_installed.length}'}),
              selected: !_browse,
              onTap: () => setState(() => _browse = false),
              icon: Icons.download_done_rounded,
            ),
            const Spacer(),
            if (_searching) const SizedBox(width: 16, height: 16, child: NovaLoader(size: 16, stroke: 2)),
            const SizedBox(width: 6),
            NovaIconButton(
              icon: Icons.upload_file_rounded,
              size: 34,
              iconSize: 17,
              filled: true,
              tooltip: L10n.t('uploadFile'),
              onTap: _uploadJar,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_downloadStarted) ...<Widget>[
          _downloadProgressPanel(),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _searchError != null
              ? ErrorState(message: _searchError!, onRetry: _search, compact: true)
              : _searching && _results.isEmpty
                  ? const SkeletonList(count: 4, cardHeight: 108)
                  : _results.isEmpty
                      ? EmptyState(
                          title: L10n.t('modNoResults'),
                          body: L10n.t('modNoResultsBody'),
                          icon: Icons.search_off_rounded,
                          compact: true,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24, top: 2),
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: _results.length,
                          separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int i) => _projectCard(_results[i]),
                        ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: 12, color: p.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Modrinth · ${L10n.t('modRestartNote')}',
                  style: NovaTextStyles.caption(p.textDim),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _loadersForTab() {
    if (_tab == 0) return <String>['fabric', 'quilt'];
    return <String>['paper', 'purpur', 'spigot'];
  }

  Widget _projectCard(ModrinthProject project) {
    final p = context.nova;
    final DirEntry? installed = _installedEntry(project);
    final bool synced = installed != null && _isSyncedToRunner(installed);
    final bool busy = _busyId == project.id;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rLg,
          border: Border.all(color: synced ? p.success.withValues(alpha: 0.28) : (installed != null ? p.warning.withValues(alpha: 0.24) : p.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: NovaRadii.rXs,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: project.iconUrl.isEmpty
                      ? Container(
                          color: p.cardHigh,
                          child: Icon(Icons.extension_rounded, color: p.violet, size: 20),
                        )
                      : Image.network(
                          project.iconUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext c, Object e, StackTrace? s) => Container(
                            color: p.cardHigh,
                            child: Icon(Icons.extension_rounded, color: p.violet, size: 20),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTextStyles.bodyStrong(p.text).copyWith(fontSize: 14),
                          ),
                        ),
                        if (installed != null)
                          Pill(
                            label: L10n.t(_syncLabel(installed)),
                            tone: synced ? PillTone.success : (_runtime?.jarSyncStatus == 'failed' ? PillTone.danger : PillTone.warning),
                            dense: true,
                            icon: synced ? Icons.check_rounded : Icons.hourglass_empty_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTextStyles.small(p.textMuted).copyWith(fontSize: 11.5),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _Meta(icon: Icons.public_rounded, text: 'Modrinth'),
                        _Meta(icon: Icons.download_rounded, text: Fmt.compactNumber(project.downloads)),
                        if (project.author.isNotEmpty) _Meta(icon: Icons.person_outline_rounded, text: project.author),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              SoftChip(label: _tab == 0 ? L10n.t('modsTab') : L10n.t('pluginsTab'), color: _tab == 0 ? p.violet : p.cyan),
              const SizedBox(width: 6),
              SoftChip(
                label: widget.config.mcVersion.isEmpty ? L10n.t('unknown') : widget.config.mcVersion,
                color: p.primaryBright,
              ),
              const Spacer(),
              if (busy)
                _installProjectId == project.id && _installCancellation != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(width: 22, height: 22, child: NovaLoader(size: 22, stroke: 2)),
                          IconButton(
                            tooltip: L10n.t('cancel'),
                            onPressed: _installCancellation!.isCancelled ? null : _cancelInstall,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                            icon: Icon(
                              _installCancellation!.isCancelled ? Icons.hourglass_top_rounded : Icons.close_rounded,
                              size: 18,
                              color: p.warning,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(width: 22, height: 22, child: NovaLoader(size: 22, stroke: 2))
              else
                NovaButton(
                  label: installed == null ? L10n.t('install') : L10n.t('update'),
                  icon: installed == null ? Icons.download_rounded : Icons.system_update_alt_rounded,
                  size: NovaButtonSize.compact,
                  expand: false,
                  variant: installed == null ? NovaButtonVariant.primary : NovaButtonVariant.secondary,
                  onPressed: () => _install(project),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _installedBody() {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            NovaChip(
              label: L10n.t('browseTab'),
              selected: false,
              onTap: () => setState(() => _browse = true),
              icon: Icons.travel_explore_rounded,
            ),
            const SizedBox(width: 6),
            NovaChip(
              label: L10n.f('modRepoFilesCount', <String, String>{'count': '${_installed.length}'}),
              selected: true,
              onTap: () {},
              icon: Icons.download_done_rounded,
            ),
            const Spacer(),
            if (_installCancellation != null && !_installCancellation!.isCancelled)
              NovaIconButton(
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 16,
                accent: p.warning,
                onTap: _cancelInstall,
                tooltip: L10n.t('cancel'),
              ),
            NovaIconButton(
              icon: Icons.refresh_rounded,
              size: 32,
              iconSize: 16,
              onTap: _refreshInstalled,
              tooltip: L10n.t('refresh'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          L10n.f('modsFolderLabel', <String, String>{'folder': _folder}),
          style: NovaTextStyles.caption(p.textDim),
        ),
        const SizedBox(height: 7),
        InfoBanner(body: L10n.t('modRunnerSyncInfo'), dense: true, color: p.primaryBright),
        if (_downloadStarted) ...<Widget>[
          const SizedBox(height: 8),
          _downloadProgressPanel(),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: _loadingInstalled && _installed.isEmpty
              ? const SkeletonList(count: 4, cardHeight: 62)
              : _installedError != null
                  ? ErrorState(message: _installedError!, onRetry: _refreshInstalled, compact: true)
                  : _installed.isEmpty
                      ? EmptyState(
                          title: L10n.t('installedTab'),
                          body: L10n.t('modUploadHint'),
                          icon: Icons.inbox_rounded,
                          compact: true,
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _installed.length,
                          separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int i) {
                            final DirEntry entry = _installed[i];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: p.cardSoft,
                                borderRadius: NovaRadii.rMd,
                                border: Border.all(color: p.stroke),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: p.violet.withValues(alpha: 0.14),
                                      borderRadius: NovaRadii.rXs,
                                    ),
                                    child: Icon(Icons.extension_rounded, size: 18, color: p.violet),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: NovaTextStyles.smallStrong(p.text),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(Fmt.bytes(entry.size), style: NovaTextStyles.caption(p.textDim)),
                                        const SizedBox(height: 2),
                                        Text(
                                          L10n.t(_syncLabel(entry)),
                                          style: NovaTextStyles.caption(
                                            _isSyncedToRunner(entry) ? p.success : (_runtime?.jarSyncStatus == 'failed' ? p.danger : p.warning),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_busyId == entry.path)
                                    const SizedBox(width: 18, height: 18, child: NovaLoader(size: 18, stroke: 2))
                                  else
                                    NovaIconButton(
                                      icon: Icons.delete_outline_rounded,
                                      size: 34,
                                      iconSize: 18,
                                      accent: p.danger,
                                      onTap: () => _remove(entry),
                                      tooltip: L10n.t('remove'),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
        const SizedBox(height: 8),
        InfoBanner(body: L10n.t('modRestartNote'), dense: true, color: p.warning),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 11, color: p.textDim),
        const SizedBox(width: 3),
        Text(text, style: NovaTextStyles.caption(p.textDim)),
      ],
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.version, required this.onTap});

  final ModrinthVersion version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
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
              decoration: BoxDecoration(
                color: p.violet.withValues(alpha: 0.14),
                borderRadius: NovaRadii.rXs,
              ),
              child: Icon(Icons.extension_rounded, size: 17, color: p.violet),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(version.versionNumber, style: NovaTextStyles.bodyStrong(p.text).copyWith(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '${version.loaders.join(', ')} · ${version.gameVersions.take(3).join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.caption(p.textDim),
                  ),
                ],
              ),
            ),
            Icon(Icons.download_rounded, size: 18, color: p.primaryBright),
          ],
        ),
      ),
    );
  }
}

class _RejectedVersionTile extends StatelessWidget {
  const _RejectedVersionTile({required this.version, required this.reason});

  final ModrinthVersion version;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.06),
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: p.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.block_rounded, size: 15, color: p.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(version.versionNumber, style: NovaTextStyles.bodyStrong(p.textMuted).copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(reason, style: NovaTextStyles.caption(p.warning)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
