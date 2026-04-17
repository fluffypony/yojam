import Sparkle
import SwiftUI

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general, browsers, pipeline, integrations, advanced, about
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:      "General"
        case .browsers:     "Browsers"
        case .pipeline:     "Link Handling"
        case .integrations: "Integrations"
        case .advanced:     "Advanced"
        case .about:        "About"
        }
    }

    var icon: String {
        switch self {
        case .general:      "gearshape.fill"
        case .browsers:     "macwindow.on.rectangle"
        case .pipeline:     "globe"
        case .integrations: "puzzlepiece.fill"
        case .advanced:     "wrench.and.screwdriver.fill"
        case .about:        "info.circle.fill"
        }
    }
}

// MARK: - Searchable Settings Index

struct SettingsSearchItem: Identifiable {
    let id = UUID()
    let tab: PreferencesTab
    let section: String
    let title: String
    let subtitle: String

    var searchText: String { "\(title) \(subtitle) \(section)".lowercased() }
}

enum SettingsSearchIndex {
    static let items: [SettingsSearchItem] = [
        // General > Startup
        SettingsSearchItem(tab: .general, section: "Startup", title: "Launch at Login",
                           subtitle: "Automatically start Yojam when you log in"),
        SettingsSearchItem(tab: .general, section: "Startup", title: "Default Browser",
                           subtitle: "Set Yojam as your system default browser to intercept all links"),

        // General > Activation
        SettingsSearchItem(tab: .general, section: "Activation", title: "Activation Mode",
                           subtitle: "Controls when the browser picker appears always hold shift smart fallback auto-pick"),
        SettingsSearchItem(tab: .general, section: "Activation", title: "Default Selection",
                           subtitle: "Which browser is pre-selected when the picker opens first last used smart learned"),

        // General > Picker
        SettingsSearchItem(tab: .general, section: "Picker", title: "Layout",
                           subtitle: "Choose the picker appearance auto small big horizontal vertical"),
        SettingsSearchItem(tab: .general, section: "Picker", title: "Vertical Threshold",
                           subtitle: "Switch to vertical layout when this many browsers are shown"),
        SettingsSearchItem(tab: .general, section: "Picker", title: "Reverse Order",
                           subtitle: "Show browsers from right to left bottom to top invert flip"),
        SettingsSearchItem(tab: .general, section: "Picker", title: "Sound Effects",
                           subtitle: "Play a sound when you pick a browser select"),
        SettingsSearchItem(tab: .general, section: "Picker", title: "Picker Shortcuts",
                           subtitle: "keyboard shortcuts number keys return escape copy hotkeys"),

        // General > History
        SettingsSearchItem(tab: .general, section: "History", title: "Recent URLs",
                           subtitle: "How long to keep recently opened URLs never timed forever auto-delete"),
        SettingsSearchItem(tab: .general, section: "History", title: "Auto-delete After",
                           subtitle: "Minutes before recent URLs are automatically removed retention"),

        // General > Services
        SettingsSearchItem(tab: .general, section: "Services", title: "Clipboard Monitoring",
                           subtitle: "Show a notification when a URL is copied to the clipboard copy link copy URL"),
        SettingsSearchItem(tab: .general, section: "Services", title: "iCloud Sync",
                           subtitle: "Sync settings across your devices via iCloud"),

        // General > Quick Start
        SettingsSearchItem(tab: .general, section: "Startup", title: "Quick Start",
                           subtitle: "setup guide onboarding how to use getting started"),

        // Browsers
        SettingsSearchItem(tab: .browsers, section: "Active Browsers", title: "Browser List",
                           subtitle: "Manage installed browsers drag reorder enable disable private strip trackers"),
        SettingsSearchItem(tab: .browsers, section: "Active Browsers", title: "Display Name",
                           subtitle: "Custom display name for browser profile bundle"),
        SettingsSearchItem(tab: .browsers, section: "Active Browsers", title: "Custom Icon",
                           subtitle: "Set a custom icon for a browser"),
        SettingsSearchItem(tab: .browsers, section: "Active Browsers", title: "Private Window",
                           subtitle: "Open links in private incognito window"),
        SettingsSearchItem(tab: .browsers, section: "Active Browsers", title: "Browser Profiles",
                           subtitle: "Select browser profile chromium firefox work personal"),
        SettingsSearchItem(tab: .browsers, section: "Suggested Browsers", title: "Suggested Browsers",
                           subtitle: "Auto-detected browsers not yet added"),
        SettingsSearchItem(tab: .browsers, section: "Email Clients", title: "Email Clients",
                           subtitle: "Manage email clients for mailto links email"),

        // Pipeline
        SettingsSearchItem(tab: .pipeline, section: "URL Tester", title: "URL Tester",
                           subtitle: "Test how a URL will be processed through the pipeline"),
        SettingsSearchItem(tab: .pipeline, section: "Global Processing", title: "Strip Tracking Parameters",
                           subtitle: "Automatically remove tracking parameters utm gclid fbclid tracker from all URLs"),
        SettingsSearchItem(tab: .pipeline, section: "Pipeline", title: "Routing Rules",
                           subtitle: "URL routing rules match pattern target browser domain path regex"),
        SettingsSearchItem(tab: .pipeline, section: "Pipeline", title: "Rewrite Rules",
                           subtitle: "URL rewrite rules find replace regex transform old reddit nitter redirect"),
        SettingsSearchItem(tab: .pipeline, section: "Pipeline", title: "Import Export Rules",
                           subtitle: "Import or export routing rules as JSON"),

        // Integrations
        SettingsSearchItem(tab: .integrations, section: "System Registrations", title: "Default Browser",
                           subtitle: "Check if Yojam is the system default browser"),
        SettingsSearchItem(tab: .integrations, section: "System Registrations", title: "Webloc Handler",
                           subtitle: "Handle AirDrop webloc inetloc internet location files"),
        SettingsSearchItem(tab: .integrations, section: "System Registrations", title: "Yojam Scheme",
                           subtitle: "yojam:// URL scheme registration for extensions and automation"),
        SettingsSearchItem(tab: .integrations, section: "System Registrations", title: "Handoff",
                           subtitle: "Continue browsing from iPhone iPad to Mac via Handoff"),
        SettingsSearchItem(tab: .integrations, section: "Extensions", title: "Share Extension",
                           subtitle: "Open in Yojam share menu share sheet"),
        SettingsSearchItem(tab: .integrations, section: "Extensions", title: "Safari Extension",
                           subtitle: "Safari web extension toolbar button context menu"),
        SettingsSearchItem(tab: .integrations, section: "Extensions", title: "Services Menu",
                           subtitle: "Open in Yojam services menu keyboard shortcut"),
        SettingsSearchItem(tab: .integrations, section: "Browser Native Messaging", title: "Chrome Native Host",
                           subtitle: "Chrome Chromium Brave Edge Vivaldi Arc native messaging host manifest"),
        SettingsSearchItem(tab: .integrations, section: "Browser Native Messaging", title: "Firefox Native Host",
                           subtitle: "Firefox native messaging host manifest"),
        SettingsSearchItem(tab: .integrations, section: "App Group Storage", title: "Shared Container",
                           subtitle: "App Group container access shared routing store"),

        // Advanced
        SettingsSearchItem(tab: .advanced, section: "Diagnostics", title: "Debug Logging",
                           subtitle: "Logs to ~/Library/Logs/Yojam/ debug diagnostics"),
        SettingsSearchItem(tab: .advanced, section: "Tracker Parameter List", title: "Tracker Parameter List",
                           subtitle: "Parameters stripped when tracking parameter removal is enabled utm"),
        SettingsSearchItem(tab: .advanced, section: "Smart Routing", title: "Learned Preferences",
                           subtitle: "Yojam learns which browser you prefer for each domain clear smart routing remember"),
        SettingsSearchItem(tab: .advanced, section: "Settings Data", title: "Export Settings",
                           subtitle: "Save all settings to a JSON file for backup or transfer"),
        SettingsSearchItem(tab: .advanced, section: "Settings Data", title: "Import Settings",
                           subtitle: "Load settings from a previously exported JSON file"),
        SettingsSearchItem(tab: .advanced, section: "Danger Zone", title: "Re-detect Browsers",
                           subtitle: "Clear all browser data and detect installed browsers from scratch"),
        SettingsSearchItem(tab: .advanced, section: "Danger Zone", title: "Reset All Settings",
                           subtitle: "Restore all settings to their factory defaults"),

        // About
        SettingsSearchItem(tab: .about, section: "About", title: "About Yojam",
                           subtitle: "Version copyright credits author riccardo spagni"),
        SettingsSearchItem(tab: .about, section: "Links", title: "Website",
                           subtitle: "yoj.am homepage link"),
        SettingsSearchItem(tab: .about, section: "Links", title: "Source Code",
                           subtitle: "github fluffypony yojam open source repository"),
        SettingsSearchItem(tab: .about, section: "License", title: "License",
                           subtitle: "BSD 3-clause license terms copyright"),
    ]

