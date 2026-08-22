# Drip Drop Dont Stop — tilt-physics prototype

A water droplet lives in a miniature diorama. **Tilt the phone and the whole
world tilts** — gravity is yours. Guide the droplet to the glowing basin.

Design rule carried over from the abandoned Maestro prototype: no discrete
motion gestures. Tilt is *continuous* with instant visual feedback (nothing to
detect, nothing to misfire), and the other sensors only ever *help*:

- **Breath** — blow into the mic and the droplet lifts on the updraft
  (touch-and-hold anywhere is the equivalent fallback, and works in the simulator).
- **Cold** — as ice, the droplet slides nearly frictionless and can cross
  grates that swallow water. Freeze with the ❄ button, or by darkening the
  room: with auto-brightness enabled, killing the lights (or covering the
  light sensor) drags screen brightness down and the game notices. iOS has no
  public ambient-light API, so brightness is the proxy — button is the
  reliable path, darkness is the magic path.
- **Haptics** — wall impacts thump proportionally to speed; freezing clicks.

## Run it

Open `DripDropDontStop.swiftpm` in Xcode, select your iPhone, ⌘R. It will ask for
microphone access (that's the blow mechanic; decline and touch-and-hold
still works).

**Simulator test harness**: launch arguments `-autostart N` (jump straight
into level N, no tap needed) and `-ice` (freeze ~1s after the level loads —
delayed because didMove reloads the level, which resets to water). E.g.
`xcrun simctl launch <sim> com.dgperkins.dripdropdontstop -autostart 10 -ice`
then `simctl io <sim> screenshot`. No effect on normal launches.

## The four levels (one mechanic each)

1. **The Descent** — pure tilt: zigzag down shelves into the basin.
2. **Updraft** — blow (or hold a finger down) to lift over the center wall.
3. **Cold Crossing** — roll off the shelf, freeze, slide across the grate.
4. **Leap of Frost** — freeze *before* the ramp: only ice carries enough
   speed off the end to fly the pit and strike the wall above the ledge.
   Water splatters at speed (lower velocity cap) and arcs down into the drain.
5. **Aqueduct** — the floor is all drain. Draw on the glass with a finger:
   the stroke becomes a channel the droplet rides (full tilt control returns
   while touching it). Channels are rationed — ink per stroke, two at a
   time — and evaporate after ~6 seconds.
6. **Icefall** (carve + freeze) — mirrored flow (right→left), all-drain
   floor, 300 pts of ink, and a hanging icicle band: carve the one right
   slide *under* the icicles and freeze; water off the same slide falls short.
7. **The Chimney** (breath + tilt) — serpentine blow-climb with shelves as
   rest stops; grate patches on the landings punish careless water touchdowns.
   No carving here.
8. **Boost Slide** (freeze + breath) — skate a grate floor as ice, puff over
   a bump, puff again across a drain pit — under a hanging icicle field that
   kills anyone who tries to fly over instead. No carving.

9. **Switchback** (routing) — three storeys: freeze early, work right across
   a grated shelf, drop, work LEFT over a shelf pit (puff mid-slide), drop
   again and skate the grate floor home to the corner basin.
10. **Meltpoint** (phase timing, the finale) — freeze mid-fall for the grate
    floor, build ice speed, puff the pit — then MELT in mid-air: the water
    speed cap + drag drop you short of the far drain, into the basin. Stay
    ice and you overfly; melting is the air-brake.

11. **Rising Water** (movers intro) — an elevator platform sinks flush with
    the floor; board it, ride up, roll off onto the ledge. The grate floor
    beyond it punishes overshooting.
12. **Cold Storage** (movers + phase) — freeze mid-fall onto slatted shelves,
    ride the lift DOWN, and clear a gap over the drain on the way off.
13. **The Long Pour** (capstone) — carve a catch-slide during the opening
    fall (260 ink), freeze on the perch, skate the grates, puff the pit,
    then ride the lift and step off at the apex onto the goal ledge.

