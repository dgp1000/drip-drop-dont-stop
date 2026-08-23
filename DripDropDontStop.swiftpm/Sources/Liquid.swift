// Metaball water rendering: the droplet is drawn by a fragment shader as a
// blobby field — the main ball plus a short trail of history blobs — so it
// stretches along its motion, drips behind itself, wobbles on impact, and
// merges back together like actual liquid. The physics body stays the same
// plain circle; this file is presentation only.
//
// Photoreal pass: the shader derives a 3D surface normal from the analytic
// gradient of the metaball field and does real droplet optics with it —
// REFRACTION of the backdrop (SKShaders can't sample the framebuffer, but
// the backdrop is a known procedural gradient, so the bent background is
// recomputed per-fragment, with slight chromatic dispersion), fresnel rim
// reflection, blinn-phong speculars from two lights, and depth-tinted
// absorption. A soft contact shadow fades in when the drop settles.
//
// As ice the same field hardens: faceted pale crystal, sparkle glints.
//
// GOTCHA (cost a debugging round): SpriteKit's GLSL→Metal translation
// cannot handle a bare `return` after writing gl_FragColor — the shader
// dies at runtime and renders an opaque white quad. No early-outs.

import SpriteKit
import UIKit
import simd

final class DropletVisual: SKNode {
    /// Side of the square shader canvas, in points. Must match QUAD in the
    /// shader source. Trail offsets are in canvas UV units (1.0 = quad pts).
    static let quad: CGFloat = 170
    private static let trailCount = 5
    private static let mainRadiusUV: Float = Float(15.0 / DropletVisual.quad)

    private let sprite: SKSpriteNode
    private let contactShadow: SKSpriteNode
    /// Condensation warning: droplets rain off the cloud as the vapor
    /// clock runs out — the player's cue that the pop is coming.
    private let drips: SKEmitterNode
    private let uP: [SKUniform]
    private let uR: [SKUniform]
    private let uStretch = SKUniform(name: "u_stretch", vectorFloat2: vector_float2(0, 0))
    private let uWob = SKUniform(name: "u_wob", float: 0)
    private let uIce = SKUniform(name: "u_ice", float: 0)
    private let uSteam = SKUniform(name: "u_steam", float: 0)
    private let uRem = SKUniform(name: "u_rem", float: 1)   // vapor time left, 1→0
    private let uLift = SKUniform(name: "u_lift", float: 0)
    private let uGround = SKUniform(name: "u_ground", float: 0)
    private let uWorldY = SKUniform(name: "u_worldY", float: 0)
    private let uSceneH: SKUniform

    private var history: [(p: CGPoint, t: TimeInterval)] = []
    private var wobble: CGFloat = 0
    private var iceMix: CGFloat = 0
    private var steamMix: CGFloat = 0
    private var groundMix: CGFloat = 0

    init(sceneHeight: CGFloat, mood: Mood = .abyss) {
        var ps: [SKUniform] = []
        var rs: [SKUniform] = []
        for i in 0..<Self.trailCount {
            ps.append(SKUniform(name: "u_p\(i + 1)", vectorFloat2: vector_float2(0, 0)))
            rs.append(SKUniform(name: "u_r\(i + 1)", float: 0))
        }
        uP = ps
        uR = rs
        uSceneH = SKUniform(name: "u_sceneH", float: Float(max(sceneHeight, 1)))
        sprite = SKSpriteNode(color: .white, size: CGSize(width: Self.quad, height: Self.quad))
        contactShadow = SKSpriteNode(texture: Decor.shadow)
        drips = SKEmitterNode()
        super.init()

        drips.particleTexture = Decor.softDot
        drips.particleBirthRate = 0
        drips.particleLifetime = 0.6
        drips.particleSpeed = 12
        drips.particleSpeedRange = 10
        drips.emissionAngle = -.pi / 2
        drips.emissionAngleRange = 0.7
        drips.yAcceleration = -650
        drips.particlePositionRange = CGVector(dx: 26, dy: 8)
        drips.particleAlpha = 0.65
        drips.particleAlphaSpeed = -0.9
        drips.particleScale = 0.22
        drips.particleScaleRange = 0.10
        drips.particleColor = UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1)
        drips.particleColorBlendFactor = 1
        drips.zPosition = -0.5
        addChild(drips)

        // The refraction must bend THIS level's backdrop, not a hardcoded
        // one — the mood palette rides in as uniforms.
        let (top, mid, bot) = mood.gradient
        let shader = SKShader(source: Self.source)
        shader.uniforms = [SKUniform(name: "u_r0", float: Self.mainRadiusUV),
                           SKUniform(name: "u_bgTop", vectorFloat3: top),
                           SKUniform(name: "u_bgMid", vectorFloat3: mid),
                           SKUniform(name: "u_bgBot", vectorFloat3: bot),
                           uStretch, uWob, uIce, uSteam, uRem, uLift, uGround,
                           uWorldY, uSceneH] + uP + uR
        sprite.shader = shader

