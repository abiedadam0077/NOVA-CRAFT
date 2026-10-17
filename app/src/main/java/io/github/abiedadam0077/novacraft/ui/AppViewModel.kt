package io.github.abiedadam0077.novacraft.ui

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.abiedadam0077.novacraft.BuildConfig
import io.github.abiedadam0077.novacraft.core.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

data class AuthState(val checked: Boolean = false, val user: GhUser? = null, val expired: Boolean = false)

class AppViewModel(app: Application) : AndroidViewModel(app) {
    val store = SecureStore(app)
    val api = GitHubApi()
    val mc = MinecraftApi()
    val clientId: String = BuildConfig.GITHUB_CLIENT_ID
    val appSlug: String = BuildConfig.GITHUB_APP_SLUG

    private val _auth = MutableStateFlow(AuthState()); val auth: StateFlow<AuthState> = _auth.asStateFlow()
    private val _servers = MutableStateFlow<List<ServerConfig>>(emptyList()); val servers: StateFlow<List<ServerConfig>> = _servers.asStateFlow()
    private val _serversLoading = MutableStateFlow(false); val serversLoading: StateFlow<Boolean> = _serversLoading.asStateFlow()
    private val _serversError = MutableStateFlow<String?>(null); val serversError: StateFlow<String?> = _serversError.asStateFlow()
    private val _language = MutableStateFlow("ar"); val language: StateFlow<String> = _language.asStateFlow()
    private val _theme = MutableStateFlow("dark"); val theme: StateFlow<String> = _theme.asStateFlow()
    var selected: ServerConfig? = null
    var pendingConfig: ServerConfig? = null
    var pendingCreateNew: Boolean = true
    var pendingIcon: ByteArray? = null
    var onboarded: Boolean = false

    init {
        viewModelScope.launch {
            store.language.collect { _language.value = it }
        }
        viewModelScope.launch { store.themeMode.collect { _theme.value = it } }
        viewModelScope.launch {
            onboarded = store.getSetting("onboarded") == "1"
            restoreSession()
        }
    }
    fun t(key: String) = Strings.t(_language.value, key)

    suspend fun restoreSession() {
        var token = store.accessToken()
        if (token == null) { _auth.value = AuthState(checked = true); return }
        val exp = store.tokenExpiresAt()
        if (exp != null && System.currentTimeMillis() > exp) {
            val rt = store.refreshToken()
            if (rt != null) {
                when (val r = api.refreshUserToken(clientId, rt)) {
                    is TokenPoll.Success -> {
                        token = r.accessToken
                        store.saveTokens(r.accessToken, r.refreshToken ?: rt, r.expiresIn?.let { System.currentTimeMillis() + it * 1000L })
                    }
                    else -> { _auth.value = AuthState(checked = true, expired = true); return }
                }
            } else { _auth.value = AuthState(checked = true, expired = true); return }
        }
        api.accessToken = token
        try {
            val user = api.getUser()
            _auth.value = AuthState(checked = true, user = user)
            refreshServers()
        } catch (e: ApiException) {
            _auth.value = AuthState(checked = true, expired = e.status == 401)
        } catch (e: Exception) {
            _auth.value = AuthState(checked = true)
        }
    }
    suspend fun onLoggedIn(access: String, refresh: String?, expiresIn: Int?) {
        store.saveTokens(access, refresh, expiresIn?.let { System.currentTimeMillis() + it * 1000L })
        api.accessToken = access
        val user = api.getUser()
        _auth.value = AuthState(checked = true, user = user)
        refreshServers()
    }
    fun logout() = viewModelScope.launch {
        store.clearTokens(); api.accessToken = null
        _auth.value = AuthState(checked = true); _servers.value = emptyList(); selected = null
    }
    fun setOnboarded() = viewModelScope.launch { store.putSetting("onboarded", "1"); onboarded = true }
    fun setLanguage(v: String) = viewModelScope.launch { store.setLanguage(v) }
    fun setTheme(v: String) = viewModelScope.launch { store.setTheme(v) }

    suspend fun refreshServers() {
        _serversLoading.value = true; _serversError.value = null
        try {
            val list = Provisioner.discoverServers(api)
            _servers.value = list
            if (selected == null && list.isNotEmpty()) selected = list.first()
            if (selected != null && list.none { it.repoFull == selected!!.repoFull }) selected = list.firstOrNull()
        } catch (e: Exception) { _serversError.value = e.message }
        finally { _serversLoading.value = false }
    }
    fun refreshServersAsync() = viewModelScope.launch { refreshServers() }

    fun localServerName(repoFull: String): String {
        val s = _servers.value.firstOrNull { it.repoFull == repoFull }; if (s != null) selected = s
        return s?.name ?: repoFull
    }
    fun iconBytes(bitmap: Bitmap): ByteArray {
        val scaled = Bitmap.createScaledBitmap(bitmap, 64, 64, true)
        val out = ByteArrayOutputStream(); scaled.compress(Bitmap.CompressFormat.PNG, 100, out); return out.toByteArray()
    }
    fun decodeImage(bytes: ByteArray): Bitmap? = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}
