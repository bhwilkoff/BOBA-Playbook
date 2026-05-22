package com.bobaplaybook.app.feature.learn

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Recent BoBA blog post entry — sourced from `assets/data/blog-feed.json`
 * (mirrored from the repo's `docs/blog-feed.json` via
 * `android/scripts/sync_shared_assets.sh`). The feed itself is refreshed
 * daily at 05:17 UTC by `.github/workflows/refresh-blog.yml`.
 *
 * Tick 236 — surfaces the BoBA blog inside the app so users don't need
 * to leave to catch announcements / rules updates / release news.
 */
@Serializable
data class BlogPost(
    val id:      String,
    val title:   String,
    val date:    String,      // "YYYY-MM-DD"
    val url:     String,
    val excerpt: String = "",
)

// Tick 243 — bug fix. blog-feed.json is wrapped: `{ version, posts: [...] }`
// not a bare array. Tick 236's loader decoded as List<BlogPost> which
// silently failed (kotlinx-serialization returns parse error → catch
// → empty list), so the "Recent BoBA news" section never rendered.
// Same bug existed on iOS LearnBlogLoader + the web fetch path; all
// three are corrected in the same commit.
@Serializable
private data class BlogFeedBundle(
    val posts: List<BlogPost> = emptyList(),
    val lastUpdated: String? = null,
)

object BlogFeedLoader {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    /**
     * Synchronous decoder — blog-feed.json is ~22 KB, no background-task
     * needed. Returns an empty list when the file is missing or
     * malformed so the surface renders cleanly even on a partial install.
     */
    fun load(context: Context): List<BlogPost> =
        try {
            val text = context.assets.open("data/blog-feed.json").bufferedReader().use { it.readText() }
            json.decodeFromString<BlogFeedBundle>(text).posts
        } catch (_: Throwable) {
            emptyList()
        }
}
