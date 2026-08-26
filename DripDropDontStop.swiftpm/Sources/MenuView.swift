import SwiftUI

/// Medals for a level's banked best. One set of thresholds serves every
/// level because the pot decays normalized by par — 1000 at the gun, 525
/// at par, 50 at 2× par — so gold means "par or better" everywhere,
/// silver means inside ~1.5× par, bronze means finished at all.
enum Medal: CaseIterable {
    case gold, silver, bronze

    init?(best: Int) {
        if best >= 525 { self = .gold }
        else if best >= 290 { self = .silver }
        else if best > 0 { self = .bronze }
        else { return nil }
    }

    var color: Color {
        switch self {
        case .gold:   return Color(red: 1.00, green: 0.80, blue: 0.25)
        case .silver: return Color(red: 0.80, green: 0.84, blue: 0.90)
        case .bronze: return Color(red: 0.80, green: 0.52, blue: 0.28)
        }
    }
}

struct MenuView: View {
    @ObservedObject var model: GameModel
    @State private var breathing = false
    @State private var showSecrets = false

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
                    Text("BEST SCORE  ·  \(model.bestRun)")
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Start from level 1 and bank all you can — that\u{2019}s your best score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                medalTally

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(Levels.tiers.enumerated()), id: \.offset) { _, tier in
                            let visible = tier.range.filter(unlocked)
                            if !visible.isEmpty {
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
                                ForEach(visible, id: \.self) { i in
                                    Button {
                                        model.startGame(at: i)
                                    } label: {
                                        LevelRow(index: i, level: Levels.all[i],
                                                 best: model.bestScores[i],
                                                 isNext: isNext(i))
                                    }
                                }
                            }
                        }
                        lockedTeaser
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                Text("Starting at level 1 counts toward your best score.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    showSecrets = true
                } label: {
                    Label("SECRETS", systemImage: "moon.stars.fill")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showSecrets) { SecretsCard() }
    }

    /// Old-people-proof progression: the menu shows only where you've
    /// been and the one place you can go next. A level unlocks when the
    /// one before it has been banked — index-relative, so it survives
    /// the planned difficulty re-sort untouched.
    private func unlocked(_ i: Int) -> Bool {
        i == 0 || model.bestScores[i - 1] > 0
    }

    /// The single next place to go: first unlocked level with no bank yet.
    private func isNext(_ i: Int) -> Bool {
        model.bestScores[i] == 0 && unlocked(i)
    }

    /// A quiet promise that the cave goes deeper.
    @ViewBuilder private var lockedTeaser: some View {
        let locked = Levels.all.indices.filter { !unlocked($0) }.count
        if locked > 0 {
            Label("\(locked) more levels await — finish the newest one to reveal the next.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 14)
        }
    }

    /// Gold/silver/bronze counts across all levels. Hidden until the
    /// first medal exists — the empty state shouldn't advertise a system
    /// the player hasn't met yet.
    @ViewBuilder private var medalTally: some View {
        let earned = model.bestScores.compactMap(Medal.init)
        if !earned.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(Medal.allCases.enumerated()), id: \.offset) { _, medal in
                    let n = earned.filter { $0 == medal }.count
                    if n > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(medal.color)
                            Text("\(n)")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
    }
}

/// The magic paths, spelled out. The darkness freeze and the real-breath
/// updraft are the app's best party tricks and were previously completely
/// undiscoverable — this card is the map to them, worded to preserve a
/// little of the mystery.
private struct SecretsCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.20),
                                    Color(red: 0.02, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Label("SECRETS", systemImage: "moon.stars.fill")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .tracking(4)
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)

                secret(icon: "lightbulb.slash.fill",
                       title: "The dark freezes.",
                       body: "Kill the lights — or cup a hand over the top of the phone — and the droplet ices over on its own. (Auto-brightness must be on; the ❄ button always works.)")
                secret(icon: "wind",
                       title: "Breath is real.",
                       body: "The mic hears a genuine blow. Touch-and-hold is only the understudy — a real puff of air is the true updraft.")
                secret(icon: "rosette",
                       title: "Nightfall.",
                       body: "A hidden Game Center badge waits for anyone the darkness has frozen.")

                Spacer()
            }
            .padding(28)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func secret(icon: String, title: String, body text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

private struct LevelRow: View {
    let index: Int
    let level: Level
    let best: Int
    var isNext = false

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
            if isNext {
                // The one obvious thing to tap.
                Label("PLAY", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.cyan, in: Capsule())
            } else {
                if let medal = Medal(best: best) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(medal.color)
                        .shadow(color: medal.color.opacity(0.6), radius: 3)
                }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isNext ? Color.cyan.opacity(0.8) : .clear, lineWidth: 2))
    }

    /// Which verbs this level offers, at a glance.
    private var verbIcons: some View {
        HStack(spacing: 5) {
            if level.blowAllowed { Image(systemName: "hand.tap.fill") }
            if level.inkBudget > 0 { Image(systemName: "pencil.tip") }
            if level.steamAllowed { Image(systemName: "cloud.fill") }
            if !level.movers.isEmpty { Image(systemName: "arrow.up.arrow.down") }
            if !level.winds.isEmpty { Image(systemName: "wind") }
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
            for w in level.winds {
                ctx.fill(Path(roundedRect: rect(w.rect), cornerRadius: 2),
                         with: .color(.mint.opacity(0.22)))
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
