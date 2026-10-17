import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/formatters.dart';
import '../core/github_api.dart';
import '../core/logs.dart';
import '../core/minecraft_ping.dart';
import '../core/models.dart';
import '../core/provisioner.dart';
import '../core/validation.dart';

/// Live state for one server. Everything shown in the UI is derived from real
/// GitHub data (runs, jobs, heartbeat file) and real protocol pings, or is
/// explicitly `null` when the value is not available.
class ServerMonitor extends ChangeNotifier {
  ServerMonitor({
    required this.api,
    required ServerConfig config,
    this.pollInterval = defaultPollInterval,
  }) : _config = config;

  final GitHubApi api;
  ServerConfig _config;

  ServerConfig get config => _config;
  set config(ServerConfig value) {
    if (value.repoFull != _config.repoFull) {
      run = null;
      jobs = <WorkflowJob>[];
      heartbeat = null;
      ping = null;
      logs = null;
      logsRunId = null;
    }
    _config = value;
    notifyListeners();
  }

  WorkflowRun? run;
  List<WorkflowRun> recentRuns = <WorkflowRun>[];
  List<WorkflowJob> jobs = <WorkflowJob>[];
  RunnerHeartbeat? heartbeat;
  PingResult? ping;
  String? logs;
  int? logsRunId;

  bool loading = true;
  bool refreshing = false;
  bool loadingLogs = false;
  String? error;
  String? logsError;
  DateTime? lastRefresh;
  bool stopRequested = false;

  Timer? _timer;
  bool _disposed = false;

  static const Duration defaultPollInterval = Duration(seconds: 12);

  /// Detail screens poll every 12 s; the servers list uses a slower cadence so
  /// a long list does not burn through the GitHub API rate limit.
  final Duration pollInterval;

  void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  /// Stops background polling while a screen is off-screen.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_timer != null) return;
    start();
  }

  bool get polling => _timer != null;

  Future<void> refresh({bool withPing = true}) async {
    if (_disposed || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      final List<WorkflowRun> runs = await api.listRuns(_config.repoOwner, _config.repoName, workflow: Provisioner.workflowFile);
      final WorkflowRun? next = runs.isNotEmpty ? runs.first : null;
      if (next != null && (next.id != run?.id)) {
        logs = null;
        logsRunId = null;
        logsError = null;
      }
      run = next;
      recentRuns = runs.take(6).toList();
      jobs = <WorkflowJob>[];
      if (run != null) {
        try {
          jobs = await api.listJobs(_config.repoOwner, _config.repoName, run!.id);
        } catch (_) {
          jobs = <WorkflowJob>[];
        }
      }
      heartbeat = await _loadHeartbeat();
      if (withPing) ping = await _ping();
      error = null;
      if (stopRequested && ping?.online != true) stopRequested = false;
    } catch (err) {
      error = Fmt.error(err);
    } finally {
      refreshing = false;
      loading = false;
      lastRefresh = DateTime.now();
      if (!_disposed) notifyListeners();
    }
  }

  Future<RunnerHeartbeat?> _loadHeartbeat() async {
    try {
      final String text = await api.getFileText(_config.repoOwner, _config.repoName, Provisioner.statusPath);
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map) return RunnerHeartbeat.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<PingResult?> _ping() async {
    final String address = _config.connectionHostPort;
    if (address.isEmpty) return null;
    final int defaultPort = _config.isBedrock ? _config.playitBedrockPort : _config.playitJavaPort;
    final HostPort target = Validation.parseHostPort(address, defaultPort);
    if (!target.isValid) return null;
    if (_config.isBedrock) {
      return MinecraftPing.bedrock(host: target.host, port: target.port);
    }
    return MinecraftPing.java(host: target.host, port: target.port);
  }

  Future<void> loadLogs({bool force = false}) async {
    final WorkflowRun? current = run;
    if (current == null || _disposed) return;
    if (!force && logsRunId == current.id) return;
    loadingLogs = true;
    logsError = null;
    notifyListeners();
    try {
      if (current.isCompleted) {
        logs = await api.downloadRunLogs(_config.repoOwner, _config.repoName, current.id);
        logsRunId = current.id;
      } else {
        logs = null;
      }
    } catch (err) {
      logsError = Fmt.error(err);
    } finally {
      loadingLogs = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool get runActive => run?.isActive ?? false;

  bool get heartbeatFresh {
    final DateTime? updated = heartbeat?.updatedAtDate;
    if (updated == null) return false;
    return DateTime.now().difference(updated).inMinutes < 20;
  }

  ServerPhase get phase {
    final bool pingOnline = ping?.online ?? false;
    if (stopRequested && (pingOnline || runActive)) return ServerPhase.stopping;
    if (pingOnline) return ServerPhase.online;
    if (runActive) return ServerPhase.starting;
    if (run != null && run!.isCompleted && (run!.conclusion == 'failure' || run!.conclusion == 'timed_out')) {
      return ServerPhase.error;
    }
    if (run == null) return ServerPhase.unknown;
    return ServerPhase.offline;
  }

  int? get playersOnline => (ping?.online ?? false) ? ping?.playersOnline : null;
  int? get playersMax => (ping?.online ?? false) ? (ping?.playersMax ?? _config.maxPlayers) : _config.maxPlayers;
  int? get latencyMs => (ping?.online ?? false) ? ping?.latencyMs : null;

  /// Process RSS reported by the runner heartbeat. This is not total machine RAM.
  int? get ramMb => heartbeat?.rssMb;

  /// The runner heartbeat does not report CPU usage, so the UI must show "—".
  double? get cpuFraction => null;

  Duration? get uptime {
    final DateTime? started = run?.startedAtDate;
    if (started == null) return null;
    if (!runActive && !heartbeatFresh) return null;
    final Duration value = DateTime.now().difference(started);
    return value.isNegative ? null : value;
  }

  List<LogEntry> buildLogEntries() {
    if (runActive) return LogParser.fromJobs(jobs);
    if (logs != null && logs!.isNotEmpty) return LogParser.fromText(logs!, source: 'logs');
    return LogParser.fromJobs(jobs);
  }

  void markStopRequested() {
    stopRequested = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
