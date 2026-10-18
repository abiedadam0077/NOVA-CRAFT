/// Public identifiers only. No client secret, no private key, no redirect URI.
class AppConfig {
  const AppConfig._();

  static const String appName = 'NOVA CRAFT';
  static const String versionName = '1.0.0';
  static const String versionCode = '1';
  static const String packageName = 'io.github.abiedadam0077.novacraft';

  static const String githubClientId = 'Iv23linL1Tf6ResSgUqL';
  static const String githubAppId = '5353235';
  static const String githubAppSlug = 'nova-craft-by-abiedadam0077';

  static const String githubApi = 'https://api.github.com';
  static const String deviceCodeUrl = 'https://github.com/login/device/code';
  static const String accessTokenUrl = 'https://github.com/login/oauth/access_token';
  static const String deviceVerificationUrl = 'https://github.com/login/device';

  static const String playitDashboard = 'https://playit.gg/account/tunnels';
  static const String playitAgentUrl = 'https://playit.gg/account/agents/new-docker';
  static const String playitAgentDocs = 'https://playit.gg/download';
  static const String modrinthApi = 'https://api.modrinth.com/v2';

  static const Duration pollInterval = Duration(seconds: 12);
  static const Duration consoleInterval = Duration(seconds: 15);

  static String get userAgent => 'NOVA-CRAFT-Flutter/$versionName';
  static String get appInstallUrl => 'https://github.com/apps/$githubAppSlug/installations/new';

  /// Install/configure URL pre-filled with one repository, so the user does
  /// not have to hunt for the right repository in GitHub's picker.
  static String appInstallUrlFor(String? repoFull) {
    if (repoFull == null || !repoFull.contains('/')) return appInstallUrl;
    return 'https://github.com/apps/$githubAppSlug/installations/new?state=${Uri.encodeComponent(repoFull)}';
  }
  static String get appPageUrl => 'https://github.com/apps/$githubAppSlug';
  static const String manageInstallationsUrl = 'https://github.com/settings/installations';
  static String repoUrl(String owner, String repo) => 'https://github.com/$owner/$repo';
  static String secretsUrl(String owner, String repo) => 'https://github.com/$owner/$repo/settings/secrets/actions';
  static String runsUrl(String owner, String repo) => 'https://github.com/$owner/$repo/actions';
}