        contactShadow.size = CGSize(width: 42, height: 13)
        contactShadow.position = CGPoint(x: 0, y: -14)
        contactShadow.alpha = 0
        contactShadow.zPosition = -1
        addChild(contactShadow)
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
              phase: Phase, steamRemaining: CGFloat, iceRemaining: CGFloat,
              lift: CGFloat, now: TimeInterval, dt: CGFloat) {
        position = center
        let speed = hypot(velocity.dx, velocity.dy)

        // Phase morphs + wobble decay + grounded settle, all smoothed.
        let clampedDT = min(max(dt, 0), 0.05)
        iceMix += ((phase == .ice ? 1 : 0) - iceMix) * min(1, clampedDT * 9)
        steamMix += ((phase == .steam ? 1 : 0) - steamMix) * min(1, clampedDT * 7)
        wobble *= exp(-clampedDT * 5.5)
        let settle: CGFloat = (grounded && speed < 220 && phase != .steam) ? 1 : 0
        groundMix += (settle - groundMix) * min(1, clampedDT * 7)

        // Trail: recent positions become shrinking satellite blobs. Ice is
        // rigid, so its trail collapses with the phase morph; vapor smears
        // even at drift speeds.
        history.append((center, now))
        history.removeAll { now - $0.t > 0.17 }
        let liquid = max((1 - iceMix) * min(1, max(0, speed - 90) / 240),
                         steamMix * min(1, speed / 180) * 0.8)
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
        // Expiry warning: as a phase clock runs out, the body flickers
        // between its phase look and water — the flash IS the morph-back
        // starting.
        var iceOut = iceMix
        var steamOut = steamMix
        let flicker = 0.60 + 0.40 * CGFloat(sin(now * 17))
        if phase == .ice, iceRemaining < 0.19 { iceOut *= flicker }
        if phase == .steam, steamRemaining < 0.32 { steamOut *= flicker }
        uIce.floatValue = Float(iceOut)
        uSteam.floatValue = Float(steamOut)
        uRem.floatValue = Float(steamRemaining)
        uLift.floatValue = Float(lift)
        uGround.floatValue = Float(groundMix * (1 - iceMix))
        uWorldY.floatValue = Float(center.y)

        contactShadow.alpha = groundMix * 0.42 * (1 - steamMix)

        // Rain intensifies as the condensation clock runs down.
        drips.particleBirthRate = (steamMix > 0.5 && steamRemaining < 0.45)
            ? (0.45 - steamRemaining) * 70 : 0
    }

    // MARK: shader

    private static let source = """
    // Backdrop gradient — must match the stops used by GameScene.bgTexture.
    // t: 0 = scene bottom, 1 = scene top. The mood colors are passed as
    // ARGUMENTS: SpriteKit's GLSL->Metal translation only exposes uniforms
    // inside main(), so helper functions must receive them (a bare uniform
    // reference here fails to compile and renders an opaque white quad).
    vec3 bgColor(float t, vec3 cTop, vec3 cMid, vec3 cBot) {
        vec3 hi = mix(cMid, cTop, clamp((t - 0.45) / 0.55, 0.0, 1.0));
        vec3 lo = mix(cBot, cMid, clamp(t / 0.45, 0.0, 1.0));
        return t > 0.45 ? hi : lo;
    }

    void main() {
        float QUAD = 170.0;
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

        // Metaball field + analytic gradient (for the surface normal).
        float ang = atan(uv.y, uv.x);
        float wr = 1.0 + u_wob * 0.20 * sin(ang * 3.0 + u_time * 26.0)
                       + u_wob * 0.09 * sin(ang * 5.0 - u_time * 31.0)
                       // vapor billows slowly with a finer curling detail
                       + u_steam * (0.10 * sin(ang * 2.0 + u_time * 3.1)
                                  + 0.07 * sin(ang * 4.0 - u_time * 2.3)
                                  + 0.045 * sin(ang * 7.0 + u_time * 5.3));
        float r0 = u_r0 * wr;
        float d2 = max(dot(uv, uv), 0.00001);
        float field = r0 * r0 / d2;
        vec2 grad = r0 * r0 * -2.0 * uv / (d2 * d2);
        vec2 q;
        q = uv - u_p1; d2 = max(dot(q, q), 0.00001);
        field += u_r1 * u_r1 / d2; grad += u_r1 * u_r1 * -2.0 * q / (d2 * d2);
        q = uv - u_p2; d2 = max(dot(q, q), 0.00001);
        field += u_r2 * u_r2 / d2; grad += u_r2 * u_r2 * -2.0 * q / (d2 * d2);
        q = uv - u_p3; d2 = max(dot(q, q), 0.00001);
        field += u_r3 * u_r3 / d2; grad += u_r3 * u_r3 * -2.0 * q / (d2 * d2);
        q = uv - u_p4; d2 = max(dot(q, q), 0.00001);
        field += u_r4 * u_r4 / d2; grad += u_r4 * u_r4 * -2.0 * q / (d2 * d2);
        q = uv - u_p5; d2 = max(dot(q, q), 0.00001);
        field += u_r5 * u_r5 / d2; grad += u_r5 * u_r5 * -2.0 * q / (d2 * d2);

        // Crisp meniscus edge — fuzz reads as glow, not liquid. Vapor is the
        // exception: its edge is deliberately soft and wide.
        float lo = mix(mix(0.94, 0.97, u_ice), 0.45, u_steam);
        float hi = mix(mix(1.10, 1.06, u_ice), 1.55, u_steam);
        float edge = smoothstep(lo, hi, field);

        // Surface normal of the droplet dome. The field gradient gives the
        // in-plane slope; blend to flat (z=1) toward the blob center where
        // the dome levels off. 0.05 sets edge steepness — tuned by eye.
        vec2 slope = -grad * 0.12;
        float dome = clamp((field - lo) / 1.6, 0.0, 1.0);
        slope *= (1.0 - dome * 0.85);
        vec3 n = normalize(vec3(slope, 1.0));
        float thickness = sqrt(dome);           // 0 at rim, 1 at center

        // --- Water: how a droplet actually photographs on a dark ground —
        // a dark transparent body (the refracted backdrop), a THIN bright
        // fresnel rim, and one small hard specular glint. No broad glows:
        // that reads as plasma, not liquid (learned by screenshot).
        vec3 V = vec3(0.0, 0.0, 1.0);
        vec3 L = normalize(vec3(-0.45, 0.60, 0.66));
        float fres = pow(1.0 - max(n.z, 0.0), 3.0);

        // Refraction: bend the background through the lens, stronger at the
        // rim, with mild chromatic dispersion. World-space, vertical bg.
        float bendPts = 60.0 * (0.35 + fres);
        float wy = u_worldY + uv.y * QUAD;
        float tR = clamp((wy - n.y * bendPts * 1.15) / u_sceneH, 0.0, 1.0);
        float tG = clamp((wy - n.y * bendPts)        / u_sceneH, 0.0, 1.0);
        float tB = clamp((wy - n.y * bendPts * 0.85) / u_sceneH, 0.0, 1.0);
        vec3 refr = vec3(bgColor(tR, u_bgTop, u_bgMid, u_bgBot).r,
                         bgColor(tG, u_bgTop, u_bgMid, u_bgBot).g,
                         bgColor(tB, u_bgTop, u_bgMid, u_bgBot).b);

        // Transparent body: refracted bg, cool-tinted and glassy-darkened
        // with thickness.
        vec3 water = refr * mix(vec3(1.0), vec3(0.60, 0.78, 1.05), thickness * 0.8);
        water *= 1.0 - 0.15 * thickness;
        // Thin bright rim — the signature of a droplet. Banded directly off
        // the field (fresnel alone stays too weak at this dome steepness).
        float rimBand = smoothstep(lo, lo + 0.10, field)
                      * (1.0 - smoothstep(lo + 0.10, lo + 0.40, field));
        water += vec3(0.62, 0.80, 1.0) * (rimBand * 0.85 + fres * 0.35);
        // Hard key glint up-left + dim counter-glint low-right. Fixed in
        // blob space, so they ride the wobble/stretch distortion.
        vec2 hl = uv - vec2(-0.032, 0.038);
        water += vec3(1.35) * exp(-dot(hl, hl) * 2600.0);
        vec2 hl2 = uv - vec2(0.030, -0.030);
        water += vec3(0.45, 0.62, 0.85) * exp(-dot(hl2, hl2) * 3800.0) * 0.55;

        // --- Ice: faceted pale crystal, lit by the same normal ---
        float facet = floor((ang + 3.1416) / 0.9);
        float fh = fract(sin(facet * 17.23) * 43758.55);
        vec3 ice = mix(vec3(0.72, 0.86, 0.99), vec3(0.94, 0.98, 1.0), fh);
        ice *= 0.75 + 0.35 * max(dot(n, L), 0.0);
        vec2 cell = floor((uv + vec2(0.5)) * 52.0);
        float twinkle = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float sparkle = step(0.992, twinkle) * (0.5 + 0.5 * sin(u_time * 6.0 + twinkle * 40.0));
        ice += vec3(sparkle * 0.7);
        vec3 H1 = normalize(L + V);
        ice += vec3(1.0) * pow(max(dot(n, H1), 0.0), 60.0) * 0.8;

        // Steam: a lit puff — no refraction, no glint, just soft scatter,
        // thinning as its condensation clock (u_rem 1→0) runs down.
        float cl = 0.55 + 0.45 * max(dot(n, L), 0.0);
        vec3 cloud = vec3(0.82, 0.86, 0.94) * cl;

        vec3 col = mix(mix(water, ice, u_ice), cloud, u_steam);
        // Water reads photoreal because you *see through it* — near-solid
        // alpha works since the shader paints the refracted backdrop itself.
        float aBody = edge * mix(0.93, 1.0, u_ice);
        float aCloud = edge * (0.28 + 0.34 * u_rem);
        float alpha = mix(aBody, aCloud, u_steam);

        // Blow halo: the sub-threshold field skirt glows when lifting.
        float halo = (smoothstep(0.26, 0.95, field) - edge) * u_lift;
        col += vec3(0.35, 0.85, 1.0) * halo;
        alpha = min(1.0, alpha + halo * 0.65);

        gl_FragColor = vec4(col * alpha, alpha);
    }
    """
}
