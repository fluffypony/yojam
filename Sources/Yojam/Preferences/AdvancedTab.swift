import SwiftUI
import UniformTypeIdentifiers

struct AdvancedTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    let routingSuggestionEngine: RoutingSuggestionEngine
    @State private var showingResetAlert = false
    @State private var showingResetBrowsersAlert = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Debug") {
                Toggle("Enable debug logging",
                       isOn: $settingsStore.debugLoggingEnabled)
                Text("Logs to ~/Library/Logs/Yojam/")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("UTM Parameter List") {
                Text("Parameters stripped when UTM stripping is enabled:")
                    .font(.caption)
                TextEditor(
                    text: Binding(
                        get: {
                            settingsStore.utmStripList
                                .joined(separator: "\n")
                        },
                        set: {
                            settingsStore.utmStripList = $0
                                .components(separatedBy: .newlines)
                                .map {
                                    $0.trimmingCharacters(in: .whitespaces)
                                }
                                .filter { !$0.isEmpty }
                        }
                    )
                )
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 120)
                Button("Reset to Defaults") {
                    settingsStore.utmStripList = UTMStripper.defaultParameters
                }
            }
            Section("Smart Routing") {
                Text("Yojam learns which browser you prefer for each domain.")
                    .font(.caption)
                Button("Clear Learned Preferences") {
                    routingSuggestionEngine.clearAll()
                }
            }
            Section("Settings") {
                HStack {
                    Button("Export Settings...") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.json]
                        panel.nameFieldStringValue = "yojam-settings.json"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                let data = try settingsStore.exportJSON()
                                try data.write(to: url)
                            } catch {
                                errorMessage = "Export failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    Button("Import Settings...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                let data = try Data(contentsOf: url)
                                try settingsStore.importJSON(data)
                                browserManager.browsers = settingsStore.loadBrowsers()
                                browserManager.emailClients = settingsStore.loadEmailClients()
                                ruleEngine.reloadRules()
                            } catch {
                                errorMessage = "Import failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                Button("Re-detect Browsers") {
                    showingResetBrowsersAlert = true
                }
                .alert("Re-detect browsers?",
                       isPresented: $showingResetBrowsersAlert) {
                    Button("Re-detect", role: .destructive) {
                        settingsStore.saveBrowsers([])
                        settingsStore.saveEmailClients([])
                        UserDefaults.standard.removeObject(forKey: "browsers")
                        UserDefaults.standard.removeObject(forKey: "emailClients")
                        browserManager.browsers = []
                        browserManager.suggestedBrowsers = []
                        browserManager.emailClients = []
                        // Re-init triggers fresh detection
                        let fresh = BrowserManager(settingsStore: settingsStore)
                        browserManager.browsers = fresh.browsers
                        browserManager.emailClients = fresh.emailClients
                        browserManager.suggestedBrowsers = fresh.suggestedBrowsers
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Clears all browser and email client data and re-detects from scratch.")
                }
                Button("Reset All Settings", role: .destructive) {
                    showingResetAlert = true
                }
                .alert("Reset?", isPresented: $showingResetAlert) {
                    Button("Reset", role: .destructive) {
                        settingsStore.resetToDefaults()
                        browserManager.browsers = settingsStore.loadBrowsers()
                        browserManager.emailClients = settingsStore.loadEmailClients()
                        ruleEngine.reloadRules()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
