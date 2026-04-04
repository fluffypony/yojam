import AppKit

enum DefaultBrowserManager {
    static func promptSetDefault() {
        let bundleURL = Bundle.main.bundleURL
        // Registration only works when running as a proper .app bundle.
        // A bare binary from `swift run` will always fail with permErr.
        guard bundleURL.pathExtension == "app" else {
            YojamLogger.shared.log(
                "Not running as .app bundle — skipping default browser registration. "
                + "Build via Xcode (xcodegen generate) for full functionality.")
            return
        }
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

    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isDefaultBrowser: Bool {
        guard let defaultHTTP = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ) else { return false }
        guard let defaultBundle = Bundle(url: defaultHTTP) else { return false }
        return defaultBundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
