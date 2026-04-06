import Foundation
import Combine

@MainActor
final class UTMStripper {
    private let settingsStore: SettingsStore

    static let defaultParameters: [String] = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_cid", "utm_reader", "utm_name", "utm_social", "utm_social-type",
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid",
        "msclkid", "twclkid", "li_fat_id",
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "hsCtaTracking",
        "oly_enc_id", "oly_anon_id", "__s", "vero_id",
        "ref", "ref_", "referrer", "source"
    ]

    // §35: Cache the strip set to avoid rebuilding on every URL
    private var cachedStripSet: Set<String>?
    private var cancellable: AnyCancellable?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.cancellable = settingsStore.$utmStripList.sink { [weak self] _ in
            self?.cachedStripSet = nil
        }
    }

    func strip(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems, !queryItems.isEmpty else { return url }
        let parametersToStrip: Set<String>
        if let cached = cachedStripSet {
            parametersToStrip = cached
        } else {
            let built = Set(settingsStore.utmStripList.map { $0.lowercased() })
            cachedStripSet = built
            parametersToStrip = built
        }
        let filteredItems = queryItems.filter { !parametersToStrip.contains($0.name.lowercased()) }
        guard filteredItems.count < queryItems.count else { return url }
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        return components.url ?? url
    }
}
