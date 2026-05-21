@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bobaplaybook.app.feature.collection.CollectionViewModel
import com.bobaplaybook.core.domain.model.Designation

/**
 * Scan → Collection designation chooser.
 *
 * iOS DESIGN.md §6.5 calls for "Add to which designation?" sheet at
 * scan-time before the write. Defaults remembered locally (last-used
 * designation) once we wire a DataStore; for v1 the sheet always
 * presents the five options fresh.
 */
@Composable
fun ScanDesignationSheet(
    bobaId: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val vm: CollectionViewModel = hiltViewModel()
    val authState by vm.uiState.collectAsStateWithLifecycle()

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text(
                "Add to which designation?",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(bottom = 8.dp),
            )
            Text(
                "Scanned card · $bobaId",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 12.dp),
            )
            HorizontalDivider()
            if (!authState.isSignedIn) {
                Text(
                    "Sign in from Find → Profile to save scans to your collection.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 16.dp),
                )
            } else {
                Designation.entries.forEach { designation ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                vm.add(bobaId, designation)
                                onDismiss()
                            }
                            .padding(vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            designation.label,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        Spacer(modifier = Modifier.padding(end = 8.dp))
                        Text(
                            designation.subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** Display description for each designation — surfaced in the picker. */
private val Designation.subtitle: String
    get() = when (this) {
        Designation.PERSONAL  -> "Your personal collection"
        Designation.FOR_SALE  -> "Cards you're selling"
        Designation.FOR_TRADE -> "Open to trades"
        Designation.WANTED    -> "Cards you're hunting"
        Designation.GRAILS    -> "Top of the want list"
    }
