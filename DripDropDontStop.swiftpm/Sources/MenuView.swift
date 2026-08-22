import SwiftUI

struct MenuView: View {
    @ObservedObject var model: GameModel
    @State private var breathing = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.26),
                                    Color(red: 0.06, green: 0.08, blue: 0.16),
                                    Color(red: 0.02, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("💧")
                    .font(.system(size: 54))
                    .scaleEffect(breathing ? 1.08 : 0.94)
                    .offset(y: breathing ? -5 : 5)
                    .shadow(color: .cyan.opacity(0.55), radius: breathing ? 22 : 10)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                               value: breathing)
                    .onAppear { breathing = true }
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
                        ForEach(Array(Levels.tiers.enumerated()), id: \.offset) { _, tier in
                            HStack(spacing: 10) {
                                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                                Text(tier.title)
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2.5)
                                    .foregroundStyle(.white.opacity(0.45))
                                    .fixedSize()
                                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                            }
                            .padding(.top, 8)
                            ForEach(Array(tier.range), id: \.self) { i in
                                Button {
                                    model.startGame(at: i)
                                } label: {
                                    LevelRow(index: i, level: Levels.all[i],
                                             best: model.bestScores[i])
                                }
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

private struct LevelRow: View {
    let index: Int
    let level: Level
    let best: Int

    var body: some View {
        HStack(spacing: 12) {
            LevelThumbnail(level: level)
            VStack(alignment: .leading, spacing: 3) {
                Text(level.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.cyan)
                    Text("target \(Int(level.par))s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    verbIcons
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(best > 0 ? "\(best)" : "—")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundStyle(best > 0 ? .orange : .white.opacity(0.25))
                Text("BEST")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    /// Which verbs this level offers, at a glance.
    private var verbIcons: some View {
        HStack(spacing: 5) {
            if level.blowAllowed { Image(systemName: "wind") }
            if level.inkBudget > 0 { Image(systemName: "pencil.tip") }
            if level.steamAllowed { Image(systemName: "cloud.fill") }
            if !level.movers.isEmpty { Image(systemName: "arrow.up.arrow.down") }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white.opacity(0.45))
    }
}

/// A tiny schematic of the diorama, drawn straight from the level data —
/// slate walls, green goal, red drains, white icicles, cyan grates.
private struct LevelThumbnail: View {
    let level: Level

    var body: some View {
        Canvas { ctx, size in
            func rect(_ u: CGRect) -> CGRect {
                CGRect(x: u.minX * size.width,
                       y: (1 - u.minY - u.height) * size.height,
                       width: max(u.width * size.width, 1.5),
                       height: max(u.height * size.height, 1.5))
            }
            for w in level.walls {
                ctx.fill(Path(roundedRect: rect(w), cornerRadius: 1),
                         with: .color(.white.opacity(0.5)))
            }
            for r in level.ramps {
                let rr = CGRect(x: r.center.x - r.size.width / 2,
                                y: r.center.y - r.size.height / 2,
                                width: r.size.width, height: r.size.height)
                ctx.fill(Path(roundedRect: rect(rr), cornerRadius: 1),
                         with: .color(.white.opacity(0.5)))
            }
            for m in level.movers {
                let mr = CGRect(x: m.center.x - m.size.width / 2,
                                y: m.center.y - m.size.height / 2,
                                width: m.size.width, height: m.size.height)
                ctx.fill(Path(roundedRect: rect(mr), cornerRadius: 1),
                         with: .color(.cyan.opacity(0.8)))
            }
            for z in level.zones {
                let color: Color
                switch z.kind {
                case .goal:  color = .green
                case .grate: color = .cyan.opacity(0.55)
                case .drain: color = z.rect.minY > 0.06
                    ? .white.opacity(0.85)      // icicles
                    : .red.opacity(0.75)        // pit
                }
                ctx.fill(Path(roundedRect: rect(z.rect), cornerRadius: 1),
                         with: .color(color))
            }
            // Spawn marker.
            let s = CGPoint(x: level.spawn.x * size.width,
                            y: (1 - level.spawn.y) * size.height)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - 2, y: s.y - 2, width: 4, height: 4)),
                     with: .color(Color(red: 0.4, green: 0.7, blue: 1)))
        }
        .frame(width: 42, height: 58)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.05, green: 0.06, blue: 0.11)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
