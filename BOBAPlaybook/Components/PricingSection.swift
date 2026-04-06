import SwiftUI

/// Inline pricing card shown in card detail views.
/// Fetches sold item history (Marketplace Insights) or active listing prices
/// (Browse API fallback) from the eBay proxy worker.
struct PricingSection: View {
    let card: Card

    @State private var selectedDays = 30
    @State private var result: PricingService.PricingResult?
    @State private var isLoading = false
    @State private var fetchError: String?
    @State private var showRadish = false
    @State private var showEbay = false
    @State private var selectedItemURL: IdentifiableURL?

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
                    // LOW / AVG / HIGH
                    HStack(spacing: 0) {
                        priceCell(label: "LOW",  value: result.low)
                        Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                        priceCell(label: "AVG",  value: result.average)
                        Divider().frame(maxHeight: 48).overlay(Design.Colors.glassBorder)
                        priceCell(label: "HIGH", value: result.high)
                    }
                    .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Colors.surface2))

                    // Count + type label
                    let typeLabel = result.isSold ? "sold" : "active listing"
                    let plural    = result.count != 1 ? "s" : ""
                    Text("\(result.count) \(typeLabel)\(plural) · last \(selectedDays)d")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)

                    // Individual items list
                    if !result.items.isEmpty {
                        itemsList(result.items, isSold: result.isSold)
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
        .onAppear { fetch() }
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

            Text(item.title)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
                .lineLimit(1)
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

    // MARK: - Helpers

    private func priceCell(label: String, value: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.2)
            Text(value, format: .currency(code: "USD"))
                .font(Design.Fonts.mono(16, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
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

    private var radishURL: URL {
        if let prebuilt = card.radishUrl, let url = URL(string: prebuilt) { return url }

        let prefixMap = ["LOGO": "Logo", "RAD": "Rad", "MIX": "Mix"]
        var cardNum = card.cardNumber
        for (ours, theirs) in prefixMap {
            if cardNum.hasPrefix(ours + "-") { cardNum = theirs + cardNum.dropFirst(ours.count); break }
        }
        // Includes all set name variants found in cards.json (short names, full names, slug forms)
        let setMap: [String: (year: String, slug: String)] = [
            // Alpha Edition variants
            "Alpha":                          ("2024", "Alpha_Edition"),
            "Alpha Edition":                  ("2024", "Alpha_Edition"),
            "alpha-edition":                  ("2024", "Alpha_Edition"),
            // Alpha Update variants
            "Alpha Update":                   ("2025", "Alpha_Update"),
            "alpha-update":                   ("2025", "Alpha_Update"),
            "Alpha Blast":                    ("2025", "Alpha_Blast"),
            // Griffey Edition variants
            "Griffey":                        ("2026", "Griffey_Edition"),
            "Griffey Edition":                ("2026", "Griffey_Edition"),
            "griffey-edition":                ("2026", "Griffey_Edition"),
            // National Show Starter Set variants
            "2024 National Show Starter Set": ("2024", "National_24_Starter_Set"),
            "National '24":                   ("2024", "National_24_Starter_Set"),
            "National 24 Starter Set":        ("2024", "National_24_Starter_Set"),
            // World Champions variants
            "World Champions":                ("2024", "World_Champions"),
            "world-champions":                ("2024", "World_Champions"),
            "World Champions 2024":           ("2024", "World_Champions"),
            "World Champions 2025":           ("2025", "World_Champions"),
            // Other sets
            "Battle Trainer Kit":             ("2024", "Battle_Trainer_Kit"),
            "Superfan Series":                ("2024", "Alpha_Edition"),
            "Tecmo Bowl Edition":             ("2025", "Tecmo_Bowl"),
            "tecmo-bowl":                     ("2025", "Tecmo_Bowl"),
            "Promo Cards":                    ("2025", "Promo_Cards"),
            "Big League Chew":                ("2025", "Big_League_Chew"),
            "big-league-chew":                ("2025", "Big_League_Chew"),
            "sandstorm":                      ("2025", "Sandstorm"),
        ]
        let (year, slug) = setMap[card.set] ?? ("2024", "Alpha_Edition")
        let hero = card.hero.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? card.hero
        let num  = cardNum.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cardNum
        return URL(string: "https://radishpriceguide.com/boba/\(year)/\(slug)/\(hero)/\(num)")
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
                result = try await PricingService.shared.pricing(
                    for: card.cardNumber,
                    hero: card.hero,
                    set: card.set,
                    element: card.element,
                    power: card.power,
                    radishUrl: card.radishUrl,
                    days: selectedDays
                )
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
