import Foundation

enum ProfileLaunchHelper {
    static func launchArguments(
        forProfile profileId: String, browserBundleId: String
    ) -> [String] {
        switch browserBundleId {
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
             "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium":
            return ["--profile-directory=\(profileId)"]
        case "org.mozilla.firefox":
            // Firefox: -P expects profile name
            return ["-P", profileId]
        default:
            return []
        }
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
        case "org.mozilla.firefox":
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
    }

    /// Open a URL in a private window via AppleScript GUI scripting.
    /// Requires Accessibility permissions. Used for Safari and Orion
    /// which have no CLI flags for private browsing.
    /// Returns true if the script executed successfully, false otherwise.
    @discardableResult
    static func openPrivateWindowViaAppleScript(
        url: URL, appName: String
    ) -> Bool {
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
