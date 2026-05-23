package com.bobaplaybook.core.network

/**
 * Cloudflare Worker endpoints — single source of truth.
 *
 * Mirrors iOS `WorkerConfig.swift`. Same URLs for both clients; same
 * auth (Bearer JWT) where required. Transport-agnostic; zero
 * server-side changes needed for Android.
 *
 * Every Worker call MUST refresh the JWT first (ANDROID-DEV.md §5.3)
 * — wrap the call in the `SupabaseAuthInterceptor` OkHttp interceptor.
 */
object WorkerConfig {

    /** eBay Browse + Marketplace Insights API + Whatnot show feed proxy. */
    const val EBAY_PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"

    /**
     * Market Est. fallback Worker. Consulted by `PricingService` when
     * `EBAY_PROXY` returns no sold section. Replaces the Radish Market
     * Est. tier that was removed 2026-05-23 (DECISIONS.md #056). See
     * workers/price-estimator/README.md.
     */
    const val PRICE_ESTIMATOR = "https://boba-price-estimator.benwilkoff.workers.dev"

    /** COMC asking-price proxy. Soft-fails when Turnstile is up (DECISIONS.md #034). */
    const val COMC_PROXY = "https://boba-comc-proxy.benwilkoff.workers.dev"

    /** Account deletion (auth-gated). */
    const val ACCOUNT_DELETE = "https://boba-account-delete.benwilkoff.workers.dev"

    /** Avatar upload (auth-gated, ≤2 MB). */
    const val AVATAR_UPLOAD = "https://boba-avatar-upload.benwilkoff.workers.dev"

    /** Mod card-image merge / approval (auth + role-gated). */
    const val MOD_MERGE = "https://boba-mod-merge.benwilkoff.workers.dev"

    /** YouTube feed aggregator for Learn → Watch tab. */
    const val YOUTUBE_FEED = "https://boba-youtube-feed.benwilkoff.workers.dev"

    // Future: BOBA push dispatcher (DECISIONS.md #045)
    // const val PUSH_DISPATCHER = "https://boba-push-dispatcher.benwilkoff.workers.dev"
}
