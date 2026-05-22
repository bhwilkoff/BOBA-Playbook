@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.feature.collection.RainbowCatalogViewModel
import com.bobaplaybook.core.data.decks.DeckTemplate
import com.bobaplaybook.core.data.decks.DeckTemplateLoader
import kotlinx.coroutines.launch

/**
 * Template gallery — pick one of the five iOS-parity archetype decks
 * to seed the draft. Tap a template → DeckStore expands its bobaId
 * arrays against the live catalog and replaces the active draft.
 */
@Composable
fun TemplateGallerySheet(
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val decksViewModel: DecksViewModel = hiltViewModel()
    val catalogVm: RainbowCatalogViewModel = hiltViewModel()
    val catalog by catalogVm.cards.collectAsStateWithLifecycle()
    val draft by decksViewModel.draft.collectAsStateWithLifecycle()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current

    // Load templates lazily off the assets bundle on first sheet open.
    val templates by produceState(initialValue = emptyList<DeckTemplate>()) {
        value = DeckTemplateLoader().load(context)
    }
    // Tick 326 — haptic on template-load (parity with EmptyDeckCTA
    // tick 301). Loading 60+ cards is a "big-deal" moment; LongPress
    // signals magnitude before the Snackbar appears.
    val haptic = LocalHapticFeedback.current

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text("Start from a template", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Pre-built archetype decks. Tap to replace your current draft.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
            )
            HorizontalDivider()
            LazyColumn(modifier = Modifier.fillMaxWidth()) {
                items(items = templates, key = { it.id }) { template ->
                    // Tick 326 — 44×60 monogram tile + accent color
                    // (parity with EmptyDeckCTA tick 306). Each
                    // archetype gets a visual identity matching the
                    // iOS TemplateCard look. clearAndSetSemantics
                    // hides the decorative letter from TalkBack
                    // (tick 316 a11y parity).
                    val accent = templateAccent(template.id)
                    ListItem(
                        headlineContent = { Text(template.name) },
                        supportingContent = {
                            Text(
                                template.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        leadingContent = {
                            Box(
                                modifier = Modifier
                                    .size(width = 44.dp, height = 60.dp)
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(accent.copy(alpha = 0.25f))
                                    .border(1.5.dp, accent.copy(alpha = 0.5f), RoundedCornerShape(4.dp))
                                    .clearAndSetSemantics { },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    template.name.firstOrNull()?.uppercase() ?: "?",
                                    style = MaterialTheme.typography.headlineLarge,
                                    color = accent,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                val cards = template.expand(catalog)
                                if (cards.isNotEmpty()) {
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    // Capture pre-load draft state so the
                                    // Snackbar can call out a destructive
                                    // overwrite (parity with AddToDeckSheet
                                    // tick 96's "swapped your draft" surfacing).
                                    val hadDraft = draft.cards.isNotEmpty()
                                    decksViewModel.clear()
                                    decksViewModel.rename(template.name)
                                    cards.forEach { decksViewModel.add(it) }
                                    scope.launch {
                                        val msg = if (hadDraft)
                                            "Loaded \"${template.name}\" — your previous draft was replaced."
                                        else
                                            "Loaded \"${template.name}\""
                                        appSnackbar?.showSnackbar(msg)
                                    }
                                }
                                onDismiss()
                            },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}
