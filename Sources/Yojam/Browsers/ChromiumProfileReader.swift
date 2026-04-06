import Foundation

struct ChromiumProfileReader {
    func readProfiles(appSupportPath: String, bundleId: String) -> [BrowserProfile] {
        let localStatePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportPath)
            .appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileDict = json["profile"] as? [String: Any],
              let infoCache = profileDict["info_cache"] as? [String: [String: Any]]
        else { return [] }
        // "profile.last_used" identifies which profile opens on launch
        let lastUsed = profileDict["last_used"] as? String ?? "Default"
        return infoCache.compactMap { (dirName, info) -> BrowserProfile? in
            let rawName = info["name"] as? String
                ?? info["gaia_name"] as? String
            let name = rawName.flatMap { $0.isEmpty ? nil : $0 } ?? dirName
            let email = info["user_name"] as? String
            return BrowserProfile(
                id: dirName, name: name, email: email,
                browserBundleId: bundleId,
                isDefault: dirName == lastUsed
            )
        }.sorted { $0.name < $1.name }
    }
}
