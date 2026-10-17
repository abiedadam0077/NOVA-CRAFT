package io.github.abiedadam0077.novacraft.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.abiedadam0077.novacraft.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

fun parseHostPort(address: String, defaultPort: Int): Pair<String, Int> {
    val a = address.trim().removePrefix("tcp://").removePrefix("udp://")
    val idx = a.lastIndexOf(':')
    return if (idx > 0 && a.substring(idx + 1).all { it.isDigit() }) a.substring(0, idx) to (a.substring(idx + 1).toIntOrNull() ?: defaultPort) else a to defaultPort
}

@Composable
fun HomeScreen(vm: AppViewModel, onOpenServer: (ServerConfig) -> Unit, onNew: () -> Unit) {
    val servers by vm.servers.collectAsState(); val loading by vm.serversLoading.collectAsState(); val err by vm.serversError.collectAsState()
    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text("NOVA CRAFT", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(12.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        err?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (servers.isEmpty() && !loading) { EmptyView(vm.t("no_servers")) }
        servers.forEach { s ->
            NovaCard(Modifier.clickable { vm.selected = s; onOpenServer(s) }) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text("◆", color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(8.dp)); Text(s.name, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); StatusChip(s.edition, null) }
                Text("${s.software} • ${s.mcVersion} • ${s.repoFull}", style = MaterialTheme.typography.bodySmall)
                if (s.playitAddress.isNotBlank()) Text("${vm.t("address")}: ${s.playitAddress}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.tertiary)
            }
            Spacer(Modifier.height(10.dp))
        }
        Button(onClick = onNew, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Filled.Add, null); Text(vm.t("new_server")) }
        TextButton(onClick = { vm.refreshServersAsync() }) { Text(vm.t("refresh")) }
    }
}

@Composable
fun ServersScreen(vm: AppViewModel, onOpen: (ServerConfig) -> Unit, onNew: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val servers by vm.servers.collectAsState()
    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("my_servers"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        OutlinedTextField(query, { query = it }, label = { Text(vm.t("search")) }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        servers.filter { it.name.contains(query, true) || it.repoFull.contains(query, true) }.forEach { s ->
            NovaCard(Modifier.clickable { vm.selected = s; onOpen(s) }) {
                Text(s.name, fontWeight = FontWeight.Bold); Text("${s.edition} • ${s.software} ${s.mcVersion}", style = MaterialTheme.typography.bodySmall)
                Text(s.repoFull + if (s.repoPrivate) " 🔒" else " 🌐", style = MaterialTheme.typography.bodySmall)
            }; Spacer(Modifier.height(8.dp))
        }
        Button(onClick = onNew, modifier = Modifier.fillMaxWidth()) { Text(vm.t("new_server")) }
    }
}

@Composable
fun ServerDetailScreen(vm: AppViewModel, owner: String, repo: String, onBack: () -> Unit) {
    val servers by vm.servers.collectAsState()
    val cfg = servers.firstOrNull { it.repoOwner == owner && it.repoName == repo }
    if (cfg == null) { ErrorView(vm.t("empty"), vm.t("back"), onBack); return }
    vm.selected = cfg
    var tab by remember { mutableIntStateOf(0) }
    val tabs = listOf("◈", vm.t("server_settings"), vm.t("players"), vm.t("mods_plugins"), vm.t("backups"), vm.t("worlds"), vm.t("network"), vm.t("actions"))
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, vm.t("back")) }
            Column { Text(cfg.name, fontWeight = FontWeight.Bold); Text("${cfg.edition} • ${cfg.software} ${cfg.mcVersion} • ${cfg.repoFull}", style = MaterialTheme.typography.bodySmall) }
        }
        ScrollableTabRow(selectedTabIndex = tab) { tabs.forEachIndexed { i, label -> Tab(tab == i, { tab = i }, text = { Text(label) }) } }
        when (tab) {
            0 -> OverviewTab(vm, cfg); 1 -> ServerSettingsTab(vm, cfg); 2 -> PlayersTab(vm, cfg); 3 -> ModsTab(vm, cfg)
            4 -> BackupsTab(vm, cfg); 5 -> WorldsTab(vm, cfg); 6 -> NetworkTab(vm, cfg); else -> ActionsTab(vm, cfg)
        }
    }
}

