// The ambient bed: a looping cave rumble with sparse echoing drips,
// plus two phase layers — a crystalline shimmer while frozen and a soft
// hiss as vapor — that crossfade with the droplet's phase.
//
// Every level is deliberately QUIET. The blow detector reads raw mic RMS
// (measurement mode, no echo cancellation), so speaker bleed from a loud
// bed could read as breath: the bed stays low-frequency and under ~-16 dB,
// well below the detector's -34 dB-at-the-mic floor. If a future device
// test ever shows phantom lift with the volume up, duck `bedVolume` first.

import AVFoundation

final class Ambience {
    static let shared = Ambience()

    private static let bedVolume: Float = 0.16
    private static let iceVolume: Float = 0.22
    private static let steamVolume: Float = 0.20
    private static let fade: TimeInterval = 0.8

    private var bed: AVAudioPlayer?
    private var ice: AVAudioPlayer?
    private var steam: AVAudioPlayer?
    private var started = false

    /// Begin the bed. Safe to call once at app start — the audio session
    /// is already configured (playAndRecord + mixWithOthers) by the
    /// BlowDetector, and AVAudioPlayer just joins it.
    func start() {
        guard !started else { return }
        started = true
        bed = loop("ambience")
        ice = loop("amb_ice")
        steam = loop("amb_steam")
        bed?.setVolume(Self.bedVolume, fadeDuration: 2.5)
    }

    /// Crossfade the phase layers. Idempotent and cheap — called from the
    /// model whenever the phase changes.
    func set(phase: Phase) {
        guard started else { return }
        ice?.setVolume(phase == .ice ? Self.iceVolume : 0, fadeDuration: Self.fade)
        steam?.setVolume(phase == .steam ? Self.steamVolume : 0, fadeDuration: Self.fade)
    }

    private func loop(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        return p
    }
}
