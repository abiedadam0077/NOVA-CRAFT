import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// The first setup step after GitHub sign-in. The user selects a writable
/// repository before entering a Playit secret so it can be stored directly in
/// that repository's Actions secrets.
class RepositorySelectionScreen extends StatefulWidget {
  const RepositorySelectionScreen({super.key});

  @override
  State<RepositorySelectionScreen> createState() => _RepositorySelectionScreenState();
}

class _RepositorySelectionScreenState extends State<RepositorySelectionScreen> {
  final TextEditingController _newRepo = TextEditingController();
  List<GhRepo> _repos = <GhRepo>[];
  GhRepo? _createdRepo;
  bool _loading = true;
  bool _creating = false;
  bool _private = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _newRepo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final AppState state = AppScope.read(context);
      final List<GhInstallation> installations = await state.api.listInstallations();
      final Map<String, GhRepo> byName = <String, GhRepo>{};
      for (final GhInstallation installation in installations) {
        for (final GhRepo repo in await state.api.listInstallationRepos(installation.id)) {
          if (repo.permissionsPush) byName[repo.fullName] = repo;
        }
      }
      if (!mounted) return;
      final List<GhRepo> repos = byName.values.toList()
        ..sort((GhRepo a, GhRepo b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      setState(() => _repos = repos);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  GhRepo? _find(String fullName) {
    for (final GhRepo repo in _repos) {
      if (repo.fullName == fullName && repo.permissionsPush) return repo;
    }
    return null;
  }

  void _select(GhRepo repo) {
    if (!repo.permissionsPush) {
      setState(() => _error = L10n.t('repoNoWriteAccess'));
      return;
    }
    AppScope.read(context).selectPendingRepo(repo);
  }

  Future<void> _createRepo() async {
    final String name = _newRepo.text.trim();
    if (!Validation.validRepoName(name)) {
      setState(() => _error = L10n.t('repoRequired'));
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
      _createdRepo = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final GhRepo created = await state.api.createRepo(name, _private, 'NOVA CRAFT Minecraft server');
      if (!mounted) return;
      setState(() => _createdRepo = created);
      await launchUrl(
        Uri.parse(AppConfig.appInstallUrlFor(created.fullName)),
        mode: LaunchMode.externalApplication,
      );
      await _load();
      if (!mounted) return;
      if (_find(created.fullName) == null) {
        setState(() => _error = L10n.t('repoAppInstallRequired'));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _installApp() async {
    final GhRepo? repo = _createdRepo;
    final Uri uri = Uri.parse(repo == null ? AppConfig.appInstallUrl : AppConfig.appInstallUrlFor(repo.fullName));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            NovaTopBar(showBrand: true, title: L10n.t('repositoryPickerTitle')),
            Expanded(
              child: RefreshIndicator(
                color: p.primaryBright,
                backgroundColor: p.cardHigh,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 28),
                  children: <Widget>[
                    Text(L10n.t('repositoryPickerTitle'), style: NovaTextStyles.display(25, p.text)),
                    const SizedBox(height: 8),
                    Text(L10n.t('repositoryPickerBody'), style: NovaTextStyles.body(p.textMuted)),
                    const SizedBox(height: 16),
                    if (_error != null) ...<Widget>[
                      InlineError(message: _error!, onRetry: _load),
                      const SizedBox(height: 12),
                    ],
                    SectionCard(
                      title: L10n.t('repository'),
                      icon: Icons.folder_open_rounded,
                      actionLabel: _loading ? L10n.t('loading') : L10n.t('refresh'),
                      onAction: _loading ? null : _load,
                      child: _loading
                          ? const SkeletonList(count: 3, cardHeight: 62)
                          : _repos.isEmpty
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Text(L10n.t('repoNoAccessible'), style: NovaTextStyles.small(p.textMuted)),
                                    const SizedBox(height: 10),
                                    NovaButton(
                                      label: L10n.t('installApp'),
                                      icon: Icons.open_in_new_rounded,
                                      variant: NovaButtonVariant.secondary,
                                      size: NovaButtonSize.compact,
                                      onPressed: _installApp,
                                    ),
                                  ],
                                )
                              : Column(
                                  children: <Widget>[
                                    for (final GhRepo repo in _repos)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: _RepositoryTile(repo: repo, onTap: () => _select(repo)),
                                      ),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: L10n.t('repoCreateTitle'),
                      icon: Icons.create_new_folder_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(L10n.t('repoCreateBody'), style: NovaTextStyles.small(p.textMuted)),
                          const SizedBox(height: 12),
                          NovaField(
                            label: L10n.t('repoName'),
                            hint: 'nova-craft-server',
                            controller: _newRepo,
                            prefixIcon: Icons.folder_special_rounded,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 4),
                          NovaSwitchTile(
                            title: L10n.t('repoPrivate'),
                            subtitle: L10n.t('publicWarning'),
                            value: _private,
                            onChanged: (bool value) => setState(() => _private = value),
                            icon: Icons.lock_rounded,
                          ),
                          if (_createdRepo != null && _find(_createdRepo!.fullName) == null) ...<Widget>[
                            const SizedBox(height: 8),
                            InfoBanner(
                              body: L10n.t('repoAppInstallRequired'),
                              icon: Icons.info_outline_rounded,
                              color: p.warning,
                              actionLabel: L10n.t('installApp'),
                              onAction: _installApp,
                            ),
                            const SizedBox(height: 8),
                            NovaButton(
                              label: L10n.t('checkAgain'),
                              icon: Icons.refresh_rounded,
                              size: NovaButtonSize.compact,
                              onPressed: _loading ? null : _load,
                            ),
                          ],
                          const SizedBox(height: 10),
                          NovaButton(
                            label: L10n.t('repoCreateButton'),
                            icon: Icons.add_rounded,
                            loading: _creating,
                            onPressed: _creating || _newRepo.text.trim().isEmpty ? null : _createRepo,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InfoBanner(
                      body: L10n.t('repoNoWriteAccess'),
                      icon: Icons.lock_outline_rounded,
                      color: p.violet,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({required this.repo, required this.onTap});

  final GhRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Material(
      color: p.cardSoft,
      borderRadius: NovaRadii.rMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: NovaRadii.rMd,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: <Widget>[
              Icon(repo.private ? Icons.lock_rounded : Icons.public_rounded, color: p.primaryBright, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(repo.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.bodyStrong(p.text)),
                    const SizedBox(height: 2),
                    Text(repo.defaultBranch, style: NovaTextStyles.caption(p.textDim)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: p.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