@Composable
fun OverviewTab(vm: AppViewModel, cfg: ServerConfig) {
    val scope = rememberCoroutineScope()
    var run by remember { mutableStateOf<WorkflowRun?>(null) }; var ping by remember { mutableStateOf<PingResult?>(null) }
    var heartbeat by remember { mutableStateOf("") }; var confirmStop by remember { mutableStateOf(false) }; var msg by remember { mutableStateOf<String?>(null) }
    suspend fun load() {
        run = try { vm.api.listRuns(cfg.repoOwner, cfg.repoName, "novacraft-server.yml").firstOrNull() } catch (e: Exception) { null }
        heartbeat = try { vm.api.getFile(cfg.repoOwner, cfg.repoName, "nova-craft/status.json").second } catch (e: Exception) { "" }
        if (cfg.playitAddress.isNotBlank()) {
            val (h, p) = parseHostPort(cfg.playitAddress, cfg.localPort)
            ping = if (cfg.edition == "BEDROCK") MinecraftPing.pingBedrock(h, if (cfg.playitAddress.contains(":")) p else cfg.playitBedrockPort) else MinecraftPing.pingJava(h, if (cfg.playitAddress.contains(":")) p else cfg.playitJavaPort)
        }
    }
    LaunchedEffect(cfg.repoFull) { load() }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        NovaCard {
            Text(vm.t("workflow_status"), fontWeight = FontWeight.Bold)
            val r = run; if (r == null) Text(vm.t("unknown")) else { Text("#${r.id} • ${r.status} ${r.conclusion ?: ""}"); Text(r.createdAt, style = MaterialTheme.typography.bodySmall) }
            ping?.let { p -> Spacer(Modifier.height(6.dp)); StatusChip(if (p.online) vm.t("online") else vm.t("offline"), p.online); Text("${vm.t("ping")}: ${p.latencyMs} ms • ${vm.t("players")}: ${p.playersOnline ?: "?"}/${p.playersMax ?: "?"}"); if (p.motd.isNotBlank()) Text(p.motd, style = MaterialTheme.typography.bodySmall) }
            if (heartbeat.isNotBlank()) { Spacer(Modifier.height(6.dp)); Text("${vm.t("uptime")}:", fontWeight = FontWeight.Bold); Text(heartbeat, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace) }
        }
        Spacer(Modifier.height(12.dp))
        Row {
            Button(onClick = { scope.launch { try { Provisioner.startServer(vm.api, cfg); msg = "▶ start dispatched" } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("start")) }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { confirmStop = true }) { Text(vm.t("stop")) }
        }
        Spacer(Modifier.height(8.dp))
        Row {
            OutlinedButton(onClick = { scope.launch { try { Provisioner.sendCommand(vm.api, cfg, "nova:backup"); msg = "backup queued" } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("backup_now")) }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { scope.launch { try { vm.api.listRuns(cfg.repoOwner, cfg.repoName, "novacraft-server.yml").firstOrNull { it.status != "completed" }?.let { vm.api.cancelRun(cfg.repoOwner, cfg.repoName, it.id) }; msg = "force stop sent" } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("force_stop")) }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { scope.launch { load() } }) { Text(vm.t("refresh")) }
        }
        msg?.let { Spacer(Modifier.height(8.dp)); Text(it) }
    }
    if (confirmStop) ConfirmDialog(vm.t("stop"), vm.t("stop_confirm"), vm.t("confirm"), vm.t("cancel"), {
        confirmStop = false; scope.launch { try { Provisioner.sendCommand(vm.api, cfg, "nova:stop") } catch (e: Exception) {} }
    }, { confirmStop = false })
}

