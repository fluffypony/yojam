import AppKit

final class IconResolver: @unchecked Sendable {
    // §36: Shared singleton to avoid duplicate icon caches
    static let shared = IconResolver()

    private var cache: [String: (image: NSImage, modDate: Date)] = [:]
    private let queue = DispatchQueue(label: "com.yojam.iconresolver")

    func icon(forBundleIdentifier bundleId: String) -> NSImage {
        // §31: Trust the cache on hit — AppInstallMonitor calls invalidateCache when apps update
        if let cached = queue.sync(execute: { cache[bundleId] }) {
            return cached.image
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId
        ) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        let modDate = (try? FileManager.default.attributesOfItem(
            atPath: appURL.path
        )[.modificationDate] as? Date) ?? Date()
        queue.sync { _ = cache.updateValue((icon, modDate), forKey: bundleId) }
        return icon
    }

    func invalidateCache(for bundleId: String) {
        queue.sync { _ = cache.removeValue(forKey: bundleId) }
    }
}
