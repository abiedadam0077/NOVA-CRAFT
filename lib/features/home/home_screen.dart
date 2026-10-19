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
import '../servers/create_server_screen.dart';

/// The first tab. Deliberately short: identity, real state, address and the
/// three run controls. Files, mods and configuration live in their own tabs.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.active,
    required this.onPickServer,
  });

  final bool active;
  final VoidCallback onPickServer;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final ServerConfig? server = state.selected;
    if (server == null) {
      return SafeArea(
        bottom: false,
        child: EmptyState(
          title: L10n.t('noServersYet'),
          body: L10n.t('firstServerBody'),
          icon: Icons.dns_rounded,
          actionLabel: L10n.t('firstServerTitle'),
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateServerScreen()),
          ),
          artAsset: 'assets/images/hero_castle_card.jpg',
        ),
      );
    }
    return MonitorScope(
      config: server,
      active: active,
      interval: const Duration(seconds: 10),
      builder: (BuildContext context, ServerMonitor monitor) {
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: monitor.refresh,
            color: context.nova.primaryBright,
            backgroundColor: context.nova.card,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 130),
              children: <Widget>[
                _HomeHeader(server: server, onPickServer: onPickServer, serverCount: state.servers.length),
                const SizedBox(height: NovaSpace.lg),
                _ServerHero(server: server, monitor: monitor),
                if (!server.eulaAccepted && server.isJava) ...<Widget>[
                  const SizedBox(height: NovaSpace.md),
                  InfoBanner(
                    title: L10n.t('eulaSectionTitle'),
                    body: L10n.t('eulaNotAccepted'),
                    icon: Icons.gavel_rounded,
                    color: context.nova.warning,
                  ),
                ],
                const SizedBox(height: NovaSpace.lg),
                _RunControls(server: server, monitor: monitor),
                const SizedBox(height: NovaSpace.lg),
                _ConnectionCard(server: server, monitor: monitor),
                const SizedBox(height: NovaSpace.lg),
                _VitalsRow(server: server, monitor: monitor),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.server, required this.onPickServer, required this.serverCount});

  final ServerConfig server;
  final VoidCallback onPickServer;
  final int serverCount;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final AppState state = AppScope.of(context);
    return Row(
      children: <Widget>[
        const LogoMark(size: 38, glow: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('NOVA CRAFT', style: TextStyle(fontFamily: 'Oxanium', fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 14)),
              Text(
                '${L10n.t('appTagline')} · ${state.user?.login ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaTextStyles.caption(p.textDim),
              ),
            ],
          ),
        ),
        if (serverCount > 1)
          PressableScale(
            onTap: onPickServer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.cardSoft,
                borderRadius: NovaRadii.rSm,
                border: Border.all(color: p.stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.swap_horiz_rounded, size: 16, color: p.primaryBright),
                  const SizedBox(width: 6),
                  Text('$serverCount', style: NovaTextStyles.monoStrong(12, p.textMuted)),
                ],
              ),
            ),
          ),
        const SizedBox(width: 8),
        PressableScale(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
          child: AvatarBadge(name: state.user?.login ?? 'N', imageUrl: state.user?.avatarUrl, size: 38),
        ),
      ],
    );
  }
}

class _ServerHero extends StatelessWidget {
  const _ServerHero({required this.server, required this.monitor});

