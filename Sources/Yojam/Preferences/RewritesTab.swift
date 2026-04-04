import SwiftUI

struct RewritesTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var rewriteManager: URLRewriter
    @State private var rules: [URLRewriteRule] = []
    @State private var testURL = ""
    @State private var testResult = ""
    @State private var showingAddRewrite = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Test URL:", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                Button("Preview") {
                    guard let url = URL(string: testURL) else {
                        testResult = "Invalid"; return
                    }
                    let result = rewriteManager.applyGlobalRewrites(to: url)
                    testResult = result.absoluteString == testURL
                        ? "No changes"
                        : "-> \(result.absoluteString)"
                }
            }.padding()
            if !testResult.isEmpty {
                Text(testResult).font(.caption).padding(.horizontal)
            }
            List {
                ForEach(rules) { rule in
                    HStack {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { rule.enabled },
                                set: { _ in toggleRewrite(rule.id) }
                            )
                        ).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(rule.name).fontWeight(.medium)
                            Text("\(rule.matchPattern) -> \(rule.replacement)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteRewrite(rule.id)
                        } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }.opacity(rule.enabled ? 1 : 0.5)
                }
            }
            HStack {
                Button("Add Rewrite") { showingAddRewrite = true }
                Spacer()
            }.padding()
        }
        .onAppear { rules = settingsStore.loadGlobalRewriteRules() }
        .sheet(isPresented: $showingAddRewrite) {
            AddRewriteSheet(onAdd: { rule in
                rules.append(rule)
                settingsStore.saveGlobalRewriteRules(rules)
            }, onDismiss: { showingAddRewrite = false })
        }
    }

    private func toggleRewrite(_ id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle()
            settingsStore.saveGlobalRewriteRules(rules)
        }
    }

    private func deleteRewrite(_ id: UUID) {
        rules.removeAll { $0.id == id }
        settingsStore.saveGlobalRewriteRules(rules)
    }
}

struct AddRewriteSheet: View {
    let onAdd: (URLRewriteRule) -> Void
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var matchPattern = ""
    @State private var replacement = ""
    @State private var isRegex = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name:", text: $name)
                TextField("Match Pattern:", text: $matchPattern)
                TextField("Replacement:", text: $replacement)
                Toggle("Is Regex", isOn: $isRegex)
            }.formStyle(.grouped)

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let rule = URLRewriteRule(
                        name: name, matchPattern: matchPattern,
                        replacement: replacement, isRegex: isRegex,
                        scope: .global)
                    onAdd(rule)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || matchPattern.isEmpty)
            }.padding()
        }
        .frame(minWidth: 400, minHeight: 250)
    }
}
