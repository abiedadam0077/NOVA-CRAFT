package io.github.abiedadam0077.novacraft.core

import android.util.Base64
import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream

class ApiException(val status: Int, message: String) : Exception(message)

class GitHubApi {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    @Volatile var accessToken: String? = null

    private fun req(url: String, token: String? = accessToken): Request.Builder {
        val b = Request.Builder().url(url)
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .header("User-Agent", "NOVA-CRAFT-Android")
        if (!token.isNullOrBlank()) b.header("Authorization", "Bearer $token")
        return b
    }

    private suspend fun executeText(builder: Request.Builder): Pair<Int, String> = withContext(Dispatchers.IO) {
        client.newCall(builder.build()).execute().use { r -> r.code to (r.body?.string() ?: "") }
    }
    private suspend fun executeBytes(builder: Request.Builder): Pair<Int, ByteArray> = withContext(Dispatchers.IO) {
        client.newCall(builder.build()).execute().use { r -> r.code to (r.body?.bytes() ?: ByteArray(0)) }
    }
    private fun ensureOk(code: Int, body: String) {
        if (code !in 200..299) {
            val msg = try { JSONObject(body).optString("message", body.take(200)) } catch (e: Exception) { body.take(200) }
            throw ApiException(code, "GitHub $code: $msg")
        }
    }
    suspend fun getJson(url: String): JSONObject { val (c, b) = executeText(req(url)); ensureOk(c, b); return JSONObject(b) }
    suspend fun getJsonArray(url: String): JSONArray { val (c, b) = executeText(req(url)); ensureOk(c, b); return JSONArray(b) }
    suspend fun sendJson(method: String, url: String, body: JSONObject?): JSONObject {
        val rb = (body ?: JSONObject()).toString().toRequestBody("application/json".toMediaType())
        val b = req(url); when (method) { "POST" -> b.post(rb); "PUT" -> b.put(rb); "PATCH" -> b.patch(rb); "DELETE" -> b.delete(rb) }
        val (c, t) = executeText(b); ensureOk(c, t); return if (t.isBlank()) JSONObject() else JSONObject(t)
    }

    // ---------- Device Flow (no client secret, no redirect URI) ----------
    suspend fun requestDeviceCode(clientId: String): DeviceCode {
        val form = FormBody.Builder().add("client_id", clientId).add("scope", "offline_access").build()
        val r = Request.Builder().url("https://github.com/login/device/code")
            .header("Accept", "application/json").post(form).build()
        val (c, t) = executeText(Request.Builder().url(r.url).headers(r.headers).post(form))
        ensureOk(c, t); val o = JSONObject(t)
        return DeviceCode(o.getString("device_code"), o.getString("user_code"), o.getString("verification_uri"), o.optInt("expires_in", 900), o.optInt("interval", 5))
    }
    suspend fun pollDeviceToken(clientId: String, deviceCode: String): TokenPoll {
        val form = FormBody.Builder().add("client_id", clientId).add("device_code", deviceCode)
            .add("grant_type", "urn:ietf:params:oauth:grant-type:device_code").build()
        val b = Request.Builder().url("https://github.com/login/oauth/access_token").header("Accept", "application/json").post(form)
        val (c, t) = executeText(b)
        if (c !in 200..299) return TokenPoll.Failure("HTTP $c")
        val o = JSONObject(t)
        o.optString("error").takeIf { it.isNotBlank() }?.let {
            return if (it == "authorization_pending" || it == "slow_down") TokenPoll.Pending(it) else TokenPoll.Failure(it + ": " + o.optString("error_description"))
        }
        val at = o.optString("access_token"); if (at.isBlank()) return TokenPoll.Failure("Empty token response")
        return TokenPoll.Success(at, o.optString("refresh_token").ifBlank { null }, if (o.has("expires_in")) o.getInt("expires_in") else null)
    }
    /** Best-effort refresh; GitHub may require re-authorization for secret-less public clients. */
    suspend fun refreshUserToken(clientId: String, refreshToken: String): TokenPoll {
        val form = FormBody.Builder().add("client_id", clientId).add("refresh_token", refreshToken)
            .add("grant_type", "refresh_token").build()
        val b = Request.Builder().url("https://github.com/login/oauth/access_token").header("Accept", "application/json").post(form)
        val (c, t) = executeText(b)
        if (c !in 200..299) return TokenPoll.Failure("HTTP $c")
        val o = JSONObject(t)
        o.optString("error").takeIf { it.isNotBlank() }?.let { return TokenPoll.Failure(it) }
        val at = o.optString("access_token"); if (at.isBlank()) return TokenPoll.Failure("Empty refresh response")
        return TokenPoll.Success(at, o.optString("refresh_token").ifBlank { null }, if (o.has("expires_in")) o.getInt("expires_in") else null)
    }

