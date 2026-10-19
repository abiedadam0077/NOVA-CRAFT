import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/minecraft_api.dart';
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
import '../../state/monitor_scope.dart';
import '../../state/server_monitor.dart';
import '../account/account_screen.dart';
import '../backups/backups_screen.dart';
import '../network/network_screen.dart';
import '../servers/server_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../worlds/worlds_screen.dart';

/// Fifth tab: Minecraft settings, network, run cycle and the secondary pages
/// that used to live in their own tabs.
class ServerSettingsScreen extends StatelessWidget {
  const ServerSettingsScreen({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final ServerConfig? server = state.selected;
    if (server == null) {
      return SafeArea(
        bottom: false,
        child: EmptyState(
          title: L10n.t('noServerSelected'),
          body: L10n.t('firstServerBody'),
          icon: Icons.tune_rounded,
        ),
      );
    }
    return MonitorScope(
      config: server,
      active: active,
      builder: (BuildContext context, ServerMonitor monitor) {
        return SafeArea(
          bottom: false,
          child: _SettingsBody(server: server, monitor: monitor),
        );
      },
    );
  }
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody({required this.server, required this.monitor});

  final ServerConfig server;
  final ServerMonitor monitor;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  late int _players;
  late int _viewDistance;
  late int _memory;
  late String _gamemode;
  late String _difficulty;
  late bool _onlineMode;
  late bool _eula;
  late bool _autoRestart;
  late bool _allowCommands;
  late int _backupRetention;
  late TextEditingController _motd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(widget.server);
  }

