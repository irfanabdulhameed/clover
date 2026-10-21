import AppKit

/// The chip's touch and sound: a tap on the trackpad and a soft sound when a job finishes.
@MainActor
enum ChipFeedback {
    private static var sound: NSSound?
    private static var lastSound = Date.distantPast

    /// A small tick under the finger, when the trackpad is being touched.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// The finish sound, quietly. Two jobs ending in the same instant share one sound.
    /// `force` is for the preview in the Dashboard.
    static func playFinishSound(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSound) > 0.25 else { return }
        lastSound = Date()
        if sound == nil { sound = NSSound(named: NSSound.Name(ChipMotion.soundName)) }
        guard let sound else { return }
        sound.stop()
        sound.volume = ChipMotion.soundVolume
        sound.play()
    }
}
