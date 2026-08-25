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
                    // Old-people-proof: restart is a real labeled button,
                    // not a mystery glyph.
                    Button {
                        model.resetLevel()
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.orange.opacity(0.9), in: Capsule())
                            .shadow(color: .orange.opacity(0.45), radius: 6)
                    }
                    Button {
                        model.backToMenu()
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(9)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
                Text(model.hint)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Old-people-proof control bar: meters on their own slim
                // row, then BIG phase buttons that read from across the
                // room. Two rows so ink + lift + two buttons always fit.
                VStack(alignment: .leading, spacing: 10) {
                    if model.carveAllowed || model.blowAllowed {
                        HStack(spacing: 16) {
                            if model.carveAllowed {
                                meter(label: "INK", icon: "pencil.tip",
                                      frac: model.inkFrac,
                                      color: Color(red: 0.6, green: 0.9, blue: 1.0))
                                    .frame(maxWidth: 110)
                            }
                            if model.blowAllowed {
                                meter(label: "LIFT", icon: "hand.tap.fill",
                                      frac: model.liftFrac,
                                      color: model.liftFrac > 0.3 ? .cyan : .orange)
                                    .frame(maxWidth: 130)
                            }
                            Spacer()
                        }
                    }

                    HStack(spacing: 14) {
                        phaseButton(
                            title: model.isIce ? "MELT" : "FREEZE",
                            icon: model.isIce ? "drop.fill" : "snowflake",
                            gradient: model.isIce
                                ? [Color(red: 0.15, green: 0.35, blue: 0.75),
                                   Color(red: 0.10, green: 0.20, blue: 0.50)]
                                : [Color(red: 0.15, green: 0.75, blue: 0.95),
                                   Color(red: 0.10, green: 0.40, blue: 0.85)],
                            glow: .cyan,
                            disabled: model.phaseLocked
                        ) { model.toggleIce() }

                        if model.steamAllowed {
                            phaseButton(
                                title: model.phase == .steam ? "CONDENSE" : "STEAM",
                                icon: model.phase == .steam ? "drop.fill" : "cloud.fill",
                                gradient: model.phase == .steam
                                    ? [Color(white: 0.45), Color(white: 0.25)]
                                    : [Color(white: 0.85), Color(white: 0.55)],
                                glow: .white,
                                disabled: model.phaseLocked
                                    || (model.phase != .steam && !model.steamReady)
                            ) { model.toggleSteam() }
                        }

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)

            if model.briefing { briefingCard }

            if let phase = model.countdown {
                Text(phase)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(Color.green)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
                    .id(phase)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }

            if model.finished { finishOverlay }
        }
        .animation(.spring(duration: 0.3), value: model.countdown)
        .animation(.spring(duration: 0.35), value: model.briefing)
        #if targetEnvironment(simulator)
        .modifier(SimTiltKeys(model: model))
        #endif
    }

    /// The pre-level briefing: name, hint, START. Sits on screen for as
    /// long as the player wants — the level clock doesn't run until the
    /// tap. Death restarts and ↺ skip it.
    private var briefingCard: some View {
        VStack(spacing: 18) {
            Text("LEVEL \(model.levelNumber)")
                .font(.system(.caption, design: .rounded).weight(.black))
                .tracking(3)
                .foregroundStyle(.cyan)
            Text(model.levelName)
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(model.hint)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.beginLevel()
            } label: {
                Label("START", systemImage: "play.fill")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .cyan.opacity(0.5), radius: 10, y: 2)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 30)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    /// A big, unmistakable phase button: chunky icon, loud label,
    /// gradient fill, glow. Steam's text scales down a notch so
    /// "CONDENSE" never wraps beside FREEZE.
    private func phaseButton(title: String, icon: String, gradient: [Color],
                             glow: Color, disabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                LinearGradient(colors: gradient,
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.35), lineWidth: 1.5))
            .shadow(color: glow.opacity(disabled ? 0 : 0.45), radius: 8, y: 2)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    /// A labeled resource meter (ink / lift).
    private func meter(label: String, icon: String, frac: CGFloat,
                       color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
        }
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
