import Foundation

struct BrowserEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var bundleIdentifier: String
    var displayName: String
    var enabled: Bool
    var position: Int
    var profileId: String?
    var profileName: String?
    var stripUTMParams: Bool
    var openInPrivateWindow: Bool
    var rewriteRules: [URLRewriteRule]
    var source: BrowserSource
    var isInstalled: Bool
    var lastSeenAt: Date?
    var lastModifiedAt: Date?
    var customIconData: Data?

    init(
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
        customIconData: Data? = nil
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
    }

    var fullDisplayName: String {
        if let profileName { return "\(displayName) — \(profileName)" }
        return displayName
    }
}

enum BrowserSource: String, Codable, Sendable {
    case autoDetected, manual, suggested
}
