package com.bobaplaybook.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import dagger.hilt.android.HiltAndroidApp
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath
import java.util.concurrent.TimeUnit

/**
 * Application entry point.
 *
 * Two responsibilities at launch:
 *
 *  1. Wire Hilt for compile-time DI. [HiltAndroidApp] is mandatory or
 *     the app won't compile against Hilt-annotated ViewModels.
 *  2. Build the Coil 3 [ImageLoader] singleton — 60 MB memory + 500 MB
 *     disk to mirror the iOS NSCache + URLCache configuration
 *     (DECISIONS.md #024 + ANDROID-DEV.md §5.5). The OkHttp client is
 *     shared between Coil and Ktor so we get one connection pool, one
 *     DNS cache, one TLS session-resumption cache — ~30% cold-start
 *     memory win.
 *
 * Notification channels (FCM) are created at onCreate per
 * ANDROID-DEV.md §7.2 — channel IDs are stable forever so once a
 * user mutes a channel the system remembers across reinstalls.
 */
@HiltAndroidApp
class BOBAApplication : Application(), SingletonImageLoader.Factory {

    /**
     * Shared OkHttp client used by both Coil 3 (image loading) and Ktor
     * (Supabase + Cloudflare Worker calls). Single connection pool +
     * one TLS session cache means cold-start is meaningfully cheaper.
     */
    val sharedHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    /**
     * Notification channels — required on API 26+. The FCM dispatcher
     * (DECISIONS.md #045) routes match alerts / breaking news / trade
     * messages by channel; we register the channels at launch so the
     * first push has somewhere to land.
     *
     * Channel IDs are stable forever — once a user has dismissed/muted
     * a channel, the system remembers the choice keyed on the id.
     * Don't rename or recreate channels.
     */
    private fun createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_MATCH_ALERTS,
                "Match alerts",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Wanted/Grail card matches with other collectors"
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_BREAKING_NEWS,
                "Breaking news",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "New set drops, schedule changes, app-wide announcements"
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_TRADE_MESSAGES,
                "Trade messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Direct messages from a trade partner you've opened a thread with"
            },
        )
    }

    companion object {
        const val CHANNEL_MATCH_ALERTS = "match_alerts"
        const val CHANNEL_BREAKING_NEWS = "breaking_news"
        const val CHANNEL_TRADE_MESSAGES = "trade_messages"
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizeBytes(60L * 1024 * 1024)   // 60 MB — matches iOS NSCache
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(applicationContext.cacheDir.resolve("image_cache").toOkioPath())
                    .maxSizeBytes(500L * 1024 * 1024)  // 500 MB — matches iOS URLCache
                    .build()
            }
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { sharedHttpClient }))
            }
            .crossfade(true)
            .build()
}
