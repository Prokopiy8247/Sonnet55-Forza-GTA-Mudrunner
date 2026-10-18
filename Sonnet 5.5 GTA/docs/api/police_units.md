# Police units + combat AI + gang NPCs (Police-B)

Owner: Police-B agent. Files: `gta/code/police/{police_units,police_officer,police_car_ai,police_roadblock,spike_strip}.gd`,
`gta/code/ai/{combat_brain,combat_actor,combat_mover,cover_finder}.gd`, `gta/code/npc/{gang_npc,hostile_manager}.gd`.
The director (`wanted_system.gd`, `police_manager.gd`, Police-A) talks to us only through `PoliceUnits.*` and `set_order`.

Tests (all headless `exec`, print `TEST name PASS|FAIL`):
| file | what | command |
|---|---|---|
| `gta/tests/police_units_test.gd` | officers: perception, memory, hearing, cover, accuracy by distance, combat flow, group alert, SWAT grenades | `exec -Script res://gta/tests/police_units_test.gd -Seconds 200 -GameArgs "--no-traffic --no-peds --no-hostiles"` |
| `gta/tests/police_units_cars_test.gd` | cruisers: caps, patrol loop, 60 s chase with 3 cruisers, PIT, deploy + arrest, roadblocks L3-5, spike strip, perf (`--only=spawn,patrol,chase,pit,deploy,roadblock,spike,perf`) | `... -Seconds 500 -GameArgs "--no-peds --no-hostiles"` |
| `gta/tests/gang_test.gd` | HostileManager autostart / groups / cap / respawn, provocation rules, friend alert, flee, calm-down, gang vs police, perf (`--only=city,provoke,retreat,calm,police,perf`) | `... -Seconds 300 -GameArgs "--no-traffic --no-peds"` |
| `gta/tests/police_units_game.gd` | REAL Police-A director + PoliceUnits in the full city: 1-star arrest, 3-star pursuit, clear (`--only=arrest,pursuit,clear`) | `... -Seconds 500` |
| `gta/tests/police_units_shots.gd` | real-renderer screenshot scenes `officers cover roadblock arrest chase gang` | `shot -Out screenshots\police\x.png -GameArgs "--exec=res://gta/tests/police_units_shots.gd --scene=chase --time=18.3 --delay=3 --no-peds --no-hostiles --wait=7"` |
| `police_units_probe.gd`, `police_units_debug.gd` | scratch probes (1-star standstill probe, free-form debug) - safe to delete | |

Screenshots (read them): `screenshots/police/officers.png`, `chase.png` (dusk), `roadblock.png` (spike strip + tactical van), `gang.png`, `officers1-3.png` (older).

