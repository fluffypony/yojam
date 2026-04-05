import SwiftUI

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general, browsers, pipeline, advanced
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:  "General"
        case .browsers: "Browsers"
        case .pipeline: "URL Pipeline"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general:  "gearshape.fill"
        case .browsers: "macwindow.on.rectangle"
        case .pipeline: "globe"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var rewriteManager: URLRewriter
    let routingSuggestionEngine: RoutingSuggestionEngine

    @State private var selectedTab: PreferencesTab = .general
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 900, height: 600)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
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

            // Nav items
            VStack(spacing: 2) {
                ForEach(filteredTabs) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 240)
        .background(Theme.bgSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
    }

    private var filteredTabs: [PreferencesTab] {
        if searchText.isEmpty { return PreferencesTab.allCases }
        return PreferencesTab.allCases.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
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
            GeneralTab(settingsStore: settingsStore)
        case .browsers:
            BrowsersTab(settingsStore: settingsStore, browserManager: browserManager)
        case .pipeline:
            PipelineTab(
                settingsStore: settingsStore,
                ruleEngine: ruleEngine,
                rewriteManager: rewriteManager,
                browserManager: browserManager)
        case .advanced:
            AdvancedTab(
                settingsStore: settingsStore,
                browserManager: browserManager,
                ruleEngine: ruleEngine,
                routingSuggestionEngine: routingSuggestionEngine)
        }
    }
}
