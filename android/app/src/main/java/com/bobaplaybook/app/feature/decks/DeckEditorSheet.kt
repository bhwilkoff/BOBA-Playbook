@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.decks

import androidx.compose.foundation.clickable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import kotlinx.coroutines.launch

/**
 * Deck editor — full-screen ModalBottomSheet on compact (ANDROID-
 * DESIGN.md §8.3). Tap the summary bar → this opens.
 *
 *  - Editable name field at top
 *  - Stats row (hero/play/bonus/HD with legality chip)
 *  - Sectioned card list (Heroes / Plays / Bonus / Coach)
 *  - Remove via swipe / tap delete on each row
 *  - Save action triggers Supabase persist when M7 wires it
 */
@Composable
fun DeckEditorSheet(
    draft: DeckDraft,
    isSignedIn: Boolean,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    onGenerateWall: () -> Unit = {},
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        DeckEditorContent(
            draft = draft,
            isSignedIn = isSignedIn,
            onDismiss = onDismiss,
            onRename = onRename,
            onRemove = onRemove,
            onSave = onSave,
            onSignInRequest = onSignInRequest,
            onGenerateWall = onGenerateWall,
        )
    }
}

/**
 * Inline editor variant — same body content as the ModalBottomSheet
 * editor, but rendered directly inside a tablet's right-pane Surface.
 * No close button (the pane is always-visible on tablet).
 */
