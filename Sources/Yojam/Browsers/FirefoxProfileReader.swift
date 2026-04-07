import Foundation

struct FirefoxProfileReader {
    func readProfiles(bundleId: String) -> [BrowserProfile] {
        let appSupportName: String
        switch bundleId {
        case "org.mozilla.firefoxdeveloperedition": appSupportName = "Firefox Developer Edition"
        case "org.mozilla.nightly":                 appSupportName = "Firefox Nightly"
        default:                                    appSupportName = "Firefox"
        }
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportName)
        let profilesIni = profilesDir.appendingPathComponent("profiles.ini")
        guard let content = try? String(contentsOf: profilesIni, encoding: .utf8)
        else {
            YojamLogger.shared.log("FirefoxProfileReader: profiles.ini not found at \(profilesIni.path)")
            return []
        }

        // Parse all sections
        var sections: [(header: String, entries: [String: String])] = []
        var currentHeader = ""
        var currentEntries: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(";") || trimmed.hasPrefix("#") { continue } // INI comments
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if !currentHeader.isEmpty {
                    sections.append((currentHeader, currentEntries))
                }
                currentHeader = String(trimmed.dropFirst().dropLast())
                currentEntries = [:]
            } else if let eqIdx = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eqIdx])
                let value = String(trimmed[trimmed.index(after: eqIdx)...])
                currentEntries[key] = value
            }
        }
        if !currentHeader.isEmpty {
            sections.append((currentHeader, currentEntries))
        }

        // Find the default profile path from [Install*] sections (Firefox 67+).
        // Falls back to [Profile*] with Default=1.
        var defaultPath: String?
        for (header, entries) in sections where header.hasPrefix("Install") {
            if let path = entries["Default"] {
                defaultPath = path; break
            }
        }

        var profiles: [BrowserProfile] = []
        for (header, entries) in sections where header.hasPrefix("Profile") {
            guard let name = entries["Name"], let path = entries["Path"],
                  !name.isEmpty else { continue }
            let isDefault: Bool
            if let dp = defaultPath {
                isDefault = (path == dp)
            } else {
                isDefault = (entries["Default"] == "1")
            }
            profiles.append(BrowserProfile(
                id: name, name: name, browserBundleId: bundleId,
                isDefault: isDefault))
        }
        return profiles
    }
}
