import AppKit

enum ScreenEdgeDetector {
    static func calculateOrigin(pickerSize: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(cursor)
        }) ?? NSScreen.main!
        let visible = screen.visibleFrame
        var origin = NSPoint.zero

        if cursor.x + (pickerSize.width / 2) > visible.maxX {
            origin.x = cursor.x - pickerSize.width
        } else if cursor.x - (pickerSize.width / 2) < visible.minX {
            origin.x = cursor.x
        } else {
            origin.x = cursor.x - (pickerSize.width / 2)
        }

        if cursor.y - pickerSize.height - 8 < visible.minY {
            origin.y = cursor.y + 8
        } else {
            origin.y = cursor.y - pickerSize.height - 8
        }

        origin.x = max(visible.minX,
                        min(origin.x, visible.maxX - pickerSize.width))
        origin.y = max(visible.minY,
                        min(origin.y, visible.maxY - pickerSize.height))
        return origin
    }
}
