import AppKit
import SwiftUI

@MainActor
final class PickerPanel: NSPanel {
    private var hostingView: NSHostingView<PickerContentView>?
    private var globalMonitor: Any?
    private let onDismiss: () -> Void

    init(url: URL, entries: [BrowserEntry], preselectedIndex: Int,
         settingsStore: SettingsStore,
         onSelect: @escaping (BrowserEntry, URL) -> Void,
         onCopy: @escaping (URL) -> Void,
         onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let isVertical = entries.count > settingsStore.verticalThreshold

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
            url: url, entries: entries,
            selectedIndex: preselectedIndex,
            isVertical: isVertical,
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

        let size = isVertical
            ? NSSize(
                width: 220,
                height: min(CGFloat(entries.count) * 40 + 60, 500))
            : NSSize(
                width: CGFloat(entries.count) * 48 - 8 + 24,
                height: 40 + 60)
        self.setContentSize(size)
    }

    func showAtCursor() {
        let cursor = NSEvent.mouseLocation
        let size = frame.size
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(cursor)
        }) ?? NSScreen.main!
        let visible = screen.visibleFrame

        var origin = NSPoint.zero
        if cursor.x + (size.width / 2) > visible.maxX {
            origin.x = cursor.x - size.width
        } else if cursor.x - (size.width / 2) < visible.minX {
            origin.x = cursor.x
        } else {
            origin.x = cursor.x - (size.width / 2)
        }

        if cursor.y - size.height - 8 < visible.minY {
            origin.y = cursor.y + 8
        } else {
            origin.y = cursor.y - size.height - 8
        }

        origin.x = max(visible.minX,
                        min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY,
                        min(origin.y, visible.maxY - size.height))
        setFrameOrigin(origin)

        PickerAnimator.animateIn(panel: self)
        makeKey()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissAnimated()
        }
    }

    func dismissAnimated() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        PickerAnimator.animateOut(panel: self) { [weak self] in
            self?.orderOut(nil)
            self?.onDismiss()
        }
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
