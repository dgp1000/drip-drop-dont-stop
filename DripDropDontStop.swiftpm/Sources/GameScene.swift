// The diorama: SpriteKit physics, levels defined in unit coordinates.
//
// Control philosophy (lesson from the Maestro prototype): tilt is a
// CONTINUOUS input with instant visual feedback — nothing to detect,
// nothing to misfire. The sensors that could misfire (mic, light) only
// ever help the player; they never gate basic movement.

import SpriteKit
import UIKit

// MARK: - Level data (unit coordinates: x 0→1 left→right, y 0→1 bottom→top)

enum ZoneKind { case drain, grate, goal }

/// Per-level ambience: backdrop gradient, caustic tint, mote color.
/// The droplet's refraction shader receives the same palette so its
/// transparency stays truthful in every mood.
enum Mood {
    case abyss      // deep blue — the default diorama
    case frost      // pale, freezing (the ice-lesson levels)
    case warm       // amber boiler-light (the breath/heat levels)
    case storm      // violet dusk (the capstones)
    case mist       // grey-green vapor (the steam intro)

    /// (top, mid, bottom) backdrop gradient as RGB triples.
    var gradient: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch self {
        // Abyss ambience went warm-brown when its diorama became the night
        // kitchen — the droplet's refraction must bend kitchen light.
        case .abyss: return (.init(0.12, 0.09, 0.075), .init(0.07, 0.055, 0.045), .init(0.045, 0.035, 0.03))
        case .frost: return (.init(0.16, 0.20, 0.30), .init(0.10, 0.14, 0.22), .init(0.05, 0.08, 0.13))
        case .warm:  return (.init(0.22, 0.12, 0.10), .init(0.13, 0.07, 0.08), .init(0.06, 0.03, 0.05))
        case .storm: return (.init(0.16, 0.10, 0.26), .init(0.10, 0.06, 0.17), .init(0.04, 0.02, 0.09))
        case .mist:  return (.init(0.14, 0.18, 0.20), .init(0.09, 0.12, 0.14), .init(0.04, 0.06, 0.07))
        }
    }

    var causticTint: SIMD3<Float> {
        switch self {
        case .abyss: return .init(0.30, 0.55, 0.90)
        case .frost: return .init(0.55, 0.75, 0.95)
        case .warm:  return .init(0.95, 0.55, 0.25)
        case .storm: return .init(0.60, 0.45, 0.95)
        case .mist:  return .init(0.55, 0.80, 0.75)
        }
    }

    var moteColor: UIColor {
        switch self {
        case .abyss: return UIColor(red: 0.55, green: 0.75, blue: 1.00, alpha: 1)
        case .frost: return UIColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 1)
        case .warm:  return UIColor(red: 1.00, green: 0.75, blue: 0.50, alpha: 1)
        case .storm: return UIColor(red: 0.75, green: 0.65, blue: 1.00, alpha: 1)
        case .mist:  return UIColor(red: 0.75, green: 0.90, blue: 0.85, alpha: 1)
        }
    }
}

struct Zone {
    let rect: CGRect
    let kind: ZoneKind
}

/// An angled wall. Center and size in unit coordinates, rotation in radians.
struct Ramp {
    let center: CGPoint
    let size: CGSize
    let rotation: CGFloat
}

/// A platform that oscillates between (center - travel) and (center + travel)
/// with an ease-in-out cycle. Vertical movers (elevators) are the reliable
/// kind — SpriteKit's static bodies don't carry passengers horizontally.
struct Mover {
    let center: CGPoint     // midpoint of travel, unit coords
    let size: CGSize
    let travel: CGVector    // half-amplitude, unit coords
    let period: Double      // full cycle, seconds
    /// Fraction of a period to hold at the start position before cycling —
    /// lets two lifts run anti-phase (0.5) for transfer puzzles.
    var phase: Double = 0
}

struct Level {
    let name: String
    let hint: String
    let spawn: CGPoint
    let walls: [CGRect]
    let zones: [Zone]
    var ramps: [Ramp] = []
    var movers: [Mover] = []
    /// Carving ink for this level (stroke-length budget, points).
    /// 0 = no carving — early levels stay pure tests of their own verb,
    /// otherwise a drawn ramp is a skeleton key for everything.
    var inkBudget: CGFloat = 0
    /// Par time in seconds: the score pot holds at 1000 until par elapses,
    /// then decays. Finish under par for the full pot.
    var par: Double = 20
    /// Whether the STEAM button is offered. Off for levels 1–13 so the
    /// original tuning survives — same gating precedent as ink.
    var steamAllowed = false
    /// Whether lift (touch-hold or breath) works. Default is now FALSE:
    /// lift belongs only to the levels designed around it (2, 7, 8, 10,
    /// 12, 13) — everywhere else the verb set stays pure.
    var blowAllowed = false
    /// Ambience palette for this diorama.
    var mood: Mood = .abyss
    /// Seconds of lift thrust per level (tester-requested air supply):
    /// hold/blow drains it; empty = no more lift until restart. Death does
    /// NOT refill it — the ↺ restart does. (8 → 4 → 2 across David's
    /// tuning passes: scarcity is the point.)
    var liftBudget: Double = 2
    /// How long ice holds before melting back on its own. Expiring over a
    /// grate is death — levels with long mandatory skates (11, 22…) may
    /// need a longer freeze.
    var iceDuration: Double = 8
}

enum Levels {
    /// Menu sections. Purely presentational — level order (and the
    /// UserDefaults best-score keys, which are index-based) is untouched.
    static let tiers: [(title: String, range: Range<Int>)] = [
        ("THE BASICS", 0..<4),      // one verb each: tilt, blow, freeze, momentum
        ("INK & AIR", 4..<8),       // carving and breath, alone and together
        ("MASTERY", 8..<10),        // routing and phase timing
        ("MACHINERY", 10..<13),     // movers
        ("STEAM", 13..<18),         // the third phase
        ("EXPERT", 18..<22),        // everything, one route each
    ]

