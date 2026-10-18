# Pedestrians / NPC population (`Game.sys(&"peds")`)

Owner: Pedestrian agent. Files: `gta/code/npc/{ped_manager,pedestrian,ped_brain,ped_spawner,ped_defs,ped_variants}.gd`, `gta/code/ai/ped_nav.gd`,
tests `gta/tests/ped_test.gd` (+ `ped_shots.gd`, `ped_gpu.gd`, `ped_vis.gd`, `ped_probe.gd`, `ped_smoke.gd`). No shared files are edited.

STATUS (successor: read this first)
* Everything in the brief is implemented, parse-clean (`tools\gd.ps1 check` = VALIDATE OK) and verified by `ped_test.gd` (see the log at the bottom).
* Full suite: `tools\gd.ps1 exec -Script res://gta/tests/ped_test.gd -Seconds 1500 -GameArgs "--no-traffic"` (needs ~20 simulated minutes; the exec runner stops after
  `Seconds*60` frames, so give it plenty; `--no-traffic` keeps the vehicle sections deterministic, with traffic a parked / driving car can interfere). Partial runs: `-GameArgs "--only=boot,variety,walk,crossing,panic,aim,witness,zones,death,vehicle,explosion,driver,sit,pool,perf,ring"`.
* Screenshots: `tools\gd.ps1 shot -Out screenshots\peds\x.png -GameArgs "--exec=res://gta/tests/ped_shots.gd --scene=<street|crowd|lineup|panic|bench|sunbathe|phone|talk|pier> --delay=4 --time=12 --no-traffic"`
  (extra: `--co=x,y,z` camera offset for panic, `--ang/--dist` for bench, `--after=<frames>` for panic). The scenes set `Game.gameplay_camera` to their camera.
* Render cost probe (real renderer): `ped_gpu.gd` via `shot` (draw calls with / without 40 peds, with / without ped shadows).

## What it does
* Pooled `Pedestrian` nodes (CharacterBase subclass, groups `npc`,`pedestrian`,`damageable`, faction civilian, layer `GC.L_NPC`, 3-shape hitbox
  Head/Torso/Legs so `Ballistics.character_zone` resolves head / torso / limb) with a `CharacterRig` dressed from `PedVariants`
  (business / casual / worker / beach / jogger / tourist / elder / taxi / shop) by district.
* `PedBrain` = state machine (idle walk wait cross jaywalk sit talk sunbathe static call flee cower hands_up gawk fight stagger knocked getup
  driving dead) ticked by ONE scheduler in `PedManager._physics_process`: movement every tick, decisions staggered by tier under a ~1.8 ms budget,
  spatial hash (4 m cells) for neighbours / witnesses, no physics queries for avoidance.
* Navigation on `WorldLayout.ped_graph` through `PedNav` (random walk with heading preference, `flee_next` = away from the threat, A* `find_path`,
  soft avoidance of furniture from a circle grid, lane offsets). Crossings obey `WorldLayout.crossing_open` (wait at the curb on red, hurry when the light
  is about to change, occasional jaywalk when no car is near). Smooth turning (6 rad/s, 9 running), accel / decel, personal space 1.15 m.
* Scenes: bench sitters (rig `sit_car` stance lifted to the seat plank, bench claim), talking pairs, phone idle, window shopping, bus-stop waiters,
  joggers, sunbathers lying on a towel on the sand (rig stance `dead` + towel plane), strollers.
* Reactions are data driven by `PedDefs.PERSONALITIES` (timid normal brave tough oblivious elderly): gunshot (loudness = reach x alert), explosion,
  `Events.character_died`, violence against others, vehicles speeding at them (dodge: jump aside), player aiming a firearm (hands up / cower / flee / fight),
  being hit (stagger, then flee or fight back with punches), panic contagion (attenuated per hop), flee along the graph away from the threat, calm down after
  the personality's calm time (8-40 s), bumping into the player (cough / gasp + shove), voices rate limited.
* Witness / phone call per ARCHITECTURE 14.1. Drivers / carjack per 14.3.
* Death => rig ragdoll (RagdollBody keeps <= 8 live), 60 % cash drop (20-120 $) through `CombatSystem.spawn_pickup(&"cash", ...)`, body stays 30 s then
  dithers out (max 10 corpses, oldest fade early). Vehicle impact => damage by speed + knockdown/ragdoll + get up; explosion => ragdoll.

