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
    static let leaderboardID = "dripdrop.bestrun"
    private(set) var available = false

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

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
