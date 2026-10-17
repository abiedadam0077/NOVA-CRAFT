import 'package:flutter/widgets.dart';

import '../core/config.dart';
import '../core/github_api.dart';
import '../core/minecraft_api.dart';
import '../core/models.dart';
import '../core/modrinth_api.dart';
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
  })  : store = store ?? SecureStore(),
        api = api ?? GitHubApi(),
        minecraft = minecraft ?? MinecraftApi(),
        modrinth = modrinth ?? ModrinthApi();

  final SecureStore store;
  final GitHubApi api;
  final MinecraftApi minecraft;
  final ModrinthApi modrinth;

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

  bool notifyBackups = true;
  bool notifyFailures = true;

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
        final TokenPoll result = await api.refreshUserToken(AppConfig.githubClientId, refresh);
        if (result.kind == TokenPollKind.success && result.accessToken != null) {
          token = result.accessToken;
          await store.saveTokens(result.accessToken!, result.refreshToken ?? refresh, result.expiresIn);
        } else {
          sessionExpired = true;
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
    notifyListeners();
    await refreshServers();
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
    }
    api.accessToken = null;
    user = null;
    servers = <ServerConfig>[];
    selected = null;
    sessionExpired = false;
    if (clearLocalData) {
      onboarded = false;
      language = 'ar';
      themeMode = 'dark';
      L10n.lang = 'ar';
      notifyBackups = true;
      notifyFailures = true;
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
