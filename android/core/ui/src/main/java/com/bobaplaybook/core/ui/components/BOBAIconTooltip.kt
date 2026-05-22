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
 * Collapses ~8 lines of TooltipBox boilerplate (positionProvider +
 * PlainTooltip + Text + rememberTooltipState + content slot) to a
 * single line per call site. Default anchor is below — matches the
 * TopAppBar convention which has plenty of room downward.
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
