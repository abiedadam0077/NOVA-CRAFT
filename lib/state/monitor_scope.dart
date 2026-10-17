import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import 'app_state.dart';
import 'server_monitor.dart';

/// Owns a [ServerMonitor] for a screen and keeps it in sync with the selected
/// server, pausing polling when the screen is not visible.
class MonitorScope extends StatefulWidget {
  const MonitorScope({
    super.key,
    required this.config,
    required this.builder,
    this.active = true,
    this.autoStart = true,
    this.interval = ServerMonitor.defaultPollInterval,
  });

  final ServerConfig config;
  final Widget Function(BuildContext context, ServerMonitor monitor) builder;
  final bool active;
  final bool autoStart;
  final Duration interval;

  @override
  State<MonitorScope> createState() => _MonitorScopeState();
}

class _MonitorScopeState extends State<MonitorScope> {
  ServerMonitor? _monitor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureMonitor();
  }

  void _ensureMonitor() {
    final AppState state = AppScope.read(context);
    if (_monitor == null || _monitor!.config.repoFull != widget.config.repoFull) {
      _monitor?.dispose();
      _monitor = ServerMonitor(api: state.api, config: widget.config, pollInterval: widget.interval);
      _monitor!.addListener(_onChange);
      if (widget.autoStart && widget.active) _monitor!.start();
    } else if (_monitor!.config != widget.config) {
      _monitor!.config = widget.config;
    }
    if (_monitor!.polling && !widget.active) {
      _monitor!.pause();
    } else if (!_monitor!.polling && widget.active && widget.autoStart) {
      _monitor!.resume();
    }
  }

  @override
  void didUpdateWidget(MonitorScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureMonitor();
    final ServerMonitor? monitor = _monitor;
    if (monitor == null) return;
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        monitor.resume();
      } else {
        monitor.pause();
      }
    }
  }

  void _onChange() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _monitor?.removeListener(_onChange);
    _monitor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ServerMonitor? monitor = _monitor;
    if (monitor == null) return const SizedBox.shrink();
    return widget.builder(context, monitor);
  }
}
