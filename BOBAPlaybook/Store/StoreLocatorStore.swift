import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class StoreLocatorStore {
    var stores: [StoreLocation] = []
    var filtered: [StoreLocation] = []
    var searchText: String = "" { didSet { applyFilter() } }
    var selectedState: String = "" { didSet { applyFilter() } }
    /// Big-box retailers (Target, DICK'S, etc.) are hidden by default so
    /// the independent hobby shops — the stores most likely to care
    /// about BOBA — aren't buried by ~1,800 national-chain rows.
    var includeBigBox: Bool = false { didSet { applyFilter() } }
    var userLocation: CLLocationCoordinate2D? = nil { didSet { applyFilter() } }
    var loadState: LoadState = .idle
    var lastUpdatedLabel: String? = nil

    /// Count of big-box stores that would be added if `includeBigBox`
    /// flipped on. Used by the UI to tell coaches "X big-box hidden" so
    /// they know the toggle exists.
    var hiddenBigBoxCount: Int {
        stores.filter { $0.isBigBox }.count
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let service = StoreLocatorService()

    /// State codes present in the snapshot, sorted. "" means "All".
    var availableStates: [String] {
        let all = Set(stores.map(\.address.stateShort)).subtracting([""])
        return Array(all).sorted()
    }

    func load() async {
        loadState = .loading
        do {
            stores = try await service.loadStores()
            lastUpdatedLabel = await service.cachedScrapedAt()
            applyFilter()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        loadState = .loading
        do {
            stores = try await service.refresh()
            lastUpdatedLabel = await service.cachedScrapedAt()
            applyFilter()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func applyFilter() {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        var rows = stores.filter { s in
            if !includeBigBox && s.isBigBox                                    { return false }
            if !selectedState.isEmpty, s.address.stateShort != selectedState   { return false }
            if q.isEmpty { return true }
            return s.name.lowercased().contains(q)
                || s.address.city.lowercased().contains(q)
                || s.address.street.lowercased().contains(q)
                || s.address.postCode.lowercased().contains(q)
        }
        if let origin = userLocation {
            let o = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            rows.sort { a, b in
                let da = CLLocation(latitude: a.location.lat, longitude: a.location.lng).distance(from: o)
                let db = CLLocation(latitude: b.location.lat, longitude: b.location.lng).distance(from: o)
                return da < db
            }
        } else {
            rows.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        filtered = rows
    }

    /// Meters → human-readable "3.2 mi" / "450 ft". Returns empty string
    /// when we don't have a user location.
    func distanceLabel(to store: StoreLocation) -> String {
        guard let origin = userLocation else { return "" }
        let s = CLLocation(latitude: store.location.lat, longitude: store.location.lng)
        let o = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let meters = s.distance(from: o)
        let miles = meters / 1609.344
        if miles < 0.1 {
            let feet = Int(meters * 3.28084)
            return "\(feet) ft"
        }
        if miles < 10 { return String(format: "%.1f mi", miles) }
        return "\(Int(miles.rounded())) mi"
    }
}
