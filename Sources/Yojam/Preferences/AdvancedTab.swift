import SwiftUI
import UniformTypeIdentifiers

struct AdvancedTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    let routingSuggestionEngine: RoutingSuggestionEngine
    @Binding var scrollToSection: String?

    @State private var showingResetAlert = false
    @State private var showingResetBrowsersAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(title: "Advanced", subtitle: "Debug, data management, and maintenance.")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        debugSection.id("Diagnostics")
                        utmParametersSection.id("Tracker Parameter List")
                        smartRoutingSection.id("Smart Routing")
                        dataSection.id("Settings Data")
                        dangerZoneSection.id("Danger Zone")
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
        .alert("Re-detect browsers?", isPresented: $showingResetBrowsersAlert) {
            Button("Re-detect", role: .destructive) { redetectBrowsers() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears all browser and email client data and re-detects from scratch.")
        }
        .alert("Reset all settings?", isPresented: $showingResetAlert) {
            Button("Reset", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Diagnostics")
            ThemePanel {
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug Logging")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Logs to ~/Library/Logs/Yojam/")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeToggle(isOn: $settingsStore.debugLoggingEnabled)
                }
            }
        }
    }

    // MARK: - UTM Parameters

    private var utmParametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Tracker Parameter List")
            VStack(alignment: .leading, spacing: 8) {
                Text("Parameters stripped when tracking parameter removal is enabled:")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                TextEditor(
                    text: Binding(
                        get: {
                            settingsStore.utmStripList.joined(separator: "\n")
                        },
                        set: {
                            settingsStore.utmStripList = $0
                                .components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    )
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(8)
                .background(Theme.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )

                HStack {
                    Spacer()
                    ThemeButton("Reset to Defaults") {
                        settingsStore.utmStripList = UTMStripper.defaultParameters
                    }
                }
            }
        }
    }

    // MARK: - Smart Routing

    private var smartRoutingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Smart Routing")
            ThemePanel {
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learned Preferences")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Yojam learns which browser you prefer for each domain.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Clear") {
                        routingSuggestionEngine.clearAll()
                    }
                }
            }
        }
    }

    // MARK: - Data Management

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Settings Data")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Save all settings to a JSON file for backup or transfer.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Export...") { exportSettings() }
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Load settings from a previously exported JSON file.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Import...") { importSettings() }
                }
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Danger Zone")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Re-detect Browsers")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Clear all browser data and detect installed browsers from scratch.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeDangerButton(label: "Re-detect") {
                        showingResetBrowsersAlert = true
                    }
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset All Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Restore all settings to their factory defaults.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeDangerButton(label: "Reset All") {
                        showingResetAlert = true
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func exportSettings() {
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

    private func importSettings() {
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

    private func redetectBrowsers() {
        settingsStore.saveBrowsers([])
        settingsStore.saveEmailClients([])
        UserDefaults.standard.removeObject(forKey: "browsers")
        UserDefaults.standard.removeObject(forKey: "emailClients")
        browserManager.browsers = []
        browserManager.suggestedBrowsers = []
        browserManager.emailClients = []
        let fresh = BrowserManager(settingsStore: settingsStore)
        browserManager.browsers = fresh.browsers
        browserManager.emailClients = fresh.emailClients
        browserManager.suggestedBrowsers = fresh.suggestedBrowsers
    }

    // §16: Re-detect browsers after reset to avoid empty browser list
    private func resetAll() {
        settingsStore.resetToDefaults()
        redetectBrowsers()
        ruleEngine.reloadRules()
    }
}
