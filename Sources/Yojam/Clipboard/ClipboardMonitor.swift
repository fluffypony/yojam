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

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    // §41: Clean up timer on deallocation
    deinit { timer?.invalidate() }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // §25: Skip self-triggered clipboard writes
        if suppressNextChange { suppressNextChange = false; return }
        // §24: Trim whitespace and guard against excessively large clipboard text
        guard let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              string.count < 2048,
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
