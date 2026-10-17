package io.github.abiedadam0077.novacraft.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class McVersion(val id: String, val type: String)
data class ResolvedDownload(val url: String, val sha: String, val javaMajor: Int, val label: String)

/** Live version/software resolution from official or primary project APIs. No invented version lists. */
class MinecraftApi {
    private val client = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(40, TimeUnit.SECONDS).build()
    private suspend fun text(url: String): String = withContext(Dispatchers.IO) {
        val r = Request.Builder().url(url).header("User-Agent", "NOVA-CRAFT-Android").build()
        client.newCall(r).execute().use { resp -> if (!resp.isSuccessful) throw ApiException(resp.code, "HTTP ${resp.code} for $url"); resp.body?.string() ?: "" }
    }
    private suspend fun json(url: String) = JSONObject(text(url))
    private suspend fun jsonArray(url: String) = JSONArray(text(url))

    suspend fun javaReleases(): List<McVersion> {
        val o = json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        val arr = o.getJSONArray("versions"); val out = mutableListOf<McVersion>()
        for (i in 0 until arr.length()) { val v = arr.getJSONObject(i); if (v.getString("type") == "release") out += McVersion(v.getString("id"), "release") }
        return out
    }
    suspend fun resolveVanilla(version: String): ResolvedDownload {
        val manifest = json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        val arr = manifest.getJSONArray("versions"); var detailUrl: String? = null
        for (i in 0 until arr.length()) { val v = arr.getJSONObject(i); if (v.getString("id") == version) { detailUrl = v.getString("url"); break } }
        val detail = json(detailUrl ?: throw ApiException(404, "Version not found"))
        val server = detail.getJSONObject("downloads").getJSONObject("server")
        val javaMajor = detail.optJSONObject("javaVersion")?.optInt("majorVersion", 21) ?: 21
        return ResolvedDownload(server.getString("url"), server.optString("sha1"), javaMajor, "Vanilla $version")
    }
    suspend fun paperVersions(): List<String> {
        val o = json("https://api.papermc.io/v2/projects/paper")
        val arr = o.getJSONArray("versions"); val out = mutableListOf<String>()
        for (i in 0 until arr.length()) out += arr.getString(i); return out.reversed()
    }
    suspend fun resolvePaper(version: String): ResolvedDownload {
        val builds = json("https://api.papermc.io/v2/projects/paper/versions/$version/builds")
        val arr = builds.getJSONArray("builds"); if (arr.length() == 0) throw ApiException(404, "No Paper build for $version")
        var chosen: JSONObject? = null
        for (i in arr.length() - 1 downTo 0) { val b = arr.getJSONObject(i); if (b.optString("channel") == "default") { chosen = b; break } }
        val b = chosen ?: arr.getJSONObject(arr.length() - 1)
        val name = b.getJSONObject("downloads").getJSONObject("application").getString("name")
        val build = b.getInt("build")
        return ResolvedDownload("https://api.papermc.io/v2/projects/paper/versions/$version/builds/$build/downloads/$name", b.getJSONObject("downloads").getJSONObject("application").optString("sha256"), javaForMc(version), "Paper $version #$build")
    }
    suspend fun purpurVersions(): List<String> {
        val o = json("https://api.purpurmc.org/v2/purpur"); val arr = o.getJSONArray("versions"); val out = mutableListOf<String>()
        for (i in 0 until arr.length()) out += arr.getString(i); return out.reversed()
    }
    suspend fun resolvePurpur(version: String): ResolvedDownload =
        ResolvedDownload("https://api.purpurmc.org/v2/purpur/$version/latest/download", "", javaForMc(version), "Purpur $version (latest)")
    suspend fun fabricLoaders(mcVersion: String): List<String> {
        val arr = try { jsonArray("https://meta.fabricmc.net/v2/versions/loader/$mcVersion") } catch (e: Exception) { return emptyList() }
        val out = mutableListOf<String>()
        for (i in 0 until arr.length()) { val l = arr.getJSONObject(i).getJSONObject("loader"); if (l.optBoolean("stable")) out += l.getString("version") }
        return out
    }
    suspend fun resolveFabric(mcVersion: String): ResolvedDownload {
        val loaders = fabricLoaders(mcVersion); if (loaders.isEmpty()) throw ApiException(404, "No stable Fabric loader for $mcVersion")
        val vanilla = resolveVanilla(mcVersion)
        return ResolvedDownload("https://meta.fabricmc.net/v2/versions/loader/$mcVersion/${loaders.first()}/1.0.1/server/jar", "", vanilla.javaMajor, "Fabric ${loaders.first()} for $mcVersion")
    }
    fun javaForMc(version: String): Int {
        val parts = version.split(".").mapNotNull { it.toIntOrNull() }
        if (parts.size >= 2) {
            val minor = parts[1]
            return when { minor >= 20 && (parts.getOrNull(2) ?: 0) >= 5 || minor > 20 -> 21; minor >= 18 -> 17; minor >= 17 -> 16; else -> 8 }
            // note: 1.20.5+ needs 21; handled by caller override from piston detail for vanilla
        }
        return 21
    }
    /** Bedrock has no version-picker API; the workflow resolves the official Linux ZIP at run time. */
    fun bedrockPlaceholder() = ResolvedDownload("https://www.minecraft.net/en-us/download/server/bedrock", "", 0, "Bedrock Dedicated Server (latest official)")
}
