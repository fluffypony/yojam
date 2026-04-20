import Foundation
import YojamCore

struct BrowserProfile: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var email: String?
    var browserBundleId: String
    var isDefault: Bool = false
}

final class ProfileDiscovery: Sendable {
    private let chromiumReader = ChromiumProfileReader()
    private let firefoxReader = FirefoxProfileReader()

    func discoverProfiles(for bundleId: String) -> [BrowserProfile] {
        switch bundleId {
        case "com.google.Chrome":
            return chromiumReader.readProfiles(
                appSupportPath: "Google/Chrome", bundleId: bundleId)
        case "com.brave.Browser":
            return chromiumReader.readProfiles(
                appSupportPath: "BraveSoftware/Brave-Browser", bundleId: bundleId)
        case "com.microsoft.edgemac":
            return chromiumReader.readProfiles(
                appSupportPath: "Microsoft Edge", bundleId: bundleId)
        case "com.vivaldi.Vivaldi":
            return chromiumReader.readProfiles(
                appSupportPath: "Vivaldi", bundleId: bundleId)
        case "com.operasoftware.Opera":
            return chromiumReader.readProfiles(
                appSupportPath: "com.operasoftware.Opera", bundleId: bundleId)
        case "org.chromium.Chromium":
            return chromiumReader.readProfiles(
                appSupportPath: "Chromium", bundleId: bundleId)
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly":
            return firefoxReader.readProfiles(bundleId: bundleId)
        case "com.apple.Safari":
            return readSafariProfiles(bundleId: bundleId)
        case "com.kagi.kagimacOS":
            // Orion profile discovery: Kagi does not currently publish a
            // stable per-profile launch surface. Users who want per-profile
            // routing should add Orion as a custom app with custom launch
            // args pointing at the profile-specific launch command.
            return []
        // Arc profile discovery remains disabled: launch args not supported.
        default:
            return []
        }
    }

    /// Read Safari profiles registered by the Yojam Safari extension.
    /// Each profile where the extension runs self-registers its profile UUID
    /// into shared App Group defaults under "safariProfileRegistry".
    private func readSafariProfiles(bundleId: String) -> [BrowserProfile] {
        guard let defaults = UserDefaults(suiteName: SharedRoutingStore.suiteName) else { return [] }
        guard let registry = defaults.dictionary(forKey: "safariProfileRegistry") as? [String: String],
              !registry.isEmpty else { return [] }
        return registry.map { (uuid, name) in
            BrowserProfile(
                id: uuid,
                name: name,
                email: nil,
                browserBundleId: bundleId,
                isDefault: false)
        }.sorted { $0.name < $1.name }
    }
}
