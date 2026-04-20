import SwiftUI
import YojamCore

/// Manage the routing suggestion engine's learned domain → browser preferences.
/// Shows each domain with its observed entry hit counts, lets the user delete
/// individual entries or promote them to explicit rules.
struct LearnedPreferencesSheet: View {
    @ObservedObject var routingSuggestionEngine: RoutingSuggestionEngine
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var ruleEngine: RuleEngine
    let onDismiss: () -> Void

    @State private var rows: [Row] = []

    struct Row: Identifiable {
        let id: String // domain
        let domain: String
        let entries: [RowEntry]
    }
    struct RowEntry: Identifiable, Hashable {
        let id: String // entryId
        let entryId: String
        let displayName: String
        let bundleId: String
        let count: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Learned Preferences")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Theme.borderSubtle)

            if rows.isEmpty {
                ThemeEmptyState(
                    icon: "brain",
                    title: "No learned preferences yet",
                    message: "Yojam will remember which browser you choose per domain after a few uses.",
                    action: nil,
                    actionLabel: nil)
                    .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                            Divider().background(Theme.borderSubtle)
                        }
                    }
                }
            }

            Divider().background(Theme.borderSubtle)
            HStack {
                ThemeDangerButton(label: "Clear All") {
                    routingSuggestionEngine.clearAll()
                    refresh()
                }
                Spacer()
                ThemeButton("Done", isPrimary: true) { onDismiss() }
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 400, idealHeight: 520)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.domain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                HStack(spacing: 8) {
                    ForEach(row.entries) { entry in
                        HStack(spacing: 4) {
                            Text(entry.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            Text("\(entry.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.bgHover)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer()
            if let top = row.entries.first {
                ThemeButton("Promote to Rule") {
                    let template = routingSuggestionEngine.makeRuleTemplate(
                        domain: row.domain,
                        entryId: top.entryId,
                        targetBundleId: top.bundleId,
                        targetAppName: top.displayName)
                    ruleEngine.addRule(template)
                }
            }
            ThemeIconButton(systemName: "trash", isDanger: true) {
                routingSuggestionEngine.removePreference(for: row.domain)
                refresh()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func refresh() {
        let raw = routingSuggestionEngine.allDomainPreferences()
        let allBrowsers = browserManager.browsers + browserManager.emailClients
        rows = raw.map { tuple in
            let entries = tuple.entries.map { pair -> RowEntry in
                let entry = allBrowsers.first { $0.id.uuidString == pair.entryId }
                return RowEntry(
                    id: pair.entryId,
                    entryId: pair.entryId,
                    displayName: entry?.fullDisplayName ?? "Unknown",
                    bundleId: entry?.bundleIdentifier ?? "",
                    count: pair.count)
            }
            return Row(id: tuple.domain, domain: tuple.domain, entries: entries)
        }
    }
}
