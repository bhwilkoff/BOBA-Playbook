import Foundation

// MARK: - Radish Price Guide URL
//
// Radish URLs are NOT stored on every catalog card (the `radishUrl`
// field exists but is populated only for a small sample). Every card
// detail view still surfaces a "Radish Guide" link by synthesizing
// the URL from set + hero + cardNumber — the same function used below.
//
// Exposed here so every caller (the Radish Guide button + the eBay
// pricing Worker call) hits the identical URL. Without this, the
// Worker's Radish-scrape path was being passed `nil` and silently
// skipping sold-comp enrichment, even though users could click through
// to the same URL from the card detail view.

extension Card {
    /// Best-effort Radish Price Guide URL for this card. Prefers the
    /// explicit `radishUrl` field when present, otherwise composes
    /// one from the catalog metadata.
    ///
    /// URL shape (verified by `scripts/probe_radish_urls.py` —
    /// 60/93 sampled cards land on real data pages, the rest are
    /// new releases Radish hasn't indexed sales for yet):
    ///
    ///   • Sealed Product → /boba/sealed
    ///       Radish has no per-product detail page; the sealed-sales
    ///       index is the closest page that actually carries data.
    ///   • Hero / Play / HotDog → /boba/{year}/{slug}/{name}
    ///       Plays and HotDogs put their card name in the `hero`
    ///       field per the One-ID-per-Card mantra, so the same
    ///       formula works without a card-type segment in the path.
    ///       The cardNumber is NOT in the URL — earlier attempts
    ///       to include it (like `/boba/{year}/{slug}/{hero}/{num}`)
    ///       hit Radish's filter route, which renders an empty
    ///       cardNumber-echo page instead of the hero detail page
    ///       with sales data.
    var resolvedRadishURL: URL? {
        if let raw = radishUrl, let url = URL(string: raw) { return url }

        if cardType == "Sealed Product" {
            return URL(string: "https://radishpriceguide.com/boba/sealed")
        }

        // Year + URL-slug per canonical set name. Radish embeds both
        // in the URL (e.g. /boba/2024/Alpha_Edition/...) so the lookup
        // returns a (year, slug) tuple.
        let setMap: [String: (year: String, slug: String)] = [
            "Alpha":                          ("2024", "Alpha_Edition"),
            "Alpha Edition":                  ("2024", "Alpha_Edition"),
            "alpha-edition":                  ("2024", "Alpha_Edition"),
            "Alpha Update":                   ("2025", "Alpha_Update"),
            "alpha-update":                   ("2025", "Alpha_Update"),
            "Alpha Blast":                    ("2025", "Alpha_Blast"),
            "Griffey":                        ("2026", "Griffey_Edition"),
            "Griffey Edition":                ("2026", "Griffey_Edition"),
            "griffey-edition":                ("2026", "Griffey_Edition"),
            "National Starter Set":           ("2024", "National_24_Starter_Set"),
            "2024 National Show Starter Set": ("2024", "National_24_Starter_Set"),
            "National '24":                   ("2024", "National_24_Starter_Set"),
            "National 24 Starter Set":        ("2024", "National_24_Starter_Set"),
            "World Champions":                ("2024", "World_Champions"),
            "world-champions":                ("2024", "World_Champions"),
            "World Champions 2024":           ("2024", "World_Champions"),
            "World Champions 2025":           ("2025", "World_Champions"),
            "Battle Trainer Kit":             ("2024", "Battle_Trainer_Kit"),
            "Superfan Series":                ("2024", "Alpha_Edition"),
            "Tecmo Bowl Edition":             ("2025", "Tecmo_Bowl"),
            "tecmo-bowl":                     ("2025", "Tecmo_Bowl"),
            "Promo Cards":                    ("2025", "Promo_Cards"),
            "Big League Chew":                ("2025", "Big_League_Chew"),
            "big-league-chew":                ("2025", "Big_League_Chew"),
            "sandstorm":                      ("2025", "Sandstorm"),
        ]

        let (year, slug) = setMap[set] ?? ("2024", "Alpha_Edition")

        // Hero/Play/HotDog name lives in the `hero` field for all
        // three cardTypes; falls back to `name` for the rare missing
        // case. Path component is percent-encoded so apostrophes,
        // dots, ampersands, commas, and CJK characters all survive
        // (verified in the smoketest — Mull & Bones, Bern Baby,
        // Bern, Dr. J, A.I., 怪獣焼き all round-trip cleanly).
        let raw = self.hero.isEmpty ? self.name : self.hero
        guard !raw.isEmpty,
              let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        return URL(string: "https://radishpriceguide.com/boba/\(year)/\(slug)/\(encoded)")
    }

    /// String form of `resolvedRadishURL` for passing to the pricing
    /// Worker (which takes a String query param).
    var resolvedRadishUrlString: String? { resolvedRadishURL?.absoluteString }
}
