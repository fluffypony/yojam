import AppIntents
import AppKit
import YojamCore

struct OpenURLInBrowserIntent: AppIntent {
    static let title: LocalizedStringResource = "Open URL in Browser"
    static let description: IntentDescription = IntentDescription(
        "Opens a URL in a specific browser via Yojam")

    @Parameter(title: "URL") var url: URL
    @Parameter(title: "Browser", optionsProvider: BrowserOptionsProvider())
    var browser: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result()
        }

        let request = IncomingLinkRequest(
            url: url,
            origin: .intent,
            forcedBrowserBundleId: browser,
            forcePrivateWindow: false
        )
        delegate.routeIncomingRequest(request)

        return .result()
    }
}
