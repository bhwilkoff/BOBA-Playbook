import SwiftUI

/// Inline pricing card shown in card detail views.
/// Fetches sold item history (Marketplace Insights) or active listing prices
/// (Browse API fallback) from the eBay proxy worker.
struct PricingSection: View {
    let card: Card
    /// Whether to render the "BUY NOW" bucket of active listings. The
    /// Collection surface passes `false` so coaches see only what the
    /// card has actually sold for — active asks are not apples-to-
    /// apples with owned-copy market value.
    var showActiveListings: Bool = true

    @State private var selectedDays = 30
    @State private var result: PricingService.PricingResult?
    @State private var isLoading = false
    @State private var fetchError: String?
    @State private var showRadish = false
    @State private var showEbay = false
    @State private var selectedItemURL: IdentifiableURL?
    /// HEAD-probed Radish URL — populated on appear by the resolver.
    /// Falls back to `card.resolvedRadishURL` while the probe is in
    /// flight or if both options 404. The Radish button + the
    /// pricing-Worker request both read from this so they stay in
    /// sync (we don't want the button to point one place while the
    /// Worker scrapes a different page).
    @State private var resolvedRadishURL: URL?
    /// COMC.com asking-price listings, fetched in parallel with the
    /// eBay/Radish pricing call. Additive to the BUY NOW panel —
    /// stays empty when COMC's WAF blocks the worker (current state
    /// per 2026-04-29). Soft-fail by design.
    @State private var comcListings: [ComcService.Listing] = []

    private let dayOptions = [7, 30, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {

            // Header row — label + day picker
            HStack {
                Text("MARKET PRICING")
                    .font(Design.Fonts.mono(9, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(1.5)
                Spacer()
                Picker("Period", selection: $selectedDays) {
                    ForEach(dayOptions, id: \.self) { d in
                        Text("\(d)d").tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .colorMultiply(Design.Colors.bobaOrange)
            }

            // Price grid / loading / error
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView().tint(Design.Colors.bobaOrange); Spacer() }
                        .frame(height: 64)
                } else if let result {
                    if result.sold != nil || result.active != nil {
                        // Dual-section layout per DESIGN.md §8.7. Walkthrough
                        // anchors point at each bucket so the .pricingPanels
                        // first-visit script can teach the asking-vs-sold
                        // distinction.
                        if let sold = result.sold {
                            bucketView(sold, label: "RECENT SALES", isActive: false)
                                .walkthroughAnchor("pricing.sold")
                        }
                        if showActiveListings, let active = result.active {
                            bucketView(active, label: "BUY NOW", isActive: true)
                                .walkthroughAnchor("pricing.buyNow")
                        }
                        // COMC asking-price strip lives below the eBay
                        // BUY NOW bucket. Renders only when COMC has
                        // listings; absent (Turnstile blocked, no
                        // inventory) means nothing shows.
                        if showActiveListings, !comcListings.isEmpty {
                            comcStrip(comcListings)
                        }
                    } else {
                        // Legacy single-section layout
                        HStack(spacing: 0) {
                            priceCell(label: "LOW",  value: result.low,     isActive: false)
                            Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                            priceCell(label: "AVG",  value: result.average, isActive: false)
                            Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                            priceCell(label: "HIGH", value: result.high,    isActive: false)
                        }
                        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))

                        let typeLabel = result.isSold ? "sold" : "active listing"
                        let plural    = result.count != 1 ? "s" : ""
                        Text("\(result.count) \(typeLabel)\(plural) · last \(selectedDays)d")
                            .font(Design.Fonts.mono(10))
                            .foregroundStyle(Design.Colors.textMuted)

                        if !result.items.isEmpty {
                            itemsList(result.items, isSold: result.isSold)
                        }
                    }
                } else if let err = fetchError {
                    Text(err)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Design.Spacing.md)
                }
            }

