import Foundation

struct OrionProfileReader {
    func readProfiles(bundleId: String) -> [BrowserProfile] {
        let profilesIni = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Orion/Defaults/profiles.ini")
        guard let content = try? String(contentsOf: profilesIni, encoding: .utf8)
        else { return [] }
        var profiles: [BrowserProfile] = []
        var currentName: String?
        var currentPath: String?
        var inProfile = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Profile") {
                if inProfile, let name = currentName, let path = currentPath {
                    profiles.append(BrowserProfile(
                        id: path, name: name, browserBundleId: bundleId))
                }
                inProfile = true; currentName = nil; currentPath = nil
            } else if trimmed.hasPrefix("Name=") {
                currentName = String(trimmed.dropFirst(5))
            } else if trimmed.hasPrefix("Path=") {
                currentPath = String(trimmed.dropFirst(5))
            }
        }
        if inProfile, let name = currentName, let path = currentPath {
            profiles.append(BrowserProfile(
                id: path, name: name, browserBundleId: bundleId))
        }
        return profiles
    }
}
