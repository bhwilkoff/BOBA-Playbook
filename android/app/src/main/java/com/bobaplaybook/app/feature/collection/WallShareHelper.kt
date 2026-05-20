package com.bobaplaybook.app.feature.collection

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

/**
 * Capture a Compose graphics layer to a PNG file and fire the system
 * share sheet. Used by Wall view + future deck-wall share.
 *
 * Per DECISIONS.md #036 the Wall view is a real shareable surface
 * (collection brag image, sale lists, trade lists). On iOS the
 * equivalent is `ImageRenderer` + Photos-app share; on Android we
 * write a PNG to the cache and use FileProvider so any installed
 * messaging app can attach it.
 *
 * File lifecycle: written under `{cacheDir}/wall/` with a timestamped
 * name. Cache is OS-managed; we don't proactively clean up older
 * exports — a Files-app "free up space" sweep is sufficient.
 */
object WallShareHelper {

    fun share(
        context: Context,
        bitmap: Bitmap,
        designationLabel: String,
        username: String?,
    ) {
        val dir = File(context.cacheDir, "wall").apply { mkdirs() }
        val file = File(dir, "boba-wall-${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        val publicLink = username?.let { "https://bobaplaybook.com/u/$it" }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "My BOBA $designationLabel")
            if (publicLink != null) {
                putExtra(Intent.EXTRA_TEXT, "Check out my BOBA Playbook ${designationLabel.lowercase()}!\n$publicLink")
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Share Wall"))
    }
}
