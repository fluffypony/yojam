import AppKit

@MainActor
final class ClipboardMonitor {
    private let settingsStore: SettingsStore
    private let onURLDetected: (URL) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int = 0

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

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let string = pasteboard.string(forType: .string),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else { return }
        // Skip suppressed domains (§23.1)
        let domain = host.lowercased()
        if settingsStore.suppressedClipboardDomains.contains(where: {
            domain == $0 || domain.hasSuffix(".\($0)")
        }) { return }
        onURLDetected(url)
    }
}
