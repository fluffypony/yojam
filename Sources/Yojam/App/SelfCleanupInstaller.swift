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
            // Non-whitelisted launch (dev build, mounted DMG, double-clicked
            // copy in Downloads, etc.). Do NOT touch any pre-existing agent:
            // the real Applications install may still be present, and the
            // helper's own Launch Services probe handles stale stored paths.
            // Touching the agent here would leave that real install armless
            // until it launches again.
            return
        }

        do {
            try writeHelperScript()
            let wroteNewPlist = try writeLaunchAgentPlist(bundlePath: bundleURL.path)
            if wroteNewPlist {
                reloadAgent()
            }
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
# If no Yojam bundle can be found on this Mac for several consecutive
# check-ins, wipes user state and removes itself. The stored path is only a
# fast-path hint; a rename, move, or unindexed volume must not cause
# false-positive destruction on a single fire.

set -u

BUNDLE_PATH="${1:-}"
BUNDLE_ID="com.yojam.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/org.yojam.cleanup.plist"
SELF_PATH="$0"
STATE_DIR="$HOME/Library/Application Support/Yojam"
STRIKE_FILE="$STATE_DIR/.cleanup-strikes"
# Require this many consecutive "bundle not found" fires before wiping.
# With StartInterval=86400 this is effectively ~3 days of confirmed absence.
STRIKE_THRESHOLD=3

reset_strikes() {
  rm -f "$STRIKE_FILE" 2>/dev/null || true
}

# Fast path: last-known install location is still there.
if [ -n "$BUNDLE_PATH" ] && [ -d "$BUNDLE_PATH" ]; then
  reset_strikes
  exit 0
fi

# Spotlight lookup covers renamed/moved installs (including other volumes).
# Silently ignored if indexing is disabled — the explicit fallback below
# catches the common locations.
if command -v mdfind >/dev/null 2>&1; then
  HIT=$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | head -n 1)
  if [ -n "$HIT" ] && [ -d "$HIT" ]; then
    reset_strikes
    exit 0
  fi
fi

# Launch Services lookup via lsregister's dump. Unlike `path to application
# id` in AppleScript, this doesn't send an AppleEvent to the target app
# (which can wake/launch it). Blocks in the dump are separated by lines of
# dashes; within each block we track the last `path:` value and emit it
# when `identifier:` matches the Yojam bundle ID.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  LS_HIT=$("$LSREGISTER" -dump 2>/dev/null \
    | awk -v id="$BUNDLE_ID" '
        /^-+$/ { p=""; next }
        /^path:[[:space:]]+/ {
          p=$0
          sub(/^path:[[:space:]]+/, "", p)
          sub(/[[:space:]]+\(0x[0-9a-f]+\)[[:space:]]*$/, "", p)
        }
        /^identifier:[[:space:]]+/ {
          i=$0
          sub(/^identifier:[[:space:]]+/, "", i)
          sub(/[[:space:]]+\(0x[0-9a-f]+\)[[:space:]]*$/, "", i)
          if (i == id && p != "") { print p; exit }
        }')
  if [ -n "$LS_HIT" ] && [ -d "$LS_HIT" ]; then
    reset_strikes
    exit 0
  fi
fi

# Explicit fallback: conventional install locations.
for alt in \
  "/Applications/Yojam.app" \
  "$HOME/Applications/Yojam.app"; do
  if [ -d "$alt" ]; then
    reset_strikes
    exit 0
  fi
done

# Nothing found this round — record a strike. Only wipe after repeated
# confirmations so a transient lookup failure cannot destroy user state.
mkdir -p "$STATE_DIR" 2>/dev/null || true
strikes=$(cat "$STRIKE_FILE" 2>/dev/null || echo 0)
# Guard against non-numeric garbage in the strike file.
case "$strikes" in ''|*[!0-9]*) strikes=0;; esac
strikes=$((strikes + 1))
echo "$strikes" > "$STRIKE_FILE"
if [ "$strikes" -lt "$STRIKE_THRESHOLD" ]; then
  exit 0
fi

# Bundle is genuinely missing — wipe user state.
find "$HOME/Library/Application Support" -name "org.yojam.host.json" -type f -delete 2>/dev/null
rm -rf "$HOME/Library/Logs/Yojam" 2>/dev/null
rm -rf "$HOME/Library/Group Containers/group.org.yojam.shared" 2>/dev/null
rm -rf "$HOME/Library/Application Support/Yojam" 2>/dev/null
rm -f  "$HOME/Library/Preferences/com.yojam.app.plist" 2>/dev/null
defaults delete com.yojam.app >/dev/null 2>&1 || true
defaults delete group.org.yojam.shared >/dev/null 2>&1 || true
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

    /// Write the LaunchAgent plist. Returns true when the on-disk plist was
    /// changed (or newly created). Callers use this to decide whether to
    /// cycle `launchctl unload`/`launchctl load`.
    private static func writeLaunchAgentPlist(bundlePath: String) throws -> Bool {
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

        if let existing = try? Data(contentsOf: agentPlistURL), existing == data {
            return false
        }
        try data.write(to: agentPlistURL, options: .atomic)
        return true
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
