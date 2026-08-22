import SwiftUI
import SpriteKit

struct GameView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            SpriteView(scene: model.scene)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                HStack(alignment: .top) {
                    Text("LEVEL \(model.levelNumber) · \(model.levelName.uppercased())")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(model.totalScore)")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                        Text("+\(model.availableScore)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(model.availableScore >= 500 ? .cyan : .orange)
                    }
                    Button {
                        model.resetLevel()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Button {
                        model.backToMenu()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Text(model.hint)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        model.toggleIce()
                    } label: {
                        Label(model.isIce ? "Melt" : "Freeze",
                              systemImage: model.isIce ? "drop.fill" : "snowflake")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                model.isIce ? Color.blue.opacity(0.4) : Color.cyan.opacity(0.25),
                                in: Capsule())
                    }

                    if model.steamAllowed {
                        Button {
                            model.toggleSteam()
                        } label: {
                            Label(model.phase == .steam ? "Condense" : "Steam",
                                  systemImage: model.phase == .steam ? "drop.fill" : "cloud.fill")
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    model.phase == .steam ? Color.gray.opacity(0.5)
                                                          : Color.white.opacity(0.18),
                                    in: Capsule())
                        }
                        .disabled(model.phase != .steam && !model.steamReady)
                        .opacity(model.phase != .steam && !model.steamReady ? 0.4 : 1)
                    }

                    Image(systemName: model.carveAllowed ? "pencil.tip" : "pencil.slash")
                        .font(.callout)
                        .foregroundStyle(model.carveAllowed ? Color.cyan : Color.white.opacity(0.3))

                    if model.blowAllowed {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.micActive ? "MIC" : "HOLD")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.5))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule().fill(.cyan)
                                    .frame(width: geo.size.width * CGFloat(min(1, model.blowLevel)))
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(maxWidth: 110)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)

            if let phase = model.countdown {
                VStack(spacing: 22) {
                    Text(phase)
                        .font(.system(size: phase == "GO!" ? 72 : 52,
                                      weight: .black, design: .rounded))
                        .foregroundStyle(phase == "GO!" ? Color.green : Color.orange)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
                        .id(phase)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                    if phase != "GO!" {
                        Text(model.hint)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 34)
                            .transition(.opacity)
                    }
                }
            }

            if model.finished { finishOverlay }
        }
        .animation(.spring(duration: 0.3), value: model.countdown)
        #if targetEnvironment(simulator)
        .modifier(SimTiltKeys(model: model))
        #endif
    }

    private var finishOverlay: some View {
        VStack(spacing: 14) {
            Text("💧")
                .font(.system(size: 52))
            Text("Run complete")
                .font(.title3.weight(.semibold))
            Text("\(model.totalScore)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            if model.bestRun > 0 {
                Text("Best run: \(model.bestRun)")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text("The pot drains from the moment a level starts — the faster you finish, the more you bank.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Menu") { model.backToMenu() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Button("Play again") { model.restart() }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(40)
    }
}