## Population
* Target = `CAP_ACTIVE (60) x density(district at the player, time of day) x Game.settings["ped_density"]`, hard cap 90, `Game.cheats["pedestrians"]` = off switch.
* Spawn ring: graph points 18-120 m from the player, never where the player could see them (frustum with margin + line of sight to feet / hips / head);
  distance bands are weighted towards the player (50 % 0-48 m, 32 % 48-85 m, 18 % 85-120 m). Scene spots (bench seat, sunbather spot) are re-checked.
* Instant fill: at boot and after a teleport > 90 m the area is populated at once (also in view, from 9 m) for 1.6 s (`instant_fill`, `PedDefs.INSTANT_FILL_TIME`),
  then the hidden ring keeps it filled (2 scenes / 0.4 s). Despawn: > 150 m, or > 90 m and out of view, or surplus.
* Tiers: near < 40 m (avoidance + perception at 20 Hz), mid 40-90 m (6 Hz decisions, no avoidance), far > 90 m (despawn candidates).
* Render budget (it matters: 40 peds cost +1266 draw calls before, +548 after): peds farther than `SHADOW_RANGE` (30 m) from the camera cast no shadow, drivers never do,
  nothing is drawn beyond `VIS_END` (112 m, dithered fade). Rig animation LOD from the camera: < 6 m or (in view and < 18 m) full rate, in view < 60 m ~15 Hz,
  otherwise frozen.
* World data fix: `PedNav.fix_heights()` (run at boot by `PedManager.fix_graph_heights()`) corrects graph nodes that carry the sea-floor height under the piers
  (21 dock nodes: peds were walking inside the deck) and marks nodes lying on a stunt ramp (`Ramp*` collider) as no-go for random walks / spawns.

## Public API
### PedManager (`Game.sys(&"peds")`)
| member | meaning |
|---|---|
| `spawn_pedestrian(pos, kind := &"civilian", opts := {}) -> Pedestrian` | kind: `civilian` (look by district) / a look name (`business casual worker beach jogger tourist elder`) / `shop` / `dummy`. opts: `yaw role personality persistent stationary variant node force` |
| `spawn_crowd(center, radius, count, look := &"") -> Array` | ambient strollers regardless of visibility (screenshots / stress tests) |
| `create_driver(vehicle) -> CharacterBase` | seated through `vehicle.enter(driver, 0)`, look by vehicle (taxi driver outfit for `taxi`), null if the rig cannot be built |
| `create_occupant(vehicle, seat := 0, look := &"")` | passengers (taxi fares ...) |
| `get_witnesses(pos, perpetrator := null, radius := 45.0) -> Array` | living civilian peds (incl. drivers) in radius with FOV + line of sight; sorted by distance |
| `notify_event(kind, pos, radius, severity, source := null)` | other modules report a frightening event (crash, fire ...) |
| `get_peds()`, `active_count()`, `get_peds_in_radius(pos, r)`, `find_nearest_ped(pos, max)`, `query_radius(pos, r)` | queries (spatial hash, positions <= 0.1 s old, released peds are skipped) |
| `is_ped_visible(pos)`, `is_visible_to_player(pos, check_los := true)` | would the player see something standing there |
| `release(ped)`, `clear_all(include_persistent := true)`, `set_enabled(on)` | lifecycle (release deactivates first, so leaving a moving car does no damage) |
| `auto_population`, `instant_fill`, `rig_lod_override`, `signal_clock` | test / cut-scene switches |
| signals | `ped_spawned(ped)`, `ped_despawned(ped)`, `ped_killed(ped, killer)` |
| `stats` | dict: spawned despawned killed tick_us think_us move_us thinks voices target visible_rejects pool created |

### Pedestrian
`notify_threat(kind, pos, severity, source := null, direct := false)`, `witness(crime, pos, perpetrator, severity := 1.0) -> bool`,
`on_carjacked(thief)`, `knock_down(impulse, duration := 2.2)`, `knockback(impulse)`, `apply_damage(amount, info)` (damage contract),
`is_calling()`, `has_pending_call()`, `get_eye_position()`, `get_state_name()`, `is_fleeing()`, `is_panicked()`, `is_knocked_down()`,
`show_towel(on, color)`, `set_shadows(on)`, signals `phone_call_started`, `phone_call_ended(reported)`, `panicked(threat_pos)`, `knocked_down`, `got_up`.
Fields: `personality`, `look`, `role`, `panic` (0..1), `tier` (0 near, 1 mid, 2 far), `persistent`, `is_driver`, `brain`, `rig`.

