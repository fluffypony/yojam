import Foundation

/// Installs a periodic LaunchAgent that removes Yojam's user-state when the
/// app bundle has been moved to the Trash without the in-app Uninstall flow.
///
/// Rationale: when the user drags Yojam.app to the Trash directly, the main
/// app never runs `UninstallManager`, so native messaging manifests, App Group
/// data, and login-item registration linger on disk. A standalone helper
/// script installed outside the bundle provides the belt-and-suspenders
/// cleanup path described in the plan.
///
/// Layout:
/// - `~/Library/Application Support/Yojam/cleanup-helper.sh`
///     Standalone bash script. Checks whether the stored bundle path still
///     exists; if not, wipes state and removes itself + the LaunchAgent.
/// - `~/Library/LaunchAgents/org.yojam.cleanup.plist`
///     Periodic agent that runs the helper every 24h and at load.
///
/// Skipped in development (binary not inside a conventional app install
/// location) so Xcode rebuilds do not trip self-cleanup.
@MainActor
enum SelfCleanupInstaller {
    private static let agentLabel = "org.yojam.cleanup"
    private static let periodSeconds = 86_400   // daily

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private static var helperScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yojam/cleanup-helper.sh")
    }

    /// Install or refresh the cleanup helper + LaunchAgent so the stored
    /// bundle path tracks the current running bundle.
    static func installOrRefresh() {
        let bundleURL = Bundle.main.bundleURL
        guard shouldInstall(forBundle: bundleURL) else {
            YojamLogger.shared.log("SelfCleanupInstaller: skipping — bundle not in Applications (\(bundleURL.path))")
            return
        }

        do {
            try writeHelperScript()
            try writeLaunchAgentPlist(bundlePath: bundleURL.path)
            reloadAgent()
        } catch {
            YojamLogger.shared.log("SelfCleanupInstaller: install failed: \(error.localizedDescription)")
        }
    }

    /// Unload and delete the LaunchAgent and helper script. Called from the
    /// in-app Uninstall flow so the agent does not fire after an intentional
    /// uninstall.
    static func uninstallAgent() {
        unloadAgent()
        try? FileManager.default.removeItem(at: agentPlistURL)
        try? FileManager.default.removeItem(at: helperScriptURL)
    }

    // MARK: - Private

    private static func shouldInstall(forBundle url: URL) -> Bool {
        let path = url.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications").path + "/")
    }

    private static func writeHelperScript() throws {
        let dir = helperScriptURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = #"""
#!/bin/bash
# Yojam self-cleanup helper (managed by Yojam.app).
# Runs periodically via ~/Library/LaunchAgents/org.yojam.cleanup.plist.
# If the installed app bundle is gone, wipes user state and removes itself.

set -u

BUNDLE_PATH="${1:-}"
AGENT_PLIST="$HOME/Library/LaunchAgents/org.yojam.cleanup.plist"
SELF_PATH="$0"

if [ -z "$BUNDLE_PATH" ] || [ -d "$BUNDLE_PATH" ]; then
  # No bundle path given, or the app is still installed. Nothing to do.
  exit 0
fi

# Bundle is missing — wipe user state.
find "$HOME/Library/Application Support" -name "org.yojam.host.json" -type f -delete 2>/dev/null
rm -rf "$HOME/Library/Logs/Yojam" 2>/dev/null
rm -rf "$HOME/Library/Group Containers/group.org.yojam.shared" 2>/dev/null
rm -rf "$HOME/Library/Application Support/Yojam" 2>/dev/null
rm -f  "$HOME/Library/Preferences/com.yojam.app.plist" 2>/dev/null
defaults delete com.yojam.app >/dev/null 2>&1 || true
rm -rf "$HOME/.config/yojam" 2>/dev/null

# Unload and remove self.
launchctl bootout "gui/$(id -u)/org.yojam.cleanup" >/dev/null 2>&1 || true
launchctl unload "$AGENT_PLIST" >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"
rm -f "$SELF_PATH"
exit 0
"""#
        try script.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: helperScriptURL.path)
    }

    private static func writeLaunchAgentPlist(bundlePath: String) throws {
        let dir = agentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [
                "/bin/bash",
                helperScriptURL.path,
                bundlePath,
            ],
            "StartInterval": periodSeconds,
            "RunAtLoad": true,
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)

        // Skip rewrite if identical — avoids redundant unload/load cycles.
        if let existing = try? Data(contentsOf: agentPlistURL), existing == data {
            return
        }
        try data.write(to: agentPlistURL, options: .atomic)
    }

    private static func reloadAgent() {
        unloadAgent()
        runLaunchctl(["load", agentPlistURL.path])
    }

    private static func unloadAgent() {
        runLaunchctl(["unload", agentPlistURL.path])
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        task.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