@Composable
fun ServerSettingsTab(vm: AppViewModel, cfg: ServerConfig) {
    val scope = rememberCoroutineScope()
    var maxPlayers by remember { mutableStateOf(cfg.maxPlayers.toString()) }; var motd by remember { mutableStateOf(cfg.motd) }
    var gamemode by remember { mutableStateOf(cfg.gamemode) }; var difficulty by remember { mutableStateOf(cfg.difficulty) }
    var view by remember { mutableStateOf(cfg.viewDistance.toString()) }; var memory by remember { mutableStateOf(cfg.memoryMb.toString()) }
    var pvp by remember { mutableStateOf(cfg.pvp) }; var online by remember { mutableStateOf(cfg.onlineMode) }; var wl by remember { mutableStateOf(cfg.whiteList) }
    var msg by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        OutlinedTextField(maxPlayers, { maxPlayers = it.filter { c -> c.isDigit() } }, label = { Text(vm.t("max_players")) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(motd, { motd = it }, label = { Text(vm.t("motd")) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(view, { view = it.filter { c -> c.isDigit() } }, label = { Text(vm.t("view_distance")) }, modifier = Modifier.fillMaxWidth())
        if (cfg.edition == "JAVA") OutlinedTextField(memory, { memory = it.filter { c -> c.isDigit() } }, label = { Text(vm.t("memory")) }, modifier = Modifier.fillMaxWidth())
        Row { listOf("survival", "creative", "adventure").forEach { g -> FilterChip(gamemode == g, { gamemode = g }, { Text(g) }); Spacer(Modifier.width(6.dp)) } }
        Row { listOf("peaceful", "easy", "normal", "hard").forEach { d -> FilterChip(difficulty == d, { difficulty = d }, { Text(d) }); Spacer(Modifier.width(6.dp)) } }
        Row(verticalAlignment = Alignment.CenterVertically) { Switch(pvp, { pvp = it }); Text("PvP"); Spacer(Modifier.width(10.dp)); Switch(online, { online = it }); Text("Online"); Spacer(Modifier.width(10.dp)); Switch(wl, { wl = it }); Text("Whitelist") }
        Text("Changing online-mode/whitelist affects security. Changes apply on next cycle start.", style = MaterialTheme.typography.bodySmall)
        Button(onClick = {
            scope.launch { try {
                val updated = cfg.copy(maxPlayers = Validation.clampPlayers(maxPlayers.toIntOrNull() ?: 20), motd = motd, gamemode = gamemode, difficulty = difficulty, viewDistance = Validation.clampView(view.toIntOrNull() ?: 10), memoryMb = (memory.toIntOrNull() ?: 4096).coerceIn(1024, 12288), pvp = pvp, onlineMode = online, whiteList = wl)
                Provisioner.putText(vm.api, updated, "nova-craft/server.json", updated.toJson().toString(2), "nova: update config")
                Provisioner.putText(vm.api, updated, "server/server.properties", if (updated.edition == "BEDROCK") WorkflowTemplates.bedrockProperties(updated) else WorkflowTemplates.javaProperties(updated), "nova: update properties")
                vm.refreshServers(); msg = "✓ saved"
            } catch (e: Exception) { msg = e.message } }
        }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("save")) }
        msg?.let { Text(it) }
    }
}

suspend fun lookupUuid(vm: AppViewModel, name: String): String? {
    val req = Request.Builder().url("https://api.mojang.com/users/profiles/minecraft/$name").build()
    return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        vm.api.client.newCall(req).execute().use { r -> if (!r.isSuccessful) null else JSONObject(r.body?.string() ?: "{}").optString("id").ifBlank { null } }
    }
}

@Composable
fun PlayersTab(vm: AppViewModel, cfg: ServerConfig) {
    val scope = rememberCoroutineScope()
    var entries by remember { mutableStateOf<List<String>>(emptyList()) }; var newName by remember { mutableStateOf("") }; var msg by remember { mutableStateOf<String?>(null) }
    var filePath by remember { mutableStateOf(if (cfg.edition == "BEDROCK") "server/allowlist.json" else "server/whitelist.json") }
    suspend fun load() {
        entries = try { val arr = JSONArray(vm.api.getFile(cfg.repoOwner, cfg.repoName, filePath).second); List(arr.length()) { arr.getJSONObject(it).optString("name") } } catch (e: Exception) { emptyList() }
    }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        Row { FilterChip(cfg.edition != "BEDROCK", { filePath = "server/whitelist.json"; scope.launch { load() } }, { Text("Whitelist") }); Spacer(Modifier.width(6.dp)); FilterChip(cfg.edition == "BEDROCK", { filePath = if (cfg.edition == "BEDROCK") "server/allowlist.json" else "server/banned-players.json"; scope.launch { load() } }, { Text(if (cfg.edition == "BEDROCK") "Allowlist" else "Banned") }) }
        entries.forEach { n -> NovaCard { Row { Text(n, Modifier.weight(1f)); TextButton(onClick = { scope.launch { try { Provisioner.sendCommand(vm.api, cfg, if (filePath.contains("ban")) "pardon $n" else "whitelist remove $n"); msg = "queued" } catch (e: Exception) { msg = e.message } } }) { Text("✕") } } }; Spacer(Modifier.height(6.dp)) }
        OutlinedTextField(newName, { newName = it }, label = { Text(vm.t("players")) }, modifier = Modifier.fillMaxWidth())
        Row {
            Button(onClick = { scope.launch { try { Provisioner.sendCommand(vm.api, cfg, "whitelist add $newName"); msg = "queued: whitelist add" } catch (e: Exception) { msg = e.message } } }) { Text("+ Whitelist") }
            Spacer(Modifier.width(6.dp))
            OutlinedButton(onClick = { scope.launch { try { Provisioner.sendCommand(vm.api, cfg, "op $newName"); msg = "queued: op" } catch (e: Exception) { msg = e.message } } }) { Text("OP") }
            Spacer(Modifier.width(6.dp))
            OutlinedButton(onClick = { scope.launch { try { Provisioner.sendCommand(vm.api, cfg, "ban $newName"); msg = "queued: ban" } catch (e: Exception) { msg = e.message } } }) { Text("Ban") }
        }
        Text("Actions are queued as real server commands and run on the live server (~12s poll). Mojang UUID lookup is used when editing whitelist files offline.", style = MaterialTheme.typography.bodySmall)
        msg?.let { Text(it) }
    }
}

