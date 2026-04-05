import SwiftUI
import UniformTypeIdentifiers

struct PipelineTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var rewriteManager: URLRewriter
    @ObservedObject var browserManager: BrowserManager
    @Binding var scrollToSection: String?

    @State private var testURL = ""
    @State private var testPipeline: [PipelineNode] = []
    @State private var rewriteRules: [URLRewriteRule] = []
    @State private var showingAddRule = false
    @State private var showingAddRewrite = false
    @State private var showingTrackerList = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(
                title: "URL Pipeline",
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
                        testerSection.id("URL Tester")
                        globalProcessingSection.id("Global Processing")
                        pipelineTableSection.id("Pipeline")
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
        .onAppear { rewriteRules = settingsStore.loadGlobalRewriteRules() }
        .onReceive(settingsStore.objectWillChange) {
            rewriteRules = settingsStore.loadGlobalRewriteRules()
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(ruleEngine: ruleEngine, onDismiss: { showingAddRule = false })
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

    // MARK: - URL Tester

    private var testerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ThemeTextField(placeholder: "Paste a URL here to test...", text: $testURL)
                ThemeButton("Test") { runTest() }
            }

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
            }
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
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strip Tracking Parameters")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Automatically remove tracking parameters (utm_*, gclid, fbclid) from all URLs before routing.")
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
            ThemeSectionTitle(text: "Routing & Transformation Pipeline (Executed top to bottom)")
            ThemePanel {
                // Table header
                HStack(spacing: 0) {
                    Text("").frame(width: 30) // drag
                    Text("STATUS").frame(width: 50, alignment: .leading)
                    Text("TYPE").frame(width: 80, alignment: .leading)
                    Text("PATTERN MATCH").frame(minWidth: 150, alignment: .leading)
                    Spacer()
                    Text("ACTION / TARGET").frame(width: 150, alignment: .leading)
                    Text("").frame(width: 60) // controls
                }
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.bgPanel)

                Divider().background(Theme.borderSubtle)

                // Rewrite rules
                ForEach(Array(rewriteRules.enumerated()), id: \.element.id) { index, rule in
                    VStack(spacing: 0) {
                        pipelineRewriteRow(rule: rule, index: index)
                        Divider().background(Theme.borderSubtle)
                    }
                }

                // Routing rules
                let userRules = ruleEngine.rules.filter { !$0.isBuiltIn }
                let builtInRules = ruleEngine.rules.filter(\.isBuiltIn)

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

            // Import/Export
            HStack(spacing: 8) {
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

            // Toggle
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in toggleRewrite(rule.id) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
            .scaleEffect(0.7)
            .frame(width: 50, alignment: .leading)

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
                ThemeIconButton(systemName: "square.and.pencil") {
                    // Edit - future enhancement
                }
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

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in ruleEngine.toggleRule(rule.id) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
            .scaleEffect(0.7)
            .frame(width: 50, alignment: .leading)

            ThemeBadge(text: "Rule", isRewrite: false)
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
                if !rule.isBuiltIn {
                    ThemeIconButton(systemName: "square.and.pencil") {
                        // Edit - future enhancement
                    }
                    ThemeIconButton(systemName: "trash", isDanger: true) {
                        ruleEngine.deleteRule(rule.id)
                    }
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(rule.enabled ? 1 : 0.5)
    }

    // MARK: - Test Logic

    private func runTest() {
        var input = testURL
        if !input.contains("://") { input = "https://" + input }
        guard let url = URL(string: input) else {
            testPipeline = [PipelineNode(label: "Invalid URL", isActive: false, isFinal: false)]
            return
        }

        var nodes: [PipelineNode] = []
        nodes.append(PipelineNode(label: "Input URL"))
        nodes.append(.arrow)

        var processedURL = url

        // UTM stripping
        if settingsStore.globalUTMStrippingEnabled {
            let stripped = UTMStripper(settingsStore: settingsStore).strip(processedURL)
            let didStrip = stripped.absoluteString != processedURL.absoluteString
            nodes.append(PipelineNode(label: "Strip Trackers", icon: "xmark.rectangle", isActive: didStrip))
            nodes.append(.arrow)
            processedURL = stripped
        }

        // Rewrite rules
        let rewritten = rewriteManager.applyGlobalRewrites(to: processedURL)
        if rewritten.absoluteString != processedURL.absoluteString {
            nodes.append(PipelineNode(label: "Rewrite", icon: "arrow.2.squarepath", isActive: true))
            nodes.append(.arrow)
            processedURL = rewritten
        }

        // Rule matching
        if let match = ruleEngine.rules.filter(\.enabled).first(
            where: { ruleEngine.matches(url: processedURL, rule: $0) }
        ) {
            let host = processedURL.host ?? ""
            nodes.append(PipelineNode(label: "Match: \(host)", icon: "globe", isActive: true))
            nodes.append(.arrow)
            nodes.append(PipelineNode(label: "Open in: \(match.targetAppName)", isFinal: true))
        } else {
            nodes.append(PipelineNode(label: "No match", icon: "questionmark.circle"))
            nodes.append(.arrow)
            nodes.append(PipelineNode(label: "Show picker", isFinal: true))
        }

        testPipeline = nodes
    }

    // MARK: - Rewrite Helpers

    private func toggleRewrite(_ id: UUID) {
        if let idx = rewriteRules.firstIndex(where: { $0.id == id }) {
            rewriteRules[idx].enabled.toggle()
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

// MARK: - Add Rule Sheet (restyled)

struct AddRuleSheet: View {
    @ObservedObject var ruleEngine: RuleEngine
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var matchType: MatchType = .domain
    @State private var pattern = ""
    @State private var targetBundleId = ""
    @State private var targetAppName = ""
    @State private var priority = 100
    @State private var stripUTMParams = false
    @State private var sourceAppBundleId = ""
    @State private var testURL = ""
    @State private var testResult = ""

    private var installedApps: [(String, String)] {
        let handlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        return handlers.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  seen.insert(bundleId).inserted else { return nil }
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return (bundleId, name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                    fieldRow("Name") {
                        ThemeTextField(placeholder: "e.g. Work GitHub", text: $name)
                    }
                    fieldRow("Match Type") {
                        Picker("", selection: $matchType) {
                            ForEach(MatchType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    fieldRow("Pattern") {
                        ThemeTextField(placeholder: "e.g. github.com/my-company/*", text: $pattern, isMono: true)
                    }
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
                    HStack(spacing: 24) {
                        fieldRow("Priority") {
                            HStack(spacing: 8) {
                                Text("\(priority)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Theme.textPrimary)
                                Stepper("", value: $priority, in: 1...1000)
                                    .labelsHidden()
                            }
                        }
                        fieldRow("Strip Trackers") {
                            ThemeToggle(isOn: $stripUTMParams)
                        }
                    }
                    fieldRow("Source App (optional)") {
                        ThemeTextField(placeholder: "com.apple.mail", text: $sourceAppBundleId, isMono: true)
                    }

                    // Test section
                    Divider().background(Theme.borderSubtle).padding(.vertical, 4)
                    HStack(spacing: 8) {
                        ThemeTextField(placeholder: "Test URL...", text: $testURL)
                        ThemeButton("Test") {
                            guard let url = URL(string: testURL) else {
                                testResult = "Invalid URL"; return
                            }
                            let testRule = Rule(
                                name: name, matchType: matchType,
                                pattern: pattern, targetBundleId: targetBundleId,
                                targetAppName: targetAppName)
                            testResult = ruleEngine.matches(url: url, rule: testRule)
                                ? "Match" : "No match"
                        }
                    }
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(testResult == "Match" ? Theme.success : Theme.textSecondary)
                    }
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)
            HStack {
                ThemeButton("Cancel") { onDismiss() }
                Spacer()
                ThemeButton("Add Rule", isPrimary: true) {
                    let rule = Rule(
                        name: name, matchType: matchType,
                        pattern: pattern, targetBundleId: targetBundleId,
                        targetAppName: targetAppName,
                        priority: priority, stripUTMParams: stripUTMParams,
                        sourceAppBundleId: sourceAppBundleId.isEmpty ? nil : sourceAppBundleId)
                    ruleEngine.addRule(rule)
                    onDismiss()
                }
                .opacity(name.isEmpty || pattern.isEmpty || targetBundleId.isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 520, height: 520)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            content()
        }
    }
}

// MARK: - Add Rewrite Sheet (restyled)

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

            VStack(alignment: .leading, spacing: 16) {
                fieldRow("Name") {
                    ThemeTextField(placeholder: "e.g. Twitter to Nitter", text: $name)
                }
                fieldRow("Match Pattern") {
                    ThemeTextField(placeholder: "^https://twitter\\.com/(.*)", text: $matchPattern, isMono: true)
                }
                fieldRow("Replacement") {
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

            Spacer()

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
                .opacity(name.isEmpty || matchPattern.isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 480, height: 400)
        .background(Theme.bgApp)
        .preferredColorScheme(.dark)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
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
                Text("One parameter per line. These are stripped from URLs when tracking parameter removal is enabled.")
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