            // External links
            HStack(spacing: Design.Spacing.sm) {
                Button { showEbay = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cart.fill").font(.system(size: 11))
                        Text("eBay Sales").font(Design.Fonts.mono(12))
                    }
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaOrange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaOrange.opacity(0.4), lineWidth: 1))
                    )
                }

                Button { showRadish = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 11))
                        Text("Radish Guide").font(Design.Fonts.mono(12))
                    }
                    .foregroundStyle(Design.Colors.bobaCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.sm)
                            .fill(Design.Colors.bobaCyan.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .strokeBorder(Design.Colors.bobaCyan.opacity(0.35), lineWidth: 1))
                    )
                }
            }
        }
        .task(id: PricingPulse.shared.version) {
            // Re-runs when:
            //   - The view first appears (initial id matches)
            //   - PricingService invalidates (Collection refresh,
            //     Show queue scanner, individual show "Refresh
            //     Prices", or per-card forceRefresh) bumps the
            //     pulse — every open PricingSection re-fetches.
            //
            // Probe Radish for the right URL before kicking off the
            // pricing Worker request. The resolver caches per-bobaId
            // so this is a one-time HEAD per card per session.
            let probed = await RadishURLResolver.shared.resolve(for: card)
            if probed != resolvedRadishURL {
                resolvedRadishURL = probed
            }
            fetch()
        }
        .onChange(of: selectedDays) { fetch() }
        .sheet(isPresented: $showEbay)   { SafariView(url: ebayURL) }
        .sheet(isPresented: $showRadish) { SafariView(url: radishURL) }
        // sheet(item:) ensures the URL is set before the sheet is presented,
        // fixing the blank-on-first-tap bug that sheet(isPresented:) caused.
        .sheet(item: $selectedItemURL) { item in SafariView(url: item.url) }
    }

    // MARK: - Items list

    private func itemsList(_ items: [PricingService.PricingItem], isSold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isSold ? "RECENT SALES" : "CURRENT LISTINGS")
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
                .padding(.bottom, Design.Spacing.xs)

            VStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        if let url = URL(string: item.url), !item.url.isEmpty {
                            selectedItemURL = IdentifiableURL(url: url)
                        }
                    } label: {
                        itemRow(item, isSold: isSold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
    }

    private func itemRow(_ item: PricingService.PricingItem, isSold: Bool) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Text(item.price, format: .currency(code: "USD"))
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                // "Probable match" amber pill + tooltip when the Worker's
                // enriched matcher reports confidence below the confirmed
                // threshold (0.70). Tap to reveal the reasons that drove
                // the match decision. Per SOLD_COMP_MATCHER_HANDOFF.md §7.
                if item.isProbableMatch {
                    probableMatchBadge(reasons: item.matchReasons ?? [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSold, let label = relativeDate(item.date) {
                Text(label)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Design.Colors.textMuted)
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface2)
    }

    private func probableMatchBadge(reasons: [String]) -> some View {
        let amber = Color(hex: "E0A000")
        let tooltip = humanizeReasons(reasons)
        return HStack(spacing: 4) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Probable match")
                .font(Design.Fonts.mono(8, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(amber)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(amber.opacity(0.12))
            .overlay(Capsule().strokeBorder(amber.opacity(0.45), lineWidth: 0.7)))
        .help(tooltip)
    }

    private func humanizeReasons(_ reasons: [String]) -> String {
        if reasons.isEmpty { return "Likely this card" }
        let map: [String: String] = [
            "card_number_exact":   "card number",
            "card_number_partial": "partial card number",
            "hero":                "hero name",
            "power":               "power level",
            "power_in_title":      "power in title",
            "element":             "weapon type",
            "treatment":           "treatment",
            "manufacturer":        "BOBA manufacturer tag",
            "year":                "release year",
            "trusted_seller":      "trusted seller",
            "price_in_range":      "typical price range",
        ]
        let positive = reasons
            .filter { !$0.contains("penalty") && !$0.contains("outlier") && !$0.contains("mismatch") }
            .compactMap { map[$0] }
        if positive.isEmpty { return "Likely this card" }
        let list = positive.count == 1 ? positive[0]
                 : positive.dropLast().joined(separator: ", ") + " and " + positive.last!
        return "Matched by \(list)."
    }

    // MARK: - Helpers

    private func bucketView(_ bucket: PricingService.PricingBucket, label: String, isActive: Bool) -> some View {
        // Three sold-bucket modes:
        //   - estimated: Market Est. range (no real sales). Show as
        //     "MARKET EST." with low/avg/high tri-grid, no items list.
        //   - stale:     single sale older than requested window. Show
        //                as "LAST SOLD" single cell with age caption.
        //   - default:   real in-window sales. Show standard tri-grid.
        // Only the sold bucket carries the stale/estimated flags.
        let isEstimated = !isActive && (bucket.estimated ?? false)
        let isStale = !isActive && !isEstimated && (bucket.stale ?? false)
        let staleSale = isStale ? bucket.items.first : nil
        let displayLabel = isEstimated ? "MARKET EST." : label
        return VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: 6) {
                Text(displayLabel)
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                    .tracking(1.5)
                if isStale {
                    Text("STALE")
                        .font(Design.Fonts.mono(8, weight: .bold))
                        .foregroundStyle(Color(hex: "E0A000"))
                        .tracking(1.0)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: "E0A000").opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color(hex: "E0A000").opacity(0.45), lineWidth: 0.7)))
                }
                if isEstimated {
                    Text("EST")
                        .font(Design.Fonts.mono(8, weight: .bold))
                        .foregroundStyle(Design.Colors.bobaCyan)
                        .tracking(1.0)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Design.Colors.bobaCyan.opacity(0.45), lineWidth: 0.7)))
                }
            }

            if isStale, let sale = staleSale {
                // Single-cell layout — the one stale sale IS the
                // market anchor. No low/avg/high tri-cell since
                // there's only one data point.
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("LAST SOLD")
                            .font(Design.Fonts.mono(8, weight: .bold))
                            .foregroundStyle(Design.Colors.textMuted)
                            .tracking(1.2)
                        Text(sale.price, format: .currency(code: "USD"))
                            .font(Design.Fonts.mono(16, weight: .bold))
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                    Spacer()
                }
                .padding(.vertical, Design.Spacing.md)
                .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))

                if let staleLabel = staleAgeLabel(sale.date) {
                    Text("Sale \(staleLabel) · older than \(selectedDays)d window")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                } else {
                    Text("Older than \(selectedDays)d window")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            } else {
                HStack(spacing: 0) {
                    priceCell(label: isEstimated ? "EST. LOW"  : "LOW",  value: bucket.low,     isActive: isActive)
                    Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                    priceCell(label: isEstimated ? "EST. MID"  : "AVG",  value: bucket.average, isActive: isActive)
                    Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                    priceCell(label: isEstimated ? "EST. HIGH" : "HIGH", value: bucket.high,    isActive: isActive)
                }
                .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))

                if isEstimated {
                    Text(estimatedCaption(source: bucket.estimatedSource))
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                } else {
                    let typeLabel = isActive ? "listing" : "sold"
                    let plural    = bucket.count != 1 ? "s" : ""
                    Text("\(bucket.count) \(typeLabel)\(plural) · last \(selectedDays)d")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }

            if !bucket.items.isEmpty {
                itemsList(bucket.items, isSold: !isActive)
            }
        }
    }

    /// Renders COMC asking-price listings beneath the eBay BUY NOW
    /// bucket. Same row shape as eBay's `itemRow` — price + title
    /// + tap-out arrow — with a cyan "COMC asking" pill on each
    /// row to make the source obvious. Asking prices ARE NOT
    /// transacted prices, so labelling matters per the handoff's
    /// open-question #1.
    private func comcStrip(_ listings: [ComcService.Listing]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("COMC ASKING")
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.bobaCyan)
                .tracking(1.5)

            VStack(spacing: 1) {
                // Top 3 cheapest — matches the handoff's recommended
                // surface area. The Worker already returns them
                // sorted cheapest-first, so we just take the prefix.
                ForEach(Array(listings.prefix(3))) { listing in
                    Button {
                        if let url = URL(string: listing.comcUrl) {
                            selectedItemURL = IdentifiableURL(url: url)
                        }
                    } label: {
                        comcRow(listing)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
    }

    private func comcRow(_ listing: ComcService.Listing) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            if let price = listing.askingPriceUsd {
                Text(price, format: .currency(code: "USD"))
                    .font(Design.Fonts.mono(13, weight: .bold))
                    .foregroundStyle(Design.Colors.bobaOrange)
                    .frame(width: 64, alignment: .leading)
            } else {
                Text("—")
                    .font(Design.Fonts.mono(13))
                    .foregroundStyle(Design.Colors.textMuted)
                    .frame(width: 64, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Display hero with leading element-prefix stripped —
                // some COMC listings render as "Glow - Showtime"; our
                // catalog stores the hero plainly. Per handoff
                // open-question #2.
                Text(displayTitle(for: listing))
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                comcSourcePill(condition: listing.condition, grading: listing.grading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.textMuted)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface2)
    }

    private func comcSourcePill(condition: String, grading: String) -> some View {
        // "COMC asking · Ungraded NM" — clarifies that the price is
        // an asking, not a sale; condition+grading provide signal
        // about what the buyer would actually receive.
        let suffix: String = {
            let parts = [grading, condition].filter { !$0.isEmpty }
            return parts.isEmpty ? "" : " · \(parts.joined(separator: " "))"
        }()
        return Text("COMC asking\(suffix)")
            .font(Design.Fonts.mono(8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Design.Colors.bobaCyan)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Design.Colors.bobaCyan.opacity(0.10))
                .overlay(Capsule().strokeBorder(Design.Colors.bobaCyan.opacity(0.40), lineWidth: 0.7)))
    }

    private func displayTitle(for listing: ComcService.Listing) -> String {
        // COMC sometimes prefixes hero with element ("Glow - Showtime").
        // Strip a known-element prefix for cleaner display; fall
        // through to the raw hero string if no prefix matches.
        let elements = ["Glow", "Steel", "Fire", "Ice", "Hex", "Brawl", "Gum", "Super"]
        var hero = listing.hero
        for el in elements {
            let prefix = "\(el) - "
            if hero.hasPrefix(prefix) {
                hero = String(hero.dropFirst(prefix.count))
                break
            }
        }
        // "{cardNumber} {hero} ({set})" — concise enough to fit one
        // line, distinct enough to confirm the listing matches the
        // card the user is looking at.
        return "\(listing.cardNumber) \(hero)"
    }

    /// Caption for the Market Est. row. "comps" means the range came
    /// from comparable cards; "own_sales" means it came from the
    /// card's own historical sales (rare for the estimated path —
    /// usually means no in-window sales but some historical ones).
    private func estimatedCaption(source: String?) -> String {
        switch source {
        case "comps":     return "Estimated from comparable cards"
        case "own_sales": return "Estimated from prior sales"
        default:          return "Estimated value"
        }
    }

    /// Human-readable age string for a stale sale. Used on the
    /// "Sale {age} · older than {days}d window" caption. Falls back
    /// to nil when the date can't be parsed (UI then drops the age
    /// portion of the caption).
    private func staleAgeLabel(_ iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days < 0  { return nil }
        if days < 60 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        let years = days / 365
        return "\(years)y ago"
    }

    private func priceCell(label: String, value: Decimal, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.2)
            Text(value, format: .currency(code: "USD"))
                .font(Design.Fonts.mono(16, weight: .bold))
                .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.md)
    }

    /// Converts an ISO 8601 date string to a short relative label.
    private func relativeDate(_ iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days < 0  { return nil }
        if days == 0 { return "today" }
        if days < 7  { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }
        return "\(days / 30)mo ago"
    }

    // MARK: - eBay URL

    private var ebayURL: URL {
        let query = ["bo jackson battle arena", card.hero, card.cardNumber]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")!
        components.queryItems = [
            URLQueryItem(name: "_nkw",        value: query),
            URLQueryItem(name: "LH_Sold",     value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "_sacat",      value: "0"),
            URLQueryItem(name: "_from",       value: "R40"),
            URLQueryItem(name: "_trksid",     value: "m570.l1313"),
            URLQueryItem(name: "_osacat",     value: "0"),
        ]
        return components.url ?? URL(string: "https://www.ebay.com")!
    }

    // MARK: - Radish URL
    //
    // Shared builder lives on Card — see Card+Radish.swift. The same URL
    // is sent to the pricing Worker so it can scrape Radish's pre-
    // validated sold data, not just the one iOS users tap through to.

    private var radishURL: URL {
        resolvedRadishURL
            ?? card.resolvedRadishURL
            ?? URL(string: "https://radishpriceguide.com/boba")!
    }

    // MARK: - Fetch

    private func fetch() {
        guard !WorkerConfig.ebayProxyURL.isEmpty else { return }
        isLoading  = true
        fetchError = nil
        result     = nil
        comcListings = []
        // COMC fires in parallel with the pricing waterfall — it's an
        // additive source on the BUY NOW panel, never blocks the
        // primary fetch. Soft-fails to [] when the Worker is blocked
        // by Cloudflare Turnstile (current state) or any other error.
        if showActiveListings {
            Task {
                let resp = await ComcService.shared.listings(cardNumber: card.cardNumber)
                comcListings = resp.listings
            }
        }
        Task {
            do {
                // Send the RESOLVED URL, not the raw constructed
                // one. Without this, a card whose primary URL
                // 404s would have its button point to the
                // hero-only fallback while the Worker still tried
                // (and failed) to scrape the original 404 — wasting
                // the Radish lookup on every pricing fetch.
                let radishStr = (resolvedRadishURL ?? card.resolvedRadishURL)?.absoluteString
                let pricingResult = try await PricingService.shared.pricing(
                    for: card.cardNumber,
                    hero: card.hero,
                    set: card.set,
                    element: card.element,
                    power: card.power,
                    radishUrl: radishStr,
                    days: selectedDays,
                    treatment: card.treatment
                )
                result = pricingResult
                // Snap the Radish button to whichever URL actually
                // returned data. The Worker tried the cardNumber-
                // specific page first, fell back to the hero-only
                // page, and reported back which one had real
                // listings. Stronger signal than a bare HEAD probe
                // (which can't tell a 200-OK shell from a 200-OK
                // page with sales).
                if let workerURL = pricingResult.radishResolvedUrl,
                   let url = URL(string: workerURL),
                   url != resolvedRadishURL {
                    resolvedRadishURL = url
                    RadishURLResolver.shared.cacheURL(url, for: card)
                }
            } catch PricingService.PricingError.noData {
                fetchError = "No eBay listings found for the last \(selectedDays) days."
            } catch PricingService.PricingError.notConfigured {
                return
            } catch {
                fetchError = "Pricing unavailable"
            }
            isLoading = false
        }
    }
}

// MARK: - IdentifiableURL

/// Wrapper so URL can be used with sheet(item:), ensuring the URL is
/// available before the sheet is presented (fixes blank-on-first-tap).
private struct IdentifiableURL: Identifiable {
    let id  = UUID()
    let url: URL
}