@Composable
fun ModsTab(vm: AppViewModel, cfg: ServerConfig) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val folder = when { cfg.edition == "BEDROCK" -> "server/behavior_packs"; cfg.software == "FABRIC" || cfg.software == "FORGE" || cfg.software == "NEOFORGE" -> "server/mods"; cfg.software == "VANILLA" -> ""; else -> "server/plugins" }
    var files by remember { mutableStateOf<List<DirEntry>>(emptyList()) }; var msg by remember { mutableStateOf<String?>(null) }; var confirmDelete by remember { mutableStateOf<DirEntry?>(null) }
    suspend fun load() { files = if (folder.isBlank()) emptyList() else try { vm.api.listDir(cfg.repoOwner, cfg.repoName, folder) } catch (e: Exception) { emptyList() } }
    LaunchedEffect(Unit) { load() }
    val upload = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && folder.isNotBlank()) scope.launch { try {
            val bytes = ctx.contentResolver.openInputStream(uri)?.readBytes() ?: throw Exception("Cannot read file")
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "upload.jar"
            Provisioner.putBytes(vm.api, cfg, "$folder/$name", bytes, "nova: upload $name"); load(); msg = "✓ uploaded (restart required)"
        } catch (e: Exception) { msg = e.message } }
    }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        if (folder.isBlank()) { EmptyView("Vanilla has no mods/plugins folder. Switch software in a new server to use mods/plugins."); return@Column }
        Text("$folder — restart required after changes. Take a backup first.", style = MaterialTheme.typography.bodySmall)
        files.forEach { f -> NovaCard { Row { Text(f.name, Modifier.weight(1f)); Text("${f.size} B", style = MaterialTheme.typography.bodySmall); TextButton(onClick = { confirmDelete = f }) { Text(vm.t("delete")) } } }; Spacer(Modifier.height(6.dp)) }
        Button(onClick = { upload.launch(arrayOf("*/*")) }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("upload")) }
        OutlinedButton(onClick = { scope.launch { try { Provisioner.snapshot(vm.api, cfg); msg = "snapshot dispatched" } catch (e: Exception) { msg = e.message } } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("snapshot")) }
        msg?.let { Text(it) }
    }
    confirmDelete?.let { f -> ConfirmDialog(vm.t("delete"), vm.t("delete_confirm"), vm.t("confirm"), vm.t("cancel"), { confirmDelete = null; scope.launch { try { vm.api.deleteFile(cfg.repoOwner, cfg.repoName, f.path, f.sha, "nova: remove file"); load() } catch (e: Exception) { msg = e.message } } }, { confirmDelete = null }) }
}

