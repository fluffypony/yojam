import Sparkle
import SwiftUI
import TipKit

struct GeneralTab: View {
    @ObservedObject var settingsStore: SettingsStore
    let updater: SPUUpdater
    @Binding var scrollToSection: String?
    @Binding var selectedTab: PreferencesTab
    @State private var isDefault = DefaultBrowserManager.isDefaultBrowser

    private let setDefaultTip = SetDefaultBrowserTip()
    private let activationModeTip = ActivationModeTip()

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(short) (build \(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(title: "General", subtitle: "Startup, activation mode, and core preferences.")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if !settingsStore.hasDismissedQuickStart {
                            QuickStartCard(
                                settingsStore: settingsStore,
                                onSwitchTab: { tab in selectedTab = tab },
                                onScrollToSection: { section in
                                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                                })
                        }
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
                ThemePanelRow(helpText: HelpText.General.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Yojam starts automatically when you log in.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.launchAtLogin)
                }
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically check for updates")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text(versionString)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: automaticUpdatesBinding)
                }
                ThemePanelRow(isLast: true, helpText: HelpText.General.defaultBrowser) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Browser")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Set Yojam as your default so every link goes through it.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    defaultBrowserStatus
                }
            }
            if !isDefault {
                TipView(setDefaultTip)
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
            ThemeButton("Set Default", isPrimary: true, help: "Opens macOS system prompt to set Yojam as your default browser") {
                DefaultBrowserManager.promptSetDefault()
                SetDefaultBrowserTip.hasSetDefault = true
                for delay in [1.0, 3.0, 6.0, 10.0, 15.0, 20.0, 30.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if !isDefault {
                            isDefault = DefaultBrowserManager.isDefaultBrowser
                        }
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
                ThemePanelRow(hideDivider: true, helpText: HelpText.General.activationMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activation Mode")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Pick when the browser chooser appears.")
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
                    .frame(width: 220)
                    .accessibilityLabel("Activation mode")
                    .help("Choose when the browser picker appears")
                    .onChange(of: settingsStore.activationMode) { _, _ in
                        ActivationModeTip.hasChangedMode = true
                    }
                }
                // Dynamic inline help for current activation mode
                VStack(spacing: 0) {
                    ThemeInlineHelp(text: "Currently set: " + {
                        switch settingsStore.activationMode {
                        case .always: return HelpText.General.activationAlways
                        case .holdShift: return HelpText.General.activationHoldShift
                        case .smartFallback: return HelpText.General.activationSmartFallback
                        }
                    }())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    Divider().background(Theme.borderSubtle)
                }
                ThemePanelRow(isLast: true, helpText: HelpText.General.defaultSelection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Selection")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Which browser is pre-highlighted when the picker opens.")
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
                    .frame(width: 220)
                    .accessibilityLabel("Default selection behavior")
                    .help("Choose which browser is pre-highlighted")
                }
            }
            // Dynamic inline help for current default selection
            ThemeInlineHelp(text: "Currently set: " + {
                switch settingsStore.defaultSelectionBehavior {
                case .alwaysFirst: return HelpText.General.defaultSelectionAlwaysFirst
                case .lastUsed: return HelpText.General.defaultSelectionLastUsed
                case .smart: return HelpText.General.defaultSelectionSmart
                }
            }())
            TipView(activationModeTip)
        }
    }

    // MARK: - Picker

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Picker")
            ThemePanel {
                ThemePanelRow(helpText: HelpText.General.pickerLayout) {
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
                    .accessibilityLabel("Picker layout")
                    .help("Pick the visual style of the browser chooser")
                }
                if settingsStore.pickerLayout == .auto {
                    ThemePanelRow(helpText: HelpText.General.verticalThreshold) {
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
                                .accessibilityLabel("Vertical threshold")
                        }
                    }
                }
                ThemePanelRow(helpText: HelpText.General.invertOrder) {
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
                ThemePanelRow(isLast: true, helpText: HelpText.General.soundEffects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Effects")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Plays a short sound when you pick a browser.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.soundEffectsEnabled)
                }
            }

            // Picker Shortcuts
            ThemeCalloutCard {
                Text("Picker shortcuts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                HStack(spacing: 16) {
                    shortcutEntry("\u{21B5} / Space", "Open selected browser")
                    shortcutEntry("1\u{2013}9", "Choose directly by number")
                    shortcutEntry("\u{2318}C", "Copy URL to clipboard")
                    shortcutEntry("Esc", "Dismiss picker")
                }
            }
        }
    }

    private func shortcutEntry(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Theme.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "History")
            ThemePanel {
                ThemePanelRow(isLast: settingsStore.recentURLRetention != .timed, helpText: HelpText.General.recentURLs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent URLs")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Shows recent links in the menu bar so you can re-open one in a different browser.")
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
                    .accessibilityLabel("Recent URL retention")
                }
                if settingsStore.recentURLRetention == .timed {
                    ThemePanelRow(isLast: true, helpText: HelpText.General.recentURLsAutoDelete) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-delete After")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("Clears old entries from the recent URLs list after this long.")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            TextField("", value: $settingsStore.recentURLRetentionMinutes, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(width: 70)
                                .background(Theme.bgInput)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                                        .stroke(Theme.borderSubtle, lineWidth: 1)
                                )
                                .multilineTextAlignment(.trailing)
                                .onChange(of: settingsStore.recentURLRetentionMinutes) { _, val in
                                    settingsStore.recentURLRetentionMinutes = max(1, min(val, 1440))
                                }
                            Text("min")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                            Stepper("", value: $settingsStore.recentURLRetentionMinutes, in: 1...1440)
                                .labelsHidden()
                                .accessibilityLabel("Auto-delete minutes")
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
                ThemePanelRow(helpText: HelpText.General.clipboardMonitoring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clipboard Monitoring")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("When you copy a URL, a notification pops up so you can route it through Yojam.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.clipboardMonitoringEnabled)
                }
                ThemePanelRow(isLast: true, helpText: HelpText.General.iCloudSync) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Syncs your browser list, rules, and preferences across your Macs.")
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
