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
    }

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
}
