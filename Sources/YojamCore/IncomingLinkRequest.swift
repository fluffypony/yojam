import Foundation

/// A normalized, ingress-agnostic representation of an inbound link.
/// Every entry point — Apple Event, Handoff, AirDrop, Share Extension,
/// browser extension, Services menu, yojam:// scheme — produces one of
/// these before handing off to the routing pipeline.
public struct IncomingLinkRequest: Sendable {
    public let url: URL
    public let sourceAppBundleId: String?
    public let origin: IngressOrigin
    public let modifierFlags: UInt
    public let receivedAt: Date
    public let metadata: [String: String]

    /// When set, forces routing to this specific browser bundle ID,
    /// skipping rule evaluation.
    public let forcedBrowserBundleId: String?

    /// When true, forces the picker to appear regardless of activation mode.
    public let forcePicker: Bool

    /// When true, requests a private/incognito window in the target browser.
    public let forcePrivateWindow: Bool

    public init(
        url: URL,
        sourceAppBundleId: String? = nil,
        origin: IngressOrigin,
        modifierFlags: UInt = 0,
        receivedAt: Date = Date(),
        metadata: [String: String] = [:],
        forcedBrowserBundleId: String? = nil,
        forcePicker: Bool = false,
        forcePrivateWindow: Bool = false
    ) {
        self.url = url
        self.sourceAppBundleId = sourceAppBundleId
        self.origin = origin
        self.modifierFlags = modifierFlags
        self.receivedAt = receivedAt
        self.metadata = metadata
        self.forcedBrowserBundleId = forcedBrowserBundleId
        self.forcePicker = forcePicker
        self.forcePrivateWindow = forcePrivateWindow
    }
}
