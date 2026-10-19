import 'package:flutter/widgets.dart';

import '../core/config.dart';
import '../core/github_api.dart';
import '../core/minecraft_api.dart';
import '../core/models.dart';
import '../core/modrinth_api.dart';
import '../core/modrinth_installer.dart';
import '../core/playit_api.dart';
import '../core/provisioner.dart';
import '../core/secure_store.dart';
import '../core/strings.dart';

/// Single source of truth for session, language, theme and the server list.
class AppState extends ChangeNotifier {
  AppState({
    SecureStore? store,
    GitHubApi? api,
    MinecraftApi? minecraft,
    ModrinthApi? modrinth,
    ModrinthInstaller? installer,
  })  : store = store ?? SecureStore(),
        api = api ?? GitHubApi(),
        minecraft = minecraft ?? MinecraftApi(),
        modrinth = modrinth ?? ModrinthApi() {
    this.installer = installer ?? ModrinthInstaller(modrinth: this.modrinth, github: this.api);
  }

  final SecureStore store;
  final GitHubApi api;
  final MinecraftApi minecraft;
  final ModrinthApi modrinth;
  late final ModrinthInstaller installer;

  bool booting = true;
  bool sessionReady = false;
  bool sessionExpired = false;
  String? bootError;

  GhUser? user;
  String language = 'ar';
  String themeMode = 'dark';
  bool onboarded = false;

  List<ServerConfig> servers = <ServerConfig>[];
  bool loadingServers = false;
  String? serversError;
  ServerConfig? selected;

  /// Repository selected before first server creation. Kept only in memory so
  /// interrupted setup restarts at the repository picker instead of guessing.
  GhRepo? pendingRepo;
  bool pendingRepoPlayitSecretReady = false;

  bool notifyBackups = true;
  bool notifyFailures = true;

  /// True once a Playit agent secret has been stored on this device. The value
  /// itself is never cached in memory beyond the write call.
  bool playitPrepared = false;

  /// Set only when the user explicitly continues without Playit. Persisted so
  /// the guided step is not repeated on every launch.
  bool playitSkipped = false;

  bool get signedIn => user != null;
  bool get isArabic => language == 'ar';