### Events
Consumed: `gunshot`, `explosion`, `character_died`, `character_damaged`, `vehicle_collision`, `vehicle_removed`, `vehicle_destroyed`.
Emitted: `Events.crime_reported(crime, pos, perpetrator)` when a witness call completes (aborted when the ped is hurt / knocked down / dies / despawns).
`post_setup()` sets `CombatSystem.drop_cash_chance[F_CIVILIAN] = 0` (runtime data) because PedManager owns the civilian cash drop.

## Tunables (`PedDefs`)
`CAP_ACTIVE 60`, `CAP_HARD 90`, `RING_MIN 42`, `RING_HIDDEN_MIN 18`, `RING_MAX 120`, `RING_BANDS`, `INSTANT_FILL_TIME 1.6`, `DESPAWN_FAR 150`, `DESPAWN_BEHIND 90`,
`NEAR 40`, `MID 90`, `THINK_NEAR 0.05`, `THINK_MID 0.16`, `TICK_BUDGET_US 1800`, `SHADOW_RANGE 30`, `VIS_END 112`, `MAX_DEAD_BODIES 10`, `BODY_LIFETIME 30`,
`DENSITY` (district x time of day), `PERSONALITIES`, `TURN_RATE`, `ACCEL`, `SEPARATION`. `PedManager.MAX_POOL = 64`.

## Known limits / notes for other agents
* Peds are kinematic (no physics shapes pushing them): they avoid each other and the player softly, a car that hits them goes through `Pedestrian.apply_damage`/`knockback`.
* Interiors: peds never enter buildings (graph zone INDOOR is avoided).
* The ped graph has a few wrong heights in the World data (pier nodes: fixed at runtime by PedNav; one hill-path node 2.4 m under the road at (205,-230)); a stunt ramp
  (`Ramp_stunt_jump_3`) lies on the end of the beach pier.
* Audio: `AudioSystem._on_character_damaged` awaits a frame and then calls `_is_female(character)` on a possibly freed node (script error if a ped is freed within a frame of being
  hurt; PedManager now frees nodes 2 s late and pools up to 64 so this no longer happens in practice).
* Traffic: `TrafficGrid` keeps node references from the group `pedestrian` between rebuilds (same reason as above).
* Rig animation is GDScript (~110-125 us per full-rate rig): all 60 peds in view within 18 m would cost ~7 ms; the LOD policy keeps typical scenes at < 1 ms.

## Verification log (last verified in the final run of this agent)
* Headless `ped_test.gd` (84 checks): every section passed in the last runs (boot, variety, walk, crossing, panic, aim, witness, zones, death, vehicle, explosion, driver,
  sit, pool, perf, ring). Sections were re-run individually after each fix; the last complete suite run stopped 2 checks short of the end because of the frame budget
  (use -Seconds 1500) and had 3 test-robustness failures (random strolling activities, a scared sitter) that were fixed and re-run green (walk, sit, perf, pool).
* Scheduler: 62 peds = 0.45-1.1 ms / physics tick (think ~0.3-0.5, move ~0.35-0.55, headless on a machine shared with other agents); rig update 76-125 us per full-rate rig;
  LOD mix in a 62 ped crowd around the camera = 3-6 full / 2-7 reduced / ~54 frozen = 0.15-0.6 ms; worst case (all rigs full rate) 5-7 ms, only if all 60 are in view within 18 m.
* Real renderer (RTX 5070, shared machine): downtown at noon, windowed, 1280x720: ~75 fps with 60 peds + traffic vs ~95 fps with `--no-peds`; draw calls 3030 vs 2450.
  Before the shadow / visibility budget: ~65 fps and 3800 draw calls (40 peds = +1266 draw calls then, +548 now).
* Screenshots read and critiqued: street, crowd, lineup (variety: business / casual / worker / beach / jogger / tourist / elder), panic (runners, cowering, hands up, gawkers),
  bench (front + side view: seated at the right height, no clipping), sunbathe (lying on a towel), phone, talk, pier (walking ON the deck after the height fix), natural downtown /
  beach / park at several times of day.
* Fixed in this run: stale hash entries of released peds (not-in-tree errors), damage to drivers released from a moving car, snapping to the facing direction when stopping for
  a shop window, spawn distribution (nobody within 40 m before), instant population at boot / teleport, visible spawn of scene offsets, pier nodes at sea-floor height,
  render budget (shadows / visibility range), freed-too-early pooled nodes.
* Not done / limits: no swimmers; sunbathers use the rig's `dead` lying pose (knees bent); peds do not use building interiors; no phone-photo behaviour (not required).