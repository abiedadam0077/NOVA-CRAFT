/// Data models mirrored from the existing NOVA CRAFT schema so repositories
/// created by earlier versions keep working byte-for-byte.
class GhUser {
  const GhUser(this.login, this.id, this.avatarUrl);

  final String login;
  final int id;
  final String avatarUrl;

  factory GhUser.fromJson(Map<String, dynamic> o) => GhUser(
        o['login'] as String? ?? '',
        (o['id'] as num?)?.toInt() ?? 0,
        o['avatar_url'] as String? ?? '',
      );
}

class GhRepo {
  const GhRepo({
    required this.id,
    required this.name,
    required this.owner,
    required this.private,
    required this.description,
    this.defaultBranch = 'main',
  });

  final int id;
  final String name;
  final String owner;
  final bool private;
  final String description;
  final String defaultBranch;

  String get fullName => '$owner/$name';

  factory GhRepo.fromJson(Map<String, dynamic> o) {
    final owner = o['owner'];
    return GhRepo(
      id: (o['id'] as num?)?.toInt() ?? 0,
      name: o['name'] as String? ?? '',
      owner: owner is Map ? owner['login'] as String? ?? '' : '',
      private: o['private'] as bool? ?? false,
      description: o['description'] as String? ?? '',
      defaultBranch: o['default_branch'] as String? ?? 'main',
    );
  }
}

class GhInstallation {
  const GhInstallation(this.id, this.accountLogin, this.accountType);

  final int id;
  final String accountLogin;
  final String accountType;
}

class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.createdAt,
    required this.updatedAt,
    required this.htmlUrl,
    required this.event,
    required this.runStartedAt,
    required this.headSha,
  });

  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final String createdAt;
  final String updatedAt;
  final String htmlUrl;
  final String event;
  final String? runStartedAt;
  final String headSha;

  bool get isActive => status == 'in_progress' || status == 'queued' || status == 'requested' || status == 'waiting' || status == 'pending';
  bool get isCompleted => status == 'completed';

  DateTime? get createdAtDate => DateTime.tryParse(createdAt)?.toLocal();
  DateTime? get startedAtDate => DateTime.tryParse(runStartedAt ?? '')?.toLocal();

  factory WorkflowRun.fromJson(Map<String, dynamic> o) => WorkflowRun(
        id: (o['id'] as num?)?.toInt() ?? 0,
        name: o['name'] as String? ?? '',
        status: o['status'] as String? ?? '',
        conclusion: o['conclusion'] as String?,
        createdAt: o['created_at'] as String? ?? '',
        updatedAt: o['updated_at'] as String? ?? '',
        htmlUrl: o['html_url'] as String? ?? '',
        event: o['event'] as String? ?? '',
        runStartedAt: o['run_started_at'] as String?,
        headSha: o['head_sha'] as String? ?? '',
      );
}

class JobStep {
  const JobStep(this.name, this.number, this.status, this.conclusion);

  final String name;
  final int number;
  final String status;
  final String? conclusion;

  bool get isSuccess => conclusion == 'success';
  bool get isFailure => conclusion == 'failure' || conclusion == 'timed_out' || conclusion == 'cancelled';
  bool get isRunning => status == 'in_progress';
}

class WorkflowJob {
  const WorkflowJob(this.id, this.name, this.status, this.conclusion, this.steps, this.startedAt);

  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final List<JobStep> steps;
  final String? startedAt;

  factory WorkflowJob.fromJson(Map<String, dynamic> o) {
    final rawSteps = o['steps'];
    final steps = <JobStep>[];
    if (rawSteps is List) {
      for (final s in rawSteps) {
        if (s is Map) {
          steps.add(JobStep(
            s['name'] as String? ?? '',
            (s['number'] as num?)?.toInt() ?? 0,
            s['status'] as String? ?? '',
            s['conclusion'] as String?,
          ));
        }
      }
    }
    return WorkflowJob(
      (o['id'] as num?)?.toInt() ?? 0,
      o['name'] as String? ?? '',
      o['status'] as String? ?? '',
      o['conclusion'] as String?,
      steps,
      o['started_at'] as String?,
    );
  }
}

