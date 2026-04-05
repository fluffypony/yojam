import Foundation

@MainActor
final class RecentURLsManager {
    private let maxRecents = 10
    private(set) var recentURLs: [URL] = []
    private var timestamps: [URL: Date] = [:]
    private var cleanupTimer: Timer?

    init() {
        loadFromDefaults()
    }

    func configure(retention: RecentURLRetention, retentionMinutes: Int) {
        cleanupTimer?.invalidate()
        cleanupTimer = nil

        if retention == .never {
            recentURLs = []
            timestamps = [:]
            saveToDefaults()
        } else if retention == .timed {
            purgeExpired(minutes: retentionMinutes)
            // Poll every 60s to clean up expired entries
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.purgeExpired(minutes: retentionMinutes)
                }
            }
        }
    }

    func add(_ url: URL, retention: RecentURLRetention) {
        guard retention != .never else { return }
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        timestamps[url] = Date()
        if recentURLs.count > maxRecents {
            let removed = recentURLs.suffix(from: maxRecents)
            for r in removed { timestamps.removeValue(forKey: r) }
            recentURLs = Array(recentURLs.prefix(maxRecents))
        }
        saveToDefaults()
    }

    func clear() {
        recentURLs = []
        timestamps = [:]
        saveToDefaults()
    }

    private func purgeExpired(minutes: Int) {
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        let before = recentURLs.count
        recentURLs.removeAll { url in
            guard let ts = timestamps[url] else { return true }
            return ts < cutoff
        }
        // Clean up orphan timestamps
        let urlSet = Set(recentURLs)
        timestamps = timestamps.filter { urlSet.contains($0.key) }
        if recentURLs.count != before {
            saveToDefaults()
        }
    }

    // MARK: - Persistence

    private func saveToDefaults() {
        let d = UserDefaults.standard
        d.set(recentURLs.map(\.absoluteString), forKey: "recentURLs")
        let tsDict = Dictionary(uniqueKeysWithValues: timestamps.map {
            ($0.key.absoluteString, $0.value.timeIntervalSince1970)
        })
        d.set(tsDict, forKey: "recentURLTimestamps")
    }

    private func loadFromDefaults() {
        let d = UserDefaults.standard
        if let strings = d.stringArray(forKey: "recentURLs") {
            recentURLs = strings.compactMap { URL(string: $0) }
        }
        if let tsDict = d.dictionary(forKey: "recentURLTimestamps") as? [String: TimeInterval] {
            for (urlStr, ts) in tsDict {
                if let url = URL(string: urlStr) {
                    timestamps[url] = Date(timeIntervalSince1970: ts)
                }
            }
        }
    }
}
