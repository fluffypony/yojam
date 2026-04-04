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

        // Dynamic vertical mode: check threshold and screen width
        var isVertical = entries.count > settingsStore.verticalThreshold
        if !isVertical {
            let horizontalWidth = CGFloat(entries.count) * 48 - 8 + 24
            let cursor = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main {
                if horizontalWidth > screen.visibleFrame.width * 0.8 {
                    isVertical = true
                }
            }
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

        // 42px per vertical entry (32px icon + 8px padding + 2px spacing)
        let size = isVertical
            ? NSSize(
                width: 220,
                height: min(CGFloat(entries.count) * 42 + 60, 500))
            : NSSize(
                width: CGFloat(entries.count) * 48 - 8 + 24,
                height: 40 + 60)
        self.setContentSize(size)
    }

    func showAtCursor() {
        let origin = ScreenEdgeDetector.calculateOrigin(pickerSize: frame.size)
        setFrameOrigin(origin)

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
