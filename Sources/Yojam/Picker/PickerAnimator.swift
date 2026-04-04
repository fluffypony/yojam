import AppKit

@MainActor
enum PickerAnimator {
    static func animateIn(panel: NSPanel) {
        let reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.contentView?.layer?.setAffineTransform(
            CGAffineTransform(scaleX: 0.95, y: 0.95))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.contentView?.layer?.setAffineTransform(.identity)
        }
    }

    static func animateOut(
        panel: NSPanel, completion: @escaping @MainActor () -> Void
    ) {
        let reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.orderOut(nil)
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.06
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    panel.alphaValue = 1.0
                    panel.contentView?.layer?.setAffineTransform(.identity)
                    completion()
                }
            })
    }
}
