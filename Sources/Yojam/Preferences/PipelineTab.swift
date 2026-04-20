import SwiftUI
import UniformTypeIdentifiers
import TipKit
import YojamCore

struct PipelineTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var rewriteManager: URLRewriter
    @ObservedObject var browserManager: BrowserManager
    @Binding var scrollToSection: String?

    @State private var testURL = ""
    @State private var testSourceApp = "" // B-URLTESTER: source app for source-scoped rules
    @State private var testPipeline: [PipelineNode] = []
    @State private var testSummary: String?
    @State private var rewriteRules: [URLRewriteRule] = []
    @State private var showingAddRule = false
    @State private var showingAddRewrite = false
    @State private var showingTrackerList = false
    @State private var errorMessage: String?
    @State private var editingRule: Rule?
    @State private var pipelineOverviewDismissed = UserDefaults.standard.bool(forKey: "helpDismissed_pipelineOverview")

    private let urlTesterTip = URLTesterTip()

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(
                title: "Link Handling",
                subtitle: "Configure how Yojam processes, cleans, and routes URLs before opening."
            ) {
                HStack(spacing: 8) {
                    ThemeButton("+ Add Rule", isPrimary: true) { showingAddRule = true }
                    ThemeButton("+ Add Rewrite") { showingAddRewrite = true }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if !pipelineOverviewDismissed {
                            pipelineOverviewCard
                        }
                        testerSection.id("URL Tester")
                        globalProcessingSection.id("Global Processing")
                        pipelineTableSection.id("Pipeline")
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.visible)
                .onChange(of: scrollToSection) { _, section in
                    guard let section else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    scrollToSection = nil
                }
            }
        }
        .background(Theme.bgApp)
        .onAppear { rewriteRules = settingsStore.loadGlobalRewriteRules() }
        .onReceive(settingsStore.objectWillChange) {
            rewriteRules = settingsStore.loadGlobalRewriteRules()
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(ruleEngine: ruleEngine, onDismiss: { showingAddRule = false })
        }
        .sheet(item: $editingRule) { rule in
            AddRuleSheet(
                ruleEngine: ruleEngine,
                onDismiss: { editingRule = nil },
                editing: rule)
        }
        .sheet(isPresented: $showingAddRewrite) {
            AddRewriteSheet(
                onAdd: { rule in
                    rewriteRules.append(rule)
                    settingsStore.saveGlobalRewriteRules(rewriteRules)
                },
                onDismiss: { showingAddRewrite = false })
        }
        .sheet(isPresented: $showingTrackerList) {
            TrackerParameterSheet(settingsStore: settingsStore, onDismiss: { showingTrackerList = false })
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

    // MARK: - Pipeline Overview Card

    private var pipelineOverviewCard: some View {
        ThemeCalloutCard {
            Text("How Yojam handles a link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                overviewStep("1", "Global rewrite rules transform the URL")
                overviewStep("2", "Tracking parameters are stripped (if on)")
                overviewStep("3", "Routing rules match the URL to a browser")
                overviewStep("4", "Browser-specific rewrites run")
                overviewStep("5", "The link opens, or the picker appears")
            }
        } onDismiss: {
            withAnimation {
                pipelineOverviewDismissed = true
                UserDefaults.standard.set(true, forKey: "helpDismissed_pipelineOverview")
            }
        }
    }

    private func overviewStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - URL Tester

    private var testerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ThemeTextField(placeholder: "Paste a URL here to test...", text: $testURL)
                ThemeTextField(placeholder: "Source app (optional)", text: $testSourceApp)
                    .frame(width: 160)
                ThemeButton("Test", help: "Run this URL through the pipeline to see what happens") {
                    runTest()
                    settingsStore.quickStartVisitedTester = true
                }
            }
            .themeHighlight(settingsStore, controlId: "urlTester")

            if !testPipeline.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(testPipeline.enumerated()), id: \.offset) { _, node in
                            if node.isArrow {
                                Text("\u{2192}")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textSecondary)
                            } else {
                                pipelineNodeView(node)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                if let testSummary {
                    Text(testSummary)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            ThemeInlineHelp(text: HelpText.Pipeline.urlTester)
            TipView(urlTesterTip)
        }
        .padding(16)
        .background(Theme.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .stroke(Theme.borderStrong, lineWidth: 1)
        )
    }

    private func pipelineNodeView(_ node: PipelineNode) -> some View {
        HStack(spacing: 6) {
            if let icon = node.icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(node.label)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundColor(
            node.isFinal ? Theme.textInverse :
            node.isActive ? Theme.textInverse :
            Theme.textSecondary
        )
        .background(
            node.isFinal ? Theme.success.opacity(0.1) :
            node.isActive ? Theme.accent.opacity(0.1) :
            Theme.bgHover
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                node.isFinal ? Theme.success :
                node.isActive ? Theme.accent :
                Theme.borderSubtle,
                lineWidth: 1
            )
        )
    }

    // MARK: - Global Processing

    private var globalProcessingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Global Processing")
            ThemePanel {
                ThemePanelRow(isLast: true, helpText: HelpText.Pipeline.stripTrackingGlobal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strip Tracking Parameters")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Strips tracking parameters from every URL before any browser sees it.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Edit List...") {
                        showingTrackerList = true
                    }
                    .padding(.trailing, 8)
                    ThemeToggle(isOn: $settingsStore.globalUTMStrippingEnabled)
                }
            }
        }
    }

    // MARK: - Pipeline Table

    private var pipelineTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Routing & Transformation Pipeline (Executed top to bottom)", helpText: HelpText.Pipeline.pipelineOrder)

            let userRules = ruleEngine.rules.filter { !$0.isBuiltIn }
            let builtInRules = ruleEngine.rules.filter(\.isBuiltIn)
            let hasContent = !rewriteRules.isEmpty || !userRules.isEmpty || !builtInRules.isEmpty

            if hasContent {
                ThemePanel {
                    // Table header
                    HStack(spacing: 0) {
                        Text("").frame(width: 30)
                        Text("STATUS").frame(width: 50, alignment: .leading)
                            .help("Whether this rule is active")
                        Text("TYPE").frame(width: 80, alignment: .leading)
                            .help("Rewrite transforms URLs; Rule routes to a browser")
                        Text("PATTERN MATCH").frame(minWidth: 150, alignment: .leading)
                            .help("The URL pattern this entry matches against")
                        Spacer()
                        Text("ACTION / TARGET").frame(width: 150, alignment: .leading)
                            .help("What happens when the pattern matches")
                        Text("").frame(width: 60)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.bgPanel)

                    Divider().background(Theme.borderSubtle)

                    ForEach(Array(rewriteRules.enumerated()), id: \.element.id) { index, rule in
                        VStack(spacing: 0) {
                            pipelineRewriteRow(rule: rule, index: index)
                            Divider().background(Theme.borderSubtle)
                        }
                    }

                    ForEach(userRules) { rule in
                        VStack(spacing: 0) {
                            pipelineRuleRow(rule: rule)
                            Divider().background(Theme.borderSubtle)
                        }
                    }

                    ForEach(Array(builtInRules.enumerated()), id: \.element.id) { index, rule in
                        VStack(spacing: 0) {
                            pipelineRuleRow(rule: rule)
                            if index < builtInRules.count - 1 {
                                Divider().background(Theme.borderSubtle)
                            }
                        }
                    }
                }
            } else {
                ThemePanel {
                    ThemeEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "No routing rules yet",
                        message: "Create a rule to automatically route specific links to a specific browser.",
                        action: { showingAddRule = true },
                        actionLabel: "+ Add Rule")
                }
            }

            // Import/Export
            HStack(spacing: 8) {
                ThemeButton("Restore Default Rules") {
                    ruleEngine.restoreAllBuiltIns()
                }
                Spacer()
                ThemeButton("Import Rules...") { importRules() }
                ThemeButton("Export Rules...") { exportRules() }
            }
        }
    }

    private func pipelineRewriteRow(rule: URLRewriteRule, index: Int) -> some View {
        HStack(spacing: 0) {
            Text("\u{22EE}\u{22EE}")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 30)
                .help("Drag to reorder priority")

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in toggleRewrite(rule.id) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
            .scaleEffect(0.7)
            .frame(width: 50, alignment: .leading)
            .help("Enable or disable this rule")
            .accessibilityLabel(rule.enabled ? "Enabled" : "Disabled")

            ThemeBadge(text: "Rewrite", isRewrite: true)
                .frame(width: 80, alignment: .leading)

            Text(rule.matchPattern)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 150, alignment: .leading)

            Spacer()

            Text(rule.replacement)
                .font(.system(size: 11))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            HStack(spacing: 4) {
                ThemeIconButton(systemName: "trash", isDanger: true) {
                    deleteRewrite(rule.id)
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(rule.enabled ? 1 : 0.5)
    }

    private func pipelineRuleRow(rule: Rule) -> some View {
        HStack(spacing: 0) {
            Text("\u{22EE}\u{22EE}")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 30)
                .help("Drag to reorder priority")

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in ruleEngine.toggleRule(rule.id) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
            .scaleEffect(0.7)
            .frame(width: 50, alignment: .leading)
            .help("Enable or disable this rule")
            .accessibilityLabel(rule.enabled ? "Enabled" : "Disabled")

            ThemeBadge(text: rule.isBuiltIn ? "Built-in" : "Rule", isRewrite: false)
                .frame(width: 80, alignment: .leading)

            Text(rule.pattern)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 150, alignment: .leading)

            Spacer()

            Text(rule.targetAppName)
                .font(.system(size: 11))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            HStack(spacing: 4) {
                ThemeIconButton(systemName: "pencil", help: "Edit rule") {
                    editingRule = rule
                }
                ThemeIconButton(systemName: "doc.on.doc", help: "Duplicate as editable rule") {
                    ruleEngine.duplicateRule(rule.id)
                }
                if rule.isBuiltIn {
                    ThemeIconButton(systemName: "arrow.counterclockwise", help: "Reset to default") {
                        ruleEngine.resetBuiltInRule(rule.id)
                    }
                }
                ThemeIconButton(systemName: "trash", isDanger: true) {
                    ruleEngine.deleteRule(rule.id)
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(rule.enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingRule = rule
        }
    }

    // MARK: - Test Logic

    private func runTest() {
        URLTesterTip.hasTestedURL = true
        var input = testURL
        // B-URLTESTER: Don't blindly prepend https:// for mailto/file schemes
        if !input.contains("://") && !input.hasPrefix("mailto:") && !input.hasPrefix("file:") {
            input = "https://" + input
        }
        guard let url = URL(string: input) else {
            testPipeline = [PipelineNode(label: "Invalid URL", isActive: false, isFinal: false)]
            testSummary = nil
            return
        }

        var nodes: [PipelineNode] = []
        nodes.append(PipelineNode(label: "Input URL"))
        nodes.append(.arrow)

        var processedURL = url

        let rewritten = rewriteManager.applyGlobalRewrites(to: processedURL)
        if rewritten.absoluteString != processedURL.absoluteString {
            nodes.append(PipelineNode(label: "Rewrite", icon: "arrow.2.squarepath", isActive: true))
            nodes.append(.arrow)
            processedURL = rewritten
        }

        var didStrip = false
        if settingsStore.globalUTMStrippingEnabled {
            let stripped = UTMStripper(settingsStore: settingsStore).strip(processedURL)
            didStrip = stripped.absoluteString != processedURL.absoluteString
            nodes.append(PipelineNode(label: "Strip Trackers", icon: "xmark.rectangle", isActive: didStrip))
            nodes.append(.arrow)
            processedURL = stripped
        }

        let sourceApp = testSourceApp.isEmpty ? nil : testSourceApp
        if let match = ruleEngine.evaluate(processedURL, sourceAppBundleId: sourceApp) {
            let host = processedURL.host ?? ""
            let result = RuleMatcher.evaluate(url: processedURL, against: match, sourceApp: sourceApp)
            nodes.append(PipelineNode(label: "Match: \(host)", icon: "globe", isActive: true))
            nodes.append(.arrow)
            nodes.append(PipelineNode(label: "Open in: \(match.targetAppName)", isFinal: true))
            let strippedNote = didStrip ? " after tracker stripping" : ""
            let ruleInfo = "\(match.name) via \(match.matchType.displayName)"
            testSummary = "This link would open in \(match.targetAppName)\(strippedNote). Matched rule: \(ruleInfo). \(result.explanation)"
        } else {
            nodes.append(PipelineNode(label: "No match", icon: "questionmark.circle"))
            nodes.append(.arrow)
            nodes.append(PipelineNode(label: "Show picker", isFinal: true))
            testSummary = "No rule matched \u{2014} Yojam would show the picker."
        }

        testPipeline = nodes
    }

    // MARK: - Rewrite Helpers

    private func toggleRewrite(_ id: UUID) {
        if let idx = rewriteRules.firstIndex(where: { $0.id == id }) {
            rewriteRules[idx].enabled.toggle()
            rewriteRules[idx].lastModifiedAt = Date()
            settingsStore.saveGlobalRewriteRules(rewriteRules)
        }
    }

    private func deleteRewrite(_ id: UUID) {
        rewriteRules.removeAll { $0.id == id }
        settingsStore.saveGlobalRewriteRules(rewriteRules)
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                try ruleEngine.importRules(from: data)
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "yojam-rules.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try ruleEngine.exportRules()
                try data.write(to: url)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Pipeline Node Model

struct PipelineNode {
    let label: String
    var icon: String? = nil
    var isActive: Bool = false
    var isFinal: Bool = false
    var isArrow: Bool = false

    static var arrow: PipelineNode {
        PipelineNode(label: "", isArrow: true)
    }
}

// MARK: - Add Rule Sheet

struct AddRuleSheet: View {
    @ObservedObject var ruleEngine: RuleEngine
    let onDismiss: () -> Void
    /// When provided, the sheet edits the given rule in-place instead of adding a new one.
    var editing: Rule?

    @State private var name = ""
    @State private var matchType: MatchType = .domain
    @State private var pattern = ""
    @State private var targetBundleId = ""
    @State private var targetAppName = ""
    @State private var priority = 100
    @State private var stripUTMParams = false
    @State private var sourceAppBundleId = ""
    @State private var firefoxContainer = ""
    @State private var targetDisplayUUID: String? = nil
    @State private var ruleProfileId: String? = nil
    @State private var rulePrivateWindowOverride: PrivateWindowOverride = .inherit
    @State private var ruleCustomLaunchArgs = ""
    @State private var targetProfiles: [BrowserProfile] = []
    @State private var testURL = ""
    @State private var testResult = ""
    @State private var testExplanation = ""
    @State private var testMatched = false

    private enum PrivateWindowOverride: String, CaseIterable, Identifiable {
        case inherit, forcePrivate, forceNormal
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .inherit:      "Inherit from browser"
            case .forcePrivate: "Private window"
            case .forceNormal:  "Normal window"
            }
        }
        var boolValue: Bool? {
            switch self {
            case .inherit: nil
            case .forcePrivate: true
            case .forceNormal: false
            }
        }
        static func from(_ value: Bool?) -> PrivateWindowOverride {
            switch value {
            case .none: .inherit
            case .some(true): .forcePrivate
            case .some(false): .forceNormal
            }
        }
    }

    private var installedApps: [(String, String)] {
        let handlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        return handlers.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier,
                  seen.insert(bundleId).inserted else { return nil }
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return (bundleId, name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Routing Rule")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    matchTypeField
                    patternField
                    targetAppField
                    priorityStripRow
                    sourceAppField
                    advancedTargetingFields
                    browserOptionsSection
                    liveTestSection
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Theme.bgApp.opacity(0), Theme.bgApp],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 20)
                .allowsHitTesting(false)
            }

            Divider().background(Theme.borderSubtle)
            HStack {
                ThemeButton("Cancel") { onDismiss() }
                Spacer()
                ThemeButton(editing == nil ? "Add Rule" : "Save", isPrimary: true) {
                    commit()
                }
                .disabled(name.isEmpty || pattern.isEmpty || targetBundleId.isEmpty
                          || (matchType == .regex && !RegexMatcher.isValid(pattern: pattern)))
                .opacity(name.isEmpty || pattern.isEmpty || targetBundleId.isEmpty
                         || (matchType == .regex && !RegexMatcher.isValid(pattern: pattern)) ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 560, idealHeight: 660, maxHeight: 800)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
        .onAppear {
            loadEditing()
            refreshTargetProfiles()
        }
        .onChange(of: targetBundleId) { _, _ in
            // New target → its profile list is different. Clear the rule's
            // profile override (the old ID won't apply to the new browser)
            // and reload.
            ruleProfileId = nil
            refreshTargetProfiles()
        }
    }

    private var nameField: some View {
        fieldRow("Name") {
            ThemeTextField(placeholder: "e.g. Work GitHub", text: $name)
        }
    }

    private var matchTypeField: some View {
        fieldRow("Match Type", helpText: HelpText.Pipeline.ruleMatchType) {
            Picker("", selection: $matchType) {
                ForEach(MatchType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Match type")
        }
    }

    @ViewBuilder
    private var patternField: some View {
        fieldRow("Pattern") {
            ThemeTextField(placeholder: "e.g. github.com/my-company", text: $pattern, isMono: true)
            if matchType == .regex && !pattern.isEmpty && !RegexMatcher.isValid(pattern: pattern) {
                Text("Invalid regex pattern")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.danger)
            }
        }
    }

    private var targetAppField: some View {
        fieldRow("Target App") {
            HStack(spacing: 8) {
                Picker("", selection: $targetBundleId) {
                    Text("Select...").tag("")
                    ForEach(installedApps, id: \.0) { bundleId, appName in
                        Text(appName).tag(bundleId)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Target application")
                .onChange(of: targetBundleId) { _, newValue in
                    targetAppName = installedApps.first(where: { $0.0 == newValue })?.1 ?? ""
                }
                ThemeButton("Choose App...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url,
                       let bundle = Bundle(url: url),
                       let bundleId = bundle.bundleIdentifier {
                        targetBundleId = bundleId
                        targetAppName = bundle.infoDictionary?["CFBundleName"] as? String
                            ?? url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        }
    }

    private var priorityStripRow: some View {
        HStack(spacing: 24) {
            fieldRow("Priority", helpText: HelpText.Pipeline.rulePriority) {
                HStack(spacing: 8) {
                    Text("\(priority)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                    Stepper("", value: $priority, in: 1...1000)
                        .labelsHidden()
                        .accessibilityLabel("Rule priority")
                }
            }
            fieldRow("Strip Trackers") {
                ThemeToggle(isOn: $stripUTMParams)
            }
        }
    }

    private var sourceAppField: some View {
        fieldRow("Source App (optional)", helpText: HelpText.Pipeline.ruleSourceApp) {
            HStack(spacing: 8) {
                ThemeTextField(placeholder: "com.apple.mail", text: $sourceAppBundleId, isMono: true)
                ThemeButton("Choose App\u{2026}") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url,
                       let bundle = Bundle(url: url),
                       let bundleId = bundle.bundleIdentifier {
                        sourceAppBundleId = bundleId
                    }
                }
            }
        }
    }

    /// Per-rule browser overrides: profile, private-window, custom launch args.
    /// Only surface this block when a target is picked — without a
    /// bundle ID there's nothing sensible to list profiles for.
    @ViewBuilder
    private var browserOptionsSection: some View {
        if !targetBundleId.isEmpty {
            Divider().background(Theme.borderSubtle).padding(.vertical, 4)
            Text("Browser options for this rule")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text("Overrides the target browser's defaults when this rule matches. Leave as \u{201C}Inherit\u{201D} to use whatever is configured on the Browsers tab.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !targetProfiles.isEmpty {
                fieldRow("Profile") {
                    Picker("", selection: $ruleProfileId) {
                        Text("Inherit from browser").tag(nil as String?)
                        ForEach(targetProfiles) { profile in
                            Text(profile.name).tag(profile.id as String?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Rule profile")
                }
            }

            if ProfileLaunchHelper.supportsPrivateWindow(browserBundleId: targetBundleId) {
                fieldRow("Window Type") {
                    Picker("", selection: $rulePrivateWindowOverride) {
                        ForEach(PrivateWindowOverride.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Window type for this rule")
                }
            }

            fieldRow("Custom Launch Args", helpText: HelpText.Browsers.customLaunchArgs) {
                HStack(spacing: 8) {
                    ThemeTextField(
                        placeholder: "Leave blank to inherit (use $URL for the link)",
                        text: $ruleCustomLaunchArgs,
                        isMono: true)
                }
            }
        }
    }

    @ViewBuilder
    private var advancedTargetingFields: some View {
        if isFirefoxTarget(targetBundleId) {
            fieldRow("Firefox Container (optional)") {
                ThemeTextField(placeholder: "Work", text: $firefoxContainer)
            }
        }
        fieldRow("Target Display (optional)") {
            Picker("", selection: $targetDisplayUUID) {
                Text("Any").tag(nil as String?)
                ForEach(DisplayManager.availableDisplays()) { display in
                    Text(display.name).tag(display.id as String?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var liveTestSection: some View {
        Divider().background(Theme.borderSubtle).padding(.vertical, 4)
        Text("Live test")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
        ThemeTextField(placeholder: "https://example.com/path to test match...", text: $testURL)
            .onChange(of: testURL) { _, _ in runLiveTest() }
            .onChange(of: pattern) { _, _ in runLiveTest() }
            .onChange(of: matchType) { _, _ in runLiveTest() }
        if !testResult.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(testMatched ? Theme.success : Theme.textSecondary)
                        .frame(width: 6, height: 6)
                    Text(testResult)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(testMatched ? Theme.success : Theme.textSecondary)
                }
                if !testExplanation.isEmpty {
                    Text(testExplanation)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func isFirefoxTarget(_ bundleId: String) -> Bool {
        ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]
            .contains(bundleId)
    }

    private func loadEditing() {
        guard let rule = editing else { return }
        name = rule.name
        matchType = rule.matchType
        pattern = rule.pattern
        targetBundleId = rule.targetBundleId
        targetAppName = rule.targetAppName
        priority = rule.priority
        stripUTMParams = rule.stripUTMParams
        sourceAppBundleId = rule.sourceAppBundleId ?? ""
        firefoxContainer = rule.firefoxContainer ?? ""
        targetDisplayUUID = rule.targetDisplayUUID
        ruleProfileId = rule.ruleProfileId
        rulePrivateWindowOverride = PrivateWindowOverride.from(rule.ruleOpenInPrivateWindow)
        ruleCustomLaunchArgs = rule.ruleCustomLaunchArgs ?? ""
    }

    /// Load profiles for the current target browser off the main thread —
    /// ChromiumProfileReader touches `~/Library/Application Support/<app>/`
    /// which can be slow on cold disk reads.
    private func refreshTargetProfiles() {
        let bundleId = targetBundleId
        guard !bundleId.isEmpty else { targetProfiles = []; return }
        let discovery = ProfileDiscovery()
        Task { @MainActor in
            let found = await Task.detached {
                discovery.discoverProfiles(for: bundleId)
            }.value
            // Race guard: ignore result if the user picked a different
            // target while we were fetching.
            if bundleId == targetBundleId {
                targetProfiles = found
            }
        }
    }

    private func commit() {
        let baseId = editing?.id ?? UUID()
        let trimmedArgs = ruleCustomLaunchArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = Rule(
            id: baseId,
            name: name, enabled: editing?.enabled ?? true,
            matchType: matchType,
            pattern: pattern, targetBundleId: targetBundleId,
            targetAppName: targetAppName,
            isBuiltIn: editing?.isBuiltIn ?? false,
            priority: priority, stripUTMParams: stripUTMParams,
            rewriteRules: editing?.rewriteRules ?? [],
            sourceAppBundleId: sourceAppBundleId.isEmpty ? nil : sourceAppBundleId,
            firefoxContainer: firefoxContainer.isEmpty ? nil : firefoxContainer,
            targetDisplayUUID: targetDisplayUUID,
            ruleProfileId: ruleProfileId,
            ruleOpenInPrivateWindow: rulePrivateWindowOverride.boolValue,
            ruleCustomLaunchArgs: trimmedArgs.isEmpty ? nil : trimmedArgs)
        if editing == nil {
            ruleEngine.addRule(rule)
        } else {
            ruleEngine.updateRule(rule)
        }
        onDismiss()
    }

    private func runLiveTest() {
        guard !testURL.isEmpty else {
            testResult = ""; testExplanation = ""; testMatched = false; return
        }
        guard let url = URL(string: testURL) else {
            testResult = "Invalid URL"
            testExplanation = "Could not parse \"\(testURL)\" as a URL."
            testMatched = false
            return
        }
        let testRule = Rule(
            name: name, matchType: matchType,
            pattern: pattern, targetBundleId: targetBundleId,
            targetAppName: targetAppName)
        let result = RuleMatcher.evaluate(url: url, against: testRule,
                                          sourceApp: sourceAppBundleId.isEmpty ? nil : sourceAppBundleId)
        testMatched = result.matched
        testResult = result.matched ? "Match (\(matchType.displayName))" : "No match"
        testExplanation = result.explanation
    }

    private func fieldRow<Content: View>(_ label: String, helpText: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                if let helpText {
                    ThemeHelpIcon(text: helpText)
                }
            }
            content()
        }
    }
}

// MARK: - Add Rewrite Sheet

struct AddRewriteSheet: View {
    let onAdd: (URLRewriteRule) -> Void
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var matchPattern = ""
    @State private var replacement = ""
    @State private var isRegex = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Rewrite Rule")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldRow("Name") {
                        ThemeTextField(placeholder: "e.g. Twitter to Nitter", text: $name)
                    }
                    fieldRow("Match Pattern", helpText: HelpText.Pipeline.rewriteMatch) {
                        ThemeTextField(placeholder: "^https://twitter\\.com/(.*)", text: $matchPattern, isMono: true)
                        if isRegex && !matchPattern.isEmpty && !RegexMatcher.isValid(pattern: matchPattern) {
                            Text("Invalid regex pattern")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.danger)
                        }
                    }
                    fieldRow("Replacement", helpText: HelpText.Pipeline.rewriteReplacement) {
                        ThemeTextField(placeholder: "https://nitter.net/$1", text: $replacement, isMono: true)
                    }
                    HStack {
                        Text("Is Regex")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        ThemeToggle(isOn: $isRegex)
                    }
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Theme.bgApp.opacity(0), Theme.bgApp],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 20)
                .allowsHitTesting(false)
            }

            Divider().background(Theme.borderSubtle)
            HStack {
                ThemeButton("Cancel") { onDismiss() }
                Spacer()
                ThemeButton("Add Rewrite", isPrimary: true) {
                    let rule = URLRewriteRule(
                        name: name, matchPattern: matchPattern,
                        replacement: replacement, isRegex: isRegex,
                        scope: .global)
                    onAdd(rule)
                    onDismiss()
                }
                .disabled(name.isEmpty || matchPattern.isEmpty
                          || (isRegex && !RegexMatcher.isValid(pattern: matchPattern)))
                .opacity(name.isEmpty || matchPattern.isEmpty
                         || (isRegex && !RegexMatcher.isValid(pattern: matchPattern)) ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 480, minHeight: 400, idealHeight: 500, maxHeight: 700)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
    }

    private func fieldRow<Content: View>(_ label: String, helpText: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                if let helpText {
                    ThemeHelpIcon(text: helpText)
                }
            }
            content()
        }
    }
}

// MARK: - Tracker Parameter List Sheet

struct TrackerParameterSheet: View {
    @ObservedObject var settingsStore: SettingsStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tracker Parameter List")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("URL parameters that get stripped when tracker removal is on. One per line.")
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
                .padding(8)
                .background(Theme.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            }
            .padding(24)

            Divider().background(Theme.borderSubtle)
            HStack {
                ThemeButton("Reset to Defaults") {
                    settingsStore.utmStripList = UTMStripper.defaultParameters
                }
                Spacer()
                ThemeButton("Done", isPrimary: true) { onDismiss() }
            }
            .padding(16)
        }
        .frame(width: 420, height: 400)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
    }
}
