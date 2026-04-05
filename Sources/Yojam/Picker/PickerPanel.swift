import AppKit
import SwiftUI

@MainActor
final class PickerPanel: NSPanel {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onDismiss: () -> Void

    init(url: URL, entries: [BrowserEntry], preselectedIndex: Int,
         settingsStore: SettingsStore,
         onSelect: @escaping (BrowserEntry, URL) -> Void,
         onCopy: @escaping (URL) -> Void,
         onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

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
            displayEntries = entries.reversed()
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

        self.cursorTarget = Self.cursorTarget(for: resolvedLayout, panelSize: size)
    }

    private var cursorTarget: NSPoint = .zero

    // MARK: - Layout Metrics

    static func panelSize(for layout: PickerLayout, entryCount: Int) -> NSSize {
        let count = CGFloat(entryCount)
        switch layout {
        case .smallHorizontal:
            // 36px icons, 6px spacing, 12px padding each side
            return NSSize(
                width: count * 42 - 6 + 24,
                height: 36 + 60)
        case .bigHorizontal:
            // 56px icons + 16px label, 10px spacing, 16px padding each side
            return NSSize(
                width: count * 76 - 10 + 32,
                height: 56 + 16 + 60)
        case .smallVertical:
            // 24px icon, 32px row height, compact
            return NSSize(
                width: 200,
                height: min(count * 32 + 52, 440))
        case .bigVertical:
            // 40px icon, 48px row height
            return NSSize(
                width: 240,
                height: min(count * 48 + 60, 540))
        case .auto:
            // Should not reach here; resolved before calling
            return NSSize(width: 200, height: 100)
        }
    }

    static func cursorTarget(for layout: PickerLayout, panelSize: NSSize) -> NSPoint {
        switch layout {
        case .smallHorizontal:
            return NSPoint(x: 30, y: panelSize.height / 2)
        case .bigHorizontal:
            return NSPoint(x: 54, y: panelSize.height / 2)
        case .smallVertical:
            return NSPoint(x: panelSize.width / 2, y: panelSize.height - 28)
        case .bigVertical:
            return NSPoint(x: panelSize.width / 2, y: panelSize.height - 36)
        case .auto:
            return NSPoint(x: panelSize.width / 2, y: panelSize.height / 2)
        }
    }

    func showAtCursor() {
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: frame.size, cursorTarget: cursorTarget)
        setFrameOrigin(origin)

        orderFrontRegardless()
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
    }

    func dismissAnimated() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        PickerAnimator.animateOut(panel: self) { [weak self] in
            self?.onDismiss()
        }
    }

    override func keyDown(with event: NSEvent) {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