    static func search(_ query: String) -> [SettingsSearchItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return items.filter { $0.searchText.contains(q) }
    }
}

// MARK: - Main Preferences View

struct PreferencesView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var rewriteManager: URLRewriter
    let routingSuggestionEngine: RoutingSuggestionEngine
    let updater: SPUUpdater

    @State private var selectedTab: PreferencesTab = .general
    @State private var searchText = ""
    @State private var scrollToSection: String?

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchIndex.search(searchText)
    }

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 900, height: 600)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
        // When Quick Start is re-shown (e.g. from menu bar), switch to General tab
        .onChange(of: settingsStore.hasDismissedQuickStart) { _, dismissed in
            if !dismissed {
                selectedTab = .general
            }
        }
        // Handle scroll requests from menu bar actions
        .onChange(of: settingsStore.pendingScrollToSection) { _, section in
            guard let section else { return }
            selectedTab = .general
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToSection = section
                settingsStore.pendingScrollToSection = nil
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                TextField("Search settings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
            .padding(16)

            if isSearching {
                searchResultsList
            } else {
                // Nav items
                VStack(spacing: 2) {
                    ForEach(PreferencesTab.allCases) { tab in
                        sidebarItem(tab)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Help entry point
            Button {
                settingsStore.hasDismissedQuickStart = false
                selectedTab = .general
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                    Text("Quick Start")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("Show the Quick Start guide")
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .background(Theme.bgSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        let results = searchResults
        if results.isEmpty {
            VStack(spacing: 8) {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
        } else {
            let grouped = Dictionary(grouping: results, by: \.tab)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PreferencesTab.allCases) { tab in
                        if let items = grouped[tab], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.label.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 2)

                                ForEach(items) { item in
                                    Button {
                                        selectedTab = item.tab
                                        searchText = ""
                                        let section = item.section
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            scrollToSection = section
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Theme.textPrimary)
                                            Text(item.section)
                                                .font(.system(size: 10))
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Theme.bgHover.opacity(0.001))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private func sidebarItem(_ tab: PreferencesTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 16)
                Text(tab.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(selectedTab == tab ? Theme.textInverse : Theme.textSecondary)
            .background(
                selectedTab == tab ? Theme.bgActive : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:
            GeneralTab(
                settingsStore: settingsStore,
                updater: updater,
                scrollToSection: $scrollToSection,
                selectedTab: $selectedTab)
        case .browsers:
            BrowsersTab(settingsStore: settingsStore, browserManager: browserManager, scrollToSection: $scrollToSection)
        case .pipeline:
            PipelineTab(
                settingsStore: settingsStore,
                ruleEngine: ruleEngine,
                rewriteManager: rewriteManager,
                browserManager: browserManager,
                scrollToSection: $scrollToSection)
        case .integrations:
            IntegrationsTab(
                settingsStore: settingsStore,
                scrollToSection: $scrollToSection)
        case .advanced:
            AdvancedTab(
                settingsStore: settingsStore,
                browserManager: browserManager,
                ruleEngine: ruleEngine,
                routingSuggestionEngine: routingSuggestionEngine,
                scrollToSection: $scrollToSection)
        case .about:
            AboutTab(scrollToSection: $scrollToSection)
        }
    }
}
