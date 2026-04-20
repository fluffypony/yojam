import Foundation
import AppKit

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

    // MARK: - Public API

    /// Reconcile manifests against actually-installed browsers. Installs
    /// manifests for browsers that are present, removes stale manifests for
    /// browsers that are not.
    @MainActor
    static func reconcileInstalled() {
        guard let hostPath = resolveHostPath() else {
            YojamLogger.shared.log("Cannot locate YojamNativeHost binary in app bundle")
            return
        }

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        // Chromium-based
        for entry in chromiumPaths {
            let dir = appSupport.appendingPathComponent(entry.relativePath)
            let installed = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: entry.bundleId) != nil
            if installed {
                installChromiumManifest(at: dir, hostPath: hostPath, browserName: entry.name)
                YojamLogger.shared.log("Installed native host manifest for \(entry.name)")
            } else {
                removeManifest(at: dir)
            }
        }

        // Firefox
        let firefoxInstalled = firefoxBundleIds.contains { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }
        let firefoxDir = appSupport.appendingPathComponent(firefoxPath)
        if firefoxInstalled {
            installFirefoxManifest(at: firefoxDir, hostPath: hostPath)
        } else {
            removeManifest(at: firefoxDir)
        }
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

    /// Backwards-compatible alias used by older call sites. Prefer reconcileInstalled().
    @MainActor
    static func installAll() { reconcileInstalled() }

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
    /// 3. Empty (manifest installation will be skipped with a clear log)
    static func resolveChromeExtensionIds() -> [String] {
        if let env = ProcessInfo.processInfo.environment["YOJAM_CHROME_EXTENSION_IDS"], !env.isEmpty {
            return env.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let url = Bundle.main.url(forResource: "chrome-extension-ids", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids.filter { !$0.isEmpty }
        }
        return []
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

    private static func installChromiumManifest(
        at directory: URL, hostPath: String, browserName: String
    ) {
        let extensionIds = resolveChromeExtensionIds()
        guard !extensionIds.isEmpty else {
            YojamLogger.shared.log(
                "Skipping \(browserName) native host manifest install: no Chrome extension IDs configured "
                + "(set YOJAM_CHROME_EXTENSION_IDS or bundle chrome-extension-ids.json).")
            removeManifest(at: directory)
            return
        }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Yojam browser picker - routes links to the right browser",
            "path": hostPath,
            "type": "stdio",
            "allowed_origins": extensionIds.map { "chrome-extension://\($0)/" }
        ]
        writeManifest(manifest, to: directory, browserName: browserName)
    }

    private static func installFirefoxManifest(
        at directory: URL, hostPath: String
    ) {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Yojam browser picker - routes links to the right browser",
            "path": hostPath,
            "type": "stdio",
            "allowed_extensions": [
                "yojam@yoj.am"
            ]
        ]
        writeManifest(manifest, to: directory, browserName: "Firefox")
    }

    private static func removeManifest(at directory: URL) {
        let filePath = directory.appendingPathComponent("\(hostName).json")
        if FileManager.default.fileExists(atPath: filePath.path) {
            try? FileManager.default.removeItem(at: filePath)
        }
    }

    private static func writeManifest(
        _ manifest: [String: Any], to directory: URL, browserName: String
    ) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let filePath = directory.appendingPathComponent("\(hostName).json")
            let data = try JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: filePath, options: .atomic)
        } catch {
            YojamLogger.shared.log(
                "Failed to install native messaging manifest for \(browserName): \(error.localizedDescription)")
        }
    }
}