@Composable
fun BackupsTab(vm: AppViewModel, cfg: ServerConfig) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var releases by remember { mutableStateOf<List<ReleaseInfo>>(emptyList()) }; var msg by remember { mutableStateOf<String?>(null) }
    var restoreTarget by remember { mutableStateOf<ReleaseInfo?>(null) }; var deleteTarget by remember { mutableStateOf<ReleaseInfo?>(null) }
    suspend fun load() { releases = try { vm.api.listReleases(cfg.repoOwner, cfg.repoName).filter { it.tag.startsWith("backup-${cfg.id}-") } } catch (e: Exception) { emptyList() } }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        Button(onClick = { scope.launch { try { Provisioner.snapshot(vm.api, cfg); msg = "snapshot dispatched" } catch (e: Exception) { msg = e.message } } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("snapshot")) }
        OutlinedButton(onClick = { scope.launch { load() } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("refresh")) }
        releases.forEach { r ->
            NovaCard {
                Text(r.tag, fontWeight = FontWeight.Bold); Text(r.createdAt, style = MaterialTheme.typography.bodySmall)
                Text(r.assets.joinToString { "${it.name} (${it.size / 1024} KB)" }, style = MaterialTheme.typography.bodySmall)
                Row {
                    Button(onClick = { restoreTarget = r }) { Text(vm.t("restore")) }; Spacer(Modifier.width(6.dp))
                    OutlinedButton(onClick = {
                        scope.launch { try { val a = r.assets.firstOrNull { it.name == "world-backup.zip" } ?: return@launch; val bytes = vm.api.downloadAsset(cfg.repoOwner, cfg.repoName, a.id); val f = File(ctx.cacheDir, "downloads/${r.tag}.zip"); f.parentFile?.mkdirs(); f.writeBytes(bytes); val uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f); ctx.startActivity(Intent(Intent.ACTION_SEND).setType("application/zip").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) } catch (e: Exception) { msg = e.message } }
                    }) { Text(vm.t("download")) }; Spacer(Modifier.width(6.dp))
                    TextButton(onClick = { deleteTarget = r }) { Text(vm.t("delete")) }
                }
            }; Spacer(Modifier.height(8.dp))
        }
        if (releases.isEmpty()) EmptyView(vm.t("empty"))
        msg?.let { Text(it) }
    }
    restoreTarget?.let { r -> ConfirmDialog(vm.t("restore"), vm.t("restore_confirm"), vm.t("confirm"), vm.t("cancel"), { restoreTarget = null; scope.launch { try { vm.api.dispatch(cfg.repoOwner, cfg.repoName, "novacraft-server.yml", mapOf("action" to "start", "restore_tag" to r.tag)); msg = "restore dispatched" } catch (e: Exception) { msg = e.message } } }, { restoreTarget = null }) }
    deleteTarget?.let { r -> ConfirmDialog(vm.t("delete"), vm.t("delete_confirm"), vm.t("confirm"), vm.t("cancel"), { deleteTarget = null; scope.launch { try { vm.api.deleteRelease(cfg.repoOwner, cfg.repoName, r.id); load() } catch (e: Exception) { msg = e.message } } }, { deleteTarget = null }) }
}

@Composable
fun WorldsTab(vm: AppViewModel, cfg: ServerConfig) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var entries by remember { mutableStateOf<List<DirEntry>>(emptyList()) }; var msg by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { entries = try { vm.api.listDir(cfg.repoOwner, cfg.repoName, "server").filter { it.name.startsWith("world") || it.name == "worlds" } } catch (e: Exception) { emptyList() } }
    val upload = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch { try { val bytes = ctx.contentResolver.openInputStream(uri)?.readBytes() ?: throw Exception("Cannot read"); Provisioner.putBytes(vm.api, cfg, "nova-craft/import/world.zip", bytes, "nova: import world"); msg = "✓ world zip staged; it will be applied on the next start (backup first!)" } catch (e: Exception) { msg = e.message } }
    }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        Text("World folders are included in every backup release (world-backup.zip). Export = download a backup. Import replaces the world on next start.", style = MaterialTheme.typography.bodySmall)
        entries.forEach { e -> NovaCard { Text("${e.name}  (${e.type})") }; Spacer(Modifier.height(6.dp)) }
        Button(onClick = { upload.launch(arrayOf("application/zip")) }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("upload") + " world.zip") }
        msg?.let { Text(it) }
    }
}

