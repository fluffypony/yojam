import AppKit
import Foundation

struct FirefoxProfileReader: Sendable {
    private let applicationSupportDirectory: URL
    private let firefoxVersionProvider: @Sendable (String) -> String?

    init(
        applicationSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support"),
        firefoxVersionProvider: @escaping @Sendable (String) -> String? = FirefoxProfileReader
            .installedFirefoxVersion(bundleId:)
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.firefoxVersionProvider = firefoxVersionProvider
    }

    func readProfiles(bundleId: String) -> [BrowserProfile] {
        let appSupportName: String
        switch bundleId {
        case "org.mozilla.firefoxdeveloperedition": appSupportName = "Firefox Developer Edition"
        case "org.mozilla.nightly":                 appSupportName = "Firefox Nightly"
        default:                                    appSupportName = "Firefox"
        }
        let profilesDir = applicationSupportDirectory
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
        var defaultPaths = Set<String>()
        for (header, entries) in sections where header.hasPrefix("Install") {
            if let path = entries["Default"] {
                defaultPaths.insert(path)
            }
        }

        let profileGroupsDir = profilesDir.appendingPathComponent("Profile Groups")
        let hasSelectableProfileStore = FileManager.default.fileExists(
            atPath: profileGroupsDir.path)
        let supportsSelectableProfiles = Self.supportsSelectableProfiles(
            versionString: firefoxVersionProvider(bundleId))

        var profiles: [BrowserProfile] = []
        for (header, entries) in sections where header.hasPrefix("Profile") {
            guard let name = entries["Name"], let path = entries["Path"],
                  !name.isEmpty else { continue }
            let profileURL = resolvedProfileURL(
                path: path, entries: entries, profilesDir: profilesDir)
            let storeID = value(in: entries, caseInsensitiveKey: "StoreID")
            let shouldUsePathId = shouldUseSelectableProfilePath(
                entries: entries,
                hasSelectableProfileStore: hasSelectableProfileStore,
                supportsSelectableProfiles: supportsSelectableProfiles)
            let profileId = shouldUsePathId && storeID?.isEmpty == false
                ? profileURL.path
                : name
            let isDefault: Bool
            if !defaultPaths.isEmpty {
                isDefault = defaultPaths.contains(path)
            } else {
                isDefault = (entries["Default"] == "1")
            }
            profiles.append(BrowserProfile(
                id: profileId, name: name, browserBundleId: bundleId,
                isDefault: isDefault))
        }
        return profiles
    }

    func selectableProfilePath(named name: String, bundleId: String) -> String? {
        readProfiles(bundleId: bundleId).first { profile in
            profile.name == name && profile.id.hasPrefix("/")
        }?.id
    }

    private func shouldUseSelectableProfilePath(
        entries: [String: String],
        hasSelectableProfileStore: Bool,
        supportsSelectableProfiles: Bool
    ) -> Bool {
        guard let storeID = value(in: entries, caseInsensitiveKey: "StoreID"),
              !storeID.isEmpty else { return false }
        if supportsSelectableProfiles { return true }
        if value(in: entries, caseInsensitiveKey: "ShowSelector") == "1" {
            return true
        }
        return hasSelectableProfileStore
    }

    private func resolvedProfileURL(
        path: String,
        entries: [String: String],
        profilesDir: URL
    ) -> URL {
        let isRelative = entries["IsRelative"] != "0"
        if isRelative {
            return URL(fileURLWithPath: path, relativeTo: profilesDir)
                .standardizedFileURL
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func value(
        in entries: [String: String],
        caseInsensitiveKey target: String
    ) -> String? {
        entries.first { key, _ in
            key.caseInsensitiveCompare(target) == .orderedSame
        }?.value
    }

    static func supportsSelectableProfiles(versionString: String?) -> Bool {
        guard let majorVersion = majorVersion(from: versionString) else {
            return false
        }
        return majorVersion >= 138
    }

    private static func majorVersion(from versionString: String?) -> Int? {
        guard let firstComponent = versionString?.split(separator: ".").first else {
            return nil
        }
        return Int(firstComponent)
    }

    private static func installedFirefoxVersion(bundleId: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId),
            let bundle = Bundle(url: appURL) else {
            return nil
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
