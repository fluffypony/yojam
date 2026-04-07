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
    @Parameter(title: "Strip Tracking Parameters", default: false)
    var stripUTM: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result()
        }

        // Route through the unified ingress coordinator instead of
        // partially re-implementing the routing pipeline.
        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: nil,
            origin: .intent,
            forcedBrowserBundleId: browser,
            forcePicker: false,
            forcePrivateWindow: false
        )

        // Use routeURL directly since enqueueOrHandle is private.
        // The intent runs after launch, so isFinishedLaunching is true.
        if let bundleId = browser {
            delegate.routeURL(url, forcedBrowserBundleId: bundleId)
        } else {
            delegate.routeURL(url)
        }

        return .result()
    }
}
