import AppKit

enum SoundPlayer {
    static func playSelection() { NSSound(named: "Tink")?.play() }
    static func playDismiss() { NSSound(named: "Pop")?.play() }
}
