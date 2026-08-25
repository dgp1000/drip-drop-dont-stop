import SwiftUI
import UIKit

/// The droplet's three phases. Water is the default; ice is fast, slippery
/// and grate-proof; steam rises on its own, ignores floor drains and grates,
/// but condenses back to water after a few seconds and can't enter the goal.
enum Phase {
    case water, ice, steam
}

/// Best scores are keyed by level NAME, not index — a difficulty re-sort
/// of the level list is planned, and index keys would silently attach
/// every player's bests (and medals) to the wrong levels. One-time
/// migration copies the old index keys over; run it BEFORE any reorder
/// ships, while indexes still mean what they meant when written.
enum BestScores {
    static func key(_ name: String) -> String {
        "dripdrop.best." + name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "dripdrop.bestKeysMigrated") else { return }
        for (i, level) in Levels.all.enumerated() {
            let old = d.integer(forKey: "dripdrop.best.\(i)")
            if old > 0, d.object(forKey: key(level.name)) == nil {
                d.set(old, forKey: key(level.name))
            }
        }
        d.set(true, forKey: "dripdrop.bestKeysMigrated")
    }
}

final class GameModel: ObservableObject {
    @Published var levelNumber = 1
    @Published var levelName = ""
    @Published var hint = ""
    @Published var phase: Phase = .water {
        didSet { Ambience.shared.set(phase: phase) }
    }
    @Published var steamAllowed = false
    @Published var blowAllowed = true
    /// Whether the mic is delivering breath input (informational — holds
    /// and breath are BOTH first-class lift now; testers preferred taps).
    @Published var micActive = false
    /// Remaining lift air supply, 1→0. Empty = no more lift; ↺ refills.
    @Published var liftFrac: CGFloat = 1
    /// Phase buttons are locked until READY-STEADY-GO completes — now that
    /// phases run on clocks, a countdown freeze would be a free head start.
    @Published var phaseLocked = true
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
        BestScores.migrateIfNeeded()
        bestScores = Levels.all.map { defaults.integer(forKey: BestScores.key($0.name)) }
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
                    // After the countdown finishes (phases are GO-locked).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
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
            UserDefaults.standard.set(banked,
                                      forKey: BestScores.key(Levels.all[levelIndex].name))
        }
        GameCenter.shared.report(.firstBasin)
        // The one-and-only permission ask rides the first win.
        Reminders.shared.requestAfterFirstBank(bestScores: bestScores, bestRun: bestRun)
        // 525 = a par-or-better finish (the pot decays normalized by par —
        // same math as the menu's gold medal).
        if banked >= 525 { GameCenter.shared.report(.underPar) }
        let golds = bestScores.filter { $0 >= 525 }.count
        GameCenter.shared.report(.allGold,
                                 percent: Double(golds) / Double(bestScores.count) * 100)
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
            GameCenter.shared.report(.honestRun)
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
        // After the blow detector has claimed the audio session — the
        // ambience joins the session, it must not configure one.
        Ambience.shared.start()

        // Darkness freezes the droplet. iOS has no public ambient-light API,
        // so we use auto-brightness as a proxy: with auto-brightness on,
        // covering the sensor / killing the lights drags screen brightness
        // down. The ❄ button is the reliable path; this is the magic path.
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let b = UIScreen.main.brightness
            if b < 0.08, self.phase == .water, !self.phaseLocked {
                self.phase = .ice
                self.autoFroze = true
                // The hidden one: frozen by actual darkness.
                GameCenter.shared.report(.nightfall)
            } else if b > 0.4, self.autoFroze {
                if self.phase == .ice { self.phase = .water }
                self.autoFroze = false
            }
        }
    }

    func toggleIce() {
        guard !phaseLocked else { return }
        autoFroze = false
        phase = (phase == .ice) ? .water : .ice
    }

    /// Steam toggle; from ice this sublimates straight to vapor. Condensing
    /// is always allowed; vaporizing waits out the recharge.
    func toggleSteam() {
        guard !phaseLocked else { return }
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
