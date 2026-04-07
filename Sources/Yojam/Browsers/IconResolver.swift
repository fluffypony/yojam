import AppKit

final class IconResolver: @unchecked Sendable {
    // §36: Shared singleton to avoid duplicate icon caches
    static let shared = IconResolver()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    func icon(forBundleIdentifier bundleId: String) -> NSImage {
        let key = bundleId as NSString
        // §31: Trust the cache on hit — AppInstallMonitor calls invalidateCache when apps update
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId
        ) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        // Copy before mutating to avoid mutating the shared NSImage from NSWorkspace
        let iconCopy = icon.copy() as! NSImage
        iconCopy.size = NSSize(width: 64, height: 64)
        cache.setObject(iconCopy, forKey: key)
        return iconCopy
    }

    func invalidateCache(for bundleId: String) {
        cache.removeObject(forKey: bundleId as NSString)
    }
}
