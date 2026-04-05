import SwiftUI

/// Inline pricing card for card detail view.
/// Shows eBay sold LOW / AVG / HIGH for a selectable time window,
/// plus a "View on Radish Price Guide" deep link.
struct PricingSection: View {
    let card: Card

    @State private var selectedDays = 30
    @State private var result: PricingService.PricingResult?
    @State private var isLoading = false
    @State private var fetchError: String?
    @State private var showRadish = false

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

            // Price grid
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView().tint(Design.Colors.bobaOrange); Spacer() }
                        .frame(height: 64)
                } else if let result {
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
                } else if let err = fetchError {
                    Text(err)
                        .font(Design.Fonts.mono(11))
                        .foregroundStyle(Design.Colors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Design.Spacing.md)
                }
            }

            // Radish link
            Button { showRadish = true } label: {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text("View on Radish Price Guide")
                        .font(Design.Fonts.mono(12))
                }
                .foregroundStyle(Design.Colors.bobaCyan)
            }
        }
        .onAppear { fetch() }
        .onChange(of: selectedDays) { fetch() }
        .sheet(isPresented: $showRadish) {
            SafariView(url: radishURL)
        }
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

    private var radishURL: URL {
        // Best-effort Radish URL using card number as the primary key.
        // If Radish updates their URL structure, update this helper.
        let encoded = card.cardNumber
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? card.cardNumber
        return URL(string: "https://radishpriceguide.com/boba/\(encoded)")
            ?? URL(string: "https://radishpriceguide.com")!
    }

    private func fetch() {
        guard !WorkerConfig.ebayProxyURL.isEmpty else { return }
        isLoading  = true
        fetchError = nil
        result     = nil
        Task {
            do {
                result = try await PricingService.shared.pricing(
                    for: card.cardNumber, days: selectedDays
                )
            } catch PricingService.PricingError.noSales {
                fetchError = "No eBay sales found in the last \(selectedDays) days."
            } catch PricingService.PricingError.notConfigured {
                // Worker not wired up yet — stay silent (no pricing UI shown)
                return
            } catch {
                fetchError = "Pricing unavailable"
            }
            isLoading = false
        }
    }
}
