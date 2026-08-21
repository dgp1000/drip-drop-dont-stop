import SwiftUI

struct MenuView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("💧")
                    .font(.system(size: 54))
                    .padding(.top, 24)
                VStack(spacing: 2) {
                    Text("DRIP DROP")
                    Text("DONT STOP")
                }
                .font(.system(.title2, design: .rounded).weight(.black))
                .tracking(6)
                .foregroundStyle(.cyan)

                if model.bestRun > 0 {
                    Text("BEST RUN  ·  \(model.bestRun)")
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Finish a full run from level 1 to set a best run score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(Levels.all.enumerated()), id: \.offset) { i, level in
                            Button {
                                model.startGame(at: i)
                            } label: {
                                HStack(spacing: 14) {
                                    Text("\(i + 1)")
                                        .font(.system(.title3, design: .monospaced).weight(.bold))
                                        .foregroundStyle(.cyan)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(.white.opacity(0.08)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.name)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("target \(Int(level.par))s")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(model.bestScores[i] > 0 ? "\(model.bestScores[i])" : "—")
                                            .font(.system(.body, design: .monospaced).weight(.bold))
                                            .foregroundStyle(model.bestScores[i] > 0 ? .orange : .white.opacity(0.25))
                                        Text("BEST")
                                            .font(.system(size: 8, weight: .bold))
                                            .tracking(1.5)
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                Text("Starting at level 1 counts toward your best run.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
    }
}
