import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/logs.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../state/app_state.dart';
import '../../state/monitor_scope.dart';
import '../../state/server_monitor.dart';

/// The bottom-nav console. When there is no selected server it offers a picker
/// instead of pretending to be connected to anything.
class ConsoleScreen extends StatelessWidget {
  const ConsoleScreen({super.key, required this.active, required this.onPickServer});

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
          title: L10n.t('noServerSelected'),
          body: L10n.t('emptyConsoleTitle'),
          icon: Icons.terminal_rounded,
          actionLabel: L10n.t('navServers'),
          onAction: onPickServer,
          artAsset: 'assets/images/art_island.jpg',
        ),
      );
    }
    return MonitorScope(
      config: server,
      active: active,
      builder: (BuildContext context, ServerMonitor monitor) {
        return SafeArea(
          bottom: false,
          child: ConsoleView(
            config: server,
            monitor: monitor,
            embedded: false,
            onPickServer: onPickServer,
          ),
        );
      },
    );
  }
}

class ConsoleView extends StatefulWidget {
  const ConsoleView({
    super.key,
    required this.config,
    required this.monitor,
    this.embedded = true,
    this.onPickServer,
  });

  final ServerConfig config;
  final ServerMonitor monitor;
  final bool embedded;
  final VoidCallback? onPickServer;

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final TextEditingController _command = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _searchOpen = false;
  bool _follow = true;
  int _lastCount = 0;
  int? _clearedRunId;
  bool _sending = false;

