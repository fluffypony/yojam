import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
                    .onChange(of: settingsStore.launchAtLogin) { _, v in
                        if v { try? SMAppService.mainApp.register() }
                        else { try? SMAppService.mainApp.unregister() }
                    }
                HStack {
                    Text("Default browser:")
                    if DefaultBrowserManager.isDefaultBrowser {
                        Text("Yojam").foregroundStyle(.green)
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
                    ForEach(ActivationMode.allCases) {
                        Text($0.displayName).tag($0)
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
            Section("Universal Click Modifier") {
                Toggle(
                    "Enable modifier+click",
                    isOn: $settingsStore.universalClickModifierEnabled)
                if settingsStore.universalClickModifierEnabled {
                    Toggle("Cmd+Shift Click",
                           isOn: $settingsStore.cmdShiftClickEnabled)
                    Toggle("Ctrl+Shift Click",
                           isOn: $settingsStore.ctrlShiftClickEnabled)
                    Toggle("Cmd+Option Click",
                           isOn: $settingsStore.cmdOptionClickEnabled)
                    Text("Requires Accessibility permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Sync") {
                Toggle("Sync via iCloud",
                       isOn: $settingsStore.iCloudSyncEnabled)
            }
        }.formStyle(.grouped)
    }
}
