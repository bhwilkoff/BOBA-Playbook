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
                        // Dual-section layout
                        if let sold = result.sold {
                            bucketView(sold, label: "RECENT SALES", isActive: false)
                        }
                        if showActiveListings, let active = result.active {
                            bucketView(active, label: "BUY NOW", isActive: true)
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
        .task {
            // Probe Radish for the right URL before kicking off the
            // pricing Worker request. The resolver caches per-bobaId
            // so this is a one-time HEAD per card per session. If
            // the probe lands a different URL than card.resolvedRadishURL
            // (e.g. fell back from /hero/cardNumber → /hero), we
            // re-fetch with the corrected URL so the pricing Worker
            // scrapes the same page the user's button now points at.
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
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(label)
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(isActive ? Design.Colors.bobaOrange : Design.Colors.textMuted)
                .tracking(1.5)

            HStack(spacing: 0) {
                priceCell(label: "LOW",  value: bucket.low,     isActive: isActive)
                Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                priceCell(label: "AVG",  value: bucket.average, isActive: isActive)
                Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                priceCell(label: "HIGH", value: bucket.high,    isActive: isActive)
            }
            .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))

            let typeLabel = isActive ? "listing" : "sold"
            let plural    = bucket.count != 1 ? "s" : ""
            Text("\(bucket.count) \(typeLabel)\(plural) · last \(selectedDays)d")
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Design.Colors.textMuted)

            if !bucket.items.isEmpty {
                itemsList(bucket.items, isSold: !isActive)
            }
        }
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
