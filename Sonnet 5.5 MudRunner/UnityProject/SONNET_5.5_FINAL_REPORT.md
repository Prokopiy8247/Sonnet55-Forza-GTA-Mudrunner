# SONNET 5.5 FINAL REPORT — "Mire & Iron" (Unity 6 MudRunner-style mud physics game)

Original off-road simulation built autonomously by Claude Sonnet 5.5 in the existing Unity 6000.6.0f1 / URP 17.6 project, with every 3D asset authored through the verified Blender MCP (localhost:9891).
Primary focus, as required: **the physics of mud and of suspension/wheels**; the player reads the terrain and picks a route so the vehicle does not get stuck.

## 1. What was built (summary)
* **Mud physics (project-owned).** Static smooth ground + a persistent virtual-sinkage `MudField` (0.25 m cells, toroidal 256 m window, sparse tile store); reduced Bekker–Wong–Janosi tyre–soil model per wheel (sinkage from load/width/diameter/softness, shear thrust vs slip, compaction + bulldozing resistance, spin-digging, berms, churn, compaction); wetness/rain softening; hidden extra depth; belly/body contact on the deformed surface.
* **Suspension/wheels.** Own wheel-circle solver against the deformed surface and physics props (no `WheelCollider`), spring/damper/bump stop/anti-roll, solid-axle style articulation, impulse-limited tyre forces; visible spring/shock/link/axle parts that follow the physics.
* **Drivetrain.** Torque curve, stall, auto + manual gearbox, low/high range, AWD, locked front/rear/centre diffs (implicit solve, stable when wheels spin free), fuel.
* **Recovery/water/cargo.** Winch with anchors, water buoyancy/current/fording/engine flooding, trailer with hitch joint and log/barrel/crate cargo.
* **Vehicles (Blender-authored, data-driven).** Pathfinder 4×4 scout (2.0 t), Bruiser utility truck (4.2 t, winch), Mammoth 6×6 hauler (9.0 t), timber trailer.
* **World.** Procedural 2 km map with the 1.5 km wilderness (3 routes, river with fords, swamp, bridges, landmarks, hidden traps) and the proving ground; GPU-displaced ground renderer; procedural audio; VFX; HUD/menus/debug menu; objectives; save/load.

## 2. What works (verified) / partial / not done
Full table: `FEATURE_MATRIX.md`. Highlights:
* **Verified by automated tests (final run `Logs/cli/final1.xml`): 114 PlayMode tests, 113 passed, 0 failed, 1 skipped** (a GPU-only capture test). Includes the 21-check in-game physics suite, 25 world tests, 48 audio tests, UI tests, Game-scene smoke tests (all three vehicles drive).
* **PARTIAL / unverified:** UI/HUD/debug-menu visuals were never screenshot-reviewed; VFX dust/water spray/flooded-engine not seen on screen; Blender props exist but the world still instances procedural stand-in meshes; no Blender buildings/bridges/signs; no damage model, vehicle-dirt shader, tow-strap mode; save/load has no round-trip test; audio not listened to.

