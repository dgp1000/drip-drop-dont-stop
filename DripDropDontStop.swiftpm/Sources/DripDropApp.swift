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
            // The reminder ladder runs only while the player is away:
            // rescheduled from fresh progress every time we background.
            if phase == .background {
                Reminders.shared.sync(bestScores: model.bestScores,
                                      bestRun: model.bestRun)
            }
        }
    }
}