@Composable
fun NetworkTab(vm: AppViewModel, cfg: ServerConfig) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope(); val clipboard = LocalClipboardManager.current
    var address by remember { mutableStateOf(cfg.playitAddress) }; var secret by remember { mutableStateOf("") }
    var secrets by remember { mutableStateOf<List<String>>(emptyList()) }; var ping by remember { mutableStateOf<PingResult?>(null) }; var msg by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { secrets = try { vm.api.listSecretNames(cfg.repoOwner, cfg.repoName) } catch (e: Exception) { emptyList() } }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        NovaCard {
            Text(vm.t("network"), fontWeight = FontWeight.Bold)
            Text("1) playit.gg → Agents → create agent → copy SECRET_KEY\n2) Tunnels → Minecraft ${if (cfg.edition == "BEDROCK") "Bedrock (UDP → 127.0.0.1:19132)" else "Java (TCP → 127.0.0.1:25565)"}\n3) Paste the static tunnel address below.", style = MaterialTheme.typography.bodySmall)
            Button(onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://playit.gg/account/tunnels"))) }) { Text(vm.t("open_playit")) }
        }
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(address, { address = it }, label = { Text(vm.t("address") + " (host or host:port)") }, modifier = Modifier.fillMaxWidth())
        Text(vm.t("tunnel_hint"), style = MaterialTheme.typography.bodySmall)
        Row {
            Button(onClick = { scope.launch { try { val u = cfg.copy(playitAddress = address.trim()); Provisioner.putText(vm.api, u, "nova-craft/server.json", u.toJson().toString(2), "nova: playit address"); vm.refreshServers(); msg = "✓ saved" } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("save")) }
            Spacer(Modifier.width(6.dp))
            OutlinedButton(onClick = { clipboard.setText(AnnotatedString(address)) }) { Text(vm.t("copy")) }
            Spacer(Modifier.width(6.dp))
            OutlinedButton(onClick = { scope.launch { val (h, p) = parseHostPort(address, cfg.localPort); ping = if (cfg.edition == "BEDROCK") MinecraftPing.pingBedrock(h, p) else MinecraftPing.pingJava(h, p) } }) { Text(vm.t("ping")) }
        }
        ping?.let { Text("${if (it.online) "✓" else "✗"} ${it.latencyMs} ms • ${it.playersOnline ?: "?"}/${it.playersMax ?: "?"} ${it.error ?: ""}") }
        Spacer(Modifier.height(12.dp))
        NovaCard {
            Text(vm.t("playit_secret"), fontWeight = FontWeight.Bold); Text(vm.t("playit_body"), style = MaterialTheme.typography.bodySmall)
            Text("PLAYIT_SECRET_KEY present: ${secrets.contains("PLAYIT_SECRET_KEY")}", color = if (secrets.contains("PLAYIT_SECRET_KEY")) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.error)
            OutlinedTextField(secret, { secret = it }, label = { Text("SECRET_KEY") }, modifier = Modifier.fillMaxWidth())
            Button(enabled = secret.isNotBlank(), onClick = { scope.launch { try { vm.api.putSecret(cfg.repoOwner, cfg.repoName, "PLAYIT_SECRET_KEY", secret.trim()); secret = ""; secrets = vm.api.listSecretNames(cfg.repoOwner, cfg.repoName); msg = vm.t("secret_set") } catch (e: Exception) { msg = e.message } } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("set_secret")) }
        }
        msg?.let { Text(it) }
    }
}

