import Foundation

struct FirefoxProfileReader {
    func readProfiles(bundleId: String) -> [BrowserProfile] {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox")
        let profilesIni = profilesDir.appendingPathComponent("profiles.ini")
        guard let content = try? String(contentsOf: profilesIni, encoding: .utf8)
        else { return [] }
        var profiles: [BrowserProfile] = []
        var currentName: String?
        var currentPath: String?
        var currentIsRelative: Bool = true
        var inProfile = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Profile") {
                if inProfile, let name = currentName, currentPath != nil {
                    // Use profile name as ID since -P expects the name, not the path
                    profiles.append(BrowserProfile(
                        id: name, name: name, browserBundleId: bundleId))
                }
                inProfile = true; currentName = nil; currentPath = nil; currentIsRelative = true
            } else if trimmed.hasPrefix("Name=") {
                currentName = String(trimmed.dropFirst(5))
            } else if trimmed.hasPrefix("Path=") {
                currentPath = String(trimmed.dropFirst(5))
            } else if trimmed.hasPrefix("IsRelative=") {
                currentIsRelative = String(trimmed.dropFirst(11)) == "1"
            }
        }
        if inProfile, let name = currentName, currentPath != nil {
            profiles.append(BrowserProfile(
                id: name, name: name, browserBundleId: bundleId))
        }
        return profiles
    }
}