    static let all: [Level] = [
        Level(name: "The Descent",
              hint: "TILT the phone to roll the droplet down into the glowing basin.",
              spawn: CGPoint(x: 0.12, y: 0.90),
              walls: [
                  CGRect(x: 0.00, y: 0.68, width: 0.62, height: 0.030),
                  CGRect(x: 0.38, y: 0.44, width: 0.62, height: 0.030),
                  CGRect(x: 0.00, y: 0.20, width: 0.62, height: 0.030),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.20, height: 0.05), kind: .goal),
              ],
              par: 9),
        Level(name: "Updraft",
              hint: "HOLD the screen (or blow on the mic) to ride the updraft over the wall — the LIFT bar is your air supply. Empty means restart.",
              spawn: CGPoint(x: 0.15, y: 0.25),
              walls: [
                  CGRect(x: 0.47, y: 0.00, width: 0.06, height: 0.40),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.20, height: 0.05), kind: .goal),
              ],
              par: 12,
              blowAllowed: true,
              mood: .warm),
        Level(name: "Cold Crossing",
              hint: "Tap FREEZE to turn to ice — ice slides over the blue grates that swallow water.",
              spawn: CGPoint(x: 0.90, y: 0.72),
              walls: [
                  CGRect(x: 0.25, y: 0.60, width: 0.75, height: 0.030),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.28, y: 0.00, width: 0.44, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.80, y: 0.015, width: 0.16, height: 0.05), kind: .goal),
              ],
              par: 14,
              mood: .frost),
        Level(name: "Leap of Frost",
              hint: "FREEZE at the top, then ride the ramp — only fast ice makes the jump. Water is too slow.",
              spawn: CGPoint(x: 0.08, y: 0.88),
              walls: [
                  CGRect(x: 0.78, y: 0.32, width: 0.22, height: 0.03),   // landing ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.45, y: 0.00, width: 0.55, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.87, y: 0.35, width: 0.12, height: 0.05), kind: .goal),
              ],
              ramps: [
                  Ramp(center: CGPoint(x: 0.24, y: 0.66),
                       size: CGSize(width: 0.40, height: 0.028),
                       rotation: -0.28),
              ],
              par: 16,
              mood: .frost),
        Level(name: "Aqueduct",
              hint: "DRAW on the screen with your finger to create a path to the basin. Drawn paths fade.",
              spawn: CGPoint(x: 0.15, y: 0.90),
              walls: [],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 0.85, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.87, y: 0.015, width: 0.12, height: 0.05), kind: .goal),
              ],
              inkBudget: 420,
              par: 12),
        Level(name: "Icefall",
              hint: "DRAW a slide down to the LEFT, then FREEZE and fly to the ledge — under the icicles. One stroke of ink.",
              spawn: CGPoint(x: 0.90, y: 0.88),
              walls: [
                  CGRect(x: 0.00, y: 0.36, width: 0.16, height: 0.03),   // landing ledge (left wall)
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.20, y: 0.78, width: 0.40, height: 0.04), kind: .drain),  // icicles: thread under
                  Zone(rect: CGRect(x: 0.01, y: 0.39, width: 0.11, height: 0.05), kind: .goal),
              ],
              inkBudget: 300,
              par: 20,
              mood: .frost),
        Level(name: "The Chimney",
              hint: "BLOW in short breaths to climb. Rest on the shelves — but land clear of the slatted patches.",
              spawn: CGPoint(x: 0.80, y: 0.08),
              walls: [
                  CGRect(x: 0.00, y: 0.30, width: 0.55, height: 0.03),
                  CGRect(x: 0.45, y: 0.52, width: 0.55, height: 0.03),
                  CGRect(x: 0.00, y: 0.74, width: 0.55, height: 0.03),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 0.70, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.35, y: 0.33, width: 0.20, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.45, y: 0.55, width: 0.25, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.05, y: 0.775, width: 0.14, height: 0.05), kind: .goal),
              ],
              par: 32,
              blowAllowed: true,
              mood: .warm,
              liftBudget: 3),       // the long climb gets a deeper lung
        Level(name: "Boost Slide",
              hint: "FREEZE, tilt to skate, and BLOW quick puffs to hop the bump and the pit. Stay LOW — icicles above.",
              spawn: CGPoint(x: 0.07, y: 0.10),
              walls: [
                  CGRect(x: 0.38, y: 0.00, width: 0.05, height: 0.08),   // the bump
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.58, y: 0.00, width: 0.13, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.25, y: 0.34, width: 0.65, height: 0.05), kind: .drain),  // icicle field: no flying
                  Zone(rect: CGRect(x: 0.15, y: 0.00, width: 0.85, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.88, y: 0.015, width: 0.11, height: 0.05), kind: .goal),
              ],
              par: 20,
              blowAllowed: true,
              mood: .storm),
        // Switchback's route REQUIRES a mid-slide puff over the storey-2
        // pit — it belongs to the lift set (missed in the first
        // blowAllowed audit; David found it unwinnable without lift).
        Level(name: "Switchback",
              hint: "FREEZE early — grates on every storey. Work right, drop, work LEFT and PUFF over the pit mid-slide, then skate home.",
              spawn: CGPoint(x: 0.06, y: 0.90),
              walls: [
                  CGRect(x: 0.00, y: 0.70, width: 0.75, height: 0.03),
                  CGRect(x: 0.30, y: 0.42, width: 0.70, height: 0.03),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.28, y: 0.73, width: 0.30, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.46, y: 0.45, width: 0.16, height: 0.02), kind: .drain),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 0.55, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.02, y: 0.015, width: 0.12, height: 0.05), kind: .goal),
              ],
              par: 24,
              blowAllowed: true,
              // Three storeys of mandatory skating with grates on every
              // one — the default 8 s forces a mid-route refreeze fiddle
              // that isn't the level's point.
              iceDuration: 14),
        Level(name: "Meltpoint",
              hint: "FREEZE for the grates, puff the pit — then MELT mid-air to drop short of the far drain. Ice flies; water falls.",
              spawn: CGPoint(x: 0.06, y: 0.90),
              walls: [],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 0.55, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.55, y: 0.00, width: 0.20, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.28, y: 0.32, width: 0.47, height: 0.05), kind: .drain),  // icicles: no flying
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.12, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.90, y: 0.00, width: 0.10, height: 0.035), kind: .drain),
              ],
              par: 18,
              blowAllowed: true,
              mood: .warm),
        // One way only: no blowing, all-grate floor. Freeze mid-fall, board
        // the (narrow, fast) lift when it's low, ride up, roll off right.
        Level(name: "Rising Water",
              hint: "No breath in here, and the whole floor is a grate: FREEZE before you land, board the lift LOW, ride it up, roll off at the top.",
              spawn: CGPoint(x: 0.08, y: 0.88),
              walls: [
                  CGRect(x: 0.74, y: 0.62, width: 0.24, height: 0.03),   // top ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.82, y: 0.648, width: 0.12, height: 0.045), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .grate),
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.58, y: 0.32),
                        size: CGSize(width: 0.16, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.34), period: 4.2),
              ],
              par: 18,
              blowAllowed: false,
              // Freeze happens mid-fall, then up to a full 4.2 s lift
              // cycle waiting on the all-grate floor plus the ride — the
              // worst case brushes the default 8 s clock.
              iceDuration: 12),
        // One way only: the mid shelf no longer overhangs the lower shelf
        // (a direct drop lands in the drain), so the lift is mandatory —
        // leap onto it from the mid shelf as it passes, ride DOWN, and puff
        // LOW back across the gap. Icicles over the goal punish high hops.
        Level(name: "Cold Storage",
              hint: "FREEZE before you land — shelves are slatted. Leap from the mid shelf onto the passing lift, ride DOWN, and puff LOW across the gap. Icicles hang over the goal.",
              spawn: CGPoint(x: 0.08, y: 0.86),
              walls: [
                  CGRect(x: 0.00, y: 0.80, width: 0.35, height: 0.03),   // top shelf
                  CGRect(x: 0.22, y: 0.55, width: 0.34, height: 0.03),   // mid shelf
                  CGRect(x: 0.30, y: 0.18, width: 0.22, height: 0.03),   // lower shelf
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.33, y: 0.215, width: 0.11, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.26, y: 0.58, width: 0.22, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.30, y: 0.21, width: 0.18, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.30, y: 0.32, width: 0.25, height: 0.035), kind: .drain),  // icicles: no high hops
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.82, y: 0.415),
                        size: CGSize(width: 0.20, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.135), period: 4.5),
              ],
              par: 26,
              blowAllowed: true,
              mood: .frost,
              // Slatted shelves are lethal to melt on, and boarding the
              // 4.5 s-period lift means standing on one while it comes
              // around.
              iceDuration: 12),
        // One way only: the goal ledge is capped (ceiling + side wall), so
        // the sole entry is the hop from the lift's apex. Ink is cut to a
        // catch-slide's worth — it can no longer carve a road to the goal.
        Level(name: "The Long Pour",
              hint: "DRAW a catch-slide as you fall (ink is tight), FREEZE on the perch, skate, puff the pit — the goal ledge is capped: enter from the lift side only.",
              spawn: CGPoint(x: 0.42, y: 0.92),
              walls: [
                  CGRect(x: 0.00, y: 0.30, width: 0.25, height: 0.03),   // the perch
                  CGRect(x: 0.52, y: 0.52, width: 0.22, height: 0.03),   // goal ledge
                  CGRect(x: 0.40, y: 0.63, width: 0.36, height: 0.03),   // cap over the ledge
                  CGRect(x: 0.48, y: 0.52, width: 0.04, height: 0.14),   // side wall: no left entry
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.55, y: 0.55, width: 0.14, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 0.62, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.62, y: 0.00, width: 0.14, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.76, y: 0.00, width: 0.24, height: 0.035), kind: .grate),
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.86, y: 0.28),
                        size: CGSize(width: 0.18, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.29), period: 5),
              ],
              inkBudget: 160,
              par: 34,
              blowAllowed: true,
              mood: .storm,
              // Grate skate + puff + waiting out the 5 s lift period while
              // standing on grates: the worst-case ice window is ~11 s.
              iceDuration: 12),
        // MARK: v1.1 — the steam levels. STEAM rises as vapor, drifts with
        // reduced tilt authority, ignores floor drains and grates, dies to
        // icicles, can't enter the basin, and condenses back to water after
        // a few seconds. Only these levels offer the button (steamAllowed).
        // One way only: no breath, and the right chamber's floor is a grate
        // with the basin as its only safe island — steam over the divider,
        // drift, and condense DIRECTLY above the goal. (Goal listed first:
        // the same-frame zone check must see it before the grate.)
        Level(name: "Vapor",
              hint: "Tap STEAM to rise as vapor and drift with TILT. The right floor is a grate — condense directly over the basin. Vapor can't enter it.",
              spawn: CGPoint(x: 0.15, y: 0.10),
              walls: [
                  CGRect(x: 0.47, y: 0.00, width: 0.06, height: 0.62),   // the divider
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.18, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.53, y: 0.00, width: 0.47, height: 0.035), kind: .grate),
              ],
              par: 12,
              steamAllowed: true,
              blowAllowed: false,
              mood: .mist),
        // One way only: smaller stones, and an icicle sky caps the hops —
        // vaporize, condense EARLY, fall onto the next stone, recharge.
        Level(name: "Stepping Stones",
              hint: "Vapor hops under an icicle sky: STEAM up, condense EARLY, land each stone while it recharges. The floor swallows everything.",
              spawn: CGPoint(x: 0.10, y: 0.18),
              walls: [
                  CGRect(x: 0.05, y: 0.12, width: 0.14, height: 0.03),
                  CGRect(x: 0.44, y: 0.20, width: 0.14, height: 0.03),
                  CGRect(x: 0.81, y: 0.12, width: 0.14, height: 0.03),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.30, y: 0.48, width: 0.40, height: 0.04), kind: .drain),  // icicle sky
                  Zone(rect: CGRect(x: 0.83, y: 0.155, width: 0.11, height: 0.05), kind: .goal),
              ],
              par: 20,
              steamAllowed: true,
              blowAllowed: false,
              mood: .storm),
        // One way only: two icicle fronts with offset gaps and a single
        // perch. Burst up the left gap, drift right, condense on the perch,
        // recharge, then burst up the right gap onto the top-right ledge.
        Level(name: "Cold Front",
              hint: "Two icicle fronts. STEAM up the LEFT gap, condense on the perch, let it recharge — then up the RIGHT gap to the ledge.",
              spawn: CGPoint(x: 0.10, y: 0.08),
              walls: [
                  CGRect(x: 0.50, y: 0.50, width: 0.33, height: 0.03),   // the perch
                  CGRect(x: 0.70, y: 0.88, width: 0.30, height: 0.03),   // goal ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.30, y: 0.38, width: 0.70, height: 0.04), kind: .drain),  // front 1: gap left
                  Zone(rect: CGRect(x: 0.00, y: 0.72, width: 0.55, height: 0.04), kind: .drain),  // front 2: gap right
                  Zone(rect: CGRect(x: 0.78, y: 0.915, width: 0.14, height: 0.05), kind: .goal),
              ],
              par: 20,
              steamAllowed: true,
              blowAllowed: false,
              mood: .frost),
        // One way only: a full ceiling at 0.60 — solid slab on the left,
        // icicles on the right — with the ledge below it. Early vapor gets
        // pinned under the slab, drifts into the icicle seam, and dies; the
        // only survivable vaporize is from the right half of the grate
        // floor, which you can only reach by freezing and skating.
        Level(name: "Boiler Room",
              hint: "FREEZE to land on the grates and skate RIGHT — then STEAM straight from ice (sublime!) and condense on the ledge before the icicle ceiling.",
              spawn: CGPoint(x: 0.08, y: 0.50),
              walls: [
                  CGRect(x: 0.00, y: 0.60, width: 0.55, height: 0.03),   // slab cap, left half
                  CGRect(x: 0.64, y: 0.40, width: 0.30, height: 0.03),   // the ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .grate),
                  Zone(rect: CGRect(x: 0.55, y: 0.60, width: 0.45, height: 0.04), kind: .drain),  // icicle ceiling, right half
                  Zone(rect: CGRect(x: 0.78, y: 0.43, width: 0.12, height: 0.05), kind: .goal),
              ],
              par: 24,
              steamAllowed: true,
              blowAllowed: false,
              mood: .warm),
        // One way only (the capstone): a mid icicle band forbids the direct
        // steam crossing, so the route is CARVE a low slide under it, ride
        // right as water, then vaporize up the narrow corridor between the
        // bands (x .70–.75) and condense onto the goal shelf.
        Level(name: "Cloudburst",
              hint: "The capstone: CARVE a low slide under the icicles, ride it RIGHT, then STEAM up the narrow gap and condense onto the goal shelf.",
              spawn: CGPoint(x: 0.10, y: 0.62),
              walls: [
                  CGRect(x: 0.02, y: 0.55, width: 0.20, height: 0.03),   // start shelf
                  CGRect(x: 0.75, y: 0.70, width: 0.23, height: 0.03),   // goal shelf
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.25, y: 0.60, width: 0.45, height: 0.04), kind: .drain),  // icicles: no direct crossing
                  Zone(rect: CGRect(x: 0.30, y: 0.82, width: 0.45, height: 0.04), kind: .drain),  // icicles: no ceiling route
                  Zone(rect: CGRect(x: 0.80, y: 0.73, width: 0.14, height: 0.05), kind: .goal),
              ],
              inkBudget: 220,
              par: 34,
              steamAllowed: true,
              blowAllowed: false,
              mood: .storm),
        // MARK: expert tier (19–22) — each one combo the game hasn't
        // demanded yet, hardened to a single route. Design lesson from the
        // 11–18 pass: vapor rises too fast for height alone to force
        // anything — steam levels force via horizontal serpentines against
        // the fuse; the rest force by removing blow/steam entirely.
        Level(name: "Piston & Pane",
              hint: "Two lifts, half a beat apart. FREEZE onto the first, cross at the moment they pass, ride DOWN, and roll out under the ice curtain.",
              spawn: CGPoint(x: 0.10, y: 0.92),
              walls: [],
              zones: [
                  Zone(rect: CGRect(x: 0.80, y: 0.015, width: 0.16, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.72, y: 0.28, width: 0.06, height: 0.30), kind: .drain),  // the ice curtain
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.26, y: 0.35),
                        size: CGSize(width: 0.16, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.20), period: 4.0),
                  Mover(center: CGPoint(x: 0.60, y: 0.35),
                        size: CGSize(width: 0.16, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.20), period: 4.0, phase: 0.5),
              ],
              par: 28,
              blowAllowed: false,
              mood: .storm),
        Level(name: "Inkline",
              hint: "One line decides it: fall to the perch, DRAW a long slide under the icicle shelf, and ride it off the edge into the basin.",
              spawn: CGPoint(x: 0.08, y: 0.78),
              walls: [
                  CGRect(x: 0.02, y: 0.72, width: 0.18, height: 0.03),   // start shelf
                  CGRect(x: 0.24, y: 0.47, width: 0.16, height: 0.03),   // the perch
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.16, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  Zone(rect: CGRect(x: 0.52, y: 0.20, width: 0.48, height: 0.04), kind: .drain),  // icicle shelf: thread under
              ],
              inkBudget: 340,
              par: 30,
              blowAllowed: false,
              mood: .abyss),
        Level(name: "Threadneedle",
              hint: "One breathless burst: STEAM up the LEFT gap, then lean HARD right the whole climb — thread the top gap before you condense.",
              spawn: CGPoint(x: 0.10, y: 0.15),
              walls: [
                  CGRect(x: 0.04, y: 0.08, width: 0.14, height: 0.03),   // spawn shelf
                  CGRect(x: 0.70, y: 0.80, width: 0.30, height: 0.03),   // goal ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.78, y: 0.83, width: 0.14, height: 0.045), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
                  // Low first band: the drift phase needs the full climb.
                  // Rising vapor is already at the speed cap, so sideways
                  // speed only builds as the velocity vector slowly rotates
                  // (~150pt/s average, not the naive 218) — the thread is
                  // impossible without this much runway.
                  Zone(rect: CGRect(x: 0.22, y: 0.22, width: 0.78, height: 0.04), kind: .drain),  // band: gap left
                  Zone(rect: CGRect(x: 0.00, y: 0.72, width: 0.62, height: 0.04), kind: .drain),  // band: gap right
                  Zone(rect: CGRect(x: 0.92, y: 0.50, width: 0.08, height: 0.04), kind: .drain),  // wall-hug nub
              ],
              par: 16,
              steamAllowed: true,
              blowAllowed: false,
              mood: .mist),
        // Playtest lesson (David): a FALLING spawn + ink = carve a catch
        // slide from your own fall line to anywhere below it — the lift was
        // optional. Ground starts are the counter: carving can only
        // redirect falls, so a standing droplet can't carve altitude, and
        // the lift becomes the only way up.
        Level(name: "Cold Service",
              hint: "The lift only goes up — the way back is yours to build: CARVE a bridge from the apex and skate it home before it evaporates.",
              spawn: CGPoint(x: 0.88, y: 0.095),  // ground start on the pad
              walls: [
                  CGRect(x: 0.02, y: 0.40, width: 0.21, height: 0.03),   // goal ledge
                  CGRect(x: 0.80, y: 0.05, width: 0.16, height: 0.03),   // start pad
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.06, y: 0.435, width: 0.12, height: 0.045), kind: .goal),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .grate),
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.70, y: 0.30),
                        size: CGSize(width: 0.16, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.245), period: 4.4),
              ],
              inkBudget: 220,
              par: 30,
              blowAllowed: false,
              mood: .frost,
              // README-flagged long skate: melting mid-bridge over the
              // all-grate floor is death, and the carve happens first —
              // give the skate home an honest window.
              iceDuration: 12),
    ]
}

