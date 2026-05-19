package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Brand wordmark — "BOBA Playbook" rendered in Bebas-Neue-style display
 * type, brand orange, all-caps. Used in:
 *
 *  - root `CenterAlignedTopAppBar` title slot on every tab
 *  - splash overlay during initial catalog load
 *  - Profile / About screens
 *
 * NOT used at the home-screen icon label — that's "Playbook" only
 * (DECISIONS.md #032).
 *
 * M0 uses system display fonts; Bebas Neue lands in M0 phase 2 when
 * the font sync task runs.
 */
@Composable
fun BOBAWordmark(modifier: Modifier = Modifier) {
    Text(
        text = "BOBA Playbook",
        style = MaterialTheme.typography.displayMedium.copy(
            fontWeight = FontWeight.Black,
            letterSpacing = 2.sp,
        ),
        color = BobaBrand.Orange,
        textAlign = TextAlign.Center,
        modifier = modifier.padding(8.dp),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewWordmark() {
    BobaTheme {
        BOBAWordmark()
    }
}
