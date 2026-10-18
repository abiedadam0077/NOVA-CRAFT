import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

class WorldsView extends StatefulWidget {
  const WorldsView({super.key, required this.config, this.active = true});

  final ServerConfig config;
  final bool active;

  @override
  State<WorldsView> createState() => _WorldsViewState();
}

class _WorldsViewState extends State<WorldsView> {
  List<DirEntry> _world = <DirEntry>[];
  List<ReleaseInfo> _backups = <ReleaseInfo>[];
  bool _loading = true;
  String? _error;
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
    if (!oldWidget.active && widget.active) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<DirEntry> world = await state.api.listDir(widget.config.repoOwner, widget.config.repoName, 'server/world');
      final List<ReleaseInfo> releases = await state.api.listReleases(widget.config.repoOwner, widget.config.repoName);
      if (!mounted) return;
      setState(() {
        _world = world;
        _backups = releases.where((ReleaseInfo r) => r.tag.startsWith('backup-')).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _worldSize {
    int total = 0;
    for (final DirEntry entry in _world) {
      if (entry.isFile) total += entry.size;
    }
    return total;
  }

  Future<void> _backupNow() async {
    setState(() => _backingUp = true);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.snapshot(state.api, widget.config);
      if (!mounted) return;
      showNovaToast(context, L10n.t('backupRestoreQueued'), kind: ToastKind.success);
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
      showNovaToast(context, L10n.t('worldUploadQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadWorld() async {
    final ReleaseInfo? latest = _backups.isEmpty ? null : _backups.first;
    final ReleaseAsset? asset = latest == null || latest.assets.isEmpty ? null : latest.assets.first;
    if (asset?.downloadUrl == null) {
      showNovaToast(context, L10n.t('backupEmptyBody'), kind: ToastKind.warning);
      return;
    }
    final bool ok = await launchUrl(Uri.parse(asset!.downloadUrl!), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showNovaToast(context, L10n.t('errorGeneric'), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool present = _world.isNotEmpty;
    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Text(L10n.t('worldsTitle'), style: NovaTextStyles.title(p.text)),
          const SizedBox(height: 2),
          Text(L10n.t('worldsSubtitle'), style: NovaTextStyles.caption(p.textMuted)),
          const SizedBox(height: 14),
          if (_loading && _world.isEmpty)
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
                            label: present ? L10n.t('online') : L10n.t('worldEmpty'),
                            tone: present ? PillTone.success : PillTone.neutral,
                            dense: true,
                            icon: present ? Icons.check_rounded : Icons.schedule_rounded,
                          ),
                        ),
                        PositionedDirectional(
                          start: 16,
                          bottom: 14,
                          end: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(L10n.t('worldCurrent'), style: NovaTextStyles.display(21, Colors.white)),
                              const SizedBox(height: 2),
                              Text(
                                present
                                    ? '${L10n.t('worldSizeHint')} ${Fmt.bytes(_worldSize)}'
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
                              : '${_backups.length} ${L10n.t('backupReady')}',
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
