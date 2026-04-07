import AppIntents
import YojamCore

struct ApplyURLRulesIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply URL Rules"
    static let description: IntentDescription = IntentDescription(
        "Returns which browser/app a URL would be routed to")

    @Parameter(title: "URL") var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Use the unified routing pipeline via RoutingService.decide
        // instead of calling ruleEngine.evaluate directly.
        let sharedStore = SharedRoutingStore()
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: sharedStore) else {
            return .result(value: "Cannot load routing configuration")
        }
        let request = IncomingLinkRequest(
            url: url,
            origin: .urlScheme
        )
        let decision = RoutingService.decide(request: request, configuration: config)
        let preview = RouteDecisionPreview.from(decision)
        return .result(value: preview.summary)
    }
}

struct GetBrowserListIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Browser List"
    static let description: IntentDescription = IntentDescription(
        "Returns the user's configured browser list")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let sharedStore = SharedRoutingStore()
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: sharedStore) else {
            return .result(value: [])
        }
        return .result(
            value: config.browsers.map {
                "\($0.displayName) (\($0.bundleIdentifier))"
            })
    }
}
