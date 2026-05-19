package com.bobaplaybook.app

import android.app.Application
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
 * Notification channels (FCM) get created here too once Firebase is
 * wired up; see ANDROID-DEV.md §7.2. Stub left as a TODO for M7.
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
        // TODO(M7): create notification channels for match-alerts / breaking-news /
        // trade-messages here. See ANDROID-DEV.md §7.2.
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
