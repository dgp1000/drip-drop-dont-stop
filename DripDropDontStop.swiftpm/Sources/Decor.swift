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

/// The five diorama worlds, one per mood.
enum DioramaTheme {
    case kitchen        // abyss — moonlit night kitchen
    case freezer        // frost — steel walk-in cold room
    case boiler         // warm — iron pipes and ember light
    case rooftop        // storm — night rain over a skyline
    case greenhouse     // mist — glass panes and hanging leaves

    static func theme(for mood: Mood) -> DioramaTheme {
        switch mood {
        case .abyss: return .kitchen
        case .frost: return .freezer
        case .warm:  return .boiler
        case .storm: return .rooftop
        case .mist:  return .greenhouse
        }
    }
}

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
        let tex: SKTexture
        switch currentTheme {
        case .kitchen:    tex = woodTexture(size: rect.size)
        case .freezer:    tex = frostSteelTexture(size: rect.size)
        case .boiler:     tex = ironTexture(size: rect.size)
        case .rooftop:    tex = slateShingleTexture(size: rect.size)
        case .greenhouse: tex = mossWoodTexture(size: rect.size)
        }
        let slab = SKSpriteNode(texture: tex)
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

    /// Goal: a themed vessel that collects the droplet — glass, ice-cube
    /// tray, bucket, rain barrel, or plant pot. The green glow, ripples and
    /// bubbles are shared across all themes: that's the "home" language.
    static func goalVessel(rect: CGRect, theme: DioramaTheme) -> SKNode {
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

        let w = rect.width, h = rect.height
        switch theme {
        case .kitchen:
            // A drinking glass: transparent walls rising past the zone.
            let wall = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 0.45)
            for sx in [-w / 2 + 1.5, w / 2 - 1.5] {
                let side = SKShapeNode(rectOf: CGSize(width: 3, height: h + 14),
                                       cornerRadius: 1.5)
                side.fillColor = wall
                side.strokeColor = .clear
                side.position = CGPoint(x: sx, y: 7)
                node.addChild(side)
            }
            let base = SKShapeNode(rectOf: CGSize(width: w, height: 3.5), cornerRadius: 1.5)
            base.fillColor = wall
            base.strokeColor = .clear
            base.position = CGPoint(x: 0, y: -h / 2 + 1.5)
            node.addChild(base)
        case .freezer:
            // An ice-cube tray: pale body with cube dividers.
            let tray = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 3)
            tray.fillColor = UIColor(red: 0.72, green: 0.82, blue: 0.94, alpha: 0.85)
            tray.strokeColor = UIColor.white.withAlphaComponent(0.7)
            tray.lineWidth = 1.2
            node.addChild(tray)
            for dx in [-w / 6, w / 6] {
                let div = SKShapeNode(rectOf: CGSize(width: 2, height: h - 6))
                div.fillColor = UIColor(red: 0.45, green: 0.58, blue: 0.72, alpha: 0.7)
                div.strokeColor = .clear
                div.position = CGPoint(x: dx, y: 0)
                node.addChild(div)
            }
        case .boiler:
            // A riveted bucket with a handle.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: -w / 2, y: h / 2))
            body.addLine(to: CGPoint(x: w / 2, y: h / 2))
            body.addLine(to: CGPoint(x: w * 0.36, y: -h / 2))
            body.addLine(to: CGPoint(x: -w * 0.36, y: -h / 2))
            body.closeSubpath()
            let bucket = SKShapeNode(path: body)
            bucket.fillColor = UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 0.95)
            bucket.strokeColor = UIColor(red: 0.7, green: 0.72, blue: 0.78, alpha: 0.8)
            bucket.lineWidth = 1.2
            node.addChild(bucket)
            let handle = SKShapeNode(path: {
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: 0, y: h / 2), radius: w * 0.42,
                         startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                return p
            }())
            handle.strokeColor = UIColor(red: 0.62, green: 0.64, blue: 0.7, alpha: 0.85)
            handle.lineWidth = 2.5
            node.addChild(handle)
        case .rooftop:
            // A rain barrel: staves and hoops.
            let barrel = SKShapeNode(rectOf: CGSize(width: w, height: h + 8), cornerRadius: 5)
            barrel.fillColor = UIColor(red: 0.34, green: 0.23, blue: 0.14, alpha: 0.95)
            barrel.strokeColor = UIColor(red: 0.5, green: 0.36, blue: 0.22, alpha: 0.9)
            barrel.lineWidth = 1.2
            barrel.position = CGPoint(x: 0, y: -1)
            node.addChild(barrel)
            for hy in [-h * 0.28, h * 0.22] {
                let hoop = SKShapeNode(rectOf: CGSize(width: w, height: 3.2))
                hoop.fillColor = UIColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0.9)
                hoop.strokeColor = .clear
                hoop.position = CGPoint(x: 0, y: hy)
                node.addChild(hoop)
            }
            for i in 1...3 {
                let stave = SKShapeNode(rectOf: CGSize(width: 1.2, height: h + 6))
                stave.fillColor = UIColor.black.withAlphaComponent(0.25)
                stave.strokeColor = .clear
                stave.position = CGPoint(x: -w / 2 + w * CGFloat(i) / 4, y: -1)
                node.addChild(stave)
            }
        case .greenhouse:
            // A terracotta pot with a hopeful sprout.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: -w / 2, y: h / 2))
            body.addLine(to: CGPoint(x: w / 2, y: h / 2))
            body.addLine(to: CGPoint(x: w * 0.34, y: -h / 2))
            body.addLine(to: CGPoint(x: -w * 0.34, y: -h / 2))
            body.closeSubpath()
            let pot = SKShapeNode(path: body)
            pot.fillColor = UIColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 0.95)
            pot.strokeColor = UIColor(red: 0.72, green: 0.44, blue: 0.28, alpha: 0.9)
            pot.lineWidth = 1.2
            node.addChild(pot)
            let rim = SKShapeNode(rectOf: CGSize(width: w + 6, height: 6), cornerRadius: 2)
            rim.fillColor = UIColor(red: 0.66, green: 0.38, blue: 0.24, alpha: 1)
            rim.strokeColor = .clear
            rim.position = CGPoint(x: 0, y: h / 2 - 2)
            node.addChild(rim)
            let stem = SKShapeNode(rectOf: CGSize(width: 1.8, height: 10))
            stem.fillColor = UIColor(red: 0.3, green: 0.6, blue: 0.32, alpha: 1)
            stem.strokeColor = .clear
            stem.position = CGPoint(x: w * 0.28, y: h / 2 + 6)
            node.addChild(stem)
            for (dx, rot) in [(-5.0, 0.6), (5.0, -0.6)] {
                let leaf = SKShapeNode(ellipseOf: CGSize(width: 11, height: 5))
                leaf.fillColor = UIColor(red: 0.32, green: 0.65, blue: 0.35, alpha: 1)
                leaf.strokeColor = .clear
                leaf.position = CGPoint(x: w * 0.28 + dx, y: h / 2 + 12)
                leaf.zRotation = rot
                node.addChild(leaf)
            }
        }

        // The collected water inside, whatever the vessel.
        let waterFill = SKShapeNode(rectOf: CGSize(width: w * 0.8, height: h * 0.42),
                                    cornerRadius: 2)
        waterFill.fillColor = UIColor(red: 0.10, green: 0.5, blue: 0.38, alpha: 0.8)
        waterFill.strokeColor = .clear
        waterFill.position = CGPoint(x: 0, y: -h * 0.18)
        node.addChild(waterFill)
        let surface = SKShapeNode(rectOf: CGSize(width: w * 0.8, height: 1.8),
                                  cornerRadius: 0.9)
        surface.fillColor = UIColor(red: 0.55, green: 1.0, blue: 0.8, alpha: 0.85)
        surface.strokeColor = .clear
        surface.glowWidth = 2
        surface.position = CGPoint(x: 0, y: h * 0.03)
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

    // MARK: - Dioramas: every level is a miniature scene, themed by mood.
    // Hazard visuals (pools, pits, icicles, grates) are shared across all
    // themes — the danger language must survive the set dressing.

    /// Which slab texture the builders use; GameScene sets this per level
    /// before constructing geometry.
    static var currentTheme: DioramaTheme = .kitchen

    static func dioramaBackdrop(theme: DioramaTheme, size: CGSize) -> SKNode {
        switch theme {
        case .kitchen:    return kitchenBackdrop(size: size)
        case .freezer:    return freezerBackdrop(size: size)
        case .boiler:     return boilerBackdrop(size: size)
        case .rooftop:    return rooftopBackdrop(size: size)
        case .greenhouse: return greenhouseBackdrop(size: size)
        }
    }

    /// Ambient set dressing that isn't the water source.
    static func ambientProp(theme: DioramaTheme, sceneSize: CGSize) -> SKNode? {
        switch theme {
        case .rooftop:    return downpipe(sceneSize: sceneSize)
        case .greenhouse: return vines(sceneSize: sceneSize)
        case .kitchen, .freezer, .boiler: return nil
        }
    }

    // MARK: - Water sources: every droplet comes from somewhere.
    // High spawns hang a ceiling source; edge spawns get a wall stub.

    /// A slow drip falling from the source nozzle — the droplet's siblings.
    private static func dripEmitter() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = softDot
        e.particleBirthRate = 0.6
        e.particleLifetime = 0.7
        e.particleSpeed = 30
        e.emissionAngle = -.pi / 2
        e.yAcceleration = -420
        e.particleAlpha = 0.6
        e.particleAlphaSpeed = -0.7
        e.particleScale = 0.2
        e.particleColor = UIColor(red: 0.5, green: 0.75, blue: 1.0, alpha: 1)
        e.particleColorBlendFactor = 1
        return e
    }

    private static func sourcePalette(_ theme: DioramaTheme)
        -> (pipe: UIColor, accent: UIColor) {
        switch theme {
        case .kitchen:    return (UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1),
                                  UIColor(red: 0.75, green: 0.80, blue: 0.88, alpha: 0.9))
        case .freezer:    return (UIColor(red: 0.48, green: 0.56, blue: 0.66, alpha: 1),
                                  UIColor.white.withAlphaComponent(0.85))
        case .boiler:     return (UIColor(red: 0.45, green: 0.27, blue: 0.15, alpha: 1),
                                  UIColor(red: 0.78, green: 0.64, blue: 0.42, alpha: 0.95))
        case .rooftop:    return (UIColor(red: 0.18, green: 0.19, blue: 0.24, alpha: 1),
                                  UIColor(red: 0.45, green: 0.48, blue: 0.56, alpha: 0.9))
        case .greenhouse: return (UIColor(red: 0.16, green: 0.34, blue: 0.20, alpha: 1),
                                  UIColor(red: 0.72, green: 0.60, blue: 0.35, alpha: 0.95))
        }
    }

    /// The level's water source, above or beside the spawn.
    static func sourceProp(theme: DioramaTheme, spawn: CGPoint,
                           sceneSize: CGSize) -> SKNode {
        // The kitchen's high source is the full faucet — the original.
        if theme == .kitchen, spawn.y > sceneSize.height * 0.72 {
            let f = faucet(aboveSpawn: spawn, sceneSize: sceneSize)
            let drip = dripEmitter()
            drip.position = CGPoint(x: spawn.x + 12,
                                    y: min(spawn.y + 46, sceneSize.height - 30) - 40)
            f.addChild(drip)
            return f
        }
        let (pipeColor, accent) = sourcePalette(theme)
        let node = SKNode()
        node.zPosition = -50

        if spawn.y > sceneSize.height * 0.72 {
            // Ceiling source: a pipe dropping from the top edge, ending in
            // a nozzle above the spawn.
            let tipY = min(spawn.y + 42, sceneSize.height - 24)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: spawn.x, y: sceneSize.height + 8))
            path.addLine(to: CGPoint(x: spawn.x, y: tipY))
            let pipe = SKShapeNode(path: path)
            pipe.strokeColor = pipeColor
            pipe.lineWidth = 10
            pipe.lineCap = .round
            node.addChild(pipe)
            let joint = SKShapeNode(rectOf: CGSize(width: 16, height: 6), cornerRadius: 2)
            joint.fillColor = accent
            joint.strokeColor = .clear
            joint.position = CGPoint(x: spawn.x, y: tipY + 26)
            node.addChild(joint)
            let nozzle = SKShapeNode(rectOf: CGSize(width: 14, height: 7), cornerRadius: 2.5)
            nozzle.fillColor = pipeColor
            nozzle.strokeColor = accent
            nozzle.lineWidth = 1
            nozzle.position = CGPoint(x: spawn.x, y: tipY - 3)
            node.addChild(nozzle)
            let drip = dripEmitter()
            drip.position = CGPoint(x: spawn.x, y: tipY - 8)
            node.addChild(drip)
        } else {
            // Wall stub from the nearest side edge, elbowing down over the
            // spawn — a cracked pipe, tap, hose, or scupper by theme.
            let fromLeft = spawn.x < sceneSize.width / 2
            let edgeX: CGFloat = fromLeft ? -6 : sceneSize.width + 6
            let y = min(spawn.y + 30, sceneSize.height - 24)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: edgeX, y: y))
            path.addLine(to: CGPoint(x: spawn.x - (fromLeft ? 6 : -6), y: y))
            path.addLine(to: CGPoint(x: spawn.x, y: y - 10))
            let pipe = SKShapeNode(path: path)
            pipe.strokeColor = pipeColor
            pipe.lineWidth = 9
            pipe.lineCap = .round
            pipe.lineJoin = .round
            node.addChild(pipe)
            let sheen = SKShapeNode(path: path)
            sheen.strokeColor = accent.withAlphaComponent(0.45)
            sheen.lineWidth = 2.5
            sheen.lineCap = .round
            sheen.position = CGPoint(x: 0, y: 2)
            node.addChild(sheen)
            // Theme accent at the elbow: valve wheel, frost cap, gutter lip.
            switch theme {
            case .kitchen, .boiler:
                let wheel = SKShapeNode(circleOfRadius: 8)
                wheel.strokeColor = accent
                wheel.lineWidth = 2.5
                wheel.fillColor = .clear
                wheel.position = CGPoint(x: spawn.x - (fromLeft ? 26 : -26), y: y + 10)
                let spoke = SKShapeNode(rectOf: CGSize(width: 2, height: 16))
                spoke.fillColor = accent
                spoke.strokeColor = .clear
                wheel.addChild(spoke)
                node.addChild(wheel)
            case .freezer:
                let frost = SKShapeNode(circleOfRadius: 7)
                frost.fillColor = UIColor.white.withAlphaComponent(0.8)
                frost.strokeColor = .clear
                frost.glowWidth = 3
                frost.position = CGPoint(x: spawn.x, y: y - 6)
                node.addChild(frost)
            case .rooftop:
                let lip = SKShapeNode(rectOf: CGSize(width: 16, height: 10), cornerRadius: 2)
                lip.fillColor = pipeColor
                lip.strokeColor = accent
                lip.lineWidth = 1
                lip.position = CGPoint(x: spawn.x, y: y - 8)
                node.addChild(lip)
            case .greenhouse:
                let nozzle = SKShapeNode(rectOf: CGSize(width: 8, height: 12), cornerRadius: 2)
                nozzle.fillColor = accent
                nozzle.strokeColor = .clear
                nozzle.position = CGPoint(x: spawn.x, y: y - 12)
                node.addChild(nozzle)
            }
            let drip = dripEmitter()
            drip.position = CGPoint(x: spawn.x, y: y - 16)
            node.addChild(drip)
        }
        return node
    }

    // MARK: - Diorama: night kitchen (abyss)

    /// A moody night-kitchen wall: warm darkness, a moonlit window with a
    /// light shaft, backsplash tiles, a counter horizon. All procedural.
    static func kitchenBackdrop(size: CGSize) -> SKNode {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.12, green: 0.09, blue: 0.075, alpha: 1).cgColor,
                                           UIColor(red: 0.07, green: 0.055, blue: 0.045, alpha: 1).cgColor,
                                           UIColor(red: 0.045, green: 0.035, blue: 0.03, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
            c.drawLinearGradient(grad, start: .zero,
                                 end: CGPoint(x: 0, y: size.height), options: [])

            // Moonlit window, upper right (renderer y runs downward).
            let win = CGRect(x: size.width * 0.56, y: size.height * 0.08,
                             width: size.width * 0.34, height: size.height * 0.24)
            let winPath = UIBezierPath(roundedRect: win, cornerRadius: 6)
            UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 0.10).setFill()
            winPath.fill()
            UIColor(red: 0.8, green: 0.88, blue: 1.0, alpha: 0.22).setStroke()
            winPath.lineWidth = 2
            winPath.stroke()
            // Panes.
            c.setStrokeColor(UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.8).cgColor)
            c.setLineWidth(3)
            c.move(to: CGPoint(x: win.midX, y: win.minY)); c.addLine(to: CGPoint(x: win.midX, y: win.maxY))
            c.move(to: CGPoint(x: win.minX, y: win.midY)); c.addLine(to: CGPoint(x: win.maxX, y: win.midY))
            c.strokePath()
            // Light shaft falling left toward the floor.
            c.saveGState()
            c.beginPath()
            c.move(to: CGPoint(x: win.minX, y: win.maxY))
            c.addLine(to: CGPoint(x: win.maxX, y: win.maxY))
            c.addLine(to: CGPoint(x: size.width * 0.42, y: size.height))
            c.addLine(to: CGPoint(x: size.width * 0.08, y: size.height))
            c.closePath()
            c.setFillColor(UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 0.045).cgColor)
            c.fillPath()
            c.restoreGState()

            // Backsplash tiles on the lower wall.
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.05).cgColor)
            c.setLineWidth(1)
            let tileTop = size.height * 0.62
            var y = tileTop
            var row = 0
            while y < size.height {
                c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y))
                var x = (row % 2 == 0) ? 0 : size.width * 0.075
                while x < size.width {
                    c.move(to: CGPoint(x: x, y: y))
                    c.addLine(to: CGPoint(x: x, y: min(y + size.height * 0.055, size.height)))
                    x += size.width * 0.15
                }
                y += size.height * 0.055
                row += 1
            }
            // Counter horizon.
            c.setStrokeColor(UIColor(red: 0.55, green: 0.42, blue: 0.28, alpha: 0.35).cgColor)
            c.setLineWidth(2.5)
            c.move(to: CGPoint(x: 0, y: tileTop)); c.addLine(to: CGPoint(x: size.width, y: tileTop))
            c.strokePath()
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        sprite.size = size
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = -100
        return sprite
    }

    /// Warm wood for counters/shelves: grain streaks and a lit top edge.
    static func woodTexture(size: CGSize) -> SKTexture {
        let sz = CGSize(width: max(size.width, 6), height: max(size.height, 6))
        let renderer = UIGraphicsImageRenderer(size: sz)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let r = CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: r, cornerRadius: min(4, min(r.width, r.height) / 2))
            c.addPath(path.cgPath)
            c.clip()
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.36, green: 0.25, blue: 0.15, alpha: 1).cgColor,
                                           UIColor(red: 0.24, green: 0.155, blue: 0.095, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: sz.height), options: [])
            // Grain: wavy darker streaks.
            c.setStrokeColor(UIColor(red: 0.14, green: 0.09, blue: 0.05, alpha: 0.35).cgColor)
            c.setLineWidth(1.2)
            let streaks = max(2, Int(sz.height / 7))
            for i in 0..<streaks {
                let gy = sz.height * (CGFloat(i) + 0.6) / CGFloat(streaks)
                c.move(to: CGPoint(x: 0, y: gy))
                var x: CGFloat = 0
                while x < sz.width {
                    x += 14
                    let wobble = sin((x / 23) + CGFloat(i) * 1.7) * 1.3
                    c.addLine(to: CGPoint(x: x, y: gy + wobble))
                }
            }
            c.strokePath()
            // Lit top edge (moonlight catches the counter).
            UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 0.35).setFill()
            c.fill(CGRect(x: 1.5, y: 0.5, width: sz.width - 3, height: 1.5))
        }
        return SKTexture(image: img)
    }

    /// A wooden slab (same shadow treatment as the slate one).
    static func woodSlab(rect: CGRect) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        let sh = SKSpriteNode(texture: shadow)
        sh.centerRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        sh.size = CGSize(width: rect.width + 18, height: rect.height + 18)
        sh.position = CGPoint(x: 2, y: -5)
        sh.alpha = 0.6
        sh.zPosition = -1
        node.addChild(sh)
        let slab = SKSpriteNode(texture: woodTexture(size: rect.size))
        slab.size = rect.size
        node.addChild(slab)
        return node
    }

    /// The storyteller: a steel faucet whose spout sits above the spawn —
    /// the droplet is the drip.
    static func faucet(aboveSpawn spawn: CGPoint, sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        let riserX = spawn.x - 64
        let armY = min(spawn.y + 46, sceneSize.height - 30)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: riserX, y: sceneSize.height + 8))
        path.addLine(to: CGPoint(x: riserX, y: armY))
        path.addArc(tangent1End: CGPoint(x: riserX, y: armY - 16),
                    tangent2End: CGPoint(x: riserX + 16, y: armY - 16), radius: 14)
        path.addLine(to: CGPoint(x: spawn.x, y: armY - 16))
        path.addArc(tangent1End: CGPoint(x: spawn.x + 12, y: armY - 16),
                    tangent2End: CGPoint(x: spawn.x + 12, y: armY - 30), radius: 10)
        path.addLine(to: CGPoint(x: spawn.x + 12, y: armY - 34))
        let pipe = SKShapeNode(path: path)
        pipe.strokeColor = UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
        pipe.lineWidth = 11
        pipe.lineCap = .round
        node.addChild(pipe)
        let sheen = SKShapeNode(path: path)
        sheen.strokeColor = UIColor(red: 0.75, green: 0.80, blue: 0.88, alpha: 0.45)
        sheen.lineWidth = 3
        sheen.lineCap = .round
        sheen.position = CGPoint(x: -2, y: 2)
        node.addChild(sheen)
        // Nozzle.
        let tip = SKShapeNode(rectOf: CGSize(width: 18, height: 8), cornerRadius: 3)
        tip.fillColor = UIColor(red: 0.35, green: 0.37, blue: 0.41, alpha: 1)
        tip.strokeColor = UIColor(red: 0.7, green: 0.74, blue: 0.8, alpha: 0.5)
        tip.lineWidth = 1
        tip.position = CGPoint(x: spawn.x + 12, y: armY - 36)
        node.addChild(tip)
        node.zPosition = -50
        return node
    }

    // MARK: - Diorama: freezer (frost)

    static func freezerBackdrop(size: CGSize) -> SKNode {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.11, green: 0.13, blue: 0.18, alpha: 1).cgColor,
                                           UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Steel wall panels: vertical seams with rivet dots.
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
            c.setLineWidth(2)
            var x = size.width * 0.22
            while x < size.width {
                c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height))
                c.strokePath()
                var y: CGFloat = 30
                while y < size.height {
                    c.setFillColor(UIColor.white.withAlphaComponent(0.16).cgColor)
                    c.fillEllipse(in: CGRect(x: x - 2.5, y: y, width: 5, height: 5))
                    y += 120
                }
                x += size.width * 0.26
            }
            // Fan grille, top right.
            let fc = CGPoint(x: size.width * 0.82, y: size.height * 0.12)
            let fr: CGFloat = size.width * 0.09
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            c.setLineWidth(2.5)
            c.strokeEllipse(in: CGRect(x: fc.x - fr, y: fc.y - fr, width: fr * 2, height: fr * 2))
            c.strokeEllipse(in: CGRect(x: fc.x - fr * 0.55, y: fc.y - fr * 0.55,
                                       width: fr * 1.1, height: fr * 1.1))
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 4
                c.move(to: CGPoint(x: fc.x - cos(a) * fr, y: fc.y - sin(a) * fr))
                c.addLine(to: CGPoint(x: fc.x + cos(a) * fr, y: fc.y + sin(a) * fr))
            }
            c.strokePath()
            // Frost creeping from the bottom corners.
            for (cx, cy) in [(0.0, size.height), (size.width, size.height)] {
                let fgrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor.white.withAlphaComponent(0.07).cgColor,
                                                UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                       locations: [0, 1])!
                c.drawRadialGradient(fgrad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                     endCenter: CGPoint(x: cx, y: cy),
                                     endRadius: size.width * 0.5, options: [])
            }
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        sprite.size = size
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = -100
        return sprite
    }

    // MARK: - Diorama: boiler room (warm)

    static func boilerBackdrop(size: CGSize) -> SKNode {
        let node = SKNode()
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.13, green: 0.09, blue: 0.075, alpha: 1).cgColor,
                                           UIColor(red: 0.06, green: 0.04, blue: 0.035, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Iron plate seams with rivets.
            c.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            c.setLineWidth(2.5)
            var y = size.height * 0.30
            while y < size.height {
                c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y))
                c.strokePath()
                var x: CGFloat = 18
                while x < size.width {
                    c.setFillColor(UIColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 0.5).cgColor)
                    c.fillEllipse(in: CGRect(x: x, y: y - 8, width: 5, height: 5))
                    x += 46
                }
                y += size.height * 0.24
            }
            // The big pipe along the top, with joint bands.
            let pipeY = size.height * 0.045
            let pipe = CGRect(x: -8, y: pipeY, width: size.width + 16, height: 15)
            c.setFillColor(UIColor(red: 0.30, green: 0.18, blue: 0.11, alpha: 1).cgColor)
            c.fill(pipe)
            c.setFillColor(UIColor(red: 0.55, green: 0.36, blue: 0.22, alpha: 0.6).cgColor)
            c.fill(CGRect(x: -8, y: pipeY + 2, width: size.width + 16, height: 3))
            for bx in stride(from: size.width * 0.12, to: size.width, by: size.width * 0.24) {
                c.setFillColor(UIColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1).cgColor)
                c.fill(CGRect(x: bx, y: pipeY - 2, width: 10, height: 19))
            }
            // Pressure gauge hanging off the pipe.
            let gc = CGPoint(x: size.width * 0.78, y: pipeY + 42)
            c.setFillColor(UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: gc.x - 17, y: gc.y - 17, width: 34, height: 34))
            c.setStrokeColor(UIColor(red: 0.75, green: 0.62, blue: 0.42, alpha: 0.8).cgColor)
            c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: gc.x - 17, y: gc.y - 17, width: 34, height: 34))
            c.move(to: CGPoint(x: gc.x - 3, y: gc.y + 3))
            c.addLine(to: CGPoint(x: gc.x + 9, y: gc.y - 9))
            c.strokePath()
            c.setStrokeColor(UIColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 0.9).cgColor)
            c.move(to: CGPoint(x: gc.x + 9, y: gc.y - 13))
            c.addLine(to: CGPoint(x: gc.x + 13, y: gc.y - 9))
            c.strokePath()
            c.move(to: CGPoint(x: gc.x, y: pipeY + 15))
            c.setStrokeColor(UIColor(red: 0.30, green: 0.18, blue: 0.11, alpha: 1).cgColor)
            c.setLineWidth(6)
            c.addLine(to: CGPoint(x: gc.x, y: gc.y - 15))
            c.strokePath()
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        sprite.size = size
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = -100
        node.addChild(sprite)
        // Ember light breathing up from below.
        let ember = SKSpriteNode(texture: emberGlow)
        ember.size = CGSize(width: size.width * 1.3, height: size.height * 0.5)
        ember.position = CGPoint(x: size.width / 2, y: 0)
        ember.blendMode = .add
        ember.alpha = 0.16
        ember.zPosition = -95
        ember.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.10, duration: 2.2),
            .fadeAlpha(to: 0.20, duration: 2.2),
        ])))
        node.addChild(ember)
        return node
    }

    // MARK: - Diorama: stormy rooftop (storm)

    /// Thin vertical streak for rain.
    static let streak: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 20))
        let img = renderer.image { ctx in
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor.white.withAlphaComponent(0).cgColor,
                                           UIColor.white.cgColor,
                                           UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero,
                                             end: CGPoint(x: 0, y: 20), options: [])
        }
        return SKTexture(image: img)
    }()

    static func rooftopBackdrop(size: CGSize) -> SKNode {
        let node = SKNode()
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.13, green: 0.10, blue: 0.22, alpha: 1).cgColor,
                                           UIColor(red: 0.07, green: 0.05, blue: 0.14, alpha: 1).cgColor,
                                           UIColor(red: 0.03, green: 0.02, blue: 0.07, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Moon behind clouds.
            c.setFillColor(UIColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 0.5).cgColor)
            c.fillEllipse(in: CGRect(x: size.width * 0.14, y: size.height * 0.07,
                                     width: 46, height: 46))
            // Cloud silhouettes.
            c.setFillColor(UIColor(red: 0.05, green: 0.04, blue: 0.10, alpha: 0.75).cgColor)
            for (cx, cy, s) in [(0.22, 0.10, 1.0), (0.65, 0.06, 1.4), (0.85, 0.16, 0.9)] {
                let w0 = size.width * 0.30 * s
                c.fillEllipse(in: CGRect(x: size.width * cx - w0 / 2,
                                         y: size.height * cy, width: w0, height: w0 * 0.32))
            }
            // Distant skyline along the bottom.
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                let bw = size.width * (0.07 + 0.05 * prand(i))
                let bh = size.height * (0.045 + 0.05 * prand(i + 40))
                c.setFillColor(UIColor(red: 0.04, green: 0.035, blue: 0.09, alpha: 0.9).cgColor)
                c.fill(CGRect(x: x, y: size.height - bh, width: bw + 1, height: bh))
                // A couple of lit windows.
                if prand(i + 80) > 0.4 {
                    c.setFillColor(UIColor(red: 0.9, green: 0.8, blue: 0.5, alpha: 0.35).cgColor)
                    c.fill(CGRect(x: x + bw * 0.3, y: size.height - bh * 0.7, width: 3, height: 4))
                }
                x += bw
                i += 1
            }
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        sprite.size = size
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = -100
        node.addChild(sprite)
        // Rain, angled with the wind.
        let rain = SKEmitterNode()
        rain.particleTexture = streak
        rain.particleBirthRate = 34
        rain.particleLifetime = 1.4
        rain.particleSpeed = 780
        rain.particleSpeedRange = 160
        rain.emissionAngle = -.pi / 2 - 0.12
        rain.particleRotation = -0.12
        rain.particlePositionRange = CGVector(dx: size.width * 1.3, dy: 4)
        rain.position = CGPoint(x: size.width / 2, y: size.height + 20)
        rain.particleAlpha = 0.11
        rain.particleAlphaRange = 0.05
        rain.particleScale = 0.9
        rain.zPosition = -70
        rain.advanceSimulationTime(2)
        node.addChild(rain)
        // Far-off lightning.
        let flash = SKSpriteNode(color: UIColor(red: 0.85, green: 0.88, blue: 1.0, alpha: 1),
                                 size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.alpha = 0
        flash.zPosition = -80
        flash.run(.repeatForever(.sequence([
            .wait(forDuration: 8, withRange: 8),
            .fadeAlpha(to: 0.10, duration: 0.05),
            .fadeAlpha(to: 0.02, duration: 0.08),
            .fadeAlpha(to: 0.08, duration: 0.05),
            .fadeAlpha(to: 0, duration: 0.3),
        ])))
        node.addChild(flash)
        return node
    }

    /// Rooftop signature: a downpipe hugging the right edge.
    static func downpipe(sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        let x = sceneSize.width - 14
        let pipe = SKShapeNode(rect: CGRect(x: x - 5, y: 0, width: 10, height: sceneSize.height),
                               cornerRadius: 4)
        pipe.fillColor = UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 0.9)
        pipe.strokeColor = UIColor(red: 0.4, green: 0.42, blue: 0.5, alpha: 0.5)
        pipe.lineWidth = 1
        node.addChild(pipe)
        for fy in stride(from: sceneSize.height * 0.15, to: sceneSize.height,
                         by: sceneSize.height * 0.3) {
            let bracket = SKShapeNode(rectOf: CGSize(width: 16, height: 5), cornerRadius: 2)
            bracket.fillColor = UIColor(red: 0.28, green: 0.30, blue: 0.38, alpha: 0.9)
            bracket.strokeColor = .clear
            bracket.position = CGPoint(x: x, y: fy)
            node.addChild(bracket)
        }
        node.zPosition = -60
        return node
    }

    // MARK: - Diorama: greenhouse (mist)

    static func greenhouseBackdrop(size: CGSize) -> SKNode {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.10, green: 0.15, blue: 0.14, alpha: 1).cgColor,
                                           UIColor(red: 0.05, green: 0.09, blue: 0.08, alpha: 1).cgColor,
                                           UIColor(red: 0.03, green: 0.05, blue: 0.045, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 0.55, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Glass pane grid, catching faint light.
            c.setStrokeColor(UIColor(red: 0.7, green: 0.85, blue: 0.8, alpha: 0.07).cgColor)
            c.setLineWidth(2.5)
            var gx: CGFloat = size.width * 0.12
            while gx < size.width {
                c.move(to: CGPoint(x: gx, y: 0)); c.addLine(to: CGPoint(x: gx, y: size.height))
                gx += size.width * 0.22
            }
            var gy: CGFloat = size.height * 0.12
            while gy < size.height {
                c.move(to: CGPoint(x: 0, y: gy)); c.addLine(to: CGPoint(x: size.width, y: gy))
                gy += size.height * 0.16
            }
            c.strokePath()
            // Big leaf silhouettes in the bottom corners.
            for (side, flip) in [(0.0, 1.0), (Double(size.width), -1.0)] {
                c.setFillColor(UIColor(red: 0.05, green: 0.12, blue: 0.07, alpha: 0.85).cgColor)
                for i in 0..<3 {
                    let a = CGFloat(i) * 0.5 + 0.3
                    let len = size.width * (0.24 - 0.05 * CGFloat(i))
                    let base = CGPoint(x: side, y: Double(size.height) + 6)
                    let tip = CGPoint(x: base.x + CGFloat(flip) * cos(a) * len,
                                      y: base.y - sin(a) * len * 1.6)
                    let mid1 = CGPoint(x: base.x + CGFloat(flip) * cos(a - 0.35) * len * 0.6,
                                       y: base.y - sin(a - 0.35) * len * 0.9)
                    let mid2 = CGPoint(x: base.x + CGFloat(flip) * cos(a + 0.35) * len * 0.6,
                                       y: base.y - sin(a + 0.35) * len * 0.9)
                    c.move(to: base)
                    c.addQuadCurve(to: tip, control: mid1)
                    c.addQuadCurve(to: base, control: mid2)
                    c.fillPath()
                }
            }
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        sprite.size = size
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = -100
        return sprite
    }

    /// Greenhouse signature: hanging vines swaying from the top corners.
    static func vines(sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        for (x, dir) in [(sceneSize.width * 0.08, 1.0), (sceneSize.width * 0.92, -1.0)] {
            let vine = SKNode()
            vine.position = CGPoint(x: x, y: sceneSize.height)
            let stem = CGMutablePath()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: dir * 14, y: -130),
                              control: CGPoint(x: dir * -10, y: -70))
            let line = SKShapeNode(path: stem)
            line.strokeColor = UIColor(red: 0.14, green: 0.30, blue: 0.18, alpha: 0.9)
            line.lineWidth = 3
            line.lineCap = .round
            vine.addChild(line)
            for i in 1...4 {
                let t = CGFloat(i) / 4.5
                let leaf = SKShapeNode(ellipseOf: CGSize(width: 22, height: 10))
                leaf.fillColor = UIColor(red: 0.10, green: 0.26, blue: 0.14, alpha: 0.95)
                leaf.strokeColor = .clear
                leaf.position = CGPoint(x: dir * (8 * t - 6 * sin(t * 5)),
                                        y: -130 * t)
                leaf.zRotation = CGFloat(dir) * (0.5 - 0.2 * t)
                vine.addChild(leaf)
            }
            vine.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.05 * dir, duration: 2.6),
                .rotate(toAngle: -0.03 * dir, duration: 2.6),
            ])))
            node.addChild(vine)
        }
        node.zPosition = -60
        return node
    }

    // MARK: - Themed slab textures

    static func frostSteelTexture(size: CGSize) -> SKTexture {
        slabLike(size: size,
                 top: UIColor(red: 0.44, green: 0.52, blue: 0.62, alpha: 1),
                 bottom: UIColor(red: 0.24, green: 0.30, blue: 0.40, alpha: 1),
                 edge: UIColor.white.withAlphaComponent(0.55))
    }

    static func ironTexture(size: CGSize) -> SKTexture {
        slabLike(size: size,
                 top: UIColor(red: 0.32, green: 0.27, blue: 0.24, alpha: 1),
                 bottom: UIColor(red: 0.17, green: 0.14, blue: 0.125, alpha: 1),
                 edge: UIColor(red: 0.95, green: 0.65, blue: 0.38, alpha: 0.4))
    }

    static func slateShingleTexture(size: CGSize) -> SKTexture {
        slabLike(size: size,
                 top: UIColor(red: 0.30, green: 0.32, blue: 0.40, alpha: 1),
                 bottom: UIColor(red: 0.15, green: 0.17, blue: 0.24, alpha: 1),
                 edge: UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 0.35))
    }

    static func mossWoodTexture(size: CGSize) -> SKTexture {
        slabLike(size: size,
                 top: UIColor(red: 0.22, green: 0.30, blue: 0.18, alpha: 1),
                 bottom: UIColor(red: 0.19, green: 0.13, blue: 0.08, alpha: 1),
                 edge: UIColor(red: 0.45, green: 0.70, blue: 0.40, alpha: 0.45))
    }

    /// Shared slab painter: vertical gradient, crisp lit top edge, hairline.
    private static func slabLike(size: CGSize, top: UIColor, bottom: UIColor,
                                 edge: UIColor) -> SKTexture {
        let sz = CGSize(width: max(size.width, 6), height: max(size.height, 6))
        let renderer = UIGraphicsImageRenderer(size: sz)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let r = CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: r, cornerRadius: min(4, min(r.width, r.height) / 2))
            c.addPath(path.cgPath)
            c.clip()
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [top.cgColor, bottom.cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: sz.height), options: [])
            edge.setFill()
            c.fill(CGRect(x: 1.5, y: 0.5, width: sz.width - 3, height: 1.5))
            UIColor.white.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        return SKTexture(image: img)
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
