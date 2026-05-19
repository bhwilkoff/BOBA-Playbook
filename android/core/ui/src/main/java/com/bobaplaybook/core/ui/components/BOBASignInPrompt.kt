package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Inline "Sign in to do this" row (ANDROID-DESIGN.md §6.5).
 *
 * Other tabs (Decks save, Collection write, Profile edit) embed this at
 * the point of action instead of bouncing the user to a full-screen
 * wall. Tapping the button opens the auth flow (Credential Manager
 * bottom sheet, M7).
 *
 * Profile is Find-only — this prompt is the only auth-affordance
 * outside Find (per `feedback_profile_only_on_find`).
 */
@Composable
fun BOBASignInPrompt(
    title: String,
    body: String? = null,
    actionLabel: String = "Sign in",
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            body?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Button(
                onClick = onAction,
                modifier = Modifier.padding(top = 8.dp),
            ) {
                Text(actionLabel)
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewPrompt() {
    BobaTheme {
        BOBASignInPrompt(
            title = "Sign in to save decks",
            body = "Your decks sync across devices once you're signed in.",
            actionLabel = "Sign in",
            onAction = {},
        )
    }
}
