import Foundation

struct ChromiumProfileReader {
    func readProfiles(appSupportPath: String, bundleId: String) -> [BrowserProfile] {
        let localStatePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportPath)
            .appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStatePath) else {
            YojamLogger.shared.log("ChromiumProfileReader: Local State not found at \(localStatePath.path)")
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileDict = json["profile"] as? [String: Any],
              let infoCache = profileDict["info_cache"] as? [String: [String: Any]]
        else {
            // Chrome writes Local State live; retry once on parse failure
            usleep(100_000)
            guard let retryData = try? Data(contentsOf: localStatePath),
                  let json = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any],
                  let profileDict = json["profile"] as? [String: Any],
                  let infoCache = profileDict["info_cache"] as? [String: [String: Any]]
            else {
                YojamLogger.shared.log("ChromiumProfileReader: Failed to parse Local State for \(bundleId)")
                return []
            }
            let lastUsed = profileDict["last_used"] as? String ?? "Default"
            return infoCache.compactMap { (dirName, info) -> BrowserProfile? in
                let rawName = info["name"] as? String ?? info["gaia_name"] as? String
                let name = rawName.flatMap { $0.isEmpty ? nil : $0 } ?? dirName
                let email = info["user_name"] as? String
                return BrowserProfile(id: dirName, name: name, email: email,
                                      browserBundleId: bundleId, isDefault: dirName == lastUsed)
            }.sorted { $0.name < $1.name }
        }
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