  @override
  void didUpdateWidget(covariant _SettingsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.id != widget.server.id) _load(widget.server);
  }

  void _load(ServerConfig c) {
    _players = c.maxPlayers;
    _viewDistance = c.viewDistance;
    _memory = c.memoryMb;
    _gamemode = c.gamemode;
    _difficulty = c.difficulty;
    _onlineMode = c.onlineMode;
    _eula = c.eulaAccepted;
    _autoRestart = c.autoRestart;
    _allowCommands = c.allowCommands;
    _backupRetention = c.backupRetention;
    _motd = TextEditingController(text: c.motd);
  }

  @override
  void dispose() {
    _motd.dispose();
    super.dispose();
  }

  bool get _dirty {
    final ServerConfig c = widget.server;
    return _players != c.maxPlayers ||
        _viewDistance != c.viewDistance ||
        _memory != c.memoryMb ||
        _gamemode != c.gamemode ||
        _difficulty != c.difficulty ||
        _onlineMode != c.onlineMode ||
        _eula != c.eulaAccepted ||
        _autoRestart != c.autoRestart ||
        _allowCommands != c.allowCommands ||
        _backupRetention != c.backupRetention ||
        _motd.text.trim() != c.motd;
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    final AppState state = AppScope.read(context);
    final ServerConfig next = widget.server.copyWith(
      maxPlayers: _players,
      viewDistance: _viewDistance,
      simulationDistance: _viewDistance,
      memoryMb: _memory,
      gamemode: _gamemode,
      difficulty: _difficulty,
      onlineMode: _onlineMode,
      eulaAccepted: _eula,
      autoRestart: _autoRestart,
      allowCommands: _allowCommands,
      backupRetention: _backupRetention,
      motd: _motd.text.trim().isEmpty ? 'A NOVA CRAFT Server' : _motd.text.trim(),
    );
    try {
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      showNovaToast(context, L10n.t('settingsSaved'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPage(Widget page) {
    final String? title;
    if (page is BackupsView) {
      title = L10n.t('settingsBackups');
    } else if (page is WorldsView) {
      title = L10n.t('settingsWorlds');
    } else if (page is NetworkView) {
      title = L10n.t('settingsNetwork');
    } else if (page is SettingsScreen) {
      title = L10n.t('settingsTitle');
    } else {
      title = null;
    }
    final bool insetHorizontally = page is! SettingsScreen;
    return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) {
      if (title == null) return page;
      return _SettingsSubpageShell(title: title, child: page, insetHorizontally: insetHorizontally);
    }));
  }

  Future<void> _changeVersion() async {
    final AppState state = AppScope.read(context);
    final ServerSoftware software = ServerSoftwareInfo.fromId(widget.server.software);
    final List<String>? versions = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VersionSheet(software: software),
    );
    if (versions == null || versions.isEmpty || !mounted) return;
    final String version = versions.first;
    if (version == widget.server.mcVersion) return;
    setState(() => _saving = true);
    try {
      final ServerBuild build = await state.minecraft.resolveBuild(software, version);
      await state.minecraft.verifyBuild(build);
      final ServerConfig next = widget.server.copyWith(
        mcVersion: version,
        javaMajor: build.javaMajor,
        downloadUrl: build.url,
        downloadSha: build.hash,
      );
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      showNovaToast(context, L10n.t('settingsSaved'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerConfig server = widget.server;
    final ServerMonitor monitor = widget.monitor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 130),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(L10n.t('navServerSettings'), style: NovaTextStyles.heading(22, p.text)),
                  const SizedBox(height: 2),
                  Text(server.repoFull, style: NovaTextStyles.caption(p.textDim)),
                ],
              ),
            ),
            if (_saving) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
          ],
        ),
        const SizedBox(height: NovaSpace.lg),

        SectionCard(
          title: L10n.t('stepVersion'),
          icon: Icons.developer_board_rounded,
          child: Column(
            children: <Widget>[
              InfoRow(label: L10n.t('mcVersion'), value: server.mcVersion.isEmpty ? '—' : server.mcVersion),
              InfoRow(label: L10n.t('software'), value: server.softwareLabel),
              InfoRow(label: 'Java', value: server.javaMajor == 0 ? '—' : '${server.javaMajor}'),
              const SizedBox(height: 8),
              NovaButton(
                label: L10n.t('changeVersion'),
                icon: Icons.swap_horiz_rounded,
                variant: NovaButtonVariant.secondary,
                height: 46,
                size: NovaButtonSize.compact,
                onPressed: _saving ? null : _changeVersion,
              ),
            ],
          ),
        ),
        const SizedBox(height: NovaSpace.md),

        SectionCard(
          title: L10n.t('settingsMinecraft'),
          icon: Icons.tune_rounded,
          child: Column(
            children: <Widget>[
              NovaSliderTile(
                label: L10n.t('players'),
                value: _players.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                icon: Icons.people_alt_outlined,
                onChanged: (double v) => setState(() => _players = v.round()),
              ),
              NovaDropdown<String>(
                label: L10n.t('gamemode'),
                value: _gamemode,
                items: <DropdownMenuItem<String>>[
                  for (final String value in <String>['survival', 'creative', 'adventure', 'spectator'])
                    DropdownMenuItem<String>(value: value, child: Text(Fmt.titleCase(value))),
                ],
                onChanged: (String? v) => setState(() => _gamemode = v ?? _gamemode),
              ),
              const SizedBox(height: 12),
              NovaDropdown<String>(
                label: L10n.t('difficulty'),
                value: _difficulty,
                items: <DropdownMenuItem<String>>[
                  for (final String value in <String>['peaceful', 'easy', 'normal', 'hard'])
                    DropdownMenuItem<String>(value: value, child: Text(Fmt.titleCase(value))),
                ],
                onChanged: (String? v) => setState(() => _difficulty = v ?? _difficulty),
              ),
              const SizedBox(height: 12),
              NovaSliderTile(
                label: L10n.t('viewDistance'),
                value: _viewDistance.toDouble(),
                min: 4,
                max: 16,
                divisions: 12,
                suffix: ' chunks',
                icon: Icons.visibility_outlined,
                onChanged: (double v) => setState(() => _viewDistance = v.round()),
              ),
              NovaSliderTile(
                label: L10n.t('memoryLabel'),
                value: _memory.toDouble(),
                min: 1024,
                max: 7168,
                divisions: 12,
                suffix: ' MB',
                icon: Icons.memory_rounded,
                onChanged: (double v) => setState(() => _memory = v.round()),
              ),
              NovaField(
                label: L10n.t('motd'),
                hint: 'A NOVA CRAFT Server',
                controller: _motd,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              NovaSwitchTile(
                title: L10n.t('onlineMode'),
                subtitle: L10n.t('onlineModeHint'),
                value: _onlineMode,
                icon: Icons.verified_user_outlined,
                onChanged: (bool v) => setState(() => _onlineMode = v),
              ),
              if (server.isJava)
                NovaSwitchTile(
                  title: L10n.t('eulaAcceptLabel'),
                  subtitle: L10n.t('eulaSectionBody'),
                  value: _eula,
                  icon: Icons.gavel_rounded,
                  onChanged: (bool v) => setState(() => _eula = v),
                ),
            ],
          ),
        ),
        const SizedBox(height: NovaSpace.md),

        SectionCard(
          title: L10n.t('settingsNetwork'),
          icon: Icons.public_rounded,
          child: Column(
            children: <Widget>[
              InfoRow(
                label: L10n.t('serverAddress'),
                value: server.connectionHostPort.isEmpty ? L10n.t('noAddressYet') : server.connectionHostPort,
                monospace: true,
              ),
              InfoRow(
                label: L10n.t('tunnelStatus'),
                value: monitor.tunnelConnected ? L10n.t('connected') : L10n.t('tunnelUnknown'),
                valueColor: monitor.tunnelConnected ? p.successBright : p.textMuted,
              ),
              const SizedBox(height: 8),
              NovaButton(
                label: L10n.t('managePlayit'),
                icon: Icons.lan_outlined,
                variant: NovaButtonVariant.secondary,
                height: 46,
                size: NovaButtonSize.compact,
                onPressed: () => _openPage(NetworkView(
                  config: server,
                  reportedAddress: monitor.address,
                  runtime: monitor.runtime,
                  activeRun: monitor.runActive,
                  showHeader: false,
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: NovaSpace.md),

        SectionCard(
          title: L10n.t('runtimeSection'),
          icon: Icons.settings_suggest_rounded,
          child: Column(
            children: <Widget>[
              InfoRow(label: L10n.t('status'), value: monitor.run == null ? '—' : '${monitor.run!.status}${monitor.run!.conclusion != null ? ' · ${monitor.run!.conclusion}' : ''}'),
              InfoRow(label: L10n.t('lastRun'), value: Fmt.relative(monitor.run?.createdAtDate)),
              NovaSwitchTile(
                title: L10n.t('autoRestart'),
                subtitle: L10n.t('autoRestartBody'),
                value: _autoRestart,
                icon: Icons.autorenew_rounded,
                onChanged: (bool v) => setState(() => _autoRestart = v),
              ),
              NovaSwitchTile(
                title: L10n.t('allowCommands'),
                subtitle: L10n.t('allowCommandsBody'),
                value: _allowCommands,
                icon: Icons.terminal_rounded,
                onChanged: (bool v) => setState(() => _allowCommands = v),
              ),
              const SizedBox(height: 8),
              NovaSliderTile(
                label: L10n.t('backupRetention'),
                value: _backupRetention.toDouble(),
                min: 2,
                max: 30,
                divisions: 28,
                suffix: '',
                icon: Icons.inventory_2_outlined,
                onChanged: (double v) => setState(() => _backupRetention = v.round()),
              ),
              Text(
                L10n.f('backupRetentionBody', <String, String>{'count': '$_backupRetention'}),
                style: NovaTextStyles.caption(p.textDim),
              ),
              const SizedBox(height: 8),
              InfoBanner(body: L10n.t('runnerLimitNote'), icon: Icons.schedule_rounded, color: p.warning, dense: true),
            ],
          ),
        ),
        const SizedBox(height: NovaSpace.md),

        SectionCard(
          title: L10n.t('settingsAdvanced'),
          icon: Icons.grid_view_rounded,
          child: Column(
            children: <Widget>[
              _LinkRow(icon: Icons.insights_rounded, label: L10n.t('details'), onTap: () => _openPage(ServerDetailScreen(config: server))),
              _LinkRow(icon: Icons.backup_outlined, label: L10n.t('settingsBackups'), onTap: () => _openPage(BackupsView(config: server, activeRun: monitor.runActive, showHeader: false))),
              _LinkRow(icon: Icons.public_rounded, label: L10n.t('settingsWorlds'), onTap: () => _openPage(WorldsView(config: server, activeRun: monitor.runActive, showHeader: false))),
              _LinkRow(icon: Icons.palette_outlined, label: L10n.t('navSettings'), onTap: () => _openPage(const SettingsScreen(active: true, showHeader: false))),
              _LinkRow(icon: Icons.person_outline_rounded, label: L10n.t('settingsAccount'), onTap: () => _openPage(const AccountScreen())),
            ],
          ),
        ),
        const SizedBox(height: NovaSpace.lg),
        NovaButton(
          label: L10n.t('saveChanges'),
          icon: Icons.save_rounded,
          onPressed: _dirty && !_saving ? _save : null,
          loading: _saving,
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: p.primaryBright),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: NovaTextStyles.body(p.text))),
            Icon(context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: p.textDim),
          ],
        ),
      ),
    );
  }
}

