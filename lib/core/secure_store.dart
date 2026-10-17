import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret preferences live in SharedPreferences. GitHub tokens are kept in
/// Android Keystore–backed encrypted storage (the same security model as the
/// previous Kotlin build, which used an AES-GCM Keystore key).
class SecureStore {
  SecureStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  static const String _accessKey = 'access_token_enc';
  static const String _refreshKey = 'refresh_token_enc';
  static const String _expiresKey = 'token_expires';
  static const String _langKey = 'nova_language';
  static const String _themeKey = 'nova_theme';
  static const String _onboardedKey = 'nova_onboarded';
  static const String _notifyBackupsKey = 'nova_notify_backups';
  static const String _notifyFailuresKey = 'nova_notify_failures';
  static const String _lastServerKey = 'nova_last_server';
  static const String _playitKey = 'playit_agent_secret_enc';
  static const String _playitPreparedKey = 'nova_playit_prepared';

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      throw StateError('SecureStore.init() must be awaited before use');
    }
    return prefs;
  }

  // ---------------------------------------------------------------- tokens
  Future<void> saveTokens(String access, String? refresh, int? expiresInSeconds) async {
    try {
      await _secure.write(key: _accessKey, value: access);
      if (refresh != null && refresh.isNotEmpty) {
        await _secure.write(key: _refreshKey, value: refresh);
      } else {
        await _secure.delete(key: _refreshKey);
      }
      if (expiresInSeconds != null) {
        final int at = DateTime.now().millisecondsSinceEpoch + expiresInSeconds * 1000;
        await _p.setString(_expiresKey, at.toString());
      } else {
        await _p.remove(_expiresKey);
      }
    } catch (error) {
      debugPrint('NOVA: could not persist tokens securely ($error)');
      rethrow;
    }
  }

  Future<String?> accessToken() async {
    try {
      return await _secure.read(key: _accessKey);
    } catch (error) {
      debugPrint('NOVA: could not read access token ($error)');
      return null;
    }
  }

  Future<String?> refreshToken() async {
    try {
      return await _secure.read(key: _refreshKey);
    } catch (error) {
      debugPrint('NOVA: could not read refresh token ($error)');
      return null;
    }
  }

  DateTime? tokenExpiry() {
    final String? raw = _prefs?.getString(_expiresKey);
    if (raw == null) return null;
    final int? ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> clearTokens() async {
    try {
      await _secure.delete(key: _accessKey);
      await _secure.delete(key: _refreshKey);
    } catch (error) {
      debugPrint('NOVA: token delete failed ($error)');
    }
    await _p.remove(_expiresKey);
  }

  // ---------------------------------------------------------------- playit
  /// The Playit agent secret never leaves the device unencrypted and is never
  /// rendered. It is only installed into a repository as an Actions secret.
  Future<void> savePlayitSecret(String value) async {
    await _secure.write(key: _playitKey, value: value.trim());
    await _p.setBool(_playitPreparedKey, true);
  }

  Future<String?> playitSecret() async {
    try {
      final String? value = await _secure.read(key: _playitKey);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  bool get playitPrepared => _p.getBool(_playitPreparedKey) ?? false;

  Future<void> clearPlayitSecret() async {
    try {
      await _secure.delete(key: _playitKey);
    } catch (_) {
      // Nothing else to do; the flag below still hides the flow.
    }
    await _p.setBool(_playitPreparedKey, false);
  }

  // ------------------------------------------------------------ preferences
  String get language => _p.getString(_langKey) ?? 'ar';
  Future<void> setLanguage(String value) => _p.setString(_langKey, value);

  String get themeMode => _p.getString(_themeKey) ?? 'dark';
  Future<void> setThemeMode(String value) => _p.setString(_themeKey, value);

  bool get onboarded => _p.getBool(_onboardedKey) ?? false;
  Future<void> setOnboarded(bool value) => _p.setBool(_onboardedKey, value);

  bool get notifyBackups => _p.getBool(_notifyBackupsKey) ?? true;
  Future<void> setNotifyBackups(bool value) => _p.setBool(_notifyBackupsKey, value);

  bool get notifyFailures => _p.getBool(_notifyFailuresKey) ?? true;
  Future<void> setNotifyFailures(bool value) => _p.setBool(_notifyFailuresKey, value);

  String? get lastServerRepo => _p.getString(_lastServerKey);
  Future<void> setLastServerRepo(String? value) async {
    if (value == null || value.isEmpty) {
      await _p.remove(_lastServerKey);
    } else {
      await _p.setString(_lastServerKey, value);
    }
  }

  Future<void> clearLocalData() async {
    await clearTokens();
    await clearPlayitSecret();
    await _p.clear();
  }
}
