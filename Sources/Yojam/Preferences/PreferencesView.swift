import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var rewriteManager: URLRewriter

    var body: some View {
        TabView {
            GeneralTab(settingsStore: settingsStore)
                .tabItem { Label("General", systemImage: "gearshape") }
            BrowsersTab(
                settingsStore: settingsStore,
                browserManager: browserManager)
                .tabItem { Label("Browsers", systemImage: "globe") }
            RulesTab(
                settingsStore: settingsStore,
                ruleEngine: ruleEngine)
                .tabItem {
                    Label("URL Rules",
                          systemImage: "arrow.triangle.branch")
                }
            RewritesTab(
                settingsStore: settingsStore,
                rewriteManager: rewriteManager)
                .tabItem {
                    Label("Rewrites",
                          systemImage: "arrow.2.squarepath")
                }
            EmailTab(
                settingsStore: settingsStore,
                browserManager: browserManager)
                .tabItem { Label("Email", systemImage: "envelope") }
            AdvancedTab(settingsStore: settingsStore)
                .tabItem {
                    Label("Advanced",
                          systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(minWidth: 600, minHeight: 450)
        .padding()
    }
}