**v1.1 adds STEAM** — a third phase (a button, like Freeze; tapping it from
ice sublimates directly). Vapor rises fast on its own buoyancy, drifts with
reduced tilt authority, ignores floor drains and grates, and auto-condenses
back to water after 2.8 s, followed by a 0.7 s recharge before the next
vaporize (the button dims). It cannot enter the basin (liquid only),
blowing does nothing to it, and icicles condense it dead — which is what
keeps the existing no-fly ceilings honest.
Device-playtest lesson: steam and blow originally blurred into the same
"float up" feel. They're separated by rhythm now — blow is the hover jet
(slow, precise, continuous, vulnerable), steam is the committed leap
(fast, hazard-immune, short fuse, recharge). The cooldown is the load-
bearing part: without it, tap-spam re-created a hover. Steam is per-level gated
(`Level.steamAllowed`, same precedent as ink): levels 1–13 never offer it,
so their tuning is untouched. Dying as steam respawns as water; dying as
ice still keeps ice (Switchback relies on that).

14. **Vapor** (steam intro) — rise over the divider, condense, roll home.
15. **Stepping Stones** — the floor drains everything; vapor-hop between
    three stones on the condensation clock.
16. **Cold Front** — icicle bands with alternating gaps and a mid-way
    perch. Teaches that icicles kill vapor.
17. **Boiler Room** — freeze to land on a grate floor, skate right, then
    sublime ice→steam and condense on the high ledge.
18. **Cloudburst** (capstone) — drain floor, icicle ceiling, 300 ink:
    carve a catch-slide, steam between perches, condense onto the goal
    shelf.

**Movers** (`Level.movers`) are oscillating platforms (ease-in-out cycle).
Vertical elevators only — SpriteKit static bodies don't carry passengers
horizontally, so horizontal ferries are unreliable by construction. Design
note: a platform that sinks flush into a grate floor does NOT protect a
water rider — zone checks are geometric — so keep lethal floor zones away
from the boarding column.

Touch does two things: a **stationary hold** is the updraft (mic fallback);
a **moving finger** carves. The 18 pt movement threshold disambiguates.

**Menu & records**: the app opens on a level-select screen — any level is
playable directly, each row shows its par and best banked pot. Bests persist
in `UserDefaults` (`dripdrop.best.<i>`), as does the best full run
(`dripdrop.bestRun`) — only runs started from level 1 count toward it, so
cherry-picking late levels can't beat an honest run. The grid button in the
game HUD returns to the menu.

**Countdown**: every level opens on READY → STEADY → GO! (1.6 s on READY for
reading, 0.9 s on STEADY). The level's hint is shown as a card under the
countdown — the hints are written as imperative instructions (TILT / BLOW /
FREEZE / DRAW) so first-timers know the verb before play starts.
The droplet holds at spawn and the score clock waits; play begins on GO.
Freezing or pre-drawing channels during the countdown is allowed — that's
strategy, not cheating.

**Scoring**: each level has a 1000-point pot that drains linearly from the
moment the level starts, reaching the 50-point floor at 2× the level's par
time (`Level.par` — this is how long levels stay fair against short ones).
Pars were tightened ~20% across the board after TestFlight 1 (difficulty-up
pass); rebalance against real runs, not the old values.
Shown live in the HUD: cyan above 500, orange below. Reaching the basin banks
the pot into the run total. Deaths aren't charged directly; they cost time.
Every level starts as water.

**Ink is per-level** (`Level.inkBudget`, 0 = no carving; a pencil icon in the
HUD shows availability). Levels 1–4 have zero ink so carving can't skeleton-key
the verb they each teach; Aqueduct is generous (420); Icefall is rationed (300);
7–8 are carve-free. Playtest lesson: an unlimited draw-anything tool
retroactively trivializes every level.

## Physics rules (learned by playtest)

- **"Up" belongs to breath.** The downward tilt component is floored, so
  flipping the phone can't invert gravity (discovered as an exploit).
- **The air is ballistic.** Full tilt authority exists only while touching a
  surface; airborne the droplet falls at standard weight with faint
  air-steer. Without this, tilt is a mid-air thruster and any gap can be
  flown by either phase — momentum jumps only mean something under this rule.
- **Water splatters, ice doesn't.** Water's speed is capped (380 pt/s), ice's
  isn't (1400 pt/s). Ice = fast but slippery, water = slow but grippy.
- Zone effects (goal/drain/grate) are plain per-frame geometry checks, not
  physics-contact sensors — sensor contacts silently missed for a ball
  rolling along the scene edge.

## Tuning knobs (top of `GameScene.swift`)

