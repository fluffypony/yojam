import Foundation
import AppKit
import CryptoKit

/// Installs native messaging host manifests for Chrome, Firefox, and
/// Chromium-based browsers so the Yojam browser extension can communicate
/// with the main app without triggering the protocol-handler prompt.
///
/// Called from `applicationDidFinishLaunching` and from the
/// "Reinstall Browser Helpers" button in Preferences > Integrations.
enum NativeMessagingInstaller {
    static let hostName = "org.yojam.host"

    /// All Chromium-based browser manifest directories + bundle IDs so we can
    /// reconcile manifests with actual installs (no stale files for uninstalled browsers).
    private static let chromiumPaths: [(name: String, relativePath: String, bundleId: String)] = [
        ("Chrome",   "Google/Chrome/NativeMessagingHosts",                  "com.google.Chrome"),
        ("Brave",    "BraveSoftware/Brave-Browser/NativeMessagingHosts",    "com.brave.Browser"),
        ("Edge",     "Microsoft Edge/NativeMessagingHosts",                 "com.microsoft.edgemac"),
        ("Vivaldi",  "Vivaldi/NativeMessagingHosts",                        "com.vivaldi.Vivaldi"),
        ("Chromium", "Chromium/NativeMessagingHosts",                       "org.chromium.Chromium"),
        ("Arc",      "Arc/User Data/NativeMessagingHosts",                  "company.thebrowser.Browser"),
    ]

