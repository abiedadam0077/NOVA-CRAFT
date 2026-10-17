package io.github.abiedadam0077.novacraft

import io.github.abiedadam0077.novacraft.core.ServerConfig
import io.github.abiedadam0077.novacraft.core.Validation
import io.github.abiedadam0077.novacraft.core.WorkflowTemplates
import org.junit.Assert.*
import org.junit.Test

class CoreLogicTest {
    @Test fun repoNames() {
        assertTrue(Validation.validRepoName("nova-server-1"))
        assertFalse(Validation.validRepoName("bad name"))
        assertFalse(Validation.validRepoName(".."))
    }
    @Test fun pathsBlockTraversal() {
        assertEquals("server/world", Validation.safePath("server/world"))
        assertNull(Validation.safePath("../secrets"))
        assertNull(Validation.safePath("server/../../etc"))
    }
    @Test fun dangerousCommands() {
        assertTrue(Validation.isDangerousCommand("stop"))
        assertTrue(Validation.isDangerousCommand("/op Steve"))
        assertFalse(Validation.isDangerousCommand("say hello"))
        assertFalse(Validation.isDangerousCommand("list"))
    }
    @Test fun clamps() {
        assertEquals(1, Validation.clampPlayers(0))
        assertEquals(1000, Validation.clampPlayers(5000))
        assertEquals(32, Validation.clampView(99))
    }
    @Test fun configRoundTrip() {
        val c = ServerConfig(id = "abc123", name = "Test", repoOwner = "me", repoName = "srv", repoPrivate = true,
            edition = "JAVA", mcVersion = "1.21.4", software = "PAPER", downloadUrl = "https://example.com/server.jar")
        val back = ServerConfig.fromJson(c.toJson())
        assertEquals(c.id, back.id); assertEquals(c.name, back.name); assertEquals(c.software, back.software); assertTrue(back.repoPrivate)
    }
    @Test fun workflowHasSafetyPieces() {
        val y = WorkflowTemplates.serverWorkflow("abc123")
        assertTrue(y.contains("backup-abc123-"))
        assertTrue(y.contains("concurrency:"))
        assertTrue(y.contains("nova:stop"))
        assertTrue(y.contains("PLAYIT_SECRET_KEY"))
        assertTrue(y.contains("timeout-minutes: 330"))
    }
    @Test fun propertiesRespectEdition() {
        val j = ServerConfig(id = "x", name = "J", repoOwner = "o", repoName = "r", repoPrivate = true, edition = "JAVA", mcVersion = "1.21", software = "VANILLA", downloadUrl = "")
        val b = j.copy(edition = "BEDROCK", software = "BDS")
        assertTrue(WorkflowTemplates.javaProperties(j).contains("server-port=25565"))
        assertTrue(WorkflowTemplates.bedrockProperties(b).contains("server-port=19132"))
        assertTrue(WorkflowTemplates.bedrockProperties(b).contains("transport=raknet"))
    }
}
