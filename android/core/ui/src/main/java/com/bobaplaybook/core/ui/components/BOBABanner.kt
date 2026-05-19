package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Persistent attention-required message (ANDROID-DESIGN.md §6.7).
 *
 * Material's convention is **Snackbar = transient, Banner = persistent**.
 * BOBA's `BOBABanner` is the persistent path — offline state, auth
 * expired, region-blocked, sync failure that won't auto-recover.
 *
 * Dismiss only on user action (`onAction` or `onDismiss`).
 *
 * For transient action failures (save failed, brief sync hiccup), use a
 * `Snackbar` via `SnackbarHost` with `actionLabel = "Retry"` instead.
 */
@Composable
fun BOBABanner(
    icon: ImageVector,
    message: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f),
            )
            if (actionLabel != null && onAction != null) {
                TextButton(onClick = onAction) {
                    Text(actionLabel, color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewBanner() {
    BobaTheme {
        BOBABanner(
            icon = Icons.Default.CloudOff,
            message = "You're offline. Some features won't update until you reconnect.",
            actionLabel = "Retry",
            onAction = {},
        )
    }
}
