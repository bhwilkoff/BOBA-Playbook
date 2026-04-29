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

        // URL-slug per canonical set name. Radish dropped the year
        // segment from URLs around 2026-04 — the new shape is
        // `/boba/{slug}/{name}/{num}`. Old `/boba/{year}/{slug}/...`
        // returns 404 for every card type now (Heroes, Plays, Hot
        // Dogs alike), which is what made the user notice broken
        // Plays + Hot Dogs links specifically.
        let setMap: [String: String] = [
            "Alpha":                          "Alpha_Edition",
            "Alpha Edition":                  "Alpha_Edition",
            "alpha-edition":                  "Alpha_Edition",
            "Alpha Update":                   "Alpha_Update",
            "alpha-update":                   "Alpha_Update",
            "Alpha Blast":                    "Alpha_Blast",
            "Griffey":                        "Griffey_Edition",
            "Griffey Edition":                "Griffey_Edition",
            "griffey-edition":                "Griffey_Edition",
            "National Starter Set":           "National_24_Starter_Set",
            "2024 National Show Starter Set": "National_24_Starter_Set",
            "National '24":                   "National_24_Starter_Set",
            "National 24 Starter Set":        "National_24_Starter_Set",
            "World Champions":                "World_Champions",
            "world-champions":                "World_Champions",
            "World Champions 2024":           "World_Champions",
            "World Champions 2025":           "World_Champions",
            "Battle Trainer Kit":             "Battle_Trainer_Kit",
            "Superfan Series":                "Alpha_Edition",
            "Tecmo Bowl Edition":             "Tecmo_Bowl",
            "tecmo-bowl":                     "Tecmo_Bowl",
            "Promo Cards":                    "Promo_Cards",
            "Big League Chew":                "Big_League_Chew",
            "big-league-chew":                "Big_League_Chew",
            "sandstorm":                      "Sandstorm",
        ]

        let slug = setMap[set] ?? "Alpha_Edition"
        // Plays + Hot Dogs use the play/hot-dog name (which lives in
        // the catalog's `hero` field per the One-ID-per-Card mantra)
        // exactly the same way Heroes use the hero name.
        let name = self.hero.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self.hero
        let num  = cardNum.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cardNum
        return URL(string: "https://radishpriceguide.com/boba/\(slug)/\(name)/\(num)")
    }

    /// String form of `resolvedRadishURL` for passing to the pricing
    /// Worker (which takes a String query param).
    var resolvedRadishUrlString: String? { resolvedRadishURL?.absoluteString }
}
