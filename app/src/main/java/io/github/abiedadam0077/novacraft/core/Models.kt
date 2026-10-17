package io.github.abiedadam0077.novacraft.core

import org.json.JSONObject

data class GhUser(val login: String, val id: Long, val avatarUrl: String)
data class GhRepo(val id: Long, val name: String, val owner: String, val private: Boolean, val description: String) {
    val fullName get() = "$owner/$name"
}
data class GhInstallation(val id: Long, val accountLogin: String, val accountType: String)
data class WorkflowRun(
    val id: Long, val name: String, val status: String, val conclusion: String?,
    val createdAt: String, val updatedAt: String, val htmlUrl: String, val event: String
)
data class WorkflowJob(val id: Long, val name: String, val status: String, val conclusion: String?, val steps: List<JobStep>)
data class JobStep(val name: String, val status: String, val conclusion: String?, val number: Int)
data class ReleaseInfo(val id: Long, val tag: String, val name: String, val createdAt: String, val assets: List<ReleaseAsset>)
data class ReleaseAsset(val id: Long, val name: String, val size: Long)
data class DirEntry(val name: String, val path: String, val type: String, val size: Long, val sha: String, val downloadUrl: String?)
data class DeviceCode(val deviceCode: String, val userCode: String, val verificationUri: String, val expiresIn: Int, val interval: Int)
sealed class TokenPoll {
    data class Success(val accessToken: String, val refreshToken: String?, val expiresIn: Int?) : TokenPoll()
    data class Pending(val error: String) : TokenPoll()
    data class Failure(val message: String) : TokenPoll()
}
data class PingResult(
    val online: Boolean, val latencyMs: Long, val playersOnline: Int?, val playersMax: Int?,
    val motd: String, val version: String, val error: String? = null
)

data class ServerConfig(
    val id: String,
    val name: String,
    val repoOwner: String,
    val repoName: String,
    val repoPrivate: Boolean,
    val edition: String, // JAVA | BEDROCK
    val mcVersion: String,
    val software: String, // VANILLA PAPER PURPUR SPIGOT FABRIC FORGE NEOFORGE BDS
    val downloadUrl: String,
    val downloadSha: String = "",
    val javaMajor: Int = 21,
    val maxPlayers: Int = 20,
    val gamemode: String = "survival",
    val difficulty: String = "normal",
    val viewDistance: Int = 10,
    val simulationDistance: Int = 10,
    val pvp: Boolean = true,
    val whiteList: Boolean = false,
    val onlineMode: Boolean = true,
    val seed: String = "",
    val motd: String = "A NOVA CRAFT Server",
    val memoryMb: Int = 4096,
    val playitAddress: String = "",
    val playitJavaPort: Int = 25565,
    val playitBedrockPort: Int = 19132,
    val autoRestart: Boolean = true,
    val createdAt: String = ""
) {
    val repoFull get() = "$repoOwner/$repoName"
    val localPort get() = if (edition == "BEDROCK") 19132 else 25565
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("name", name); put("repoOwner", repoOwner); put("repoName", repoName)
        put("repoPrivate", repoPrivate); put("edition", edition); put("mcVersion", mcVersion)
        put("software", software); put("downloadUrl", downloadUrl); put("downloadSha", downloadSha)
        put("javaMajor", javaMajor); put("maxPlayers", maxPlayers); put("gamemode", gamemode)
        put("difficulty", difficulty); put("viewDistance", viewDistance); put("simulationDistance", simulationDistance)
        put("pvp", pvp); put("whiteList", whiteList); put("onlineMode", onlineMode); put("seed", seed)
        put("motd", motd); put("memoryMb", memoryMb); put("playitAddress", playitAddress)
        put("playitJavaPort", playitJavaPort); put("playitBedrockPort", playitBedrockPort)
        put("autoRestart", autoRestart); put("createdAt", createdAt)
    }
    companion object {
        fun fromJson(o: JSONObject) = ServerConfig(
            id = o.optString("id"), name = o.optString("name"),
            repoOwner = o.optString("repoOwner"), repoName = o.optString("repoName"),
            repoPrivate = o.optBoolean("repoPrivate", true),
            edition = o.optString("edition", "JAVA"), mcVersion = o.optString("mcVersion"),
            software = o.optString("software", "VANILLA"), downloadUrl = o.optString("downloadUrl"),
            downloadSha = o.optString("downloadSha"), javaMajor = o.optInt("javaMajor", 21),
            maxPlayers = o.optInt("maxPlayers", 20), gamemode = o.optString("gamemode", "survival"),
            difficulty = o.optString("difficulty", "normal"), viewDistance = o.optInt("viewDistance", 10),
            simulationDistance = o.optInt("simulationDistance", 10), pvp = o.optBoolean("pvp", true),
            whiteList = o.optBoolean("whiteList", false), onlineMode = o.optBoolean("onlineMode", true),
            seed = o.optString("seed"), motd = o.optString("motd", "A NOVA CRAFT Server"),
            memoryMb = o.optInt("memoryMb", 4096), playitAddress = o.optString("playitAddress"),
            playitJavaPort = o.optInt("playitJavaPort", 25565), playitBedrockPort = o.optInt("playitBedrockPort", 19132),
            autoRestart = o.optBoolean("autoRestart", true), createdAt = o.optString("createdAt")
        )
    }
}

object Validation {
    val repoNameRegex = Regex("^[A-Za-z0-9._-]{1,100}$")
    val serverCommandDanger = listOf("stop", "ban-ip", "pardon-ip", "op ", "deop ", "whitelist reload")
    fun validRepoName(n: String) = repoNameRegex.matches(n) && n != "." && n != ".."
    fun clampPlayers(v: Int) = v.coerceIn(1, 1000)
    fun clampView(v: Int) = v.coerceIn(2, 32)
    fun safePath(p: String): String? {
        val clean = p.trim().removePrefix("/")
        if (clean.isBlank()) return ""
        val parts = clean.split("/")
        if (parts.any { it == ".." || it.isBlank() }) return null
        return parts.joinToString("/")
    }
    fun isDangerousCommand(cmd: String): Boolean {
        val c = cmd.trim().removePrefix("/").lowercase()
        return c == "stop" || serverCommandDanger.any { c.startsWith(it) }
    }
}
