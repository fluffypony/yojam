import AppKit

enum ScreenEdgeDetector {
    /// Calculate picker origin so a specific point within the picker
    /// (the ``cursorTarget``, in picker-local coordinates from bottom-left)
    /// lands at the cursor position, clamped to the visible screen frame.
    static func calculateOrigin(
        pickerSize: NSSize, cursor: NSPoint, visibleFrame: NSRect,
        cursorTarget: NSPoint = .zero
    ) -> NSPoint {
        // Place the picker so that cursorTarget lines up with cursor
        var origin = NSPoint(
            x: cursor.x - cursorTarget.x,
            y: cursor.y - cursorTarget.y
        )

        // Clamp to visible frame
        origin.x = max(visibleFrame.minX,
                        min(origin.x, visibleFrame.maxX - pickerSize.width))
        origin.y = max(visibleFrame.minY,
                        min(origin.y, visibleFrame.maxY - pickerSize.height))
        return origin
    }

    static func calculateOrigin(
        pickerSize: NSSize, cursorTarget: NSPoint = .zero
    ) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(cursor)
        }) ?? NSScreen.main else {
            return NSPoint(x: cursor.x, y: cursor.y)
        }
        return calculateOrigin(
            pickerSize: pickerSize, cursor: cursor,
            visibleFrame: screen.visibleFrame,
            cursorTarget: cursorTarget)
    }
}