## 3. Controls (keyboard + mouse; basic gamepad)
`W/S` throttle / brake-reverse · `A/D` steer · `Space` handbrake · `LShift/LCtrl` shift up/down (manual) · `M` auto/manual · `R` low/high range · `T` AWD · `F` front diff lock · `G` rear diff lock(s) · `V` centre lock · `I` ignition · `Z` winch hook/release · `Q/E` winch out/in · `C` camera (chase, cockpit, wheel close-up, top) · `[ ]` select wheel · `Tab` map · `H` help · `L` headlights · `Backspace` recover (costs fuel + time) · `Enter` garage · `Esc` pause · `` ` ``/`F1` debug menu · `F2` physics overlay · `F3` FPS · `F5/F9` quick save/load · `F10` hide HUD.

## 4. Vehicles
| | Pathfinder scout | Bruiser utility | Mammoth hauler | Timber trailer |
|---|---|---|---|---|
| mass | 2.0 t | 4.2 t | 9.0 t | 1.5 t (+2.9 t logs) |
| drive / tyres (R×w) | 4×4, 0.40×0.235 all-terrain | 4×4, 0.54×0.375 mud-terrain | 6×6, 0.76×0.60 flotation | 0.54×0.375 |
| engine | 255 Nm, 5-speed + low | 700 Nm, 5-speed + low | 1900 Nm, 6-speed + low | – |
| winch | – | 45 kN / 30 m | 70 kN / 35 m | – |
| rated fording | 1.66 m | 1.72 m | 2.58 m | – |
Models: scout 61k triangles (high LOD, validated in Blender); utility, hauler and trailer built to the same standard; all with LOD1/LOD2, collision proxies and spring/shock/link/axle parts on mount markers.

## 5. Map and routes (generated, seed 20260611)
Wilderness base camp (SW) → cabin on the swamp island (NE): **north road 2544 m** (firm gravel, max 9.8°, causeway through the swamp edge), **central track 2130 m** (forest ruts, ford F1 0.83 m / 1.3 m/s, climbs to 24°), **swamp shortcut 1874 m** (bog, Widowmaker mud hill ~25°, deep ford, hidden-depth traps up to +0.8 m). Landmarks: logging landing, sawmill, pump station, watchtower, radio mast, old fragile bridge. **Proving ground** east of the ridge: 6 mud pits (shallow → bog), 12/20/28° mud hill, 12–19° side slope, 45 m articulation course, 36 m river ford with 1.5 m/s current, log pile, measuring pad.

## 6. Physics results (`Docs/PHYSICS_SUITE_REPORT.txt`)
* Static sinkage (scout/utility/hauler): shallow mud 0.12/0.14/0.10 m, deep mud 0.26/0.30/0.22 m, bog 0.48/0.63/0.42 m; net thrust margin in deep mud +0.8/+6.1/+15 kN, bog negative for all.
* Crossings: scout stuck in deep mud and bog (any mode); utility crosses deep mud only with diff locks + low range (33 s); hauler crosses deep mud open or locked; nobody crosses bog without the winch.
* Spinning wheels dig deeper and progress less than controlled throttle; locks + low range climb an 18° mud hill where 2WD/open diffs stall; winch recovers a bogged utility (peak 17 kN of 45 kN).
* Water: vehicles pass below their rating and stall/float/get swept away above it. Rock course: all three vehicles complete it without jitter (max angular velocity 1.1 rad/s, tilt ≤ 7°, up to 0.31 m axle articulation).
* Trailer: 2.9 t of logs through shallow mud, 5/5 logs kept, hitch angle 1°.
* **Performance:** vehicle physics **0.74 ms per fixed step for 4 vehicles** (≈0.19 ms/vehicle at 100 Hz); ground renderer: 0 B GC/frame, LOD sweep 0.3 ms for 4096 chunks, ≈1.1–1.8 ms whole-frame CPU in the capture harness; wilderness generation 3.4–4.4 s. Target 60 FPS has not been profiled in a standalone player build.

## 7. Known bugs / limitations
See `DEVELOPMENT.md` §11. Notably: unreviewed UI screenshots, procedural stand-in props in the world, unconfirmed SRP-Batcher compatibility of the ground shader, soil numbers are tuned gameplay values loosely based on published terramechanics ranges (not measurements), shared-Unity-project queue made iteration slow (documented in §9 of DEVELOPMENT.md).

## 8. Repository / how to run
`Docs/` contracts (ART/RENDER/WORLD/UI/VFX specs), `RESEARCH_NOTES.md` (539 lines, adopt/adapt/skip), `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, screenshots in `Docs/screenshots/`. Open `Assets/Scenes/Game.unity` and press Play; CLI: `Tools/ub.sh`, `Tools/rt.sh`, `python -I Tools/qc.py`. Git milestones are in `git log`.

