import AppKit
import Carbon.HIToolbox

@MainActor
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    private var hotkeys: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32,
                  handler: @escaping () -> Void) -> UInt32 {
        let id = nextId; nextId += 1
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x594A4D00), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        hotkeys[id] = handler
        return id
    }

    func unregister(id: UInt32) { hotkeys.removeValue(forKey: id) }
    func handleHotKey(id: UInt32) { hotkeys[id]?() }
}
