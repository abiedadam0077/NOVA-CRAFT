import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/monitor_scope.dart';
import '../../state/server_monitor.dart';
import '../account/account_screen.dart';
import '../servers/server_detail_screen.dart';
import '../servers/create_server_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.active, required this.onOpenServers});

  final bool active;
  final VoidCallback onOpenServers;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _requestedRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestedRefresh) {
      _requestedRefresh = true;
      final AppState state = AppScope.read(context);
      if (state.signedIn && state.servers.isEmpty && !state.loadingServers) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) state.refreshServers();
        });
      }
    }
  }

  String _greeting() {
    final int hour = DateTime.now().hour;
    return hour < 12 ? L10n.t('greetingMorning') : L10n.t('greetingEvening');
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    final ServerConfig? server = state.selected;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: p.primaryBright,
        backgroundColor: p.cardHigh,
        onRefresh: () async {
          await Future.wait(<Future<void>>[state.refreshServers(), state.refreshUser()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 130),
          children: <Widget>[
            _Header(state: state, onOpenServers: widget.onOpenServers),
            const SizedBox(height: 20),
            Text(
              _greeting(),
              style: NovaTextStyles.display(25, p.text),
            ),
            const SizedBox(height: 2),
            Text(L10n.t('dashboardSubtitle'), style: NovaTextStyles.small(p.textMuted)),
            const SizedBox(height: 18),
            if (state.loadingServers && state.servers.isEmpty)
              const SkeletonList(count: 2, cardHeight: 180)
            else if (server == null)
              _NoServerCard(onCreate: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreateServerScreen())), onBrowse: widget.onOpenServers)
            else
              MonitorScope(
                config: server,
                active: widget.active,
                builder: (BuildContext context, ServerMonitor monitor) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ServerHero(
                      server: server,
                      monitor: monitor,
                      onOpen: () => _openServer(context, server, 0),
                      onTab: (int tab) => _openServer(context, server, tab),
                    ),
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: L10n.t('quickActions'),
                      eyebrow: 'NOVA CRAFT',
                      icon: Icons.bolt_rounded,
                    ),
                    _QuickActions(server: server),
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: L10n.t('recentActivity'),
                      icon: Icons.history_rounded,
                      actionLabel: L10n.t('viewAll'),
                      onAction: () => _openServer(context, server, 0),
                    ),
                    _RecentRuns(monitor: monitor),
                    const SizedBox(height: 18),
                    InfoBanner(
                      body: L10n.t('githubRunnersNote'),
                      icon: Icons.info_outline_rounded,
                      color: p.warning,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openServer(BuildContext context, ServerConfig server, int tab) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServerDetailScreen(config: server, initialTab: tab),
    ));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onOpenServers});

  final AppState state;
  final VoidCallback onOpenServers;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      children: <Widget>[
        const BrandLockup(markSize: 32, fontSize: 15, letterSpacing: 2.4),
        const Spacer(),
        NovaIconButton(
          icon: Icons.dns_rounded,
          size: 38,
          iconSize: 18,
          onTap: onOpenServers,
          tooltip: L10n.t('myServers'),
        ),
        const SizedBox(width: 8),
        PressableScale(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
          child: AvatarBadge(
            name: state.user?.login ?? 'N',
            imageUrl: state.user?.avatarUrl,
            size: 38,
          ),
        ),
      ],
    );
  }
}

class _ServerHero extends StatelessWidget {
  const _ServerHero({
    required this.server,
    required this.monitor,
    required this.onOpen,
    required this.onTab,
  });

  final ServerConfig server;
  final ServerMonitor monitor;
  final VoidCallback onOpen;
  final ValueChanged<int> onTab;

