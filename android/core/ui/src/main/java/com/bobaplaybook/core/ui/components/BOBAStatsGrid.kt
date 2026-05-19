package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Canonical 6-cell card-stats grid (DECISIONS.md #029, ANDROID-DESIGN.md §11.1).
 *
 * Every card-detail surface across Find / Decks / Collection renders
 * the SAME six rows in the same order:
 *
 *     Card #     │  Type
 *     Treatment  │  Weapon
 *     Set        │  Sub-set
 *
 * Sealed Products pass `weapon = null` + `treatment = null` to skip
 * those rows cleanly without affecting layout. Cost + DBS (Plays only)
 * render BELOW the canonical six — they're NOT part of this grid.
 *
 * One canonical implementation, no per-surface variants. Drift is
 * the bug.
 */
@Composable
fun BOBAStatsGrid(
    cardNumber: String,
    cardType: String,
    treatment: String?,
    weapon: String?,
    set: String,
    subSet: String?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        StatsRow(
            leftLabel = "Card #",     leftValue = cardNumber,
            rightLabel = "Type",      rightValue = cardType,
        )
        StatsRow(
            leftLabel = "Treatment",  leftValue = treatment ?: "—",
            rightLabel = "Weapon",    rightValue = weapon ?: "—",
        )
        StatsRow(
            leftLabel = "Set",        leftValue = set,
            rightLabel = "Sub-set",   rightValue = subSet ?: "—",
        )
    }
}

@Composable
private fun StatsRow(
    leftLabel: String,
    leftValue: String,
    rightLabel: String,
    rightValue: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        StatsCell(label = leftLabel,  value = leftValue,  modifier = Modifier.weight(1f))
        StatsCell(label = rightLabel, value = rightValue, modifier = Modifier.weight(1f))
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun StatsCell(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(vertical = 4.dp)) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewStatsGrid() {
    BobaTheme {
        BOBAStatsGrid(
            cardNumber = "1",
            cardType   = "Hero",
            treatment  = "Base Set",
            weapon     = "FIRE",
            set        = "Base Set",
            subSet     = "First Edition",
        )
    }
}