@Composable
fun DeckEditorContentInline(
    draft: DeckDraft,
    isSignedIn: Boolean,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    onOpenRules: () -> Unit,
    onOpenLegality: () -> Unit,
    onGenerateWall: () -> Unit = {},
) {
    // Bind directly to draft.name so loading a saved deck via the
    // Manage screen actually updates the visible field. Earlier this
    // captured draft.name via `var name by remember` which froze the
    // initial value — typing worked, but loadSaved silently failed
    // to refresh the TextField.
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = draft.name,
                onValueChange = { onRename(it) },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }

        StatsRow(draft = draft)
        PlayModeChipStrip(draft = draft)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            androidx.compose.material3.OutlinedButton(onClick = onOpenRules) { Text("Rules") }
            androidx.compose.material3.OutlinedButton(onClick = onOpenLegality) { Text("Legality") }
            androidx.compose.material3.OutlinedButton(
                onClick = onGenerateWall,
                enabled = draft.cards.isNotEmpty(),
            ) { Text("Wall") }
            Spacer(Modifier.weight(1f))
            SaveOrSignInButton(
                isSignedIn = isSignedIn,
                hasCards = draft.cards.isNotEmpty(),
                onSave = onSave,
                onSignInRequest = onSignInRequest,
                hasName = draft.name.trim().isNotEmpty(),
            )
        }

        HorizontalDivider()

        if (draft.cards.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.Save,
                headline = "Empty draft",
                body = "Long-press cards on the Decks tab to add them.",
                modifier = Modifier.fillMaxSize(),
            )
            return
        }

        SectionedCardList(
            draft = draft,
            onRemove = onRemove,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun DeckEditorContent(
    draft: DeckDraft,
    isSignedIn: Boolean,
    onDismiss: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    onGenerateWall: () -> Unit = {},
) {
    // Bind directly to draft.name — see DeckEditorContentInline
    // comment for the same fix at the inline variant.

    Column(
        modifier = Modifier.fillMaxSize(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
            OutlinedTextField(
                value = draft.name,
                onValueChange = { onRename(it) },
                label = { Text("Deck name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            // Generate-deck-wall affordance (DESIGN.md §8.8 + web tick 9
            // parity). Reuses WallShareHelper via DeckWallSheet.
            IconButton(
                onClick = onGenerateWall,
                enabled = draft.cards.isNotEmpty(),
            ) {
                Icon(Icons.Default.ViewModule, contentDescription = "Generate deck wall")
            }
            SaveOrSignInButton(
                isSignedIn = isSignedIn,
                hasCards = draft.cards.isNotEmpty(),
                onSave = onSave,
                onSignInRequest = onSignInRequest,
                hasName = draft.name.trim().isNotEmpty(),
            )
        }

        StatsRow(draft = draft)
        PlayModeChipStrip(draft = draft)

        HorizontalDivider()

        if (draft.cards.isEmpty()) {
            BOBAEmptyState(
                icon = Icons.Default.Save,
                headline = "Empty draft",
                body = "Long-press cards on the Decks tab to add them. Or scan a real deck via the scan icon.",
                modifier = Modifier.fillMaxSize(),
            )
            return
        }

        SectionedCardList(
            draft = draft,
            onRemove = onRemove,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/**
 * iOS parity: SAVE button morphs to SIGN IN when signed-out. Tapping
 * routes to the Profile destination (Find tab) for sign-in. Avoids
 * the dead-click where signed-out users tap Save with no feedback.
 *
 * See `feedback_profile_only_on_find` memory + DESIGN.md §6.5
 * inline-sign-in pattern.
 */
@Composable
private fun SaveOrSignInButton(
    isSignedIn: Boolean,
    hasCards: Boolean,
    onSave: () -> Unit,
    onSignInRequest: () -> Unit,
    hasName: Boolean = true,
) {
    if (isSignedIn) {
        Button(
            onClick = onSave,
            // Require both at least one card AND a non-empty name —
            // the viewModel rejects empty names too but disabling the
            // button keeps the user from a failed-save snackbar loop.
            enabled = hasCards && hasName,
        ) {
            Icon(
                Icons.Default.Save,
                contentDescription = null,
                modifier = Modifier.width(18.dp).height(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text("Save")
        }
    } else {
        Button(onClick = onSignInRequest) {
            Text("Sign in")
        }
    }
}

@Composable
private fun PlayModeChipStrip(draft: DeckDraft) {
    val vm: DecksViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val modes = remember { DeckPlayMode.entries }
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        modes.forEachIndexed { index, mode ->
            SegmentedButton(
                selected = mode == draft.playMode,
                onClick = { vm.setPlayMode(mode) },
                shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                icon = {},
            ) {
                Text(mode.label, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
    Text(
        text = draft.playMode.description,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
}

@Composable
private fun StatsRow(draft: DeckDraft) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Each chip tints red when it's BLOCKING legality. Heroes
        // and Plays count exact equality (== cap) as the legal
        // target; Bonus and HD are ≤-cap so only the strictly-over
        // case is "wrong" — under-cap is just an unfinished deck,
        // not an illegal one.
        StatChip(
            "Heroes",
            "${draft.heroCount}/${draft.heroCap}",
            overBudget = draft.heroCount > draft.heroCap,
        )
        StatChip(
            "Plays",
            "${draft.playCount + draft.bonusCount}/${draft.playCap}",
            overBudget = (draft.playCount + draft.bonusCount) > draft.playCap,
        )
        StatChip(
            "Bonus",
            "${draft.bonusCount}/${draft.bonusCap}",
            overBudget = draft.bonusCount > draft.bonusCap,
        )
        StatChip(
            "HD",
            "${draft.totalHD}/${draft.hdCap}",
            overBudget = draft.totalHD > draft.hdCap,
        )
        // DBS chip — Playmaker format only; matches iOS DeckBuilderView
        // line 428 (effectiveEnforceDBS gate). Tints red when over budget.
        // Tap → DBSInfoSheet (existing explainer shipped on Card detail
        // tick around launch). Tick 134 makes the explainer reachable
        // from the deck editor too — new coaches building a Playmaker
        // deck see "DBS 750/1000" and now have a one-tap path to learn
        // what DBS even is.
        if (draft.enforcesDBS) {
            var dbsInfoOpen by remember { mutableStateOf(false) }
            StatChip(
                label = "DBS",
                value = "${draft.totalDBS}/${draft.dbsBudget}",
                overBudget = draft.totalDBS > draft.dbsBudget,
                onTap = { dbsInfoOpen = true },
            )
            if (dbsInfoOpen) {
                com.bobaplaybook.app.feature.carddetail.DBSInfoSheet(
                    onDismiss = { dbsInfoOpen = false },
                )
            }
        }
        Spacer(Modifier.weight(1f))
        if (draft.isStandardLegal) {
            androidx.compose.material3.Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = null,
                        modifier = Modifier.width(14.dp).height(14.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        "Legal",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
    }
}

@Composable
private fun StatChip(
    label: String,
    value: String,
    overBudget: Boolean = false,
    onTap: (() -> Unit)? = null,
) {
    val baseModifier = if (onTap != null) Modifier.clickable { onTap() } else Modifier
    Surface(
        color = if (overBudget) MaterialTheme.colorScheme.errorContainer
                else MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.small,
        modifier = baseModifier,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.titleSmall,
                color = if (overBudget) MaterialTheme.colorScheme.onErrorContainer
                        else MaterialTheme.colorScheme.onSurface,
            )
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = if (overBudget) MaterialTheme.colorScheme.onErrorContainer
                        else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SectionedCardList(
    draft: DeckDraft,
    onRemove: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Section the deck the same way iOS DecksView does — heroes by power
    // tier (descending), then plays (by cost asc), bonus plays (cost asc),
    // hot dogs (alphabetical). Coach cards are a Playmaker-format extra
    // and only render when present. Power-tier subheaders inside Heroes
    // mirror iOS's `pwrSubheader(...)` so the deck reads the same shape
    // on both platforms.
    val heroesByTier = remember(draft.cards) {
        draft.cards
            .filter { it.cardType.equals("Hero", ignoreCase = true) }
            .groupBy { it.power ?: 0 }
            .toSortedMap(compareByDescending { it })
    }
    val plays = remember(draft.cards) {
        draft.cards
            .filter { it.cardType.contains("Play", ignoreCase = true) && !it.cardType.contains("Bonus", ignoreCase = true) }
            .sortedWith(compareBy({ it.cost ?: 999 }, { it.displayName }))
    }
    val bonus = remember(draft.cards) {
        draft.cards
            .filter { it.cardType.contains("Bonus", ignoreCase = true) }
            .sortedWith(compareBy({ it.cost ?: 999 }, { it.displayName }))
    }
    val hotDogs = remember(draft.cards) {
        draft.cards
            .filter { it.cardType.contains("Hot Dog", ignoreCase = true) || it.cardType.contains("HotDog", ignoreCase = true) }
            .sortedBy { it.displayName }
    }
    val coach = remember(draft.cards) {
        draft.cards
            .filter { it.cardType.contains("Coach", ignoreCase = true) }
            .sortedBy { it.displayName }
    }
    val heroCount = heroesByTier.values.sumOf { it.size }

    if (draft.cards.isEmpty()) {
        EmptyDeckCTA(modifier = modifier)
        return
    }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        if (heroCount > 0) {
            item(key = "header-heroes") {
                BOBASectionHeader(title = "Heroes ($heroCount)")
            }
            heroesByTier.forEach { (power, cards) ->
                item(key = "tier-$power") {
                    PowerTierSubheader(power = power, weaponBreakdown = heroWeaponBreakdown(cards))
                }
                items(
                    items = cards,
                    key = { "hero-${it.bobaId}" },
                    contentType = { "card-row" },
                ) { card ->
                    DeckCardRow(card = card, onRemove = { onRemove(card.bobaId) })
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
        listOf(
            "Plays" to plays,
            "Bonus Plays" to bonus,
            "Hot Dogs" to hotDogs,
            "Coach" to coach,
        ).forEach { (label, cards) ->
            if (cards.isEmpty()) return@forEach
            item(key = "header-$label") {
                BOBASectionHeader(title = "$label (${cards.size})")
            }
            items(
                items = cards,
                key = { "$label-${it.bobaId}" },
                contentType = { "card-row" },
            ) { card ->
                DeckCardRow(card = card, onRemove = { onRemove(card.bobaId) })
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

/**
 * Empty-deck CTA — port of iOS DecksView.emptyDeckCTA. Inline template
 * gallery with one row per archetype (Lockdown Locker, Frozen Tempo,
 * Draw and Adapt, Glow Sacrifice, Brawl Beatdown). Tapping a row loads
 * the template's cards into the active draft so a new user has a real
 * starting point instead of an opaque "empty draft" prompt.
 */
@Composable
private fun EmptyDeckCTA(modifier: Modifier = Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val decksVm: DecksViewModel = androidx.hilt.navigation.compose.hiltViewModel()
    val catalogVm: com.bobaplaybook.app.feature.collection.RainbowCatalogViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val catalog by catalogVm.cards.collectAsStateWithLifecycle(initialValue = emptyList())
    val templates by androidx.compose.runtime.produceState(initialValue = emptyList<com.bobaplaybook.core.data.decks.DeckTemplate>()) {
        value = com.bobaplaybook.core.data.decks.DeckTemplateLoader().load(context)
    }
    // Tick 164 — confirm template load with a Snackbar. The visual
    // flip from empty-state → populated editor IS a signal, but the
    // explicit "Loaded X" message matches TemplateGallerySheet's
    // tick-136 pattern + gives a verbal cue ("yes, the tap registered")
    // alongside the visual change.
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    // Tick 301 — haptic on template load. Loading a 60-card deck is
    // a "big-deal" moment (vs Quick Add of a single card); LongPress
    // feedback signals the magnitude of what just happened.
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item("empty-cta-head") {
            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                Text(
                    "Build your first deck",
                    style = MaterialTheme.typography.headlineSmall,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Long-press any card on the Decks tab to start. Or pick a template below.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item("empty-cta-divider") {
            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        }
        item("empty-cta-templates-header") {
            BOBASectionHeader(title = "START FROM A TEMPLATE")
        }
        items(items = templates, key = { it.id }) { template ->
            val accent = templateAccent(template.id)
            Surface(
                color = accent.copy(alpha = 0.08f),
                contentColor = MaterialTheme.colorScheme.onSurface,
                shape = MaterialTheme.shapes.medium,
                border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.4f)),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .clickable {
                        val cards = template.expand(catalog)
                        if (cards.isNotEmpty()) {
                            haptic.performHapticFeedback(
                                androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress
                            )
                            decksVm.clear()
                            decksVm.rename(template.name)
                            cards.forEach { decksVm.add(it) }
                            scope.launch {
                                appSnackbar?.showSnackbar("Loaded \"${template.name}\"")
                            }
                        }
                    },
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Icon(
                        imageVector = Icons.Default.ViewModule,
                        contentDescription = null,
                        tint = accent,
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            template.name,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            template.description,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 3,
                        )
                    }
                }
            }
        }
    }
}

/** Match iOS DecksView.templateAccent — element color per archetype id. */
@Composable
private fun templateAccent(templateId: String) = when (templateId) {
    "lockdown-locker" -> com.bobaplaybook.core.ui.theme.BobaElements.Steel
    "frozen-tempo"    -> com.bobaplaybook.core.ui.theme.BobaElements.Ice
    "draw-and-adapt"  -> com.bobaplaybook.core.ui.theme.BobaBrand.Cyan
    "glow-sacrifice"  -> com.bobaplaybook.core.ui.theme.BobaElements.Glow
    "brawl-beatdown"  -> com.bobaplaybook.core.ui.theme.BobaElements.Brawl
    else              -> com.bobaplaybook.core.ui.theme.BobaBrand.Cyan
}

/**
 * Inline "PWR 160 · Maverick (FIRE×2), Cruschman (ICE)" header — same
 * shape as iOS DecksView.pwrSubheader so heroes are scannable by tier.
 */
@Composable
private fun PowerTierSubheader(power: Int, weaponBreakdown: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "PWR $power",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        if (weaponBreakdown.isNotBlank()) {
            Text(
                weaponBreakdown,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Per-tier "Maverick (FIRE×2, ICE)" breakdown — iOS DecksView parity. */
private fun heroWeaponBreakdown(cards: List<Card>): String {
    val elementOrder = listOf("FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER", "CYBER", "ALT", "NONE")
    val byHero = cards.groupBy { it.hero.ifEmpty { it.name } }
    return byHero.entries
        .sortedByDescending { it.value.size }
        .joinToString(" · ") { (hero, hcards) ->
            val weapons = hcards
                .groupingBy { it.element.uppercase() }
                .eachCount()
                .entries
                .sortedBy { elementOrder.indexOf(it.key).let { i -> if (i < 0) 99 else i } }
                .joinToString(", ") { (el, n) -> if (n > 1) "$el×$n" else el }
            "$hero ($weapons)"
        }
}

@Composable
private fun DeckCardRow(card: Card, onRemove: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Bigger thumbnail (72×100 — 5:7) so the artwork actually reads.
        // The previous 48×67 felt cramped and indistinguishable from a
        // mod tool. Matches iOS DeckCardRow's visual weight.
        Box(modifier = Modifier.width(72.dp).height(100.dp)) {
            BOBACardCell(
                imageFile = card.imageFile,
                isSealed = card.isSealed,
                contentDescription = card.displayName,
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                card.displayName,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Weapon pill (element-tinted) — primary attribute, in
                // the user's vocabulary. Mirrors iOS card-row pill chip.
                val elementUpper = card.element.uppercase()
                val elementColor = com.bobaplaybook.core.ui.theme.BobaElements.forElement(elementUpper)
                Surface(
                    color = elementColor.copy(alpha = 0.18f),
                    contentColor = elementColor,
                    shape = MaterialTheme.shapes.small,
                ) {
                    Text(
                        elementUpper,
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
                Text(
                    card.cardNumber,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                card.power?.let { p ->
                    Text(
                        "PWR $p",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                card.cost?.let { c ->
                    Text(
                        "${c}c",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Remove from deck",
                tint = MaterialTheme.colorScheme.error,
            )
        }
    }
}
