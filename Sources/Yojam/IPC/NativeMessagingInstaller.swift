import Foundation

/// Installs native messaging host manifests for Chrome, Firefox, and
/// Chromium-based browsers so the Yojam browser extension can communicate
/// with the main app without triggering the protocol-handler prompt.
///
/// Called from `applicationDidFinishLaunching` and from the
/// "Reinstall Browser Helpers" button in Preferences > Integrations.
enum NativeMessagingInstaller {
    static let hostName = "org.yojam.host"

    /// All Chromium-based browser manifest directories.
    private static let chromiumPaths: [(name: String, relativePath: String)] = [
        ("Chrome",   "Google/Chrome/NativeMessagingHosts"),
        ("Brave",    "BraveSoftware/Brave-Browser/NativeMessagingHosts"),
        ("Edge",     "Microsoft Edge/NativeMessagingHosts"),
        ("Vivaldi",  "Vivaldi/NativeMessagingHosts"),
        ("Chromium", "Chromium/NativeMessagingHosts"),
        ("Arc",      "Arc/User Data/NativeMessagingHosts"),
    ]

    private static let firefoxPath = "Mozilla/NativeMessagingHosts"

    /// Install manifests for all supported browsers.
    /// Call from the main thread (accesses Bundle.main).
    @MainActor
    static func installAll() {
        guard let hostPath = resolveHostPath() else {
            YojamLogger.shared.log("Cannot locate YojamNativeHost binary in app bundle")
            return
        }

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        // Chrome / Chromium-based
        for (name, relPath) in chromiumPaths {
            let dir = appSupport.appendingPathComponent(relPath)
            installChromiumManifest(at: dir, hostPath: hostPath, browserName: name)
        }

        // Firefox
        let firefoxDir = appSupport.appendingPathComponent(firefoxPath)
        installFirefoxManifest(at: firefoxDir, hostPath: hostPath)
    }

    /// Check if at least one native messaging manifest is installed.
    static func isAnyManifestInstalled() -> Bool {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        for (_, relPath) in chromiumPaths {
            let manifest = appSupport
                .appendingPathComponent(relPath)
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

    /// Stable extension ID derived from the "key" field in chrome/manifest.json.
    /// Set this to the real ID once the extension is published to the Chrome Web Store,
    /// or use the unpacked extension ID during development. The extension's native
    /// messaging will fail silently until this is a real Chrome extension ID.
    static let chromeExtensionId = "placeholder_extension_id"

    private static func installChromiumManifest(
        at directory: URL, hostPath: String, browserName: String
    ) {
        if chromeExtensionId == "placeholder_extension_id" {
            YojamLogger.shared.log(
                "WARNING: Chrome native messaging uses placeholder extension ID — "
                + "sendNativeMessage will be rejected by Chrome. Update NativeMessagingInstaller.chromeExtensionId.")
        }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Yojam browser picker - routes links to the right browser",
            "path": hostPath,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(chromeExtensionId)/"
            ]
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
                "yojam@yojam.org"
            ]
        ]
        writeManifest(manifest, to: directory, browserName: "Firefox")
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
