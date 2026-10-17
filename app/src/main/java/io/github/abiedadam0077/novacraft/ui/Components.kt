package io.github.abiedadam0077.novacraft.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun NovaCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier = modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant), content = { Column(Modifier.padding(16.dp), content = content) })
}
@Composable
fun LoadingView(text: String) { Box(Modifier.fillMaxSize(), Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(); Spacer(Modifier.height(12.dp)); Text(text) } } }
@Composable
fun ErrorView(message: String, retryLabel: String, onRetry: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text("⚠", style = MaterialTheme.typography.displayMedium); Spacer(Modifier.height(8.dp)); Text(message); Spacer(Modifier.height(12.dp)); Button(onClick = onRetry) { Text(retryLabel) } } }
}
@Composable
fun EmptyView(message: String) { Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) { Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
@Composable
fun ConfirmDialog(title: String, body: String, confirm: String, cancel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(body) },
        confirmButton = { Button(onClick = onConfirm) { Text(confirm) } }, dismissButton = { TextButton(onClick = onDismiss) { Text(cancel) } })
}
@Composable
fun StatusChip(label: String, ok: Boolean?) {
    val color = when (ok) { true -> MaterialTheme.colorScheme.tertiary; false -> MaterialTheme.colorScheme.error; null -> MaterialTheme.colorScheme.secondary }
    Surface(color = color.copy(alpha = 0.18f), shape = MaterialTheme.shapes.small) { Text(label, color = color, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium) }
}
