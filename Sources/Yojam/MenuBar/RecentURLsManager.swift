import Foundation
import YojamCore

@MainActor
final class RecentURLsManager {
    private let maxRecents = 10
    private(set) var recentURLs: [URL] = []
    private var timestamps: [URL: Date] = [:]
    private var cleanupTimer: Timer?
    private let sharedDefaults: UserDefaults

    init() {
        self.sharedDefaults = SharedRoutingStore().defaults
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
        sharedDefaults.set(recentURLs.map(\.absoluteString),
                          forKey: SharedRoutingStore.Keys.recentURLs)
        let tsDict = Dictionary(uniqueKeysWithValues: timestamps.map {
            ($0.key.absoluteString, $0.value.timeIntervalSince1970)
        })
        sharedDefaults.set(tsDict, forKey: SharedRoutingStore.Keys.recentURLTimestamps)
    }

    private func loadFromDefaults() {
        if let strings = sharedDefaults.stringArray(
            forKey: SharedRoutingStore.Keys.recentURLs) {
            recentURLs = strings.compactMap { URL(string: $0) }
        }
        if let tsDict = sharedDefaults.dictionary(
            forKey: SharedRoutingStore.Keys.recentURLTimestamps) as? [String: TimeInterval] {
            for (urlStr, ts) in tsDict {
                if let url = URL(string: urlStr) {
                    timestamps[url] = Date(timeIntervalSince1970: ts)
                }
            }
        }
    }
}
