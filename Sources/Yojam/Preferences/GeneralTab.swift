import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(title: "General", subtitle: "Startup, activation mode, and core preferences.")

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    startupSection
                    activationSection
                    pickerSection
                    servicesSection
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .background(Theme.bgApp)
    }

    // MARK: - Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Startup")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Automatically start Yojam when you log in.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.launchAtLogin)
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Browser")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Set Yojam as your system default browser to intercept all links.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    defaultBrowserStatus
                }
            }
        }
    }

    @ViewBuilder
    private var defaultBrowserStatus: some View {
        if DefaultBrowserManager.isDefaultBrowser {
            HStack(spacing: 4) {
                Circle().fill(Theme.success).frame(width: 6, height: 6)
                Text("Active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.success)
            }
        } else if !DefaultBrowserManager.isAppBundle {
            Text("Requires .app build")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        } else {
            ThemeButton("Set Default", isPrimary: true) {
                DefaultBrowserManager.promptSetDefault()
            }
        }
    }

    // MARK: - Activation

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Activation")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activation Mode")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Controls when the browser picker appears.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settingsStore.activationMode) {
                        ForEach(ActivationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Selection")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Which browser is pre-selected when the picker opens.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settingsStore.defaultSelectionBehavior) {
                        ForEach(DefaultSelectionBehavior.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }
        }
    }

    // MARK: - Picker

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Picker")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vertical Threshold")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Switch to vertical layout when this many browsers are shown.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(settingsStore.verticalThreshold)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: 24, alignment: .trailing)
                        Stepper("", value: $settingsStore.verticalThreshold, in: 4...20)
                            .labelsHidden()
                    }
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Effects")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Play a sound when the picker opens.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.soundEffectsEnabled)
                }
            }
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Services")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clipboard Monitoring")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Show a notification when a URL is copied to the clipboard.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.clipboardMonitoringEnabled)
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Sync settings across your devices via iCloud.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.iCloudSyncEnabled)
                }
            }
        }
    }
}
