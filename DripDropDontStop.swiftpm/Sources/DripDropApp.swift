import SwiftUI
import UIKit

/// Runtime orientation lock, over and above the plist declarations —
/// David saw rotation slip through (iPad compat container); this is the
/// authority every container asks.
final class OrientationLock: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask { .portrait }
}

@main
struct DripDropApp: App {
    @UIApplicationDelegateAdaptor(OrientationLock.self) private var delegate
    @StateObject private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.screen == .playing {
                    GameView(model: model)
                } else {
                    MenuView(model: model)
                }
            }
            .onAppear { model.start() }
            .preferredColorScheme(.dark)
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                // The reminder ladder runs only while the player is away:
                // rescheduled from fresh progress every time we background.
                Reminders.shared.sync(bestScores: model.bestScores,
                                      bestRun: model.bestRun)
                // Engagement analytics: close the level visit and the
                // session at the moment they walk away.
                if model.screen == .playing { model.logAbandonIfNeeded() }
                model.bankRunScore()
                Analytics.sessionEnd(
                    levelIndex: model.screen == .playing ? model.levelNumber : nil)
            case .active:
                Analytics.sessionStart()
            default:
                break
            }
        }
    }
}
