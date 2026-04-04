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
        // Use exact modifier matching to avoid accidental triggers with extra keys held
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let activeFlags = flags.intersection(relevant)
        var triggered = false
        if settingsStore.cmdShiftClickEnabled
            && activeFlags == [.command, .shift] { triggered = true }
        if settingsStore.ctrlShiftClickEnabled
            && activeFlags == [.control, .shift] { triggered = true }
        if settingsStore.cmdOptionClickEnabled
            && activeFlags == [.command, .option] { triggered = true }
        if triggered { onModifierClick() }
    }
}