// MARK: - Scene

final class GameScene: SKScene, SKPhysicsContactDelegate {
    weak var model: GameModel?

    private enum Cat {
        static let droplet: UInt32 = 1 << 0
        static let wall:    UInt32 = 1 << 1
        static let drain:   UInt32 = 1 << 2
        static let grate:   UInt32 = 1 << 3
        static let goal:    UInt32 = 1 << 4
    }

    // Feel knobs
    private let gravityStrength: CGFloat = 28   // m/s² at full tilt
    private let liftStrength: CGFloat = 45      // extra climb headroom beyond hover
    private let maxRiseSpeed: CGFloat = 620     // stop pushing once rising this fast
    private let maxSpeed: CGFloat = 1400        // ice top speed / anti-tunneling cap
    private let waterMaxSpeed: CGFloat = 380    // water splatters beyond this — ice doesn't
    private let airSteer: CGFloat = 0.15        // tilt authority while airborne (ballistic air)
    // Steam vs blow, separated by feel (device playtest: they blurred
    // together): blow is the hover jet — slow, precise, continuous,
    // vulnerable; steam is the committed leap — fast, hazard-immune, on a
    // short fuse, and with a recharge so tap-spam can't fake a hover.
    private let steamMaxSpeed: CGFloat = 380    // a whoosh, not a float
    private let steamBuoyancy: CGFloat = 0.50   // upward pull as a fraction of gravityStrength
    private let steamSteer: CGFloat = 0.35      // tilt authority as vapor (the crossing verb)
    private let steamDuration: TimeInterval = 2.8   // then it condenses back to water
    private let steamCooldown: TimeInterval = 0.7   // recharge after condensing

