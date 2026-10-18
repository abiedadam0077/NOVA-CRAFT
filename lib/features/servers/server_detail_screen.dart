import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
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
import '../../state/monitor_scope.dart';
import '../../state/server_monitor.dart';
import '../backups/backups_screen.dart';
import '../console/console_screen.dart';
import '../files/files_screen.dart';
import '../mods/mods_screen.dart';
import '../network/network_screen.dart';
import '../worlds/worlds_screen.dart';

class ServerDetailScreen extends StatefulWidget {
  const ServerDetailScreen({super.key, required this.config, this.initialTab = 0});

  final ServerConfig config;
  final int initialTab;

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> {
  late int _tab = widget.initialTab < 0 ? 0 : (widget.initialTab > 7 ? 7 : widget.initialTab);

  static const List<IconData> _icons = <IconData>[
    Icons.space_dashboard_rounded,
    Icons.terminal_rounded,
    Icons.folder_copy_rounded,
    Icons.extension_rounded,
    Icons.backup_rounded,
    Icons.public_rounded,
    Icons.hub_rounded,
    Icons.tune_rounded,
  ];

  List<String> get _labels => <String>[
        L10n.t('tabOverview'),
        L10n.t('tabConsole'),
        L10n.t('tabFiles'),
        L10n.t('tabMods'),
        L10n.t('tabBackups'),
        L10n.t('tabWorlds'),
        L10n.t('tabNetwork'),
        L10n.t('tabSettings'),
      ];

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
                onBack: () => Navigator.of(context).maybePop(),
                title: widget.config.name,
                subtitle: widget.config.repoFull,
                actions: <Widget>[
                  NovaIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'GitHub',
                    onTap: () => launchUrl(
                      Uri.parse('https://github.com/${widget.config.repoFull}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: MonitorScope(
                  config: widget.config,
                  builder: (BuildContext context, ServerMonitor monitor) {
                    return Column(
                      children: <Widget>[
                        _ServerHeader(config: widget.config, monitor: monitor),
                        const SizedBox(height: 6),
                        NovaTabStrip(
                          labels: _labels,
                          icons: _icons,
                          index: _tab,
                          onChanged: (int i) => setState(() => _tab = i),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _body(monitor)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ServerMonitor monitor) {
    switch (_tab) {
      case 1:
        return ListView(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 24),
          children: <Widget>[
            ConsoleView(config: widget.config, monitor: monitor, embedded: true),
          ],
        );
      case 2:
        return ServerFilesView(config: widget.config, active: true);
      case 3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 12),
          child: ModsView(config: widget.config),
        );
      case 4:
        return Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 0),
          child: BackupsView(config: widget.config, activeRun: monitor.runActive),
        );
      case 5:
        return Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 0),
          child: WorldsView(config: widget.config),
        );
      case 6:
        return Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 0),
          child: NetworkView(
            config: widget.config,
            reportedAddress: monitor.address,
            runtime: monitor.runtime,
            activeRun: monitor.runActive,
          ),
        );
      case 7:
        return _ServerSettingsTab(config: widget.config);
      default:
        return _OverviewTab(config: widget.config, monitor: monitor, onOpenTab: (int i) => setState(() => _tab = i));
    }
  }
}

class _ServerHeader extends StatelessWidget {
  const _ServerHeader({required this.config, required this.monitor});

