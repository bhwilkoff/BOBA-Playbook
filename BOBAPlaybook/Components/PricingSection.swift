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
    @State private var showEbay = false
    @State private var selectedItemURL: IdentifiableURL?
    /// COMC.com asking-price listings, fetched in parallel with the
    /// eBay pricing call. Additive to the BUY NOW panel — stays empty
    /// when COMC's WAF blocks the worker (current state per 2026-04-29).
    /// Soft-fail by design.
    @State private var comcListings: [ComcService.Listing] = []
    /// Whatnot active asks (Tier 2) — additive BUY NOW source, matched-first.
    @State private var whatnotListings: [WhatnotProductsService.Listing] = []
    /// Tier 3 community-comp submission sheet (PRICING_PLAYBOOK §5). Opened
    /// from a quiet foot affordance; the sheet carries the form + auth gate.
    @State private var showCommunityCompSheet = false

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
                        // Market-estimate caption per DESIGN.md §8.7 — single
                        // line above the two sections. Per DECISIONS.md #034,
                        // asking prices are NEVER folded into this number;
                        // the basis is exposed so users can audit.
                        if let sold = result.sold,
                           let caption = marketEstimateCaption(sold: sold) {
                            Text(caption)
                                .font(Design.Fonts.mono(11, weight: .bold))
                                .foregroundStyle(Design.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Dual-section layout per DESIGN.md §8.7 — order is
                        // BUY NOW (asking, "where can I buy") on top, then
                        // RECENT SALES (transacted, "what's it worth") below.
                        // Walkthrough anchors point at each bucket so the
                        // .pricingPanels script teaches the asking-vs-sold
                        // distinction.
                        // Provenance-honest (DESIGN.md §8.7): with no
                        // real sold data the active listings ARE the
                        // signal — show them as "LISTED RANGE" (range +
                        // honest "no recent sales" provenance), never a
                        // fabricated Market Est. With real sold data the
                        // dual "BUY NOW" + "RECENT SALES" framing holds.
                        let noSold = result.sold == nil
                        if showActiveListings, let active = result.active {
                            bucketView(active,
                                       label: noSold ? "LISTED RANGE" : "BUY NOW",
                                       isActive: true,
                                       listedRange: noSold)
                                .walkthroughAnchor("pricing.buyNow")
                        }
                        if let sold = result.sold {
                            bucketView(sold, label: "RECENT SALES", isActive: false)
                                .walkthroughAnchor("pricing.sold")
                        }
                        // COMC asking-price strip lives below the eBay
                        // BUY NOW bucket. Renders only when COMC has
                        // listings; absent (Turnstile blocked, no
                        // inventory) means nothing shows.
                        if showActiveListings, !comcListings.isEmpty {
                            comcStrip(comcListings)
                        }
                        // Whatnot active asks — additive BUY NOW source,
                        // matched-first then "Other {hero}" (Hybrid). Asks
                        // never fold into any sold number (#034).
                        if showActiveListings, !whatnotListings.isEmpty {
                            whatnotStrip(whatnotListings)
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

                // Per Radish (2026-05-23): ordinary user-facing link
                // ONLY — opens the system browser outside the app; no
                // SafariView / SFSafariViewController. Uses the legacy
                // catalog `radishUrl` field when present (static data
                // acquired before the email; no probing or lookup),
                // falls back to the Radish homepage when null.
                Link(destination: card.radishDisplayURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                        Text("View on Radish").font(Design.Fonts.mono(12))
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

            // Community comp submission (Tier 3, DESIGN.md §8.7) — a quiet,
            // subordinate affordance at the FOOT of the pricing section. A
            // low-emphasis link; the focused sheet carries the form + auth
            // gate. Never rivals the card art or Add to Collection.
            Button { showCommunityCompSheet = true } label: {
                Text("Saw one sell? Add a price")
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.bobaCyan.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .task(id: PricingPulse.shared.version) {
            // Re-runs when:
            //   - The view first appears (initial id matches)
            //   - PricingService invalidates (Collection refresh,
            //     Show queue scanner, individual show "Refresh
            //     Prices", or per-card forceRefresh) bumps the
            //     pulse — every open PricingSection re-fetches.
            fetch()
        }
        .onChange(of: selectedDays) { fetch() }
        .sheet(isPresented: $showEbay)   { SafariView(url: ebayURL) }
        // sheet(item:) ensures the URL is set before the sheet is presented,
        // fixing the blank-on-first-tap bug that sheet(isPresented:) caused.
        .sheet(item: $selectedItemURL) { item in SafariView(url: item.url) }
        .sheet(isPresented: $showCommunityCompSheet) {
            SubmitCommunityCompSheet(card: card)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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

    private func bucketView(_ bucket: PricingService.PricingBucket, label: String, isActive: Bool, listedRange: Bool = false) -> some View {
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
                // Per user feedback — Low/AVG/High only makes sense
                // when there's enough data to spread across three
                // anchor points. For BUY NOW, where each listing is
                // an independent asking price, the items list below
                // already shows every individual price so the
                // tri-grid is redundant. For SOLD, the tri-grid
                // adds signal only when count > 1; a single sale
                // gets a single "Last sold" cell.
                let showsTriGrid = isEstimated || (!isActive && bucket.count > 1) || (listedRange && bucket.count > 1)
                if showsTriGrid {
                    HStack(spacing: 0) {
                        priceCell(label: isEstimated ? "EST. LOW"  : "LOW",  value: bucket.low,     isActive: isActive)
                        Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                        priceCell(label: isEstimated ? "EST. MID"  : "AVG",  value: bucket.average, isActive: isActive)
                        Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                        priceCell(label: isEstimated ? "EST. HIGH" : "HIGH", value: bucket.high,    isActive: isActive)
                    }
                    .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))
                } else {
                    // Single anchor — for BUY NOW shows lowest asking
                    // price; for a single SOLD shows that one sale.
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text(isActive ? "FROM" : "LAST SOLD")
                                .font(Design.Fonts.mono(8, weight: .bold))
                                .foregroundStyle(Design.Colors.textMuted)
                                .tracking(1.2)
                            Text(bucket.low, format: .currency(code: "USD"))
                                .font(Design.Fonts.mono(16, weight: .bold))
                                .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Design.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))
                }

                if isEstimated {
                    Text(estimatedCaption(source: bucket.estimatedSource))
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                } else if listedRange {
                    // Honest provenance: these are active asks, and we
                    // have no recent sales to anchor a value yet.
                    let plural = bucket.count != 1 ? "s" : ""
                    Text("\(bucket.count) active eBay listing\(plural) · no recent sales data yet")
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

    // MARK: - Whatnot active asks (Tier 2)

    /// Renders Whatnot active listings beneath the eBay BUY NOW + COMC
    /// strips. Hybrid surfacing: this card's matched listings first, then
    /// an "Other {hero} listings" group below a divider. Violet accent
    /// separates it from the cyan COMC strip. Asking prices, NEVER folded
    /// into any sold number (#034). Top 3 per group.
    @ViewBuilder
    private func whatnotStrip(_ listings: [WhatnotProductsService.Listing]) -> some View {
        let matched = listings.filter { $0.matchesCard == true }
        let others  = listings.filter { $0.matchesCard != true }
        let hasMatch = !matched.isEmpty
        let lead = hasMatch ? matched : others
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("WHATNOT · ACTIVE ASKS")
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.bobaViolet)
                .tracking(1.5)

            whatnotGroup(Array(lead.prefix(3)))

            if hasMatch, !others.isEmpty {
                Text("Other \(card.hero) listings")
                    .font(Design.Fonts.mono(8, weight: .bold))
                    .foregroundStyle(Design.Colors.textMuted)
                    .tracking(0.5)
                    .padding(.top, 2)
                whatnotGroup(Array(others.prefix(3)))
            }
        }
    }

    private func whatnotGroup(_ listings: [WhatnotProductsService.Listing]) -> some View {
        VStack(spacing: 1) {
            ForEach(listings) { listing in
                Button {
                    if let url = URL(string: listing.listingUrl) {
                        selectedItemURL = IdentifiableURL(url: url)
                    }
                } label: {
                    whatnotRow(listing)
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
    }

    private func whatnotRow(_ listing: WhatnotProductsService.Listing) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Text(listing.price, format: .currency(code: listing.currency ?? "USD"))
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.bobaOrange)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(Design.Fonts.mono(11))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
                whatnotSourcePill(listing)
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

    private func whatnotSourcePill(_ listing: WhatnotProductsService.Listing) -> some View {
        let label = listing.format == "auction" ? "Whatnot bid" : "Whatnot ask"
        let seller = (listing.seller?.isEmpty == false) ? " · @\(listing.seller!)" : ""
        return Text("\(label)\(seller)")
            .font(Design.Fonts.mono(8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Design.Colors.bobaViolet)
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Design.Colors.bobaViolet.opacity(0.10))
                .overlay(Capsule().strokeBorder(Design.Colors.bobaViolet.opacity(0.40), lineWidth: 0.7)))
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

    /// Single-line market-estimate caption above the dual price sections
    /// per DESIGN.md §8.7 — "$24 · based on 8 recent sales". The number
    /// reflects ONLY transacted prices (sold bucket) per DECISIONS.md
    /// #034; asking prices are never folded in.
    private func marketEstimateCaption(sold: PricingService.PricingBucket) -> String? {
        let est = sold.average
        guard est > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = est >= 100 ? 0 : 2
        guard let priceStr = formatter.string(from: est as NSDecimalNumber) else { return nil }
        let isEstimated = sold.estimated ?? false
        if isEstimated {
            return "Market est. \(priceStr) · \(estimatedCaption(source: sold.estimatedSource))"
        }
        let n = sold.count
        guard n > 0 else { return "Market est. \(priceStr)" }
        let plural = n != 1 ? "sales" : "sale"
        return "~\(priceStr) · based on \(n) recent \(plural)"
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

    // MARK: - Fetch

    private func fetch() {
        guard !WorkerConfig.ebayProxyURL.isEmpty else { return }
        isLoading  = true
        fetchError = nil
        result     = nil
        comcListings = []
        whatnotListings = []
        // COMC + Whatnot fire in parallel with the pricing waterfall —
        // additive asking sources on the BUY NOW panel, never block the
        // primary fetch. Both soft-fail to [] when their Worker is blocked
        // by Cloudflare or hits any other error.
        if showActiveListings {
            Task {
                let resp = await ComcService.shared.listings(cardNumber: card.cardNumber)
                comcListings = resp.listings
            }
            // Whatnot active asks — query by the distinctive hero token;
            // the Worker binds to this card via cardNumber + weapon and
            // flags matchesCard (best-first). Asks, never sold (#034).
            Task {
                let resp = await WhatnotProductsService.shared.products(
                    query: card.hero, cardNumber: card.cardNumber, weapon: card.element)
                if resp.challenged != true { whatnotListings = resp.listings }
            }
        }
        Task {
            do {
                let pricingResult = try await PricingService.shared.pricing(
                    for: card.cardNumber,
                    hero: card.hero,
                    set: card.set,
                    element: card.element,
                    power: card.power,
                    days: selectedDays,
                    treatment: card.treatment,
                    variation: card.variation
                )
                result = pricingResult
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

// MARK: - Community comp submission (Tier 3)

/// Quiet, subordinate sheet reached from the foot of the pricing section
/// (PRICING_PLAYBOOK §5 · DESIGN.md §8.7). Auth-gated; the server RPC
/// `submit_community_comp` enforces the rate limits (5/day, 1/card/week),
/// so the client just collects price + date + platform + optional notes.
/// Inlined here rather than a standalone file per the Xcode
/// synchronized-group reliability note (DECISIONS.md #031).
private struct SubmitCommunityCompSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth

    @State private var priceText  = ""
    @State private var soldDate   = Date()
    @State private var platform   = "ebay"
    @State private var notes      = ""
    @State private var submitting = false
    @State private var statusText: String?
    @State private var done = false

    private let platforms = ["ebay", "whatnot", "mercari", "in-person", "other"]
    private func platformLabel(_ p: String) -> String {
        switch p {
        case "ebay":      return "eBay"
        case "whatnot":   return "Whatnot"
        case "mercari":   return "Mercari"
        case "in-person": return "In person"
        default:          return "Other"
        }
    }
    private var priceValue: Decimal { Decimal(string: priceText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("Thanks — a moderator will review your comp.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Design.Colors.bobaCyan)
                    }
                } else if !auth.isAuthenticated {
                    Section {
                        Text("Sign in from the Profile tab to add a sold price, then come back.")
                            .font(Design.Fonts.mono(12))
                            .foregroundStyle(Design.Colors.textMuted)
                    }
                } else {
                    Section("Sold price") {
                        HStack {
                            Text("Price")
                            Spacer()
                            TextField("$0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }
                        DatePicker("Sold on", selection: $soldDate,
                                   in: ...Date(), displayedComponents: .date)
                        Picker("Where", selection: $platform) {
                            ForEach(platforms, id: \.self) { Text(platformLabel($0)).tag($0) }
                        }
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(1...3)
                    }
                    if let statusText {
                        Section {
                            Text(statusText)
                                .font(Design.Fonts.mono(11))
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            Text(submitting ? "Submitting…" : "Submit comp")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(submitting || priceValue <= 0)
                    } footer: {
                        Text("A moderator reviews each submission before it appears in the estimate.")
                    }
                }
            }
            .navigationTitle("Add a sold price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard priceValue > 0 else { statusText = "Enter a valid price."; return }
        submitting = true
        statusText = nil
        do {
            try await SupabaseClient.shared.submitCommunityComp(
                bobaId:   card.bobaId,
                price:    priceValue,
                soldAt:   soldDate,
                platform: platform,
                notes:    notes.isEmpty ? nil : notes)
            submitting = false
            withAnimation { done = true }
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        } catch {
            submitting = false
            statusText = "Couldn't submit — you may have hit the daily limit, or already added one for this card this week."
        }
    }
}
