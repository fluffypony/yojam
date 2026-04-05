import AppIntents

struct ApplyURLRulesIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply URL Rules"
    static let description: IntentDescription = IntentDescription(
        "Returns which browser/app a URL would be routed to")

    @Parameter(title: "URL") var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = SettingsStore()
        // §14: Apply global rewrites and UTM stripping before rule evaluation
        var processedURL = url
        processedURL = URLRewriter(settingsStore: store).applyGlobalRewrites(to: processedURL)
        if store.globalUTMStrippingEnabled {
            processedURL = UTMStripper(settingsStore: store).strip(processedURL)
        }
        let engine = RuleEngine(settingsStore: store)
        if let rule = engine.evaluate(processedURL) {
            return .result(
                value: "\(rule.targetAppName) (\(rule.targetBundleId))")
        }
        return .result(value: "No rule matched")
    }
}

struct GetBrowserListIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Browser List"
    static let description: IntentDescription = IntentDescription(
        "Returns the user's configured browser list")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let browsers = SettingsStore().loadBrowsers().filter(\.enabled)
        return .result(
            value: browsers.map {
                "\($0.displayName) (\($0.bundleIdentifier))"
            })
    }
}