  @override
  void dispose() {
    _command.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_follow || !_scroll.hasClients) return;
      final double max = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - max).abs() > 4) {
        _scroll.jumpTo(max);
      }
    });
  }

  Future<void> _send() async {
    final String text = _command.text.trim();
    if (text.isEmpty || _sending) return;
    if (Validation.isDangerousCommand(text)) {
      final bool ok = await showNovaConfirm(
        context,
        title: L10n.t('dangerCommandTitle'),
        body: L10n.t('dangerCommandBody'),
        confirmLabel: L10n.t('consoleSend'),
        danger: true,
        icon: Icons.warning_amber_rounded,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _sending = true);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.sendCommand(state.api, widget.config, text);
      if (!mounted) return;
      _command.clear();
      HapticFeedback.selectionClick();
      showNovaToast(context, L10n.t('commandQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _levelColor(LogLevel level) {
    final p = context.nova;
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFFF6B6B);
      case LogLevel.warn:
        return const Color(0xFFFFC466);
      case LogLevel.success:
        return const Color(0xFF5BE49B);
      case LogLevel.command:
        return const Color(0xFF5FD4FF);
      case LogLevel.debug:
        return const Color(0xFF8FA3C8);
      case LogLevel.step:
        return p.violet;
      case LogLevel.info:
        return const Color(0xFFC9D6F2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final ServerMonitor monitor = widget.monitor;
    final List<LogEntry> raw = monitor.buildLogEntries();
    final bool cleared = _clearedRunId != null && _clearedRunId == monitor.run?.id;
    final String q = _search.text.trim().toLowerCase();
    final List<LogEntry> entries = (cleared ? <LogEntry>[] : raw)
        .where((LogEntry e) => q.isEmpty || e.text.toLowerCase().contains(q))
        .toList();
    if (entries.length != _lastCount) {
      _lastCount = entries.length;
      _scheduleScroll();
    }

    final Widget header = _ConsoleHeader(
      monitor: monitor,
      follow: _follow,
      onToggleFollow: () => setState(() => _follow = !_follow),
      searchOpen: _searchOpen,
      onToggleSearch: () => setState(() {
        _searchOpen = !_searchOpen;
        if (!_searchOpen) _search.clear();
      }),
      onClear: () => setState(() => _clearedRunId = monitor.run?.id),
      onJump: () {
        setState(() => _follow = true);
        _scheduleScroll();
      },
      onCopy: entries.isEmpty
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: entries.map((LogEntry e) => e.text).join('\n')));
              showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
            },
    );

    final Widget terminal = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF05080F),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: p.stroke),
        boxShadow: NovaShadows.soft(p),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0A101F),
              border: Border(bottom: BorderSide(color: Color(0xFF1A2540))),
            ),
            child: Row(
              children: <Widget>[
                _Dot(color: const Color(0xFFFF5F57)),
                _Dot(color: const Color(0xFFFEBC2E)),
                _Dot(color: const Color(0xFF28C840)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.config.repoName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'PlexMono',
                      fontSize: 10,
                      color: Color(0xFF6E82A8),
                    ),
                  ),
                ),
                Text(
                  '${entries.length} ${L10n.t('consoleLines')}',
                  style: const TextStyle(fontFamily: 'PlexMono', fontSize: 9.5, color: Color(0xFF6E82A8)),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? _ConsolePlaceholder(monitor: monitor, cleared: cleared)
                : NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      if (notification is UserScrollNotification || notification is ScrollUpdateNotification) {
                        final bool atBottom = notification.metrics.extentAfter < 24;
                        if (atBottom != _follow) setState(() => _follow = atBottom);
                      }
                      return false;
                    },
                    child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: entries.length,
                      itemBuilder: (BuildContext context, int i) {
                        final LogEntry e = entries[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                if (e.timestamp != null)
                                  TextSpan(
                                    text: '${e.timestamp} ',
                                    style: const TextStyle(color: Color(0xFF51648A), fontSize: 10.5),
                                  ),
                                TextSpan(text: e.text),
                              ],
                            ),
                            style: TextStyle(
                              fontFamily: 'PlexMono',
                              fontSize: 11,
                              height: 1.45,
                              color: _levelColor(e.level),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  ),
          ),
        ],
      ),
    );

    final Widget commandBar = Row(
      children: <Widget>[
        Expanded(
          child: NovaField(
            controller: _command,
            hint: L10n.t('consoleCommandHint'),
            prefixIcon: Icons.chevron_right_rounded,
            monospace: true,
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          height: 52,
          child: NovaIconButton(
            icon: Icons.send_rounded,
            size: 52,
            iconSize: 21,
            filled: true,
            onTap: _sending ? null : _send,
            tooltip: L10n.t('consoleSend'),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: <Widget>[
          header,
          if (_searchOpen) ...<Widget>[
            const SizedBox(height: 10),
            NovaSearchField(
              controller: _search,
              hint: L10n.t('consoleSearch'),
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() => _search.clear()),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(height: 430, child: terminal),
          const SizedBox(height: 10),
          commandBar,
          const SizedBox(height: 8),
          const _QueueNote(),
          const SizedBox(height: 14),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 6, NovaSpace.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(L10n.t('consoleTitle'), style: NovaTextStyles.display(24, p.text)),
                    const SizedBox(height: 2),
                    Text(
                      widget.config.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTextStyles.small(p.textMuted),
                    ),
                  ],
                ),
              ),
              if (widget.onPickServer != null)
                NovaIconButton(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: L10n.t('selectServer'),
                  onTap: widget.onPickServer,
                ),
            ],
          ),
          const SizedBox(height: 10),
          header,
          if (_searchOpen) ...<Widget>[
            const SizedBox(height: 8),
            NovaSearchField(
              controller: _search,
              hint: L10n.t('consoleSearch'),
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() => _search.clear()),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(child: terminal),
          const SizedBox(height: 10),
          commandBar,
          const SizedBox(height: 8),
          const _QueueNote(),
          SizedBox(height: MediaQuery.viewInsetsOf(context).bottom + 96),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsetsDirectional.only(end: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.8), shape: BoxShape.circle),
    );
  }
}

