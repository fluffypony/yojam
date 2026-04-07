import Foundation

public enum ActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case always, holdShift, smartFallback
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .always: "Always show picker"
        case .holdShift: "Open directly; hold Shift to choose"
        case .smartFallback: "Auto-pick when confident"
        }
    }
}

public enum DefaultSelectionBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case alwaysFirst, lastUsed, smart
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .alwaysFirst: "First in browser list"
        case .lastUsed: "Last browser I used"
        case .smart: "Learned preference for this site"
        }
    }
}
