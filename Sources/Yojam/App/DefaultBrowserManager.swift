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
        let schemeResults: [(String, OSStatus)] = [
            ("http", LSSetDefaultHandlerForURLScheme("http" as CFString, cfBundleId)),
            ("https", LSSetDefaultHandlerForURLScheme("https" as CFString, cfBundleId)),
            ("mailto", LSSetDefaultHandlerForURLScheme("mailto" as CFString, cfBundleId)),
            ("yojam", LSSetDefaultHandlerForURLScheme("yojam" as CFString, cfBundleId)),
        ]
        for (scheme, status) in schemeResults where status != noErr {
            YojamLogger.shared.log("LSSetDefaultHandlerForURLScheme(\(scheme)) failed: \(status)")
        }

        let contentResults: [(String, OSStatus)] = [
            ("public.html", LSSetDefaultRoleHandlerForContentType(
                "public.html" as CFString, .viewer, cfBundleId)),
            ("public.xhtml", LSSetDefaultRoleHandlerForContentType(
                "public.xhtml" as CFString, .viewer, cfBundleId)),
            ("com.apple.web-internet-location", LSSetDefaultRoleHandlerForContentType(
                "com.apple.web-internet-location" as CFString, .viewer, cfBundleId)),
            ("com.apple.internet-location", LSSetDefaultRoleHandlerForContentType(
                "com.apple.internet-location" as CFString, .viewer, cfBundleId)),
            ("public.url", LSSetDefaultRoleHandlerForContentType(
                "public.url" as CFString, .viewer, cfBundleId)),
        ]
        for (type, status) in contentResults where status != noErr {
            YojamLogger.shared.log("LSSetDefaultRoleHandlerForContentType(\(type)) failed: \(status)")
        }

        YojamLogger.shared.log("Registered as default browser (CoreServices)")
    }

    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isDefaultBrowser: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }

        if let appURL = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ), let defaultBundle = Bundle(url: appURL),
           defaultBundle.bundleIdentifier == bundleId {
            return true
        }

        return false
    }

    /// Check if Yojam is registered as the handler for .webloc files.
    static var isWeblocHandler: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            "com.apple.web-internet-location" as CFString, .viewer
        )?.takeRetainedValue() as String? else { return false }
        return handler == bundleId
    }

    /// Check if the yojam:// scheme is registered.
    static var isYojamSchemeRegistered: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let probe = URL(string: "yojam://"),
              let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let handlerBundleId = Bundle(url: handlerURL)?.bundleIdentifier
        else { return false }
        return handlerBundleId == bundleId
    }
}
