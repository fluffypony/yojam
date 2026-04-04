import AppKit

enum SourceAppResolver {
    static func resolveSourceApp(from event: NSAppleEventDescriptor) -> String? {
        // Attempt to extract PID from the event sender
        guard let senderPID = event.attributeDescriptor(
            forKeyword: AEKeyword(keySenderPIDAttr)
        ) else { return nil }

        let pid = pid_t(senderPID.int32Value)
        guard pid > 0 else { return nil }

        let app = NSRunningApplication(processIdentifier: pid)
        return app?.bundleIdentifier
    }
}
