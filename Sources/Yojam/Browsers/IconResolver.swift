import AppKit

final class IconResolver: @unchecked Sendable {
    private var cache: [String: (image: NSImage, modDate: Date)] = [:]
    private let queue = DispatchQueue(label: "com.yojam.iconresolver")

    func icon(forBundleIdentifier bundleId: String) -> NSImage {
        if let cached = queue.sync(execute: { cache[bundleId] }) {
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId
            ) {
                let modDate = (try? FileManager.default.attributesOfItem(
                    atPath: appURL.path
                )[.modificationDate] as? Date) ?? Date.distantPast
                if modDate <= cached.modDate { return cached.image }
            } else {
                return cached.image
            }
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
