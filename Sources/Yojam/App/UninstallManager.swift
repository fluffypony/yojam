import AppKit
import ServiceManagement
import YojamCore

/// Removes all Yojam-owned state from the user's system and quits the app.
/// Called from the Uninstall button in Advanced > Danger Zone and from the
/// status-bar menu Uninstall item.
enum UninstallManager {

    @MainActor
    static func uninstall(removePreferences: Bool) {
        YojamLogger.shared.log("Uninstall starting (removePreferences=\(removePreferences))")

        // 1. Remove native messaging manifests.
        NativeMessagingInstaller.removeAll()

        // 1b. Unload and remove the self-cleanup LaunchAgent so it does not
        // fire after we intentionally remove everything.
        SelfCleanupInstaller.uninstallAgent()

        // 2. Unregister login item.
        try? SMAppService.mainApp.unregister()

        // 3. Remove log directory.
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Yojam")
        try? FileManager.default.removeItem(at: logDir)

        // 4. Optionally remove App Group and user-level preferences.
        if removePreferences {
            if let suite = UserDefaults(suiteName: SharedRoutingStore.suiteName) {
                suite.removePersistentDomain(forName: SharedRoutingStore.suiteName)
                _ = suite  // silence unused-warning
            }
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Yojam")
            try? FileManager.default.removeItem(at: appSupportDir)
            let groupContainer = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/\(SharedRoutingStore.suiteName)")
            try? FileManager.default.removeItem(at: groupContainer)
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/yojam")
            try? FileManager.default.removeItem(at: configDir)
        }

        // 5. Move the app bundle to the Trash (best-effort).
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            if let error {
                YojamLogger.shared.log("Trash recycle failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
