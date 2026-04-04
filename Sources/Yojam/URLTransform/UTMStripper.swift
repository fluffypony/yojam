import Foundation

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

    init(settingsStore: SettingsStore) { self.settingsStore = settingsStore }

    func strip(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems, !queryItems.isEmpty else { return url }
        let parametersToStrip = Set(settingsStore.utmStripList)
        let filteredItems = queryItems.filter { !parametersToStrip.contains($0.name) }
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        return components.url ?? url
    }
}
