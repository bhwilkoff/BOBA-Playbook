@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package com.bobaplaybook.app.feature.find

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.domain.showcase.Showcases
import com.bobaplaybook.core.ui.components.BOBASectionHeader
import com.bobaplaybook.core.ui.theme.BobaElements

/**
 * Full filter sheet (ANDROID-DESIGN.md §8.1 + iOS FilterSheetView).
 *
 * Sections, top to bottom:
 *  1. Sort
 *  2. Card Type (chip row)
 *  3. Showcase (chip row — WoBA, Rookie Inspired, Sports)
 *  4. Weapon (multi-select element chips)
 *  5. Has Image toggle
 *  6. Set / Treatment / Release dropdowns
 *  7. Power range (min / max) + presets row
 *  8. Clear All button at bottom
 *
 * Modal bottom sheet on compact. iPad-style popover is automatic via
 * window-size adaptation (Compose handles this internally).
 */
@Composable
fun FilterSheet(
    state: FindUiState,
    onEvent: (FindEvent) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        FilterSheetContent(state = state, onEvent = onEvent, onDismiss = onDismiss)
    }
}

@Composable
private fun FilterSheetContent(
    state: FindUiState,
    onEvent: (FindEvent) -> Unit,
    onDismiss: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        // Sticky header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Filters",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = { onEvent(FindEvent.ClearAllFilters) },
                enabled = state.activeFilterCount > 0,
            ) {
                Text("Clear all")
            }
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Done")
            }
        }
        HorizontalDivider()

        LazyColumn(modifier = Modifier.fillMaxSize()) {
            item { SortSection(state.sortOrder, onChange = { onEvent(FindEvent.SortChanged(it)) }) }
            item { Spacer(Modifier.height(8.dp)) }
            item { CardPurposeSection(state.cardPurpose, onChange = { onEvent(FindEvent.CardPurposeChanged(it)) }) }
            item { Spacer(Modifier.height(8.dp)) }
            item { ShowcaseSection(state.showcaseId, onChange = { onEvent(FindEvent.ShowcaseChanged(it)) }) }
            item { Spacer(Modifier.height(8.dp)) }
            item { WeaponSection(state.activeWeapons, onToggle = { onEvent(FindEvent.WeaponToggled(it)) }) }
            item { Spacer(Modifier.height(8.dp)) }
            item {
                HasImageRow(
                    enabled = state.hasImageOnly,
                    onToggle = { onEvent(FindEvent.HasImageToggled(it)) },
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item {
                DropdownPickerSection(
                    title = "Set",
                    options = state.availableSets,
                    selected = state.activeSet,
                    onChange = { onEvent(FindEvent.SetChanged(it)) },
                    allLabel = "All Sets",
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item {
                DropdownPickerSection(
                    title = "Treatment",
                    options = state.availableTreatments,
                    selected = state.activeTreatment,
                    onChange = { onEvent(FindEvent.TreatmentChanged(it)) },
                    allLabel = "All Treatments",
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item {
                DropdownPickerSection(
                    title = "Release",
                    options = state.availableReleases,
                    selected = state.activeRelease,
                    onChange = { onEvent(FindEvent.ReleaseChanged(it)) },
                    allLabel = "All Releases",
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item {
                PowerRangeSection(
                    powerMin = state.powerMin,
                    powerMax = state.powerMax,
                    onMin = { onEvent(FindEvent.PowerMinChanged(it)) },
                    onMax = { onEvent(FindEvent.PowerMaxChanged(it)) },
                    onPreset = { onEvent(FindEvent.PowerPresetApplied(it)) },
                )
            }
            item { Spacer(Modifier.height(48.dp)) }
        }
    }
}

@Composable
private fun SortSection(
    selected: SortOrder,
    onChange: (SortOrder) -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = "Sort")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SortOrder.entries.forEach { order ->
                FilterChip(
                    selected = order == selected,
                    onClick = { onChange(order) },
                    label = { Text(order.label, style = MaterialTheme.typography.labelMedium) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                )
            }
        }
    }
}

@Composable
private fun CardPurposeSection(
    selected: CardPurpose,
    onChange: (CardPurpose) -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = "Card type")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CardPurpose.entries.forEach { purpose ->
                FilterChip(
                    selected = purpose == selected,
                    onClick = { onChange(purpose) },
                    label = { Text(purpose.label, style = MaterialTheme.typography.labelMedium) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                )
            }
        }
    }
}

@Composable
private fun ShowcaseSection(
    selected: String?,
    onChange: (String?) -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = "Showcase")
        Text(
            text = "Curated subsets — more showcases (teams, cities, custom) planned.",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Showcases.all.forEach { showcase ->
                val isSelected = selected == showcase.id
                FilterChip(
                    selected = isSelected,
                    onClick = { onChange(if (isSelected) null else showcase.id) },
                    label = { Text(showcase.name, style = MaterialTheme.typography.labelMedium) },
                )
            }
        }
    }
}