    private static let firefoxPath = "Mozilla/NativeMessagingHosts"
    private static let firefoxBundleIds = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
    ]

    struct Configuration {
        let applicationSupportDirectory: URL
        let hostPath: String
        let chromeExtensionIds: [String]
        let installedBrowserBundleIds: Set<String>
    }

    struct Manifest {
        let browserName: String
        let fileURL: URL
        let contents: Data?
    }

    struct Plan {
        let manifests: [Manifest]

        /// Only desired content is read here. Browser directories can require
        /// TCC access, so leave them alone when this fingerprint is unchanged.
        var registrationKey: String {
            var hash = SHA256()
            for manifest in manifests {
                hash.update(data: Data(manifest.fileURL.path.utf8))
                hash.update(data: Data([0]))
                hash.update(data: manifest.contents ?? Data("absent".utf8))
                hash.update(data: Data([0]))
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    @MainActor
    struct FileAccess {
        var read: (URL) throws -> Data?
        var write: (Data, URL) throws -> Void
        var remove: (URL) throws -> Void

        static let live = FileAccess(
            read: { url in
                do { return try Data(contentsOf: url) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
            },
            write: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            },
            remove: { url in
                do { _ = try FileManager.default.attributesOfItem(atPath: url.path) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
                try FileManager.default.removeItem(at: url)
            })
    }

    // MARK: - Public API

    /// Reconcile when the desired manifests change. Explicit repair also
    /// checks for missing or altered files without rewriting matching content.
    @MainActor
    static func reconcileInstalled(settingsStore: SettingsStore, force: Bool = false) {
        guard let hostPath = resolveHostPath() else {
            YojamLogger.shared.log("Cannot locate YojamNativeHost binary in app bundle")
            return
        }

        let browserIds = chromiumPaths.map(\.bundleId) + firefoxBundleIds
        let installed = Set(browserIds.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        })
        let configuration = Configuration(
            applicationSupportDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support"),
            hostPath: hostPath,
            chromeExtensionIds: resolveChromeExtensionIds(),
            installedBrowserBundleIds: installed)
        do {
            reconcile(plan: try makePlan(configuration), settingsStore: settingsStore, force: force)
        } catch {
            YojamLogger.shared.log("Cannot prepare native messaging manifests: \(error.localizedDescription)")
        }
    }

    @MainActor
    @discardableResult
    static func reconcile(
        plan: Plan, settingsStore: SettingsStore, force: Bool = false,
        files: FileAccess = .live,
        log: (String) -> Void = { YojamLogger.shared.log($0) }
    ) -> Bool {
        let key = plan.registrationKey
        guard force || settingsStore.lastNativeMessagingRegistrationKey != key else { return true }
        var succeeded = true
        for manifest in plan.manifests {
            do {
                if let expected = manifest.contents {
                    if let existing = try files.read(manifest.fileURL),
                       manifestsMatch(existing, expected) { continue }
                    try files.write(expected, manifest.fileURL)
                    log("Installed native host manifest for \(manifest.browserName)")
                } else {
                    try files.remove(manifest.fileURL)
                }
            } catch {
                succeeded = false
                log(
                    "Cannot reconcile native host manifest for \(manifest.browserName): \(error.localizedDescription)")
            }
        }
        // A failed repair must remain retryable, even if its previous key
        // matched before the user explicitly asked to repair the files.
        settingsStore.lastNativeMessagingRegistrationKey = succeeded ? key : nil
        return succeeded
    }

    /// Remove all manifests managed by Yojam (used by Uninstall flow).
    static func removeAll() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        for entry in chromiumPaths {
            removeManifest(at: appSupport.appendingPathComponent(entry.relativePath))
        }
        removeManifest(at: appSupport.appendingPathComponent(firefoxPath))
    }

    /// Check if at least one native messaging manifest is installed.
    static func isAnyManifestInstalled() -> Bool {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        for entry in chromiumPaths {
            let manifest = appSupport
                .appendingPathComponent(entry.relativePath)
                .appendingPathComponent("\(hostName).json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return true
            }
        }

        let firefoxManifest = appSupport
            .appendingPathComponent(firefoxPath)
            .appendingPathComponent("\(hostName).json")
        return FileManager.default.fileExists(atPath: firefoxManifest.path)
    }

    /// Check if a specific browser's manifest exists.
    static func isManifestInstalled(for browser: String) -> Bool {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        if browser.lowercased() == "firefox" {
            let manifest = appSupport
                .appendingPathComponent(firefoxPath)
                .appendingPathComponent("\(hostName).json")
            return FileManager.default.fileExists(atPath: manifest.path)
        }

        if let entry = chromiumPaths.first(where: { $0.name.lowercased() == browser.lowercased() }) {
            let manifest = appSupport
                .appendingPathComponent(entry.relativePath)
                .appendingPathComponent("\(hostName).json")
            return FileManager.default.fileExists(atPath: manifest.path)
        }

        return false
    }

    /// Bundle ID for a well-known browser display name (used by reconciler + rule targeting).
    static func bundleIdForBrowserName(_ name: String) -> String {
        chromiumPaths.first(where: { $0.name == name })?.bundleId ?? ""
    }

    // MARK: - Extension ID resolution

    /// Resolves the list of Chrome extension IDs Yojam should allow for native
    /// messaging. Priority:
    /// 1. `YOJAM_CHROME_EXTENSION_IDS` environment variable (comma-separated)
    /// 2. `Contents/Resources/chrome-extension-ids.json` bundle resource (array of strings)
    /// 3. Empty (Chrome manifests are omitted until an ID is configured)
    static func resolveChromeExtensionIds() -> [String] {
        if let env = ProcessInfo.processInfo.environment["YOJAM_CHROME_EXTENSION_IDS"], !env.isEmpty {
            return canonicalExtensionIds(env.components(separatedBy: ","))
        }
        if let url = Bundle.main.url(forResource: "chrome-extension-ids", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return canonicalExtensionIds(ids)
        }
        return []
    }

    // MARK: - Desired manifests

    static func makePlan(_ configuration: Configuration) throws -> Plan {
        let extensionIds = canonicalExtensionIds(configuration.chromeExtensionIds)
        let chromiumManifest: [String: Any] = [
            "name": hostName,
            "description": "Yojam browser picker - routes links to the right browser",
            "path": configuration.hostPath,
            "type": "stdio",
            "allowed_origins": extensionIds.map { "chrome-extension://\($0)/" }
        ]
        let chromiumData = try JSONSerialization.data(
            withJSONObject: chromiumManifest, options: [.prettyPrinted, .sortedKeys])
        var manifests = chromiumPaths.map { entry in
            Manifest(
                browserName: entry.name,
                fileURL: configuration.applicationSupportDirectory
                    .appendingPathComponent(entry.relativePath).appendingPathComponent("\(hostName).json"),
                contents: !extensionIds.isEmpty && configuration.installedBrowserBundleIds.contains(entry.bundleId)
                    ? chromiumData : nil)
        }
        let firefoxManifest: [String: Any] = [
            "name": hostName,
            "description": "Yojam browser picker - routes links to the right browser",
            "path": configuration.hostPath,
            "type": "stdio",
            "allowed_extensions": [
                "yojam@yoj.am"
            ]
        ]
        let firefoxData = try JSONSerialization.data(
            withJSONObject: firefoxManifest, options: [.prettyPrinted, .sortedKeys])
        manifests.append(Manifest(
            browserName: "Firefox",
            fileURL: configuration.applicationSupportDirectory
                .appendingPathComponent(firefoxPath).appendingPathComponent("\(hostName).json"),
            contents: firefoxBundleIds.contains(where: configuration.installedBrowserBundleIds.contains)
                ? firefoxData : nil))
        return Plan(manifests: manifests)
    }

    // MARK: - Private

    private static func resolveHostPath() -> String? {
        let bundle = Bundle.main
        // xcodegen tool targets with `copy: destination: executables` go to
        // Contents/MacOS. Check multiple locations for robustness.
        let candidates = [
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/YojamNativeHost"),
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/YojamNativeHost"),
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/yojamnativehost"),
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        YojamLogger.shared.log(
            "YojamNativeHost not found in any expected location: \(candidates.map(\.path))")
        return nil
    }

    private static func canonicalExtensionIds(_ ids: [String]) -> [String] {
        Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
    }

    private static func manifestsMatch(_ existing: Data, _ expected: Data) -> Bool {
        if existing == expected { return true }
        guard let existingJSON = try? JSONSerialization.jsonObject(with: existing) as? NSDictionary,
              let expectedJSON = try? JSONSerialization.jsonObject(with: expected) as? NSDictionary else {
            return false
        }
        return existingJSON == expectedJSON
    }

    private static func removeManifest(at directory: URL) {
        let filePath = directory.appendingPathComponent("\(hostName).json")
        if FileManager.default.fileExists(atPath: filePath.path) {
            try? FileManager.default.removeItem(at: filePath)
        }
    }
}
