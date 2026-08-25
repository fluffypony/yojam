import Foundation

struct ChromiumProfileReader: Sendable {
    private let applicationSupportDirectory: URL

    init(
        applicationSupportDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    func readProfiles(
        appSupportPath: String,
        bundleId: String,
        userDataDirectory: String? = nil
    ) -> [BrowserProfile] {
        let localStatePath = userDataRoot(
            appSupportPath: appSupportPath,
            userDataDirectory: userDataDirectory)
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

    private func userDataRoot(
        appSupportPath: String,
        userDataDirectory: String?
    ) -> URL {
        if let userDataDirectory,
           !userDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: expandedPath(userDataDirectory))
        }
        return applicationSupportDirectory
            .appendingPathComponent(appSupportPath)
    }

    private func expandedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return home + String(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("$HOME/") {
            return home + String(trimmed.dropFirst("$HOME".count))
        }
        return trimmed
    }
}