    // ---------- User / installations / repos ----------
    suspend fun getUser(): GhUser { val o = getJson("https://api.github.com/user"); return GhUser(o.getString("login"), o.getLong("id"), o.optString("avatar_url")) }
    suspend fun listInstallations(): List<GhInstallation> {
        val o = getJson("https://api.github.com/user/installations?per_page=100")
        val arr = o.optJSONArray("installations") ?: JSONArray(); val out = mutableListOf<GhInstallation>()
        for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); val acc = x.optJSONObject("account"); out += GhInstallation(x.getLong("id"), acc?.optString("login") ?: "", acc?.optString("type") ?: "") }
        return out
    }
    suspend fun listInstallationRepos(installationId: Long): List<GhRepo> {
        val o = getJson("https://api.github.com/user/installations/$installationId/repositories?per_page=100")
        val arr = o.optJSONArray("repositories") ?: JSONArray(); val out = mutableListOf<GhRepo>()
        for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); out += GhRepo(x.getLong("id"), x.getString("name"), x.getJSONObject("owner").getString("login"), x.optBoolean("private"), x.optString("description")) }
        return out
    }
    suspend fun createRepo(name: String, isPrivate: Boolean, description: String): GhRepo {
        val body = JSONObject().put("name", name).put("private", isPrivate).put("description", description).put("auto_init", true)
        val o = sendJson("POST", "https://api.github.com/user/repos", body)
        return GhRepo(o.getLong("id"), o.getString("name"), o.getJSONObject("owner").getString("login"), o.optBoolean("private"), o.optString("description"))
    }
    suspend fun getRepo(owner: String, repo: String): JSONObject = getJson("https://api.github.com/repos/$owner/$repo")

    // ---------- Contents ----------
    suspend fun listDir(owner: String, repo: String, path: String): List<DirEntry> {
        val p = Validation.safePath(path) ?: throw ApiException(400, "Invalid path")
        val arr = getJsonArray("https://api.github.com/repos/$owner/$repo/contents/$p")
        val out = mutableListOf<DirEntry>()
        for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); out += DirEntry(x.getString("name"), x.getString("path"), x.getString("type"), x.optLong("size"), x.optString("sha"), x.optString("download_url").ifBlank { null }) }
        return out.sortedWith(compareBy({ it.type != "dir" }, { it.name.lowercase() }))
    }
    suspend fun getFile(owner: String, repo: String, path: String): Pair<String, String> { // sha to text
        val o = getJson("https://api.github.com/repos/$owner/$repo/contents/$path")
        val decoded = String(Base64.decode(o.optString("content").replace("\n", ""), Base64.DEFAULT), Charsets.UTF_8)
        return o.getString("sha") to decoded
    }
    suspend fun getFileBytes(owner: String, repo: String, path: String): ByteArray {
        val o = getJson("https://api.github.com/repos/$owner/$repo/contents/$path")
        if (o.optLong("size") > 1_000_000 && o.has("git_url")) {
            val blob = getJson(o.getString("git_url")); return Base64.decode(blob.optString("content").replace("\n", ""), Base64.DEFAULT)
        }
        return Base64.decode(o.optString("content").replace("\n", ""), Base64.DEFAULT)
    }
    suspend fun putFile(owner: String, repo: String, path: String, content: ByteArray, message: String, sha: String? = null) {
        if (content.size <= 1_000_000) {
            val body = JSONObject().put("message", message).put("content", Base64.encodeToString(content, Base64.NO_WRAP))
            if (sha != null) body.put("sha", sha)
            sendJson("PUT", "https://api.github.com/repos/$owner/$repo/contents/$path", body)
        } else uploadViaGitData(owner, repo, path, content, message)
    }
    suspend fun deleteFile(owner: String, repo: String, path: String, sha: String, message: String) {
        sendJson("DELETE", "https://api.github.com/repos/$owner/$repo/contents/$path", JSONObject().put("message", message).put("sha", sha))
    }
    suspend fun uploadViaGitData(owner: String, repo: String, path: String, content: ByteArray, message: String) {
        val base = "https://api.github.com/repos/$owner/$repo"
        val blob = sendJson("POST", "$base/git/blobs", JSONObject().put("content", Base64.encodeToString(content, Base64.NO_WRAP)).put("encoding", "base64"))
        val ref = getJson("$base/git/ref/heads/main")
        val commitSha = ref.getJSONObject("object").getString("sha")
        val commit = getJson("$base/git/commits/$commitSha")
        val treeSha = commit.getJSONObject("tree").getString("sha")
        val treeArr = JSONArray().put(JSONObject().put("path", path).put("mode", "100644").put("type", "blob").put("sha", blob.getString("sha")))
        val newTree = sendJson("POST", "$base/git/trees", JSONObject().put("base_tree", treeSha).put("tree", treeArr))
        val newCommit = sendJson("POST", "$base/git/commits", JSONObject().put("message", message).put("tree", newTree.getString("sha")).put("parents", JSONArray().put(commitSha)))
        sendJson("PATCH", "$base/git/refs/heads/main", JSONObject().put("sha", newCommit.getString("sha")))
    }
    suspend fun fileSha(owner: String, repo: String, path: String): String? =
        try { getJson("https://api.github.com/repos/$owner/$repo/contents/$path").optString("sha").ifBlank { null } } catch (e: ApiException) { if (e.status == 404) null else throw e }

    // ---------- Actions ----------
    suspend fun dispatch(owner: String, repo: String, workflow: String, inputs: Map<String, String> = emptyMap()) {
        val inp = JSONObject(); inputs.forEach { (k, v) -> inp.put(k, v) }
        sendJson("POST", "https://api.github.com/repos/$owner/$repo/actions/workflows/$workflow/dispatches", JSONObject().put("ref", "main").put("inputs", inp))
    }
    suspend fun listRuns(owner: String, repo: String, workflow: String? = null): List<WorkflowRun> {
        val url = if (workflow == null) "https://api.github.com/repos/$owner/$repo/actions/runs?per_page=20"
            else "https://api.github.com/repos/$owner/$repo/actions/workflows/$workflow/runs?per_page=20"
        val o = getJson(url); val arr = o.optJSONArray("workflow_runs") ?: JSONArray(); val out = mutableListOf<WorkflowRun>()
        for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); out += WorkflowRun(x.getLong("id"), x.optString("name"), x.optString("status"), if (x.isNull("conclusion")) null else x.optString("conclusion"), x.optString("created_at"), x.optString("updated_at"), x.optString("html_url"), x.optString("event")) }
        return out
    }
    suspend fun listJobs(owner: String, repo: String, runId: Long): List<WorkflowJob> {
        val o = getJson("https://api.github.com/repos/$owner/$repo/actions/runs/$runId/jobs?per_page=50")
        val arr = o.optJSONArray("jobs") ?: JSONArray(); val out = mutableListOf<WorkflowJob>()
        for (i in 0 until arr.length()) { val j = arr.getJSONObject(i); val steps = mutableListOf<JobStep>(); val sa = j.optJSONArray("steps") ?: JSONArray()
            for (s in 0 until sa.length()) { val st = sa.getJSONObject(s); steps += JobStep(st.optString("name"), st.optString("status"), if (st.isNull("conclusion")) null else st.optString("conclusion"), st.optInt("number")) }
            out += WorkflowJob(j.getLong("id"), j.optString("name"), j.optString("status"), if (j.isNull("conclusion")) null else j.optString("conclusion"), steps) }
        return out
    }
    suspend fun downloadRunLogs(owner: String, repo: String, runId: Long): String {
        val (c, bytes) = executeBytes(req("https://api.github.com/repos/$owner/$repo/actions/runs/$runId/logs"))
        if (c !in 200..299) throw ApiException(c, "Logs not available yet (HTTP $c)")
        val sb = StringBuilder()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            var e = zip.nextEntry
            while (e != null) { sb.append("\n===== ").append(e.name).append(" =====\n"); sb.append(zip.readBytes().toString(Charsets.UTF_8)); e = zip.nextEntry }
        }
        return sb.toString()
    }
    suspend fun cancelRun(owner: String, repo: String, runId: Long) { sendJson("POST", "https://api.github.com/repos/$owner/$repo/actions/runs/$runId/cancel", JSONObject()) }
    suspend fun rerunRun(owner: String, repo: String, runId: Long) { sendJson("POST", "https://api.github.com/repos/$owner/$repo/actions/runs/$runId/rerun", JSONObject()) }

    // ---------- Releases (durable backups) ----------
    suspend fun listReleases(owner: String, repo: String): List<ReleaseInfo> {
        val arr = getJsonArray("https://api.github.com/repos/$owner/$repo/releases?per_page=50"); val out = mutableListOf<ReleaseInfo>()
        for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); val assets = mutableListOf<ReleaseAsset>(); val aa = x.optJSONArray("assets") ?: JSONArray()
            for (a in 0 until aa.length()) { val y = aa.getJSONObject(a); assets += ReleaseAsset(y.getLong("id"), y.optString("name"), y.optLong("size")) }
            out += ReleaseInfo(x.getLong("id"), x.optString("tag_name"), x.optString("name"), x.optString("created_at"), assets) }
        return out
    }
    suspend fun deleteRelease(owner: String, repo: String, releaseId: Long) { sendJson("DELETE", "https://api.github.com/repos/$owner/$repo/releases/$releaseId", JSONObject()) }
    suspend fun downloadAsset(owner: String, repo: String, assetId: Long): ByteArray {
        val b = req("https://api.github.com/repos/$owner/$repo/releases/assets/$assetId").header("Accept", "application/octet-stream")
        val (c, bytes) = executeBytes(b); if (c !in 200..299) throw ApiException(c, "Asset download failed"); return bytes
    }

    // ---------- Actions secrets (values are never readable) ----------
    suspend fun listSecretNames(owner: String, repo: String): List<String> {
        val o = getJson("https://api.github.com/repos/$owner/$repo/actions/secrets?per_page=100")
        val arr = o.optJSONArray("secrets") ?: JSONArray(); val out = mutableListOf<String>()
        for (i in 0 until arr.length()) out += arr.getJSONObject(i).optString("name"); return out
    }
    suspend fun putSecret(owner: String, repo: String, name: String, value: String) {
        val keyObj = getJson("https://api.github.com/repos/$owner/$repo/actions/secrets/public-key")
        val encrypted = encryptSecret(value, keyObj.getString("key"))
        sendJson("PUT", "https://api.github.com/repos/$owner/$repo/actions/secrets/$name",
            JSONObject().put("encrypted_value", encrypted).put("key_id", keyObj.getString("key_id")))
    }
    private fun encryptSecret(value: String, publicKeyB64: String): String {
        val sodium = LazySodiumAndroid(SodiumAndroid()).sodium
        val pk = Base64.decode(publicKeyB64, Base64.DEFAULT)
        require(pk.size == 32) { "Invalid repository public key" }
        val msg = value.toByteArray(Charsets.UTF_8)
        val cipher = ByteArray(msg.size + 48) // crypto_box_SEALBYTES = 48
        val rc = sodium.crypto_box_seal(cipher, msg, msg.size.toLong(), pk)
        require(rc == 0) { "Secret encryption failed" }
        return Base64.encodeToString(cipher, Base64.NO_WRAP)
    }
}