class ReleaseAsset {
  const ReleaseAsset(this.id, this.name, this.size, this.downloadUrl);

  final int id;
  final String name;
  final int size;
  final String? downloadUrl;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.id,
    required this.tag,
    required this.name,
    required this.createdAt,
    required this.assets,
    required this.prerelease,
    required this.isDraft,
  });

  final int id;
  final String tag;
  final String name;
  final String createdAt;
  final List<ReleaseAsset> assets;
  final bool prerelease;
  final bool isDraft;

  int get totalSize => assets.fold(0, (sum, a) => sum + a.size);

  DateTime? get createdAtDate => DateTime.tryParse(createdAt)?.toLocal();

  factory ReleaseInfo.fromJson(Map<String, dynamic> o) {
    final rawAssets = o['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final a in rawAssets) {
        if (a is Map) {
          assets.add(ReleaseAsset(
            (a['id'] as num?)?.toInt() ?? 0,
            a['name'] as String? ?? '',
            (a['size'] as num?)?.toInt() ?? 0,
            a['browser_download_url'] as String?,
          ));
        }
      }
    }
    return ReleaseInfo(
      id: (o['id'] as num?)?.toInt() ?? 0,
      tag: o['tag_name'] as String? ?? '',
      name: o['name'] as String? ?? '',
      createdAt: o['created_at'] as String? ?? '',
      assets: assets,
      prerelease: o['prerelease'] as bool? ?? false,
      isDraft: o['draft'] as bool? ?? false,
    );
  }
}

class DirEntry {
  const DirEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    required this.sha,
    required this.downloadUrl,
  });

  final String name;
  final String path;
  final String type;
  final int size;
  final String sha;
  final String? downloadUrl;

  bool get isDir => type == 'dir';
  bool get isFile => type == 'file';

  factory DirEntry.fromJson(Map<String, dynamic> o) => DirEntry(
        name: o['name'] as String? ?? '',
        path: o['path'] as String? ?? '',
        type: o['type'] as String? ?? 'file',
        size: (o['size'] as num?)?.toInt() ?? 0,
        sha: o['sha'] as String? ?? '',
        downloadUrl: o['download_url'] as String?,
      );
}

class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

enum TokenPollKind { success, pending, failure }

class TokenPoll {
  const TokenPoll._(this.kind, {this.accessToken, this.refreshToken, this.expiresIn, this.message});

  final TokenPollKind kind;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? message;

  factory TokenPoll.success(String access, String? refresh, int? expiresIn) =>
      TokenPoll._(TokenPollKind.success, accessToken: access, refreshToken: refresh, expiresIn: expiresIn);
  factory TokenPoll.pending(String message) => TokenPoll._(TokenPollKind.pending, message: message);
  factory TokenPoll.failure(String message) => TokenPoll._(TokenPollKind.failure, message: message);
}

class PingResult {
  const PingResult({
    required this.online,
    required this.latencyMs,
    this.playersOnline,
    this.playersMax,
    this.motd = '',
    this.version = '',
    this.error,
  });

  final bool online;
  final int latencyMs;
  final int? playersOnline;
  final int? playersMax;
  final String motd;
  final String version;
  final String? error;

  static const PingResult unknown = PingResult(online: false, latencyMs: 0, error: 'not-probed');
}

