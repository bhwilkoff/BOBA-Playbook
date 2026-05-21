@file:OptIn(
    ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import androidx.compose.foundation.layout.Row
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.core.data.rainbows.CustomRainbow
import com.bobaplaybook.core.data.rainbows.RainbowCriteria
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Custom rainbow editor — Compose port of the iOS editor
 * (v2.219-v2.221). All eight criterion dimensions surface:
 * Heroes / Weapons / Treatments / Sets / Sub-sets / Releases /
 * Card types, plus the Inspired Ink toggle. (Web tick 16 + iOS
 * `CustomRainbowEditorSheet` already expose the full set; tick 81
 * closes the Android polish gap.)
 *
 * Two modes:
 *  - `existing == null` → create mode. Save → vm.create.
 *  - `existing != null` → edit mode. State pre-filled. Save →
 *    vm.update. Title swaps to "Edit". (Tick 61 Android parity with
 *    web tick 15 + iOS CustomRainbowEditorSheet.)
 */
@Composable
fun CustomRainbowEditorSheet(
    onDismiss: () -> Unit,
    existing: CustomRainbow? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val vm: CustomRainbowsViewModel = hiltViewModel()
    val catalogVm: RainbowCatalogViewModel = hiltViewModel()
    val catalog by catalogVm.cards.collectAsStateWithLifecycle()

    // Pre-fill from `existing` on first composition. After that, the
    // user's edits drive state — re-keying on existing.id ensures
    // opening the editor for a different rainbow resets correctly.
    var name by rememberSavedField(existing?.name ?: "", existing?.id)
    var heroes by rememberSavedSet(existing?.criteria?.heroes?.toSet() ?: emptySet(), existing?.id)
    var elements by rememberSavedSet(existing?.criteria?.elements?.toSet() ?: emptySet(), existing?.id)
    var treatments by rememberSavedSet(existing?.criteria?.treatments?.toSet() ?: emptySet(), existing?.id)
    var sets by rememberSavedSet(existing?.criteria?.sets?.toSet() ?: emptySet(), existing?.id)
    var subSets by rememberSavedSet(existing?.criteria?.subSets?.toSet() ?: emptySet(), existing?.id)
    var releases by rememberSavedSet(existing?.criteria?.releases?.toSet() ?: emptySet(), existing?.id)
    var cardTypes by rememberSavedSet(existing?.criteria?.cardTypes?.toSet() ?: emptySet(), existing?.id)
    var inspiredInkOnly by rememberSavedField(existing?.criteria?.inspiredInkOnly ?: false, existing?.id)

    // Derive picker options from the live catalog so options stay in
    // sync as the catalog grows.
    val heroOptions      = remember(catalog) { catalog.map { it.hero }.filter { it.isNotBlank() }.distinct().sorted().take(60) }
    val elementOptions   = remember(catalog) { catalog.map { it.element }.filter { it.isNotBlank() }.distinct().sorted() }
    val treatmentOptions = remember(catalog) { catalog.mapNotNull { it.treatment }.filter { it.isNotBlank() }.distinct().sorted().take(40) }
    val setOptions       = remember(catalog) { catalog.map { it.set }.filter { it.isNotBlank() }.distinct().sorted() }
    val subSetOptions    = remember(catalog) { catalog.mapNotNull { it.subSet }.filter { it.isNotBlank() }.distinct().sorted().take(40) }
    val releaseOptions   = remember(catalog) { catalog.mapNotNull { it.release }.filter { it.isNotBlank() }.distinct().sorted() }
    val cardTypeOptions  = remember(catalog) { catalog.map { it.cardType }.filter { it.isNotBlank() }.distinct().sorted() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                if (existing == null) "New custom rainbow" else "Edit custom rainbow",
                style = MaterialTheme.typography.headlineSmall,
            )
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name (e.g. \"Every Maverick Battlefoil\")") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            HorizontalDivider()
            BOBASectionHeader(title = "Weapons (any of)")
            ChipsPicker(options = elementOptions, selected = elements, onToggle = { elements = elements.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Heroes (any of)")
            ChipsPicker(options = heroOptions, selected = heroes, onToggle = { heroes = heroes.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Treatments (any of)")
            ChipsPicker(options = treatmentOptions, selected = treatments, onToggle = { treatments = treatments.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Sets (any of)")
            ChipsPicker(options = setOptions, selected = sets, onToggle = { sets = sets.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Sub-sets (any of)")
            ChipsPicker(options = subSetOptions, selected = subSets, onToggle = { subSets = subSets.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Releases (any of)")
            ChipsPicker(options = releaseOptions, selected = releases, onToggle = { releases = releases.toggle(it) })

            HorizontalDivider()
            BOBASectionHeader(title = "Card types (any of)")
            ChipsPicker(options = cardTypeOptions, selected = cardTypes, onToggle = { cardTypes = cardTypes.toggle(it) })

            HorizontalDivider()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = inspiredInkOnly, onCheckedChange = { inspiredInkOnly = it })
                Spacer(modifier = Modifier.padding(end = 12.dp))
                Text("Inspired Ink only (Hex /5, Glow /10, Fire /25, Ice /50)")
            }

            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Cancel") }
                Button(
                    onClick = {
                        val criteria = RainbowCriteria(
                            heroes = heroes.toList(),
                            sets = sets.toList(),
                            subSets = subSets.toList(),
                            elements = elements.toList(),
                            treatments = treatments.toList(),
                            cardTypes = cardTypes.toList(),
                            releases = releases.toList(),
                            inspiredInkOnly = inspiredInkOnly,
                        )
                        if (existing == null) {
                            vm.create(name.trim(), criteria) { ok -> if (ok) onDismiss() }
                        } else {
                            vm.update(existing.id, name.trim(), criteria) { ok -> if (ok) onDismiss() }
                        }
                    },
                    enabled = name.trim().isNotEmpty(),
                    modifier = Modifier.weight(1f),
                ) { Text("Save") }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun ChipsPicker(
    options: List<String>,
    selected: Set<String>,
    onToggle: (String) -> Unit,
) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEach { opt ->
            FilterChip(
                selected = opt in selected,
                onClick = { onToggle(opt) },
                label = { Text(opt) },
            )
        }
    }
}

private fun <T> Set<T>.toggle(value: T): Set<T> =
    if (value in this) this - value else this + value

@Composable
private fun rememberSavedField(initial: String, reKey: Any? = null): androidx.compose.runtime.MutableState<String> =
    androidx.compose.runtime.saveable.rememberSaveable(reKey) { androidx.compose.runtime.mutableStateOf(initial) }

@Composable
@JvmName("rememberSavedFieldBool")
private fun rememberSavedField(initial: Boolean, reKey: Any? = null): androidx.compose.runtime.MutableState<Boolean> =
    androidx.compose.runtime.saveable.rememberSaveable(reKey) { androidx.compose.runtime.mutableStateOf(initial) }

@Composable
private fun rememberSavedSet(initial: Set<String> = emptySet(), reKey: Any? = null): androidx.compose.runtime.MutableState<Set<String>> =
    androidx.compose.runtime.saveable.rememberSaveable(
        reKey,
        saver = androidx.compose.runtime.saveable.Saver(
            save = { it.value.toList() },
            restore = { androidx.compose.runtime.mutableStateOf(it.toSet()) },
        ),
    ) { androidx.compose.runtime.mutableStateOf(initial) }
