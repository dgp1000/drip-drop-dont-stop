// Metaball water rendering: the droplet is drawn by a fragment shader as a
// blobby field — the main ball plus a short trail of history blobs — so it
// stretches along its motion, drips behind itself, wobbles on impact, and
// merges back together like actual liquid. The physics body stays the same
// plain circle; this file is presentation only.
//
// As ice the same shader hardens: the edge sharpens, the body goes pale and
// faceted, the trail vanishes (ice doesn't smear), and sparkle glints appear.

import SpriteKit
import simd

final class DropletVisual: SKNode {
    /// Side of the square shader canvas, in points. Trail offsets are
    /// expressed in canvas UV units (1.0 = quad points).
    static let quad: CGFloat = 170
    private static let trailCount = 5
    private static let mainRadiusUV: Float = Float(15.0 / DropletVisual.quad)

    private let sprite: SKSpriteNode
    private let uP: [SKUniform]
    private let uR: [SKUniform]
    private let uStretch = SKUniform(name: "u_stretch", vectorFloat2: vector_float2(0, 0))
    private let uWob = SKUniform(name: "u_wob", float: 0)
    private let uIce = SKUniform(name: "u_ice", float: 0)
    private let uLift = SKUniform(name: "u_lift", float: 0)
    private let uGround = SKUniform(name: "u_ground", float: 0)

    private var history: [(p: CGPoint, t: TimeInterval)] = []
    private var wobble: CGFloat = 0
    private var iceMix: CGFloat = 0
    private var groundMix: CGFloat = 0

