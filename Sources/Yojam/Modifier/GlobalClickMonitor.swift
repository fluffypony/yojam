import AppKit

@MainActor
final class GlobalClickMonitor {
    private let settingsStore: SettingsStore
    private let onModifierClick: () -> Void
    private var monitor: Any?

    init(settingsStore: SettingsStore, onModifierClick: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.onModifierClick = onModifierClick
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] event in
            Task { @MainActor in self?.handleGlobalClick(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
        var triggered = false
        if settingsStore.cmdShiftClickEnabled
            && flags.contains([.command, .shift]) { triggered = true }
        if settingsStore.ctrlShiftClickEnabled
            && flags.contains([.control, .shift]) { triggered = true }
        if settingsStore.cmdOptionClickEnabled
            && flags.contains([.command, .option]) { triggered = true }
        if triggered { onModifierClick() }
    }
}
