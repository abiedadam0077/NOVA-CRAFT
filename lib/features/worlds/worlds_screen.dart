import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/server_file_manifest.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

class _ImportResultLoad {
  const _ImportResultLoad({this.value, this.error});

  final Map<String, dynamic>? value;
  final String? error;
}

class WorldsView extends StatefulWidget {
  const WorldsView({super.key, required this.config, this.active = true, this.activeRun = false, this.showHeader = true});

  final ServerConfig config;
  final bool active;
  final bool activeRun;
  final bool showHeader;

  @override
  State<WorldsView> createState() => _WorldsViewState();
}

class _WorldsViewState extends State<WorldsView> {
  List<ServerWorldInfo> _worlds = <ServerWorldInfo>[];
  List<ReleaseInfo> _backups = <ReleaseInfo>[];
  bool _loading = true;
  String? _error;
  bool _manifestTruncated = false;
  DateTime? _manifestGeneratedAt;
  Map<String, dynamic>? _importResult;
  String? _importResultError;
  int _loadGeneration = 0;
  bool _uploading = false;
  bool _backingUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(WorldsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool serverChanged = oldWidget.config.id != widget.config.id ||
        oldWidget.config.repoFull != widget.config.repoFull ||
        oldWidget.config.dataPath != widget.config.dataPath ||
        oldWidget.config.edition != widget.config.edition;
    final bool runFinished = oldWidget.activeRun && !widget.activeRun;
    if (serverChanged || (!oldWidget.active && widget.active) || runFinished) _load();
  }

  Future<ServerFileManifest> _loadManifest(AppState state) async {
    try {
      final String text = await state.api.getFileText(
        widget.config.repoOwner,
        widget.config.repoName,
        Provisioner.manifestPath,
        branch: widget.config.defaultBranch,
      );
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Server file manifest is malformed');
      return ServerFileManifest.fromJson(Map<String, dynamic>.from(decoded));
    } on ApiException catch (error) {
      if (error.status == 404) return const ServerFileManifest(entries: <ServerFileEntry>[], generatedAt: null);
      rethrow;
    }
  }

