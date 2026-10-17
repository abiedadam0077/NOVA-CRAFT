package io.github.abiedadam0077.novacraft.ui

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.abiedadam0077.novacraft.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

@Composable
fun SplashScreen() {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("◆", style = MaterialTheme.typography.displayLarge, color = MaterialTheme.colorScheme.primary)
            Text("NOVA CRAFT", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp)); CircularProgressIndicator()
        }
    }
}

@Composable
fun WelcomeScreen(vm: AppViewModel, onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()), Arrangement.Center) {
        Text("◆ NOVA CRAFT", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(12.dp))
        Text(vm.t("welcome_title"), style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp)); Text(vm.t("welcome_body"))
        Spacer(Modifier.height(16.dp))
        NovaCard { Text("Java TCP 25565  •  Bedrock UDP 19132") ; Text("GitHub Actions + Playit.gg", color = MaterialTheme.colorScheme.secondary) }
        Spacer(Modifier.height(24.dp))
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(vm.t("get_started")) }
    }
}

@Composable
fun AuthScreen(vm: AppViewModel) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope(); val clipboard = LocalClipboardManager.current
    val auth by vm.auth.collectAsState()
    var device by remember { mutableStateOf<DeviceCode?>(null) }
    var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }; var polling by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("connect_github"), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp)); Text(vm.t("device_instructions"))
        if (auth.expired) { Spacer(Modifier.height(8.dp)); StatusChip(vm.t("expired"), false) }
        Spacer(Modifier.height(16.dp))
        if (device == null) {
            Button(enabled = !busy, onClick = {
                busy = true; error = null
                scope.launch { try { device = vm.api.requestDeviceCode(vm.clientId) } catch (e: Exception) { error = e.message }; busy = false }
            }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("show_code")) }
        } else {
            NovaCard {
                Text(vm.t("copy_code"), style = MaterialTheme.typography.labelMedium)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(device!!.userCode, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = { clipboard.setText(AnnotatedString(device!!.userCode)) }) { Icon(Icons.Filled.ContentCopy, vm.t("copy")) }
                }
                Spacer(Modifier.height(8.dp))
                Button(onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(device!!.verificationUri))) }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("open_github")) }
                Spacer(Modifier.height(8.dp))
                if (polling) { LinearProgressIndicator(Modifier.fillMaxWidth()); Spacer(Modifier.height(6.dp)); Text(vm.t("waiting")) }
                Button(enabled = !polling, onClick = {
                    polling = true; error = null
                    scope.launch {
                        val dc = device!!; val deadline = System.currentTimeMillis() + dc.expiresIn * 1000L
                        while (System.currentTimeMillis() < deadline) {
                            when (val r = vm.api.pollDeviceToken(vm.clientId, dc.deviceCode)) {
                                is TokenPoll.Success -> { try { vm.onLoggedIn(r.accessToken, r.refreshToken, r.expiresIn) } catch (e: Exception) { error = e.message }; polling = false; return@launch }
                                is TokenPoll.Pending -> delay(dc.interval * 1000L + 500)
                                is TokenPoll.Failure -> { error = r.message; polling = false; return@launch }
                            }
                        }
                        error = "Code expired"; polling = false
                    }
                }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("waiting")) }
                TextButton(onClick = { device = null; polling = false }) { Text(vm.t("cancel")) }
            }
        }
        error?.let { Spacer(Modifier.height(10.dp)); Text(it, color = MaterialTheme.colorScheme.error) }
        Spacer(Modifier.height(20.dp)); Text(vm.t("privacy_body"), style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun WizardScreen(vm: AppViewModel, onDone: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("") }; var edition by remember { mutableStateOf("JAVA") }
    var versions by remember { mutableStateOf<List<String>>(emptyList()) }; var mcVersion by remember { mutableStateOf("") }
    var software by remember { mutableStateOf("VANILLA") }; var resolveInfo by remember { mutableStateOf("") }; var resolved by remember { mutableStateOf<ResolvedDownload?>(null) }
    var maxPlayers by remember { mutableStateOf("20") }; var gamemode by remember { mutableStateOf("survival") }; var difficulty by remember { mutableStateOf("normal") }
    var viewDistance by remember { mutableStateOf("10") }; var motd by remember { mutableStateOf("A NOVA CRAFT Server") }; var seed by remember { mutableStateOf("") }
    var memory by remember { mutableStateOf("4096") }; var pvp by remember { mutableStateOf(true) }; var onlineMode by remember { mutableStateOf(true) }; var whiteList by remember { mutableStateOf(false) }
    var createNew by remember { mutableStateOf(true) }; var isPrivate by remember { mutableStateOf(true) }
    var repoName by remember { mutableStateOf("") }; var existing by remember { mutableStateOf<List<GhRepo>>(emptyList()) }; var selectedRepo by remember { mutableStateOf<GhRepo?>(null) }
    var repoSearch by remember { mutableStateOf("") }; var installNeeded by remember { mutableStateOf(false) }
    var imageBytes by remember { mutableStateOf<ByteArray?>(null) }; var error by remember { mutableStateOf<String?>(null) }; var busy by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { try { ctx.contentResolver.openInputStream(uri)?.use { imageBytes = vm.iconBytes(BitmapFactory.decodeStream(it)) } } catch (e: Exception) { error = e.message } }
    }
    LaunchedEffect(edition) {
        busy = true
        try { if (edition == "JAVA") { val v = vm.mc.javaReleases().map { it.id }; versions = v; mcVersion = v.firstOrNull() ?: "" } else { versions = emptyList(); mcVersion = "latest" } } catch (e: Exception) { error = e.message }
        busy = false
    }
    LaunchedEffect(Unit) {
        try { val inst = vm.api.listInstallations(); installNeeded = inst.isEmpty(); val repos = inst.flatMap { vm.api.listInstallationRepos(it.id) }; existing = repos } catch (e: Exception) { error = e.message }
    }
    LaunchedEffect(software, mcVersion, edition) {
        resolved = null; resolveInfo = ""
        if (edition == "BEDROCK") { resolved = vm.mc.bedrockPlaceholder(); return@LaunchedEffect }
        if (mcVersion.isBlank()) return@LaunchedEffect
        busy = true
        try {
            resolved = when (software) {
                "VANILLA" -> vm.mc.resolveVanilla(mcVersion)
                "PAPER" -> vm.mc.resolvePaper(mcVersion)
                "PURPUR" -> vm.mc.resolvePurpur(mcVersion)
                "FABRIC" -> vm.mc.resolveFabric(mcVersion)
                else -> null
            }
            resolveInfo = resolved?.label ?: ""
        } catch (e: Exception) { resolveInfo = "⚠ ${e.message}" }
        busy = false
    }
    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("new_server"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        LinearProgressIndicator(progress = { (step + 1) / 5f }, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp))
        when (step) {
            0 -> {
                OutlinedTextField(name, { name = it }, label = { Text(vm.t("server_name")) }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(12.dp)); Text(vm.t("edition"))
                Row { FilterChip(edition == "JAVA", { edition = "JAVA" }, { Text("Java Edition") }); Spacer(Modifier.width(8.dp)); FilterChip(edition == "BEDROCK", { edition = "BEDROCK" }, { Text("Bedrock Edition") }) }
                if (edition == "JAVA") {
                    Spacer(Modifier.height(12.dp)); Text(vm.t("mc_version"))
                    var exp by remember { mutableStateOf(false) }
                    ExposedDropdownMenuBox(expanded = exp, onExpandedChange = { exp = it }) {
                        OutlinedTextField(mcVersion, {}, readOnly = true, label = { Text(vm.t("mc_version")) }, modifier = Modifier.menuAnchor().fillMaxWidth())
                        ExposedDropdownMenu(expanded = exp, onDismissRequest = { exp = false }) { versions.take(60).forEach { v -> DropdownMenuItem(text = { Text(v) }, onClick = { mcVersion = v; exp = false }) } }
                    }
                    Spacer(Modifier.height(12.dp)); Text(vm.t("software"))
                    val softwares = listOf("VANILLA", "PAPER", "PURPUR", "FABRIC")
                    softwares.forEach { s -> Row(verticalAlignment = Alignment.CenterVertically) { RadioButton(software == s, { software = s }); Text(s) } }
                    Text("Forge / NeoForge / Spigot: require an installer/BuildTools step that is not in workflow v1, so they are not offered as fake options.", style = MaterialTheme.typography.bodySmall)
                    if (resolveInfo.isNotBlank()) { Spacer(Modifier.height(6.dp)); Text(resolveInfo, color = if (resolved == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary) }
                } else {
                    Spacer(Modifier.height(8.dp)); Text("Bedrock Dedicated Server — official latest Linux build is resolved at run time. UDP 19132, transport=raknet for Playit.", style = MaterialTheme.typography.bodySmall)
                }
            }
            1 -> {
                OutlinedTextField(maxPlayers, { maxPlayers = it.filter { ch -> ch.isDigit() } }, label = { Text(vm.t("max_players")) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(motd, { motd = it }, label = { Text(vm.t("motd")) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(seed, { seed = it }, label = { Text(vm.t("seed")) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(viewDistance, { viewDistance = it.filter { ch -> ch.isDigit() } }, label = { Text(vm.t("view_distance")) }, modifier = Modifier.fillMaxWidth())
                if (edition == "JAVA") OutlinedTextField(memory, { memory = it.filter { ch -> ch.isDigit() } }, label = { Text(vm.t("memory")) }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp)); Text(vm.t("gamemode"))
                Row { listOf("survival", "creative", "adventure", "spectator").forEach { g -> FilterChip(gamemode == g, { gamemode = g }, { Text(g) }); Spacer(Modifier.width(6.dp)) } }
                Text(vm.t("difficulty"))
                Row { listOf("peaceful", "easy", "normal", "hard").forEach { d -> FilterChip(difficulty == d, { difficulty = d }, { Text(d) }); Spacer(Modifier.width(6.dp)) } }
                Row(verticalAlignment = Alignment.CenterVertically) { Switch(pvp, { pvp = it }); Text("PvP") ; Spacer(Modifier.width(12.dp)); Switch(onlineMode, { onlineMode = it }); Text("Online mode") }
                Row(verticalAlignment = Alignment.CenterVertically) { Switch(whiteList, { whiteList = it }); Text("Whitelist / Allow-list") }
            }
            2 -> {
                Row { FilterChip(createNew, { createNew = true }, { Text(vm.t("create_new_repo")) }); Spacer(Modifier.width(8.dp)); FilterChip(!createNew, { createNew = false }, { Text(vm.t("use_existing_repo")) }) }
                Spacer(Modifier.height(12.dp))
                if (installNeeded) {
                    NovaCard { Text(vm.t("install_body")); Button(onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/apps/${vm.appSlug}/installations/new"))) }) { Text(vm.t("install_app")) } }
                }
                if (createNew) {
                    OutlinedTextField(repoName, { repoName = it }, label = { Text(vm.t("repo")) }, modifier = Modifier.fillMaxWidth())
                    Row(verticalAlignment = Alignment.CenterVertically) { RadioButton(isPrivate, { isPrivate = true }); Text(vm.t("repo_private")); Spacer(Modifier.width(10.dp)); RadioButton(!isPrivate, { isPrivate = false }); Text(vm.t("repo_public")) }
                    if (!isPrivate) Text(vm.t("public_warning"), color = MaterialTheme.colorScheme.error)
                } else {
                    OutlinedTextField(repoSearch, { repoSearch = it }, label = { Text(vm.t("search")) }, modifier = Modifier.fillMaxWidth())
                    existing.filter { it.fullName.contains(repoSearch, true) }.take(30).forEach { r ->
                        Row(verticalAlignment = Alignment.CenterVertically) { RadioButton(selectedRepo?.id == r.id, { selectedRepo = r }); Text("${r.fullName} ${if (r.private) "🔒" else "🌐"}") }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Button(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text(vm.t("pick_image")) }
                imageBytes?.let { b -> Spacer(Modifier.height(8.dp)); vm.decodeImage(b)?.let { Image(it.asImageBitmap(), null, Modifier.size(72.dp)) }; TextButton(onClick = { imageBytes = null }) { Text(vm.t("remove_image")) } }
            }
            3 -> {
                NovaCard {
                    Text(vm.t("summary"), fontWeight = FontWeight.Bold)
                    Text("${vm.t("server_name")}: $name"); Text("${vm.t("edition")}: $edition  •  $mcVersion  •  $software")
                    Text("${vm.t("repo")}: ${if (createNew) repoName + if (isPrivate) " (private)" else " (public)" else selectedRepo?.fullName ?: ""}")
                    Text("Players: $maxPlayers • $gamemode • $difficulty • View: $viewDistance")
                    Text(resolveInfo)
                    if (!createNew) Text("⚠ Existing data in this repo may be overwritten under server/ and .github/workflows/novacraft-server.yml", color = MaterialTheme.colorScheme.error)
                    if (!isPrivate && createNew) Text(vm.t("public_warning"), color = MaterialTheme.colorScheme.error)
                }
            }
        }
        error?.let { Spacer(Modifier.height(8.dp)); Text(it, color = MaterialTheme.colorScheme.error) }
        Spacer(Modifier.height(16.dp))
        Row {
            if (step > 0) OutlinedButton(onClick = { step-- }) { Text(vm.t("back")) }
            Spacer(Modifier.weight(1f))
            if (step < 3) Button(enabled = !busy && (step != 0 || (name.isNotBlank() && resolved != null)), onClick = { step++ }) { Text(vm.t("next")) }
            else Button(enabled = !busy && name.isNotBlank() && resolved != null && (if (createNew) Validation.validRepoName(repoName) else selectedRepo != null), onClick = {
                val user = vm.auth.value.user!!
                val cfg = ServerConfig(
                    id = UUID.randomUUID().toString().take(8), name = name,
                    repoOwner = if (createNew) user.login else selectedRepo!!.owner,
                    repoName = if (createNew) repoName else selectedRepo!!.name,
                    repoPrivate = if (createNew) isPrivate else selectedRepo!!.private,
                    edition = edition, mcVersion = mcVersion, software = if (edition == "BEDROCK") "BDS" else software,
                    downloadUrl = resolved!!.url, downloadSha = resolved!!.sha, javaMajor = resolved!!.javaMajor,
                    maxPlayers = Validation.clampPlayers(maxPlayers.toIntOrNull() ?: 20), gamemode = gamemode, difficulty = difficulty,
                    viewDistance = Validation.clampView(viewDistance.toIntOrNull() ?: 10), motd = motd, seed = seed,
                    memoryMb = (memory.toIntOrNull() ?: 4096).coerceIn(1024, 12288), pvp = pvp, onlineMode = onlineMode, whiteList = whiteList,
                    createdAt = java.time.Instant.now().toString()
                )
                vm.pendingConfig = cfg; vm.pendingCreateNew = createNew; vm.pendingIcon = imageBytes
                onDone()
            }) { Text(vm.t("review")) }
        }
    }
}

@Composable
fun ProvisioningScreen(vm: AppViewModel, onFinish: () -> Unit) {
    val scope = rememberCoroutineScope()
    var lines by remember { mutableStateOf(listOf<String>()) }; var done by remember { mutableStateOf(false) }; var failed by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        val cfg0 = vm.pendingConfig ?: return@LaunchedEffect
        try {
            var cfg = cfg0
            if (vm.pendingCreateNew) {
                lines += "Creating repository ${cfg.repoFull}…"
                val repo = vm.api.createRepo(cfg.repoName, cfg.repoPrivate, "NOVA CRAFT server: ${cfg.name}")
                cfg = cfg.copy(repoOwner = repo.owner, repoName = repo.name, repoPrivate = repo.private); vm.pendingConfig = cfg
            }
            lines += "Writing server config & workflow…"
            Provisioner.writeServerFiles(vm.api, cfg, vm.pendingIcon)
            lines += "Dispatching first run…"
            Provisioner.startServer(vm.api, cfg)
            lines += "Waiting for GitHub Actions run…"
            repeat(40) {
                delay(5000)
                val runs = vm.api.listRuns(cfg.repoOwner, cfg.repoName, "novacraft-server.yml")
                val run = runs.firstOrNull()
                if (run != null) {
                    lines = lines.dropLastWhile { it.startsWith("Run:") } + "Run: ${run.status} ${run.conclusion ?: ""} (#${run.id})"
                    if (run.status == "completed") { done = true; return@LaunchedEffect }
                }
            }
            done = true
        } catch (e: Exception) { failed = e.message }
    }
    Column(Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("provisioning"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp)); if (!done && failed == null) LinearProgressIndicator(Modifier.fillMaxWidth())
        lines.forEach { Text("• $it", modifier = Modifier.padding(vertical = 3.dp)) }
        failed?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (done || failed != null) { Spacer(Modifier.height(16.dp)); Button(onClick = { scope.launch { vm.refreshServers() }; onFinish() }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("servers")) } }
    }
}

@Composable
fun AccountScreen(vm: AppViewModel) {
    val ctx = LocalContext.current; val auth by vm.auth.collectAsState(); val scope = rememberCoroutineScope()
    var installations by remember { mutableStateOf<List<GhInstallation>>(emptyList()) }; var checkedAt by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { try { installations = vm.api.listInstallations(); checkedAt = java.time.Instant.now().toString() } catch (e: Exception) {} }
    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text(vm.t("account"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        NovaCard {
            Text("GitHub: @${auth.user?.login ?: ""}", fontWeight = FontWeight.Bold)
            StatusChip(if (auth.user != null) vm.t("connected") else vm.t("disconnected"), auth.user != null)
            Text("Installations: ${installations.joinToString { "${it.accountLogin} (#${it.id})" }}", style = MaterialTheme.typography.bodySmall)
            Text("Last check: $checkedAt", style = MaterialTheme.typography.bodySmall)
            Button(onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/apps/${vm.appSlug}/installations/new"))) }) { Text(vm.t("install_app")) }
        }
        Spacer(Modifier.height(12.dp))
        NovaCard { Text(vm.t("privacy"), fontWeight = FontWeight.Bold); Text(vm.t("privacy_body")) }
        Spacer(Modifier.height(12.dp))
        Button(onClick = { scope.launch { vm.api.listInstallations() } }) { Text(vm.t("refresh")) }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { vm.logout() }, modifier = Modifier.fillMaxWidth()) { Text(vm.t("logout")) }
    }
}
