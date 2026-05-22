import SwiftUI
import MapKit
import CoreLocation
import Combine

struct StoreLocatorView: View {
    @State private var store = StoreLocatorStore()
    @State private var selectedStore: StoreLocation?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .init(latitude: 39.8283, longitude: -98.5795),   // CONUS center
            span:   .init(latitudeDelta: 55, longitudeDelta: 55)
        )
    )
    @StateObject private var location = LocationPermissionManager()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // iPad regular width gets a true horizontal split (map left,
        // list right) per DESIGN.md §6.6 — phone keeps the vertical
        // stack with the fixed-height map. Filter bar spans full
        // width on both layouts.
        VStack(spacing: 0) {
            filterBar
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    mapSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    listSection
                        .frame(width: 380)
                }
            } else {
                mapSection
                listSection
            }
        }
        .background(Design.Colors.nearBlack)
        .navigationTitle("Find a Store")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if store.stores.isEmpty { await store.load() }
        }
        .sheet(item: $selectedStore) { s in
            StoreDetailSheet(store: s)
        }
        .onChange(of: location.coordinateTick) { _, _ in
            guard let c = location.coordinate else { return }
            store.userLocation = c
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(center: c,
                                       span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6))
                )
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Design.Colors.textMuted)
                    TextField("Search name, city, or ZIP", text: $store.searchText)
                        .font(Design.Fonts.mono(14))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Design.Colors.textMuted)
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(Design.Colors.glass)
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.md)
                            .strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
                )

                stateMenu
                nearMeButton
            }

            HStack(spacing: Design.Spacing.sm) {
                bigBoxToggle
                Spacer()
                if let label = store.lastUpdatedLabel {
                    // Tick 432 — relative-format the stamp ("Updated 5d
                    // ago" instead of "Updated 2026-05-17"). Web tick 428
                    // + Android tick 431 parity. Falls back to ISO prefix
                    // for >5wk-old scrapes.
                    Text("Updated \(relativeStoreDate(label))")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }

            HStack {
                Text(summaryLine)
                    .font(Design.Fonts.mono(10))
                    .foregroundStyle(Design.Colors.textMuted)
                Spacer()
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface)
    }

    private var stateMenu: some View {
        Menu {
            Button("All States") { store.selectedState = "" }
            ForEach(store.availableStates, id: \.self) { code in
                Button(code) { store.selectedState = code }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.selectedState.isEmpty ? "State" : store.selectedState)
                    .font(Design.Fonts.mono(12, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(store.selectedState.isEmpty ? Design.Colors.textSecondary : Design.Colors.nearBlack)
            .padding(.horizontal, Design.Spacing.sm)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .fill(store.selectedState.isEmpty ? Design.Colors.glass : Design.Colors.bobaOrange)
            )
        }
    }

    // "Include Big Box" toggle pill. Default off — puts independent
    // hobby shops front-and-center. Label shows hidden count so coaches
    // understand the toggle is hiding things, not missing them.
    private var bigBoxToggle: some View {
        Button {
            store.includeBigBox.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.includeBigBox ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .bold))
                Text(store.includeBigBox ? "Big box included" : "Include big box")
                    .font(Design.Fonts.mono(11, weight: .bold))
                if !store.includeBigBox && store.hiddenBigBoxCount > 0 {
                    Text("(\(store.hiddenBigBoxCount) hidden)")
                        .font(Design.Fonts.mono(10))
                        .foregroundStyle(Design.Colors.textMuted)
                }
            }
            .foregroundStyle(store.includeBigBox ? Design.Colors.nearBlack : Design.Colors.textSecondary)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(store.includeBigBox ? Design.Colors.bobaCyan : Design.Colors.glass)
                    .overlay(Capsule().strokeBorder(Design.Colors.glassBorder, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    /// Summary line: "X independent  ·  Y of Z shown" depending on mode.
    /// Tick 427 — locale-format the counts. The full catalog hits
    /// ~2,000 stores between indie + big-box; "2,130" reads cleaner
    /// than "2130". Android tick 424 + tick 412/414 (collection)
    /// parity pattern.
    private var summaryLine: String {
        let shown = store.filtered.count
        let total = store.stores.count
        if !store.includeBigBox {
            let hidden = store.hiddenBigBoxCount
            return "\(shown.formatted()) independent retailers  ·  \(hidden.formatted()) big box hidden"
        }
        return "\(shown.formatted()) of \(total.formatted()) authorized retailers"
    }

    private var nearMeButton: some View {
        Button {
            location.requestAndFetch()
        } label: {
            Image(systemName: location.isAuthorized ? "location.fill" : "location")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(location.isAuthorized ? Design.Colors.nearBlack : Design.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.md)
                        .fill(location.isAuthorized ? Design.Colors.bobaCyan : Design.Colors.glass)
                )
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        // Per user feedback — the map was inset by horizontal +
        // vertical padding inside a black-background parent, which
        // produced a black halo around the rounded-rectangle map and
        // looked clashy when the list scrolled into the gap. Map now
        // fills edge-to-edge (no rounded corners, no padding) so it
        // sits flush against the filter bar above and the list below
        // — like Apple Maps' own Find layout.
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition, selection: .constant(nil)) {
                ForEach(store.filtered.prefix(500)) { s in
                    Annotation(s.name, coordinate: s.coordinate) {
                        Button { selectedStore = s } label: {
                            BOBAPinMarker(size: 26)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
                if let userLoc = store.userLocation {
                    Annotation("You", coordinate: userLoc) {
                        Circle()
                            .fill(Design.Colors.bobaCyan)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapStyle(.standard(elevation: .flat))
            // Compact (phone): fixed 240pt above the list. Regular
            // (iPad): fill the trailing column; the parent split-view
            // gives the map full vertical headroom.
            .frame(height: horizontalSizeClass == .regular ? nil : 240)
            .frame(maxHeight: horizontalSizeClass == .regular ? .infinity : nil)

            if store.loadState == .loading {
                ProgressView()
                    .tint(Design.Colors.bobaOrange)
                    .padding(Design.Spacing.sm)
                    .background(.thinMaterial, in: Capsule())
                    .padding(Design.Spacing.sm)
            }
        }
        .walkthroughAnchor("purchase.storeMap")  // §6.10.1 walkthrough catalog
    }

    // MARK: - List

    private var listSection: some View {
        Group {
            switch store.loadState {
            case .loading where store.stores.isEmpty:
                loadingState
            case .failed(let msg) where store.stores.isEmpty:
                failureState(msg)
            default:
                if store.filtered.isEmpty {
                    emptyFilterState
                } else {
                    StoreListView(
                        stores: store.filtered,
                        distanceLabel: { store.distanceLabel(to: $0) },
                        onTap: { selectedStore = $0 }
                    )
                    .refreshable {
                        await store.refresh()
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            ProgressView().tint(Design.Colors.bobaOrange)
            Text("Loading stores…")
                .font(Design.Fonts.mono(13))
                .foregroundStyle(Design.Colors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func failureState(_ msg: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("Couldn't load the store list.")
                .font(Design.Fonts.display(16))
                .foregroundStyle(Design.Colors.textPrimary)
            Text(msg)
                .font(Design.Fonts.mono(12))
                .foregroundStyle(Design.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.xl)
            Button("Try Again") {
                Task { await store.refresh() }
            }
            .font(Design.Fonts.mono(13, weight: .bold))
            .foregroundStyle(Design.Colors.nearBlack)
            .padding(.horizontal, Design.Spacing.lg)
            .frame(height: 38)
            .background(Capsule().fill(Design.Colors.bobaOrange))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyFilterState: some View {
        VStack(spacing: Design.Spacing.sm) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Design.Colors.textMuted)
            Text("No stores match your search.")
                .font(Design.Fonts.mono(14))
                .foregroundStyle(Design.Colors.textMuted)
            Button("Clear filters") {
                store.searchText = ""
                store.selectedState = ""
            }
            .font(Design.Fonts.mono(12, weight: .bold))
            .foregroundStyle(Design.Colors.bobaCyan)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BOBA logo marker
//
// The 2×2 XOXO grid from the app icon, scaled to a 28pt circle. Drawn
// as a SwiftUI Canvas so there's no PNG to import and the mark scales
// cleanly on any display density. Used for map annotations + list rows
// so "BOBA lives here" reads instantly in both places.
private struct BOBAMarkIcon: View {
    var stroke: Color = .white
    var body: some View {
        Canvas { ctx, size in
            let cellW = size.width / 2
            let cellH = size.height / 2
            let r = min(cellW, cellH) * 0.32
            let lineW = max(1.5, min(cellW, cellH) * 0.18)
            let centers: [(CGFloat, CGFloat, Bool)] = [
                // (cx, cy, isX)
                (cellW * 0.5, cellH * 0.5, true),
                (cellW * 1.5, cellH * 0.5, false),
                (cellW * 0.5, cellH * 1.5, false),
                (cellW * 1.5, cellH * 1.5, true),
            ]
            for (cx, cy, isX) in centers {
                if isX {
                    var p = Path()
                    p.move(to: CGPoint(x: cx - r, y: cy - r))
                    p.addLine(to: CGPoint(x: cx + r, y: cy + r))
                    p.move(to: CGPoint(x: cx + r, y: cy - r))
                    p.addLine(to: CGPoint(x: cx - r, y: cy + r))
                    ctx.stroke(p, with: .color(stroke),
                               style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                } else {
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: lineW)
                }
            }
        }
    }
}

struct BOBAPinMarker: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle()
                .fill(Design.Colors.bobaOrange)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
            BOBAMarkIcon(stroke: .white)
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 2.5, x: 0, y: 1.5)
    }
}

// MARK: - Location permission helper

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var coordinate: CLLocationCoordinate2D? = nil
    /// Monotonic counter bumped each time `coordinate` changes. Used by
    /// SwiftUI `onChange` since `CLLocationCoordinate2D` isn't Equatable.
    @Published var coordinateTick: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var permissionDenied: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        isAuthorized = manager.authorizationStatus == .authorizedWhenInUse
                   || manager.authorizationStatus == .authorizedAlways
    }

    func requestAndFetch() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        Task { @MainActor in
            self.isAuthorized = (auth == .authorizedWhenInUse || auth == .authorizedAlways)
            if self.isAuthorized { manager.requestLocation() }
            if auth == .denied || auth == .restricted { self.permissionDenied = true }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let c = loc.coordinate
        Task { @MainActor in
            self.coordinate = c
            self.coordinateTick &+= 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — UI still works, user just doesn't get distance sort.
    }
}

// Tick 432 — Relative date for the stores-manifest scraped_at stamp.
// Mirrors `_relativeDate` in js/store-locator.js (tick 428) +
// `relativeStoreDate` in Android PurchaseScreen (tick 431).
// "today" / "Nd ago" / "Nw ago" within 5 weeks; "Nmo ago" beyond.
// Falls back to the raw ISO prefix when parse fails.
fileprivate func relativeStoreDate(_ iso: String) -> String {
    let datePart = String(iso.prefix(10))
    let parts = datePart.split(separator: "-").map(String.init)
    guard parts.count == 3,
          let y = Int(parts[0]),
          let m = Int(parts[1]),
          let d = Int(parts[2]) else { return datePart }
    var comps = DateComponents()
    comps.year = y; comps.month = m; comps.day = d
    guard let date = Calendar.current.date(from: comps) else { return datePart }
    let days = Int((Date().timeIntervalSince(date)) / 86_400)
    switch days {
    case ..<0:    return datePart
    case 0:       return "today"
    case 1..<7:   return "\(days)d ago"
    case 7..<35:  return "\(days / 7)w ago"
    default:      return "\(days / 30)mo ago"
    }
}