| Knob | Value | Feel |
|---|---|---|
| `gravityStrength` | 28 | How hard full tilt pulls. Higher = twitchier. |
| `liftStrength` | 90 | Blow updraft strength (mass-relative). |
| Water material | friction .25, damping .4, restitution .3 | Rolls heavy, settles. |
| Ice material | friction .02, damping .05, restitution .08 | Skates. |

Blow mapping (RMS 0.05–0.30 → 0–1) lives in `Sensors.swift`.

**Haptics**: discrete haptics (wall bumps scaled by speed, freeze click,
carve tick, countdown ticks, goal/death buzzes) PLUS a continuous rolling
texture via CoreHaptics — soft/watery for water, tight/gritty for ice,
intensity from speed, silent while airborne. Gotcha that bit us: iOS mutes
ALL haptics while the app records audio unless
`setAllowHapticsAndSystemSoundsDuringRecording(true)` is set — the mic for
the blow mechanic was silently suppressing every haptic until that flag.

**Sound & juice**: nine procedurally synthesized WAVs live in
`Sources/Resources/` (generated by a Python script — no licensed assets):
water plink / ice tap on impacts (speed-gated, matching the haptic), freeze
shimmer, melt bloop, goal chime, drain gurgle on death, countdown ticks and a
GO chord, and a carve scritch.

**Visuals (post-TestFlight-1 polish pass)**: the droplet is drawn by a
metaball fragment shader (`Liquid.swift`) — main blob + a trail of history
blobs — so it stretches into a teardrop in flight, drips behind itself,
wobbles like jelly on impacts, puddles when it settles, and glows when
blown; as ice the same shader hardens into a pale faceted crystal with
twinkling glints. The physics circle is untouched — presentation only.
The water shading does real droplet optics: a surface normal derived from
the analytic field gradient drives REFRACTION of the backdrop (SKShaders
can't sample the framebuffer, so the known bg gradient is recomputed
per-fragment, with chromatic dispersion), a thin bright rim, one hard
specular glint, and a fading contact shadow when the drop settles.
Look lesson (two screenshot rounds): broad glows/caustics read as plasma,
not liquid — a droplet on a dark ground is a dark transparent body + thin
bright rim + small hard glint, nothing more.
GOTCHA: SpriteKit's GLSL→Metal translation cannot handle a bare `return`
after writing gl_FragColor (it emits a double return and the shader dies at
runtime, rendering an opaque white quad) — no early-outs in SKShader source.
Environment art lives in `Decor.swift`: glassy slate slabs with shadows
(movers get a pulsing cyan running light), a glowing goal pool with ripples
and rising bubbles, floor drains as ember-lit pits, elevated drains as
hanging icicle teeth, cyan machined grates, a caustic-shimmer shader +
vignette + drifting motes on the backdrop, a pulsing spawn ring during the
countdown, water spray on hard impacts, and a small camera shake on big
hits and deaths.

## TestFlight

The package is upload-ready: real AppIcon asset (`Sources/Assets.xcassets`),
displayVersion 1.0, all-original audio (no licensing issues). To ship a build:

1. Open `DripDropDontStop.swiftpm` in Xcode; destination **Any iOS Device (arm64)**.
2. Product → **Archive**, then in Organizer: **Distribute App → App Store
   Connect → Upload** (automatic signing).
3. First time only: create the app record at appstoreconnect.apple.com →
   My Apps → **+** → New App (iOS, bundle ID `com.dgperkins.dripdropdontstop`,
   the listing name "Drip Drop Dont Stop" should be unique as-is (add "!" if contested)). If you'd rather ship
   under a cleaner bundle ID, change it in Xcode **before** the first upload;
   the ASC app record binds to it permanently.
4. When the build finishes processing (~15 min), TestFlight tab → answer the
   export-compliance question (the app uses no networking or custom
   encryption) → add internal testers (instant) or an external group
   (one-time beta review, ~a day).
5. Bump `bundleVersion` for each subsequent upload.

## Obvious next steps if it feels good

- Finger-carved channels (draw a line, it becomes a temporary wall) — the
  touch mechanic that makes it a *puzzle* game rather than a dexterity game.
- Steam as a third phase (warmth/holding the phone? or just a pickup).
- Metaball rendering for a properly gooey droplet (SKEffectNode or a shader).
- Real level art direction: dioramas — kitchen counters, gutters, greenhouses.
