// Sensor inputs. Both are deliberately low-stakes: tilt is continuous
// (can't misfire), and breath only ever adds lift — it can't ruin a run.

import CoreMotion
import AVFoundation
import CoreGraphics

/// Continuous tilt from device motion — the primary control.
final class TiltSource {
    private let motion = CMMotionManager()
    var onTilt: ((CGVector) -> Void)?

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let dm else { return }
            // Device-frame gravity: x right, y toward the top of the screen.
            // Held flat the vector is ~zero — a level table, as it should be.
            self?.onTilt?(CGVector(dx: dm.gravity.x, dy: dm.gravity.y))
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

/// Smoothed microphone level, tuned so a deliberate blow reads near 1.0
/// and normal room noise stays under the game's 0.12 threshold.
final class BlowDetector {
    private let engine = AVAudioEngine()
    private var smoothed: Float = 0
    var onLevel: ((Float) -> Void)?
    /// Reports whether the mic is actually delivering breath input. When
    /// true, touch-and-hold lift is disabled (breath owns "up"); when false
    /// — permission denied, engine failure — holds take over as the lift.
    var onActive: ((Bool) -> Void)?

    func start() {
        #if targetEnvironment(simulator)
        // The simulator routes the Mac's mic unreliably; always use holds
        // there so mouse testing works.
        onActive?(false)
        #else
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.defaultToSpeaker, .mixWithOthers])
        // CRITICAL: iOS suppresses ALL haptics while recording unless this
        // is set — without it every haptic in the game is silently muted.
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try? session.setActive(true)
        session.requestRecordPermission { [weak self] granted in
            guard granted else {
                // Game still playable: touch-and-hold becomes the lift.
                DispatchQueue.main.async { self?.onActive?(false) }
                return
            }
            DispatchQueue.main.async { self?.installTap() }
        }
        #endif
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { onActive?(false); return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = (sum / Float(n)).squareRoot()
            // dB mapping so holding distance matters less than breath effort:
            // ~-34 dB (gentle breath at holding distance) → 0, -14 dB → 1.
            let db = 20 * log10(max(rms, 1e-6))
            let target = min(1, max(0, (db + 34) / 20))
            // Fast attack so lift feels immediate, slower release so the
            // updraft doesn't stutter between breath pulses.
            if target > self.smoothed {
                self.smoothed = 0.5 * self.smoothed + 0.5 * target
            } else {
                // Quick release: the updraft should die with the breath,
                // not carry the droplet around for another second.
                self.smoothed = 0.78 * self.smoothed + 0.22 * target
            }
            let level = self.smoothed
            DispatchQueue.main.async { self.onLevel?(level) }
        }
        do {
            try engine.start()
            onActive?(true)
        } catch {
            onActive?(false)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