    private var droplet: SKShapeNode!
    private var dropletVisual: DropletVisual?
    private var cam: SKCameraNode?
    private var spawnMarker: SKNode?
    private var currentLift: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    private var frameDT: CGFloat = 1 / 60
    private(set) var levelIndex = 0
    private var holdingLift = false
    private var transitioning = false
    private var appliedPhase: Phase = .water
    private var steamElapsed: TimeInterval = 0
    private var steamFrac: CGFloat = 1          // remaining vapor time, 1→0
    private var steamCooldownUntil: TimeInterval = 0
    private var liftRemaining: CGFloat = 0
    private var levelLiftBudget: CGFloat = 8
    private var iceElapsed: TimeInterval = 0
    private var iceFrac: CGFloat = 1            // remaining freeze time, 1→0
    private var levelIceDuration: TimeInterval = 8
    private var phaseWarned = false             // one warning cue per phase
    /// Zones in scene coordinates, checked geometrically every frame.
    /// Sensor-style physics contacts (collision-less bodies) proved
    /// unreliable for a ball rolling along the scene edge, so the checks
    /// that decide life and death are plain rect math instead.
    /// `elevated` marks drains that render as icicles — the one hazard that
    /// still kills vapor (cold condenses it dead).
    private var zoneRects: [(kind: ZoneKind, rect: CGRect, elevated: Bool)] = []
    private var levelStartTime: TimeInterval = 0

