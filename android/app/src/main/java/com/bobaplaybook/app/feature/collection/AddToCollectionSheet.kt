@file:OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.bobaplaybook.app.feature.collection

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.domain.model.Designation
import com.bobaplaybook.core.ui.components.BOBACardCell
import com.bobaplaybook.core.ui.components.BOBASectionHeader

/**
 * Add to Collection sheet — mirrors iOS AddToCollectionSheet.swift.
 *
 * Sections, top to bottom:
 *  - Card header (thumb + name + number)
 *  - Designation chip row (5 options)
 *  - Condition (NM/EX/GD/PR + grading company + grade — owned only)
 *  - Pricing (market avg / purchase / asking — owned + sale only)
 *  - Notes (optional, multi-line)
 *  - Save button (Cancel + Save toolbar)
 */
@Composable
fun AddToCollectionSheet(
    card: Card,
    onDismiss: () -> Unit,
    onSubmit: (AddToCollectionInput) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        AddToCollectionContent(
            card = card,
            onDismiss = onDismiss,
            onSubmit = onSubmit,
        )
    }
}

data class AddToCollectionInput(
    val cardBobaId: String,
    val designation: Designation,
    val quantity: Int,
    val condition: String?,
    val grade: String?,
    val gradingCompany: String?,
    val purchasePriceUsd: Double?,
    val askingPriceUsd: Double?,
    val notes: String?,
)

@Composable
private fun AddToCollectionContent(
    card: Card,
    onDismiss: () -> Unit,
    onSubmit: (AddToCollectionInput) -> Unit,
) {
    var designation by remember { mutableStateOf(Designation.PERSONAL) }
    var quantity by remember { mutableStateOf("1") }
    var condition by remember { mutableStateOf<String?>(null) }
    var gradingCompany by remember { mutableStateOf<String?>(null) }
    var gradeText by remember { mutableStateOf("") }
    var purchaseText by remember { mutableStateOf("") }
    var askingText by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize()) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Add to Collection",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
        }
        HorizontalDivider()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 96.dp),
        ) {
            // Card header card-row
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(modifier = Modifier.width(60.dp).height(84.dp)) {
                    BOBACardCell(imageFile = card.imageFile, contentDescription = card.displayName)
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(card.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${card.cardNumber} · ${card.element.lowercase().replaceFirstChar { it.uppercase() }}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    card.treatment?.let {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            HorizontalDivider()

            // Designation
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                BOBASectionHeader(title = "Designation")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Designation.entries.forEach { d ->
                        FilterChip(
                            selected = designation == d,
                            onClick = { designation = d },
                            label = { Text(d.label) },
                        )
                    }
                }
            }
            HorizontalDivider()

            // Quantity
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                BOBASectionHeader(title = "Quantity")
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it.filter { c -> c.isDigit() }.take(3) },
                    label = { Text("How many copies?") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Condition + grade (only for owned designations)
            if (designation != Designation.WANTED) {
                HorizontalDivider()
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    BOBASectionHeader(title = "Condition")
                    val conditions = remember { listOf("Mint", "Near Mint", "Excellent", "Good", "Poor") }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        conditions.forEach { c ->
                            FilterChip(
                                selected = condition == c,
                                onClick = { condition = if (condition == c) null else c },
                                label = { Text(c, style = MaterialTheme.typography.labelMedium) },
                            )
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    BOBASectionHeader(title = "Grading (optional)")
                    val companies = remember { listOf("PSA", "BGS", "SGC", "CGC") }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        companies.forEach { c ->
                            FilterChip(
                                selected = gradingCompany == c,
                                onClick = { gradingCompany = if (gradingCompany == c) null else c },
                                label = { Text(c, style = MaterialTheme.typography.labelMedium) },
                            )
                        }
                    }
                    if (gradingCompany != null) {
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = gradeText,
                            onValueChange = { gradeText = it },
                            label = { Text("Grade") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                // Pricing
                HorizontalDivider()
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    BOBASectionHeader(title = "Pricing")
                    OutlinedTextField(
                        value = purchaseText,
                        onValueChange = { purchaseText = it.filter { c -> c.isDigit() || c == '.' } },
                        label = { Text("Purchase price (USD)") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (designation == Designation.FOR_SALE || designation == Designation.FOR_TRADE) {
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = askingText,
                            onValueChange = { askingText = it.filter { c -> c.isDigit() || c == '.' } },
                            label = { Text(if (designation == Designation.FOR_SALE) "Asking price (USD)" else "Trade value (USD)") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }

            HorizontalDivider()
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                BOBASectionHeader(title = "Notes (optional)")
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    placeholder = { Text("Add notes about this card") },
                    minLines = 2,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Cancel")
                }
                Button(
                    onClick = {
                        onSubmit(
                            AddToCollectionInput(
                                cardBobaId       = card.bobaId,
                                designation      = designation,
                                quantity         = quantity.toIntOrNull() ?: 1,
                                condition        = condition,
                                grade            = gradeText.takeIf { it.isNotBlank() },
                                gradingCompany   = gradingCompany,
                                purchasePriceUsd = purchaseText.toDoubleOrNull(),
                                askingPriceUsd   = askingText.toDoubleOrNull(),
                                notes            = notes.takeIf { it.isNotBlank() },
                            ),
                        )
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.width(18.dp).height(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Save")
                }
            }
        }
    }
}
