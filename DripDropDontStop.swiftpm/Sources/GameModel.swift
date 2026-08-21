import SwiftUI
import UIKit

final class GameModel: ObservableObject {
    @Published var levelNumber = 1
    @Published var levelName = ""
    @Published var hint = ""
    @Published var isIce = false
    @Published var blowLevel: Float = 0
    @Published var finished = false
    @Published var carveAllowed = false
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
    }

    // MARK: Flow

    func startGame(at index: Int) {
        finished = false
        totalScore = 0
        runFromStart = (index == 0)
        scene.loadLevel(index)
        screen = .playing
    }

    func backToMenu() {
        finished = false
        screen = .menu
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
        if runFromStart, totalScore > bestRun {
            bestRun = totalScore
            UserDefaults.standard.set(totalScore, forKey: "dripdrop.bestRun")
        }
    }

    func start() {
        guard !started else { return }
        started = true
        tiltSource.onTilt = { [weak self] v in self?.tilt = v }
        tiltSource.start()
        blow.onLevel = { [weak self] l in self?.blowLevel = l }
        blow.start()
        UIApplication.shared.isIdleTimerDisabled = true

        // Darkness freezes the droplet. iOS has no public ambient-light API,
        // so we use auto-brightness as a proxy: with auto-brightness on,
        // covering the sensor / killing the lights drags screen brightness
        // down. The ❄ button is the reliable path; this is the magic path.
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let b = UIScreen.main.brightness
            if b < 0.08, !self.isIce {
                self.isIce = true
                self.autoFroze = true
            } else if b > 0.4, self.autoFroze {
                self.isIce = false
                self.autoFroze = false
            }
        }
    }

    func toggleIce() {
        autoFroze = false
        isIce.toggle()
    }

    func resetLevel() { scene.reloadCurrent() }

    func restart() { startGame(at: 0) }
}
