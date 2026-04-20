import SwiftUI
import YojamCore

struct ImportFromOtherAppsSheet: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    let onDismiss: () -> Void

    @State private var detected: [ConfigImporter.Source] = []
    @State private var selectedSource: ConfigImporter.Source?
    @State private var previewResult: ConfigImporter.ImportResult?
    @State private var selectedRuleIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.borderSubtle)
            content
            Divider().background(Theme.borderSubtle)
            footer
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 440, idealHeight: 520)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
        .onAppear {
            detected = ConfigImporter.detectAvailable()
        }
    }

    private var header: some View {
        HStack {
            Text("Import from Other Apps")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textInverse)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        if detected.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.textSecondary)
                Text("No supported apps detected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text("Yojam can import from Bumpr, Choosy, and Finicky if their configuration files exist in the expected locations.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                sourceList
                    .frame(width: 180)
                    .background(Theme.bgSidebar)
                Divider().background(Theme.borderSubtle)
                previewPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DETECTED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            ForEach(detected) { source in
                Button {
                    selectSource(source)
                } label: {
                    HStack {
                        Text(source.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selectedSource == source ? Theme.textInverse : Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedSource == source ? Theme.bgActive : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let result = previewResult {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(result.rules.count) rule(s) available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if !result.rules.isEmpty {
                        Button("Select all") { selectedRuleIds = Set(result.rules.map(\.id)) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                        Button("Select none") { selectedRuleIds.removeAll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                    }
                }
                .padding(12)

                Divider().background(Theme.borderSubtle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !result.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(result.warnings, id: \.self) { warning in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                        Text(warning)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }

                        ForEach(result.rules) { rule in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { selectedRuleIds.contains(rule.id) },
                                    set: { on in
                                        if on { selectedRuleIds.insert(rule.id) }
                                        else { selectedRuleIds.remove(rule.id) }
                                    }))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                    Text("\(rule.matchType.displayName) · \(rule.pattern) \u{2192} \(rule.targetAppName.isEmpty ? rule.targetBundleId : rule.targetAppName)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        } else {
            VStack {
                Text("Select a source to preview rules.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            ThemeButton("Cancel") { onDismiss() }
            Spacer()
            ThemeButton("Import \(selectedRuleIds.count) Rule(s)", isPrimary: true) {
                performImport()
            }
            .disabled(selectedRuleIds.isEmpty)
            .opacity(selectedRuleIds.isEmpty ? 0.5 : 1)
        }
        .padding(16)
    }

    private func selectSource(_ source: ConfigImporter.Source) {
        selectedSource = source
        let result = ConfigImporter.importFrom(source)
        previewResult = result
        selectedRuleIds = Set(result.rules.map(\.id))
    }

    private func performImport() {
        guard let result = previewResult else { return }
        for rule in result.rules where selectedRuleIds.contains(rule.id) {
            ruleEngine.addRule(rule)
        }
        onDismiss()
    }
}
