import SwiftUI
import UIKit

/// The droplet's three phases. Water is the default; ice is fast, slippery
/// and grate-proof; steam rises on its own, ignores floor drains and grates,
/// but condenses back to water after a few seconds and can't enter the goal.
enum Phase {
    case water, ice, steam
}

final class GameModel: ObservableObject {
    @Published var levelNumber = 1
    @Published var levelName = ""
    @Published var hint = ""
    @Published var phase: Phase = .water
    @Published var steamAllowed = false
    @Published var blowAllowed = true
    /// True when the mic is live — breath owns lift and holds are inert.
    /// False (denied / engine failure / simulator) — holds are the lift.
    @Published var micActive = false
    /// False during the post-condense recharge (scene-driven). The cooldown
    /// is what keeps steam a committed leap instead of a second hover verb.
    @Published var steamReady = true

    /// Convenience for the freeze button and darkness proxy.
    var isIce: Bool { phase == .ice }
    @Published var blowLevel: Float = 0
    @Published var finished = false
    @Published var carveAllowed = false
    /// Remaining ink for the stroke in progress, 1→0. Ink is per-stroke,
    /// so this refills on release — the meter teaches that by itself.
    @Published var inkFrac: CGFloat = 1
    @Published var totalScore = 0
    @Published var availableScore = 1000
    @Published var countdown: String?

    enum Screen { case menu, playing }
    @Published var screen: Screen = .menu
    @Published var bestScores: [Int]
    @Published var bestRun: Int
    private var runFromStart = false

    /// Raw tilt, updated at 60 Hz — read by the scene each frame, so not
    /// published (no need to redraw SwiftUI at sensor rate).
    var tilt = CGVector(dx: 0, dy: -0.55)   // simulator default: gentle downhill

    let scene: GameScene
    private let tiltSource = TiltSource()
    private let blow = BlowDetector()
    private var brightnessTimer: Timer?
    private var autoFroze = false
    private var started = false

    init() {
        let defaults = UserDefaults.standard
        bestScores = (0..<Levels.all.count).map { defaults.integer(forKey: "dripdrop.best.\($0)") }
        bestRun = defaults.integer(forKey: "dripdrop.bestRun")
        scene = GameScene(size: UIScreen.main.bounds.size)
        scene.scaleMode = .resizeFill
        scene.model = self

        // Test harness: `simctl launch <sim> <bundle> -autostart 3` jumps
        // straight into level 3 so automation can screenshot gameplay
        // without a tap. No effect on normal launches.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-autostart") {
            let n = (args.count > i + 1 ? Int(args[i + 1]) : nil) ?? 1
            let idx = min(max(n - 1, 0), Levels.all.count - 1)
            let forced: Phase? = args.contains("-ice") ? .ice
                               : args.contains("-steam") ? .steam : nil
            DispatchQueue.main.async { [weak self] in
                self?.startGame(at: idx)
                if let forced {
                    // After didMove's level reload (which resets to water).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.phase = forced
                    }
                }
            }
        }
    }

    // MARK: Flow

    func startGame(at index: Int) {
        finished = false
        totalScore = 0
        runFromStart = (index == 0)
        scene.loadLevel(index)
        screen = .playing
        GameCenter.shared.setAccessPoint(visible: false)
    }

    func backToMenu() {
        finished = false
        screen = .menu
        GameCenter.shared.setAccessPoint(visible: true)
    }

    // MARK: Score records

    func recordBank(levelIndex: Int, banked: Int) {
        totalScore += banked
        if banked > bestScores[levelIndex] {
            bestScores[levelIndex] = banked
            UserDefaults.standard.set(banked, forKey: "dripdrop.best.\(levelIndex)")
        }
    }

    func runFinished() {
        finished = true
        if runFromStart {
            if totalScore > bestRun {
                bestRun = totalScore
                UserDefaults.standard.set(totalScore, forKey: "dripdrop.bestRun")
            }
            // Honest runs go to the leaderboard (no-op if GC unavailable).
            GameCenter.shared.submitBestRun(totalScore)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        tiltSource.onTilt = { [weak self] v in self?.tilt = v }
        tiltSource.start()
        blow.onLevel = { [weak self] l in self?.blowLevel = l }
        blow.onActive = { [weak self] active in self?.micActive = active }
        blow.start()
        GameCenter.shared.start { [weak self] _ in
            GameCenter.shared.setAccessPoint(visible: self?.screen == .menu)
        }
        UIApplication.shared.isIdleTimerDisabled = true

        // Darkness freezes the droplet. iOS has no public ambient-light API,
        // so we use auto-brightness as a proxy: with auto-brightness on,
        // covering the sensor / killing the lights drags screen brightness
        // down. The ❄ button is the reliable path; this is the magic path.
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let b = UIScreen.main.brightness
            if b < 0.08, self.phase == .water {
                self.phase = .ice
                self.autoFroze = true
            } else if b > 0.4, self.autoFroze {
                if self.phase == .ice { self.phase = .water }
                self.autoFroze = false
            }
        }
    }

    func toggleIce() {
        autoFroze = false
        phase = (phase == .ice) ? .water : .ice
    }

    /// Steam toggle; from ice this sublimates straight to vapor. Condensing
    /// is always allowed; vaporizing waits out the recharge.
    func toggleSteam() {
        autoFroze = false
        if phase == .steam {
            phase = .water
        } else if steamReady {
            phase = .steam
        }
    }

    func resetLevel() { scene.reloadCurrent() }

    func restart() { startGame(at: 0) }
}
