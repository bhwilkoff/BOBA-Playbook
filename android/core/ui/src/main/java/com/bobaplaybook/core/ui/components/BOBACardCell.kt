package com.bobaplaybook.core.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
 * Resolution-aware (parity with iOS BOBACardGridItem, memory
 * `feedback_grid_density_per_tab`):
 *  - Cells ≥ 160 dp wide load `fullUrl` (~80 KB, ≤1200 px) because
 *    thumbs are 200 px native and look soft when displayed bigger.
 *  - Smaller cells (3-col grids, list rows) load `thumbUrl` (~10 KB,
 *    200 px). Coil 3 caches both tiers independently.
 *
 * `forceFullRes` lets callers (carousels, hero shelves) override the
 * size heuristic when they know they want the bigger asset regardless
 * of measured width.
 *
 * Placeholder + error states use [BobaBrand.Surface] so missing
 * artwork doesn't introduce a foreign-color band into the grid.
 */
@Composable
fun BOBACardCell(
    imageFile: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    forceFullRes: Boolean = false,
    /**
     * Routes the CDN call through the sealed-product path
     * (/sealed/thumbs/ + /sealed/optimized/) instead of the regular
     * /thumbs/ + /full/. iOS CDN.swift parity. Default false so most
     * call sites can stay unchanged; callers rendering a sealed
     * product (Booster Boxes etc.) should pass `isSealed = true`.
     */
    isSealed: Boolean = false,
    /**
     * Optional print-run badge surfaced as a top-trailing corner chip
     * (`/5` / `/10` / `/25` / `/50` / `SSP` / `Serial`). Default null
     * means no chip — call sites opt in by passing `card.printRunLabel`.
     * Chip is hidden at very small cell widths to keep it legible at
     * 3-col density. Discord backlog #7 per-cell variant; CardDetailScreen
     * carries the full explainer-tooltip version (DECISIONS.md #028).
     */
    printRunLabel: String? = null,
) {
    val context = androidx.compose.ui.platform.LocalContext.current

    Box(
        modifier = modifier
            .aspectRatio(5f / 7f)
            .clip(MaterialTheme.shapes.medium)
            .background(BobaBrand.SurfaceLow),
    ) {
        if (imageFile.isNullOrBlank()) {
            BOBACardPlaceholder(label = contentDescription ?: "Image pending")
        } else {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val url = if (forceFullRes || maxWidth >= 160.dp) {
                    if (isSealed) CDN.sealedFullUrl(imageFile) else CDN.fullUrl(imageFile)
                } else {
                    if (isSealed) CDN.sealedThumbUrl(imageFile) else CDN.thumbUrl(imageFile)
                }
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(url)
                        .crossfade(150)
                        .build(),
                    contentDescription = contentDescription,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                if (!printRunLabel.isNullOrBlank() && maxWidth >= 120.dp) {
                    PrintRunBadge(
                        label = printRunLabel,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(4.dp),
                    )
                }
            }
        }
    }
}

/**
 * Compact top-trailing chip rendering the print-run label. Orange for
 * SSP (Superfoil) per the CardDetailScreen pattern; cyan otherwise
 * (Inspired Ink /5 · /10 · /25 · /50 · Serial). Semi-translucent
 * background so the card art reads through.
 */
@Composable
private fun PrintRunBadge(label: String, modifier: Modifier = Modifier) {
    val accent = if (label == "SSP") BobaBrand.Orange else BobaBrand.Cyan
    Surface(
        modifier = modifier,
        color = Color.Black.copy(alpha = 0.62f),
        shape = RoundedCornerShape(4.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
            color = accent,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp),
        )
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
            .padding(4.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "BOBA",
            style = MaterialTheme.typography.titleSmall.copy(
                fontWeight = FontWeight.Bold,
            ),
            color = BobaBrand.Orange.copy(alpha = 0.5f),
            textAlign = TextAlign.Center,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            maxLines = 2,
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