class _QueueNote extends StatelessWidget {
  const _QueueNote();

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      children: <Widget>[
        Icon(Icons.schedule_rounded, size: 12, color: p.textDim),
        const SizedBox(width: 5),
        Expanded(
          child: Text(L10n.t('consoleFollow'), style: NovaTextStyles.caption(p.textDim)),
        ),
      ],
    );
  }
}

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.monitor,
    required this.follow,
    required this.onToggleFollow,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.onClear,
    required this.onJump,
    required this.onCopy,
  });

  final ServerMonitor monitor;
  final bool follow;
  final VoidCallback onToggleFollow;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final VoidCallback onClear;
  final VoidCallback onJump;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      children: <Widget>[
        Pill(
          label: L10n.t('consolePolling'),
          tone: PillTone.primary,
          icon: Icons.sync_rounded,
          dense: true,
          pulse: monitor.runActive,
        ),
        const SizedBox(width: 8),
        if (monitor.lastRefresh != null)
          Flexible(
            child: Text(
              '${L10n.t('lastUpdated')} ${Fmt.relative(monitor.lastRefresh)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NovaTextStyles.caption(p.textDim),
            ),
          ),
        const Spacer(),
        NovaChip(
          label: L10n.t('consoleFollow'),
          selected: follow,
          icon: Icons.vertical_align_bottom_rounded,
          onTap: onToggleFollow,
        ),
        const SizedBox(width: 6),
        NovaIconButton(
          icon: Icons.search_rounded,
          size: 34,
          iconSize: 17,
          filled: searchOpen,
          onTap: onToggleSearch,
          tooltip: L10n.t('consoleSearch'),
        ),
        const SizedBox(width: 6),
        NovaIconButton(
          icon: Icons.copy_rounded,
          size: 34,
          iconSize: 16,
          onTap: onCopy,
          tooltip: L10n.t('copy'),
        ),
        const SizedBox(width: 6),
        NovaIconButton(
          icon: Icons.delete_sweep_rounded,
          size: 34,
          iconSize: 17,
          onTap: onClear,
          tooltip: L10n.t('consoleClear'),
        ),
        const SizedBox(width: 6),
        NovaIconButton(
          icon: Icons.vertical_align_bottom_rounded,
          size: 34,
          iconSize: 17,
          onTap: onJump,
          tooltip: L10n.t('consoleJumpLatest'),
        ),
        const SizedBox(width: 6),
        NovaIconButton(
          icon: Icons.refresh_rounded,
          size: 34,
          iconSize: 17,
          onTap: () {
            monitor.refresh();
            monitor.loadLogs(force: true);
          },
          tooltip: L10n.t('refresh'),
        ),
      ],
    );
  }
}

class _ConsolePlaceholder extends StatelessWidget {
  const _ConsolePlaceholder({required this.monitor, required this.cleared});

  final ServerMonitor monitor;
  final bool cleared;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (cleared) {
      text = L10n.t('consoleCleared');
    } else if (monitor.loadingLogs) {
      text = L10n.t('loading');
    } else if (monitor.run == null) {
      text = L10n.t('consoleNoRun');
    } else if (monitor.runActive) {
      text = L10n.t('consoleRunActive');
    } else if (monitor.liveLog == null) {
      text = monitor.logsError ?? L10n.t('consoleStopped');
    } else {
      text = L10n.t('consoleRunCompleted');
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (monitor.loadingLogs) ...<Widget>[
              const SizedBox(width: 22, height: 22, child: NovaLoader(size: 22, stroke: 2)),
              const SizedBox(height: 12),
            ] else
              const Icon(Icons.terminal_rounded, size: 26, color: Color(0xFF3E5277)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'PlexMono', fontSize: 11, color: Color(0xFF6E82A8)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: <Widget>[
                _hint(L10n.t('consoleSourceSteps')),
                _hint(L10n.t('consoleSource')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF101A2E),
        borderRadius: NovaRadii.rPill,
        border: Border.all(color: const Color(0xFF1E2C49)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontFamily: 'PlexMono', fontSize: 9, color: Color(0xFF7C91B8)),
      ),
    );
  }
}
