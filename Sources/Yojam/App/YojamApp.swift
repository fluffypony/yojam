import SwiftUI

@main
struct YojamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(
                settingsStore: appDelegate.settingsStore,
                browserManager: appDelegate.browserManager,
                ruleEngine: appDelegate.ruleEngine,
                rewriteManager: appDelegate.urlRewriter
            )
        }
    }
}
