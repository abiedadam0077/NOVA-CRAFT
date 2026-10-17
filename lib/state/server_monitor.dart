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
      runtime = null;
      liveLog = null;
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
  ServerRuntime? runtime;
  PingResult? ping;

  /// The real log tail that the runner publishes while the server is up.
  String? liveLog;
  DateTime? liveLogAt;

  /// GitHub's full step log, only available once a run has finished.
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
      runtime = await _loadRuntime();
      if (runActive) await _loadLiveLog();
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

  Future<ServerRuntime?> _loadRuntime() async {
    try {
      final String text = await api.getFileText(_config.repoOwner, _config.repoName, Provisioner.statusPath);
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map) {
        final ServerRuntime value = ServerRuntime.fromJson(Map<String, dynamic>.from(decoded));
        // A stale heartbeat from a previous cycle must not look live.
        final DateTime? at = value.updatedAtDate;
        if (at != null && DateTime.now().difference(at).inMinutes > 15) {
          return value.phase == 'ready' ? value : value;
        }
        return value;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _loadLiveLog() async {
    try {
      final String text = await api.getFileText(_config.repoOwner, _config.repoName, Provisioner.liveLogPath);
      if (text.trim().isNotEmpty) {
        liveLog = text;
        liveLogAt = DateTime.now();
      }
    } catch (_) {
      // 404 until the runner publishes its first tail.
    }
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
        await _loadLiveLog();
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
    final DateTime? updated = runtime?.updatedAtDate;
    if (updated == null) return false;
    return DateTime.now().difference(updated).inMinutes < 20;
  }

  /// Backwards-compatible view used by older screens.
  RunnerHeartbeat? get heartbeat {
    final ServerRuntime? value = runtime;
    if (value == null) return null;
    return RunnerHeartbeat(
      serverId: _config.id,
      updatedAt: value.updatedAt,
      serverProcessRssKb: (value.rssMb ?? 0) * 1024,
      runnerFreeMb: 0,
      raw: <String, dynamic>{},
    );
  }

  /// True only when the runner itself says the world is loaded and accepting
  /// players *and* that report is recent. Workflow status alone is never
  /// treated as "online".
  bool get runtimeFresh {
    final ServerRuntime? value = runtime;
    if (value == null) return false;
    final DateTime? at = value.updatedAtDate;
    if (at == null) return false;
    return DateTime.now().difference(at).inMinutes < 6;
  }

  ServerPhase get phase {
    final bool pingOnline = ping?.online ?? false;
    if (stopRequested) return ServerPhase.stopping;
    if (pingOnline) return ServerPhase.online;
    if (runtimeFresh && (runtime?.ready ?? false) && tunnelConnected) return ServerPhase.online;
    if (runtimeFresh && (runtime?.ready ?? false)) return ServerPhase.starting;
    if (runActive) return ServerPhase.starting;
    if (run != null && run!.isCompleted && (run!.conclusion == 'failure' || run!.conclusion == 'timed_out')) {
      return ServerPhase.error;
    }
    if (run == null) return ServerPhase.unknown;
    return ServerPhase.offline;
  }

  bool get tunnelConnected => runtimeFresh && (runtime?.tunnelConnected ?? false);

  /// Configured address first, then the address the agent actually reported.
  String get address {
    final String configured = _config.connectionHostPort;
    if (configured.isNotEmpty) return configured;
    final String reported = runtime?.tunnelAddress ?? '';
    return reported.replaceFirst('tcp://', '').replaceFirst('udp://', '').trim();
  }

  int? get playersOnline {
    if (ping?.online ?? false) return ping?.playersOnline;
    if (runtimeFresh && (runtime?.ready ?? false)) return runtime?.playersOnline;
    return null;
  }

  int? get playersMax {
    if (ping?.online ?? false) return ping?.playersMax ?? _config.maxPlayers;
    if (runtimeFresh && (runtime?.ready ?? false)) return runtime?.playersMax ?? _config.maxPlayers;
    return _config.maxPlayers;
  }

  int? get latencyMs => (ping?.online ?? false) ? ping?.latencyMs : null;

  /// Process RSS reported by the runner heartbeat. This is not total machine RAM.
  int? get ramMb => heartbeat?.rssMb;

  /// The runner heartbeat does not report CPU usage, so the UI must show "—".
  double? get cpuFraction => null;

  Duration? get uptime {
    if (phase != ServerPhase.online) return null;
    final Duration? runtimeUptime = runtime?.uptime;
    if (runtimeUptime != null) return runtimeUptime;
    final DateTime? started = run?.startedAtDate;
    if (started == null) return null;
    final Duration value = DateTime.now().difference(started);
    return value.isNegative ? null : value;
  }

  /// Console contents: the real server log tail while a cycle runs, then the
  /// archived GitHub log once the run ends. Falls back to the step tree so the
  /// screen is never blank during download/setup phases.
  List<LogEntry> buildLogEntries() {
    if (liveLog != null && liveLog!.trim().isNotEmpty) {
      return LogParser.fromText(liveLog!, source: 'live');
    }
    if (!runActive && logs != null && logs!.isNotEmpty) {
      return LogParser.fromText(logs!, source: 'logs');
    }
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