  Future<void> boot() async {
    try {
      await store.init();
      language = store.language;
      themeMode = store.themeMode;
      onboarded = store.onboarded;
      notifyBackups = store.notifyBackups;
      notifyFailures = store.notifyFailures;
      playitPrepared = store.playitPrepared && (await store.playitSecret()) != null;
      playitSkipped = store.playitSkipped;
      L10n.lang = language;
      await _restoreSession();
    } catch (error) {
      bootError = error.toString();
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> _restoreSession() async {
    String? token = await store.accessToken();
    if (token == null || token.isEmpty) {
      sessionReady = true;
      return;
    }
    final DateTime? expiry = store.tokenExpiry();
    final bool expired = expiry != null && DateTime.now().isAfter(expiry);
    if (expired) {
      final String? refresh = await store.refreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        try {
          final TokenPoll result = await api.refreshUserToken(AppConfig.githubClientId, refresh);
          if (result.kind == TokenPollKind.success && result.accessToken != null) {
            token = result.accessToken;
            await store.saveTokens(result.accessToken!, result.refreshToken ?? refresh, result.expiresIn);
          } else {
            sessionExpired = true;
            sessionReady = true;
            return;
          }
        } catch (error) {
          bootError = error.toString();
          sessionReady = true;
          return;
        }
      } else {
        sessionExpired = true;
        sessionReady = true;
        return;
      }
    }
    api.accessToken = token;
    try {
      user = await api.getUser();
      sessionExpired = false;
      sessionReady = true;
      await refreshServers();
    } on ApiException catch (error) {
      if (error.status == 401) {
        sessionExpired = true;
        api.accessToken = null;
        await store.clearTokens();
      } else {
        bootError = error.message;
      }
      sessionReady = true;
    } catch (error) {
      bootError = error.toString();
      sessionReady = true;
    }
    notifyListeners();
  }

  Future<void> completeLogin(String accessToken, String? refreshToken, int? expiresIn) async {
    await store.saveTokens(accessToken, refreshToken, expiresIn);
    api.accessToken = accessToken;
    sessionExpired = false;
    user = await api.getUser();
    // Load the server list before announcing the session, so the first-run
    // gate never flashes the wizard for an account that already has servers.
    loadingServers = true;
    notifyListeners();
    await refreshServers();
  }

  /// Refreshes the GitHub user token when it is close to expiry.
  ///
  /// GitHub App user tokens live 8 hours. Refreshing ahead of the expiry keeps
  /// long sessions (and the Playit secret install) from failing with 401.
  Future<bool> ensureTokenFresh({Duration margin = const Duration(minutes: 15)}) async {
    final String? current = api.accessToken;
    if (current == null || current.isEmpty) return false;
    final DateTime? expiry = store.tokenExpiry();
    if (expiry == null || DateTime.now().add(margin).isBefore(expiry)) return true;
    final String? refresh = await store.refreshToken();
    if (refresh == null || refresh.isEmpty) return true;
    final TokenPoll result = await api.refreshUserToken(AppConfig.githubClientId, refresh);
    if (result.kind != TokenPollKind.success || result.accessToken == null) return false;
    await store.saveTokens(result.accessToken!, result.refreshToken ?? refresh, result.expiresIn);
    api.accessToken = result.accessToken;
    return true;
  }

  Future<void> refreshUser() async {
    if (api.accessToken == null) return;
    try {
      user = await api.getUser();
      notifyListeners();
    } catch (_) {
      // Keep the previous identity; screens surface API errors separately.
    }
  }

  Future<void> refreshServers() async {
    if (api.accessToken == null) {
      servers = <ServerConfig>[];
      notifyListeners();
      return;
    }
    loadingServers = true;
    serversError = null;
    notifyListeners();
    try {
      await ensureTokenFresh();
      final List<ServerConfig> found = await Provisioner.discoverServers(api);
      servers = found;
      final String? lastRepo = store.lastServerRepo;
      if (selected == null || !found.any((ServerConfig s) => s.repoFull == selected!.repoFull)) {
        ServerConfig? next;
        if (lastRepo != null) {
          for (final ServerConfig s in found) {
            if (s.repoFull == lastRepo) next = s;
          }
        }
        next ??= found.isNotEmpty ? found.first : null;
        selected = next;
      } else {
        selected = found.firstWhere((ServerConfig s) => s.repoFull == selected!.repoFull);
      }
    } catch (error) {
      serversError = error.toString();
    } finally {
      loadingServers = false;
      notifyListeners();
    }
  }

  void selectServer(ServerConfig? config) {
    selected = config;
    store.setLastServerRepo(config?.repoFull);
    notifyListeners();
  }

  void selectPendingRepo(GhRepo? repo) {
    pendingRepo = repo;
    pendingRepoPlayitSecretReady = false;
    notifyListeners();
  }

  void markPendingRepoPlayitReady() {
    pendingRepoPlayitSecretReady = true;
    notifyListeners();
  }

  void clearPendingRepo() {
    pendingRepo = null;
    pendingRepoPlayitSecretReady = false;
    notifyListeners();
  }

  void upsertServer(ServerConfig config) {
    final List<ServerConfig> next = List<ServerConfig>.from(servers);
    final int index = next.indexWhere((ServerConfig s) => s.repoFull == config.repoFull);
    if (index >= 0) {
      next[index] = config;
    } else {
      next.add(config);
    }
    next.sort((ServerConfig a, ServerConfig b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    servers = next;
    selected = config;
    store.setLastServerRepo(config.repoFull);
    notifyListeners();
  }

  /// First-run gate: the navigation shell only exists once a server is known.
  bool get hasServer => servers.isNotEmpty;

  /// Asks the official Playit agent API about the stored key. The key never
  /// enters widget state beyond the secure-store read or appears in a log.
  Future<PlayitAgentState> inspectPlayit() async {
    final String? secret = await store.playitSecret();
    if (secret == null || secret.isEmpty) {
      return const PlayitAgentState.unknown('missing-secret');
    }
    final PlayitApi playit = PlayitApi();
    try {
      return await playit.agentState(secret);
    } finally {
      playit.dispose();
    }
  }

  Future<void> savePlayitSecret(String secret) async {
    await store.savePlayitSecret(secret);
    await store.setPlayitSkipped(false);
    playitPrepared = true;
    playitSkipped = false;
    notifyListeners();
  }

  Future<void> skipPlayitForNow() async {
    await store.setPlayitSkipped(true);
    playitSkipped = true;
    notifyListeners();
  }

  Future<void> forgetPlayitSecret() async {
    await store.clearPlayitSecret();
    playitPrepared = false;
    notifyListeners();
  }

  Future<void> _writeSecretWithRefresh(String owner, String repo, String secret) async {
    await ensureTokenFresh();
    try {
      await api.putSecret(owner, repo, 'PLAYIT_SECRET_KEY', secret);
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      final String? refresh = await store.refreshToken();
      if (refresh == null || refresh.isEmpty) rethrow;
      final TokenPoll result = await api.refreshUserToken(AppConfig.githubClientId, refresh);
      if (result.kind != TokenPollKind.success || result.accessToken == null) rethrow;
      await store.saveTokens(result.accessToken!, result.refreshToken ?? refresh, result.expiresIn);
      api.accessToken = result.accessToken;
      await api.putSecret(owner, repo, 'PLAYIT_SECRET_KEY', secret);
    }
  }

  /// Writes the Playit key to GitHub first and verifies the repository Secret
  /// name before storing the credential on-device. This ordering prevents a
  /// "saved" state when the selected runner could not actually receive it.
  Future<bool> installPlayitSecretForRepo(String owner, String repo, {String? provided}) async {
    final String? secret = provided ?? await store.playitSecret();
    if (secret == null || secret.trim().isEmpty) return false;
    await _writeSecretWithRefresh(owner, repo, secret.trim());
    if (provided != null) {
      await store.savePlayitSecret(provided.trim());
    } else {
      await store.markPlayitPrepared();
    }
    await store.setPlayitSkipped(false);
    playitPrepared = true;
    playitSkipped = false;
    notifyListeners();
    return true;
  }

  /// Installs the stored key in an already-provisioned server repository.
  Future<bool> installPlayitSecret(ServerConfig config, {String? provided}) {
    return installPlayitSecretForRepo(config.repoOwner, config.repoName, provided: provided);
  }

  ServerConfig? serverByRepo(String owner, String repo) {
    for (final ServerConfig s in servers) {
      if (s.repoOwner == owner && s.repoName == repo) return s;
    }
    return null;
  }

  Future<void> setLanguage(String value) async {
    language = value;
    L10n.lang = value;
    await store.setLanguage(value);
    notifyListeners();
  }

  Future<void> setThemeMode(String value) async {
    themeMode = value;
    await store.setThemeMode(value);
    notifyListeners();
  }

  Future<void> setOnboarded(bool value) async {
    onboarded = value;
    await store.setOnboarded(value);
    notifyListeners();
  }

  Future<void> setNotifyBackups(bool value) async {
    notifyBackups = value;
    await store.setNotifyBackups(value);
    notifyListeners();
  }

  Future<void> setNotifyFailures(bool value) async {
    notifyFailures = value;
    await store.setNotifyFailures(value);
    notifyListeners();
  }

  Future<void> signOut({bool clearLocalData = false}) async {
    if (clearLocalData) {
      await store.clearLocalData();
    } else {
      await store.clearTokens();
      await store.clearPlayitSecret();
      await store.setPlayitSkipped(false);
    }
    playitPrepared = false;
    playitSkipped = false;
    api.accessToken = null;
    user = null;
    servers = <ServerConfig>[];
    selected = null;
    pendingRepo = null;
    pendingRepoPlayitSecretReady = false;
    sessionExpired = false;
    if (clearLocalData) {
      onboarded = false;
      language = 'ar';
      themeMode = 'dark';
      L10n.lang = 'ar';
      notifyBackups = true;
      notifyFailures = true;
      await forgetPlayitSecret();
    }
    notifyListeners();
  }

  Future<void> clearCache() async {
    await store.setLastServerRepo(selected?.repoFull);
    notifyListeners();
  }

  @override
  void dispose() {
    api.dispose();
    minecraft.dispose();
    modrinth.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final AppScope? scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.notifier!;
  }
}