@Composable
private fun WeaponSection(
    activeWeapons: kotlinx.collections.immutable.ImmutableSet<String>,
    onToggle: (String) -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = "Weapon")
        val canonical = remember {
            listOf("FIRE", "ICE", "STEEL", "BRAWL", "GLOW", "HEX", "GUM", "SUPER")
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            canonical.forEach { weapon ->
                val isSelected = weapon in activeWeapons
                val elementColor = BobaElements.forElement(weapon)
                FilterChip(
                    selected = isSelected,
                    onClick = { onToggle(weapon) },
                    label = {
                        Text(
                            weapon,
                            style = MaterialTheme.typography.labelMedium,
                            color = if (isSelected) Color.White else elementColor,
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = elementColor,
                        containerColor = elementColor.copy(alpha = 0.12f),
                    ),
                )
            }
        }
    }
}

@Composable
private fun HasImageRow(enabled: Boolean, onToggle: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Has Image Only", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = enabled, onCheckedChange = onToggle)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DropdownPickerSection(
    title: String,
    options: kotlinx.collections.immutable.ImmutableList<String>,
    selected: String?,
    onChange: (String?) -> Unit,
    allLabel: String,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = title)
        var expanded by remember { mutableStateOf(false) }
        androidx.compose.material3.ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = it },
        ) {
            // No label = { Text(title) } — BOBASectionHeader above
            // already names the field. M3 OutlinedTextField w/ both
            // an external section header AND its own label renders
            // the same word twice (e.g., "Set" header + "Set" floated
            // label inside the field).
            androidx.compose.material3.OutlinedTextField(
                value = selected ?: allLabel,
                onValueChange = {},
                readOnly = true,
                trailingIcon = {
                    androidx.compose.material3.ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(
                        type = androidx.compose.material3.ExposedDropdownMenuAnchorType.PrimaryNotEditable,
                        enabled = true,
                    ),
                colors = androidx.compose.material3.ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
            )
            androidx.compose.material3.DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
            ) {
                DropdownMenuItem(
                    text = { Text(allLabel) },
                    onClick = { onChange(null); expanded = false },
                    leadingIcon = {
                        if (selected == null) Icon(Icons.Default.Check, contentDescription = null)
                    },
                )
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option) },
                        onClick = { onChange(option); expanded = false },
                        leadingIcon = {
                            if (selected == option) Icon(Icons.Default.Check, contentDescription = null)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun PowerRangeSection(
    powerMin: Int?,
    powerMax: Int?,
    onMin: (Int?) -> Unit,
    onMax: (Int?) -> Unit,
    onPreset: (PowerPreset) -> Unit,
) {
    var minText by remember(powerMin) { mutableStateOf(powerMin?.toString().orEmpty()) }
    var maxText by remember(powerMax) { mutableStateOf(powerMax?.toString().orEmpty()) }

    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        BOBASectionHeader(title = "Power range")
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = minText,
                onValueChange = {
                    minText = it.filter { c -> c.isDigit() }
                    onMin(minText.toIntOrNull())
                },
                label = { Text("Min") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                modifier = Modifier.weight(1f),
            )
            Text("–")
            OutlinedTextField(
                value = maxText,
                onValueChange = {
                    maxText = it.filter { c -> c.isDigit() }
                    onMax(maxText.toIntOrNull())
                },
                label = { Text("Max") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            PowerPreset.all.forEach { preset ->
                val isActive = powerMin == preset.min && powerMax == preset.max
                FilterChip(
                    selected = isActive,
                    onClick = { onPreset(preset) },
                    label = { Text(preset.label, style = MaterialTheme.typography.labelSmall) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}
