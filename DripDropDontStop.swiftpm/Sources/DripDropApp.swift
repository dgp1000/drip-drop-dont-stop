import SwiftUI

@main
struct DripDropApp: App {
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
