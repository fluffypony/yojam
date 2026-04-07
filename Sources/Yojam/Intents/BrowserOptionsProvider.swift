import AppIntents
import YojamCore

struct BrowserOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let store = SharedRoutingStore()
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: store) else { return [] }
        return config.browsers.map(\.bundleIdentifier)
    }

    @MainActor
    func defaultResult() async -> String? {
        let store = SharedRoutingStore()
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: store) else { return nil }
        return config.browsers.first?.bundleIdentifier
    }
}
