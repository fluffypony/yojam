import SwiftUI

struct RewritesTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var rewriteManager: URLRewriter
    @State private var rules: [URLRewriteRule] = []
    @State private var testURL = ""
    @State private var testResult = ""

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
                    }.opacity(rule.enabled ? 1 : 0.5)
                }
            }
        }.onAppear { rules = settingsStore.loadGlobalRewriteRules() }
    }

    private func toggleRewrite(_ id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle()
            settingsStore.saveGlobalRewriteRules(rules)
        }
    }
}
