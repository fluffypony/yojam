import Foundation

/// Lightweight, JSON-safe transport type for previewing routing decisions.
/// Used by the native host, CLI, and extension popups. Do NOT serialize
/// `RouteDecision` directly — it has associated values with heavy payloads
/// like `customIconData`.
public struct RouteDecisionPreview: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case openDirect, showPicker, openSystemDefault, openSystemMailHandler
    }

    public let kind: Kind
    public let summary: String
    public let targetBundleId: String?
    public let targetDisplayName: String?
    public let finalURL: String
    public let reason: String?
    public let privateWindow: Bool
    public let isEmail: Bool
    public let preselectedDisplayName: String?
    public let pickerCandidates: [PickerCandidate]?

    public struct PickerCandidate: Codable, Sendable {
        public let bundleId: String
        public let displayName: String

        public init(bundleId: String, displayName: String) {
            self.bundleId = bundleId
            self.displayName = displayName
        }
    }

    public init(kind: Kind, summary: String, targetBundleId: String?,
                targetDisplayName: String?, finalURL: String,
                reason: String?, privateWindow: Bool, isEmail: Bool,
                preselectedDisplayName: String?,
                pickerCandidates: [PickerCandidate]?) {
        self.kind = kind
        self.summary = summary
        self.targetBundleId = targetBundleId
        self.targetDisplayName = targetDisplayName
        self.finalURL = finalURL
        self.reason = reason
        self.privateWindow = privateWindow
        self.isEmail = isEmail
        self.preselectedDisplayName = preselectedDisplayName
        self.pickerCandidates = pickerCandidates
    }

    public static func from(_ decision: RouteDecision) -> RouteDecisionPreview {
        switch decision {
        case .openDirect(let browser, let finalURL, let privateWindow, let reason):
            let isMailto = finalURL.scheme?.lowercased() == "mailto"
            return RouteDecisionPreview(
                kind: .openDirect,
                summary: "Would open in \(browser.fullDisplayName)",
                targetBundleId: browser.bundleIdentifier,
                targetDisplayName: browser.fullDisplayName,
                finalURL: finalURL.absoluteString,
                reason: reason,
                privateWindow: privateWindow,
                isEmail: isMailto,
                preselectedDisplayName: nil,
                pickerCandidates: nil
            )

        case .showPicker(let entries, let preselectedIndex, let finalURL, let isEmail, let reason):
            let preselected = entries.indices.contains(preselectedIndex)
                ? entries[preselectedIndex].fullDisplayName : nil
            let candidates = entries.map {
                PickerCandidate(bundleId: $0.bundleIdentifier, displayName: $0.fullDisplayName)
            }
            let summary = preselected.map { "Would show picker (preselected: \($0))" }
                ?? "Would show picker (\(entries.count) options)"
            return RouteDecisionPreview(
                kind: .showPicker,
                summary: summary,
                targetBundleId: nil,
                targetDisplayName: nil,
                finalURL: finalURL.absoluteString,
                reason: reason,
                privateWindow: false,
                isEmail: isEmail,
                preselectedDisplayName: preselected,
                pickerCandidates: candidates
            )

        case .openSystemDefault(let url):
            return RouteDecisionPreview(
                kind: .openSystemDefault,
                summary: "Would open via system default",
                targetBundleId: nil,
                targetDisplayName: nil,
                finalURL: url.absoluteString,
                reason: nil,
                privateWindow: false,
                isEmail: false,
                preselectedDisplayName: nil,
                pickerCandidates: nil
            )

        case .openSystemMailHandler(let url):
            return RouteDecisionPreview(
                kind: .openSystemMailHandler,
                summary: "Would open via system mail handler",
                targetBundleId: nil,
                targetDisplayName: nil,
                finalURL: url.absoluteString,
                reason: nil,
                privateWindow: false,
                isEmail: true,
                preselectedDisplayName: nil,
                pickerCandidates: nil
            )
        }
    }
}
