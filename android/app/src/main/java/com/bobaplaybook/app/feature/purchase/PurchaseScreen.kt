@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.purchase

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Purchase tab (ANDROID-DESIGN.md §8.5).
 *
 * M6 ships the IA shell + segmented picker:
 *  - TopAppBar
 *  - SingleChoiceSegmentedButtonRow — "Upcoming Breaks" | "Find a Store"
 *  - Both segments render placeholder EmptyState pointing at the
 *    Worker / Maps wiring that lands in the polish pass
 *
 * Deferred to M6-polish:
 *  - Whatnot tile list via boba-ebay-proxy /whatnot/upcoming
 *    (existing Worker, ANDROID-DEV.md §5.4 — auth-less GET, just
 *    needs a Ktor call + tile renderer)
 *  - Google Maps Compose for Find a Store + ModalBottomSheet store
 *    list (depends on Google Maps API key + a Worker that exposes
 *    the indie+big-box store dataset; today that dataset lives
 *    inside the iOS app)
 *
 * Both segments are wired to the same Scaffold for now so the M6-polish
 * patch is a single content-swap per segment.
 */
@Composable
fun PurchaseScreen(modifier: Modifier = Modifier) {
    var section by remember { mutableStateOf(PurchaseSection.BREAKS) }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Purchase") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            SectionPicker(
                selected = section,
                onChange = { section = it },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            when (section) {
                PurchaseSection.BREAKS -> {
                    BOBAEmptyState(
                        icon = Icons.Default.LiveTv,
                        headline = "Upcoming Whatnot breaks",
                        body = "Live break feed from boba-ebay-proxy/whatnot/upcoming lands in the M6 polish pass.",
                    )
                }
                PurchaseSection.STORES -> {
                    BOBAEmptyState(
                        icon = Icons.Default.Storefront,
                        headline = "Find a Store",
                        body = "~330 indie + ~1,800 big-box card stores on a Google Map. Wiring lands in the M6 polish pass.",
                    )
                }
            }
        }
    }
}

private enum class PurchaseSection(val label: String, val icon: ImageVector) {
    BREAKS("Upcoming Breaks", Icons.Default.LiveTv),
    STORES("Find a Store",    Icons.Default.Storefront),
}

@Composable
private fun SectionPicker(
    selected: PurchaseSection,
    onChange: (PurchaseSection) -> Unit,
    modifier: Modifier = Modifier,
) {
    val entries = remember { PurchaseSection.entries }
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        entries.forEachIndexed { index, section ->
            SegmentedButton(
                selected = section == selected,
                onClick = { onChange(section) },
                shape = SegmentedButtonDefaults.itemShape(index, entries.size),
            ) {
                Text(section.label, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}
