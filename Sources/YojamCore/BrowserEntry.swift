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
    /// Custom CLI launch arguments. Use $URL as a placeholder for the URL.
    public var customLaunchArgs: String?

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
        customLaunchArgs: String? = nil
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
        self.customLaunchArgs = customLaunchArgs
    }

    public var fullDisplayName: String {
        if let profileName { return "\(displayName) — \(profileName)" }
        return displayName
    }
}

public enum BrowserSource: String, Codable, Sendable {
    case autoDetected, manual, suggested
}
