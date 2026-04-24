import Foundation

/// Fetches the authorized-retailer list. Load order:
///   1. Cached remote copy (cachesDirectory)
///   2. Fresh remote fetch (manifest-sha256 check to skip full download
///      when unchanged; full download when the sha has moved)
///   3. Bundled seed (`stores-seed.json` + `stores-manifest-seed.json`)
///
/// The bundled seed guarantees the feature works offline and on first
/// launch, even before GitHub Pages has been published. Remote fetches
/// always trump when they succeed.
actor StoreLocatorService {
    private let manifestURL = URL(string: "https://bobaplaybook.com/assets/data/stores-manifest.json")!
    private let storesURL   = URL(string: "https://bobaplaybook.com/assets/data/stores.json")!
    private let cacheDir    = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

    private var localManifestURL: URL { cacheDir.appendingPathComponent("stores-manifest.json") }
    private var localStoresURL:   URL { cacheDir.appendingPathComponent("stores.json") }

    struct Manifest: Codable {
        let stores_sha256: String
        let stores_count: Int
        let scraped_at: String
    }

    enum LoadError: LocalizedError {
        case noData
        var errorDescription: String? { "No store data available." }
    }

    /// Returns the current stores list. Tries remote (manifest-sha256
    /// refresh) → cache → bundled seed, in that order. Only throws when
    /// every path fails, which in practice means the bundle is corrupt.
    func loadStores() async throws -> [StoreLocation] {
        if let remote = try? await fetchRemote() {
            return remote
        }
        if let cached = loadLocalCache() {
            return cached
        }
        if let seed = loadBundledSeed() {
            return seed
        }
        throw LoadError.noData
    }

    /// Pull-to-refresh: drop the local manifest so the next load always
    /// re-downloads stores.json, then route back through the normal
    /// load order (remote → cache → seed).
    func refresh() async throws -> [StoreLocation] {
        try? FileManager.default.removeItem(at: localManifestURL)
        return try await loadStores()
    }

    /// Best-effort "scraped_at" for the UI's freshness line. Prefers the
    /// cached manifest, falls back to the bundled manifest.
    func cachedScrapedAt() -> String? {
        if let data = try? Data(contentsOf: localManifestURL),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return m.scraped_at
        }
        if let url = Bundle.main.url(forResource: "stores-manifest-seed", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return m.scraped_at
        }
        return nil
    }

    // MARK: - Paths

    private func fetchRemote() async throws -> [StoreLocation] {
        let localManifest: Manifest? = (try? Data(contentsOf: localManifestURL))
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }

        let (manifestData, manifestResp) = try await URLSession.shared.data(from: manifestURL)
        guard let http = manifestResp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let remoteManifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        // Remote unchanged — prefer any cache, else fall through to full fetch
        if remoteManifest.stores_sha256 == localManifest?.stores_sha256,
           let localData = try? Data(contentsOf: localStoresURL),
           let decoded = try? JSONDecoder().decode([StoreLocation].self, from: localData) {
            return decoded
        }

        let (storesData, storesResp) = try await URLSession.shared.data(from: storesURL)
        guard let http2 = storesResp as? HTTPURLResponse, http2.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([StoreLocation].self, from: storesData)
        try? storesData.write(to: localStoresURL, options: .atomic)
        try? manifestData.write(to: localManifestURL, options: .atomic)
        return decoded
    }

    private func loadLocalCache() -> [StoreLocation]? {
        guard let data = try? Data(contentsOf: localStoresURL) else { return nil }
        return try? JSONDecoder().decode([StoreLocation].self, from: data)
    }

    private func loadBundledSeed() -> [StoreLocation]? {
        guard let url = Bundle.main.url(forResource: "stores-seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([StoreLocation].self, from: data)
    }
}
