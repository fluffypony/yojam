import Foundation

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
        // Arc and Orion profile discovery disabled: launch args not supported
        default:
            return []
        }
    }
}
