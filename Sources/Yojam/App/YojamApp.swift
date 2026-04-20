import SwiftUI

@main
struct YojamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    /// Stable identifier for the preferences Window scene. Used by both
    /// `openWindow(id:)` and AppDelegate to match the NSWindow for any
    /// AppKit-side tweaks (frame autosave, cmd-tab reveal, etc.).
    static let preferencesWindowId = "preferences"

    var body: some Scene {
        // Bridge openWindow to AppDelegate on every body evaluation so
        // AppKit code can open preferences without the deprecated selector.
        let _ = { appDelegate.openSettingsAction = { openWindow(id: Self.preferencesWindowId) } }()

        // Window scene (not Settings) because SwiftUI's Settings scene is
        // hardcoded non-resizable on macOS 14 — `.windowResizability` is
        // silently ignored there. A Window scene respects resizability and
        // behaves identically for our purposes (we wire Cmd+, manually).
        Window("Yojam Settings", id: Self.preferencesWindowId) {
            PreferencesView(
                settingsStore: appDelegate.settingsStore,
                browserManager: appDelegate.browserManager,
                ruleEngine: appDelegate.ruleEngine,
                rewriteManager: appDelegate.urlRewriter,
                routingSuggestionEngine: appDelegate.routingSuggestionEngine,
                updater: appDelegate.updater
            )
        }
        .defaultSize(width: 900, height: 600)
        // Deliberately no .windowResizability modifier: `.contentMinSize`
        // reads the view's *intrinsic* minimum (which ignores our explicit
        // `.frame(minWidth:)` floor) and keeps resetting NSWindow.minSize
        // underneath us. Default `.automatic` leaves the NSWindow alone,
        // so AppDelegate can be the single authority on minSize.
        .commands {
            // Replace the default "Settings…" menu item (which used to dispatch
            // to showSettingsWindow: for the Settings scene) with one that
            // opens our Window by id, preserving Cmd+,.
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    openWindow(id: Self.preferencesWindowId)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
