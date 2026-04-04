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
        var processedURL = url
        if stripUTM {
            let store = SettingsStore()
            processedURL = UTMStripper(settingsStore: store).strip(processedURL)
        }
        if let bundleId = browser,
           let appURL = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: bundleId
           ) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await NSWorkspace.shared.open(
                [processedURL], withApplicationAt: appURL,
                configuration: config)
        } else if let delegate = NSApp.delegate as? AppDelegate {
            delegate.routeURL(processedURL)
        }
        return .result()
    }
}
