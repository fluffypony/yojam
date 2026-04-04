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
            // Firefox: -P expects profile name, -profile expects path
            return ["-P", profileId]
        case "company.thebrowser.Browser":
            // Arc requires AppleScript or URL scheme for space switching, not CLI args
            return []
        case "com.kagi.kagimacOS":
            // Orion does not support profile switching via CLI args
            return []
        default:
            return []
        }
    }

    static func privateWindowArguments(browserBundleId: String) -> [String] {
        switch browserBundleId {
        case "com.google.Chrome", "com.brave.Browser", "org.chromium.Chromium":
            return ["--incognito"]
        case "com.microsoft.edgemac":
            return ["--inprivate"]
        case "org.mozilla.firefox":
            return ["-private-window"]
        case "com.vivaldi.Vivaldi":
            return ["--incognito"]
        default:
            return []
        }
    }
}
