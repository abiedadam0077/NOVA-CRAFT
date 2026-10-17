package io.github.abiedadam0077.novacraft

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import io.github.abiedadam0077.novacraft.ui.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { NovaRoot() }
    }
}

@Composable
fun NovaRoot(vm: AppViewModel = viewModel()) {
    val lang by vm.language.collectAsState()
    val theme by vm.theme.collectAsState()
    val auth by vm.auth.collectAsState()
    val direction = if (lang == "ar") LayoutDirection.Rtl else LayoutDirection.Ltr
    CompositionLocalProvider(LocalLayoutDirection provides direction) {
        NovaCraftTheme(theme) {
            Surface {
                var onboarded by remember { mutableStateOf<Boolean?>(null) }
                LaunchedEffect(Unit) { onboarded = vm.store.getSetting("onboarded") == "1" }
                when {
                    !auth.checked || onboarded == null -> SplashScreen()
                    onboarded == false -> WelcomeScreen(vm) { vm.setOnboarded(); onboarded = true }
                    auth.user == null -> AuthScreen(vm)
                    else -> MainScaffold(vm)
                }
            }
        }
    }
}

@Composable
fun MainScaffold(vm: AppViewModel) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route ?: "home"
    val items = listOf(
        Triple("home", Icons.Filled.Home, vm.t("home")),
        Triple("servers", Icons.Filled.Dns, vm.t("servers")),
        Triple("console", Icons.Filled.Terminal, vm.t("console")),
        Triple("files", Icons.Filled.Folder, vm.t("files")),
        Triple("settings", Icons.Filled.Settings, vm.t("settings"))
    )
    Scaffold(bottomBar = {
        NavigationBar {
            items.forEach { (r, icon, label) ->
                NavigationBarItem(selected = route == r, onClick = { nav.navigate(r) { popUpTo("home"); launchSingleTop = true } }, icon = { Icon(icon, label) }, label = { Text(label) })
            }
        }
    }) { pad ->
        NavHost(nav, startDestination = "home", Modifier.padding(pad)) {
            composable("home") { HomeScreen(vm, onOpenServer = { nav.navigate("detail/${it.repoOwner}/${it.repoName}") }, onNew = { nav.navigate("wizard") }) }
            composable("servers") { ServersScreen(vm, onOpen = { nav.navigate("detail/${it.repoOwner}/${it.repoName}") }, onNew = { nav.navigate("wizard") }) }
            composable("console") { ConsoleScreen(vm) }
            composable("files") { FilesScreen(vm, "") }
            composable("settings") { AppSettingsScreen(vm, onAccount = { nav.navigate("account") }) }
            composable("account") { AccountScreen(vm) }
            composable("wizard") { WizardScreen(vm, onDone = { nav.navigate("provisioning") { popUpTo("home") } }) }
            composable("provisioning") { ProvisioningScreen(vm, onFinish = { nav.navigate("servers") { popUpTo("home") } }) }
            composable("detail/{owner}/{repo}", arguments = listOf(navArgument("owner") { type = NavType.StringType }, navArgument("repo") { type = NavType.StringType })) { b ->
                val owner = b.arguments?.getString("owner") ?: ""; val repo = b.arguments?.getString("repo") ?: ""
                ServerDetailScreen(vm, owner, repo, onBack = { nav.popBackStack() })
            }
        }
    }
}