    override init() {
        var ps: [SKUniform] = []
        var rs: [SKUniform] = []
        for i in 0..<Self.trailCount {
            ps.append(SKUniform(name: "u_p\(i + 1)", vectorFloat2: vector_float2(0, 0)))
            rs.append(SKUniform(name: "u_r\(i + 1)", float: 0))
        }
        uP = ps
        uR = rs
        sprite = SKSpriteNode(color: .white, size: CGSize(width: Self.quad, height: Self.quad))
        super.init()

        let shader = SKShader(source: Self.source)
        shader.uniforms = [SKUniform(name: "u_r0", float: Self.mainRadiusUV),
                           uStretch, uWob, uIce, uLift, uGround] + uP + uR
        sprite.shader = shader
        addChild(sprite)
        zPosition = 10
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Call on spawn/teleport so the trail doesn't streak across the level.
    func reset() {
        history.removeAll()
        wobble = 0
        for i in 0..<Self.trailCount { uR[i].floatValue = 0 }
    }

    /// A wall hit (or landing). Strength 0…1 drives the jelly wobble.
    func impact(_ strength: CGFloat) {
        wobble = min(1, wobble + strength)
    }

    /// Sync the visual to the physics ball once per frame (didFinishUpdate).
    func sync(center: CGPoint, velocity: CGVector, grounded: Bool,
              isIce: Bool, lift: CGFloat, now: TimeInterval, dt: CGFloat) {
        position = center
        let speed = hypot(velocity.dx, velocity.dy)

        // Phase morph + wobble decay + grounded settle, all smoothed.
        let clampedDT = min(max(dt, 0), 0.05)
        let target: CGFloat = isIce ? 1 : 0
        iceMix += (target - iceMix) * min(1, clampedDT * 9)
        wobble *= exp(-clampedDT * 5.5)
        let settle: CGFloat = (grounded && speed < 220) ? 1 : 0
        groundMix += (settle - groundMix) * min(1, clampedDT * 7)

        // Trail: recent positions become shrinking satellite blobs. Ice is
        // rigid, so its trail collapses with the phase morph.
        history.append((center, now))
        history.removeAll { now - $0.t > 0.17 }
        let liquid = (1 - iceMix) * min(1, max(0, speed - 90) / 240)
        let samples = history.count
        for i in 0..<Self.trailCount {
            // Oldest history first, spread across the slots.
            let idx = samples > 1 ? (i * (samples - 1)) / Self.trailCount : 0
            let h = history[min(idx, samples - 1)]
            let dx = min(max((h.p.x - center.x) / Self.quad, -0.42), 0.42)
            let dy = min(max((h.p.y - center.y) / Self.quad, -0.42), 0.42)
            uP[i].vectorFloat2Value = vector_float2(Float(dx), Float(dy))
            let age = 1 - CGFloat(i + 1) / CGFloat(Self.trailCount + 1)
            uR[i].floatValue = Self.mainRadiusUV * Float((0.30 + 0.45 * age) * liquid)
        }

        // Velocity stretch direction * amount (water smears, ice barely).
        let s = min(speed / 1200, 0.30) * (1 - iceMix * 0.8)
        if speed > 1 {
            uStretch.vectorFloat2Value = vector_float2(Float(velocity.dx / speed * s),
                                                       Float(velocity.dy / speed * s))
        } else {
            uStretch.vectorFloat2Value = vector_float2(0, 0)
        }
        uWob.floatValue = Float(wobble * (1 - iceMix * 0.85))
        uIce.floatValue = Float(iceMix)
        uLift.floatValue = Float(lift)
        uGround.floatValue = Float(groundMix * (1 - iceMix))
    }

    // MARK: shader

    private static let source = """
    void main() {
        vec2 uv = v_tex_coord - vec2(0.5);

        // Elongate space along the velocity: the blob smears with motion.
        float sl = length(u_stretch);
        if (sl > 0.001) {
            vec2 dir = u_stretch / sl;
            float along = dot(uv, dir);
            vec2 perp = uv - dir * along;
            uv = perp * (1.0 + sl * 0.55) + dir * (along / (1.0 + sl));
        }
        // Resting puddle squash.
        uv.y *= 1.0 + u_ground * 0.22;
        uv.x /= 1.0 + u_ground * 0.12;

        // Metaball field: main blob (wobble-modulated) + trail blobs.
        float ang = atan(uv.y, uv.x);
        float wr = 1.0 + u_wob * 0.20 * sin(ang * 3.0 + u_time * 26.0)
                       + u_wob * 0.09 * sin(ang * 5.0 - u_time * 31.0);
        float r0 = u_r0 * wr;
        float field = r0 * r0 / max(dot(uv, uv), 0.00001);
        vec2 q;
        q = uv - u_p1; field += u_r1 * u_r1 / max(dot(q, q), 0.00001);
        q = uv - u_p2; field += u_r2 * u_r2 / max(dot(q, q), 0.00001);
        q = uv - u_p3; field += u_r3 * u_r3 / max(dot(q, q), 0.00001);
        q = uv - u_p4; field += u_r4 * u_r4 / max(dot(q, q), 0.00001);
        q = uv - u_p5; field += u_r5 * u_r5 / max(dot(q, q), 0.00001);

        // Water has a soft meniscus edge; ice a hard one.
        float lo = mix(0.86, 0.97, u_ice);
        float hi = mix(1.30, 1.06, u_ice);
        float edge = smoothstep(lo, hi, field);
        // (No early-out: SpriteKit's GLSL->Metal translation can't handle a
        // bare `return` after writing gl_FragColor.)

        // Water body: deep blue shaded toward an inner light.
        vec2 lightAt = vec2(-0.030, 0.036);
        float lit = 1.0 - smoothstep(0.0, 0.17, length(uv - lightAt));
        vec3 water = mix(vec3(0.08, 0.32, 0.72), vec3(0.34, 0.68, 1.0), lit * 0.85);
        float rim = (1.0 - smoothstep(1.05, 1.65, field)) * edge;
        water = mix(water, vec3(0.62, 0.88, 1.0), rim * 0.55);

        // Ice body: pale faceted crystal with animated glints.
        float facet = floor((ang + 3.1416) / 0.9);
        float fh = fract(sin(facet * 17.23) * 43758.55);
        vec3 ice = mix(vec3(0.72, 0.86, 0.99), vec3(0.94, 0.98, 1.0), fh);
        vec2 cell = floor((uv + vec2(0.5)) * 52.0);
        float twinkle = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float sparkle = step(0.992, twinkle) * (0.5 + 0.5 * sin(u_time * 6.0 + twinkle * 40.0));
        ice += vec3(sparkle * 0.7);

        vec3 col = mix(water, ice, u_ice);

        // Specular highlight — glassy in both phases.
        float spec = 1.0 - smoothstep(0.0, 0.045, length(uv - lightAt * 1.15));
        col += vec3(spec * 0.85);

        float alpha = edge * mix(0.94, 1.0, u_ice);

        // Blow halo: the sub-threshold field skirt glows when lifting.
        float halo = (smoothstep(0.26, 0.95, field) - edge) * u_lift;
        col += vec3(0.35, 0.85, 1.0) * halo;
        alpha = min(1.0, alpha + halo * 0.65);

        gl_FragColor = vec4(col * alpha, alpha);
    }
    """
}
