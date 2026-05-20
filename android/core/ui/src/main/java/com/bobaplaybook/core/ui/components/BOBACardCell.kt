package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bobaplaybook.core.network.CDN
import com.bobaplaybook.core.ui.theme.BobaBrand
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Canonical card cell — 5:7 aspect, `RoundedCornerShape(12.dp)`, uniform
 * padding, image art is the focal point (ANDROID-DESIGN.md §11.1 + §5.3
 * small multiples).
 *
 * Used in EVERY card grid across Find / Decks pool / Collection / Wall.
 * Single canonical implementation — don't fork.
 *
 * Two-tier loading per DECISIONS.md #024 + ANDROID-DEV.md §5.5:
 *  - The grid renders `thumbUrl` (~10 KB, 200 px). Coil caches it.
 *  - When the user taps to push into card detail, that screen will
 *    reuse the cached thumb as a placeholder while full-res loads.
 *    (Coil 3 cache-key API to be wired in M1 when the detail view ships.)
 *
 * Placeholder + error states use [BobaBrand.Surface] so missing
 * artwork doesn't introduce a foreign-color band into the grid.
 */
@Composable
fun BOBACardCell(
    imageFile: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val thumbUrl = CDN.thumbUrl(imageFile)

    Box(
        modifier = modifier
            .aspectRatio(5f / 7f)
            .clip(MaterialTheme.shapes.medium)
            .background(BobaBrand.SurfaceLow),
    ) {
        if (thumbUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(thumbUrl)
                    .crossfade(150)
                    .build(),
                contentDescription = contentDescription,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            BOBACardPlaceholder(label = contentDescription ?: "Image pending")
        }
    }
}

/**
 * Branded placeholder for cards lacking an `imageFile`. Mirrors iOS
 * `CardImageView.placeholderContent`.
 */
@Composable
private fun BOBACardPlaceholder(label: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(8.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "BOBA PB",
            style = MaterialTheme.typography.headlineSmall.copy(
                fontWeight = FontWeight.Bold,
            ),
            color = BobaBrand.Orange.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewCellPlaceholder() {
    BobaTheme {
        Box(modifier = Modifier.padding(32.dp)) {
            BOBACardCell(
                imageFile = null,
                contentDescription = "Maverick",
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