## Claude Sonnet 5.5 Unity MudRunner Session Metrics

```text
Project: Unity 6 MudRunner-style off-road mud physics game
Run/session identifier: run-20261016-184652 / session 3bbf66bb-50d0-4331-97ea-9e4f6f39f0b8
Working-directory full path: W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner
Start timestamp and timezone: 2026-10-16 18:46:52 +0200 (CEST, UTC+2)  [start_time.txt]
End timestamp and timezone: 2026-10-17 05:39:54 +0200 (CEST, UTC+2)  [end_time.txt]
Elapsed wall-clock time (HH:MM:SS): 10:53:02 including the pause below; 09:38:42 excluding it
Elapsed minutes: 653.0 total; 578.7 excluding the pause
Known pauses / resumed segments: one pause of 01:14:20 (23:47:13 -> 01:01:33) while the account usage limit was exhausted
  (all background workers failed with "session limit" and were resumed after the reset). Resumed once; start time unchanged.

Requested model: Claude Sonnet 5.5
Actual model identifier(s): claude-sonnet-5-5 for the main session and for every subagent/workflow agent
  (two zero-token "<synthetic>" error records are ignored)
Input tokens (state whether uncached or inclusive): 5,194 uncached (main 536 + subagents 4,658)
Cache-read tokens: 941,472,352 (main 163,718,804 + subagents 777,753,548)
Cache-write tokens: 45,533,636 (main 1,607,062 at the 1-hour tier + subagents 43,926,574 at the 5-minute tier)
Output tokens: 3,260,102 (main 611,670 + subagents 2,648,432)
Thinking/reasoning tokens (included / separate / unavailable): 1,559,426 reported inside the output tokens (not added again)
Deduplicated total tokens: 990,271,284 (uncached input + cache read + cache write + output; de-duplicated by message id + request id)
Usage source and observation cutoff: session transcript JSONL and subagent/workflow transcripts under
  C:\Users\<user>\.claude\projects\W--YouTube-Claude-Sonnet-5-5-MudRunner-UnitySonnet5-5MudRunner\3bbf66bb-...\ via Tools/usage_report.py;
  last event included 2026-10-17T03:39:05Z (the final report-writing turns after this cutoff are not counted)
Unmeasured work / limitations: tokens consumed after the cutoff; the fixed system prompt/tool schema is counted only through the
  cache-read/-write records the API returned; the 114-test final run and Unity/Blender CLI work consume no model tokens.

Token-only API-equivalent cost (USD): $243.01 (main session $28.92 + subagents $214.09)
Official pricing source, verification date and tier: https://platform.claude.com/docs/en/about-claude/pricing, verified 2026-10-16,
  standard API tier, Claude Sonnet 5.5 (input $2, output $10, 5-minute cache write $2.50, 1-hour cache write $4, cache read $0.10 per MTok)
Rates and formula used: cost = (uncached_in x 2 + cache_read x 0.10 + cache_write_5m x 2.50 + cache_write_1h x 4 + output x 10) / 1,000,000
  = 5,194x2 + 941,472,352x0.10 + 43,926,574x2.50 + 1,607,062x4 + 3,260,102x10 = $0.01 + $94.15 + $109.82 + $6.43 + $32.60
Measured / estimated / unavailable, with reasons: MEASURED (token counts are the API-returned usage records; cost computed from them);
  not a subscription charge. Excludes tokens after the observation cutoff.

Blender MCP server/tool namespace actually used: mcp__blender-mudrunner-unity__* (uvx mcp-for-blender --port 9891)
Blender host: localhost
Blender port: 9891
Blender master file: UnitySonnet5.5Mudrunner.blend
Verified full path of master file: W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner\UnitySonnet5.5Mudrunner.blend
Approximate number of major Blender assets created: 21 (3 vehicles, 1 trailer, 17 props: 4 cargo/anchor items, 3 spruce, birch, dead tree, bush, reeds, stump, 4 rocks)
```
