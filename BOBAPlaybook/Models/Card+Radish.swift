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
    /// Verified URL shape (Ben supplied two working examples):
    ///   /boba/2025/Alpha_Blast/Mean-Joe/BL-B18
    ///   /boba/2025/World_Champions/Chetmate/OKC-27
    ///
    ///   • Sealed Product → /boba/sealed (Radish has no per-product
    ///     detail page; the sealed-sales index is the closest page
    ///     that actually carries data).
    ///   • Hero / Play / HotDog →
    ///     /boba/{year}/{slug}/{hero}/{cardNumber}
    ///
    /// Notes baked into the builder:
    ///   - cardNumber prefix remap: catalog uses "LOGO-", "RAD-",
    ///     "MIX-" but Radish's URLs use "Logo-", "Rad-", "Mix-".
    ///   - hero-name normalization: a small alias table fixes
    ///     CamelCase→canonical-spelling mismatches (e.g. our catalog
    ///     stores "ChetMate" but Radish indexes him as "Chetmate";
    ///     "BoJax" exists in the catalog but Radish uses "Bojax").
    ///     Wrong casing returns 404 since Radish is case-sensitive.
    ///   - When Radish hasn't built a card-detail page for a given
    ///     hero/cardNumber pair, the URL 404s — that's a Radish-side
    ///     coverage gap, not a builder bug.
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

        // cardNumber prefix remap so LOGO-/RAD-/MIX- in the catalog
        // become Logo-/Rad-/Mix- in the URL.
        var cardNum = cardNumber
        let prefixMap = ["LOGO": "Logo", "RAD": "Rad", "MIX": "Mix"]
        for (ours, theirs) in prefixMap {
            if cardNum.hasPrefix(ours + "-") {
                cardNum = theirs + cardNum.dropFirst(ours.count)
                break
            }
        }

        // Hero name normalization. Radish is case-sensitive and uses
        // a different canonical spelling than ours for a few heroes;
        // the URL 404s without this remap. Add to the table whenever
        // you find a new mismatch (smoketest reports them).
        let rawHero = self.hero.isEmpty ? self.name : self.hero
        let heroAliases: [String: String] = [
            "ChetMate": "Chetmate",
            "BoJax":    "Bojax",
        ]
        let radishHero = heroAliases[rawHero] ?? rawHero

        guard !radishHero.isEmpty,
              let encodedHero = radishHero.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedNum  = cardNum.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        return URL(string: "https://radishpriceguide.com/boba/\(year)/\(slug)/\(encodedHero)/\(encodedNum)")
    }

    /// String form of `resolvedRadishURL` for passing to the pricing
    /// Worker (which takes a String query param).
    var resolvedRadishUrlString: String? { resolvedRadishURL?.absoluteString }

    /// Hero-only fallback URL — `/boba/{year}/{slug}/{hero}` with no
    /// cardNumber. Radish builds card-detail pages on-demand based on
    /// where they have sales data; for cards without enough comps the
    /// detail page 404s but the hero page (aggregating every print)
    /// is always present. `RadishURLResolver` swaps to this when the
    /// primary URL HEAD-probes back as 404.
    var heroOnlyRadishURL: URL? {
        guard let primary = resolvedRadishURL else { return nil }
        let path = primary.path
        // Strip the trailing /{cardNumber} segment. The path looks
        // like /boba/{year}/{slug}/{hero}/{cardNumber}; we want
        // /boba/{year}/{slug}/{hero}.
        let parts = path.split(separator: "/")
        guard parts.count >= 5 else { return primary }
        let trimmed = "/" + parts.dropLast().joined(separator: "/")
        var comps = URLComponents(url: primary, resolvingAgainstBaseURL: false)
        comps?.path = trimmed
        return comps?.url
    }
}

// MARK: - RadishURLResolver
//
// Validates that the Radish URL we hand the user (and the pricing
// Worker) actually resolves to a real page before linking it. Per
// Ben (2026-04-29) Radish 404s on cards they haven't built a detail
// page for yet, even when the URL shape is correct — so we HEAD-
// probe and fall back to the hero-only page when the primary 404s.
//
// Results are cached for the app's lifetime keyed by bobaId so each
// card resolves at most once per session.
@MainActor
final class RadishURLResolver {
    static let shared = RadishURLResolver()
    private var cache: [String: URL] = [:]

    /// Best URL for a card. Tries the cardNumber-specific URL first;
    /// falls back to the hero-only URL when the specific card 404s.
    /// Returns nil only if the catalog can't even build a primary URL
    /// (e.g. missing set/hero).
    func resolve(for card: Card) async -> URL? {
        if let cached = cache[card.id] { return cached }
        guard let primary = card.resolvedRadishURL else { return nil }

        // Sealed Products use a static index page; no probe needed.
        if card.cardType == "Sealed Product" {
            cache[card.id] = primary
            return primary
        }

        if await urlIsReachable(primary) {
            cache[card.id] = primary
            return primary
        }
        if let fallback = card.heroOnlyRadishURL,
           fallback != primary,
           await urlIsReachable(fallback) {
            cache[card.id] = fallback
            return fallback
        }
        // Even when both options 404, return the primary so the
        // button is at least clickable — Radish's 404 page lets the
        // user navigate up via breadcrumbs.
        cache[card.id] = primary
        return primary
    }

    private func urlIsReachable(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