## Verification log (last full run in this resumed session)
- `tools\gd.ps1 check` -> VALIDATE OK (the only fail seen mid-session was another agent's ped_test.gd, fixed by them).
- police_units_test: 27/27. police_units_cars_test: see "Known issues" for flaky spots (44-45 of 45 expected). gang_test: 26/26 (weapon mix forced in the test).
- police_units_game (real director): arrest at 1 star after ~27 s, 3 stars -> 4 cruisers + 11 officers, 3 on foot, 45-190 police gunshots in 75 s, nothing flipped, clear -> everybody gone in 16-18 s.
- Perf (headless, full game, 3-4 stars, 11 officers + 4 cars): CombatBrain 0.45 ms/frame, PoliceCarAI 0.13 ms/frame, whole force < 1 ms (limit 3 ms). Worst measured: 12 gang + 6 police firefight 1.3-1.6 ms/frame; 17 officers + 4 cars 0.8 + 0.16 ms.
- Screenshots re-rendered and read after the last code change (officers, chase, roadblock, gang).

## Public API

### `PoliceUnits` (static, `class_name PoliceUnits`)
| call | notes |
|---|---|
| `spawn_officer(kind: &"patrol"\|&"swat"\|&"sniper", xform) -> CharacterBase` | `PoliceOfficer` under `Game.world/PoliceUnits`, snapped to the ground, null above `MAX_OFFICERS` (44) |
| `spawn_patrol_car(xform, officers := 2) -> VehicleBase` | `police_cruiser` via VehicleFactory, driver + passenger seated, `PoliceCarAI` attached (meta `police_ai`), null above `MAX_CARS` (10) |
| `spawn_tactical_van(xform) -> VehicleBase` | `police_tactical` with 4 SWAT |
| `spawn_roadblock(center, dir, level) -> Node3D` | `PoliceRoadblock`: 2-3 cruisers/van tilted across the road + concrete/road barriers + cones + 2-4 officers in `hold` behind them (+ spike strip 16 m in front at level >= 4); `dir` = travel direction of the oncoming traffic; cleans itself up (age 300 s, > 260 m from the player, wanted < 2 for 14 s) |
| `spawn_spike_strip(center, dir, width := 8.0)` | `SpikeStrip` across the road (width axis perpendicular to `dir`): punctures the wheels of non-police vehicles that roll over it (`VehicleBase.puncture_wheel`) |
| `set_order(unit, order)` | forwards to `PoliceOfficer.set_order` or the car's `PoliceCarAI.set_order` |
| `despawn(node)` | officer: freed; car: occupants + car freed; roadblock: dismantled |
| `officers()`, `police_cars()`, `count_officers()`, `count_cars()` | live counts |
| `stats()` / `reset_stats()` | cost counters of the whole force (`brain_usec`, `car_usec`, ticks, paths, cover queries) |
| `ensure_hostile_manager() -> Node` | creates the `HostileManager` under `Game.world` if missing (also called by the first spawn call and by a deferred post-boot hook, so NO main.gd change is needed; disable with `--no-hostiles` or `PoliceUnits.autostart_hostiles = false`) |

Order dictionary (identical for officers and cars):
`{"mode": &"patrol"|&"pursue"|&"search"|&"hold"|&"leave", "target": Node, "pos": Vector3, "radius": float, "aggression": 0..1, "lethal": bool}`
extras: `"dir"` (facing for hold), `"stance"` (`&"crouch"` for hold), `"arrest"` (false = officer never calls `Player.arrest`), car-only `"role"` (`&"tail"|&"flank"|&"intercept"|&"pit"|&"block"`), `"level"`.

### `PoliceOfficer extends CharacterBase`
Groups `police`,`npc`; faction `GC.F_POLICE`; `kind` patrol (pistol 62 % / SMG 24 % / shotgun 14 %, accuracy 0.4, 100 hp) / swat (rifle/carbine/shotgun, 135 hp + 55 armour, accuracy 0.58, flanks, grenades) / sniper (hold position, marksman/sniper rifle, accuracy 0.78).
Vars `kind`, `mode`, `order`, `brain`, `mover`, `actor`, `home_vehicle`, `home_seat`, `weapon_drawn`, `ai_accuracy`. Signals `order_changed(order)`, `arrested(target)`. Static `PoliceOfficer.arrest_enabled`.
- patrol: idles / strolls near `order.pos` (idle styles), weapon holstered until something happens.
- pursue: CombatBrain on `target` (the player only while wanted: `CharacterBase.is_hostile_to`); with nobody in sight it runs to the last known position; gets back into its car for fast vehicle targets; at 4-5 stars with no car it walks to a nearby civilian car and commandeers it (stretch, NOT verified in-game).
- search: sprints to the search area (> radius*1.1+10 m away), then walks random points scanning with the head.
- hold: roadblock guards / posts (crouch or stand), fire from behind the barriers.
- leave: back to the car, or walks away and despawns when unseen / > 140 m.
- Arrest: while the player is the target and shooting is not authorised (`order.lethal` false, player not hostile to police for 25 s) the officer closes to 1.2-2.4 m, aims without firing, shouts ("Police! Stop right there!" via `Events.subtitle`) and after `ARREST_TIME` (1.1 s) within `ARREST_RANGE` (2.5 m) of a still, non-aiming player calls `Game.player.arrest(self)`.
- Every sighting of the player calls `Game.sys(&"wanted").report_sighting(pos, self)` (max once per 0.7 s).

### `PoliceCarAI extends Node` (child of the police `VehicleBase`, meta `police_ai`)
`PoliceCarAI.attach(vehicle)`, `detach(vehicle)`, `set_order(order)`. Modes: patrol (lane-follow at 1.12 x limit, red lights obeyed, siren off), pursue (siren + lights; lane-graph chase on road / pure pursuit off road; roles tail / flank / pit / intercept; obstacle avoidance; stuck recovery: reverse + U-turn, blocked-lane memory, hidden relocation to the nearest free lane point after 3 stuck events when nobody sees it; PIT at >= 11 m/s with 3.2 s cooldown; ramming only at >= 3 stars; boxing-in at <= 6 m/s), deploy (stops ~8-13 m from an on-foot target, officers exit and follow the order), search (responds at emergency speed with the siren on while > max(1.2 x radius, 55 m) from the search centre, then cruises the area with a night spotlight), leave (drives away, despawns when unseen > 150 m).
Tunables: `speed_factor`, `obey_signals`, `autonomous` (reads Game.wanted_* itself when no order arrives), `driverless`, `top_response`, consts `PIT_MIN_SPEED PIT_COOLDOWN DEPLOY_DIST BOX_SPEED LAT_ACCEL_PURSUIT`. Statics `pit_attempts pit_contacts rams deploys recoveries stat_usec`.

### `CombatBrain` (RefCounted, owned by a `CombatActor`)
Reusable on-foot combat controller (police / SWAT / gang). States `IDLE SEARCH APPROACH ENGAGE COVER_MOVE COVER_HIDE COVER_PEEK FLANK RETREAT MELEE HOLD`.
- Perception: LOS rays to chest/head, 120 deg FOV (all-round once alerted), hearing via `Events.gunshot`, memory 8 s, group alert radius, first-contact cover seeking.
- Shooting: `WeaponController.aim_at_point` + bursts, `accuracy` 0.25-0.8 with distance falloff, per-burst aim error (up to ~0.9 m for a poor shot, scaled with distance), friendly-fire guard (a friendly within 0.85 m of the line of fire or a friendly in the ray holds the trigger), reload in cover, SWAT grenades (11-30 m), melee when adjacent, dodge of fast vehicles, one-time retreat roll at `retreat_hp` (`retreat_chance`), SWAT flanking.
- Signals `target_sighted target_lost state_changed burst_started grenade_thrown heard_shot`. Tunables are plain vars: `accuracy sight_range alert_range fov_deg hearing memory reaction_time pref_min pref_max use_cover cover_bias flank grenades can_melee retreat_hp retreat_chance alert_radius aggression burst_shots burst_time burst_pause target_groups forced_target shoot_allowed aim_without_fire hold_position`. `CombatBrain.stat_usec/stat_ticks/cover_queries` = cost counters.

### `CombatActor`, `CombatMover`, `CoverFinder`
- `CombatActor.build(body, appearance, loadout, cfg)`: capsule, `CharacterRig`, `WeaponController`, mover + brain, distance tiers (near < 70 m / mid < 140 m / far; physics stride 1/2/4), crouch capsule, knock-down + get-up, death ragdoll (30 % weapon pickup) and corpse cleanup (24 s), fall-through safety net (back to the last floor position, removed on the second fall).
- `CombatMover`: `set_goal(pos, speed, arrive)`, `stop()`, `face(point)`; direct steering with ray avoidance, A* over `WorldLayout.ped_graph` for routes > 24 m or walled off, stuck handling (side-step, re-plan, skip the blocked waypoint at 2.6 s, give the route up at 4 s). Movement is scaled by the number of physics frames a (strided) tick covers.
- `CoverFinder.find(node, origin, threat, opts)`: 30 rays (22 of them in the +-105 deg half-plane facing the threat), candidates scored by walking distance / protection / threat range / claims.

### `GangNpc extends CharacterBase` + `HostileManager`
Faction `GC.F_GANG`, groups `hostile`,`npc`; "Neon Vipers" look (`CharacterVariants.make(&"gang")`); pistol (50 %) / SMG (28 %) / bat (22 %), accuracy 0.25-0.45, 92 hp; `forced_weapon` (set before add_child) picks the weapon for tests/scripted encounters.
They idle on their turf (idle styles, strolls, holstered) until the player is within 35 m **with a weapon out** or within 11 m, shoots within 55 m or hurts one of them (LOS needed for the proximity triggers); the whole group within 60 m then attacks (cover, bursts, bats rush), ~35 % of the badly hurt (< 30 % hp) run away, they calm down 25 s after the player is > 60 m away and walk home.
`HostileManager`: 3 turfs (2 industrial yards + the back alley "Gull Alley"), 3-4 members per group, <= 12 alive, groups stream in within 260 m (not while in view, not within 85 m of the player spawn), out beyond 330 m, wiped group respawns after 300 s once the player is away; spawn spots must fit a capsule. API `groups turfs alive_count() force_spawn_all() clear_all() enabled stats`.

## Events / contracts used
Consumes `Events.gunshot`, `Events.character_damaged`, `Events.character_died`; emits `Events.subtitle` (shouts). Never emits crimes (WantedSystem derives them). Calls `Game.sys(&"wanted").report_sighting`, `Game.player.arrest(officer)`, `VehicleBase.request_enter/exit/enter/place_at/set_velocity/puncture_wheel`, `set_ai_controlled`, `input_*`, `WeaponController` (`equip`, `aim_at_point`, `set_trigger`, `fire_once`, `start_reload`, `throw_grenade_now`), `CharacterVariants.make(&"police"/&"tactical"/&"gang")`.
CLI: `--no-hostiles` (no gang NPCs; also `--no-traffic --no-peds`).

## Tunables worth knowing
`PoliceUnits.MAX_CARS = 10`, `MAX_OFFICERS = 44`; `PoliceCarAI.PIT_COOLDOWN 3.2`, `PIT_MIN_SPEED 11`, `DEPLOY_DIST 13`; `PoliceOfficer.ARREST_RANGE 2.5`, `ARREST_TIME 1.1`, `SHOUT_GAP 6.5`; `GangNpc.PROVOKE_ARMED_RANGE 35`, `PROVOKE_CLOSE_RANGE 11`, `FRIEND_RADIUS 60`, `CALM_AFTER 25`; `HostileManager.MAX_ACTIVE 12`, `STREAM_IN 260`, `RESPAWN_DELAY 300`; `PoliceRoadblock.MAX_AGE 300`, `FAR_DISTANCE 260`.

## Fallbacks / placeholders
- `SpikeStrip` mesh is code-built (box + prism spikes in a MultiMesh); there is no Blender asset `props/spike_strip` (logged by `push_warning`).
- Everything else uses Blender assets: `vehicles/police_cruiser`, `police_tactical`, `props/concrete_barrier`, `road_barrier`, `road_cone`, `characters/human` via CharacterVariants.

## Known issues / limits (honest list)
- Foot officers spawned by the director 100-150 m away need ~25-30 s to reach a standing player (they run along the ped graph at 5.5-6.8 m/s); at 1 star the director's "search -> clear" timer can end the wanted level first (arrest worked in 2 of 3 full-city runs; the unlucky run was cleared by Police-A's timer before the officers arrived).
- Cars in the narrow alley at about (-5..26, -55) (lane limit 6.9 m/s, bins / bollards standing in the lane) crawl or wedge for several seconds; blocked-lane memory + hidden relocation resolve it eventually.
- Police on foot walk over crossings without waiting for traffic (they are not slowed by `WorldLayout.crossing_open`), and queues of cars across a crossing can hold one for a few seconds until the stuck handler cuts the waypoint.
- The PIT contact is verified by the minimum gap between the cars (the `collided` signal of the cruiser is not reliably raised for glancing contact); the target spins 130-180 deg in the test.
- Commandeering a civilian car (4-5 stars, stranded) is implemented but has no in-game verification. Rooftop sniper placement is up to the director (`spawn_officer(&"sniper")` holds position wherever it is put; no roof search of its own).
- SMG gang members outgun pistol patrol officers 3 v 3 (cops lost 3-0 in one run, gang lost 3-0 in the earlier one): outcomes vary with the weapon mix.
- Gang bat carriers can be hit by a friend's stray burst (reduced by the line-of-fire guard, not eliminated).
- At exit the log shows `!is_inside_tree()` errors from `ui/minimap.gd` / `vehicles/plane_vehicle.gd` and Jolt RID leak lines: not from this module.
