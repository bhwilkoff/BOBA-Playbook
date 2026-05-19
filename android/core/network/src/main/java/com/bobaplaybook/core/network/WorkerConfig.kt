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

    /** eBay Browse API + Radish pricing + Whatnot show feed proxy. */
    const val EBAY_PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"

    /** COMC asking-price proxy. Soft-fails when Turnstile is up (DECISIONS.md #034). */
    const val COMC_PROXY = "https://boba-comc-proxy.benwilkoff.workers.dev"

    /** Account deletion (auth-gated). */
    const val ACCOUNT_DELETE = "https://boba-account-delete.benwilkoff.workers.dev"

    /** Avatar upload (auth-gated, ≤2 MB). */
    const val AVATAR_UPLOAD = "https://boba-avatar-upload.benwilkoff.workers.dev"

    /** Mod card-image merge / approval (auth + role-gated). */
    const val MOD_MERGE = "https://boba-mod-merge.benwilkoff.workers.dev"

    // Future: BOBA push dispatcher (DECISIONS.md #045)
    // const val PUSH_DISPATCHER = "https://boba-push-dispatcher.benwilkoff.workers.dev"
}
