package com.bobaplaybook.core.network

/**
 * Supabase project configuration.
 *
 * URL is the public project URL — safe to commit. The anon key is also
 * public (it's gated by RLS — see iOS DECISIONS.md #023). Service role
 * key is NEVER bundled in the client; that's a Worker secret only.
 *
 * Confirm with the iOS / web setup that both project URL and anon key
 * match before connecting from Android (M7).
 */
object SupabaseConfig {

    /**
     * Public project URL. Same project as iOS + web — confirmed by
     * matching project ID `pazkimtkwwwekuguxkff` against
     * `BOBAPlaybook/Networking/SupabaseClient.swift`.
     */
    const val URL = "https://pazkimtkwwwekuguxkff.supabase.co"

    /**
     * Publishable key (`sb_publishable_…`) — the modern equivalent of
     * the legacy `anon` key. RLS-gated; safe to bundle in the client
     * APK per Supabase docs.
     *
     * The matching `sb_secret_…` (service-role) key is NEVER stored
     * here — that's a Cloudflare Worker secret only (see
     * `WorkerConfig.kt` + worker `wrangler.toml` files).
     */
    const val PUBLISHABLE_KEY = "sb_publishable_SjHCvLfeJl4XsuMWgKe5Xg_OLE0rkVF"

    /**
     * Back-compat alias for code that still imports `ANON_KEY` — the
     * publishable key is a drop-in replacement per the 2026 key
     * migration (legacy anon stays valid through end of 2026 but
     * publishable is the forward-compatible path).
     */
    const val ANON_KEY = PUBLISHABLE_KEY
}