class _SettingsSubpageShell extends StatelessWidget {
  const _SettingsSubpageShell({required this.title, required this.child, required this.insetHorizontally});

  final String title;
  final Widget child;
  final bool insetHorizontally;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        titleSpacing: 0,
        title: Text(title, style: NovaTextStyles.heading(18, p.text)),
        leading: BackButton(color: p.text),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: insetHorizontally ? NovaSpace.page : 0),
          child: child,
        ),
      ),
    );
  }
}

class _VersionSheet extends StatefulWidget {
  const _VersionSheet({required this.software});

  final ServerSoftware software;

  @override
  State<_VersionSheet> createState() => _VersionSheetState();
}

class _VersionSheetState extends State<_VersionSheet> {
  List<String>? _versions;
  String? _error;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final MinecraftApi api = AppScope.read(context).minecraft;
    try {
      List<String> versions;
      switch (widget.software) {
        case ServerSoftware.paper:
          versions = await api.paperVersions();
          break;
        case ServerSoftware.purpur:
          versions = await api.purpurVersions();
          break;
        case ServerSoftware.fabric:
        case ServerSoftware.vanilla:
          final List<McVersion> releases = await api.javaReleases();
          versions = releases.map((McVersion v) => v.id).toList();
          break;
      }
      if (mounted) setState(() => _versions = versions);
    } catch (error) {
      if (mounted) setState(() => _error = Fmt.error(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final List<String> all = _versions ?? <String>[];
    final String query = _search.text.trim();
    final List<String> filtered = query.isEmpty ? all : all.where((String v) => v.contains(query)).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(NovaRadii.xxl)),
        border: Border.all(color: p.stroke),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: p.textDim, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(L10n.t('changeVersion'), style: NovaTextStyles.heading(18, p.text))),
                  Text(widget.software.label, style: NovaTextStyles.caption(p.textDim)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: NovaSearchField(
                controller: _search,
                hint: L10n.t('search'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? ErrorState(message: _error!, compact: true, onRetry: _load)
                  : _versions == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String version = filtered[index];
                            return PressableScale(
                              onTap: () => Navigator.of(context).pop(<String>[version]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.terminal_rounded, size: 16, color: p.primaryBright),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(version, style: NovaTextStyles.body(p.text))),
                                    Icon(context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: p.textDim),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
