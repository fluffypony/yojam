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

    // §41: Invalidate timer if object is deallocated without calling stop()
    deinit {
        let t = timer
        if Thread.isMainThread {
            t?.invalidate()
        } else {
            DispatchQueue.main.async { t?.invalidate() }
        }
    }

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // §25: Skip self-triggered clipboard writes
        if suppressNextChange { suppressNextChange = false; return }
        // §24: Guard against excessively large clipboard text before trimming
        guard let rawString = pasteboard.string(forType: .string),
              rawString.count < 2048 else { return }
        let string = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
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
