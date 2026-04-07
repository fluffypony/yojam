import Foundation

/// Identifies how a link arrived in Yojam.
public enum IngressOrigin: String, Codable, Sendable {
    case defaultHandler     // kAEGetURL Apple Event
    case fileOpen           // application(_:open:)
    case handoff            // NSUserActivity
    case airdrop            // internet-location file via AirDrop
    case shareExtension
    case safariExtension
    case chromeExtension
    case firefoxExtension
    case servicesMenu
    case clipboard
    case intent
    case urlScheme          // yojam://
}
