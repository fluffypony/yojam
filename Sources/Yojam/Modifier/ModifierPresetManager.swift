import AppKit

struct ModifierPreset: Identifiable {
    let id: String
    var name: String
    var modifiers: NSEvent.ModifierFlags
    var enabled: Bool
}

enum ModifierPresetManager {
    static let defaultPresets: [ModifierPreset] = [
        ModifierPreset(
            id: "cmdShiftClick", name: "Cmd+Shift Click",
            modifiers: [.command, .shift], enabled: false),
        ModifierPreset(
            id: "ctrlShiftClick", name: "Ctrl+Shift Click",
            modifiers: [.control, .shift], enabled: false),
        ModifierPreset(
            id: "cmdOptionClick", name: "Cmd+Option Click",
            modifiers: [.command, .option], enabled: false),
    ]
}
