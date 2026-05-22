@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bobaplaybook.core.ui.components

import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable

/**
 * M3 long-press / mouse-hover tooltip wrapping a single child
 * (typically an [androidx.compose.material3.IconButton]).
 *
 * Extracted at tick 400 after 11 near-identical TooltipBox call
 * sites accumulated across Find / Decks / Collection / Card detail
 * TopAppBars (ticks 379 / 384 / 386 / 389 / 394 / 396 / 399).
 *
 * Each call site previously carried ~8 lines of TooltipBox
 * boilerplate; this helper collapses the boilerplate to a single
 * line per site. The non-letter-edged `TooltipAnchorPosition` enum
 * default matches the Find/Collection convention (below the
 * anchor — top of the TopAppBar gives plenty of room downward).
 */
@Composable
fun BOBAIconTooltip(
    text: String,
    anchor: TooltipAnchorPosition = TooltipAnchorPosition.Below,
    content: @Composable () -> Unit,
) {
    TooltipBox(
        positionProvider = TooltipDefaults.rememberTooltipPositionProvider(anchor),
        tooltip = { PlainTooltip { Text(text) } },
        state = rememberTooltipState(),
        content = { content() },
    )
}