/// Mirrors `nova-craft/server.json` exactly (keys, defaults and semantics).
class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.repoOwner,
    required this.repoName,
    this.repoPrivate = true,
    this.edition = 'JAVA',
    this.mcVersion = '',
    this.software = 'VANILLA',
    this.downloadUrl = '',
    this.downloadSha = '',
    this.javaMajor = 21,
    this.maxPlayers = 20,
    this.gamemode = 'survival',
    this.difficulty = 'normal',
    this.viewDistance = 10,
    this.simulationDistance = 10,
    this.pvp = true,
    this.whiteList = false,
    this.onlineMode = true,
    this.seed = '',
    this.motd = 'A NOVA CRAFT Server',
    this.memoryMb = 4096,
    this.playitAddress = '',
    this.playitJavaPort = 25565,
    this.playitBedrockPort = 19132,
    this.autoRestart = true,
    this.createdAt = '',
    this.allowCommands = true,
  });

  final String id;
  final String name;
  final String repoOwner;
  final String repoName;
  final bool repoPrivate;
  final String edition; // JAVA | BEDROCK
  final String mcVersion;
  final String software; // VANILLA PAPER PURPUR SPIGOT FABRIC FORGE NEOFORGE BDS
  final String downloadUrl;
  final String downloadSha;
  final int javaMajor;
  final int maxPlayers;
  final String gamemode;
  final String difficulty;
  final int viewDistance;
  final int simulationDistance;
  final bool pvp;
  final bool whiteList;
  final bool onlineMode;
  final String seed;
  final String motd;
  final int memoryMb;
  final String playitAddress;
  final int playitJavaPort;
  final int playitBedrockPort;
  final bool autoRestart;
  final String createdAt;
  final bool allowCommands;

  String get repoFull => '$repoOwner/$repoName';
  int get localPort => edition == 'BEDROCK' ? 19132 : 25565;
  bool get isJava => edition == 'JAVA';
  bool get isBedrock => edition == 'BEDROCK';
  bool get supportsPlugins => !isBedrock && (software == 'PAPER' || software == 'PURPUR' || software == 'SPIGOT');
  bool get supportsMods => !isBedrock && (software == 'FABRIC' || software == 'FORGE' || software == 'NEOFORGE');
  String get modsFolder {
    if (isBedrock) return 'server/behavior_packs';
    if (supportsMods) return 'server/mods';
    if (supportsPlugins) return 'server/plugins';
    return '';
  }

  String get connectionHostPort {
    final raw = playitAddress.trim();
    if (raw.isEmpty) return '';
    return raw
        .replaceFirst('tcp://', '')
        .replaceFirst('udp://', '')
        .trim();
  }

  ServerConfig copyWith({
    String? id,
    String? name,
    String? repoOwner,
    String? repoName,
    bool? repoPrivate,
    String? edition,
    String? mcVersion,
    String? software,
    String? downloadUrl,
    String? downloadSha,
    int? javaMajor,
    int? maxPlayers,
    String? gamemode,
    String? difficulty,
    int? viewDistance,
    int? simulationDistance,
    bool? pvp,
    bool? whiteList,
    bool? onlineMode,
    String? seed,
    String? motd,
    int? memoryMb,
    String? playitAddress,
    int? playitJavaPort,
    int? playitBedrockPort,
    bool? autoRestart,
    String? createdAt,
    bool? allowCommands,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      repoPrivate: repoPrivate ?? this.repoPrivate,
      edition: edition ?? this.edition,
      mcVersion: mcVersion ?? this.mcVersion,
      software: software ?? this.software,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      downloadSha: downloadSha ?? this.downloadSha,
      javaMajor: javaMajor ?? this.javaMajor,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      gamemode: gamemode ?? this.gamemode,
      difficulty: difficulty ?? this.difficulty,
      viewDistance: viewDistance ?? this.viewDistance,
      simulationDistance: simulationDistance ?? this.simulationDistance,
      pvp: pvp ?? this.pvp,
      whiteList: whiteList ?? this.whiteList,
      onlineMode: onlineMode ?? this.onlineMode,
      seed: seed ?? this.seed,
      motd: motd ?? this.motd,
      memoryMb: memoryMb ?? this.memoryMb,
      playitAddress: playitAddress ?? this.playitAddress,
      playitJavaPort: playitJavaPort ?? this.playitJavaPort,
      playitBedrockPort: playitBedrockPort ?? this.playitBedrockPort,
      autoRestart: autoRestart ?? this.autoRestart,
      createdAt: createdAt ?? this.createdAt,
      allowCommands: allowCommands ?? this.allowCommands,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'repoOwner': repoOwner,
        'repoName': repoName,
        'repoPrivate': repoPrivate,
        'edition': edition,
        'mcVersion': mcVersion,
        'software': software,
        'downloadUrl': downloadUrl,
        'downloadSha': downloadSha,
        'javaMajor': javaMajor,
        'maxPlayers': maxPlayers,
        'gamemode': gamemode,
        'difficulty': difficulty,
        'viewDistance': viewDistance,
        'simulationDistance': simulationDistance,
        'pvp': pvp,
        'whiteList': whiteList,
        'onlineMode': onlineMode,
        'seed': seed,
        'motd': motd,
        'memoryMb': memoryMb,
        'playitAddress': playitAddress,
        'playitJavaPort': playitJavaPort,
        'playitBedrockPort': playitBedrockPort,
        'autoRestart': autoRestart,
        'createdAt': createdAt,
        'allowCommands': allowCommands,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> o) {
    String str(String key, [String fallback = '']) {
      final v = o[key];
      return v == null ? fallback : v.toString();
    }

    int integer(String key, int fallback) {
      final v = o[key];
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    bool boolean(String key, bool fallback) {
      final v = o[key];
      if (v is bool) return v;
      if (v == null) return fallback;
      return v.toString().toLowerCase() == 'true';
    }

    return ServerConfig(
      id: str('id'),
      name: str('name'),
      repoOwner: str('repoOwner'),
      repoName: str('repoName'),
      repoPrivate: boolean('repoPrivate', true),
      edition: str('edition', 'JAVA'),
      mcVersion: str('mcVersion'),
      software: str('software', 'VANILLA'),
      downloadUrl: str('downloadUrl'),
      downloadSha: str('downloadSha'),
      javaMajor: integer('javaMajor', 21),
      maxPlayers: integer('maxPlayers', 20),
      gamemode: str('gamemode', 'survival'),
      difficulty: str('difficulty', 'normal'),
      viewDistance: integer('viewDistance', 10),
      simulationDistance: integer('simulationDistance', 10),
      pvp: boolean('pvp', true),
      whiteList: boolean('whiteList', false),
      onlineMode: boolean('onlineMode', true),
      seed: str('seed'),
      motd: str('motd', 'A NOVA CRAFT Server'),
      memoryMb: integer('memoryMb', 4096),
      playitAddress: str('playitAddress'),
      playitJavaPort: integer('playitJavaPort', 25565),
      playitBedrockPort: integer('playitBedrockPort', 19132),
      autoRestart: boolean('autoRestart', true),
      createdAt: str('createdAt'),
      allowCommands: boolean('allowCommands', true),
    );
  }
}

/// Parsed view of `nova-craft/status.json`, written by the runner heartbeat.
class RunnerHeartbeat {
  const RunnerHeartbeat({
    required this.serverId,
    required this.updatedAt,
    required this.serverProcessRssKb,
    required this.runnerFreeMb,
    required this.raw,
  });

  final String serverId;
  final String updatedAt;
  final int serverProcessRssKb;
  final int runnerFreeMb;
  final Map<String, dynamic> raw;

  DateTime? get updatedAtDate => DateTime.tryParse(updatedAt)?.toLocal();

  int? get rssMb => serverProcessRssKb > 0 ? (serverProcessRssKb / 1024).round() : null;

  factory RunnerHeartbeat.fromJson(Map<String, dynamic> o) => RunnerHeartbeat(
        serverId: o['serverId']?.toString() ?? '',
        updatedAt: o['updatedAt']?.toString() ?? '',
        serverProcessRssKb: (o['serverProcessRssKb'] as num?)?.toInt() ?? 0,
        runnerFreeMb: (o['runnerFreeMb'] as num?)?.toInt() ?? 0,
        raw: o,
      );
}

enum ServerPhase { unknown, offline, starting, online, stopping, error }

class McVersion {
  const McVersion(this.id, this.type);
  final String id;
  final String type;
}

class ResolvedDownload {
  const ResolvedDownload({required this.url, required this.sha, required this.javaMajor, required this.label});

  final String url;
  final String sha;
  final int javaMajor;
  final String label;
}

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;

  @override
  String toString() => message;
}
