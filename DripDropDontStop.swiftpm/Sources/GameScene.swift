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
}

enum Levels {
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
              hint: "BLOW on the microphone to lift the droplet over the wall (or touch & hold the screen).",
              spawn: CGPoint(x: 0.15, y: 0.25),
              walls: [
                  CGRect(x: 0.47, y: 0.00, width: 0.06, height: 0.40),
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.76, y: 0.015, width: 0.20, height: 0.05), kind: .goal),
              ],
              par: 12),
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
              par: 14),
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
              par: 16),
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
              par: 20),
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
              par: 32),
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
              par: 20),
        Level(name: "Switchback",
              hint: "FREEZE early — grates on every storey. Work right, drop, work LEFT over the pit, then skate home.",
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
              par: 24),
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
              par: 18),
        Level(name: "Rising Water",
              hint: "The lift sinks flush with the floor — but the floor around it swallows water. Commit when it's LOW, ride it up, roll off at the top.",
              spawn: CGPoint(x: 0.08, y: 0.88),
              walls: [
                  CGRect(x: 0.78, y: 0.62, width: 0.22, height: 0.03),   // top ledge
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.85, y: 0.65, width: 0.12, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.69, y: 0.00, width: 0.31, height: 0.035), kind: .grate),
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.58, y: 0.32),
                        size: CGSize(width: 0.22, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.34), period: 5),
              ],
              par: 24),
        Level(name: "Cold Storage",
              hint: "FREEZE before you land — the shelves are slatted. Ride the lift DOWN, and mind the gap on the way off.",
              spawn: CGPoint(x: 0.08, y: 0.86),
              walls: [
                  CGRect(x: 0.00, y: 0.80, width: 0.35, height: 0.03),   // top shelf
                  CGRect(x: 0.22, y: 0.55, width: 0.40, height: 0.03),   // mid shelf
                  CGRect(x: 0.30, y: 0.18, width: 0.35, height: 0.03),   // lower shelf
              ],
              zones: [
                  Zone(rect: CGRect(x: 0.31, y: 0.215, width: 0.11, height: 0.05), kind: .goal),
                  Zone(rect: CGRect(x: 0.26, y: 0.58, width: 0.22, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.30, y: 0.21, width: 0.18, height: 0.02), kind: .grate),
                  Zone(rect: CGRect(x: 0.00, y: 0.00, width: 1.00, height: 0.035), kind: .drain),
              ],
              movers: [
                  Mover(center: CGPoint(x: 0.82, y: 0.415),
                        size: CGSize(width: 0.20, height: 0.03),
                        travel: CGVector(dx: 0, dy: 0.135), period: 4.5),
              ],
              par: 32),
        Level(name: "The Long Pour",
              hint: "Everything at once: DRAW a catch-slide as you fall, FREEZE on the perch, skate, puff the pit — then ride the lift to the top.",
              spawn: CGPoint(x: 0.42, y: 0.92),
              walls: [
                  CGRect(x: 0.00, y: 0.30, width: 0.25, height: 0.03),   // the perch
                  CGRect(x: 0.52, y: 0.52, width: 0.22, height: 0.03),   // goal ledge
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
              inkBudget: 260,
              par: 38),
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
    private var iceApplied = false
    /// Zones in scene coordinates, checked geometrically every frame.
    /// Sensor-style physics contacts (collision-less bodies) proved
    /// unreliable for a ball rolling along the scene edge, so the checks
    /// that decide life and death are plain rect math instead.
    private var zoneRects: [(kind: ZoneKind, rect: CGRect)] = []
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
    private lazy var bgTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 512))
        let img = renderer.image { ctx in
            let colors = [UIColor(red: 0.11, green: 0.13, blue: 0.26, alpha: 1).cgColor,
                          UIColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1).cgColor,
                          UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1).cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.55, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero,
                                             end: CGPoint(x: 0, y: 512), options: [])
        }
        return SKTexture(image: img)
    }()

    private func loadSounds() {
        for name in ["plink", "ice_tap", "freeze", "melt", "goal", "die", "tick", "go", "carve"]
        where Bundle.main.url(forResource: name, withExtension: "wav") != nil {
            sounds[name] = SKAction.playSoundFileNamed("\(name).wav", waitForCompletion: false)
        }
        NSLog("DripDrop: loaded \(sounds.count)/9 sounds")
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
        model?.isIce = false            // every level starts as water
        levelStartTime = CACurrentMediaTime()
        model?.availableScore = 1000

        let bg = SKSpriteNode(texture: bgTexture)
        bg.size = size
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bg.zPosition = -100
        bg.shader = Decor.causticShader
        addChild(bg)
        addChild(Decor.vignette(size: size))
        for mote in Decor.motes(size: size) { addChild(mote) }

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
        zoneRects = level.zones.map { (kind: $0.kind, rect: rect($0.rect)) }
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
        node.run(.repeatForever(.sequence([go, back])))
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
            node = Decor.goalPool(rect: r)
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

        let visual = DropletVisual()
        visual.position = p
        addChild(visual)
        dropletVisual = visual

        let marker = Decor.spawnRing(at: p)
        addChild(marker)
        spawnMarker = marker
    }

    /// Water vs ice: same ball, different physics material. The look is the
    /// shader's job — DropletVisual morphs between phases on its own.
    private func applyPhase() {
        guard let model, let body = droplet?.physicsBody else { return }
        iceApplied = model.isIce
        if iceApplied {
            trail?.particleColor = .white
            body.friction = 0.02
            body.linearDamping = 0.05
            body.restitution = 0.08
        } else {
            // Damping 0.8 is water's identity: it clings in flight, which is
            // exactly why it can't clear the level-4 pit and ice can.
            trail?.particleColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)
            body.friction = 0.25
            body.linearDamping = 0.8
            body.restitution = 0.3
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
        if grounded {
            let dy = min(model.tilt.dy, -0.25)
            physicsWorld.gravity = CGVector(dx: model.tilt.dx * gravityStrength,
                                            dy: dy * gravityStrength)
        } else {
            physicsWorld.gravity = CGVector(dx: model.tilt.dx * gravityStrength * airSteer,
                                            dy: -0.55 * gravityStrength)
        }

        if model.isIce != iceApplied {
            applyPhase()
            freezeHaptic.impactOccurred()
            sfx(iceApplied ? "freeze" : "melt")
        }

        // During the countdown the world holds its breath: no gravity
        // steering, no lift, no zone checks, no score drain.
        guard runState == .playing else {
            currentLift = 0
            rolling.update(speed: 0, grounded: false, isIce: iceApplied)
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
        let pointsPerMeter: CGFloat = 150
        let lift = max(holdingLift ? 0.9 : 0, CGFloat(model.blowLevel))
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

        // Per-phase speed cap: water can't hold together at speed; ice can.
        // This is what makes momentum jumps an ice-only ability.
        let v = body.velocity
        let speed = hypot(v.dx, v.dy)
        let cap = iceApplied ? maxSpeed : waterMaxSpeed
        if speed > cap {
            let k = cap / speed
            body.velocity = CGVector(dx: v.dx * k, dy: v.dy * k)
        }

        // Squash, stretch, wobble and drip all live in the metaball shader
        // now — see DropletVisual.sync, driven from didFinishUpdate().

        // Trail intensity follows speed.
        trail?.particleBirthRate = speed > 250 ? min(40, speed / 15) : 0

        // Rolling texture in the palm: contact, speed, and phase.
        rolling.update(speed: speed, grounded: grounded, isIce: iceApplied)

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
                if circleIntersects(z.rect, center: c, radius: 14) { advance() }
            case .drain:
                if circleIntersects(z.rect, center: c, radius: 10) { die() }
            case .grate:
                if !model.isIce, circleIntersects(z.rect, center: c, radius: 10) { die() }
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
                    isIce: model.isIce,
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
            sfx(iceApplied ? "ice_tap" : "plink")
            // Water sheds a few droplets on a hard hit; ice stays whole.
            if !iceApplied, speed > 500 {
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
        let splash = iceApplied
            ? UIColor.white
            : UIColor(red: 0.35, green: 0.68, blue: 1, alpha: 1)
        burst(at: droplet.position, color: splash, up: false, count: 30)
        shake(0.7)
        droplet.physicsBody?.velocity = .zero
        droplet.physicsBody?.angularVelocity = 0
        droplet.position = point(Levels.all[levelIndex].spawn)
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
    }

    private func commitChannel(points: [CGPoint]) {
        let path = CGMutablePath()
        path.addLines(between: points)
        let node = SKShapeNode(path: path)
        node.strokeColor = UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.9)
        node.lineWidth = 5
        node.lineCap = .round
        node.glowWidth = 2
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
        node.run(.sequence([
            .wait(forDuration: channelLifetime - 1.2),
            .repeat(.sequence([.fadeAlpha(to: 0.25, duration: 0.15),
                               .fadeAlpha(to: 0.9, duration: 0.15)]), count: 3),
            .fadeOut(withDuration: 0.3),
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
