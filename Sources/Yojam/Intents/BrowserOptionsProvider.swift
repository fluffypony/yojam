import AppIntents
import YojamCore

struct BrowserOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        SettingsStore().loadBrowsers().filter(\.enabled)
            .map(\.bundleIdentifier)
    }

    @MainActor
    func defaultResult() async -> String? {
        SettingsStore().loadBrowsers().first(where: \.enabled)?.bundleIdentifier
    }
}
