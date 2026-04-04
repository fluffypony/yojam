import AppKit

enum DefaultBrowserManager {
    static func promptSetDefault() {
        let bundleURL = Bundle.main.bundleURL
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "http")
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "https")
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "mailto")
                YojamLogger.shared.log("Registered as default browser")
            } catch {
                YojamLogger.shared.log("Failed to register: \(error)")
            }
        }
    }

    static var isDefaultBrowser: Bool {
        guard let defaultHTTP = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ) else { return false }
        guard let defaultBundle = Bundle(url: defaultHTTP) else { return false }
        return defaultBundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
