import Foundation

struct ChromiumProfileReader {
    func readProfiles(appSupportPath: String, bundleId: String) -> [BrowserProfile] {
        let localStatePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportPath)
            .appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }
        return infoCache.compactMap { (dirName, info) -> BrowserProfile? in
            let name = info["name"] as? String
                ?? info["gaia_name"] as? String ?? dirName
            let email = info["user_name"] as? String
            return BrowserProfile(
                id: dirName, name: name, email: email, browserBundleId: bundleId
            )
        }.sorted { $0.name < $1.name }
    }
}
