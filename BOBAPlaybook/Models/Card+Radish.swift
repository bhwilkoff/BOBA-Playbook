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
    ///   - cardNumber prefix casing per current Radish:
    ///     • LOGO- → Logo-   (Radish uses title-case for Logofoil)
    ///     • RAD-/MIX-/everything else stays UPPERCASE
    ///     An earlier version lowercased RAD- and MIX- to title-case
    ///     too — that 404s on current Radish and sent ~2,970 catalog
    ///     cards to the hero-level fallback URL instead of the
    ///     card-specific page.
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

        // cardNumber prefix casing per current Radish (verified
        // 2026-05-20 via curl on /Swoopes/RAD-137, /Bojax/MIX-1,
        // /Bojax/Logo-263, /Bojax/CHILL-1, /Bojax/Logo-263). Pattern:
        //   - LOGO- → Logo-   (Radish uses title-case for Logofoil)
        //   - everything else stays UPPERCASE
        //
        // The earlier remap also lowercased RAD- and MIX- to title-case
        // ("Rad-", "Mix-"), which 404s on current Radish — sending the
        // resolver into a hero-only-fallback path for ~2,970 catalog
        // cards (RAD- + MIX- combined). Pricing on those cards was also
        // broken because the Worker reuses whatever cardNumber the
        // client supplies. Fix: drop RAD/MIX from the remap, keep LOGO.
        var cardNum = cardNumber
        let prefixMap = ["LOGO": "Logo"]
        for (ours, theirs) in prefixMap {
            if cardNum.hasPrefix(ours + "-") {
                cardNum = theirs + cardNum.dropFirst(ours.count)
                break
            }
        }

        // Hero name normalization. Radish is case-sensitive and uses
        // a different canonical spelling than ours for a few heroes.
        // Verified 2026-05-20 via 100-card sweep:
        //   - "ChetMate" (CamelCase) is correct on Radish (40 cards on
        //     /Alpha_Update/ChetMate). An earlier alias mapped
        //     ChetMate → Chetmate which returns a 200 but 0-card alias
        //     page — wrong. Removed.
        //   - "BoJax" → "Bojax" is correct on Radish (25 cards on
        //     /Alpha_Update/Bojax; the CamelCase alias is empty).
        //     Catalog has both spellings; alias normalizes BoJax to
        //     the Bojax spelling Radish indexes.
        let rawHero = self.hero.isEmpty ? self.name : self.hero
        let heroAliases: [String: String] = [
            "BoJax": "Bojax",
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

    /// All Radish candidate URLs to probe in priority order before
    /// falling back to hero-only. Captures three known sources of drift:
    ///
    /// 1. **CardNumber casing-flip:** Radish migrated newer sets (2026
    ///    Griffey) to title-case cardNumber prefixes (`Rad-`, `Mix-`)
    ///    while older sets (2024 Alpha Edition) stayed uppercase
    ///    (`RAD-`, `MIX-`). No single rule resolves both — we probe both.
    ///
    /// 2. **Hero-name casing-flip:** Heroes with internal CamelCase
    ///    (ChetMate, MaxLight, etc.) appear on Radish in inconsistent
    ///    casing per set — ChetMate's Alpha_Update page uses CamelCase
    ///    (40 cards); the World_Champions page uses lowercase
    ///    "Chetmate" (6 OKC cards). Probe both variants.
    ///
    /// 3. **Cross-year namespace:** Some cards with set="World Champions"
    ///    in our catalog live on Radish at /2025/World_Champions
    ///    (not /2024). Generate the alternative-year URL.
    var radishCandidateURLs: [URL] {
        guard let primary = resolvedRadishURL else { return [] }

        // Sealed products don't have card-specific pages — short-circuit.
        if cardType == "Sealed Product" { return [primary] }

        // Build a base set of (URL) candidates from year × hero × cardNum
        // permutations. Each axis has 1-2 values; total candidate count
        // stays bounded (≤8 per card).
        let years = [primary.pathComponents[2]] + alternateYears(for: primary)
        var candidates: [URL] = []
        for year in years {
            guard let yUrl = withYear(year, in: primary) else { continue }
            // Hero variants: as-typed + internal-CamelCase-lowercased.
            for heroUrl in heroCasingVariants(of: yUrl) {
                candidates.append(heroUrl)
                if let flipped = flippedCasingRadishURL(from: heroUrl) {
                    candidates.append(flipped)
                }
            }
        }
        return candidates
    }

    /// Hero-name casing variants. If the hero contains internal
    /// uppercase letters (ChetMate, MaxLight, BeKool), also probe the
    /// version with those lowered (Chetmate, Maxlight, Bekool). Used
    /// to handle Radish's inconsistent hero slugging across sets.
    private func heroCasingVariants(of url: URL) -> [URL] {
        let parts = url.pathComponents
        guard parts.count >= 5 else { return [url] }
        let hero = parts[4]
        // Find any internal uppercase after the first character.
        let chars = Array(hero)
        guard chars.count > 1 else { return [url] }
        let hasInternalUpper = chars.dropFirst().contains { $0.isUppercase }
        if !hasInternalUpper { return [url] }
        // Build "ChetMate" → "Chetmate" (keep first letter, lowercase the rest).
        let lowered = String(chars[0]) + String(chars.dropFirst()).lowercased()
        guard lowered != hero else { return [url] }
        var loweredParts = parts
        loweredParts[4] = lowered
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/" + loweredParts.dropFirst().joined(separator: "/")
        guard let loweredURL = comps?.url else { return [url] }
        return [url, loweredURL]
    }

    /// Swap the cardNumber prefix between uppercase and title-case.
    /// Returns nil when the URL doesn't have the expected 5-segment
    /// shape with an `XXX-Number` cardNumber tail.
    private func flippedCasingRadishURL(from url: URL) -> URL? {
        let parts = url.pathComponents
        guard parts.count >= 6, let tail = parts.last else { return nil }
        // Parse "RAD-137" or "Rad-137" or "Logo-263"
        guard let dashIdx = tail.firstIndex(of: "-") else { return nil }
        let prefix = String(tail[tail.startIndex..<dashIdx])
        let rest   = String(tail[tail.index(after: dashIdx)...])
        guard prefix.count >= 2 else { return nil }
        let flipped: String
        if prefix == prefix.uppercased() && prefix != prefix.lowercased() {
            // ALLCAPS → Titlecase
            flipped = prefix.prefix(1).uppercased() + prefix.dropFirst().lowercased()
        } else {
            // Titlecase / mixed → uppercase
            flipped = prefix.uppercased()
        }
        if flipped == prefix { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let newTail = "\(flipped)-\(rest)"
        let newPath = "/" + parts.dropFirst().dropLast().joined(separator: "/") + "/" + newTail
        comps?.path = newPath
        return comps?.url
    }

    /// Alternative year segments to probe when the primary URL's year
    /// 404s. Hard-coded knowledge: World Champions exists at both
    /// 2024 + 2025; Alpha Edition cards sometimes get re-hosted under
    /// Alpha Update; Griffey is 2026 with no alternative; etc.
    private func alternateYears(for url: URL) -> [String] {
        let parts = url.pathComponents
        guard parts.count >= 4 else { return [] }
        let year = parts[2]
        let slug = parts[3]
        switch (year, slug) {
        case ("2024", "World_Champions"): return ["2025"]
        case ("2025", "World_Champions"): return ["2024"]
        case ("2024", "Alpha_Edition"):   return ["2025"]  // some cards re-hosted under Alpha Update
        default: return []
        }
    }

    /// Replace the year segment in a Radish URL.
    private func withYear(_ newYear: String, in url: URL) -> URL? {
        var parts = url.pathComponents
        guard parts.count >= 4 else { return nil }
        parts[2] = newYear
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/" + parts.dropFirst().joined(separator: "/")
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

    /// Best URL for a card. Three-tier resolution, all sitemap-derived:
    ///
    /// **Tier 1 (98.2% of catalog, instant):** read `card.radishUrl`
    /// field. The offline pipeline (scripts/build_radish_url_map.py +
    /// scripts/apply_radish_urls.py) bakes the canonical URL from
    /// Radish's own sitemap into every catalog row at build time.
    ///
    /// **Tier 2 (residual ~1.8%):** call the Worker's
    /// /radish-url endpoint, which does a live sitemap lookup against
    /// an edge-cached parse of Radish's sitemap.xml (TTL 7 days). The
    /// Worker is the SINGLE place URL construction happens — when
    /// Radish changes shape (4-segment → 5-segment, hero-casing drift,
    /// whatever's next), only the Worker needs an update; all clients
    /// pick up the new shape automatically.
    ///
    /// **Tier 3 (Worker unreachable / network offline):** fall back to
    /// the locally-constructed candidate URLs and HEAD-probe them.
    /// This is the last-resort offline path; the existing
    /// `radishCandidateURLs` logic preserves behavior pre-Worker.
    func resolve(for card: Card) async -> URL? {
        if let cached = cache[card.id] { return cached }

        // Tier 1 — pre-baked from offline sitemap parse.
        if let raw = card.radishUrl, !raw.isEmpty, let prebuilt = URL(string: raw) {
            cache[card.id] = prebuilt
            return prebuilt
        }

        // Sealed Products use a static index page; no Worker call needed.
        if card.cardType == "Sealed Product" {
            if let primary = card.resolvedRadishURL {
                cache[card.id] = primary
                return primary
            }
        }

        // Tier 2 — Worker live lookup.
        if let live = await fetchRadishURLFromWorker(for: card) {
            cache[card.id] = live
            return live
        }

        // Tier 3 — last-resort local construction + HEAD probe.
        guard let primary = card.resolvedRadishURL else { return nil }
        for candidate in card.radishCandidateURLs {
            if await urlIsReachable(candidate) {
                cache[card.id] = candidate
                return candidate
            }
        }
        if let fallback = card.heroOnlyRadishURL,
           fallback != primary,
           await urlIsReachable(fallback) {
            cache[card.id] = fallback
            return fallback
        }
        cache[card.id] = primary
        return primary
    }

    /// Worker-side resolution. Single GET against the boba-ebay-proxy
    /// `/radish-url` endpoint. The Worker holds the only place that
    /// constructs URLs from sitemap data — clients consume.
    private func fetchRadishURLFromWorker(for card: Card) async -> URL? {
        var comps = URLComponents(string: "\(WorkerConfig.ebayProxyURL)/radish-url")
        comps?.queryItems = [
            URLQueryItem(name: "set",        value: card.set),
            URLQueryItem(name: "hero",       value: card.hero.isEmpty ? card.name : card.hero),
            URLQueryItem(name: "cardNumber", value: card.cardNumber),
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct Body: Decodable { let url: String? }
            let body = try JSONDecoder().decode(Body.self, from: data)
            guard let s = body.url, !s.isEmpty else { return nil }
            return URL(string: s)
        } catch {
            return nil
        }
    }

    /// Promote a Worker-validated URL into the cache. When the
    /// pricing response includes a `radishResolvedUrl`, that's a
    /// strictly stronger signal than our HEAD probe — the Worker
    /// already pulled real sales data from that URL, so it's
    /// proven to host listings. Bypassing the HEAD probe here
    /// also avoids racing against the resolver's primary attempt.
    func cacheURL(_ url: URL, for card: Card) {
        cache[card.id] = url
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
