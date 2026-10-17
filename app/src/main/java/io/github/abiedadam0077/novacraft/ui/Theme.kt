package io.github.abiedadam0077.novacraft.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val NovaDark = darkColorScheme(
    primary = Color(0xFF38BDF8), secondary = Color(0xFFA78BFA), tertiary = Color(0xFF34D399),
    background = Color(0xFF050914), surface = Color(0xFF0B1226), surfaceVariant = Color(0xFF131C38),
    onBackground = Color(0xFFE6EDF7), onSurface = Color(0xFFE6EDF7), error = Color(0xFFF87171)
)
private val NovaLight = lightColorScheme(
    primary = Color(0xFF0369A1), secondary = Color(0xFF7C3AED), background = Color(0xFFF1F5F9),
    surface = Color(0xFFFFFFFF), onBackground = Color(0xFF0F172A), onSurface = Color(0xFF0F172A)
)

@Composable
fun NovaCraftTheme(themeMode: String = "dark", content: @Composable () -> Unit) {
    val dark = when (themeMode) { "light" -> false; "system" -> isSystemInDarkTheme(); else -> true }
    MaterialTheme(colorScheme = if (dark) NovaDark else NovaLight, content = content)
}
