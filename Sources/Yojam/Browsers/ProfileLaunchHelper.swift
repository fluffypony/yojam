import Foundation

enum ProfileLaunchHelper {
    static func launchArguments(
        forProfile profileId: String,
        browserBundleId: String,
        userDataDirectory: String? = nil,
        firefoxProfileReader: FirefoxProfileReader = FirefoxProfileReader()
    ) -> [String] {
        guard let configuration = BrowserProfileCatalog.configuration(
            for: browserBundleId) else { return [] }
        switch configuration.engine {
        case .chromium:
            return dataDirectoryArguments(
                userDataDirectory: userDataDirectory,
                browserBundleId: browserBundleId)
                + ["--profile-directory=\(profileId)"]
        case .firefox:
            if isFirefoxProfilePath(profileId) {
                return ["--profile", expandedProfilePath(profileId), "--new-instance"]
            }
            if let profilePath = firefoxProfileReader.selectableProfilePath(
                named: profileId,
                appSupportPath: configuration.appSupportPath,
                bundleId: browserBundleId) {
                return ["--profile", profilePath, "--new-instance"]
            }
            // Firefox profile locks reject a forced new instance when the
            // profile is already open. -P lets Firefox reuse that profile.
            return ["-P", profileId]
        }
    }

    static func dataDirectoryArguments(
        userDataDirectory: String?,
        browserBundleId: String
    ) -> [String] {
        guard BrowserProfileCatalog.configuration(for: browserBundleId)?.engine == .chromium,
              let userDataDirectory,
              !userDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return ["--user-data-dir=\(expandedProfilePath(userDataDirectory))"]
    }

    static func supportsUserDataDirectory(browserBundleId: String) -> Bool {
        BrowserProfileCatalog.configuration(for: browserBundleId)?.engine == .chromium
    }

    private static func isFirefoxProfilePath(_ profileId: String) -> Bool {
        let expanded = expandedProfilePath(profileId)
        return expanded.hasPrefix("/")
    }

    private static func expandedProfilePath(_ profileId: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if profileId == "~" { return home }
        if profileId.hasPrefix("~/") {
            return home + String(profileId.dropFirst())
        }
        if profileId.hasPrefix("$HOME/") {
            return home + String(profileId.dropFirst("$HOME".count))
        }
        return profileId
    }

    static func supportsPrivateWindow(browserBundleId: String) -> Bool {
        !privateWindowArguments(browserBundleId: browserBundleId).isEmpty
            || appleScriptPrivateWindowApps.contains(browserBundleId)
    }

    /// Browsers that need AppleScript GUI scripting for private windows
    /// (no CLI flag available).
    static let appleScriptPrivateWindowApps: Set<String> = [
        "com.apple.Safari",
        "com.kagi.kagimacOS",       // Orion
    ]

    static func privateWindowArguments(browserBundleId: String) -> [String] {
        switch browserBundleId {
        case "com.google.Chrome", "com.brave.Browser", "org.chromium.Chromium",
             "com.operasoftware.Opera", "com.vivaldi.Vivaldi":
            return ["--incognito"]
        case "com.microsoft.edgemac":
            return ["--inprivate"]
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly":
            return ["-private-window"]
        default:
            return []
        }
    }

    /// Escape a string for safe interpolation into an AppleScript string literal.
    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "")
         .replacingOccurrences(of: "\r", with: "")
         .replacingOccurrences(of: "\t", with: "")
         .replacingOccurrences(of: "\u{2028}", with: "%E2%80%A8")
         .replacingOccurrences(of: "\u{2029}", with: "%E2%80%A9")
    }

    /// Open a URL in a private window via AppleScript GUI scripting.
    /// Requires Accessibility permissions. Used for Safari and Orion
    /// which have no CLI flags for private browsing.
    /// Returns true if the script executed successfully, false otherwise.
    ///
    /// WARNING: Uses hard-coded English menu item "New Private Window".
    /// On non-English systems, the click may fail silently.
    @discardableResult
    static func openPrivateWindowViaAppleScript(
        url: URL, appName: String
    ) -> Bool {
        // Warn once if the system language isn't English
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if lang != "en" {
            struct Once { nonisolated(unsafe) static var warned = false }
            if !Once.warned {
                Once.warned = true
                YojamLogger.shared.log(
                    "AppleScript private window: system language is '\(lang)' — "
                    + "\"New Private Window\" menu item may not be found. "
                    + "Safari/Orion private mode may fall back to a normal window.")
            }
        }
        let escapedURL = escapeForAppleScript(url.absoluteString)
        let escapedAppName = escapeForAppleScript(appName)
        let script = """
        tell application "\(escapedAppName)"
            activate
            tell application "System Events"
                click menu item "New Private Window" of menu "File" of menu bar 1 of application process "\(escapedAppName)"
            end tell
            delay 0.3
            tell window 1 to set URL of current tab to "\(escapedURL)"
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            YojamLogger.shared.log(
                "AppleScript private window failed (may be non-English locale): \(error)")
            return false
        }
        return true
    }

    /// Resolve the app name for AppleScript from a bundle ID.
    static func appName(forBundleId bundleId: String) -> String? {
        switch bundleId {
        case "com.apple.Safari": return "Safari"
        case "com.kagi.kagimacOS": return "Orion"
        default: return nil
        }
    }
}
