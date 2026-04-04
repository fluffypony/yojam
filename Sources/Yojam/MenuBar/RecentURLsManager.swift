import Foundation

@MainActor
final class RecentURLsManager {
    private let maxRecents = 10
    private(set) var recentURLs: [URL] = []

    init() {
        if let strings = UserDefaults.standard.stringArray(
            forKey: "recentURLs"
        ) {
            recentURLs = strings.compactMap { URL(string: $0) }
        }
    }

    func add(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > maxRecents {
            recentURLs = Array(recentURLs.prefix(maxRecents))
        }
        UserDefaults.standard.set(
            recentURLs.map(\.absoluteString), forKey: "recentURLs")
    }
}
