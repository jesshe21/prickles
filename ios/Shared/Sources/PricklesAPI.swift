import Foundation

enum PricklesAPI {
    static let statusURL = URL(string: "https://jessica-he.com/prickles/status.json")!
    static let historyURL = URL(string: "https://jessica-he.com/prickles/history.json")!

    static let appGroupID = "group.com.jessica-he.prickles"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static let statusCacheKey = "cached_status"
    private static let historyCacheKey = "cached_history"

    static let staleThreshold: TimeInterval = 30 * 60

    static func fetchStatus() async throws -> PricklesStatus {
        let data = try await fetch(url: statusURL)
        let status = try PricklesJSON.decoder.decode(PricklesStatus.self, from: data)
        cacheStatus(data: data)
        return status
    }

    static func fetchHistory() async throws -> PricklesHistory {
        let data = try await fetch(url: historyURL)
        let history = try PricklesJSON.decoder.decode(PricklesHistory.self, from: data)
        cacheHistory(data: data)
        return history
    }

    /// Fetches with a minute-granular cache-busting query param. The webpage does
    /// the same because Cloudflare + GitHub Pages edge-cache the JSON for up to
    /// 10 minutes, which defeats our "30-minute stale" threshold on fresh data.
    private static func fetch(url: URL) async throws -> Data {
        let bust = Int(Date().timeIntervalSince1970 / 60)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "t", value: String(bust))]
        var request = URLRequest(url: comps.url ?? url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Cache

    static func cacheStatus(data: Data) {
        sharedDefaults?.set(data, forKey: statusCacheKey)
    }

    static func cacheHistory(data: Data) {
        sharedDefaults?.set(data, forKey: historyCacheKey)
    }

    static func cachedStatus() -> PricklesStatus? {
        guard let data = sharedDefaults?.data(forKey: statusCacheKey) else { return nil }
        return try? PricklesJSON.decoder.decode(PricklesStatus.self, from: data)
    }

    static func cachedHistory() -> PricklesHistory? {
        guard let data = sharedDefaults?.data(forKey: historyCacheKey) else { return nil }
        return try? PricklesJSON.decoder.decode(PricklesHistory.self, from: data)
    }

    /// Returns a cached status immediately if available, else falls back to placeholder.
    static func statusOrPlaceholder() -> PricklesStatus {
        cachedStatus() ?? PricklesStatus.placeholderGood
    }

    static func historyOrPlaceholder() -> PricklesHistory {
        cachedHistory() ?? PricklesHistory.placeholder
    }
}

extension PricklesStatus {
    var isStale: Bool {
        guard let lastChecked else { return true }
        return Date().timeIntervalSince(lastChecked) > PricklesAPI.staleThreshold
    }
}
