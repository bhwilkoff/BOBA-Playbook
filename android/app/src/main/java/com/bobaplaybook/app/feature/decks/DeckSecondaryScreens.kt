@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Push destinations off the Decks editor — Manage / Rules / Legality.
 *
 * ANDROID-DESIGN.md §8.3 — secondary surfaces push as nav destinations
 * inside the Decks NavHost, never stacked sheets on top of the editor
 * (sheet-on-sheet anti-pattern §4.4).
 *
 * v1 ships TopAppBar + content placeholder. Real content arrives with
 * the M4 polish pass (deck management UI, rules content port, legality
 * checker against deck Format).
 */

@Composable
fun DeckManageScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    DeckSecondaryScaffold(title = "Manage Decks", onBack = onBack, modifier = modifier) {
        BOBAEmptyState(
            icon = Icons.Default.Save,
            headline = "Manage your decks",
            body = "Sign in to save decks across iOS, web, and Android. Saved decks live in Supabase decks/deck_cards tables.",
        )
    }
}

@Composable
fun DeckRulesScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    DeckSecondaryScaffold(title = "Deck Rules", onBack = onBack, modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BOBASectionHeader(title = "Standard Construction")
            Text(
                "• 8 Heroes (no duplicates) — your match-flow lineup\n" +
                "• 30 Plays + Bonus Plays — fielded sub-decks per match\n" +
                "• 1 Coach (optional) — passive bonus support\n" +
                "• Match Cost ceiling: 10 HD (Heroic Damage)",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "Hot Dog Constraint")
            Text(
                "Bonus Plays cap at 7 in a standard deck. Going beyond requires a Hot Dog parallel slot per the BoBA Comprehensive Rules Guide.",
                style = MaterialTheme.typography.bodyMedium,
            )

            BOBASectionHeader(title = "Tournament Format")
            Text(
                "Tournament play locks weapon distribution and adds a Sideboard. Tournament-legal subset enforced by the Legality screen.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
fun DeckLegalityScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    DeckSecondaryScaffold(title = "Legality", onBack = onBack, modifier = modifier) {
        BOBAEmptyState(
            icon = Icons.Default.Verified,
            headline = "Deck legality check",
            body = "Live legality validator (Standard / Tournament / League) lands when the Deck data layer ships. The check runs against the current draft and flags violations inline.",
        )
    }
}

@Composable
private fun DeckSecondaryScaffold(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        androidx.compose.foundation.layout.Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            content()
        }
    }
}
