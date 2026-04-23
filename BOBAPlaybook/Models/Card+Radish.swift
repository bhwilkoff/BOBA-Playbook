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
    /// explicit `radishUrl` field when present, otherwise composes one
    /// from the catalog's set / hero / cardNumber.
    var resolvedRadishURL: URL? {
        if let raw = radishUrl, let url = URL(string: raw) { return url }

        // Prefix remap: catalog uses "LOGO-", "RAD-", "MIX-" but Radish
        // uses "Logo-", "Rad-", "Mix-" in URLs.
        let prefixMap = ["LOGO": "Logo", "RAD": "Rad", "MIX": "Mix"]
        var cardNum = cardNumber
        for (ours, theirs) in prefixMap {
            if cardNum.hasPrefix(ours + "-") {
                cardNum = theirs + cardNum.dropFirst(ours.count)
                break
            }
        }

        // Year + URL-slug per canonical set name. Radish URLs embed
        // both, so this map is the full set-name → (year, slug) table.
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
        let hero = self.hero.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self.hero
        let num  = cardNum.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cardNum
        return URL(string: "https://radishpriceguide.com/boba/\(year)/\(slug)/\(hero)/\(num)")
    }

    /// String form of `resolvedRadishURL` for passing to the pricing
    /// Worker (which takes a String query param).
    var resolvedRadishUrlString: String? { resolvedRadishURL?.absoluteString }
}
