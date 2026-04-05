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
    static let ebayProxyURL = "https://boba-ebay-proxy.benwilkoff.workers.dev"
}