  Future<void> _run(BuildContext context, Future<void> Function() action, String successKey) async {
    try {
      await action();
      if (!context.mounted) return;
      showNovaToast(context, L10n.t(successKey), kind: ToastKind.success);
      await monitor.refresh();
    } catch (error) {
      if (!context.mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  Future<void> _stop(BuildContext context) async {
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
    await _run(context, () => Provisioner.stopServer(AppScope.read(context).api, server), 'actionQueued');
  }

  Future<void> _restart(BuildContext context) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('restartConfirmTitle'),
      body: L10n.t('restartConfirmBody'),
      confirmLabel: L10n.t('restart'),
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => Provisioner.restartServer(AppScope.read(context).api, server, activeRun: monitor.runActive),
      'actionQueued',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerPhase phase = monitor.phase;
    final bool online = phase == ServerPhase.online;
    final bool busy = monitor.refreshing && monitor.loading;
    final bool canStart = !monitor.runActive && !online;
    final bool canInteract = monitor.runActive || online || phase == ServerPhase.starting;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: NovaRadii.rXl,
        border: Border.all(color: online ? p.success.withValues(alpha: 0.35) : p.strokeStrong.withValues(alpha: 0.35)),
        boxShadow: NovaShadows.lifted(p),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Stack(
            children: <Widget>[
              SizedBox(
                height: 168,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/hero_strip.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(gradient: NovaGradients.heroScrim)),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          StatusPill(phase: phase, dense: true),
                          const Spacer(),
                          if (monitor.refreshing)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(end: 8),
                              child: SizedBox(width: 16, height: 16, child: NovaLoader(size: 16, stroke: 2)),
                            ),
                          NovaIconButton(
                            icon: Icons.refresh_rounded,
                            size: 32,
                            iconSize: 16,
                            onTap: () => monitor.refresh(),
                            tooltip: L10n.t('refresh'),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          ServerAvatar(
                            name: server.name,
                            size: 56,
                            edition: server.edition,
                            software: server.software,
                            online: online,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  server.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NovaTextStyles.display(24, Colors.white),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${server.edition == 'JAVA' ? 'Java' : 'Bedrock'} ${server.mcVersion}  ·  ${Fmt.titleCase(server.software)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NovaTextStyles.small(const Color(0xFFB9C7E8)),
                                ),
                              ],
                            ),
                          ),
                          PressableScale(
                            onTap: onOpen,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: NovaRadii.rSm,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                              ),
                              child: const Icon(Icons.open_in_full_rounded, size: 17, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: L10n.t('players'),
                        value: monitor.playersOnline?.toString(),
                        unit: monitor.playersOnline != null && monitor.playersMax != null ? '/ ${monitor.playersMax}' : null,
                        icon: Icons.groups_rounded,
                        accent: p.successBright,
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AddressPill(
                  address: server.connectionHostPort,
                  label: L10n.t('serverAddress'),
                  onCopy: () => showNovaToast(context, L10n.t('addressCopied'), kind: ToastKind.success),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: NovaButton(
                        label: L10n.t('start'),
                        icon: Icons.play_arrow_rounded,
                        height: 50,
                        loading: false,
                        onPressed: canStart
                            ? () => _run(context, () => Provisioner.startServer(AppScope.read(context).api, server), 'actionQueued')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: NovaButton(
                        label: L10n.t('stop'),
                        icon: Icons.stop_rounded,
                        variant: NovaButtonVariant.danger,
                        height: 50,
                        onPressed: canInteract ? () => _stop(context) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: NovaButton(
                        label: L10n.t('restart'),
                        icon: Icons.refresh_rounded,
                        variant: NovaButtonVariant.secondary,
                        height: 50,
                        onPressed: () => _restart(context),
                      ),
                    ),
                  ],
                ),
                if (busy) ...<Widget>[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.server});

  final ServerConfig server;

  @override
  Widget build(BuildContext context) {
    final List<_QuickActionData> actions = <_QuickActionData>[
      _QuickActionData(L10n.t('tabConsole'), Icons.terminal_rounded, 1, const Color(0xFF22D3EE)),
      _QuickActionData(L10n.t('tabFiles'), Icons.folder_copy_rounded, 2, const Color(0xFF3B82F6)),
      _QuickActionData(L10n.t('tabMods'), Icons.extension_rounded, 3, const Color(0xFFA855F7)),
      _QuickActionData(L10n.t('tabBackups'), Icons.backup_rounded, 4, const Color(0xFF22C55E)),
      _QuickActionData(L10n.t('tabWorlds'), Icons.public_rounded, 5, const Color(0xFFF59E0B)),
      _QuickActionData(L10n.t('tabNetwork'), Icons.hub_rounded, 6, const Color(0xFF818CF8)),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.02,
      children: actions
          .map((_QuickActionData action) => PressableScale(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ServerDetailScreen(config: server, initialTab: action.tab),
                )),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: NovaGradients.card(context.nova),
                    borderRadius: NovaRadii.rLg,
                    border: Border.all(color: context.nova.stroke),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: action.color.withValues(alpha: 0.14),
                          borderRadius: NovaRadii.rSm,
                          border: Border.all(color: action.color.withValues(alpha: 0.28)),
                        ),
                        child: Icon(action.icon, size: 20, color: action.color),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTextStyles.smallStrong(context.nova.text).copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _QuickActionData {
  const _QuickActionData(this.label, this.icon, this.tab, this.color);

  final String label;
  final IconData icon;
  final int tab;
  final Color color;
}

class _RecentRuns extends StatelessWidget {
  const _RecentRuns({required this.monitor});

  final ServerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    if (monitor.loading && monitor.recentRuns.isEmpty) {
      return const SkeletonList(count: 2, cardHeight: 72);
    }
    if (monitor.recentRuns.isEmpty) {
      return NovaCard(
        onTap: null,
        child: Row(
          children: <Widget>[
            Icon(Icons.history_rounded, size: 18, color: p.textDim),
            const SizedBox(width: 10),
            Expanded(child: Text(L10n.t('noRunsYet'), style: NovaTextStyles.small(p.textMuted))),
          ],
        ),
      );
    }
    return Column(
      children: monitor.recentRuns.take(4).map((WorkflowRun run) {
        final bool success = run.conclusion == 'success';
        final bool failed = run.conclusion == 'failure' || run.conclusion == 'timed_out' || run.conclusion == 'cancelled';
        final Color color = run.isActive ? p.warning : (success ? p.success : (failed ? p.danger : p.textDim));
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.cardSoft.withValues(alpha: 0.8),
            borderRadius: NovaRadii.md,
            border: Border.all(color: p.stroke),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      run.isActive ? L10n.t('starting') : (run.conclusion ?? run.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTextStyles.smallStrong(color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${run.id} · ${Fmt.relative(run.createdAtDate)}',
                      style: NovaTextStyles.small(p.textDim).copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                Fmt.shortSha(run.headSha),
                style: NovaTextStyles.mono(10.5, p.textDim),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _NoServerCard extends StatelessWidget {
  const _NoServerCard({required this.onCreate, required this.onBrowse});

  final VoidCallback onCreate;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rXl,
        border: Border.all(color: p.stroke),
        boxShadow: NovaShadows.soft(p),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ArtBanner(
            asset: 'assets/images/art_island.jpg',
            height: 190,
            radius: 0,
            alignment: Alignment.center,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  L10n.t('noServersTitle'),
                  style: NovaTextStyles.display(22, Colors.white),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Text(
                  L10n.t('noServersBody'),
                  textAlign: TextAlign.center,
                  style: NovaTextStyles.small(p.textMuted),
                ),
                const SizedBox(height: 16),
                NovaButton(label: L10n.t('createServer'), icon: Icons.add_rounded, onPressed: onCreate),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onBrowse,
                  child: Text(L10n.t('myServers'), style: NovaTextStyles.smallStrong(p.primaryBright)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
