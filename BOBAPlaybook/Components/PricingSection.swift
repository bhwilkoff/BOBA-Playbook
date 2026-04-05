import SwiftUI

/// Inline pricing card for card detail view.
/// Shows eBay sold LOW / AVG / HIGH for a selectable time window,
/// the most recent individual sales, and a "View on Radish Price Guide" deep link.
struct PricingSection: View {
    let card: Card

    @State private var selectedDays = 30
    @State private var result: PricingService.PricingResult?
    @State private var isLoading = false
    @State private var fetchError: String?
    @State private var showRadish = false
    @State private var showEbay = false
    @State private var selectedSaleURL: URL?
    @State private var showSaleSheet = false

    private let dayOptions = [7, 30, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {

            // Header row
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
                        Divider()
                            .frame(maxHeight: 48)
                            .overlay(Design.Colors.glassBorder)
                        priceCell(label: "AVG",  value: result.average)
                        Divider()
                            .frame(maxHeight: 48)
                            .overlay(Design.Colors.glassBorder)
                        priceCell(label: "HIGH", value: result.high)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.md)
                            .fill(Design.Colors.surface2)
                    )

                    Text("\(result.saleCount) sold on eBay · last \(selectedDays)d")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)

                    // Recent sales list
                    if !result.recentSales.isEmpty {
                        recentSalesList(result.recentSales)
                    }

                } else if let err = fetchError {
                    Text(err)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Design.Spacing.md)
                }
            }

            // External links row
            HStack(spacing: Design.Spacing.sm) {
                // eBay sold listings
                Button { showEbay = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 11))
                        Text("eBay Sales")
                            .font(Design.Fonts.mono(12))
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

                // Radish price guide
                Button { showRadish = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11))
                        Text("Radish Guide")
                            .font(Design.Fonts.mono(12))
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
        .sheet(isPresented: $showEbay) {
            SafariView(url: ebayURL)
        }
        .sheet(isPresented: $showRadish) {
            SafariView(url: radishURL)
        }
        .sheet(isPresented: $showSaleSheet) {
            if let url = selectedSaleURL {
                SafariView(url: url)
            }
        }
    }

    // MARK: - Recent sales list

    private func recentSalesList(_ sales: [PricingService.SaleItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT SALES")
                .font(Design.Fonts.mono(8, weight: .bold))
                .foregroundStyle(Design.Colors.textMuted)
                .tracking(1.5)
                .padding(.bottom, Design.Spacing.xs)

            VStack(spacing: 1) {
                ForEach(Array(sales.enumerated()), id: \.offset) { _, sale in
                    Button {
                        if let url = URL(string: sale.url), !sale.url.isEmpty {
                            selectedSaleURL = url
                            showSaleSheet = true
                        }
                    } label: {
                        saleRow(sale)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(Design.Colors.surface2)
            )
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
    }

    private func saleRow(_ sale: PricingService.SaleItem) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            // Price
            Text(sale.price, format: .currency(code: "USD"))
                .font(Design.Fonts.mono(13, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .frame(width: 64, alignment: .leading)

            // Title (truncated)
            Text(sale.title)
                .font(Design.Fonts.mono(11))
                .foregroundStyle(Design.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Date
            Text(relativeDate(sale.date))
                .font(Design.Fonts.mono(10))
                .foregroundStyle(Design.Colors.textMuted)
                .frame(width: 52, alignment: .trailing)
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

    /// Converts an ISO 8601 date string to a short relative label ("2d ago", "3w ago", etc.)
    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)    // fallback without fractional seconds
        guard let date else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 0 { return "" }
        let days = Int(diff / 86400)
        if days == 0 { return "today" }
        if days < 7  { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5  { return "\(weeks)w ago" }
        let months = days / 30
        return "\(months)mo ago"
    }

    // MARK: - eBay URL

    /// eBay sold/completed listings search using the Radish-validated query formula:
    /// "{year} bo jackson battle arena {hero} {treatment} {element}"
    ///
    /// This matches how sellers actually list BOBA cards — by game name, hero, and
    /// parallel treatment — rather than by card number, which sellers rarely include.
    private var ebayURL: URL {
        let query = ebaySearchQuery
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

    /// "{year} bo jackson battle arena {hero} {treatment} {element}"
    /// Shared between the eBay browser link and the pricing Worker API call.
    private var ebaySearchQuery: String {
        [ebayYear, "bo jackson battle arena", card.hero, ebayTreatment, card.element.capitalized]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var ebayTreatment: String {
        let prefix = card.cardNumber.components(separatedBy: "-").first?.uppercased() ?? ""
        let map: [String: String] = [
            "GLBF": "Grandma's Linoleum Battlefoil",
            "BLBF": "Blizzard Battlefoil",
            "RAD":  "80's Rad Battlefoil",
            "LOGO": "Logo Battlefoil",
            "MIX":  "Mix Battlefoil",
            "BBF":  "Blizzard Battlefoil",
            "ABF":  "Alpha Battlefoil",
            "IBF":  "Ice Battlefoil",
            "SBF":  "Stained Glass Battlefoil",
        ]
        return map[prefix] ?? "Paper"
    }

    private var ebayYear: String {
        let map: [String: String] = [
            "Alpha":                   "2024",
            "Alpha Blast":             "2025",
            "Alpha Update":            "2025",
            "Griffey":                 "2026",
            "Battle Trainer Kit":      "2024",
            "National 24 Starter Set": "2024",
            "World Champions 2024":    "2024",
            "World Champions 2025":    "2025",
            "Promo Cards":             "2025",
            "Big League Chew":         "2025",
        ]
        return map[card.set] ?? "2024"
    }

    // MARK: - Radish URL

    /// Returns the Radish Price Guide URL for this card.
    ///
    /// Primary: use the pre-built `radishUrl` field from the card catalog.
    /// This was constructed from Radish's own sitemap crawl, so it is always
    /// correct — including edge cases like mixed-case prefixes (Rad-, Logo-, Mix-)
    /// and multi-word hero names with spaces.
    ///
    /// Fallback: programmatic construction for the ~1.2% of cards that have
    /// `radishUrl: null` (cards not listed on Radish, e.g. Billy/Alt/BBFA prefix).
    /// These will land on the Radish homepage rather than a 404.
    private var radishURL: URL {
        // Prefer pre-built URL from catalog
        if let prebuilt = card.radishUrl, let url = URL(string: prebuilt) {
            return url
        }

        // Programmatic fallback — mirrors the RADISH_URL_SCHEMA.md logic
        let prefixMap = ["LOGO": "Logo", "RAD": "Rad", "MIX": "Mix"]
        var cardNum = card.cardNumber
        for (ours, theirs) in prefixMap {
            if cardNum.hasPrefix(ours + "-") {
                cardNum = theirs + cardNum.dropFirst(ours.count)
                break
            }
        }

        let setMap: [String: (year: String, slug: String)] = [
            "Alpha":                   ("2024", "Alpha_Edition"),
            "Alpha Blast":             ("2025", "Alpha_Blast"),
            "Alpha Update":            ("2025", "Alpha_Update"),
            "Griffey":                 ("2026", "Griffey_Edition"),
            "Battle Trainer Kit":      ("2024", "Battle_Trainer_Kit"),
            "National 24 Starter Set": ("2024", "National_24_Starter_Set"),
            "World Champions 2024":    ("2024", "World_Champions"),
            "World Champions 2025":    ("2025", "World_Champions"),
            "Promo Cards":             ("2025", "Promo_Cards"),
            "Big League Chew":         ("2025", "Big_League_Chew"),
        ]
        let (year, slug) = setMap[card.set] ?? ("2024", "Alpha_Edition")
        let hero = card.hero.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? card.hero
        let num  = cardNum.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cardNum

        return URL(string: "https://radishpriceguide.com/boba/\(year)/\(slug)/\(hero)/\(num)")
            ?? URL(string: "https://radishpriceguide.com/boba")!
    }

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
                    days: selectedDays
                )
            } catch PricingService.PricingError.noSales {
                fetchError = "No eBay sales found in the last \(selectedDays) days."
            } catch PricingService.PricingError.notConfigured {
                return
            } catch {
                fetchError = "Pricing unavailable"
            }
            isLoading = false
        }
    }
}
