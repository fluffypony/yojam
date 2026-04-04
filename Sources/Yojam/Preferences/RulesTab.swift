import SwiftUI

struct RulesTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    @State private var testURL = ""
    @State private var testResult = ""
    @State private var showingAddRule = false

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
            }.padding()
        }
    }
}
