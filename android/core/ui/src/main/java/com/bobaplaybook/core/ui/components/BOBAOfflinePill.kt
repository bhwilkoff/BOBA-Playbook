package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Subtle offline indicator (ANDROID-DESIGN.md §6.7).
 *
 * Mounted in the `TopAppBar` actions slot when `ConnectivityManager`
 * reports no network. Doesn't block; just signals that cloud writes
 * will be queued or disabled.
 *
 * Distinct from [BOBABanner] — the pill is ambient, the banner is
 * attention-required.
 */
@Composable
fun BOBAOfflinePill(modifier: Modifier = Modifier) {
    AssistChip(
        onClick = {},
        enabled = false,
        modifier = modifier,
        leadingIcon = {
            Icon(
                imageVector = Icons.Default.CloudOff,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
        },
        label = { Text(text = "Offline", style = MaterialTheme.typography.labelMedium) },
        colors = AssistChipDefaults.assistChipColors(
            disabledLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            disabledLeadingIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        ),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewOfflinePill() {
    BobaTheme {
        BOBAOfflinePill()
    }
}