  final ServerConfig config;
  final ServerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool online = monitor.phase == ServerPhase.online;
    return Padding(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: NovaGradients.cardGlow(p, online ? p.success : p.primary),
          borderRadius: NovaRadii.rLg,
          border: Border.all(color: online ? p.success.withValues(alpha: 0.32) : p.stroke),
        ),
        child: Row(
          children: <Widget>[
            ServerAvatar(
              name: config.name,
              size: 46,
              edition: config.edition,
              software: config.software,
              online: online,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          config.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTextStyles.title(p.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(phase: monitor.phase, dense: true),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${config.edition == 'JAVA' ? 'Java' : 'Bedrock'} ${config.mcVersion} · ${Fmt.titleCase(config.software)} · ${config.maxPlayers} ${L10n.t('players')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.caption(p.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            NovaIconButton(
              icon: monitor.runActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 38,
              iconSize: 19,
              filled: true,
              accent: monitor.runActive ? p.danger : p.success,
              onTap: () => _toggle(context),
              tooltip: monitor.runActive ? L10n.t('stop') : L10n.t('start'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final AppState state = AppScope.read(context);
    try {
      if (monitor.runActive) {
        final bool ok = await showNovaConfirm(
          context,
          title: L10n.t('stopConfirmTitle'),
          body: L10n.t('stopConfirmBody'),
          confirmLabel: L10n.t('stop'),
          danger: true,
          icon: Icons.stop_rounded,
        );
        if (!ok || !context.mounted) return;
        monitor.markStopRequested();
        await Provisioner.stopServer(state.api, config);
      } else {
        await Provisioner.startServer(state.api, config);
      }
      if (!context.mounted) return;
      showNovaToast(context, L10n.t('actionQueued'), kind: ToastKind.success);
      await monitor.refresh();
    } catch (error) {
      if (!context.mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.config, required this.monitor, required this.onOpenTab});

  final ServerConfig config;
  final ServerMonitor monitor;
  final ValueChanged<int> onOpenTab;

  Future<void> _action(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      if (!context.mounted) return;
      showNovaToast(context, L10n.t('actionQueued'), kind: ToastKind.success);
      await monitor.refresh();
    } catch (error) {
      if (!context.mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  Future<void> _forceStop(BuildContext context) async {
    final WorkflowRun? run = monitor.run;
    if (run == null) {
      showNovaToast(context, L10n.t('consoleNoRun'), kind: ToastKind.warning);
      return;
    }
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('forceStopConfirmTitle'),
      body: L10n.t('forceStopConfirmBody'),
      confirmLabel: L10n.t('forceStop'),
      danger: true,
      icon: Icons.power_settings_new_rounded,
    );
    if (!ok || !context.mounted) return;
    final AppState state = AppScope.read(context);
    await _action(context, () => state.api.cancelRun(config.repoOwner, config.repoName, run.id));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool online = monitor.phase == ServerPhase.online;
    final bool active = monitor.runActive;
    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: () => monitor.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 28),
        children: <Widget>[
          if (monitor.error != null) ...<Widget>[
            InlineError(message: monitor.error!, onRetry: () => monitor.refresh()),
            const SizedBox(height: 10),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: L10n.t('players'),
                  value: monitor.playersOnline?.toString(),
                  unit: monitor.playersOnline != null && monitor.playersMax != null ? '/ ${monitor.playersMax}' : null,
                  icon: Icons.groups_rounded,
                  accent: p.successBright,
                  unavailableHint: L10n.t('statUnavailable'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: L10n.t('ram'),
                  value: monitor.ramMb?.toString(),
                  unit: 'MB',
                  icon: Icons.memory_rounded,
                  accent: p.violet,
                  unavailableHint: L10n.t('statNotReported'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: L10n.t('ping'),
                  value: monitor.latencyMs?.toString(),
                  unit: 'ms',
                  icon: Icons.speed_rounded,
                  accent: p.cyan,
                  unavailableHint: L10n.t('noAddressConfigured'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: L10n.t('uptime'),
                  value: monitor.uptime == null ? null : Fmt.duration(monitor.uptime),
                  icon: Icons.schedule_rounded,
                  accent: p.warning,
                  unavailableHint: L10n.t('statUnavailable'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AddressPill(
            address: config.connectionHostPort,
            label: L10n.t('serverAddress'),
            onCopy: config.connectionHostPort.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: config.connectionHostPort));
                    showNovaToast(context, L10n.t('addressCopied'), kind: ToastKind.success);
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: NovaButton(
                  label: L10n.t('start'),
                  icon: Icons.play_arrow_rounded,
                  height: 46,
                  onPressed: active || online
                      ? null
                      : () => _action(context, () => Provisioner.startServer(AppScope.read(context).api, config)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NovaButton(
                  label: L10n.t('stop'),
                  icon: Icons.stop_rounded,
                  height: 46,
                  variant: NovaButtonVariant.danger,
                  onPressed: active || online ? () => _toggle(context) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NovaButton(
                  label: L10n.t('restart'),
                  icon: Icons.refresh_rounded,
                  height: 46,
                  variant: NovaButtonVariant.secondary,
                  onPressed: () => _restart(context),
                ),
              ),
            ],
          ),
          if (active) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _forceStop(context),
                icon: Icon(Icons.power_settings_new_rounded, size: 15, color: p.danger),
                label: Text(L10n.t('forceStop'), style: NovaTextStyles.small(p.danger)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.t('serverInfo'),
            icon: Icons.info_outline_rounded,
            actionLabel: L10n.t('edit'),
            onAction: () => onOpenTab(7),
            child: Column(
              children: <Widget>[
                InfoRow(label: L10n.t('versionLabel'), value: config.mcVersion, icon: Icons.sports_esports_rounded),
                InfoRow(label: L10n.t('softwareLabel'), value: Fmt.titleCase(config.software), icon: Icons.widgets_rounded),
                InfoRow(label: L10n.t('editionLabel'), value: config.edition == 'JAVA' ? 'Java' : 'Bedrock', icon: Icons.devices_rounded),
                InfoRow(label: L10n.t('memoryLabel'), value: '${config.memoryMb} MB', icon: Icons.memory_rounded),
                InfoRow(label: L10n.t('repoLabel'), value: config.repoFull, monospace: true, icon: Icons.folder_copy_rounded),
                InfoRow(
                  label: L10n.t('createdLabel'),
                  value: config.createdAt.isEmpty ? '—' : Fmt.dateOnly(DateTime.tryParse(config.createdAt)),
                  icon: Icons.event_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: L10n.t('runsHistory'),
            icon: Icons.history_rounded,
            actionLabel: L10n.t('tabConsole'),
            onAction: () => onOpenTab(1),
            child: Column(
              children: <Widget>[
                InfoRow(
                  label: L10n.t('runStatus'),
                  value: monitor.run == null ? L10n.t('noRunsYet') : '#${monitor.run!.id} · ${monitor.run!.isActive ? L10n.t('starting') : (monitor.run!.conclusion ?? monitor.run!.status)}',
                  icon: Icons.play_circle_outline_rounded,
                  valueColor: active ? p.warning : (monitor.run?.conclusion == 'success' ? p.successBright : null),
                ),
                InfoRow(
                  label: L10n.t('lastUpdated'),
                  value: monitor.lastRefresh == null ? '—' : Fmt.relative(monitor.lastRefresh),
                  icon: Icons.update_rounded,
                ),
                InfoRow(
                  label: L10n.t('runnerHeartbeat'),
                  value: monitor.heartbeat == null
                      ? L10n.t('statNotReported')
                      : (monitor.heartbeatFresh ? L10n.t('heartbeatFresh') : L10n.t('heartbeatStale')),
                  icon: Icons.monitor_heart_rounded,
                  valueColor: monitor.heartbeatFresh ? p.successBright : p.textDim,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: L10n.t('tabBackups'),
            icon: Icons.backup_rounded,
            actionLabel: L10n.t('viewAll'),
            onAction: () => onOpenTab(4),
            child: Column(
              children: <Widget>[
                InfoRow(
                  label: L10n.t('backupLatest'),
                  value: monitor.recentRuns.isEmpty ? L10n.t('backupEmpty') : L10n.t('backupReady'),
                  icon: Icons.inventory_2_rounded,
                ),
                InfoRow(
                  label: L10n.t('worldCurrent'),
                  value: L10n.t('worldSizeHint'),
                  icon: Icons.public_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InfoBanner(
            body: L10n.t('githubRunnersNote'),
            icon: Icons.schedule_rounded,
            color: p.warning,
          ),
        ],
      ),
    );
  }

  Future<void> _restart(BuildContext context) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('restartConfirmTitle'),
      body: L10n.t('restartConfirmBody'),
      confirmLabel: L10n.t('restart'),
    );
    if (!ok || !context.mounted) return;
    await _action(
      context,
      () => Provisioner.restartServer(AppScope.read(context).api, config, activeRun: monitor.runActive),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('stopConfirmTitle'),
      body: L10n.t('stopConfirmBody'),
      confirmLabel: L10n.t('stop'),
      danger: true,
      icon: Icons.stop_rounded,
    );
    if (!ok || !context.mounted) return;
    monitor.markStopRequested();
    await _action(context, () => Provisioner.stopServer(AppScope.read(context).api, config));
  }
}

class _ServerSettingsTab extends StatefulWidget {
  const _ServerSettingsTab({required this.config});

  final ServerConfig config;

  @override
  State<_ServerSettingsTab> createState() => _ServerSettingsTabState();
}

class _ServerSettingsTabState extends State<_ServerSettingsTab> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _motd = TextEditingController();
  final TextEditingController _seed = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _player = TextEditingController();

  String _gamemode = 'survival';
  String _difficulty = 'normal';
  int _players = 20;
  int _viewDistance = 10;
  int _memory = 4096;
  bool _pvp = true;
  bool _whiteList = false;
  bool _onlineMode = true;
  bool _allowCommands = true;
  bool _autoRestart = true;
  int _backupRetention = 10;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ServerConfig c = widget.config;
    _name.text = c.name;
    _motd.text = c.motd;
    _seed.text = c.seed;
    _address.text = c.connectionHostPort;
    _gamemode = c.gamemode;
    _difficulty = c.difficulty;
    _players = c.maxPlayers;
    _viewDistance = c.viewDistance;
    _memory = c.memoryMb;
    _pvp = c.pvp;
    _whiteList = c.whiteList;
    _onlineMode = c.onlineMode;
    _allowCommands = c.allowCommands;
    _autoRestart = c.autoRestart;
    _backupRetention = c.backupRetention;
  }

  @override
  void dispose() {
    _name.dispose();
    _motd.dispose();
    _seed.dispose();
    _address.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String address = _address.text.trim();
      if (address.isNotEmpty && !Validation.parseHostPort(address, widget.config.localPort).isValid) {
        setState(() => _error = L10n.t('addressInvalid'));
        return;
      }
      final AppState state = AppScope.read(context);
      final ServerConfig next = widget.config.copyWith(
        name: _name.text.trim().isEmpty ? widget.config.name : _name.text.trim(),
        motd: _motd.text.trim(),
        seed: _seed.text.trim(),
        playitAddress: address,
        gamemode: _gamemode,
        difficulty: _difficulty,
        maxPlayers: _players,
        viewDistance: _viewDistance,
        simulationDistance: _viewDistance,
        memoryMb: _memory,
        pvp: _pvp,
        whiteList: _whiteList,
        onlineMode: _onlineMode,
        allowCommands: _allowCommands,
        autoRestart: _autoRestart,
        backupRetention: _backupRetention,
      );
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      showNovaToast(context, L10n.t('saveChanges'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendPlayerCommand(String command, String label) async {
    final String name = _player.text.trim();
    if (name.isEmpty) return;
    final bool ok = await showNovaConfirm(
      context,
      title: label,
      body: L10n.f('playerCommandBody', <String, String>{'command': '/$command $name'}),
      confirmLabel: L10n.t('consoleSend'),
      icon: Icons.person_add_alt_1_rounded,
    );
    if (!ok || !mounted) return;
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.sendCommand(
        state.api,
        widget.config,
        '$command $name',
        confirmedDangerous: true,
      );
      if (!mounted) return;
      _player.clear();
      showNovaToast(context, L10n.t('commandQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool java = widget.config.isJava;
    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 28),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        SectionCard(
          title: L10n.t('serverConfig'),
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NovaField(label: L10n.t('serverName'), controller: _name, prefixIcon: Icons.dns_rounded),
              const SizedBox(height: 12),
              NovaField(label: L10n.t('motd'), controller: _motd, prefixIcon: Icons.chat_bubble_outline_rounded),
              const SizedBox(height: 12),
              NovaField(
                label: L10n.t('serverAddress'),
                controller: _address,
                prefixIcon: Icons.hub_rounded,
                hint: 'your-tunnel.playit.gg',
                helper: L10n.t('addressFromConfig'),
              ),
              const SizedBox(height: 12),
              NovaSliderTile(
                label: L10n.t('maxPlayers'),
                value: _players.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                icon: Icons.groups_rounded,
                onChanged: (double v) => setState(() => _players = v.round()),
              ),
              NovaSliderTile(
                label: L10n.t('viewDistance'),
                value: _viewDistance.toDouble(),
                min: 2,
                max: 32,
                divisions: 30,
                icon: Icons.visibility_rounded,
                onChanged: (double v) => setState(() => _viewDistance = v.round()),
              ),
              NovaSliderTile(
                label: L10n.t('memory'),
                value: _memory.toDouble(),
                min: 1024,
                max: 8192,
                divisions: 7,
                suffix: ' MB',
                icon: Icons.memory_rounded,
                onChanged: (double v) => setState(() => _memory = v.round()),
              ),
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
              const SizedBox(height: 8),
              NovaField(label: L10n.t('seed'), controller: _seed, prefixIcon: Icons.grass_rounded, hint: L10n.t('optional')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: L10n.t('serverConfigSub'),
          icon: Icons.rule_rounded,
          child: Column(
            children: <Widget>[
              NovaSwitchTile(title: L10n.t('pvpLabel'), value: _pvp, onChanged: (bool v) => setState(() => _pvp = v), icon: Icons.sports_martial_arts_rounded, padding: const EdgeInsets.symmetric(vertical: 2)),
              NovaSwitchTile(title: L10n.t('whitelist'), subtitle: L10n.t('whitelistHint'), value: _whiteList, onChanged: (bool v) => setState(() => _whiteList = v), icon: Icons.verified_user_rounded, padding: const EdgeInsets.symmetric(vertical: 2)),
              if (java)
                NovaSwitchTile(title: L10n.t('onlineMode'), subtitle: L10n.t('onlineModeHint'), value: _onlineMode, onChanged: (bool v) => setState(() => _onlineMode = v), icon: Icons.public_rounded, padding: const EdgeInsets.symmetric(vertical: 2)),
              NovaSwitchTile(title: L10n.t('allowCommands'), value: _allowCommands, onChanged: (bool v) => setState(() => _allowCommands = v), icon: Icons.terminal_rounded, padding: const EdgeInsets.symmetric(vertical: 2)),
              NovaSwitchTile(title: L10n.t('autoRestart'), subtitle: L10n.t('githubRunnersNote'), value: _autoRestart, onChanged: (bool v) => setState(() => _autoRestart = v), icon: Icons.sync_rounded, padding: const EdgeInsets.symmetric(vertical: 2)),
              NovaSliderTile(
                label: L10n.t('backupRetention'),
                value: _backupRetention.toDouble(),
                min: 2,
                max: 30,
                divisions: 28,
                suffix: '',
                icon: Icons.history_rounded,
                onChanged: (double value) => setState(() => _backupRetention = value.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...<Widget>[
          InlineError(message: _error!, onRetry: _save),
          const SizedBox(height: 10),
        ],
        NovaButton(
          label: L10n.t('saveChanges'),
          icon: Icons.save_rounded,
          loading: _saving,
          onPressed: _saving ? null : _save,
          height: 52,
        ),
        const SizedBox(height: 8),
        Text(L10n.t('serverConfigSub'), textAlign: TextAlign.center, style: NovaTextStyles.caption(p.textDim)),
        const SizedBox(height: 20),
        SectionHeader(title: L10n.t('managePlayers'), subtitle: L10n.t('playersHint'), icon: Icons.groups_rounded),
        SectionCard(
          title: L10n.t('managePlayers'),
          icon: Icons.person_add_alt_1_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NovaField(
                controller: _player,
                hint: L10n.t('playerNameHint'),
                prefixIcon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  NovaButton(
                    label: L10n.t('addToWhitelist'),
                    icon: Icons.playlist_add_check_rounded,
                    size: NovaButtonSize.compact,
                    expand: false,
                    variant: NovaButtonVariant.secondary,
                    onPressed: () => _sendPlayerCommand('whitelist add', L10n.t('addToWhitelist')),
                  ),
                  NovaButton(
                    label: L10n.t('makeOperator'),
                    icon: Icons.military_tech_rounded,
                    size: NovaButtonSize.compact,
                    expand: false,
                    variant: NovaButtonVariant.secondary,
                    onPressed: () => _sendPlayerCommand('op', L10n.t('makeOperator')),
                  ),
                  NovaButton(
                    label: L10n.t('banPlayer'),
                    icon: Icons.block_rounded,
                    size: NovaButtonSize.compact,
                    expand: false,
                    variant: NovaButtonVariant.danger,
                    onPressed: () => _sendPlayerCommand('ban', L10n.t('banPlayer')),
                  ),
                  NovaButton(
                    label: L10n.t('pardonPlayer'),
                    icon: Icons.lock_open_rounded,
                    size: NovaButtonSize.compact,
                    expand: false,
                    variant: NovaButtonVariant.ghost,
                    onPressed: () => _sendPlayerCommand('pardon', L10n.t('pardonPlayer')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        InfoBanner(body: L10n.t('playersHint'), icon: Icons.info_outline_rounded, color: p.warning),
      ],
    );
  }
}
