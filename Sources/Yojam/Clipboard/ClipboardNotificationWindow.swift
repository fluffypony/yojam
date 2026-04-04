import AppKit
import SwiftUI

@MainActor
final class ClipboardNotificationWindow: NSPanel {
    private var onOpen: (() -> Void)?
    private var onDismissCallback: (() -> Void)?

    init(url: URL, onOpen: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]

        let ve = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        ve.material = .popover; ve.state = .active
        ve.wantsLayer = true
        ve.layer?.cornerRadius = 10; ve.layer?.masksToBounds = true

        let displayHost = url.host ?? url.absoluteString
        let label = NSTextField(labelWithString: displayHost)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 10, y: 30, width: 220, height: 20)

        let openButton = NSButton(title: "Open", target: nil, action: nil)
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 240, y: 25, width: 70, height: 24)
        openButton.target = self
        openButton.action = #selector(openClicked)

        ve.addSubview(label)
        ve.addSubview(openButton)
        self.contentView = ve
        self.onOpen = onOpen
        self.onDismissCallback = onDismiss
    }

    func showWithAutoDismiss() {
        guard let screen = NSScreen.main else { return }
        setFrameOrigin(NSPoint(
            x: screen.visibleFrame.maxX - 330,
            y: screen.visibleFrame.maxY - 70))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                self.animator().alphaValue = 0
            },
            completionHandler: {
                MainActor.assumeIsolated {
                    self.orderOut(nil)
                    self.onDismissCallback?()
                }
            })
    }

    @objc private func openClicked() {
        dismiss()
        onOpen?()
    }
}
