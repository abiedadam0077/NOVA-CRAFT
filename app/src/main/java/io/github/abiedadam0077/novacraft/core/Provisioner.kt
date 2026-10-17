package io.github.abiedadam0077.novacraft.core

import org.json.JSONObject
import java.util.UUID

object Provisioner {
    suspend fun putText(api: GitHubApi, c: ServerConfig, path: String, text: String, msg: String) {
        val sha = api.fileSha(c.repoOwner, c.repoName, path)
        api.putFile(c.repoOwner, c.repoName, path, text.toByteArray(Charsets.UTF_8), msg, sha)
    }
    suspend fun putBytes(api: GitHubApi, c: ServerConfig, path: String, bytes: ByteArray, msg: String) {
        val sha = api.fileSha(c.repoOwner, c.repoName, path)
        api.putFile(c.repoOwner, c.repoName, path, bytes, msg, sha)
    }
    suspend fun writeServerFiles(api: GitHubApi, c: ServerConfig, iconPng: ByteArray?) {
        putText(api, c, "nova-craft/server.json", c.toJson().toString(2), "nova: server config")
        putText(api, c, "nova-craft/commands/.gitkeep", "", "nova: commands queue")
        if (c.edition == "BEDROCK") {
            putText(api, c, "server/server.properties", WorkflowTemplates.bedrockProperties(c), "nova: bedrock properties")
        } else {
            putText(api, c, "server/server.properties", WorkflowTemplates.javaProperties(c), "nova: java properties")
            putText(api, c, "server/eula.txt", "eula=true\n", "nova: accept eula")
        }
        putText(api, c, ".github/workflows/novacraft-server.yml", WorkflowTemplates.serverWorkflow(c.id), "nova: server workflow")
        if (iconPng != null) putBytes(api, c, "server/server-icon.png", iconPng, "nova: server icon")
    }
    suspend fun startServer(api: GitHubApi, c: ServerConfig) =
        api.dispatch(c.repoOwner, c.repoName, "novacraft-server.yml", mapOf("action" to "start"))
    suspend fun snapshot(api: GitHubApi, c: ServerConfig) =
        api.dispatch(c.repoOwner, c.repoName, "novacraft-server.yml", mapOf("action" to "snapshot"))
    suspend fun sendCommand(api: GitHubApi, c: ServerConfig, command: String) {
        val name = "nova-craft/commands/${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}.txt"
        putText(api, c, name, command, "nova: queue command")
    }
    suspend fun discoverServers(api: GitHubApi): List<ServerConfig> {
        val out = mutableListOf<ServerConfig>()
        for (inst in api.listInstallations()) {
            for (repo in api.listInstallationRepos(inst.id)) {
                try {
                    val (_, text) = api.getFile(repo.owner, repo.name, "nova-craft/server.json")
                    out += ServerConfig.fromJson(JSONObject(text))
                } catch (e: Exception) { /* not a NOVA CRAFT server repo */ }
            }
        }
        return out
    }
}
