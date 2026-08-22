// Environment art: everything in the diorama that isn't the droplet.
// All procedural (UIGraphicsImageRenderer textures + shape nodes) — no
// licensed assets. Visual language, kept strict for readability:
//   walls/ramps/movers — glassy slate slabs (movers get a cyan running light)
//   goal  — glowing green pool with ripples and rising bubbles
//   drain — floor pit: dark opening with a pulsing ember glow
//   drain (elevated) — hanging white-blue icicles
//   grate — cyan metallic slats on a dark base

import SpriteKit
import UIKit

enum Decor {

    // MARK: - Cached textures

    /// Soft radial falloff, tinted per use. Basis for glows and shadows.
    static func radialTexture(inner: UIColor, outer: UIColor, size: CGFloat = 128) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { ctx in
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [inner.cgColor, outer.cgColor] as CFArray,
                                  locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size / 2,
                options: [])
        }
        return SKTexture(image: img)
    }

    static let shadow = radialTexture(inner: UIColor.black.withAlphaComponent(0.55),
                                      outer: UIColor.black.withAlphaComponent(0), size: 48)
    static let greenGlow = radialTexture(inner: UIColor.systemGreen.withAlphaComponent(0.65),
                                         outer: UIColor.systemGreen.withAlphaComponent(0))
    static let emberGlow = radialTexture(inner: UIColor(red: 1, green: 0.30, blue: 0.15, alpha: 0.8),
                                         outer: UIColor(red: 1, green: 0.2, blue: 0.1, alpha: 0))
    static let softDot = radialTexture(inner: UIColor.white,
                                       outer: UIColor.white.withAlphaComponent(0), size: 32)

    /// Deterministic 0…1 hash so decoration never shifts between loads.
    static func prand(_ i: Int) -> CGFloat {
        let x = sin(CGFloat(i) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    // MARK: - Walls / ramps / movers

    /// Glassy slate slab rendered at exact pixel size: vertical gradient,
    /// crisp top highlight, hairline stroke.
    static func slabTexture(size: CGSize) -> SKTexture {
        let sz = CGSize(width: max(size.width, 6), height: max(size.height, 6))
        let renderer = UIGraphicsImageRenderer(size: sz)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let r = CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5)
            let radius = min(4, min(r.width, r.height) / 2)
            let path = UIBezierPath(roundedRect: r, cornerRadius: radius)
            c.addPath(path.cgPath)
            c.clip()
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.31, green: 0.35, blue: 0.46, alpha: 1).cgColor,
                                           UIColor(red: 0.15, green: 0.17, blue: 0.25, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero,
                                 end: CGPoint(x: 0, y: sz.height), options: [])
            // Top highlight (renderer y is top-down).
            UIColor.white.withAlphaComponent(0.30).setFill()
            c.fill(CGRect(x: 1.5, y: 0.5, width: sz.width - 3, height: 1.5))
            UIColor.white.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        return SKTexture(image: img)
    }

    /// Visual-only slab centered at rect's center; caller attaches physics.
    static func slab(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        let sh = SKSpriteNode(texture: shadow)
        sh.centerRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        sh.size = CGSize(width: rect.width + 18, height: rect.height + 18)
        sh.position = CGPoint(x: 2, y: -5)
        sh.alpha = 0.6
        sh.zPosition = -1
        node.addChild(sh)
        let slab = SKSpriteNode(texture: slabTexture(size: rect.size))
        slab.size = rect.size
        node.addChild(slab)
        return node
    }

    /// Mover platform: a slab plus a pulsing cyan running light so moving
    /// geometry is instantly tellable from static geometry.
    static func moverSlab(size: CGSize) -> SKNode {
        let node = slab(rect: CGRect(origin: .zero, size: size)
            .offsetBy(dx: -size.width / 2, dy: -size.height / 2))
        node.position = .zero
        let light = SKShapeNode(rectOf: CGSize(width: size.width - 6, height: 2.5),
                                cornerRadius: 1.2)
        light.fillColor = UIColor.systemCyan
        light.strokeColor = .clear
        light.glowWidth = 3
        light.position = CGPoint(x: 0, y: -size.height / 2 - 3)
        light.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.45, duration: 0.9),
            .fadeAlpha(to: 1.0, duration: 0.9),
        ])))
        node.addChild(light)
        return node
    }

    // MARK: - Zones

    /// Goal: a glowing pool of still water — gradient basin, breathing outer
    /// glow, expanding surface ripples, a lazy stream of rising bubbles.
    static func goalPool(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)

        let glow = SKSpriteNode(texture: greenGlow)
        glow.size = CGSize(width: rect.width * 2.1, height: rect.height * 4.5)
        glow.alpha = 0.45
        glow.blendMode = .add
        glow.zPosition = -1
        glow.run(.repeatForever(.sequence([
            .group([.fadeAlpha(to: 0.30, duration: 1.3), .scale(to: 0.92, duration: 1.3)]),
            .group([.fadeAlpha(to: 0.55, duration: 1.3), .scale(to: 1.06, duration: 1.3)]),
        ])))
        node.addChild(glow)

        let basin = SKShapeNode(rectOf: rect.size, cornerRadius: 3)
        basin.fillColor = UIColor(red: 0.05, green: 0.42, blue: 0.28, alpha: 0.9)
        basin.strokeColor = UIColor(red: 0.35, green: 0.95, blue: 0.65, alpha: 0.9)
        basin.lineWidth = 1.2
        node.addChild(basin)

        let surface = SKShapeNode(rectOf: CGSize(width: rect.width - 4, height: 1.8),
                                  cornerRadius: 0.9)
        surface.fillColor = UIColor(red: 0.55, green: 1.0, blue: 0.8, alpha: 0.85)
        surface.strokeColor = .clear
        surface.glowWidth = 2
        surface.position = CGPoint(x: 0, y: rect.height / 2 - 2)
        node.addChild(surface)

        for i in 0..<2 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.6,
                                                     height: rect.height * 0.8))
            ring.strokeColor = UIColor(red: 0.5, green: 1.0, blue: 0.75, alpha: 1)
            ring.lineWidth = 1
            ring.fillColor = .clear
            ring.alpha = 0
            let cycle = SKAction.sequence([
                .group([.scale(to: 1.5, duration: 1.8),
                        .sequence([.fadeAlpha(to: 0.5, duration: 0.3),
                                   .fadeAlpha(to: 0, duration: 1.5)])]),
                .scale(to: 0.6, duration: 0),
            ])
            ring.run(.repeatForever(.sequence([.wait(forDuration: Double(i) * 0.9), cycle])))
            node.addChild(ring)
        }

        let bubbles = SKEmitterNode()
        bubbles.particleTexture = softDot
        bubbles.particleBirthRate = 3
        bubbles.particleLifetime = 1.4
        bubbles.particleSpeed = 22
        bubbles.particleSpeedRange = 10
        bubbles.emissionAngle = .pi / 2
        bubbles.particlePositionRange = CGVector(dx: rect.width * 0.7, dy: 4)
        bubbles.particleAlpha = 0.5
        bubbles.particleAlphaSpeed = -0.4
        bubbles.particleScale = 0.16
        bubbles.particleScaleRange = 0.08
        bubbles.particleColor = UIColor(red: 0.6, green: 1.0, blue: 0.8, alpha: 1)
        bubbles.particleColorBlendFactor = 1
        node.addChild(bubbles)

        return node
    }

    /// Floor drain: a dark pit with a pulsing ember glow and drifting sparks.
    static func drainPit(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)

        let pit = SKShapeNode(rectOf: rect.size, cornerRadius: 3)
        pit.fillColor = UIColor(red: 0.06, green: 0.015, blue: 0.03, alpha: 0.95)
        pit.strokeColor = UIColor(red: 1, green: 0.28, blue: 0.2, alpha: 0.55)
        pit.lineWidth = 1
        node.addChild(pit)

        let ember = SKSpriteNode(texture: emberGlow)
        ember.size = CGSize(width: rect.width * 0.9, height: rect.height * 2.6)
        ember.position = CGPoint(x: 0, y: -rect.height * 0.2)
        ember.blendMode = .add
        ember.alpha = 0.5
        ember.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.30, duration: 0.9),
            .fadeAlpha(to: 0.65, duration: 0.9),
        ])))
        node.addChild(ember)

        let sparks = SKEmitterNode()
        sparks.particleTexture = softDot
        sparks.particleBirthRate = 4
        sparks.particleLifetime = 1.1
        sparks.particleSpeed = 20
        sparks.particleSpeedRange = 12
        sparks.emissionAngle = .pi / 2
        sparks.emissionAngleRange = 0.5
        sparks.particlePositionRange = CGVector(dx: rect.width * 0.8, dy: 2)
        sparks.particleAlpha = 0.45
        sparks.particleAlphaSpeed = -0.45
        sparks.particleScale = 0.14
        sparks.particleColor = UIColor(red: 1, green: 0.45, blue: 0.25, alpha: 1)
        sparks.particleColorBlendFactor = 1
        node.addChild(sparks)

        return node
    }

    /// Elevated drain: hanging icicles — jagged white-blue teeth under a bar,
    /// with twinkling tips. Same kill rect, honest silhouette.
    static func icicles(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width, h = rect.height

        let bar = SKShapeNode(rectOf: CGSize(width: w, height: 3.5), cornerRadius: 1.5)
        bar.fillColor = UIColor(red: 0.75, green: 0.85, blue: 0.98, alpha: 0.95)
        bar.strokeColor = UIColor.white.withAlphaComponent(0.6)
        bar.lineWidth = 0.5
        bar.position = CGPoint(x: 0, y: h / 2 - 1.5)
        node.addChild(bar)

        let teeth = CGMutablePath()
        let count = max(4, Int(w / 15))
        let toothW = w / CGFloat(count)
        for i in 0..<count {
            let x0 = -w / 2 + CGFloat(i) * toothW
            let len = h * (0.55 + 0.5 * prand(i * 7 + Int(w)))
            teeth.move(to: CGPoint(x: x0, y: h / 2 - 2))
            teeth.addLine(to: CGPoint(x: x0 + toothW, y: h / 2 - 2))
            teeth.addLine(to: CGPoint(x: x0 + toothW / 2, y: h / 2 - 2 - len))
            teeth.closeSubpath()
        }
        let icicle = SKShapeNode(path: teeth)
        icicle.fillColor = UIColor(red: 0.82, green: 0.90, blue: 1.0, alpha: 0.9)
        icicle.strokeColor = UIColor.white.withAlphaComponent(0.75)
        icicle.lineWidth = 0.8
        icicle.glowWidth = 1
        node.addChild(icicle)

        for i in 0..<3 {
            let tipIndex = (i * count) / 3
            let x = -w / 2 + (CGFloat(tipIndex) + 0.5) * toothW
            let len = h * (0.55 + 0.5 * prand(tipIndex * 7 + Int(w)))
            let glint = SKSpriteNode(texture: softDot)
            glint.size = CGSize(width: 7, height: 7)
            glint.position = CGPoint(x: x, y: h / 2 - 2 - len)
            glint.alpha = 0
            glint.run(.repeatForever(.sequence([
                .wait(forDuration: 0.7 + Double(prand(i + 91)) * 2.2),
                .fadeAlpha(to: 0.9, duration: 0.12),
                .fadeAlpha(to: 0, duration: 0.35),
            ])))
            node.addChild(glint)
        }
        return node
    }

    /// Grate: steel bars over a visible dark void, with water perpetually
    /// trickling down through the gaps — the trickle is what tells you
    /// liquid falls through here. Ice crosses it; that's the cyan accent.
    static func grate(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)

        // The void beneath the bars.
        let void = SKShapeNode(rectOf: rect.size, cornerRadius: 2)
        void.fillColor = UIColor(red: 0.01, green: 0.03, blue: 0.05, alpha: 0.95)
        void.strokeColor = UIColor(red: 0.30, green: 0.55, blue: 0.62, alpha: 0.6)
        void.lineWidth = 1
        node.addChild(void)

        // Machined steel bars: bright caps, shaded feet, real gaps between.
        let barCount = max(4, Int(rect.width / 13))
        for s in 0..<barCount {
            let x = -rect.width / 2 + rect.width * (CGFloat(s) + 0.5) / CGFloat(barCount)
            let bar = SKShapeNode(rectOf: CGSize(width: 4.5, height: rect.height * 0.9),
                                  cornerRadius: 1.5)
            bar.fillColor = UIColor(red: 0.42, green: 0.58, blue: 0.66, alpha: 0.95)
            bar.strokeColor = .clear
            bar.position = CGPoint(x: x, y: 0)
            node.addChild(bar)
            let cap = SKShapeNode(rectOf: CGSize(width: 4.5, height: 2))
            cap.fillColor = UIColor.white.withAlphaComponent(0.55)
            cap.strokeColor = .clear
            cap.position = CGPoint(x: x, y: rect.height * 0.45 - 1)
            node.addChild(cap)
            let foot = SKShapeNode(rectOf: CGSize(width: 4.5, height: 2))
            foot.fillColor = UIColor.black.withAlphaComponent(0.45)
            foot.strokeColor = .clear
            foot.position = CGPoint(x: x, y: -rect.height * 0.45 + 1)
            node.addChild(foot)
        }

        // The machined lip along the top edge.
        let rail = SKShapeNode(rectOf: CGSize(width: rect.width, height: 2.2),
                               cornerRadius: 1.1)
        rail.fillColor = UIColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 0.9)
        rail.strokeColor = .clear
        rail.glowWidth = 1
        rail.position = CGPoint(x: 0, y: rect.height / 2 - 1.1)
        node.addChild(rail)

        // Water threading down through the gaps — the storytelling.
        let trickle = SKEmitterNode()
        trickle.particleTexture = softDot
        trickle.particleBirthRate = 7
        trickle.particleLifetime = 0.55
        trickle.particleSpeed = 42
        trickle.particleSpeedRange = 18
        trickle.emissionAngle = -.pi / 2
        trickle.emissionAngleRange = 0.1
        trickle.particlePositionRange = CGVector(dx: rect.width * 0.92, dy: 2)
        trickle.position = CGPoint(x: 0, y: rect.height / 2 - 2)
        trickle.particleAlpha = 0.5
        trickle.particleAlphaSpeed = -0.8
        trickle.particleScale = 0.16
        trickle.particleScaleRange = 0.06
        trickle.particleColor = UIColor(red: 0.45, green: 0.72, blue: 1.0, alpha: 1)
        trickle.particleColorBlendFactor = 1
        node.addChild(trickle)

        return node
    }

    // MARK: - Backdrop

    /// Faint moving water-caustic shimmer over the gradient backdrop,
    /// tinted per mood. Cached per tint (shaders are per-level singletons).
    private static var causticCache: [String: SKShader] = [:]
    static func causticShader(tint: SIMD3<Float>) -> SKShader {
        let key = "\(tint.x),\(tint.y),\(tint.z)"
        if let cached = causticCache[key] { return cached }
        let shader = SKShader(source: """
        void main() {
            vec4 base = texture2D(u_texture, v_tex_coord);
            vec2 p = v_tex_coord * vec2(6.0, 10.0);
            float c = sin(p.x * 1.7 + u_time * 0.45)
                    + sin(p.y * 1.3 - u_time * 0.32)
                    + sin((p.x + p.y) * 1.1 + u_time * 0.21);
            float glow = smoothstep(1.1, 3.0, c) * 0.05;
            gl_FragColor = vec4(base.rgb + vec3(\(tint.x), \(tint.y), \(tint.z)) * glow, 1.0);
        }
        """)
        causticCache[key] = shader
        return shader
    }

    static func vignette(size: CGSize) -> SKNode {
        let dim: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim))
        let img = renderer.image { ctx in
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor.black.withAlphaComponent(0).cgColor,
                                           UIColor.black.withAlphaComponent(0.10).cgColor,
                                           UIColor.black.withAlphaComponent(0.45).cgColor] as CFArray,
                                  locations: [0, 0.72, 1])!
            ctx.cgContext.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: dim / 2, y: dim / 2), startRadius: 0,
                endCenter: CGPoint(x: dim / 2, y: dim / 2), endRadius: dim * 0.72,
                options: [.drawsAfterEndLocation])
        }
        let n = SKSpriteNode(texture: SKTexture(image: img))
        n.size = size
        n.position = CGPoint(x: size.width / 2, y: size.height / 2)
        n.zPosition = -90
        return n
    }

    /// Two layers of ambient drift: big soft motes and rare bright specks.
    static func motes(size: CGSize,
                      color: UIColor = UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1)) -> [SKEmitterNode] {
        func layer(rate: CGFloat, life: CGFloat, scale: CGFloat,
                   alpha: CGFloat, speed: CGFloat) -> SKEmitterNode {
            let e = SKEmitterNode()
            e.particleTexture = softDot
            e.particleBirthRate = rate
            e.particleLifetime = life
            e.particleSpeed = speed
            e.particleSpeedRange = speed * 0.6
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = 0.6
            e.particlePositionRange = CGVector(dx: size.width, dy: size.height)
            e.position = CGPoint(x: size.width / 2, y: size.height / 2)
            e.particleAlpha = alpha
            e.particleAlphaRange = alpha * 0.5
            e.particleScale = scale
            e.particleScaleRange = scale * 0.5
            e.particleColor = color
            e.particleColorBlendFactor = 1
            e.zPosition = -80
            e.advanceSimulationTime(Double(life))
            return e
        }
        return [layer(rate: 1.6, life: 14, scale: 1.3, alpha: 0.05, speed: 7),
                layer(rate: 0.8, life: 10, scale: 0.28, alpha: 0.14, speed: 12)]
    }

    /// Pulsing ring marking the spawn point during the countdown.
    static func spawnRing(at p: CGPoint) -> SKNode {
        let node = SKNode()
        node.position = p
        let ring = SKShapeNode(circleOfRadius: 16)
        ring.strokeColor = UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1)
        ring.lineWidth = 1.5
        ring.fillColor = .clear
        ring.glowWidth = 2
        ring.run(.repeatForever(.sequence([
            .group([.scale(to: 1.7, duration: 1.0),
                    .sequence([.fadeAlpha(to: 0.7, duration: 0.15),
                               .fadeAlpha(to: 0, duration: 0.85)])]),
            .scale(to: 1.0, duration: 0),
        ])))
        node.addChild(ring)
        return node
    }
}
