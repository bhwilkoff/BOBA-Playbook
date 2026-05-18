import Foundation

// MARK: - Supabase Configuration
// Fill in your project values from .env.local
// The anon key is safe to commit — Supabase Row Level Security enforces data access.
enum SupabaseConfig {
    static let projectURL = "https://pazkimtkwwwekuguxkff.supabase.co"
    static let anonKey    = "sb_publishable_nAaO0c10a0dJaNRRYUFv7w_PmH1XjET"
}

// MARK: - Cloudflare Worker — eBay Pricing Proxy
// Fill in after deploying workers/ebay-proxy/ to Cloudflare.
// Format: "https://boba-ebay-proxy.<your-subdomain>.workers.dev"
enum WorkerConfig {
    static let ebayProxyURL    = "https://boba-ebay-proxy.benwilkoff.workers.dev"
    /// boba-youtube-feed — aggregates BoBA YouTube content into 3
    /// categorized feeds (live / short / regular) refreshed every 4h.
    /// See workers/youtube-feed/README.md.
    static let youtubeFeedURL  = "https://boba-youtube-feed.benwilkoff.workers.dev"
    /// boba-comc-proxy — surfaces COMC.com asking-price listings as a
    /// second source alongside eBay active listings in the BUY NOW
    /// panel. See workers/comc-proxy/src/index.ts (note the Turnstile
    /// caveat: live data depends on COMC's WAF allowing the worker).
    static let comcProxyURL    = "https://boba-comc-proxy.benwilkoff.workers.dev"
    /// boba-account-delete — POST /account/delete with the user's JWT.
    /// Holds the Supabase service_role key as a secret and proxies the
    /// admin auth.users delete (which cascades through every user-data
    /// table via FK ON DELETE CASCADE). App Store 5.1.1(v) compliance.
    /// See workers/account-delete/worker.js.
    static let accountDeleteURL = "https://boba-account-delete.benwilkoff.workers.dev"
    /// boba-avatar-upload — POST /avatar (image bytes) and DELETE
    /// /avatar. Bound to the boba-card-images R2 bucket; writes to
    /// avatars/{user_id}.{ext}. Caller persists the returned URL via
    /// SupabaseClient.setAvatarUrl(_:). See workers/avatar-upload/.
    static let avatarUploadURL  = "https://boba-avatar-upload.benwilkoff.workers.dev"
    /// boba-mod-merge — POST /merge with { overrideId }. Bound to the
    /// boba-card-images R2 bucket; downloads the uploaded JPEG from
    /// Supabase Storage, writes to full/{file} + thumbs/{file}, purges
    /// Cloudflare cache, and marks the override row status='applied'
    /// with applied_image_file set. Makes admin uploads + admin-
    /// approved mod uploads appear in the app immediately rather than
    /// waiting for the daily merge cron. See workers/mod-merge/.
    static let modMergeURL      = "https://boba-mod-merge.benwilkoff.workers.dev"
}

// MARK: - Discord — Trade Room
// client_id is public. client_secret lives in the Cloudflare Worker only.
enum DiscordConfig {
    static let clientId    = "1491134218829304009"
    static let channelId   = "1306146115757936650"
    static let guildId     = "1305710603440095252"
    static let inviteCode  = "bobattlearena"
    static let redirectURI = "bobaplaybook://discord-callback"
    // Initial code exchange — Worker adds client_secret (Discord requires it even for PKCE)
    static let tokenURL    = WorkerConfig.ebayProxyURL + "/discord/token"
    static let refreshURL  = WorkerConfig.ebayProxyURL + "/discord/refresh"
    static let messagesURL = WorkerConfig.ebayProxyURL + "/discord/messages"
}
