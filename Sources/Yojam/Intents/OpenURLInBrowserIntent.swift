import AppIntents
import AppKit

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
        let store = SettingsStore()
        let rewriter = URLRewriter(settingsStore: store)
        let stripper = UTMStripper(settingsStore: store)
        var processedURL = url

        // §13: Apply global rewrites (previously skipped by intents)
        processedURL = rewriter.applyGlobalRewrites(to: processedURL)

        if let bundleId = browser {
            let entry = store.loadBrowsers().first {
                $0.bundleIdentifier == bundleId && $0.enabled
            }

            if let entry {
                processedURL = rewriter.applyBrowserRewrites(to: processedURL, browser: entry)
                if stripUTM || entry.stripUTMParams {
                    processedURL = stripper.strip(processedURL)
                } else if store.globalUTMStrippingEnabled {
                    processedURL = stripper.strip(processedURL)
                }
            } else if stripUTM || store.globalUTMStrippingEnabled {
                processedURL = stripper.strip(processedURL)
            }

            // §13: Delegate to AppDelegate for full launch path (private window, custom args)
            if let delegate = NSApp.delegate as? AppDelegate {
                let appURL = delegate.appURL(for: bundleId)
                if let appURL {
                    delegate.openURL(
                        processedURL,
                        withAppAt: appURL,
                        profile: entry?.profileId,
                        bundleId: bundleId,
                        privateWindow: entry?.openInPrivateWindow ?? false,
                        customLaunchArgs: entry?.customLaunchArgs)
                    return .result()
                }
            }

            // Fallback: NSWorkspace open
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId
            ) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                var arguments: [String] = []
                if let profile = entry?.profileId {
                    arguments.append(contentsOf: ProfileLaunchHelper.launchArguments(
                        forProfile: profile, browserBundleId: bundleId))
                }
                if entry?.openInPrivateWindow == true {
                    arguments.append(contentsOf: ProfileLaunchHelper.privateWindowArguments(
                        browserBundleId: bundleId))
                }
                if !arguments.isEmpty { config.arguments = arguments }
                try await NSWorkspace.shared.open(
                    [processedURL], withApplicationAt: appURL,
                    configuration: config)
            }
        } else if let delegate = NSApp.delegate as? AppDelegate {
            delegate.routeURL(processedURL)
        }
        return .result()
    }
}
