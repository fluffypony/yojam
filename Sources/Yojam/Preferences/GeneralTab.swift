import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
                HStack {
                    Text("Default browser:")
                    if DefaultBrowserManager.isDefaultBrowser {
                        Text("Yojam").foregroundStyle(.green)
                    } else if !DefaultBrowserManager.isAppBundle {
                        Text("Requires .app build").foregroundStyle(.secondary)
                    } else {
                        Text("Not set").foregroundStyle(.orange)
                        Button("Set") {
                            DefaultBrowserManager.promptSetDefault()
                        }
                    }
                }
            }
            Section("Activation") {
                Picker("Mode:", selection: $settingsStore.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        HStack(spacing: 4) {
                            Text(mode.displayName)
                            if mode == .smartFallback {
                                Text("(?)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("URL rules are evaluated first. If a rule matches, the URL opens in the target app. If no rule matches, the browser picker appears.")
                            }
                        }.tag(mode)
                    }
                }.pickerStyle(.radioGroup)
                Picker(
                    "Default selection:",
                    selection: $settingsStore.defaultSelectionBehavior
                ) {
                    ForEach(DefaultSelectionBehavior.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
            Section("Picker") {
                Stepper(
                    "Vertical threshold: \(settingsStore.verticalThreshold)",
                    value: $settingsStore.verticalThreshold, in: 4...20)
                Toggle("Sound effects",
                       isOn: $settingsStore.soundEffectsEnabled)
            }
            Section("URL Cleaning") {
                Toggle("Strip UTM/tracking parameters globally",
                       isOn: $settingsStore.globalUTMStrippingEnabled)
            }
            Section("Clipboard") {
                Toggle("Monitor clipboard for URLs",
                       isOn: $settingsStore.clipboardMonitoringEnabled)
            }
            Section("Sync") {
                Toggle("Sync via iCloud",
                       isOn: $settingsStore.iCloudSyncEnabled)
            }
        }.formStyle(.grouped)
    }
}
