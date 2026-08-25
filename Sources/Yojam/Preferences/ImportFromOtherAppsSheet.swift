import SwiftUI
import YojamCore

struct ImportFromOtherAppsSheet: View {
    struct Completion {
        let routeCount: Int
        let rewriteCount: Int
        let duplicateCount: Int
    }

    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    let offeredSources: [ConfigImporter.Source]?
    let onImport: (() -> Void)?
    let onDismiss: () -> Void

    @State private var detected: [ConfigImporter.Source] = []
    @State private var selectedSource: ConfigImporter.Source?
    @State private var results: [ConfigImporter.Source: ConfigImporter.ImportResult] = [:]
    @State private var selectedRuleIDs: Set<UUID> = []
    @State private var selectedRewriteIDs: Set<UUID> = []
    @State private var completion: Completion?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        ruleEngine: RuleEngine,
        offeredSources: [ConfigImporter.Source]? = nil,
        onImport: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.ruleEngine = ruleEngine
        self.offeredSources = offeredSources
        self.onImport = onImport
        self.onDismiss = onDismiss
    }

    private var orderedResults: [ConfigImporter.ImportResult] {
        detected.compactMap { results[$0] }
    }

    private var selectedItemCount: Int {
        selectedRuleIDs.count + selectedRewriteIDs.count
    }

    private var hasSelectedFinickyItem: Bool {
        guard let result = results[.finicky] else { return false }
        return result.rules.contains { selectedRuleIDs.contains($0.id) }
            || result.rewriteRules.contains { selectedRewriteIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.borderSubtle)
            content
            Divider().background(Theme.borderSubtle)
            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 460, idealHeight: 560)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadSources)
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(completion == nil ? "Import from Other Apps" : "Import Complete")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
                if completion == nil, !detected.isEmpty {
                    Text("Review each item before it is added to Yojam.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        if let completion {
            completionPanel(completion)
        } else if isLoading {
            loadingPanel
        } else if detected.isEmpty {
            emptyPanel
        } else {
            HStack(spacing: 0) {
                sourceList
                    .frame(width: 190)
                    .background(Theme.bgSidebar)
                Divider().background(Theme.borderSubtle)
                previewPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var loadingPanel: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Reading rule files...")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading rule files")
    }

    private var emptyPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("No supported apps detected")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Text("Install Bumpr, Choosy, or Finicky, then open this importer again.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
                    selectedSource = source
                } label: {
                    HStack(spacing: 8) {
                        Text(source.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let result = results[source] {
                            Text("\(result.itemCount)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .foregroundColor(
                        selectedSource == source ? Theme.textInverse : Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selectedSource == source ? Theme.bgActive : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.displayName)
                .accessibilityValue(selectedSource == source ? "Selected" : "Not selected")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let source = selectedSource, let result = results[source] {
            VStack(alignment: .leading, spacing: 0) {
                previewHeader(result)
                Divider().background(Theme.borderSubtle)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        warningList(result.warnings)

                        if result.source == .finicky {
                            shortlinkImportNotice(result)
                        }

                        if result.itemCount == 0 {
                            Text("No compatible items were found in this configuration.")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.top, result.warnings.isEmpty ? 16 : 0)
                        }

                        if !result.rules.isEmpty {
                            itemSectionTitle("ROUTES")
                            ForEach(result.rules) { rule in
                                ruleRow(rule, in: result)
                            }
                        }

                        if !result.rewriteRules.isEmpty {
                            itemSectionTitle("REWRITES")
                            ForEach(result.rewriteRules) { rewrite in
                                rewriteRow(rewrite, in: result)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        } else {
            Color.clear
        }
    }

    private func shortlinkImportNotice(
        _ result: ConfigImporter.ImportResult
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            Text(shortlinkImportDescription(result))
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shortlinkImportDescription(result))
    }

    private func shortlinkImportDescription(
        _ result: ConfigImporter.ImportResult
    ) -> String {
        switch result.finickyShortlinkPolicy {
        case .replace(let hosts, _):
            if hosts.isEmpty {
                return hasSelectedFinickyItem
                    ? "Short-link resolution will turn off with the selected Finicky items."
                    : "This Finicky configuration disables short-link resolution. Selecting an item preserves that setting in Yojam."
            }
            return hasSelectedFinickyItem
                ? "Yojam will import this Finicky short-link host list with the selected items."
                : "Selecting a Finicky item also imports its exact short-link host list."
        case .unknownDynamic:
            return "Finicky computes its short-link list dynamically. Yojam will keep its current short-link settings."
        case .none:
            return "Yojam will keep its current short-link settings."
        }
    }

    private func previewHeader(_ result: ConfigImporter.ImportResult) -> some View {
        HStack(spacing: 12) {
            Text(itemSummary(routes: result.rules.count, rewrites: result.rewriteRules.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if result.itemCount > 0 {
                Button("Select all") { selectAll(in: result) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                Button("Select none") { selectNone(in: result) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func warningList(_ warnings: [String]) -> some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Import warnings")
        }
    }

    private func itemSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 2)
    }

    private func ruleRow(
        _ rule: Rule,
        in result: ConfigImporter.ImportResult
    ) -> some View {
        let missingReviewRewrite = result.source == .finicky
            && result.rewriteRules.contains {
                requiresManualSelection($0) && !selectedRewriteIDs.contains($0.id)
            }
        return Toggle(isOn: Binding(
            get: { selectedRuleIDs.contains(rule.id) },
            set: { selected in
                if selected {
                    selectedRuleIDs.insert(rule.id)
                    if result.source == .finicky {
                        selectedRewriteIDs.formUnion(
                            result.rewriteRules.lazy
                                .filter { !requiresManualSelection($0) }
                                .map(\.id))
                    }
                } else {
                    selectedRuleIDs.remove(rule.id)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(routeDescription(rule))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                if requiresManualSelection(rule) {
                    Text("Review required before selection")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                if missingReviewRewrite {
                    Text("Select each rewrite marked for review first.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                if result.source == .finicky, !result.rewriteRules.isEmpty {
                    Text(
                        "Includes \(result.rewriteRules.count) Finicky "
                            + "\(result.rewriteRules.count == 1 ? "rewrite" : "rewrites")")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(missingReviewRewrite)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .accessibilityLabel("Route: \(rule.name)")
        .accessibilityValue(
            selectedRuleIDs.contains(rule.id) ? "Selected" : "Not selected")
        .accessibilityHint(
            routeDescription(rule)
                + (requiresManualSelection(rule) ? ". Review required before selection." : "")
                + (missingReviewRewrite
                    ? ". Select each rewrite marked for review first."
                    : "")
                + (result.source == .finicky && !result.rewriteRules.isEmpty
                    ? ". Selecting this route also selects its exact Finicky rewrites."
                    : ""))
    }

    private func rewriteRow(
        _ rewrite: URLRewriteRule,
        in result: ConfigImporter.ImportResult
    ) -> some View {
        Toggle(isOn: Binding(
            get: { selectedRewriteIDs.contains(rewrite.id) },
            set: { selected in
                if selected {
                    selectedRewriteIDs.insert(rewrite.id)
                } else {
                    selectedRewriteIDs.remove(rewrite.id)
                    if result.source == .finicky {
                        selectedRuleIDs.subtract(result.rules.map(\.id))
                    }
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rewrite.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text("\(rewrite.matchPattern) \u{2192} \(rewrite.replacement)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                if requiresManualSelection(rewrite) {
                    Text("Review required before selection")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .accessibilityLabel("Rewrite: \(rewrite.name)")
        .accessibilityValue(
            selectedRewriteIDs.contains(rewrite.id) ? "Selected" : "Not selected")
        .accessibilityHint(
            "Replaces \(rewrite.matchPattern) with \(rewrite.replacement)."
                + (requiresManualSelection(rewrite)
                    ? " Review required before selection."
                    : ""))
    }

    private func completionPanel(_ completion: Completion) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundColor(Theme.success)
                .accessibilityHidden(true)
            Text(completionTitle(completion))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Text(completionDescription(completion))
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            if completion == nil {
                ThemeButton("Cancel") { onDismiss() }
                Spacer()
                ThemeButton(importButtonLabel, isPrimary: true) {
                    performImport()
                }
                .disabled(selectedItemCount == 0)
                .opacity(selectedItemCount == 0 ? 0.5 : 1)
            } else {
                Spacer()
                ThemeButton("Done", isPrimary: true) { onDismiss() }
            }
        }
        .padding(16)
    }

    private var importButtonLabel: String {
        "Import \(selectedItemCount) \(selectedItemCount == 1 ? "Item" : "Items")"
    }

    @MainActor
    private func loadSources() {
        guard detected.isEmpty, !isLoading else { return }
        let sources = offeredSources ?? ConfigImporter.detectAvailable()
        detected = sources
        selectedSource = sources.first
        guard !sources.isEmpty else { return }

        isLoading = true
        let worker = Task.detached(priority: .userInitiated) {
            var loaded: [ConfigImporter.Source: ConfigImporter.ImportResult] = [:]
            for source in sources {
                guard !Task.isCancelled else { return loaded }
                loaded[source] = ConfigImporter.importFrom(source)
            }
            return loaded
        }
        loadTask = Task {
            let loaded = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            results = loaded
            isLoading = false
            loadTask = nil
        }
    }

    private func selectAll(in result: ConfigImporter.ImportResult) {
        selectedRewriteIDs.formUnion(
            result.rewriteRules.lazy.filter { !requiresManualSelection($0) }.map(\.id))
        let hasMissingReviewRewrite = result.source == .finicky
            && result.rewriteRules.contains {
                requiresManualSelection($0) && !selectedRewriteIDs.contains($0.id)
            }
        if !hasMissingReviewRewrite {
            selectedRuleIDs.formUnion(
                result.rules.lazy.filter { !requiresManualSelection($0) }.map(\.id))
        }
    }

    private func requiresManualSelection(_ rule: Rule) -> Bool {
        rule.metadata?["importRequiresReview"] == "true"
    }

    private func requiresManualSelection(_ rewrite: URLRewriteRule) -> Bool {
        rewrite.metadata?["importRequiresReview"] == "true"
    }

    private func selectNone(in result: ConfigImporter.ImportResult) {
        selectedRuleIDs.subtract(result.rules.map(\.id))
        selectedRewriteIDs.subtract(result.rewriteRules.map(\.id))
    }

    private func performImport() {
        let existingRewrites = settingsStore.loadGlobalRewriteRules()
        let plan = ConfigImportPlan.make(
            results: orderedResults,
            selectedRuleIDs: selectedRuleIDs,
            selectedRewriteIDs: selectedRewriteIDs,
            existingRules: ruleEngine.rules,
            existingRewriteRules: existingRewrites)

        ruleEngine.addImportedRules(plan.rules)
        if !plan.rewriteRules.isEmpty {
            settingsStore.saveGlobalRewriteRules(existingRewrites + plan.rewriteRules)
        }
        if case .replace(let hosts, let mode) = plan.shortlinkPolicyChange {
            settingsStore.shortlinkResolutionHosts = hosts
            settingsStore.shortlinkResolutionMode = mode
            settingsStore.shortlinkResolutionEnabled = !hosts.isEmpty
        }

        completion = Completion(
            routeCount: plan.rules.count,
            rewriteCount: plan.rewriteRules.count,
            duplicateCount: plan.duplicateItemCount)
        onImport?()
    }

    private func routeDescription(_ rule: Rule) -> String {
        let target = rule.targetAppName.isEmpty ? rule.targetBundleId : rule.targetAppName
        let profile = rule.ruleProfileId.map { " [\($0)]" } ?? ""
        let arguments = rule.ruleCustomLaunchArgs.map { " \u{00b7} args: \($0)" } ?? ""
        return "\(rule.matchType.displayName) \u{00b7} \(rule.pattern) \u{2192} \(target)\(profile)\(arguments)"
    }

    private func itemSummary(routes: Int, rewrites: Int) -> String {
        let routeText = "\(routes) \(routes == 1 ? "route" : "routes")"
        let rewriteText = "\(rewrites) \(rewrites == 1 ? "rewrite" : "rewrites")"
        return "\(routeText), \(rewriteText)"
    }

    private func completionDescription(_ completion: Completion) -> String {
        var sentences: [String] = []
        let added = completion.routeCount + completion.rewriteCount
        if added > 0 {
            sentences.append(
                "The import includes \(addedItemSummary(completion)).")
        }
        if completion.duplicateCount > 0 {
            let noun = completion.duplicateCount == 1 ? "duplicate" : "duplicates"
            sentences.append("It skipped \(completion.duplicateCount) \(noun).")
        }
        return sentences.joined(separator: " ")
    }

    private func completionTitle(_ completion: Completion) -> String {
        let count = completion.routeCount + completion.rewriteCount
        if count == 0 {
            return "Yojam did not add any new items."
        }
        return "Yojam added \(count) \(count == 1 ? "item" : "items")."
    }

    private func addedItemSummary(_ completion: Completion) -> String {
        var parts: [String] = []
        if completion.routeCount > 0 {
            parts.append(
                "\(completion.routeCount) "
                    + (completion.routeCount == 1 ? "route" : "routes"))
        }
        if completion.rewriteCount > 0 {
            parts.append(
                "\(completion.rewriteCount) "
                    + (completion.rewriteCount == 1 ? "rewrite" : "rewrites"))
        }
        return parts.joined(separator: " and ")
    }
}
