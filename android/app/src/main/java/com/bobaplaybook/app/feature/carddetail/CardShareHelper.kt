package com.bobaplaybook.app.feature.carddetail

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.network.CDN
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Build the system share sheet for a single card. Includes the card
 * art as an image attachment so chat apps preview the art alongside
 * the deep link. Mirrors iOS UIActivityViewController(activityItems =
 * [image, deepLink]) from CardDetailView.swift.
 *
 * Image source: CDN /full tier (≤1200px WebP, ~80KB) cached briefly
 * under `{cacheDir}/share/` with a card-keyed name so repeat shares
 * skip the network. File lifecycle is OS-managed; no proactive
 * cleanup needed.
 */
object CardShareHelper {

    suspend fun share(context: Context, card: Card) {
        // Query-param share URL is canonical across iOS / web / Android
        // since bobaId v3 (DECISIONS.md #057). The web SPA understands
        // ?card=...&hero=...&treatment=...&element=... directly;
        // element disambiguates FIRE/GLOW weapon-variant pairs that
        // share cardNumber+hero+treatment.
        val deepLink = android.net.Uri.parse("https://bobaplaybook.com/").buildUpon().apply {
            appendQueryParameter("card", card.cardNumber)
            if (card.hero.isNotEmpty())       appendQueryParameter("hero", card.hero)
            card.treatment?.takeIf { it.isNotEmpty() }?.let { appendQueryParameter("treatment", it) }
            if (card.element.isNotEmpty())    appendQueryParameter("element", card.element)
        }.build().toString()
        val text = "${card.displayName} (${card.cardNumber}) on BOBA Playbook\n$deepLink"

        val imageUri = runCatching { fetchAndCacheImage(context, card) }.getOrNull()
        val intent = Intent(Intent.ACTION_SEND).apply {
            putExtra(Intent.EXTRA_SUBJECT, card.displayName)
            putExtra(Intent.EXTRA_TEXT, text)
            if (imageUri != null) {
                type = "image/webp"
                putExtra(Intent.EXTRA_STREAM, imageUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                type = "text/plain"
            }
        }
        context.startActivity(Intent.createChooser(intent, "Share ${card.displayName}"))
    }

    private suspend fun fetchAndCacheImage(context: Context, card: Card): android.net.Uri? =
        withContext(Dispatchers.IO) {
            // Card-aware: sealed products route to /sealed/optimized/.
            val cdnUrl = CDN.fullUrl(card) ?: return@withContext null
            val dir = File(context.cacheDir, "share").apply { mkdirs() }
            val safeBobaId = card.bobaId.replace("[^A-Za-z0-9.-]".toRegex(), "_")
            val file = File(dir, "card-$safeBobaId.webp")
            if (!file.exists() || file.length() == 0L) {
                URL(cdnUrl).openStream().use { input ->
                    FileOutputStream(file).use { out -> input.copyTo(out) }
                }
            }
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
        }
}
