import AppKit
import ApplicationServices
import CoreGraphics

/// Lightweight wrapper for enumerating macOS displays and moving windows
/// across them. Used by per-display rule targeting.
enum DisplayManager {

    struct DisplayInfo: Identifiable, Hashable {
        let id: String    // persistent UUID from CGDisplayCreateUUIDFromDisplayID
        let name: String
        let frame: CGRect
    }

    /// Returns all active displays with a stable UUID identifier.
    static func availableDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { idx, screen in
            let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID ?? 0
            let uuid: String
            if let cf = CGDisplayCreateUUIDFromDisplayID(displayId) {
                uuid = CFUUIDCreateString(nil, cf.takeRetainedValue()) as String
            } else {
                uuid = String(displayId)
            }
            return DisplayInfo(
                id: uuid,
                name: "\(idx + 1): \(screen.localizedName)",
                frame: screen.frame)
        }
    }

    /// Resolve a screen by UUID. Returns nil if the display is no longer connected.
    static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID ?? 0
            guard let cf = CGDisplayCreateUUIDFromDisplayID(did) else { return false }
            let screenUUID = CFUUIDCreateString(nil, cf.takeRetainedValue()) as String
            return screenUUID == uuid
        }
    }

    /// Best-effort window placement via AX APIs. Requires the user to have
    /// granted Accessibility access in System Settings > Privacy & Security.
    /// Returns true when the move succeeded, false otherwise.
    @discardableResult
    static func moveFrontWindow(ofBundleId bundleId: String, toDisplayUUID uuid: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
              let targetScreen = screen(forUUID: uuid) else { return false }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement], let window = windows.first else {
            return false
        }

        var origin = CGPoint(x: targetScreen.frame.origin.x + 40,
                             y: targetScreen.frame.origin.y + 40)
        guard let posValue = AXValueCreate(.cgPoint, &origin) else { return false }
        let setErr = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        return setErr == .success
    }

    /// Whether the AX permission is currently granted (no prompt).
    static var isAXTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the AX permission prompt if not already granted.
    static func promptForAXPermission() {
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