  final ServerConfig server;
  final ServerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool online = monitor.phase == ServerPhase.online;
    final bool starting = monitor.phase == ServerPhase.starting;
    final int? players = monitor.playersOnline;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: NovaRadii.rXl,
        border: Border.all(
          color: online ? p.success.withValues(alpha: 0.4) : p.primary.withValues(alpha: 0.22),
        ),
        boxShadow: NovaShadows.lifted(p),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset('assets/images/hero_strip.jpg', fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        p.bg.withValues(alpha: 0.08),
                        p.card.withValues(alpha: 0.58),
                        p.card,
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: StatusPill(phase: monitor.phase, dense: true),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTextStyles.heading(22, p.text),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    SoftChip(label: server.mcVersion.isEmpty ? '—' : server.mcVersion, color: p.primaryBright, icon: Icons.terminal_rounded),
                    SoftChip(label: server.softwareLabel, color: p.violet, icon: Icons.memory_rounded),
                    if (online && players != null)
                      SoftChip(label: '$players/${server.maxPlayers}', color: p.successBright, icon: Icons.people_alt_rounded),
                    if (starting)
                      SoftChip(label: L10n.t('starting'), color: p.warning, icon: Icons.hourglass_top_rounded),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunControls extends StatefulWidget {
  const _RunControls({required this.server, required this.monitor});

  final ServerConfig server;
  final ServerMonitor monitor;

  @override
  State<_RunControls> createState() => _RunControlsState();
}

class _RunControlsState extends State<_RunControls> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String key) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showNovaToast(context, L10n.t(key), kind: ToastKind.success);
      await widget.monitor.refresh();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (!widget.server.eulaAccepted && widget.server.isJava) {
      showNovaToast(context, L10n.t('eulaNotAccepted'), kind: ToastKind.warning);
      return;
    }
    await _run(
      () => Provisioner.startServer(AppScope.read(context).api, widget.server),
      'actionQueued',
    );
  }

  Future<void> _stop() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('stopConfirmTitle'),
      body: L10n.t('stopConfirmBody'),
      confirmLabel: L10n.t('stop'),
      danger: true,
      icon: Icons.stop_rounded,
    );
    if (!ok || !mounted) return;
    widget.monitor.markStopRequested();
    await _run(
      () => Provisioner.stopServer(AppScope.read(context).api, widget.server),
      'actionQueued',
    );
  }

  Future<void> _restart() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('restartConfirmTitle'),
      body: L10n.t('restartConfirmBody'),
      confirmLabel: L10n.t('restart'),
      icon: Icons.restart_alt_rounded,
    );
    if (!ok || !mounted) return;
    await _run(
      () => Provisioner.restartServer(
        AppScope.read(context).api,
        widget.server,
        activeRun: widget.monitor.runActive,
      ),
      'actionQueued',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerMonitor m = widget.monitor;
    final bool online = m.phase == ServerPhase.online;
    final bool running = m.runActive || online || m.phase == ServerPhase.starting || m.phase == ServerPhase.stopping;
    final bool canStart = !running;

    return Row(
      children: <Widget>[
        Expanded(
          child: NovaButton(
            label: L10n.t('start'),
            icon: Icons.play_arrow_rounded,
            onPressed: (canStart && !_busy) ? _start : null,
            loading: _busy && canStart,
            height: 50,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: NovaButton(
            label: L10n.t('stop'),
            icon: Icons.stop_rounded,
            variant: NovaButtonVariant.danger,
            onPressed: (running && !_busy) ? _stop : null,
            height: 50,
          ),
        ),
        const SizedBox(width: 10),
        NovaIconButton(
          icon: Icons.restart_alt_rounded,
          filled: true,
          size: 50,
          accent: p.violet,
          onTap: _busy ? null : _restart,
          tooltip: L10n.t('restart'),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.server, required this.monitor});

  final ServerConfig server;
  final ServerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerRuntime? runtime = monitor.runtime;
    final String address = monitor.address;
    final String tunnelState = monitor.runtimeFresh ? (runtime?.tunnelStatus ?? 'unknown') : 'unknown';
    final bool tunnelLive = tunnelState == 'connected';

    return NovaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: SectionHeader(title: L10n.t('homeConnection'), icon: Icons.public_rounded)),
              SoftChip(
                label: tunnelLive
                    ? L10n.t('connected')
                    : tunnelState == 'error'
                        ? L10n.t('tunnelInactive')
                        : L10n.t('tunnelUnknown'),
                color: tunnelLive ? p.success : (tunnelState == 'error' ? p.danger : p.textDim),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (server.isJava)
            AddressPill(
              address: address,
              label: '${server.mcVersion} · ${server.softwareLabel}',
              onCopy: () => showNovaToast(context, L10n.t('addressCopied'), kind: ToastKind.success),
            )
          else
            AddressPill(
              address: address,
              label: 'Bedrock UDP ${server.playitBedrockPort}',
              onCopy: () => showNovaToast(context, L10n.t('addressCopied'), kind: ToastKind.success),
            ),
          if (address.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(L10n.t('homeNoAddress'), style: NovaTextStyles.small(p.textDim)),
          ] else if (!tunnelLive) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              monitor.runtimeFresh && (runtime?.tunnelMessage.isNotEmpty ?? false)
                  ? runtime!.tunnelMessage
                  : L10n.t('playitVerifyNote'),
              style: NovaTextStyles.small(p.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

class _VitalsRow extends StatelessWidget {
  const _VitalsRow({required this.server, required this.monitor});

  final ServerConfig server;
  final ServerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerRuntime? runtime = monitor.runtime;
    final bool fresh = monitor.runtimeFresh;
    final List<Widget> tiles = <Widget>[
      _Vital(
        icon: Icons.timer_outlined,
        label: L10n.t('uptime'),
        value: monitor.phase == ServerPhase.online ? Fmt.duration(monitor.uptime) : '—',
      ),
      _Vital(
        icon: Icons.bolt_rounded,
        label: L10n.t('ping'),
        value: monitor.latencyMs == null ? '—' : '${monitor.latencyMs} ms',
      ),
      _Vital(
        icon: Icons.memory_rounded,
        label: L10n.t('memoryLabel'),
        value: runtime?.rssMb == null || !fresh ? '—' : Fmt.mb(runtime!.rssMb),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[for (int i = 0; i < tiles.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ]]),
        const SizedBox(height: NovaSpace.md),
        NovaCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.account_tree_outlined, size: 16, color: p.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L10n.t('homeManagedBy'),
                  style: NovaTextStyles.small(p.textDim),
                ),
              ),
              Text(
                monitor.run == null ? '—' : Fmt.relative(monitor.run!.createdAtDate),
                style: NovaTextStyles.caption(p.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: p.cardSoft,
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: p.primaryBright),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.monoStrong(14, p.text)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.caption(p.textDim)),
        ],
      ),
    );
  }
}
