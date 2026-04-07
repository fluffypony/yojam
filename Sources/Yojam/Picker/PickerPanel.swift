import AppKit
import SwiftUI
import YojamCore

@MainActor
final class PickerPanel: NSPanel {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private let onDismiss: (PickerPanel) -> Void
    private var isDismissed = false

    init(url: URL, entries: [BrowserEntry], preselectedIndex: Int,
         settingsStore: SettingsStore,
         matchReason: String? = nil,
         onSelect: @escaping (BrowserEntry, URL) -> Void,
         onCopy: @escaping (URL) -> Void,
         onDismiss: @escaping (PickerPanel) -> Void) {
        self.onDismiss = onDismiss

        // Increment picker usage counter
        let usageCount = UserDefaults.standard.integer(forKey: "pickerUsageCount")
        UserDefaults.standard.set(usageCount + 1, forKey: "pickerUsageCount")

        // Resolve effective layout
        let layout = settingsStore.pickerLayout
        let resolvedLayout: PickerLayout
        if layout == .auto {
            var useVertical = entries.count > settingsStore.verticalThreshold
            if !useVertical {
                let horizontalWidth = CGFloat(entries.count) * 48 - 8 + 24
                let cursor = NSEvent.mouseLocation
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main {
                    if horizontalWidth > screen.visibleFrame.width * 0.8 {
                        useVertical = true
                    }
                }
            }
            resolvedLayout = useVertical ? .bigVertical : .smallHorizontal
        } else {
            resolvedLayout = layout
        }

        // Apply order inversion
        let displayEntries: [BrowserEntry]
        let adjustedPreselection: Int
        if settingsStore.pickerInvertOrder {
            displayEntries = Array(entries.reversed())
            adjustedPreselection = entries.count - 1 - preselectedIndex
        } else {
            displayEntries = entries
            adjustedPreselection = preselectedIndex
        }

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary,
        ]

        let contentView = PickerContentView(
            url: url, entries: displayEntries,
            selectedIndex: adjustedPreselection,
            layout: resolvedLayout,
            matchReason: matchReason,
            onSelect: { [weak self] entry in
                self?.dismissAnimated()
                if settingsStore.soundEffectsEnabled {
                    SoundPlayer.playSelection()
                }
                onSelect(entry, url)
            },
            onCopy: { [weak self] in
                self?.dismissAnimated()
                onCopy(url)
            },
            onDismiss: { [weak self] in self?.dismissAnimated() }
        )

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            visualEffect.layer?.borderWidth = 1
            visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor
        }

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(
                equalTo: visualEffect.topAnchor),
            hosting.bottomAnchor.constraint(
                equalTo: visualEffect.bottomAnchor),
            hosting.leadingAnchor.constraint(
                equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(
                equalTo: visualEffect.trailingAnchor),
        ])
        self.contentView = visualEffect

        let size = Self.panelSize(for: resolvedLayout, entryCount: displayEntries.count)
        self.setContentSize(size)

        self.cursorTarget = Self.cursorTarget(
            for: resolvedLayout, panelSize: size,
            preselectedIndex: adjustedPreselection,
            entryCount: displayEntries.count)
    }

    private var cursorTarget: NSPoint = .zero

    // Footer: hint line(14) + name(16) + url(14) + shortcut legend(16) + spacing/padding
    // Top padding: 12. Total non-content = 90.
    private static let footerAllowance: CGFloat = 90

    // MARK: - Layout Metrics

    static func panelSize(for layout: PickerLayout, entryCount: Int) -> NSSize {
        let count = CGFloat(entryCount)
        let footer = footerAllowance
        switch layout {
        case .smallHorizontal:
            // number(14) + gap(2) + icon(36) = 52
            return NSSize(
                width: count * 42 - 6 + 24,
                height: 52 + footer)
        case .bigHorizontal:
            // number(14) + gap(2) + icon(56) + gap(4) + label(14) = 90
            return NSSize(
                width: count * 76 - 10 + 32,
                height: 90 + footer)
        case .smallVertical:
            // 30px row height + 1px spacing
            return NSSize(
                width: 200,
                height: min(count * 31 + footer, 440))
        case .bigVertical:
            // 48px row height + 2px spacing
            return NSSize(
                width: 240,
                height: min(count * 50 + footer, 540))
        case .auto:
            return NSSize(width: 200, height: 100)
        }
    }

    static func cursorTarget(
        for layout: PickerLayout, panelSize: NSSize,
        preselectedIndex: Int, entryCount: Int
    ) -> NSPoint {
        let idx = CGFloat(max(0, min(preselectedIndex, entryCount - 1)))
        switch layout {
        case .smallHorizontal:
            // 12(pad) + 14(number) + 2(gap) + 18(icon center) = 46 from top
            let yFromTop: CGFloat = 46
            return NSPoint(x: 12 + idx * 42 + 18, y: panelSize.height - yFromTop)
        case .bigHorizontal:
            // 12(pad) + 14(number) + 2(gap) + 28(icon center) = 56 from top
            let yFromTop: CGFloat = 56
            return NSPoint(x: 16 + idx * 76 + 33, y: panelSize.height - yFromTop)
        case .smallVertical:
            // 12(pad) + idx * 31(row stride) + 15(row center)
            let yFromTop = 12 + idx * 31 + 15
            return NSPoint(x: panelSize.width / 2, y: panelSize.height - yFromTop)
        case .bigVertical:
            // 12(pad) + idx * 50(row stride) + 25(row center)
            let yFromTop = 12 + idx * 50 + 25
            return NSPoint(x: panelSize.width / 2, y: panelSize.height - yFromTop)
        case .auto:
            return NSPoint(x: panelSize.width / 2, y: panelSize.height / 2)
        }
    }

    func showAtCursor() {
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: frame.size, cursorTarget: cursorTarget)
        setFrameOrigin(origin)

        // Stay in .accessory policy — NSApp.activate() works without
        // switching to .regular, so the picker never appears in Cmd+Tab.
        NSApp.activate()
        PickerAnimator.animateIn(panel: self)
        makeKey()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissAnimated()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] event in
            if event.window != self {
                self?.dismissAnimated()
            }
            return event
        }

        // Dismiss when the user Cmd+Tabs away
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissAnimated() }
        }
    }

    // §10: Shared cleanup to prevent event monitor leaks
    private func removeMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let local = localMonitor { NSEvent.removeMonitor(local); localMonitor = nil }
        if let obs = deactivationObserver { NotificationCenter.default.removeObserver(obs); deactivationObserver = nil }
    }

    override func close() {
        removeMonitors()
        let shouldNotify = !isDismissed
        isDismissed = true
        super.close()
        if shouldNotify { onDismiss(self) }
    }

    func dismissAnimated() {
        guard !isDismissed else { return }
        isDismissed = true
        removeMonitors()
        PickerAnimator.animateOut(panel: self) { [weak self] in
            guard let self else { return }
            self.onDismiss(self)
        }
    }

    override func keyDown(with event: NSEvent) {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
