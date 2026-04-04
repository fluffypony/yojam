import SwiftUI

struct AdvancedTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var showingResetAlert = false

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
                    RoutingSuggestionEngine().clearAll()
                }
            }
            Section("Settings") {
                HStack {
                    Button("Export Settings...") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.json]
                        panel.nameFieldStringValue = "yojam-settings.json"
                        if panel.runModal() == .OK, let url = panel.url,
                           let data = try? settingsStore.exportJSON() {
                            try? data.write(to: url)
                        }
                    }
                    Button("Import Settings...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        if panel.runModal() == .OK, let url = panel.url,
                           let data = try? Data(contentsOf: url) {
                            try? settingsStore.importJSON(data)
                        }
                    }
                }
                Button("Reset All Settings", role: .destructive) {
                    showingResetAlert = true
                }
                .alert("Reset?", isPresented: $showingResetAlert) {
                    Button("Reset", role: .destructive) {
                        settingsStore.resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }.formStyle(.grouped)
    }
}
