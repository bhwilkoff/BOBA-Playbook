package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaBrand

/**
 * First-run hint banner (ANDROID-DESIGN.md §6.8 + DECISIONS.md #031).
 *
 * Cyan-accent stripe + lightbulb icon + dismissible X. Distinct from:
 *  - [BOBABanner] — orange / persistent attention-required
 *  - [BOBAEmptyState] — structural, no dismiss
 *  - `Snackbar` — transient confirmation
 *
 * Use sparingly: only when the UI itself can't carry a non-obvious
 * teaching moment ("long-press to add", "tap a price to open"). Wire
 * with [com.bobaplaybook.app.hints.HintsStore] so each hint shows
 * once per device.
 */
@Composable
fun BOBAHintBanner(
    title: String,
    body: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(
            modifier = Modifier
                .background(BobaBrand.Cyan.copy(alpha = 0.06f))
                .padding(start = 4.dp),
            verticalAlignment = Alignment.Top,
        ) {
            // Cyan accent stripe
            Surface(
                color = BobaBrand.Cyan,
                modifier = Modifier
                    .width(4.dp)
                    .fillMaxWidth(),
            ) {}
            Row(
                modifier = Modifier
                    .padding(12.dp)
                    .fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Lightbulb,
                    contentDescription = null,
                    tint = BobaBrand.Cyan,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = body,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Dismiss hint",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
