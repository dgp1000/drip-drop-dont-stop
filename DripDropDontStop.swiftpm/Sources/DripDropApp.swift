import SwiftUI

@main
struct DripDropApp: App {
    @StateObject private var model = GameModel()

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
    }
}
