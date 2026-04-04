import AppKit

enum ScreenEdgeDetector {
    static func calculateOrigin(
        pickerSize: NSSize, cursor: NSPoint, visibleFrame: NSRect
    ) -> NSPoint {
        var origin = NSPoint.zero

        if cursor.x + (pickerSize.width / 2) > visibleFrame.maxX {
            origin.x = cursor.x - pickerSize.width
        } else if cursor.x - (pickerSize.width / 2) < visibleFrame.minX {
            origin.x = cursor.x
        } else {
            origin.x = cursor.x - (pickerSize.width / 2)
        }

        if cursor.y - pickerSize.height - 8 < visibleFrame.minY {
            origin.y = cursor.y + 8
        } else {
            origin.y = cursor.y - pickerSize.height - 8
        }

        origin.x = max(visibleFrame.minX,
                        min(origin.x, visibleFrame.maxX - pickerSize.width))
        origin.y = max(visibleFrame.minY,
                        min(origin.y, visibleFrame.maxY - pickerSize.height))
        return origin
    }

    static func calculateOrigin(pickerSize: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(cursor)
        }) ?? NSScreen.main else {
            return NSPoint(x: cursor.x, y: cursor.y)
        }
        return calculateOrigin(
            pickerSize: pickerSize, cursor: cursor,
            visibleFrame: screen.visibleFrame)
    }
}
