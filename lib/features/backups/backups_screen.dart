import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

class BackupsView extends StatefulWidget {
  const BackupsView({super.key, required this.config, this.active = true});

  final ServerConfig config;
  final bool active;

  @override
  State<BackupsView> createState() => _BackupsViewState();
}

class _BackupsViewState extends State<BackupsView> {
  List<ReleaseInfo> _backups = <ReleaseInfo>[];
  bool _loading = true;
  String? _error;
  bool _creating = false;
  String? _busyTag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BackupsView oldWidget) {
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
      final List<ReleaseInfo> releases = await state.api.listReleases(widget.config.repoOwner, widget.config.repoName);
      if (!mounted) return;
      setState(() {
        _backups = releases
            .where((ReleaseInfo r) => r.tag.startsWith('backup-${widget.config.id}-') || r.tag.startsWith('backup-'))
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.snapshot(state.api, widget.config);
      if (!mounted) return;
      showNovaToast(context, L10n.t('backupRestoreQueued'), kind: ToastKind.success);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _restore(ReleaseInfo release) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('backupRestoreTitle'),
      body: L10n.f('backupRestoreBody', <String, String>{'tag': release.tag}),
      confirmLabel: L10n.t('restore'),
      danger: true,
      icon: Icons.restore_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyTag = release.tag);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.restoreBackup(state.api, widget.config, release.tag);
      if (!mounted) return;
      showNovaToast(context, L10n.t('backupRestoreQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyTag = null);
    }
  }

  Future<void> _delete(ReleaseInfo release) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('backupDeleteTitle'),
      body: L10n.f('backupDeleteBody', <String, String>{'tag': release.tag}),
      confirmLabel: L10n.t('delete'),
      danger: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyTag = release.tag);
    try {
      final AppState state = AppScope.read(context);
      await state.api.deleteRelease(widget.config.repoOwner, widget.config.repoName, release.id);
      if (!mounted) return;
      showNovaToast(context, L10n.t('backupDeleted'), kind: ToastKind.success);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyTag = null);
    }
  }

  Future<void> _download(ReleaseInfo release) async {
    final ReleaseAsset? asset = release.assets.isEmpty ? null : release.assets.first;
    if (asset?.downloadUrl == null) {
      showNovaToast(context, L10n.t('errorGeneric'), kind: ToastKind.error);
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
    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(L10n.t('backupsTitle'), style: NovaTextStyles.title(p.text)),
                    const SizedBox(height: 2),
                    Text(L10n.t('backupsSubtitle'), style: NovaTextStyles.caption(p.textMuted)),
                  ],
                ),
              ),
              NovaButton(
                label: L10n.t('createBackup'),
                icon: Icons.backup_rounded,
                size: NovaButtonSize.compact,
                expand: false,
                loading: _creating,
                onPressed: _creating ? null : _create,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoBanner(
            body: L10n.t('backupNote'),
            icon: Icons.shield_rounded,
            color: p.success,
            title: L10n.t('backupSafetyFirst'),
          ),
          if (widget.config.autoRestart || widget.config.edition == 'JAVA')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: InfoBanner(body: L10n.t('githubRunnersNote'), dense: true, color: p.warning),
            ),
          const SizedBox(height: 14),
          if (_loading && _backups.isEmpty)
            const SkeletonList(count: 3, cardHeight: 92)
          else if (_error != null)
            ErrorState(message: _error!, onRetry: _load, compact: true)
          else if (_backups.isEmpty)
            EmptyState(
              title: L10n.t('backupEmpty'),
              body: L10n.t('backupEmptyBody'),
              icon: Icons.backup_outlined,
              compact: true,
              actionLabel: L10n.t('createBackup'),
              onAction: _create,
            )
          else
            ..._backups.map((ReleaseInfo release) {
              final bool busy = _busyTag == release.tag;
              final ReleaseAsset? asset = release.assets.isEmpty ? null : release.assets.first;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: NovaGradients.card(p),
                  borderRadius: NovaRadii.rLg,
                  border: Border.all(color: p.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: p.success.withValues(alpha: 0.13),
                            borderRadius: NovaRadii.rXs,
                            border: Border.all(color: p.success.withValues(alpha: 0.26)),
                          ),
                          child: Icon(Icons.inventory_2_rounded, size: 19, color: p.successBright),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                release.tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NovaTextStyles.mono(12, p.text),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Icon(Icons.schedule_rounded, size: 11, color: p.textDim),
                                  const SizedBox(width: 4),
                                  Text(
                                    Fmt.relative(release.createdAtDate),
                                    style: NovaTextStyles.caption(p.textDim),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.storage_rounded, size: 11, color: p.textDim),
                                  const SizedBox(width: 4),
                                  Text(Fmt.bytes(release.totalSize), style: NovaTextStyles.caption(p.textDim)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Pill(
                          label: L10n.t('backupReady'),
                          tone: PillTone.success,
                          dense: true,
                          icon: Icons.check_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('restore'),
                            icon: Icons.restore_rounded,
                            size: NovaButtonSize.compact,
                            variant: NovaButtonVariant.secondary,
                            loading: busy,
                            onPressed: busy || asset == null ? null : () => _restore(release),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('download'),
                            icon: Icons.download_rounded,
                            size: NovaButtonSize.compact,
                            variant: NovaButtonVariant.ghost,
                            onPressed: busy || asset == null ? null : () => _download(release),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NovaIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 38,
                          iconSize: 18,
                          accent: p.danger,
                          onTap: busy ? null : () => _delete(release),
                          tooltip: L10n.t('delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.download_rounded, size: 13, color: p.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(L10n.t('backupDownload'), style: NovaTextStyles.caption(p.textDim)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
