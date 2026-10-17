import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import 'server_detail_screen.dart';

class CreateServerScreen extends StatefulWidget {
  const CreateServerScreen({super.key});

  @override
  State<CreateServerScreen> createState() => _CreateServerScreenState();
}

class _CreateServerScreenState extends State<CreateServerScreen> {
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _motd = TextEditingController(text: 'A NOVA CRAFT Server');
  final TextEditingController _playit = TextEditingController();
  final TextEditingController _newRepo = TextEditingController();

  int _step = 0;
  String _edition = 'JAVA';
  String _software = 'PAPER';
  String _version = '';

  List<String> _versions = <String>[];
  bool _loadingVersions = false;
  String? _versionsError;

  List<GhRepo> _repos = <GhRepo>[];
  bool _loadingRepos = false;
  String? _reposError;
  String _repoMode = 'existing';
  String? _repoFull;
  bool _repoPrivate = true;

  int _memoryMb = 4096;
  int _players = 20;
  int _viewDistance = 10;
  String _gamemode = 'survival';
  String _difficulty = 'normal';
  bool _startNow = true;
  bool _needsInstall = false;

  bool _creating = false;
  String? _createError;
  String _progress = '';
  List<String> _doneSteps = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVersions());
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _motd.dispose();
    _playit.dispose();
    _newRepo.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() {
      _loadingVersions = true;
      _versionsError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      List<String> values;
      switch (_software) {
        case 'PAPER':
          values = (await state.minecraft.paperVersions()).reversed.toList();
          break;
        case 'PURPUR':
          values = (await state.minecraft.purpurVersions()).reversed.toList();
          break;
        default:
          final List<McVersion> releases = await state.minecraft.javaReleases();
          values = releases.map((McVersion v) => v.id).toList();
      }
      if (!mounted) return;
      setState(() {
        _versions = values;
        if (_version.isEmpty || !values.contains(_version)) {
          _version = values.isNotEmpty ? values.first : '';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _versionsError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loadingVersions = false);
    }
  }

  Future<void> _loadRepos() async {
    if (_repos.isNotEmpty || _loadingRepos) return;
    setState(() {
      _loadingRepos = true;
      _reposError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<GhInstallation> installations = await state.api.listInstallations();
      final List<GhRepo> repos = <GhRepo>[];
      for (final GhInstallation installation in installations) {
        repos.addAll(await state.api.listInstallationRepos(installation.id));
      }
      if (!mounted) return;
      setState(() {
        _repos = repos;
        if (_repoFull == null && repos.isNotEmpty) _repoFull = repos.first.fullName;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _reposError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step == 0) {
      _loadVersions();
    }
    if (_step == 2) {
      _loadRepos();
    }
    if (_step < 3) {
      setState(() => _step += 1);
      _pages.animateToPage(_step, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step -= 1);
    _pages.animateToPage(_step, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  bool get _repoReady {
    if (_repoMode == 'existing') return _repoFull != null;
    return _newRepo.text.trim().isNotEmpty;
  }

  bool get _stepValid {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return _version.isNotEmpty;
      case 2:
        return _name.text.trim().isNotEmpty && _repoReady;
      default:
        return true;
    }
  }

  String? get _validationHint {
    if (_step == 2) {
      if (_name.text.trim().isEmpty) return L10n.t('nameRequired');
      if (!_repoReady) return _repoMode == 'existing' ? L10n.t('selectRepoRequired') : L10n.t('repoRequired');
    }
    if (_step == 1 && _version.isEmpty) return L10n.t('versionRequired');
    return null;
  }

  ServerConfig _buildConfig(String owner, String repo, int javaMajor) {
    final String cleanName = _name.text.trim();
    return ServerConfig(
      id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${repo.hashCode.abs().toRadixString(36)}',
      name: cleanName,
      repoOwner: owner,
      repoName: repo,
      repoPrivate: _repoPrivate,
      edition: _edition,
      mcVersion: _version,
      software: _software,
      javaMajor: javaMajor,
      maxPlayers: _players,
      gamemode: _gamemode,
      difficulty: _difficulty,
      viewDistance: _viewDistance,
      simulationDistance: _viewDistance,
      motd: _motd.text.trim().isEmpty ? 'A NOVA CRAFT Server' : _motd.text.trim(),
      memoryMb: _memoryMb,
      playitAddress: _playit.text.trim(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _create() async {
    if (!_stepValid || _creating) return;
    setState(() {
      _creating = true;
      _createError = null;
      _doneSteps = <String>[];
      _progress = L10n.t('provisioningRepo');
    });
    try {
      final AppState state = AppScope.read(context);
      String owner;
      String repo;
      if (_repoMode == 'existing') {
        final List<GhRepo> matches = _repos.where((GhRepo r) => r.fullName == _repoFull).toList();
        if (matches.isEmpty) throw ApiException(400, L10n.t('selectRepoRequired'));
        owner = matches.first.owner;
        repo = matches.first.name;
      } else {
        final GhRepo created = await state.api.createRepo(
          _newRepo.text.trim(),
          _repoPrivate,
          'NOVA CRAFT Minecraft server',
        );
        owner = created.owner;
        repo = created.name;
        _doneSteps = <String>[..._doneSteps, 'repo'];
        setState(() => _progress = L10n.t('checkingInstallation'));
        final List<GhInstallation> installations = await state.api.listInstallations();
        bool hasAccess = false;
        for (final GhInstallation installation in installations) {
          final List<GhRepo> granted = await state.api.listInstallationRepos(installation.id);
          if (granted.any((GhRepo r) => r.fullName == '$owner/$repo')) {
            hasAccess = true;
            break;
          }
        }
        if (!hasAccess) {
          if (!mounted) return;
          setState(() {
            _needsInstall = true;
            _creating = false;
            _progress = '';
          });
          return;
        }
      }

      setState(() => _progress = L10n.t('resolutionPending'));
      final String label = _software;
      ResolvedDownload resolved;
      switch (label) {
        case 'PAPER':
          resolved = await state.minecraft.resolvePaper(_version);
          break;
        case 'PURPUR':
          resolved = await state.minecraft.resolvePurpur(_version);
          break;
        case 'FABRIC':
          resolved = await state.minecraft.resolveFabric(_version);
          break;
        default:
          resolved = await state.minecraft.resolveVanilla(_version);
      }
      _doneSteps = <String>[..._doneSteps, 'resolve'];
      setState(() => _progress = L10n.t('provisioningFiles'));

      final ServerConfig config = _buildConfig(owner, repo, resolved.javaMajor).copyWith(
        downloadUrl: resolved.url,
        downloadSha: resolved.sha,
      );
      await Provisioner.writeServerFiles(state.api, config, null);
      _doneSteps = <String>[..._doneSteps, 'files'];
      setState(() => _progress = L10n.t('provisioningDispatch'));

      if (_startNow) {
        await Provisioner.startServer(state.api, config);
        _doneSteps = <String>[..._doneSteps, 'dispatch'];
      }
      state.upsertServer(config);
      await state.refreshServers();
      if (!mounted) return;
      setState(() {
        _progress = L10n.t('provisioningDone');
        _creating = false;
      });
      await showNovaConfirm(
        context,
        title: L10n.t('provisioningDone'),
        body: _startNow ? L10n.t('runStarted') : L10n.t('provisioningHint'),
        confirmLabel: L10n.t('goToServer'),
        cancelLabel: L10n.t('close'),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ServerDetailScreen(config: config),
      ));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _createError = Fmt.error(error);
        _creating = false;
        _progress = '';
      });
    }
  }

  Future<void> _openInstall() async {
    await launchUrl(Uri.parse(AppConfig.appInstallUrl), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() {
      _needsInstall = false;
      _repos = <GhRepo>[];
    });
    await _loadRepos();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              NovaTopBar(
                onBack: _back,
                title: L10n.t('createServerTitle'),
                subtitle: L10n.f('wizardStepOf', <String, String>{'current': '${_step + 1}', 'total': '4'}),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 4),
                child: Row(
                  children: List<Widget>.generate(4, (int i) {
                    final bool active = i <= _step;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsetsDirectional.only(end: i == 3 ? 0 : 6),
                        decoration: BoxDecoration(
                          gradient: active ? NovaGradients.primary : null,
                          color: active ? null : p.strokeStrong.withValues(alpha: 0.3),
                          borderRadius: NovaRadii.rPill,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: <Widget>[
                    _typeStep(),
                    _versionStep(),
                    _settingsStep(),
                    _reviewStep(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 16),
                child: Column(
                  children: <Widget>[
                    if (_validationHint != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.info_outline_rounded, size: 14, color: p.warning),
                            const SizedBox(width: 6),
                            Text(_validationHint!, style: NovaTextStyles.small(p.warning)),
                          ],
                        ),
                      ),
                    Row(
                      children: <Widget>[
                        if (_step > 0)
                          Expanded(
                            child: NovaButton(
                              label: L10n.t('back'),
                              variant: NovaButtonVariant.secondary,
                              onPressed: _creating ? null : _back,
                            ),
                          ),
                        if (_step > 0) const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _step == 3
                              ? NovaButton(
                                  label: L10n.t('createServer'),
                                  icon: Icons.rocket_launch_rounded,
                                  loading: _creating,
                                  onPressed: _stepValid && !_creating ? _create : null,
                                )
                              : NovaButton(
                                  label: L10n.t('next'),
                                  trailingIcon: Icons.arrow_forward_rounded,
                                  onPressed: _stepValid ? _next : null,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<Widget> children, {String? title, String? subtitle}) {
    final p = context.nova;
    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 14, NovaSpace.page, 24),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(title, style: NovaTextStyles.display(23, p.text)),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(subtitle, style: NovaTextStyles.small(p.textMuted)),
          ],
          const SizedBox(height: 16),
        ],
        ...children,
      ],
    );
  }

  Widget _typeStep() {
    final p = context.nova;
    return _body(
      <Widget>[
        _EditionCard(
          title: 'Java Edition',
          body: L10n.t('javaHint'),
          icon: Icons.computer_rounded,
          accent: p.primaryBright,
          selected: _edition == 'JAVA',
          onTap: () => setState(() => _edition = 'JAVA'),
        ),
        const SizedBox(height: 10),
        _EditionCard(
          title: 'Bedrock Edition',
          body: L10n.t('bedrockHint'),
          icon: Icons.phone_android_rounded,
          accent: p.violet,
          selected: false,
          disabled: true,
          badge: L10n.t('softwareUnsupported'),
          onTap: null,
        ),
        const SizedBox(height: 22),
        Text(L10n.t('software'), style: NovaTextStyles.title(p.text)),
        const SizedBox(height: 10),
        ...<Widget>[
          _softwareTile('PAPER', 'Paper', L10n.t('paperHint'), true),
          _softwareTile('PURPUR', 'Purpur', L10n.t('purpurHint'), true),
          _softwareTile('FABRIC', 'Fabric', L10n.t('fabricHint'), true),
          _softwareTile('VANILLA', 'Vanilla', L10n.t('vanilla'), true),
          _softwareTile('FORGE', 'Forge', L10n.t('softwareUnsupportedWhy'), false),
          _softwareTile('NEOFORGE', 'NeoForge', L10n.t('softwareUnsupportedWhy'), false),
        ],
        const SizedBox(height: 8),
        InfoBanner(body: L10n.t('softwareUnsupportedWhy'), color: p.warning),
      ],
      title: L10n.t('stepType'),
      subtitle: L10n.t('stepTypeBody'),
    );
  }

  Widget _softwareTile(String id, String name, String body, bool enabled) {
    final p = context.nova;
    final bool selected = _software == id;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: PressableScale(
        onTap: enabled ? () => setState(() => _software = id) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected ? p.primary.withValues(alpha: 0.12) : p.cardSoft,
            borderRadius: NovaRadii.rMd,
            border: Border.all(color: selected ? p.primary.withValues(alpha: 0.55) : p.stroke),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled ? p.primary.withValues(alpha: 0.14) : p.strokeStrong.withValues(alpha: 0.2),
                  borderRadius: NovaRadii.rXs,
                ),
                child: Text(
                  name.substring(0, 1),
                  style: NovaTextStyles.number(17, enabled ? p.primaryBright : p.textDim),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: NovaTextStyles.bodyStrong(p.text)),
                    const SizedBox(height: 2),
                    Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTextStyles.small(p.textDim)),
                  ],
                ),
              ),
              if (!enabled)
                Pill(label: L10n.t('unavailable'), tone: PillTone.neutral, dense: true)
              else if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: p.primaryBright)
              else
                Icon(Icons.circle_outlined, size: 20, color: p.strokeStrong),
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionStep() {
    final p = context.nova;
    return _body(
      <Widget>[
        if (_loadingVersions)
          const SkeletonList(count: 5, cardHeight: 52)
        else if (_versionsError != null)
          ErrorState(message: _versionsError!, onRetry: _loadVersions)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _versions.take(60).map((String v) {
              return NovaChip(
                label: v,
                selected: _version == v,
                onTap: () => setState(() => _version = v),
              );
            }).toList(),
          ),
        const SizedBox(height: 18),
        InfoBanner(
          body: L10n.t('versionSupportNote'),
          icon: Icons.verified_rounded,
          color: p.success,
        ),
      ],
      title: L10n.t('stepVersion'),
      subtitle: '${_softwareName()} · ${L10n.t('software')}',
    );
  }

  Widget _settingsStep() {
    final p = context.nova;
    return _body(
      <Widget>[
        NovaField(
          label: L10n.t('serverName'),
          hint: L10n.t('serverNameHint'),
          controller: _name,
          prefixIcon: Icons.dns_rounded,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        NovaField(
          label: L10n.t('motd'),
          controller: _motd,
          prefixIcon: Icons.chat_bubble_outline_rounded,
        ),
        const SizedBox(height: 18),
        Text(L10n.t('serverRepo'), style: NovaTextStyles.title(p.text)),
        const SizedBox(height: 10),
        NovaSegmented(
          labels: <String>[L10n.t('useExistingRepo'), L10n.t('createNewRepo')],
          index: _repoMode == 'existing' ? 0 : 1,
          onChanged: (int i) => setState(() => _repoMode = i == 0 ? 'existing' : 'new'),
        ),
        const SizedBox(height: 12),
        if (_repoMode == 'existing')
          _repoSelector()
        else ...<Widget>[
          NovaField(
            label: L10n.t('repoName'),
            hint: 'nova-craft-server',
            controller: _newRepo,
            prefixIcon: Icons.folder_special_rounded,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          NovaSwitchTile(
            title: L10n.t('repoPrivate'),
            subtitle: L10n.t('publicWarning'),
            value: _repoPrivate,
            onChanged: (bool v) => setState(() => _repoPrivate = v),
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 8),
          InfoBanner(
            title: L10n.t('installAppTitle'),
            body: L10n.t('installAppBody'),
            icon: Icons.apps_rounded,
            color: p.violet,
            actionLabel: L10n.t('installApp'),
            onAction: _openInstall,
          ),
          if (_needsInstall) ...<Widget>[
            const SizedBox(height: 8),
            InfoBanner(
              body: L10n.t('installNeeded'),
              icon: Icons.error_outline_rounded,
              color: p.warning,
              actionLabel: L10n.t('retry'),
              onAction: _openInstall,
            ),
          ],
        ],
        const SizedBox(height: 18),
        NovaSliderTile(
          label: L10n.t('memory'),
          value: _memoryMb.toDouble(),
          min: 1024,
          max: 8192,
          divisions: 7,
          suffix: ' MB',
          icon: Icons.memory_rounded,
          onChanged: (double v) => setState(() => _memoryMb = v.round()),
        ),
        NovaSliderTile(
          label: L10n.t('maxPlayers'),
          value: _players.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          suffix: '',
          icon: Icons.groups_rounded,
          onChanged: (double v) => setState(() => _players = v.round()),
        ),
        NovaSliderTile(
          label: L10n.t('viewDistance'),
          value: _viewDistance.toDouble(),
          min: 2,
          max: 32,
          divisions: 30,
          suffix: '',
          icon: Icons.visibility_rounded,
          onChanged: (double v) => setState(() => _viewDistance = v.round()),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: NovaDropdown<String>(
                label: L10n.t('gamemode'),
                value: _gamemode,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'survival', child: Text(L10n.t('survival'))),
                  DropdownMenuItem<String>(value: 'creative', child: Text(L10n.t('creative'))),
                  DropdownMenuItem<String>(value: 'adventure', child: Text(L10n.t('adventure'))),
                  DropdownMenuItem<String>(value: 'spectator', child: Text(L10n.t('spectator'))),
                ],
                onChanged: (String? v) => setState(() => _gamemode = v ?? 'survival'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NovaDropdown<String>(
                label: L10n.t('difficulty'),
                value: _difficulty,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'peaceful', child: Text(L10n.t('peaceful'))),
                  DropdownMenuItem<String>(value: 'easy', child: Text(L10n.t('easy'))),
                  DropdownMenuItem<String>(value: 'normal', child: Text(L10n.t('normal'))),
                  DropdownMenuItem<String>(value: 'hard', child: Text(L10n.t('hard'))),
                ],
                onChanged: (String? v) => setState(() => _difficulty = v ?? 'normal'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NovaField(
          label: L10n.t('serverAddress'),
          hint: 'your-tunnel.playit.gg',
          controller: _playit,
          prefixIcon: Icons.hub_rounded,
          helper: L10n.t('addressFromConfig'),
        ),
      ],
      title: L10n.t('stepSettings'),
    );
  }

  Widget _repoSelector() {
    final p = context.nova;
    if (_loadingRepos) return const SkeletonList(count: 3, cardHeight: 54);
    if (_reposError != null) return ErrorState(message: _reposError!, onRetry: _loadRepos, compact: true);
    if (_repos.isEmpty) {
      return InfoBanner(
        body: L10n.t('noReposAvailable'),
        icon: Icons.folder_off_rounded,
        color: p.warning,
        actionLabel: L10n.t('refresh'),
        onAction: () {
          setState(() => _repos = <GhRepo>[]);
          _loadRepos();
        },
      );
    }
    return Column(
      children: <Widget>[
        NovaDropdown<String>(
          label: L10n.t('repository'),
          value: _repoFull,
          items: _repos
              .map((GhRepo r) => DropdownMenuItem<String>(
                    value: r.fullName,
                    child: Row(
                      children: <Widget>[
                        Icon(r.private ? Icons.lock_rounded : Icons.public_rounded, size: 14, color: p.textDim),
                        const SizedBox(width: 6),
                        Flexible(child: Text(r.fullName, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (String? v) => setState(() => _repoFull = v),
        ),
        if (_repos.any((GhRepo r) => r.fullName == _repoFull)) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            L10n.t('existingRepoWarning'),
            style: NovaTextStyles.small(p.textDim),
          ),
        ],
      ],
    );
  }

  Widget _reviewStep() {
    final p = context.nova;
    final String repo = _repoMode == 'existing' ? (_repoFull ?? '—') : _newRepo.text.trim();
    return _body(
      <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: NovaGradients.cardGlow(p, p.primary),
            borderRadius: NovaRadii.rLg,
            border: Border.all(color: p.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: <Widget>[
              ServerAvatar(
                name: _name.text.trim().isEmpty ? 'N' : _name.text.trim(),
                size: 64,
                edition: _edition,
                software: _software,
              ),
              const SizedBox(height: 10),
              Text(
                _name.text.trim().isEmpty ? L10n.t('serverName') : _name.text.trim(),
                textAlign: TextAlign.center,
                style: NovaTextStyles.display(22, p.text),
              ),
              const SizedBox(height: 4),
              Text('${_softwareName()} ${_version.isEmpty ? '' : '· $_version'}', style: NovaTextStyles.small(p.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: L10n.t('summary'),
          icon: Icons.fact_check_rounded,
          child: Column(
            children: <Widget>[
              InfoRow(label: L10n.t('summaryEdition'), value: _edition == 'JAVA' ? 'Java' : 'Bedrock'),
              InfoRow(label: L10n.t('summarySoftware'), value: _softwareName()),
              InfoRow(label: L10n.t('summaryVersion'), value: _version.isEmpty ? '—' : _version),
              InfoRow(label: L10n.t('summaryRepo'), value: repo, monospace: true),
              InfoRow(label: L10n.t('summaryPlayers'), value: '$_players'),
              InfoRow(label: L10n.t('summaryMemory'), value: '$_memoryMb MB'),
              InfoRow(label: L10n.t('gamemode'), value: L10n.t(_gamemode)),
              InfoRow(label: L10n.t('difficulty'), value: L10n.t(_difficulty)),
              InfoRow(
                label: L10n.t('serverAddress'),
                value: _playit.text.trim().isEmpty ? L10n.t('noAddressYet') : _playit.text.trim(),
                monospace: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NovaSwitchTile(
          title: L10n.t('startAfterCreate'),
          subtitle: L10n.t('runStarted'),
          value: _startNow,
          onChanged: (bool v) => setState(() => _startNow = v),
          icon: Icons.play_circle_outline_rounded,
        ),
        const SizedBox(height: 16),
        if (_creating) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.cardSoft,
              borderRadius: NovaRadii.rLg,
              border: Border.all(color: p.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SizedBox(width: 18, height: 18, child: NovaLoader(size: 18, stroke: 2)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_progress, style: NovaTextStyles.smallStrong(p.text))),
                  ],
                ),
                const SizedBox(height: 12),
                ProgressTrack(value: _doneSteps.length.clamp(0, 4).toDouble() / 4, color: p.primaryBright),
                const SizedBox(height: 8),
                Text('${_doneSteps.length}/4', style: NovaTextStyles.number(12, p.textMuted)),
              ],
            ),
          ),
        ],
        if (_createError != null) ...<Widget>[
          const SizedBox(height: 12),
          InlineError(message: _createError!, onRetry: _create),
        ],
        const SizedBox(height: 12),
        InfoBanner(
          body: L10n.t('provisioningHint'),
          icon: Icons.info_outline_rounded,
          color: p.textDim,
        ),
      ],
      title: L10n.t('stepReview'),
    );
  }

  String _softwareName() {
    switch (_software) {
      case 'PAPER':
        return 'Paper';
      case 'PURPUR':
        return 'Purpur';
      case 'FABRIC':
        return 'Fabric';
      case 'FORGE':
        return 'Forge';
      case 'NEOFORGE':
        return 'NeoForge';
      default:
        return 'Vanilla';
    }
  }
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.disabled = false,
    this.badge,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : p.cardSoft,
            borderRadius: NovaRadii.rLg,
            border: Border.all(color: selected ? accent.withValues(alpha: 0.6) : p.stroke, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: NovaRadii.rSm,
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(title, style: NovaTextStyles.title(p.text)),
                        if (badge != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Pill(label: badge!, tone: PillTone.warning, dense: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(body, style: NovaTextStyles.small(p.textMuted)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.radio_button_checked_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
