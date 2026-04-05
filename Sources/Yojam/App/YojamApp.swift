import SwiftUI

@main
struct YojamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // Bridge openSettings to AppDelegate on every body evaluation so
        // AppKit code can open preferences without the deprecated selector.
        let _ = { appDelegate.openSettingsAction = openSettings }()

        Settings {
            PreferencesView(
                settingsStore: appDelegate.settingsStore,
                browserManager: appDelegate.browserManager,
                ruleEngine: appDelegate.ruleEngine,
                rewriteManager: appDelegate.urlRewriter,
                routingSuggestionEngine: appDelegate.routingSuggestionEngine
            )
        }
        // Replace Cmd+Q "Quit" with "Close Window" so preferences
        // closes without quitting the menu bar app. Actual quit is
        // via "Quit Yojam" in the status bar menu.
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    for window in NSApp.windows where !(window is NSPanel) && window.isVisible {
                        window.close()
                    }
                }
                .keyboardShortcut("q")
            }
        }
    }
}
