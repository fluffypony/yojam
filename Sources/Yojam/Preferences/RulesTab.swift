import SwiftUI
import UniformTypeIdentifiers

struct RulesTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    @State private var testURL = ""
    @State private var testResult = ""
    @State private var showingAddRule = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Test URL:", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                Button("Test") {
                    guard let url = URL(string: testURL) else {
                        testResult = "Invalid URL"; return
                    }
                    if let match = ruleEngine.evaluate(url) {
                        testResult = "\(match.name) -> \(match.targetAppName)"
                    } else {
                        testResult = "No match"
                    }
                }
            }.padding()
            if !testResult.isEmpty {
                Text(testResult).font(.caption).padding(.horizontal)
            }
            List {
                Section("Your Rules") {
                    ForEach(ruleEngine.rules.filter({ !$0.isBuiltIn })) {
                        rule in
                        HStack {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { rule.enabled },
                                    set: { _ in
                                        ruleEngine.toggleRule(rule.id)
                                    }
                                )
                            ).labelsHidden()
                            VStack(alignment: .leading) {
                                Text(rule.name).fontWeight(.medium)
                                Text(rule.pattern)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("-> \(rule.targetAppName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let src = rule.sourceAppName {
                                Text("from \(src)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            Button(role: .destructive) {
                                ruleEngine.deleteRule(rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Built-in Rules") {
                    ForEach(ruleEngine.rules.filter(\.isBuiltIn)) { rule in
                        HStack {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { rule.enabled },
                                    set: { _ in
                                        ruleEngine.toggleRule(rule.id)
                                    }
                                )
                            ).labelsHidden()
                            Text(rule.name); Spacer()
                            Text(rule.targetAppName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }.opacity(rule.enabled ? 1 : 0.5)
                    }
                }
            }
            HStack {
                Button("Add Rule") { showingAddRule = true }
                Spacer()
                Button("Import...") {
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
                Button("Export...") {
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
            }.padding()
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(ruleEngine: ruleEngine, onDismiss: { showingAddRule = false })
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
}

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
        return handlers.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return nil }
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return (bundleId, name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name:", text: $name)
                Picker("Match Type:", selection: $matchType) {
                    ForEach(MatchType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Pattern:", text: $pattern)
                Picker("Target App:", selection: $targetBundleId) {
                    Text("Select...").tag("")
                    ForEach(installedApps, id: \.0) { bundleId, appName in
                        Text(appName).tag(bundleId)
                    }
                }.onChange(of: targetBundleId) { _, newValue in
                    targetAppName = installedApps.first(where: { $0.0 == newValue })?.1 ?? ""
                }
                Stepper("Priority: \(priority)", value: $priority, in: 1...1000)
                Toggle("Strip UTM Parameters", isOn: $stripUTMParams)
                TextField("Source App (optional):", text: $sourceAppBundleId)
                    .textFieldStyle(.roundedBorder)

                Section("Test") {
                    HStack {
                        TextField("Test URL:", text: $testURL)
                            .textFieldStyle(.roundedBorder)
                        Button("Test") {
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
                        Text(testResult).font(.caption)
                    }
                }
            }.formStyle(.grouped)

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let rule = Rule(
                        name: name, matchType: matchType,
                        pattern: pattern, targetBundleId: targetBundleId,
                        targetAppName: targetAppName,
                        priority: priority, stripUTMParams: stripUTMParams,
                        sourceAppBundleId: sourceAppBundleId.isEmpty ? nil : sourceAppBundleId)
                    ruleEngine.addRule(rule)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || pattern.isEmpty || targetBundleId.isEmpty)
            }.padding()
        }
        .frame(minWidth: 450, minHeight: 400)
    }
}
