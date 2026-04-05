import AppKit
import CoreServices

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
        guard let bundleId = Bundle.main.bundleIdentifier else { return }

        // Primary: modern async API (shows system confirmation on first call)
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "http")
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "https")
                try await NSWorkspace.shared.setDefaultApplication(
                    at: bundleURL, toOpenURLsWithScheme: "mailto")
                YojamLogger.shared.log("Registered as default browser (NSWorkspace)")
            } catch {
                YojamLogger.shared.log("NSWorkspace registration failed: \(error)")
            }
        }

        // Supplementary: older CoreServices API for robustness.
        // This ensures macOS System Settings reflects the change.
        let cfBundleId = bundleId as CFString
        LSSetDefaultHandlerForURLScheme("http" as CFString, cfBundleId)
        LSSetDefaultHandlerForURLScheme("https" as CFString, cfBundleId)
        LSSetDefaultHandlerForURLScheme("mailto" as CFString, cfBundleId)
        LSSetDefaultRoleHandlerForContentType(
            "public.html" as CFString, .viewer, cfBundleId)
        LSSetDefaultRoleHandlerForContentType(
            "public.xhtml" as CFString, .viewer, cfBundleId)
        YojamLogger.shared.log("Registered as default browser (CoreServices)")
    }

    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isDefaultBrowser: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }

        // Check via CoreServices — this is what macOS System Settings reads.
        // If this doesn't match, System Settings will show a different browser
        // even if NSWorkspace routes URLs to us.
        if let handler = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() as String?,
           handler.caseInsensitiveCompare(bundleId) == .orderedSame {
            return true
        }

        // Fallback: check via NSWorkspace for .app bundles where CoreServices
        // may lag behind the async registration.
        if let defaultHTTP = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ), let defaultBundle = Bundle(url: defaultHTTP),
           defaultBundle.bundleIdentifier == bundleId {
            return true
        }

        return false
    }
}
