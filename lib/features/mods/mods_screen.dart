import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/modrinth_api.dart';
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
  List<DirEntry> _installed = <DirEntry>[];
  bool _loadingInstalled = false;
  String? _installedError;
  String _branch = 'main';
  String? _busyId;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loader = _defaultLoader(0);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBranch();
      await _refreshInstalled();
      await _search();
    });
  }

  @override
  void didUpdateWidget(ModsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _loadedOnce) {
      _refreshInstalled();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  String get _folder => _tab == 0 ? 'server/mods' : 'server/plugins';

  String get _projectType => _tab == 0 ? 'mod' : 'plugin';

  bool get _supported => widget.config.isJava && (_tab == 0 ? widget.config.supportsMods : widget.config.supportsPlugins);

  Future<void> _loadBranch() async {
    try {
      final AppState state = AppScope.read(context);
      final GhRepo repo = await state.api.getRepo(widget.config.repoOwner, widget.config.repoName);
      _branch = repo.defaultBranch.isEmpty ? 'main' : repo.defaultBranch;
    } catch (_) {
      _branch = 'main';
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _search);
    setState(() {});
  }

  Future<void> _search() async {
    if (!_supported) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<ModrinthProject> hits = await state.modrinth.search(
        query: _query.text.trim(),
        projectType: _projectType,
        loader: _loader,
        gameVersion: widget.config.mcVersion.isEmpty ? null : widget.config.mcVersion,
      );
      if (!mounted) return;
      setState(() {
        _results = hits;
        _loadedOnce = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _searchError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _refreshInstalled() async {
    if (!_supported) return;
    setState(() {
      _loadingInstalled = true;
      _installedError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<DirEntry> entries = await state.api.listDir(widget.config.repoOwner, widget.config.repoName, _folder);
      if (!mounted) return;
      setState(() => _installed = entries.where((DirEntry e) => e.name.toLowerCase().endsWith('.jar')).toList());
    } catch (error) {
      if (!mounted) return;
      setState(() => _installedError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loadingInstalled = false);
    }
  }

  DirEntry? _installedEntry(ModrinthProject project) {
    final String slug = project.slug.toLowerCase();
    for (final DirEntry entry in _installed) {
      final String name = entry.name.toLowerCase();
      if (name.contains(slug) || name.contains(project.id.toLowerCase())) return entry;
    }
    return null;
  }

  List<String> get _allowedLoaders {
    if (_tab == 0) return <String>['fabric', 'quilt'];
    switch (_loader) {
      case 'spigot':
        return <String>['spigot', 'bukkit', 'paper', 'purpur'];
      case 'purpur':
        return <String>['purpur', 'paper', 'spigot', 'bukkit'];
      default:
        return <String>['paper', 'purpur', 'spigot', 'bukkit'];
    }
  }

  bool _compatible(ModrinthVersion version) {
    final bool loaderOk = version.loaders.any((String l) => _allowedLoaders.contains(l));
    final bool versionOk = widget.config.mcVersion.isEmpty || version.gameVersions.contains(widget.config.mcVersion);
    return loaderOk && versionOk;
  }

  Future<void> _install(ModrinthProject project) async {
    setState(() => _busyId = project.id);
    try {
      final AppState state = AppScope.read(context);
      final List<ModrinthVersion> versions = await state.modrinth.versions(project.id);
      final List<ModrinthVersion> compatible = versions.where(_compatible).toList();
      if (!mounted) return;
      if (compatible.isEmpty) {
        showNovaToast(context, L10n.t('modNoCompatibleVersion'), kind: ToastKind.warning);
        return;
      }
      final ModrinthVersion? choice = await _pickVersion(project, compatible);
      if (choice == null || !mounted) return;
      final ModrinthVersionFile? file = choice.primaryFile;
      if (file == null) {
        showNovaToast(context, L10n.t('modInstallFailed'), kind: ToastKind.error);
        return;
      }
      setState(() => _busyId = project.id);
      final Uint8List bytes = await state.modrinth.download(file.url);
      final String target = '$_folder/${file.filename}';
      DirEntry? previous = _installedEntry(project);
      await state.api.putFile(
        widget.config.repoOwner,
        widget.config.repoName,
        target,
        bytes,
        'nova: install ${project.slug} ${choice.versionNumber}',
        branch: _branch,
      );
      if (previous != null && previous.name != file.filename) {
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
          // The new jar is installed; the old one can be removed manually.
        }
      }
      if (!mounted) return;
      showNovaToast(context, L10n.t('modInstallSuccess'), kind: ToastKind.success);
      await _refreshInstalled();
      setState(() => _browse = false);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<ModrinthVersion?> _pickVersion(ModrinthProject project, List<ModrinthVersion> versions) {
    final p = context.nova;
    return showModalBottomSheet<ModrinthVersion>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.72),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: p.stroke)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 38, height: 4, decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill)),
              const SizedBox(height: 14),
              Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text)),
              const SizedBox(height: 3),
              Text(
                '${L10n.t('modMcVersion')} ${widget.config.mcVersion} · ${_loader ?? ''}',
                style: NovaTextStyles.small(p.textDim),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: versions.length,
                  separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext c, int i) {
                    final ModrinthVersion v = versions[i];
                    return PressableScale(
                      onTap: () => Navigator.of(ctx).pop(v),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: p.cardSoft,
                          borderRadius: NovaRadii.md,
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
                                  Text(v.versionNumber, style: NovaTextStyles.bodyStrong(p.text).copyWith(fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${v.loaders.join(', ')} · ${v.gameVersions.take(3).join(', ')}',
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
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _remove(DirEntry entry) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('modRemoveTitle'),
      body: L10n.f('modRemoveBody', <String, String>{'name': entry.name}),
      confirmLabel: L10n.t('remove'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
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
        NovaSegmented(
          labels: <String>[L10n.t('modsTab'), L10n.t('pluginsTab')],
          index: _tab,
          onChanged: (int i) {
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
        ),
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
    return EmptyState(
      title: bedrock ? L10n.t('modBedrockTitle') : L10n.t('modVanillaTitle'),
      body: bedrock ? L10n.t('modBedrockBody') : L10n.t('modVanillaBody'),
      icon: Icons.extension_off_rounded,
      compact: true,
    );
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
              label: L10n.f('installedCount', <String, String>{'count': '${_installed.length}'}),
              selected: !_browse,
              onTap: () => setState(() => _browse = false),
              icon: Icons.download_done_rounded,
            ),
            const Spacer(),
            if (_searching) const SizedBox(width: 16, height: 16, child: NovaLoader(size: 16, stroke: 2)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _searchError != null
              ? ErrorState(message: _searchError!, onRetry: _search, compact: true)
              : _searching && _results.isEmpty
                  ? const SkeletonList(count: 4, cardHeight: 108)
                  : _results.isEmpty
                      ? EmptyState(
                          title: L10n.t('modNoResults'),
                          body: L10n.t('modBrowseError'),
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
    final bool busy = _busyId == project.id;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: installed != null ? p.success.withValues(alpha: 0.28) : p.stroke),
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
                          Pill(label: L10n.t('modInstalled'), tone: PillTone.success, dense: true, icon: Icons.check_rounded),
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
                const SizedBox(width: 22, height: 22, child: NovaLoader(size: 22, stroke: 2))
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
              label: L10n.f('installedCount', <String, String>{'count': '${_installed.length}'}),
              selected: true,
              onTap: () {},
              icon: Icons.download_done_rounded,
            ),
            const Spacer(),
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
                                borderRadius: NovaRadii.md,
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
