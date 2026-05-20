package com.bobaplaybook.core.ui.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.sp
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Brand wordmark — "BOBA Playbook" in Bebas Neue, brand orange.
 *
 * Sized for `TopAppBar` title slot — `titleLarge` (22sp). Bebas Neue
 * is naturally tall + condensed so a 22sp body weight reads as
 * 28-ish-equivalent next to a Roboto reference, which is exactly the
 * presence we want without overflowing the bar.
 *
 * No padding — TopAppBar handles its own slot spacing. Earlier wordmark
 * used `displayMedium` (45sp) + 8dp pad, which forced the bar tall and
 * read as a hero element rather than a brand mark.
 */
@Composable
fun BOBAWordmark(modifier: Modifier = Modifier) {
    Text(
        text = "BOBA Playbook",
        style = MaterialTheme.typography.titleLarge.copy(
            fontFamily = MaterialTheme.typography.displaySmall.fontFamily,  // Bebas Neue
            letterSpacing = 1.5.sp,
        ),
        color = BobaBrand.Orange,
        textAlign = TextAlign.Center,
        modifier = modifier,
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewWordmark() {
    BobaTheme {
        BOBAWordmark()
    }
}
