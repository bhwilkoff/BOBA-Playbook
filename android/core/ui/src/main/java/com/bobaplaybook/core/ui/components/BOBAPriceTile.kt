package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.ui.format.formatUsdAmount

/**
 * Pricing tile (ANDROID-DESIGN.md §8.7). Text-first row matching iOS
 * `PricingSection.itemRow` — price (left) + title (middle, wraps) +
 * date/source (right). The Worker doesn't ship per-listing thumbnails,
 * so the prior 96dp blank-thumb placeholder above every tile was just
 * dead grey space on the user's screen (and what Ben flagged as
 * "buy now thumbnails don't show correctly"). Tap → onClick (Custom
 * Tabs opens the listing).
 *
 * `thumbUrl` is preserved on the API for future Worker enrichment but
 * is currently ignored. When the Worker surfaces real thumb URLs we
 * can re-introduce a small leading 40dp art tile.
 */
@Composable
fun BOBAPriceTile(
    priceUsd: Double,
    title: String,
    @Suppress("UNUSED_PARAMETER") thumbUrl: String?,
    source: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    /** Sale / list date string from the Worker — surfaces under source. */
    date: String? = null,
) {
    Card(
        modifier = modifier
            .width(180.dp)
            .clickable { onClick() },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
        ) {
            Text(
                text = "$${priceUsd.formatUsdAmount()}",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
            )
            // Source + date on the same line so the body of the tile
            // stays compact (matches iOS row's "{relativeDate}" trailing).
            val sourceLine = buildString {
                append(source)
                date?.takeIf { it.isNotBlank() }?.let { append(" · ").append(it) }
            }
            Text(
                text = sourceLine,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
