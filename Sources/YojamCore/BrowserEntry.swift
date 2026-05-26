import Foundation

public struct BrowserEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var displayName: String
    public var enabled: Bool
    public var position: Int
    public var profileId: String?
    public var profileName: String?
    public var stripUTMParams: Bool
    public var openInPrivateWindow: Bool
    public var rewriteRules: [URLRewriteRule]
    public var source: BrowserSource
    public var isInstalled: Bool
    public var lastSeenAt: Date?
    public var lastModifiedAt: Date?
    public var customIconData: Data?
    /// Chromium user data directory. Used with --user-data-dir.
    public var userDataDirectory: String?
    /// Custom CLI launch arguments. Use $URL as a placeholder for the URL.
    public var customLaunchArgs: String?
    /// Launch this entry as a separate app instance when using app-bundle opens.
    public var openAsNewInstance: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        enabled: Bool = true,
        position: Int = 0,
        profileId: String? = nil,
        profileName: String? = nil,
        stripUTMParams: Bool = false,
        openInPrivateWindow: Bool = false,
        rewriteRules: [URLRewriteRule] = [],
        source: BrowserSource = .autoDetected,
        isInstalled: Bool = true,
        lastSeenAt: Date? = Date(),
        lastModifiedAt: Date? = nil,
        customIconData: Data? = nil,
        userDataDirectory: String? = nil,
        customLaunchArgs: String? = nil,
        openAsNewInstance: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.enabled = enabled
        self.position = position
        self.profileId = profileId
        self.profileName = profileName
        self.stripUTMParams = stripUTMParams
        self.openInPrivateWindow = openInPrivateWindow
        self.rewriteRules = rewriteRules
        self.source = source
        self.isInstalled = isInstalled
        self.lastSeenAt = lastSeenAt
        self.lastModifiedAt = lastModifiedAt
        self.customIconData = customIconData
        self.userDataDirectory = userDataDirectory
        self.customLaunchArgs = customLaunchArgs
        self.openAsNewInstance = openAsNewInstance
    }

    public var fullDisplayName: String {
        if let profileName { return "\(displayName) — \(Self.displayName(forProfileName: profileName))" }
        return displayName
    }

    private static func displayName(forProfileName profileName: String) -> String {
        switch profileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default":
            return "Default Profile"
        case "default-release":
            return "Default Release Profile"
        case "dev-edition-default":
            return "Developer Edition Default Profile"
        default:
            return profileName
        }
    }

    // Manual Codable to tolerate schema evolution: any new field uses
    // decodeIfPresent with a default, so older persisted JSON doesn't crash.
    enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName, enabled, position
        case profileId, profileName, stripUTMParams, openInPrivateWindow
        case rewriteRules, source, isInstalled, lastSeenAt, lastModifiedAt
        case customIconData, userDataDirectory, customLaunchArgs, openAsNewInstance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? bundleIdentifier
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId)
        profileName = try c.decodeIfPresent(String.self, forKey: .profileName)
        stripUTMParams = try c.decodeIfPresent(Bool.self, forKey: .stripUTMParams) ?? false
        openInPrivateWindow = try c.decodeIfPresent(Bool.self, forKey: .openInPrivateWindow) ?? false
        rewriteRules = try c.decodeIfPresent([URLRewriteRule].self, forKey: .rewriteRules) ?? []
        source = try c.decodeIfPresent(BrowserSource.self, forKey: .source) ?? .autoDetected
        isInstalled = try c.decodeIfPresent(Bool.self, forKey: .isInstalled) ?? true
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        lastModifiedAt = try c.decodeIfPresent(Date.self, forKey: .lastModifiedAt)
        customIconData = try c.decodeIfPresent(Data.self, forKey: .customIconData)
        userDataDirectory = try c.decodeIfPresent(String.self, forKey: .userDataDirectory)
        customLaunchArgs = try c.decodeIfPresent(String.self, forKey: .customLaunchArgs)
        openAsNewInstance = try c.decodeIfPresent(Bool.self, forKey: .openAsNewInstance) ?? false
    }
}

public enum BrowserSource: String, Codable, Sendable {
    case autoDetected, manual, suggested
}
