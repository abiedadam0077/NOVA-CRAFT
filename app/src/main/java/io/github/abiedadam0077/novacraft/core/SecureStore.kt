package io.github.abiedadam0077.novacraft.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private val Context.dataStore by preferencesDataStore(name = "nova_craft_prefs")

/** Non-secret settings in DataStore; GitHub tokens encrypted with an Android Keystore AES-GCM key. */
class SecureStore(private val context: Context) {
    private val alias = "nova_craft_token_key"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return gen.generateKey()
    }

    fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + ct, Base64.NO_WRAP)
    }

    fun decrypt(encoded: String): String? = try {
        val raw = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw.copyOfRange(0, 12)))
        String(cipher.doFinal(raw.copyOfRange(12, raw.size)), Charsets.UTF_8)
    } catch (e: Exception) { null }

    suspend fun saveTokens(access: String, refresh: String?, expiresAtMs: Long?) {
        context.dataStore.edit { p ->
            p[ACCESS] = encrypt(access)
            if (refresh != null) p[REFRESH] = encrypt(refresh) else p.remove(REFRESH)
            if (expiresAtMs != null) p[EXPIRES] = expiresAtMs.toString() else p.remove(EXPIRES)
        }
    }
    suspend fun accessToken(): String? = context.dataStore.data.first()[ACCESS]?.let { decrypt(it) }
    suspend fun refreshToken(): String? = context.dataStore.data.first()[REFRESH]?.let { decrypt(it) }
    suspend fun tokenExpiresAt(): Long? = context.dataStore.data.first()[EXPIRES]?.toLongOrNull()
    suspend fun clearTokens() { context.dataStore.edit { it.remove(ACCESS); it.remove(REFRESH); it.remove(EXPIRES) } }

    val language: Flow<String> = context.dataStore.data.map { it[LANG] ?: "ar" }
    val themeMode: Flow<String> = context.dataStore.data.map { it[THEME] ?: "dark" }
    suspend fun setLanguage(v: String) { context.dataStore.edit { it[LANG] = v } }
    suspend fun setTheme(v: String) { context.dataStore.edit { it[THEME] = v } }
    suspend fun putSetting(key: String, value: String) { context.dataStore.edit { it[stringPreferencesKey(key)] = value } }
    suspend fun getSetting(key: String): String? = context.dataStore.data.first()[stringPreferencesKey(key)]

    companion object {
        val ACCESS = stringPreferencesKey("access_token_enc")
        val REFRESH = stringPreferencesKey("refresh_token_enc")
        val EXPIRES = stringPreferencesKey("token_expires")
        val LANG = stringPreferencesKey("language")
        val THEME = stringPreferencesKey("theme")
    }
}
