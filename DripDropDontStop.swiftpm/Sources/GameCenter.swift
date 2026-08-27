// Game Center: a single leaderboard for the honest best run. Everything
// here is defensive — if authentication fails (no account, or the
// entitlement isn't available to a .swiftpm app package), the game runs
// exactly as before and no Game Center UI ever appears.
//
// CAVEAT: .swiftpm app packages can't declare custom entitlements, and
// Game Center formally wants com.apple.developer.game-center. If device
// auth fails with an entitlement error, shipping this means migrating to
// an .xcodeproj. ASC setup still needed either way: App → Services →
// Game Center → create leaderboard "dripdrop.bestrun" (classic, best
// score, integer), and enable Game Center on the version page.

import GameKit
import UIKit

final class GameCenter {
    static let shared = GameCenter()
    /// v1.3+: fresh board so launch day starts clean — TestFlight-era
    /// scores live on the old "dripdrop.bestrun" and stay there.
    static let leaderboardID = "dripdrop.bestscore"
    private(set) var available = false

    /// Achievements. Every ID must exist in ASC (App → Services → Game
    /// Center → Achievements) or the submit just logs and no-ops:
    ///   dripdrop.firstbasin — "First Drop"   — bank any level
    ///   dripdrop.underpar   — "Quickdrop"    — bank a level at par or better
    ///   dripdrop.honestrun  — "Dont Stop"    — finish a full run from level 1
    ///   dripdrop.allgold    — "Midas Drip"   — gold on every level (progress %)
    ///   dripdrop.nightfall  — "Nightfall"    — freeze by real darkness (hidden!)
    ///   dripdrop.twentybasins — "Twenty Basins" — complete any 20 levels
    ///   dripdrop.everybasin  — "Every Basin"   — complete all levels (progress %)
    ///   dripdrop.depths      — "Into the Depths" — clear THE DEPTHS tier
    ///   dripdrop.galeworks   — "Storm Chaser"  — clear THE GALEWORKS tier
    ///   dripdrop.flashflood  — "Flash Flood"   — bank 900+ on one level
    ///   dripdrop.stubborn    — "Stubborn"      — 100 lifetime deaths (progress %)
    enum Achievement: String {
        case firstBasin = "dripdrop.firstbasin"
        case underPar = "dripdrop.underpar"
        case honestRun = "dripdrop.honestrun"
        case allGold = "dripdrop.allgold"
        case nightfall = "dripdrop.nightfall"
        case twentyBasins = "dripdrop.twentybasins"
        case everyBasin = "dripdrop.everybasin"
        case depths = "dripdrop.depths"
        case galeworks = "dripdrop.galeworks"
        case flashFlood = "dripdrop.flashflood"
        case stubborn = "dripdrop.stubborn"
    }
    /// Highest percent already reported this session — GC dedups
    /// server-side, but there's no reason to spam it every bank.
    private var reported: [Achievement: Double] = [:]

    func start(onChange: @escaping (Bool) -> Void) {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                // Game Center wants to show its sign-in sheet.
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            self.available = GKLocalPlayer.local.isAuthenticated
            if let error {
                NSLog("DripDrop GameCenter unavailable: \(error.localizedDescription)")
            }
            // The floating access point lives on the menu only; the model
            // toggles it on screen changes via setAccessPoint.
            GKAccessPoint.shared.location = .topLeading
            onChange(self.available)
        }
    }

    /// Show or hide the floating Game Center widget (menu only, and only
    /// when authenticated — an inert widget is worse than none).
    func setAccessPoint(visible: Bool) {
        GKAccessPoint.shared.isActive = visible && available
    }

    /// Submit an honest-run total. Fire and forget; failures are logged.
    func submitBestRun(_ score: Int) {
        guard available, score > 0 else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [Self.leaderboardID]) { error in
            if let error {
                NSLog("DripDrop GameCenter submit failed: \(error.localizedDescription)")
            }
        }
    }

    /// Report an achievement (optionally partial). Fire and forget, same
    /// contract as the leaderboard: failures log, the game never notices.
    func report(_ achievement: Achievement, percent: Double = 100) {
        guard available else { return }
        let pct = min(100, max(0, percent))
        guard pct > (reported[achievement] ?? 0) else { return }
        reported[achievement] = pct
        let a = GKAchievement(identifier: achievement.rawValue)
        a.percentComplete = pct
        a.showsCompletionBanner = true
        GKAchievement.report([a]) { error in
            if let error {
                NSLog("DripDrop GameCenter achievement failed: \(error.localizedDescription)")
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
