// Continuous rolling texture through the Taptic Engine: the droplet's
// contact with the world, felt in the palm. Soft and watery as liquid,
// tight and gritty as ice, scaled by speed — and silent in flight,
// because ballistic air touches nothing.

import CoreHaptics
import QuartzCore

final class RollingHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var lastSend: TimeInterval = 0

    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.makePlayer()
            }
            try engine.start()
            self.engine = engine
            makePlayer()
        } catch {
            engine = nil
        }
    }

    private func makePlayer() {
        guard let engine else { return }
        do {
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [
                                          CHHapticEventParameter(parameterID: .hapticIntensity, value: 0),
                                          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                                      ],
                                      relativeTime: 0, duration: 3600)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let p = try engine.makeAdvancedPlayer(with: pattern)
            try p.start(atTime: CHHapticTimeImmediate)
            player = p
        } catch {
            player = nil
        }
    }

    /// Call every frame; throttled internally to ~30 Hz.
    func update(speed: CGFloat, grounded: Bool, isIce: Bool) {
        guard let player else { return }
        let now = CACurrentMediaTime()
        guard now - lastSend > 0.033 else { return }
        lastSend = now
        let intensity: Float = (grounded && speed > 60)
            ? Float(min(0.55, Double(speed - 60) / 1200)) * (isIce ? 0.8 : 1.0)
            : 0
        let sharpness: Float = isIce ? 0.85 : 0.25
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: sharpness, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
        engine = nil
    }
}
