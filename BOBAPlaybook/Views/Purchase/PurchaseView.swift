//
//  PurchaseView.swift
//  BOBAPlaybook
//
//  Two sub-modes (segmented picker, matching CollectionView's mode picker):
//    1. Upcoming Breaks — Whatnot live + upcoming feed for "Bo Jackson
//       Battle Arena", served by the boba-ebay-proxy Worker.
//    2. Find a Store — embeds StoreLocatorView (moved here from Collection).
//

import SwiftUI

struct PurchaseView: View {
    enum PurchaseMode: String, CaseIterable, Identifiable {
        case breaks = "Live Breaks"
        case stores = "Find a Store"
        var id: String { rawValue }
    }

    @State private var mode: PurchaseMode = .breaks

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)

                switch mode {
                case .breaks:
                    // UpcomingBreaksList owns its own ScrollView so the
                    // `.refreshable` gesture attaches directly to the
                    // grid's scroll context.
                    UpcomingBreaksList()
                case .stores:
                    StoreLocatorView()
                }
            }
            .background(Design.Colors.nearBlack)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BOBAWordmark()
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(PurchaseMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

}
