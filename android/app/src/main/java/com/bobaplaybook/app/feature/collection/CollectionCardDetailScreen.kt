@file:OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.model.CardFormatEligibility
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
import com.bobaplaybook.core.ui.format.formatUsdAmount
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.components.BOBAStatsGrid
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaElements

/**
 * Collection Card Detail — mirrors iOS CollectionCardDetailView.
 *
 * Tap a card in Collection grid → push to this screen showing every
 * owned copy of that card (multi-copy support), with per-copy
 * designation switch, condition/grade/pricing edit, delete, market
 * value summary. Anchored to a single bobaId.
 */
@Composable
fun CollectionCardDetailScreen(
    bobaId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val viewModel: CollectionViewModel = hiltViewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val savedDecks by viewModel.savedDecks.collectAsStateWithLifecycle()
    val catalog by viewModel.catalogCards.collectAsStateWithLifecycle()
    // Snackbar context for the per-copy "Removed · Undo" flow (tick 119).
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val appSnackbar = com.bobaplaybook.core.ui.snackbar.LocalAppSnackbar.current
    val card = remember(state, bobaId) {
        state.entriesByDesignation.values.flatten().firstOrNull { it.card.bobaId == bobaId }?.card
    }
    val copies = remember(state, bobaId) {
        state.entriesByDesignation.values.flatten().filter { it.card.bobaId == bobaId }
    }
    // Decks-containing — filter saved decks for any deck_cards row
    // matching THIS card's cardNumber. iOS uses bobaId but Supabase
    // `deck_cards` ships card_number only (see DeckRepository.kt).
    val decksContaining = remember(savedDecks, card) {
        val cn = card?.cardNumber ?: return@remember emptyList()
        savedDecks.filter { sd -> sd.cards.any { it.cardNumber == cn } }
    }
    // Other versions — same hero, different bobaId. Same shape as the
    // Find tab's card-detail "Other versions" section.
    val otherVersions = remember(catalog, card) {
        val c = card ?: return@remember emptyList()
        if (c.hero.isEmpty()) emptyList()
        else catalog.asSequence()
            .filter { it.bobaId != c.bobaId && it.hero.equals(c.hero, ignoreCase = true) }
            .filter { !it.imageFile.isNullOrEmpty() }
            .take(12)
            .toList()
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(card?.displayName ?: "Collection card") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        if (card == null) {
            BOBAEmptyState(
                headline = "Card not in collection",
                body = "This card isn't owned. Add it to your collection from card detail.",
                modifier = Modifier.fillMaxSize().padding(padding),
            )
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            ArtPanel(card)
            BOBAStatsGrid(
                cardNumber = card.cardNumber,
                cardType   = card.cardType,
                treatment  = card.treatment,
                weapon     = card.element.takeIf { !card.isSealed }?.lowercase()?.replaceFirstChar { it.uppercase() },
                set        = card.set,
                subSet     = card.subSet,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))
            // Tick 434 — locale-format the count (web tick 433 + iOS parity).
            BOBASectionHeader(
                title = "Your copies (${java.text.NumberFormat.getInstance(java.util.Locale.US).format(copies.size)})",
            )
            copies.forEach { entry ->
                CopyRow(
                    entry = entry,
                    onDesignationChange = { newDesignation ->
                        viewModel.updateDesignation(entry.userCard.id, newDesignation)
                    },
                    onDelete = {
                        // Capture the user-card fields BEFORE remove so
                        // Undo re-adds with the same designation +
                        // purchase / asking / condition / notes (tick 99
                        // enabled this on the add path). Without this,
                        // an accidental delete loses provenance metadata
                        // the user spent time entering.
                        val captured = entry.userCard
                        val capturedCard = entry.card
                        viewModel.remove(entry.userCard.id)
                        scope.launch {
                            val result = appSnackbar?.showSnackbar(
                                message = "Removed ${capturedCard.displayName}",
                                actionLabel = "Undo",
                                duration = androidx.compose.material3.SnackbarDuration.Short,
                            )
                            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                                viewModel.add(
                                    cardBobaId    = capturedCard.bobaId,
                                    designation   = captured.designation,
                                    quantity      = captured.quantity,
                                    purchasePrice = captured.purchasePrice,
                                    askingPrice   = captured.askingPrice,
                                    condition     = captured.condition,
                                    notes         = captured.notes,
                                )
                            }
                        }
                    },
                    onSaveEdits = { purchase, asking, condition, notes, grade, gradingCompany ->
                        viewModel.updateEntry(
                            userCardId = entry.userCard.id,
                            purchasePrice = purchase,
                            askingPrice = asking,
                            condition = condition,
                            notes = notes,
                            grade = grade,
                            gradingCompany = gradingCompany,
                        )
                        // Confirmation Snackbar — without it the user has
                        // no signal that the save persisted (the in-place
                        // form values look identical pre/post-save). Tick
                        // 151 parity with iOS dismissal-as-confirmation.
                        scope.launch {
                            appSnackbar?.showSnackbar("Saved edits to ${entry.card.displayName}")
                        }
                    },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
            // Add another copy — defaults to Personal designation; user can
            // change immediately via the per-copy chip strip below.
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                OutlinedButton(
                    onClick = { viewModel.add(bobaId, Designation.PERSONAL) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Add another copy")
                }
            }

            // "Decks containing this card" — iOS DESIGN.md §8.4 surfaces
            // this in CollectionCardDetail so coaches see their own decks
            // using the card. Tap-through is a future iteration; v1
            // renders the list for visibility.
            if (decksContaining.isNotEmpty()) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
                BOBASectionHeader(title = "Decks with this card (${decksContaining.size})")
                decksContaining.forEach { deck ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(deck.name, style = MaterialTheme.typography.titleSmall)
                            deck.archetype?.takeIf { it.isNotBlank() }?.let { arch ->
                                Text(
                                    arch,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        val qty = deck.cards.firstOrNull { it.cardNumber == card.cardNumber }?.quantity ?: 0
                        if (qty > 1) {
                            Text(
                                "×$qty",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }

            // "Other versions" — same hero, different treatment. Tap an
            // alt to navigate to that card's detail (read-only — Add to
            // Collection lives in the catalog Find tab card detail).
            if (otherVersions.isNotEmpty()) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
                BOBASectionHeader(title = "Other versions of ${card.displayName}")
                androidx.compose.foundation.lazy.LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(items = otherVersions, key = { it.bobaId }) { other ->
                        Box(modifier = Modifier.width(80.dp)) {
                            com.bobaplaybook.core.ui.components.BOBACardCell(
                                imageFile = other.imageFile,
                                contentDescription = other.displayName,
                                printRunLabel = other.printRunLabel,
                                formatLegalityHint = CardFormatEligibility.restrictedLegalAbbrev(other),
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(48.dp))
        }
    }
}

@Composable
private fun ArtPanel(card: Card) {
    val context = LocalContext.current
    val accent = if (card.isSealed) BobaBrand.Orange else BobaElements.forElement(card.element)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(420.dp)
            .background(Brush.verticalGradient(colors = listOf(accent.copy(alpha = 0.25f), BobaBrand.NearBlack))),
        contentAlignment = Alignment.Center,
    ) {
        // Route via the Card overload so sealed products hit
        // /sealed/optimized/ instead of /full/ (CDN parity with iOS).
        val fullUrl = remember(card.bobaId, card.imageFile) { CDN.fullUrl(card) }
        if (fullUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(fullUrl).crossfade(200).build(),
                contentDescription = card.displayName,
                modifier = Modifier.aspectRatio(5f / 7f).clip(MaterialTheme.shapes.large),
            )
        } else {
            Text(
                text = card.displayName,
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CopyRow(
    entry: CollectionEntry,
    onDesignationChange: (Designation) -> Unit,
    onDelete: () -> Unit,
    onSaveEdits: (purchase: Double?, asking: Double?, condition: String?, notes: String?, grade: String?, gradingCompany: String?) -> Unit,
) {
    var deleteOpen by rememberSaveable { mutableStateOf(false) }
    var editOpen by rememberSaveable { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "Copy",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            entry.userCard.quantity.takeIf { it > 1 }?.let {
                Text("×$it", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            BOBAIconTooltip("Edit this copy") {
                IconButton(onClick = { editOpen = true }) {
                    Icon(Icons.Default.Edit, contentDescription = "Edit", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            BOBAIconTooltip("Delete this copy") {
                IconButton(onClick = { deleteOpen = true }) {
                    Icon(Icons.Default.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
                }
            }
        }
        // Designation switcher
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Designation.entries.forEach { d ->
                FilterChip(
                    selected = entry.userCard.designation == d,
                    onClick = { onDesignationChange(d) },
                    label = { Text(d.shortLabel, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }
        // Pricing summary
        entry.userCard.estimatedValue?.let { value ->
            Text(
                "Market: $${value.formatUsdAmount()}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        entry.userCard.purchasePrice?.let { paid ->
            Text(
                "Paid: $${paid.formatUsdAmount()}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        // Tick 241 — grade + condition pill row (TCG-collector research:
        // slab tracking is a top user-requested feature; AddToCollection
        // captured it since the sheet shipped but tick 239 unblocked the
        // domain-boundary drop). Combined into one row when both fire.
        run {
            val condition = entry.userCard.condition?.takeIf { it.isNotBlank() }
            val grade = entry.userCard.grade?.takeIf { it.isNotBlank() }
            val company = entry.userCard.gradingCompany?.takeIf { it.isNotBlank() }
            val slab = if (grade != null) {
                if (company != null) "$company $grade" else "Graded $grade"
            } else null
            if (condition != null || slab != null) {
                Row(
                    modifier = Modifier.padding(top = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    condition?.let { c ->
                        androidx.compose.material3.AssistChip(
                            onClick = {},
                            enabled = false,
                            label = { Text(c, style = MaterialTheme.typography.labelSmall) },
                        )
                    }
                    slab?.let { s ->
                        androidx.compose.material3.AssistChip(
                            onClick = {},
                            enabled = false,
                            label = {
                                Text(
                                    s,
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                )
                            },
                            // Slab pill gets the brand orange — graded cards
                            // are uncommon, the visual weight is intentional.
                            colors = androidx.compose.material3.AssistChipDefaults.assistChipColors(
                                disabledLabelColor = com.bobaplaybook.core.ui.theme.BobaBrand.Orange,
                                disabledContainerColor = com.bobaplaybook.core.ui.theme.BobaBrand.Orange.copy(alpha = 0.15f),
                            ),
                        )
                    }
                }
            }
        }
        entry.userCard.notes?.takeIf { it.isNotBlank() }?.let { notes ->
            Text(
                notes,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
    if (deleteOpen) {
        AlertDialog(
            onDismissRequest = { deleteOpen = false },
            title = { Text("Remove this copy?") },
            text = { Text("This removes one copy of ${entry.card.displayName} from your collection. The catalog card stays available.") },
            confirmButton = {
                TextButton(onClick = { deleteOpen = false; onDelete() }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteOpen = false }) { Text("Cancel") }
            },
        )
    }
    if (editOpen) {
        EditCopySheet(
            entry = entry,
            onDismiss = { editOpen = false },
            onSave = { purchase, asking, condition, notes, grade, gradingCompany ->
                onSaveEdits(purchase, asking, condition, notes, grade, gradingCompany)
                editOpen = false
            },
        )
    }
}

/**
 * Edit-copy sheet — patches purchase price / asking price / condition
 * / notes on an existing user_card row. Mirrors iOS
 * EditCollectionEntrySheet from CollectionCardDetailView.swift.
 *
 * Doesn't switch designation (that's the per-row chip strip) and
 * doesn't remove the copy (delete IconButton handles that). Pure
 * field-level edit.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun EditCopySheet(
    entry: CollectionEntry,
    onDismiss: () -> Unit,
    onSave: (purchase: Double?, asking: Double?, condition: String?, notes: String?, grade: String?, gradingCompany: String?) -> Unit,
) {
    var purchaseText by rememberSaveable { mutableStateOf(entry.userCard.purchasePrice?.toString().orEmpty()) }
    var askingText by rememberSaveable { mutableStateOf(entry.userCard.askingPrice?.toString().orEmpty()) }
    var conditionPick by rememberSaveable { mutableStateOf<String?>(entry.userCard.condition) }
    // Tick 256 — grade + gradingCompany now editable post-create. iOS
    // EditCollectionEntrySheet has the same fields; Android was missing
    // them (data layer captured them since the AddToCollection sheet
    // shipped — tick 239 unblocked the domain boundary).
    var gradingCompanyPick by rememberSaveable { mutableStateOf<String?>(entry.userCard.gradingCompany) }
    var gradeText by rememberSaveable { mutableStateOf(entry.userCard.grade.orEmpty()) }
    var notesText by rememberSaveable { mutableStateOf(entry.userCard.notes.orEmpty()) }
    val conditions = remember { listOf("Mint", "Near Mint", "Excellent", "Good", "Poor") }
    val gradingCompanies = remember { listOf("PSA", "BGS", "SGC", "CGC") }

    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Edit copy", style = MaterialTheme.typography.headlineSmall)
            Text(
                entry.card.displayName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // Condition chips
            Text("Condition", style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                conditions.forEach { c ->
                    FilterChip(
                        selected = conditionPick == c,
                        onClick = { conditionPick = if (conditionPick == c) null else c },
                        label = { Text(c, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }
            // Grade — third-party slab grade + grading company. Optional;
            // most owned cards are raw (no slab).
            Text("Grade (optional)", style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                gradingCompanies.forEach { co ->
                    FilterChip(
                        selected = gradingCompanyPick == co,
                        onClick = { gradingCompanyPick = if (gradingCompanyPick == co) null else co },
                        label = { Text(co, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }
            if (gradingCompanyPick != null) {
                androidx.compose.material3.OutlinedTextField(
                    value = gradeText,
                    onValueChange = { gradeText = it.filter { ch -> ch.isDigit() || ch == '.' }.take(4) },
                    label = { Text("Grade (e.g. 10, 9.5)") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            // Pricing
            androidx.compose.material3.OutlinedTextField(
                value = purchaseText,
                onValueChange = { purchaseText = it.filter { ch -> ch.isDigit() || ch == '.' } },
                label = { Text("Purchase price ($)") },
                singleLine = true,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            androidx.compose.material3.OutlinedTextField(
                value = askingText,
                onValueChange = { askingText = it.filter { ch -> ch.isDigit() || ch == '.' } },
                label = { Text("Asking price ($) — For Sale / Trade") },
                singleLine = true,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            // Notes
            androidx.compose.material3.OutlinedTextField(
                value = notesText,
                onValueChange = { notesText = it },
                label = { Text("Notes") },
                minLines = 2,
                maxLines = 5,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                androidx.compose.material3.Button(
                    onClick = {
                        onSave(
                            purchaseText.toDoubleOrNull(),
                            askingText.toDoubleOrNull(),
                            conditionPick,
                            notesText.takeIf { it.isNotBlank() },
                            gradeText.takeIf { it.isNotBlank() && gradingCompanyPick != null },
                            gradingCompanyPick,
                        )
                        // Auto-dismiss on save — parity with the iOS
                        // EditCollectionEntrySheet pattern. Was the
                        // missing companion to tick 99's onSave wiring.
                        onDismiss()
                    },
                ) { Text("Save") }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
