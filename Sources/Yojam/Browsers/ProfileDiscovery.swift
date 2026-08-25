import Foundation
import YojamCore

struct BrowserProfile: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var email: String?
    var browserBundleId: String
    var isDefault: Bool = false
}

enum BrowserProfileEngine: Equatable, Sendable {
    case chromium
    case firefox
}

struct BrowserProfileConfiguration: Equatable, Sendable {
    let engine: BrowserProfileEngine
    let appSupportPath: String
}

enum BrowserProfileCatalog {
    private static let configurations: [String: BrowserProfileConfiguration] = [
        // Finicky 4 browsers.json.
        "com.brave.browser": .init(
            engine: .chromium,
            appSupportPath: "BraveSoftware/Brave-Browser"),
        "com.google.chrome": .init(
            engine: .chromium,
            appSupportPath: "Google/Chrome"),
        "com.google.chrome.beta": .init(
            engine: .chromium,
            appSupportPath: "Google/Chrome Beta"),
        "com.google.chrome.canary": .init(
            engine: .chromium,
            appSupportPath: "Google/Chrome Canary"),
        "org.chromium.chromium": .init(
            engine: .chromium,
            appSupportPath: "Chromium"),
        "com.microsoft.edgemac": .init(
            engine: .chromium,
            appSupportPath: "Microsoft Edge"),
        "com.vivaldi.vivaldi": .init(
            engine: .chromium,
            appSupportPath: "Vivaldi"),
        "com.bookry.wavebox": .init(
            engine: .chromium,
            appSupportPath: "WaveboxApp"),
        "net.imput.helium": .init(
            engine: .chromium,
            appSupportPath: "net.imput.helium"),
        "ai.perplexity.comet": .init(
            engine: .chromium,
            appSupportPath: "Comet"),
        "ru.yandex.desktop.yandex-browser": .init(
            engine: .chromium,
            appSupportPath: "Yandex/YandexBrowser"),
        "com.operasoftware.opera": .init(
            engine: .chromium,
            appSupportPath: "com.operasoftware.Opera"),
        "com.operasoftware.operagx": .init(
            engine: .chromium,
            appSupportPath: "com.operasoftware.OperaGX"),
        "org.mozilla.firefox": .init(
            engine: .firefox,
            appSupportPath: "Firefox"),
        "org.mozilla.firefoxdeveloperedition": .init(
            engine: .firefox,
            appSupportPath: "Firefox"),
        "app.zen-browser.zen": .init(
            engine: .firefox,
            appSupportPath: "zen"),

        // Finicky 3.4 profile-capable channels not present above.
        "com.brave.browser.beta": .init(
            engine: .chromium,
            appSupportPath: "BraveSoftware/Brave-Browser-Beta"),
        "com.brave.browser.dev": .init(
            engine: .chromium,
            appSupportPath: "BraveSoftware/Brave-Browser-Dev"),
        "com.microsoft.edgemac.beta": .init(
            engine: .chromium,
            appSupportPath: "Microsoft Edge Beta"),

        // Keep Yojam's existing Firefox Nightly support.
        "org.mozilla.nightly": .init(
            engine: .firefox,
            appSupportPath: "Firefox Nightly"),
    ]

    static func configuration(
        for bundleIdentifier: String
    ) -> BrowserProfileConfiguration? {
        configurations[bundleIdentifier.lowercased()]
    }
}

final class ProfileDiscovery: Sendable {
    private let chromiumReader: ChromiumProfileReader
    private let firefoxReader: FirefoxProfileReader

    init(
        applicationSupportDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
    ) {
        chromiumReader = ChromiumProfileReader(
            applicationSupportDirectory: applicationSupportDirectory)
        firefoxReader = FirefoxProfileReader(
            applicationSupportDirectory: applicationSupportDirectory)
    }

    func discoverProfiles(
        for bundleId: String,
        userDataDirectory: String? = nil
    ) -> [BrowserProfile] {
        if let configuration = BrowserProfileCatalog.configuration(for: bundleId) {
            switch configuration.engine {
            case .chromium:
                return chromiumReader.readProfiles(
                    appSupportPath: configuration.appSupportPath,
                    bundleId: bundleId,
                    userDataDirectory: userDataDirectory)
            case .firefox:
                return firefoxReader.readProfiles(
                    appSupportPath: configuration.appSupportPath,
                    bundleId: bundleId)
            }
        }

        switch bundleId {
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
