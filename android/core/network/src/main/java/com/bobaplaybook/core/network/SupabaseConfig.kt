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

    // TODO(M7): fill these in from the existing iOS / web BOBAPlaybook
    //  Supabase project. The URL pattern is `https://<project-id>.
    //  supabase.co`. The anon key is the `eyJ...` Bearer JWT visible in
    //  Supabase dashboard → Project Settings → API. Same values used by
    //  iOS (`BOBAPlaybook/Networking/SupabaseClient.swift`).
    const val URL = "https://REPLACE_WITH_SUPABASE_URL.supabase.co"
    const val ANON_KEY = "REPLACE_WITH_SUPABASE_ANON_KEY"
}