@Composable
fun ActionsTab(vm: AppViewModel, cfg: ServerConfig) {
    val scope = rememberCoroutineScope()
    var runs by remember { mutableStateOf<List<WorkflowRun>>(emptyList()) }; var jobs by remember { mutableStateOf<Map<Long, List<WorkflowJob>>>(emptyMap()) }; var msg by remember { mutableStateOf<String?>(null) }
    suspend fun load() { runs = try { vm.api.listRuns(cfg.repoOwner, cfg.repoName, "novacraft-server.yml") } catch (e: Exception) { emptyList() } }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
        Button(onClick = { scope.launch { load() } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("refresh")) }
        runs.forEach { r ->
            NovaCard(Modifier.clickable { scope.launch { try { jobs = jobs + (r.id to vm.api.listJobs(cfg.repoOwner, cfg.repoName, r.id)) } catch (e: Exception) { msg = e.message } } }) {
                Text("#${r.id} ${r.name}", fontWeight = FontWeight.Bold); Text("${r.status} ${r.conclusion ?: ""} • ${r.createdAt}", style = MaterialTheme.typography.bodySmall)
                jobs[r.id]?.forEach { j -> Text(" ${if (j.conclusion == "success") "✓" else if (j.conclusion == "failure") "✗" else "•"} ${j.name}", style = MaterialTheme.typography.bodySmall); j.steps.forEach { s -> Text("    ${s.number}. ${s.name} — ${s.status} ${s.conclusion ?: ""}", style = MaterialTheme.typography.bodySmall) } }
                Row {
                    TextButton(onClick = { scope.launch { try { vm.api.rerunRun(cfg.repoOwner, cfg.repoName, r.id); load() } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("retry")) }
                    if (r.status != "completed") TextButton(onClick = { scope.launch { try { vm.api.cancelRun(cfg.repoOwner, cfg.repoName, r.id); load() } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("cancel")) }
                }
            }; Spacer(Modifier.height(8.dp))
        }
        msg?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
fun ConsoleScreen(vm: AppViewModel) {
    val cfg = vm.selected; val scope = rememberCoroutineScope()
    var logs by remember { mutableStateOf("") }; var cmd by remember { mutableStateOf("") }; var filter by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }; var confirmDanger by remember { mutableStateOf(false) }
    LaunchedEffect(cfg?.repoFull) {
        while (true) {
            if (cfg != null) {
                try { val run = vm.api.listRuns(cfg.repoOwner, cfg.repoName, "novacraft-server.yml").firstOrNull(); status = if (run == null) "—" else "#${run.id} ${run.status} ${run.conclusion ?: ""}"
                    if (run != null && run.status == "completed") logs = vm.api.downloadRunLogs(cfg.repoOwner, cfg.repoName, run.id).takeLast(60000)
                } catch (e: Exception) { status = e.message ?: "" }
            }
            delay(15000)
        }
    }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(vm.t("console"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (cfg == null) { EmptyView(vm.t("select_server_first")); return@Column }
        Text("${cfg.name} • $status", style = MaterialTheme.typography.bodySmall); Text(vm.t("logs_polling"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
        OutlinedTextField(filter, { filter = it }, label = { Text(vm.t("search")) }, modifier = Modifier.fillMaxWidth())
        Box(Modifier.weight(1f).verticalScroll(rememberScrollState())) { Text(logs.lines().filter { it.contains(filter, true) }.joinToString("\n").ifBlank { vm.t("empty") }, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
        OutlinedTextField(cmd, { cmd = it }, label = { Text(vm.t("command_hint")) }, modifier = Modifier.fillMaxWidth())
        Button(onClick = { if (Validation.isDangerousCommand(cmd)) confirmDanger = true else scope.launch { try { Provisioner.sendCommand(vm.api, cfg, cmd.trim()); cmd = "" } catch (e: Exception) { status = e.message ?: "" } } }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("send_command")) }
    }
    if (confirmDanger && cfg != null) ConfirmDialog(vm.t("send_command"), vm.t("danger_confirm"), vm.t("confirm"), vm.t("cancel"), { confirmDanger = false; scope.launch { try { Provisioner.sendCommand(vm.api, cfg, cmd.trim()); cmd = "" } catch (e: Exception) {} } }, { confirmDanger = false })
}

@Composable
fun FilesScreen(vm: AppViewModel, unused: String) {
    val cfg = vm.selected; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var path by remember { mutableStateOf("server") }; var entries by remember { mutableStateOf<List<DirEntry>>(emptyList()) }
    var editName by remember { mutableStateOf<String?>(null) }; var editSha by remember { mutableStateOf<String?>(null) }; var editText by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf<String?>(null) }; var deleteTarget by remember { mutableStateOf<DirEntry?>(null) }
    suspend fun load() { if (cfg != null) entries = try { vm.api.listDir(cfg.repoOwner, cfg.repoName, path) } catch (e: Exception) { msg = e.message; emptyList() } }
    LaunchedEffect(cfg?.repoFull, path) { load() }
    val upload = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && cfg != null) scope.launch { try { val bytes = ctx.contentResolver.openInputStream(uri)?.readBytes() ?: throw Exception("Cannot read"); val n = uri.lastPathSegment?.substringAfterLast('/') ?: "file"; Provisioner.putBytes(vm.api, cfg, "$path/$n".replace("//", "/"), bytes, "nova: upload"); load() } catch (e: Exception) { msg = e.message } }
    }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(vm.t("files"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (cfg == null) { EmptyView(vm.t("select_server_first")); return@Column }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (path != "server") IconButton(onClick = { path = path.substringBeforeLast('/', "server") }) { Icon(Icons.Filled.ArrowBack, vm.t("back")) }
            Text(path, Modifier.weight(1f), fontFamily = FontFamily.Monospace)
            IconButton(onClick = { upload.launch(arrayOf("*/*")) }) { Icon(Icons.Filled.Upload, vm.t("upload")) }
        }
        msg?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            entries.forEach { e ->
                NovaCard(Modifier.clickable {
                    if (e.type == "dir") path = e.path else scope.launch {
                        try { if (e.size > 300_000) { val bytes = vm.api.getFileBytes(cfg.repoOwner, cfg.repoName, e.path); val f = File(ctx.cacheDir, "downloads/${e.name}"); f.parentFile?.mkdirs(); f.writeBytes(bytes); val uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f); ctx.startActivity(Intent(Intent.ACTION_SEND).setType("*/*").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                        else { val (sha, txt) = vm.api.getFile(cfg.repoOwner, cfg.repoName, e.path); editSha = sha; editText = txt; editName = e.path } } catch (ex: Exception) { msg = ex.message }
                    }
                }) {
                    Row { Text(if (e.type == "dir") "📁" else "📄"); Spacer(Modifier.width(8.dp)); Text(e.name, Modifier.weight(1f)); Text("${e.size}", style = MaterialTheme.typography.bodySmall); TextButton(onClick = { deleteTarget = e }) { Text(vm.t("delete")) } }
                }; Spacer(Modifier.height(6.dp))
            }
        }
        editName?.let { p ->
            Text(vm.t("edit") + ": " + p, fontWeight = FontWeight.Bold)
            OutlinedTextField(editText, { editText = it }, modifier = Modifier.fillMaxWidth().height(180.dp))
            Row { Button(onClick = { scope.launch { try { Provisioner.putBytes(vm.api, cfg, p, editText.toByteArray(), "nova: edit file"); editName = null; load() } catch (e: Exception) { msg = e.message } } }) { Text(vm.t("save")) }; TextButton(onClick = { editName = null }) { Text(vm.t("cancel")) } }
        }
    }
    deleteTarget?.let { e -> if (cfg != null) ConfirmDialog(vm.t("delete"), vm.t("delete_confirm"), vm.t("confirm"), vm.t("cancel"), { deleteTarget = null; scope.launch { try { vm.api.deleteFile(cfg.repoOwner, cfg.repoName, e.path, e.sha, "nova: delete"); load() } catch (ex: Exception) { msg = ex.message } } }, { deleteTarget = null }) }
}

@Composable
fun AppSettingsScreen(vm: AppViewModel, onAccount: () -> Unit) {
    val lang by vm.language.collectAsState(); val theme by vm.theme.collectAsState()
    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("settings"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        NovaCard { Text(vm.t("language")); Row { FilterChip(lang == "ar", { vm.setLanguage("ar") }, { Text("العربية") }); Spacer(Modifier.width(8.dp)); FilterChip(lang == "en", { vm.setLanguage("en") }, { Text("English") }) } }
        Spacer(Modifier.height(10.dp))
        NovaCard { Text(vm.t("appearance")); Row { listOf("dark", "light", "system").forEach { m -> FilterChip(theme == m, { vm.setTheme(m) }, { Text(m) }); Spacer(Modifier.width(6.dp)) } } }
        Spacer(Modifier.height(10.dp))
        NovaCard(Modifier.clickable { onAccount() }) { Text(vm.t("account"), fontWeight = FontWeight.Bold); Text("GitHub • Playit • Security") }
        Spacer(Modifier.height(10.dp))
        NovaCard { Text(vm.t("privacy"), fontWeight = FontWeight.Bold); Text(vm.t("privacy_body")) }
        Spacer(Modifier.height(10.dp))
        NovaCard { Text(vm.t("about"), fontWeight = FontWeight.Bold); Text("NOVA CRAFT 1.0.0\niu.github.abiedadam0077.novacraft\nGitHub App: nova-craft-by-abiedadam0077") }
    }
}
