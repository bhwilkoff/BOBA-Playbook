package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Canonical empty state (ANDROID-DESIGN.md §6.7).
 *
 * Compose has no `ContentUnavailableView` analog; this is BOBA's
 * single canonical surface for all "no items" / "no results" cases.
 *
 * Use brand-voice headline + productive next-action button. Bad:
 * "No items." Good: *"No decks yet — start with a template."* with
 * a button to the template gallery.
 *
 * Distinct from:
 *  - [BOBABanner] — orange / persistent attention required
 *  - [BOBAHintBanner] (when shipped) — cyan / first-run dismissible
 *  - `Snackbar` — transient confirmation
 */
@Composable
fun BOBAEmptyState(
    icon: ImageVector? = null,
    headline: String,
    body: String? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    // Optional secondary text-button rendered beneath the primary
    // action. Use for "alternative path" CTAs (e.g. "Open Whatnot" when
    // no breaks load), not for repeating the primary intent.
    secondaryActionLabel: String? = null,
    onSecondaryAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        icon?.let {
            Icon(
                imageVector = it,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            text = headline,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 12.dp),
        )
        body?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        if (actionLabel != null && onAction != null) {
            FilledTonalButton(
                onClick = onAction,
                modifier = Modifier.padding(top = 24.dp),
            ) {
                Text(text = actionLabel)
            }
        }
        if (secondaryActionLabel != null && onSecondaryAction != null) {
            TextButton(
                onClick = onSecondaryAction,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Text(text = secondaryActionLabel)
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewEmpty() {
    BobaTheme {
        BOBAEmptyState(
            headline = "No decks yet",
            body = "Start with a template or build from scratch.",
            actionLabel = "Browse templates",
            onAction = {},
        )
    }
}
