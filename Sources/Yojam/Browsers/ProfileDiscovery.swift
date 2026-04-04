import Foundation

struct BrowserProfile: Identifiable, Codable {
    let id: String
    var name: String
    var email: String?
    var browserBundleId: String
}

@MainActor
final class ProfileDiscovery {
    private let chromiumReader = ChromiumProfileReader()
    private let firefoxReader = FirefoxProfileReader()
    private let arcReader = ArcProfileReader()
    private let orionReader = OrionProfileReader()

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
        case "org.mozilla.firefox":
            return firefoxReader.readProfiles(bundleId: bundleId)
        case "company.thebrowser.Browser":
            return arcReader.readProfiles(bundleId: bundleId)
        case "com.kagi.kagimacOS":
            return orionReader.readProfiles(bundleId: bundleId)
        default:
            return []
        }
    }
}
