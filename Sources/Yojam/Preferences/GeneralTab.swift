import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var accessibilityGranted = AccessibilityHelper.isTrusted

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
            Section("Universal Click Modifier") {
                Toggle(
                    "Enable modifier+click",
                    isOn: $settingsStore.universalClickModifierEnabled)
                    .onChange(of: settingsStore.universalClickModifierEnabled) { _, enabled in
                        if enabled && !accessibilityGranted {
                            AccessibilityHelper.promptForTrust()
                        }
                    }
                if settingsStore.universalClickModifierEnabled {
                    Text("Hold a modifier while clicking a link in Slack, Mail, Notes, or other non-browser apps to force the picker. Does not work for links inside browsers (they handle clicks internally).")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Cmd+Shift Click",
                           isOn: $settingsStore.cmdShiftClickEnabled)
                    Toggle("Ctrl+Shift Click",
                           isOn: $settingsStore.ctrlShiftClickEnabled)
                    Toggle("Cmd+Option Click",
                           isOn: $settingsStore.cmdOptionClickEnabled)
                    if !accessibilityGranted {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Accessibility permission required.")
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Grant") { AccessibilityHelper.promptForTrust() }
                                    .controlSize(.small)
                            }
                            Text("Permission is tracked by binary identity. Debug builds change identity on each compile, so you may need to re-grant after rebuilding.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Accessibility permission granted.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Sync") {
                Toggle("Sync via iCloud",
                       isOn: $settingsStore.iCloudSyncEnabled)
            }
        }
        .formStyle(.grouped)
        // Poll accessibility status every 2 seconds while visible,
        // since the grant happens in System Settings and there is
        // no callback for it.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AccessibilityHelper.isTrusted
        }
        .onAppear {
            accessibilityGranted = AccessibilityHelper.isTrusted
        }
    }
}