    private enum RunState { case countdown, playing }
    private var runState: RunState = .countdown

    // Juice: sounds, particles, backdrop
    private var sounds: [String: SKAction] = [:]
    private var lastPlink: TimeInterval = 0
    private var trail: SKEmitterNode?
    private lazy var dotTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let img = renderer.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(grad,
                startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
        }
        return SKTexture(image: img)
    }()
    // (The abstract gradient backdrop retired 22 Aug — every level is a
    // diorama now, themed by mood via DioramaTheme. Mood gradients live on
    // as the droplet-refraction ambience.)

    private func loadSounds() {
        for name in ["plink", "ice_tap", "freeze", "melt", "goal", "die", "tick", "go", "carve", "steam", "condense", "crumble", "warn"]
        where Bundle.main.url(forResource: name, withExtension: "wav") != nil {
            sounds[name] = SKAction.playSoundFileNamed("\(name).wav", waitForCompletion: false)
        }
        NSLog("DripDrop: loaded \(sounds.count)/13 sounds")
    }

    private func sfx(_ name: String) {
        if let action = sounds[name] { run(action) }
    }

    /// Particle burst — death splashes, goal celebrations, impact spray.
    private func burst(at p: CGPoint, color: UIColor, up: Bool, count: Int = 20) {
        let e = SKEmitterNode()
        e.particleTexture = dotTexture
        e.numParticlesToEmit = count
        e.particleBirthRate = 600
        e.particleLifetime = 0.55
        e.particleSpeed = 230
        e.particleSpeedRange = 130
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = up ? 1.2 : 2 * .pi
        e.yAcceleration = -900
        e.particleAlpha = 0.85
        e.particleAlphaSpeed = -1.6
        e.particleScale = 0.6
        e.particleScaleSpeed = -0.8
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.position = p
        addChild(e)
        e.run(.sequence([.wait(forDuration: 1.0), .removeFromParent()]))
    }

    // Finger-carved channels: a moving finger draws a temporary wall the
    // droplet can ride; a stationary hold remains the updraft. Channels
    // are rationed (ink per stroke, two at once) and evaporate.
    private var carveStart: CGPoint?
    private var carvePoints: [CGPoint] = []
    private var isCarving = false
    private var inkUsed: CGFloat = 0
    private var carvePreview: SKShapeNode?
    private var channels: [SKNode] = []
    private let maxChannels = 2
    private var inkBudget: CGFloat = 0          // per level, from Level.inkBudget
    private let channelLifetime: TimeInterval = 6
    private let carveHaptic = UIImpactFeedbackGenerator(style: .light)
    private let bump = UIImpactFeedbackGenerator(style: .medium)
    private let freezeHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let rolling = RollingHaptics()

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)
        physicsWorld.contactDelegate = self
        bump.prepare()
        loadSounds()
        rolling.start()
        // Reload whatever level was selected (menu may have chosen one
        // before the view was presented); fresh countdown either way.
        loadLevel(levelIndex)
    }

    override func willMove(from view: SKView) {
        // Back to the menu: kill the continuous haptic so it can't stick on.
        rolling.stop()
    }

    // MARK: Level construction

    func loadLevel(_ i: Int) {
        removeAllChildren()
        levelIndex = i
        let level = Levels.all[i]
        model?.levelNumber = i + 1
        model?.levelName = level.name
        model?.hint = level.hint
        inkBudget = level.inkBudget
        model?.carveAllowed = level.inkBudget > 0
        model?.inkFrac = 1
        model?.steamAllowed = level.steamAllowed
        model?.blowAllowed = level.blowAllowed
        levelLiftBudget = CGFloat(level.liftBudget)
        liftRemaining = levelLiftBudget
        model?.liftFrac = 1
        levelIceDuration = level.iceDuration
        iceElapsed = 0
        iceFrac = 1
        model?.phase = .water           // every level starts as water
        model?.steamReady = true
        steamElapsed = 0
        steamFrac = 1
        steamCooldownUntil = 0
        levelStartTime = CACurrentMediaTime()
        model?.availableScore = 1000

        let theme = DioramaTheme.theme(for: level.mood)
        Decor.currentTheme = theme
        addChild(Decor.dioramaBackdrop(theme: theme, size: size))
        addChild(Decor.vignette(size: size))
        for mote in Decor.motes(size: size, color: level.mood.moteColor) { addChild(mote) }
        if let prop = Decor.ambientProp(theme: theme, sceneSize: size) {
            addChild(prop)
        }
        // Every droplet comes from somewhere: faucet, cracked pipe, hose,
        // scupper — dripping above the spawn.
        addChild(Decor.sourceProp(theme: theme, spawn: point(level.spawn),
                                  sceneSize: size))

        // removeAllChildren() took the camera with it; small shakes only.
        let camera = SKCameraNode()
        camera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(camera)
        self.camera = camera
        cam = camera

        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.categoryBitMask = Cat.wall
        physicsBody?.friction = 0.15

        channels = []
        carveStart = nil
        carvePreview = nil
        moverNodes = []
        for w in level.walls { addWall(rect(w)) }
        for r in level.ramps { addRamp(r) }
        for m in level.movers { addMover(m) }
        zoneRects = level.zones.map {
            (kind: $0.kind, rect: rect($0.rect),
             elevated: $0.kind == .drain && $0.rect.minY > 0.06)
        }
        for z in level.zones { addZone(z) }
        spawnDroplet(at: point(level.spawn))
        applyPhase()
        transitioning = false
        startCountdown()
    }

    /// Ready — Steady — Go! The droplet holds at spawn and the score clock
    /// waits; play (and the drain) begins on GO.
    private func startCountdown() {
        runState = .countdown
        model?.phaseLocked = true
        droplet.physicsBody?.isDynamic = false
        removeAction(forKey: "countdown")
        model?.countdown = "READY"
        let tick = UIImpactFeedbackGenerator(style: .light)
        tick.impactOccurred()
        sfx("tick")
        run(.sequence([
            .wait(forDuration: 1.6),        // reading time for the hint card
            .run { [weak self] in
                self?.model?.countdown = "STEADY"
                tick.impactOccurred()
                self?.sfx("tick")
            },
            .wait(forDuration: 0.9),
            .run { [weak self] in
                guard let self else { return }
                self.model?.countdown = "GO!"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.sfx("go")
                self.droplet.physicsBody?.isDynamic = true
                self.levelStartTime = CACurrentMediaTime()
                self.runState = .playing
                self.model?.phaseLocked = false
                self.spawnMarker?.run(.sequence([.fadeOut(withDuration: 0.4),
                                                 .removeFromParent()]))
                self.spawnMarker = nil
            },
            .wait(forDuration: 0.6),
            .run { [weak self] in self?.model?.countdown = nil },
        ]), withKey: "countdown")
    }

    func reloadCurrent() { loadLevel(levelIndex) }

    private func addWall(_ r: CGRect) {
        let node = Decor.slab(rect: r)
        let body = SKPhysicsBody(rectangleOf: r.size)
        body.isDynamic = false
        body.categoryBitMask = Cat.wall
        body.friction = 0.2
        node.physicsBody = body
        addChild(node)
    }

    private(set) var moverNodes: [SKNode] = []

    private func addMover(_ m: Mover) {
        let sz = CGSize(width: m.size.width * size.width,
                        height: m.size.height * size.height)
        let node = Decor.moverSlab(size: sz)
        let travel = CGVector(dx: m.travel.dx * size.width,
                              dy: m.travel.dy * size.height)
        let mid = point(m.center)
        node.position = CGPoint(x: mid.x - travel.dx, y: mid.y - travel.dy)
        let body = SKPhysicsBody(rectangleOf: sz)
        body.isDynamic = false
        body.categoryBitMask = Cat.wall
        body.friction = 0.3
        node.physicsBody = body
        let half = m.period / 2
        let go = SKAction.moveBy(x: travel.dx * 2, y: travel.dy * 2, duration: half)
        go.timingMode = .easeInEaseOut
        let back = SKAction.moveBy(x: -travel.dx * 2, y: -travel.dy * 2, duration: half)
        back.timingMode = .easeInEaseOut
        let cycle = SKAction.repeatForever(.sequence([go, back]))
        node.run(m.phase > 0
            ? .sequence([.wait(forDuration: m.phase * m.period), cycle])
            : cycle)
        addChild(node)
        moverNodes.append(node)
    }

    private func addRamp(_ ramp: Ramp) {
        let size = CGSize(width: ramp.size.width * self.size.width,
                          height: ramp.size.height * self.size.height)
        let node = Decor.slab(rect: CGRect(origin: .zero, size: size)
            .offsetBy(dx: -size.width / 2, dy: -size.height / 2))
        node.position = point(ramp.center)
        node.zRotation = ramp.rotation
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.categoryBitMask = Cat.wall
        body.friction = 0.2
        node.physicsBody = body
        addChild(node)
    }

    /// Zones are purely visual — their gameplay effect comes from the
    /// per-frame geometric checks in update(), not physics bodies.
    /// Visual language: goal = glowing pool, floor drain = ember pit,
    /// elevated drain = hanging icicles, grate = cyan slats.
    private func addZone(_ z: Zone) {
        let r = rect(z.rect)
        let node: SKNode
        switch z.kind {
        case .goal:
            node = Decor.goalVessel(rect: r, theme: Decor.currentTheme)
        case .drain:
            node = z.rect.minY > 0.06 ? Decor.icicles(rect: r) : Decor.drainPit(rect: r)
        case .grate:
            node = Decor.grate(rect: r)
        }
        addChild(node)
    }

    private func circleIntersects(_ rect: CGRect, center: CGPoint, radius: CGFloat) -> Bool {
        let nx = min(max(center.x, rect.minX), rect.maxX)
        let ny = min(max(center.y, rect.minY), rect.maxY)
        return hypot(center.x - nx, center.y - ny) < radius
    }

    private func spawnDroplet(at p: CGPoint) {
        // The physics ball is invisible; DropletVisual draws the liquid.
        droplet = SKShapeNode(circleOfRadius: 14)
        droplet.position = p
        droplet.fillColor = .clear
        droplet.strokeColor = .clear
        droplet.lineWidth = 0
        let body = SKPhysicsBody(circleOfRadius: 14)
        body.categoryBitMask = Cat.droplet
        body.collisionBitMask = Cat.wall
        body.contactTestBitMask = Cat.wall   // walls only — zones are geometric
        body.allowsRotation = true
        body.angularDamping = 0.6
        body.usesPreciseCollisionDetection = true
        droplet.physicsBody = body

        // Speed-streak spray, fed by speed in update().
        let t = SKEmitterNode()
        t.particleTexture = dotTexture
        t.particleBirthRate = 0
        t.particleLifetime = 0.35
        t.particleAlpha = 0.5
        t.particleAlphaSpeed = -1.4
        t.particleScale = 0.5
        t.particleScaleSpeed = -1.0
        t.particleColorBlendFactor = 1
        t.targetNode = self
        droplet.addChild(t)
        trail = t

        addChild(droplet)

        let visual = DropletVisual(sceneHeight: size.height,
                                   mood: Levels.all[levelIndex].mood)
        visual.position = p
        addChild(visual)
        dropletVisual = visual

        let marker = Decor.spawnRing(at: p)
        addChild(marker)
        spawnMarker = marker
    }

    /// Same ball, per-phase physics material. The look is the shader's job —
    /// DropletVisual morphs between phases on its own.
    private func applyPhase() {
        guard let model, let body = droplet?.physicsBody else { return }
        appliedPhase = model.phase
        switch appliedPhase {
        case .water:
            // Damping 0.8 is water's identity: it clings in flight, which is
            // exactly why it can't clear the level-4 pit and ice can.
            trail?.particleColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)
            body.friction = 0.25
            body.linearDamping = 0.8
            body.restitution = 0.3
        case .ice:
            trail?.particleColor = .white
            body.friction = 0.02
            body.linearDamping = 0.05
            body.restitution = 0.08
        case .steam:
            // Vapor: heavy drag so buoyancy sets the pace, no bounce.
            trail?.particleColor = UIColor(white: 0.95, alpha: 0.6)
            body.friction = 0.05
            body.linearDamping = 1.4
            body.restitution = 0.05
        }
    }

    // MARK: Per-frame

    override func update(_ currentTime: TimeInterval) {
        guard let model, let body = droplet?.physicsBody else { return }
        frameDT = CGFloat(min(max(currentTime - lastUpdateTime, 0), 0.05))
        lastUpdateTime = currentTime

        // Tilt IS gravity — but "up" belongs to breath alone (dy floored so
        // flipping the phone can't invert the world), and full tilt authority
        // exists only ON surfaces. Airborne, the droplet is ballistic: it
        // falls at standard weight with faint air-steer. Momentum earned on
        // a surface is what carries a jump — without this rule, tilt acts as
        // a mid-air thruster and any gap can be flown by either phase.
        let grounded = !(body.allContactedBodies().isEmpty)
        if model.phase == .steam {
            // Vapor makes its own "up": buoyant rise, drifty tilt authority,
            // grounded or not. (Blow does nothing to it — see the lift gate.)
            physicsWorld.gravity = CGVector(dx: model.tilt.dx * gravityStrength * steamSteer,
                                            dy: steamBuoyancy * gravityStrength)
        } else if grounded {
            let dy = min(model.tilt.dy, -0.25)
            physicsWorld.gravity = CGVector(dx: model.tilt.dx * gravityStrength,
                                            dy: dy * gravityStrength)
        } else {
            physicsWorld.gravity = CGVector(dx: model.tilt.dx * gravityStrength * airSteer,
                                            dy: -0.55 * gravityStrength)
        }

        if model.phase != appliedPhase {
            let wasSteam = appliedPhase == .steam
            applyPhase()
            freezeHaptic.impactOccurred()
            switch appliedPhase {
            case .ice:
                sfx("freeze")
                iceElapsed = 0
                iceFrac = 1
            case .steam:
                sfx("steam")
                // The body flashes apart into vapor.
                burst(at: droplet.position,
                      color: UIColor(white: 0.95, alpha: 0.9), up: true, count: 12)
            case .water:
                // Ice melts with a bloop; vapor condenses with its own
                // double-bloop and patter.
                sfx(wasSteam ? "condense" : "melt")
                if wasSteam {
                    // Condensation: the cloud collapses into a shower.
                    burst(at: droplet.position,
                          color: UIColor(red: 0.45, green: 0.72, blue: 1, alpha: 1),
                          up: false, count: 10)
                }
            }
            if appliedPhase == .steam { steamElapsed = 0; steamFrac = 1 }
            phaseWarned = false
            // Leaving vapor starts the recharge — steam is a committed
            // leap, and the cooldown is what stops tap-spam becoming a
            // second hover verb (that's blowing's job).
            if wasSteam { steamCooldownUntil = CACurrentMediaTime() + steamCooldown }
        }
        let steamReady = CACurrentMediaTime() >= steamCooldownUntil
        if model.steamReady != steamReady { model.steamReady = steamReady }

        // During the countdown the world holds its breath: no gravity
        // steering, no lift, no zone checks, no score drain.
        guard runState == .playing else {
            currentLift = 0
            rolling.update(speed: 0, grounded: false, isIce: appliedPhase == .ice)
            return
        }

        // Breath (or touch-and-hold fallback) is an updraft. Any recognized
        // breath first cancels whatever gravity is currently pulling, then
        // adds lift on top — so blowing ALWAYS visibly wins, and blowing
        // harder wins faster.
        //
        // UNIT TRAP: physicsWorld.gravity is in m/s² (SpriteKit scales it by
        // 150 points-per-meter internally) but applyForce works in point
        // units — forces must be multiplied by 150 or they're 150x too weak
        // to fight gravity. This is why earlier versions felt dead.
        // The phase clocks: vapor condenses and ice melts back to water on
        // their own. Both tick only while playing, so pre-freezing or
        // pre-vaporizing in the countdown is free strategy.
        if model.phase == .steam {
            steamElapsed += TimeInterval(frameDT)
            steamFrac = max(0, 1 - CGFloat(steamElapsed / steamDuration))
            if steamElapsed >= steamDuration { model.phase = .water }
        }
        if model.phase == .ice {
            iceElapsed += TimeInterval(frameDT)
            iceFrac = max(0, 1 - CGFloat(iceElapsed / levelIceDuration))
            if iceElapsed >= levelIceDuration { model.phase = .water }
        }
        // One audible warning as a phase clock enters its flash window.
        if !phaseWarned,
           (model.phase == .ice && iceFrac < 0.19)
            || (model.phase == .steam && steamFrac < 0.32) {
            phaseWarned = true
            sfx("warn")
            carveHaptic.impactOccurred()
        }

        let pointsPerMeter: CGFloat = 150
        // Lift: touch-and-hold and breath are both first-class (testers
        // preferred taps), gated by phase, level, and the AIR SUPPLY —
        // lifting drains the budget; empty means no more lift until the
        // level reloads. This is what keeps hover from being a skeleton
        // key now that it's precise.
        let hold: CGFloat = holdingLift ? 0.9 : 0
        var lift = (model.phase == .steam || !model.blowAllowed || liftRemaining <= 0) ? 0
                 : max(hold, CGFloat(model.blowLevel))
        if lift > 0.10 {
            liftRemaining = max(0, liftRemaining - frameDT)
            let frac = liftRemaining / max(levelLiftBudget, 0.01)
            if abs((model.liftFrac) - frac) > 0.005 { model.liftFrac = frac }
            if liftRemaining <= 0 { lift = 0 }
        }
        currentLift = lift > 0.10 ? lift : 0
        if lift > 0.10 {
            // Proportional all the way down — no free weightlessness at the
            // threshold. Hover sits around 40% on the meter: below that a
            // puff only softens the fall; above it, the droplet climbs.
            let pullDown = max(0, -physicsWorld.gravity.dy)
            let accel = lift * (pullDown + liftStrength) * pointsPerMeter
            if body.velocity.dy < maxRiseSpeed {
                body.applyForce(CGVector(dx: 0, dy: body.mass * accel))
            }
        }

        // Per-phase speed cap: water can't hold together at speed; ice can;
        // vapor floats. This is what makes momentum jumps an ice-only ability.
        let v = body.velocity
        let speed = hypot(v.dx, v.dy)
        let cap: CGFloat
        switch model.phase {
        case .ice:   cap = maxSpeed
        case .steam: cap = steamMaxSpeed
        case .water: cap = waterMaxSpeed
        }
        if speed > cap {
            let k = cap / speed
            body.velocity = CGVector(dx: v.dx * k, dy: v.dy * k)
        }

        // Squash, stretch, wobble and drip all live in the metaball shader
        // now — see DropletVisual.sync, driven from didFinishUpdate().

        // Trail intensity follows speed — except vapor, which always wisps.
        trail?.particleBirthRate = model.phase == .steam ? 14
            : (speed > 250 ? min(40, speed / 15) : 0)

        // Rolling texture in the palm: contact, speed, and phase.
        // (Vapor rarely touches anything; the airborne gate silences it.)
        rolling.update(speed: speed, grounded: grounded, isIce: appliedPhase == .ice)

        channels.removeAll { $0.parent == nil }   // expired channels

        // Rolling score: the pot drains linearly from the moment the level
        // starts, hitting the 50-point floor at 2x par. Faster = richer.
        let elapsed = CACurrentMediaTime() - levelStartTime
        let par = Levels.all[levelIndex].par
        var avail = Int(1000 - 950 * elapsed / (2 * par))
        avail = max(50, (avail / 10) * 10)
        if model.availableScore != avail { model.availableScore = avail }

        // Life-and-death zone checks: plain geometry, cannot miss.
        guard !transitioning else { return }
        let c = droplet.position
        for z in zoneRects {
            switch z.kind {
            case .goal:
                // The basin only takes liquid (or ice) — vapor drifts past.
                if model.phase != .steam,
                   circleIntersects(z.rect, center: c, radius: 14) { advance() }
            case .drain:
                // Floor drains can't swallow vapor; icicles (elevated)
                // condense it dead like everything else.
                if !(model.phase == .steam && !z.elevated),
                   circleIntersects(z.rect, center: c, radius: 10) { die() }
            case .grate:
                // Grates swallow only liquid water.
                if model.phase == .water,
                   circleIntersects(z.rect, center: c, radius: 10) { die() }
            }
        }

        // Failsafe: a moving platform can squeeze the ball through the
        // zero-thickness edge loop (seen on Rising Water, where the elevator
        // sinks flush with the floor). Outside the frame no zone can ever
        // catch it, so escaping the scene counts as a death.
        if !frame.insetBy(dx: -30, dy: -30).contains(c) { die() }
    }

    /// Runs after physics each frame: sync the liquid visual to the ball.
    override func didFinishUpdate() {
        guard let model, let droplet, let body = droplet.physicsBody,
              let visual = dropletVisual else { return }
        visual.sync(center: droplet.position,
                    velocity: body.velocity,
                    grounded: !body.allContactedBodies().isEmpty,
                    phase: model.phase,
                    steamRemaining: steamFrac,
                    iceRemaining: iceFrac,
                    lift: currentLift,
                    now: lastUpdateTime,
                    dt: frameDT)
    }

    /// Tiny deterministic camera shake; m scales the amplitude.
    private func shake(_ m: CGFloat) {
        guard let cam else { return }
        let home = CGPoint(x: size.width / 2, y: size.height / 2)
        let offsets: [CGPoint] = [CGPoint(x: 5, y: 2), CGPoint(x: -4, y: 3),
                                  CGPoint(x: 3, y: -3), CGPoint(x: -2, y: 1),
                                  CGPoint(x: 1, y: -1), .zero]
        cam.removeAction(forKey: "shake")
        cam.run(.sequence(offsets.map { o in
            .move(to: CGPoint(x: home.x + o.x * m, y: home.y + o.y * m), duration: 0.03)
        }), withKey: "shake")
    }

    // MARK: Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        // Only wall contacts reach here now; haptics, sounds, jelly wobble.
        let v = droplet?.physicsBody?.velocity ?? .zero
        let speed = hypot(v.dx, v.dy)
        guard speed > 220 else { return }
        bump.impactOccurred(intensity: min(1, speed / 900))
        dropletVisual?.impact(min(1, speed / 1000))
        if speed > 750 { shake(min(1, speed / 1400)) }
        let now = CACurrentMediaTime()
        if now - lastPlink > 0.09 {
            lastPlink = now
            sfx(appliedPhase == .ice ? "ice_tap" : "plink")
            // Water sheds a few droplets on a hard hit; ice stays whole.
            if appliedPhase == .water, speed > 500 {
                burst(at: droplet.position,
                      color: UIColor(red: 0.4, green: 0.72, blue: 1, alpha: 1),
                      up: false, count: 7)
            }
        }
    }

    private func advance() {
        guard !transitioning else { return }
        transitioning = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sfx("goal")
        burst(at: droplet.position, color: .systemGreen, up: true)

        // Bank the pot and celebrate it at the goal.
        let banked = model?.availableScore ?? 0
        model?.recordBank(levelIndex: levelIndex, banked: banked)
        let label = SKLabelNode(text: "+\(banked)")
        label.fontName = "Menlo-Bold"
        label.fontSize = 22
        label.fontColor = .systemCyan
        label.position = CGPoint(x: min(max(droplet.position.x, 50), size.width - 50),
                                 y: min(droplet.position.y + 30, size.height - 60))
        addChild(label)
        label.run(.group([.moveBy(x: 0, y: 46, duration: 0.8),
                          .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]))

        let next = levelIndex + 1
        dropletVisual?.run(.group([.scale(to: 0.1, duration: 0.25),
                                   .fadeOut(withDuration: 0.25)]))
        droplet.run(.group([.scale(to: 0.1, duration: 0.25),
                            .fadeOut(withDuration: 0.25)])) { [weak self] in
            guard let self, let model = self.model else { return }
            if next >= Levels.all.count {
                model.runFinished()
                self.loadLevel(0)
            } else {
                self.loadLevel(next)
            }
        }
    }

    private func die() {
        guard !transitioning else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        sfx("die")
        let splash: UIColor
        switch appliedPhase {
        case .ice:   splash = .white
        case .steam: splash = UIColor(white: 0.92, alpha: 0.9)
        case .water: splash = UIColor(red: 0.35, green: 0.68, blue: 1, alpha: 1)
        }
        burst(at: droplet.position, color: splash, up: false, count: 30)
        shake(0.7)
        droplet.physicsBody?.velocity = .zero
        droplet.physicsBody?.angularVelocity = 0
        droplet.position = point(Levels.all[levelIndex].spawn)
        // Ice survives a death (v1.0 behavior — Switchback relies on it),
        // but vapor condenses: respawning as rising steam would be chaos.
        if model?.phase == .steam { model?.phase = .water }
        dropletVisual?.reset()   // no trail streak across the teleport
    }

    // MARK: Touch — stationary hold lifts (mic fallback), a moving finger carves

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard carveStart == nil, let t = touches.first else { return }
        let p = t.location(in: self)
        carveStart = p
        carvePoints = [p]
        isCarving = false
        inkUsed = 0
        holdingLift = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start = carveStart, let t = touches.first else { return }
        let p = t.location(in: self)
        if !isCarving, hypot(p.x - start.x, p.y - start.y) > 18 {
            // A moving finger is not a hold: lift ends even on no-ink levels,
            // otherwise swiping is a free (unintended) updraft.
            holdingLift = false
            if inkBudget > 0 {
                isCarving = true
                carvePreview = SKShapeNode()
                carvePreview?.strokeColor = UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.5)
                carvePreview?.lineWidth = 5
                carvePreview?.lineCap = .round
                addChild(carvePreview!)
            }
        }
        guard isCarving, let last = carvePoints.last else { return }
        let seg = hypot(p.x - last.x, p.y - last.y)
        if seg >= 12, inkUsed + seg <= inkBudget {
            carvePoints.append(p)
            inkUsed += seg
            model?.inkFrac = max(0, 1 - inkUsed / max(inkBudget, 1))
            let path = CGMutablePath()
            path.addLines(between: carvePoints)
            carvePreview?.path = path
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouch() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouch() }

    private func endTouch() {
        holdingLift = false
        if isCarving, carvePoints.count >= 2 { commitChannel(points: carvePoints) }
        isCarving = false
        carveStart = nil
        carvePreview?.removeFromParent()
        carvePreview = nil
        model?.inkFrac = 1      // ink is per-stroke: fresh pen on release
    }

    /// Flowing shimmer along the committed channel — a current running
    /// through glass. v_path_distance is SpriteKit's stroke-shader gift.
    private static let channelShader = SKShader(source: """
        void main() {
            float flow = 0.72 + 0.28 * sin(v_path_distance * 0.13 - u_time * 9.0);
            vec3 col = vec3(0.55, 0.88, 1.0) * flow + vec3(0.25) * pow(flow, 6.0);
            gl_FragColor = vec4(col * 0.9, 0.9);
        }
        """)

    private func commitChannel(points: [CGPoint]) {
        let path = CGMutablePath()
        path.addLines(between: points)
        let node = SKShapeNode(path: path)
        node.strokeColor = UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.9)
        node.lineWidth = 6
        node.lineCap = .round
        node.glowWidth = 2
        node.strokeShader = Self.channelShader
        // Bright core line: the channel reads as a glass canal, not a mark.
        let core = SKShapeNode(path: path)
        core.strokeColor = UIColor.white.withAlphaComponent(0.85)
        core.lineWidth = 1.6
        core.lineCap = .round
        node.addChild(core)
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.isDynamic = false
        body.categoryBitMask = Cat.wall
        body.friction = 0.2
        node.physicsBody = body
        addChild(node)
        channels.append(node)
        if channels.count > maxChannels {
            channels.removeFirst().run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        // Evaporation: instead of blinking, the channel crumbles into
        // droplets along its length as it fades out.
        node.run(.sequence([
            .wait(forDuration: channelLifetime - 0.5),
            .run { [weak self, weak node] in
                guard let self, let node else { return }
                self.sfx("crumble")
                for (i, p) in points.enumerated() where i % 3 == 0 {
                    self.burst(at: node.convert(p, to: self),
                               color: UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1),
                               up: false, count: 3)
                }
            },
            .fadeOut(withDuration: 0.45),
            .removeFromParent(),
        ]))
        carveHaptic.impactOccurred()
        sfx("carve")
    }

    // MARK: Unit-coordinate helpers

    private func point(_ u: CGPoint) -> CGPoint {
        CGPoint(x: u.x * size.width, y: u.y * size.height)
    }
    private func rect(_ u: CGRect) -> CGRect {
        CGRect(x: u.minX * size.width, y: u.minY * size.height,
               width: u.width * size.width, height: u.height * size.height)
    }
}
