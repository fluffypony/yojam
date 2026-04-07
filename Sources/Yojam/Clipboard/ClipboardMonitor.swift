import AppKit

@MainActor
final class ClipboardMonitor {
    private let settingsStore: SettingsStore
    private let onURLDetected: (URL) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    // §25: Suppress detection of self-triggered pasteboard writes
    var suppressNextChange = false

    init(settingsStore: SettingsStore, onURLDetected: @escaping (URL) -> Void) {
        self.settingsStore = settingsStore
        self.onURLDetected = onURLDetected
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // Rely on explicit stop() calls from applicationWillTerminate and
    // dynamic service toggle sinks. Removed deinit timer invalidation
    // because MainActor.assumeIsolated traps in Swift 6 strict concurrency
    // when deinit runs off the main actor.

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Synchronize the expected change count after programmatic pasteboard writes.
    /// Call this AFTER setting the pasteboard content (clearContents + setString)
    /// to prevent the next poll from seeing the write as a user-initiated change.
    func updateExpectedChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // §25: Skip self-triggered clipboard writes
        if suppressNextChange { suppressNextChange = false; return }
        // §24: Guard against excessively large clipboard text
        guard let rawString = pasteboard.string(forType: .string),
              rawString.count < 2048 else { return }
        // Trim first, then check length
        let string = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard string.count < 2048 else { return }
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else { return }
        let domain = host.lowercased()
        if settingsStore.suppressedClipboardDomains.contains(where: {
            domain == $0 || domain.hasSuffix(".\($0)")
        }) { return }
        onURLDetected(url)
    }
}
