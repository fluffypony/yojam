import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var scrollToSection: String?
    @State private var isDefault = DefaultBrowserManager.isDefaultBrowser

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(title: "General", subtitle: "Startup, activation mode, and core preferences.")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        startupSection.id("Startup")
                        activationSection.id("Activation")
                        pickerSection.id("Picker")
                        historySection.id("History")
                        servicesSection.id("Services")
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: scrollToSection) { _, section in
                    guard let section else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    scrollToSection = nil
                }
            }
        }
        .background(Theme.bgApp)
        .onAppear { isDefault = DefaultBrowserManager.isDefaultBrowser }
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
        if isDefault {
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
                // Poll a few times since the system dialog is async
                for delay in [1.0, 3.0, 6.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        isDefault = DefaultBrowserManager.isDefaultBrowser
                    }
                }
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
                        Text("Layout")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Choose the picker appearance. Auto switches based on browser count.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settingsStore.pickerLayout) {
                        ForEach(PickerLayout.allCases) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                if settingsStore.pickerLayout == .auto {
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
                }
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reverse Order")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text(settingsStore.pickerLayout.isVertical || settingsStore.pickerLayout == .auto
                             ? "Show browsers from bottom to top."
                             : "Show browsers from right to left.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.pickerInvertOrder)
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

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "History")
            ThemePanel {
                ThemePanelRow(isLast: settingsStore.recentURLRetention != .timed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent URLs")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("How long to keep recently opened URLs in the menu bar list.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settingsStore.recentURLRetention) {
                        ForEach(RecentURLRetention.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                if settingsStore.recentURLRetention == .timed {
                    ThemePanelRow(isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-delete After")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("Minutes before recent URLs are automatically removed.")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(settingsStore.recentURLRetentionMinutes) min")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                                .frame(width: 60, alignment: .trailing)
                            Stepper("", value: $settingsStore.recentURLRetentionMinutes, in: 1...1440)
                                .labelsHidden()
                        }
                    }
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