  Future<_ImportResultLoad> _loadImportResult(AppState state) async {
    try {
      final String text = await state.api.getFileText(
        widget.config.repoOwner,
        widget.config.repoName,
        Provisioner.importResultPath,
        branch: widget.config.defaultBranch,
      );
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('World import result is malformed');
      return _ImportResultLoad(value: Map<String, dynamic>.from(decoded));
    } on ApiException catch (error) {
      if (error.status == 404) return const _ImportResultLoad();
      return _ImportResultLoad(error: Fmt.error(error));
    } catch (error) {
      return _ImportResultLoad(error: Fmt.error(error));
    }
  }

  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppState state = AppScope.read(context);
      // The runner publishes this manifest from the actual configured dataPath.
      // Reading `server/world` from GitHub Contents only sees committed files,
      // not the world files currently persisted in the runner cache.
      final Future<_ImportResultLoad> importResultFuture = _loadImportResult(state);
      final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
        _loadManifest(state),
        state.api.listReleases(widget.config.repoOwner, widget.config.repoName),
      ]);
      final ServerFileManifest manifest = results[0] as ServerFileManifest;
      final List<ServerWorldInfo> worlds = discoverServerWorlds(manifest, isBedrock: widget.config.isBedrock);
      final List<ReleaseInfo> releases = results[1] as List<ReleaseInfo>;
      final _ImportResultLoad importResult = await importResultFuture;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _worlds = worlds;
        _manifestTruncated = manifest.truncated;
        _manifestGeneratedAt = manifest.generatedAt;
        _importResult = importResult.value;
        _importResultError = importResult.error;
        _backups = releases.where((ReleaseInfo release) => release.isBackupFor(widget.config.id) && release.isVerifiedBackup).toList()
          ..sort((ReleaseInfo a, ReleaseInfo b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _loading = false);
    }
  }

  int get _worldSize => _worlds.fold<int>(0, (int total, ServerWorldInfo world) => total + world.size);

  Future<void> _backupNow() async {
    setState(() => _backingUp = true);
    try {
      final AppState state = AppScope.read(context);
      if (widget.activeRun) {
        await Provisioner.requestBackup(state.api, widget.config);
      } else {
        await Provisioner.snapshot(state.api, widget.config);
      }
      if (!mounted) return;
      showNovaToast(context, L10n.t(widget.activeRun ? 'backupRequestQueued' : 'backupSnapshotQueued'), kind: ToastKind.success);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _upload() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('worldUploadTitle'),
      body: L10n.t('worldUploadBody'),
      confirmLabel: L10n.t('continue'),
      danger: true,
      icon: Icons.upload_file_rounded,
    );
    if (!ok || !mounted) return;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || !mounted) return;
    final PlatformFile file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.zip')) {
      showNovaToast(context, L10n.t('worldUploadInvalid'), kind: ToastKind.error);
      return;
    }
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    if (bytes.length > 40 * 1024 * 1024) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    setState(() => _uploading = true);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.uploadWorldImport(state.api, widget.config, bytes);
      if (!mounted) return;
      showNovaToast(context, L10n.t(widget.activeRun ? 'worldUploadRestartQueued' : 'worldUploadQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadWorld() async {
    final ReleaseInfo? latest = _backups.isEmpty ? null : _backups.first;
    final ReleaseAsset? asset = latest?.backupArchive;
    final Uri? uri = asset?.downloadUrl == null ? null : Uri.tryParse(asset!.downloadUrl!);
    if (uri == null || uri.scheme != 'https' || uri.host.toLowerCase() != 'github.com' || uri.userInfo.isNotEmpty) {
      showNovaToast(context, L10n.t('backupEmptyBody'), kind: ToastKind.warning);
      return;
    }
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showNovaToast(context, L10n.t('errorGeneric'), kind: ToastKind.error);
    }
  }

  String _importErrorMessage(String code) {
    switch (code) {
      case 'missing-level-dat':
        return L10n.t('worldImportErrorLevelFile');
      case 'missing-world-db':
        return L10n.t('worldImportErrorDatabase');
      case 'ambiguous-world-root':
        return L10n.t('worldImportErrorAmbiguous');
      case 'archive-exceeds-size-limit':
      case 'archive-file-exceeds-size-limit':
      case 'archive-entry-size-mismatch':
        return L10n.t('worldImportErrorSize');
      case 'archive-has-too-many-entries':
      case 'duplicate-archive-entry':
      case 'unsafe-archive-entry':
      case 'archive-contains-a-link-or-special-file':
        return L10n.t('worldImportErrorUnsafe');
      case 'safety-backup-failed':
        return L10n.t('worldImportErrorBackup');
      default:
        return code;
    }
  }

  Widget _importResultCard() {
    final p = context.nova;
    final Map<String, dynamic>? result = _importResult;
    return SectionCard(
      title: L10n.t('worldImportResultTitle'),
      icon: Icons.fact_check_outlined,
      child: _importResultError != null
          ? InfoBanner(
              body: _importResultError!,
              color: p.danger,
              icon: Icons.error_outline_rounded,
              actionLabel: L10n.t('retry'),
              onAction: () { _load(); },
              dense: true,
            )
          : result == null
              ? InfoBanner(body: L10n.t('worldImportNoResult'), icon: Icons.hourglass_empty_rounded, dense: true)
              : _buildImportResult(result, p),
    );
  }

  Widget _buildImportResult(Map<String, dynamic> result, NovaPalette p) {
    final bool ok = result['ok'] == true;
    final bool blocked = result['status']?.toString() == 'blocked';
    final String world = result['world']?.toString() ?? '';
    final String edition = result['edition']?.toString() ?? '';
    final String path = result['path']?.toString() ?? '';
    final String error = result['error']?.toString() ?? '';
    final DateTime? processedAt = DateTime.tryParse(result['processedAt']?.toString() ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Pill(
              label: L10n.t(blocked ? 'worldImportBlocked' : (ok ? 'worldImportSuccess' : 'worldImportFailure')),
              tone: blocked ? PillTone.warning : (ok ? PillTone.success : PillTone.danger),
              icon: blocked
                  ? Icons.pause_circle_outline_rounded
                  : (ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded),
              dense: true,
            ),
            if (processedAt != null) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(child: Text(L10n.f('worldImportProcessedAt', <String, String>{'time': Fmt.relative(processedAt)}), style: NovaTextStyles.caption(p.textDim))),
            ],
          ],
        ),
        if (ok) ...<Widget>[
          if (world.isNotEmpty) InfoRow(label: L10n.t('worldImportWorldLabel'), value: world, icon: Icons.public_rounded),
          if (edition.isNotEmpty) InfoRow(label: L10n.t('worldImportEditionLabel'), value: edition, icon: Icons.computer_rounded),
          if (path.isNotEmpty) InfoRow(label: L10n.t('worldImportPathLabel'), value: path, icon: Icons.folder_open_rounded, monospace: true),
        ] else if (error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          InfoBanner(body: _importErrorMessage(error), color: p.danger, icon: Icons.report_gmailerrorred_rounded, dense: true),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool present = _worlds.isNotEmpty;
    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          if (widget.showHeader) ...<Widget>[
            Text(L10n.t('worldsTitle'), style: NovaTextStyles.title(p.text)),
            const SizedBox(height: 2),
            Text(L10n.t('worldsSubtitle'), style: NovaTextStyles.caption(p.textMuted)),
            const SizedBox(height: 3),
          ],
          Text(
            '${widget.config.softwareLabel} · ${widget.config.mcVersion.isEmpty ? L10n.t('unknown') : widget.config.mcVersion} · ${L10n.f('worldDataPath', <String, String>{'path': widget.config.serverRoot})}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NovaTextStyles.caption(p.textDim),
          ),
          if (_manifestGeneratedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                L10n.f('worldManifestUpdated', <String, String>{'time': Fmt.relative(_manifestGeneratedAt!)}),
                style: NovaTextStyles.caption(p.textDim),
              ),
            ),
          const SizedBox(height: 14),
          if (_loading && _worlds.isEmpty)
            const SkeletonList(count: 2, cardHeight: 110)
          else if (_error != null)
            ErrorState(message: _error!, onRetry: _load, compact: true)
          else ...<Widget>[
            Container(
              decoration: BoxDecoration(
                borderRadius: NovaRadii.rXl,
                border: Border.all(color: p.stroke),
                boxShadow: NovaShadows.soft(p),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.asset('assets/images/art_island.jpg', fit: BoxFit.cover),
                        const DecoratedBox(decoration: BoxDecoration(gradient: NovaGradients.heroScrim)),
                        PositionedDirectional(
                          start: 16,
                          top: 14,
                          child: Pill(
                            label: present ? L10n.t('worldSaved') : L10n.t('worldEmpty'),
                            tone: present ? PillTone.success : PillTone.neutral,
                            dense: true,
                            icon: present ? Icons.storage_rounded : Icons.inbox_outlined,
                          ),
                        ),
                        PositionedDirectional(
                          start: 16,
                          bottom: 14,
                          end: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                present
                                    ? (_worlds.length == 1 ? _worlds.single.name : L10n.t('worldSavedFolders'))
                                    : L10n.t('worldEmpty'),
                                style: NovaTextStyles.display(21, Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                present
                                    ? '${L10n.f('worldsFoundCount', <String, String>{'count': '${_worlds.length}'})} · ${Fmt.bytes(_worldSize)}'
                                    : L10n.t('worldEmptyBody'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NovaTextStyles.small(const Color(0xFFB9C7E8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('backupNow'),
                            icon: Icons.backup_rounded,
                            size: NovaButtonSize.compact,
                            variant: NovaButtonVariant.secondary,
                            loading: _backingUp,
                            onPressed: _backingUp ? null : _backupNow,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('upload'),
                            icon: Icons.upload_rounded,
                            size: NovaButtonSize.compact,
                            loading: _uploading,
                            onPressed: _uploading ? null : _upload,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          child: NovaIconButton(
                            icon: Icons.download_rounded,
                            size: 40,
                            iconSize: 19,
                            onTap: _uploading ? null : _downloadWorld,
                            tooltip: L10n.t('worldDownload'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _importResultCard(),
            if (_worlds.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              SectionCard(
                title: L10n.t('worldSavedFolders'),
                icon: Icons.folder_special_rounded,
                child: Column(
                  children: _worlds.map((ServerWorldInfo world) => InfoRow(
                    label: world.path,
                    value: '${Fmt.bytes(world.size)} · ${world.fileCount}',
                    icon: Icons.public_rounded,
                  )).toList(),
                ),
              ),
            ],
            if (_manifestTruncated)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InfoBanner(body: L10n.t('worldManifestTruncated'), color: p.warning, dense: true),
              ),
            const SizedBox(height: 10),
            SectionCard(
              title: L10n.t('worldUploadTitle'),
              icon: Icons.cloud_upload_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(L10n.t('worldUploadHint'), style: NovaTextStyles.small(p.textMuted)),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Icon(Icons.archive_rounded, size: 14, color: p.textDim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          L10n.t('worldUploadBody'),
                          style: NovaTextStyles.caption(p.textDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: L10n.t('worldDownload'),
              icon: Icons.download_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(L10n.t('backupDownload'), style: NovaTextStyles.small(p.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(Icons.inventory_2_rounded, size: 14, color: p.successBright),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _backups.isEmpty
                              ? L10n.t('backupEmpty')
                              : L10n.f('worldBackupsCount', <String, String>{'count': '${_backups.length}'}),
                          style: NovaTextStyles.caption(p.textDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            InfoBanner(
              body: L10n.t('worldNote'),
              icon: Icons.info_outline_rounded,
              color: p.warning,
            ),
          ],
        ],
      ),
    );
  }
}
