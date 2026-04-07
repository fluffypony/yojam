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

        if let bundleId = browser {
            // When a specific browser is requested, apply UTM stripping
            // per the intent parameter before routing.
            var processedURL = url
            let store = delegate.settingsStore
            let rewriter = delegate.urlRewriter
            let stripper = delegate.utmStripper

            processedURL = rewriter.applyGlobalRewrites(to: processedURL)

            let entry = store.loadBrowsers().first {
                $0.bundleIdentifier == bundleId && $0.enabled
            }
            if let entry {
                processedURL = rewriter.applyBrowserRewrites(
                    to: processedURL, browser: entry)
            }

            if stripUTM || (entry?.stripUTMParams ?? false)
                || store.globalUTMStrippingEnabled {
                processedURL = stripper.strip(processedURL)
            }

            // Delegate to routeURL with the forced browser
            delegate.routeURL(processedURL, forcedBrowserBundleId: bundleId)
        } else {
            // No browser specified — full routing pipeline
            delegate.routeURL(url)
        }

        return .result()
    }
}
