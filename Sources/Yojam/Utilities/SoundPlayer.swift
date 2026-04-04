import AppKit

enum SoundPlayer {
    static func playSelection() { NSSound(named: "Tink")?.play() }
}
