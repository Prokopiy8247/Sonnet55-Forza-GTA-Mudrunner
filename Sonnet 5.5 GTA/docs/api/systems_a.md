# Systems-A: Skills, Save/Load, Economy + pickups, World interactions

Status (kept current; see "Verified" and "Limits" at the bottom): all four modules are finished and their headless tests pass
(skills 46, save 43, economy 38, interactions 62 - run with `powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/<name>_test.gd`),
screenshots of every interaction were taken with the real renderer (`screenshots/sysa/`).

Files owned: `gta/code/systems/skills_system.gd`, `economy_system.gd`, `pickup_placer.gd`, `interaction_manager.gd`, `interaction_point.gd`,
`interaction_util.gd`, `interaction_ladders.gd`, `interaction_elevator.gd`, `interaction_props.gd`, `gta/code/save/save_system.gd` (autoload `SaveSystem`),
`gta/code/save/save_codec.gd`, tests `gta/tests/skills_test.gd`, `save_test.gd`, `economy_test.gd`, `interactions_test.gd`, helpers `interactions_shot.gd`,
`interactions_probe.gd`, `economy_dump.gd`.

## 1. SkillsSystem (`Game.sys(&"skills")`, class `SkillsSystem`)

Seven skills `stamina, shooting, strength, stealth, driving, flying, lung`, each 0..100, growing only by use.
Growth is `value = 100 * (1 - (1 - xp / XP_MAX)^1.7)` (front loaded: one minute of sprinting is visible, the last points are slow).
`record(id, amount)` takes "use units" (about one second of sustained use or one clean action). XP_MAX (units to 100):
stamina 900, shooting 450, strength 160, stealth 90, driving 800, flying 600, lung 320.

API
- `get_skill01(id) -> float` 0..1, `get_skill(id)` / `get_value(id)` 0..100 (the UI status screen reads these; values below 1 report 0 because the UI treats <= 1 as ratios), `get_percent(id) -> int`, `get_all() -> Dictionary`, `skills` (live dictionary).
- `record(id, amount) -> float` (aliases the Player probes: `train`, `add_xp`, `record_use`, `add_progress`, `use_skill`).
- `get_modifier(name) -> float`: `recoil` (1 - 0.25 s), `spread` (1 - 0.15 s), `reload_time` (1 - 0.20 s), `melee_damage` (1 + 0.40 s), `fall_damage` (1 - 0.35 s), `noise` (1 - 0.45 s), `stamina_drain` (1 / (1 + 1.2 s)), `lung_capacity` (1 + 2 s => 20 s -> 60 s), `vehicle_grip` (1 + 0.07 s), `vehicle_recovery` (+0.12 s drift grip floor), `aircraft_stability` (1 - 0.35 s) where s = the matching skill 0..1. Unknown names return 1.0.
- Debug menu: `set_skill(id, v)`, `set_all(v)`, `max_all()`, `reset_all()`; `Game.cheats["freeze_skills"] = true` stops growth.
- Persistence: `serialize()` / `deserialize()` (xp values; tolerant). Events: `Events.skill_changed(id, value)`; own signal `skill_levelled(id, value)`; a toast appears every 10 points (`announce`).
- Toggle for tests: `announce`, `sampling`.

Consumers (hooks already in place; all duck typed)
| skill | where it is trained | where it pays off |
|---|---|---|
| stamina | Player sprint/swim (`_skill_use`), bicycle riding (sampler) | Player stamina drain factor |
| shooting | `Events.hit_marker` (hit 1, kill 3, headshot +1) | WeaponController spread / recoil / reload via `get_modifier` |
| strength | melee hits / kills (`hit_marker`), Player melee/climb, surviving falls | melee damage, `Player` fall damage (`fall_damage`) |
| stealth | crouch-moving near NPCs (sampler), Player stealth takedowns | Player noise radius while crouched |
| driving | sampler: hard turns at speed, drifting (`get_slip_angle`), airtime, near misses with other vehicles | `CarVehicle.skill_grip` / `skill_recovery` (set while the player drives) |
| flying | sampler (aircraft in the air) + Air agent `record(&"flying", ..)` | `get_modifier(&"aircraft_stability")` read by `air_common.gd` |
| lung | Player underwater time | `Player.lung_capacity()` (20 s -> 60 s, scuba x4) |

## 2. SaveSystem (autoload `SaveSystem`)

- `save_game(slot := 0) -> bool`, `load_game(slot := 0) -> bool` (validates synchronously, restores asynchronously: fade out, reset dynamic content, restore, fade in; listen to `load_finished(slot, ok)` / `Events.load_completed`), `await load_game_async(slot) -> bool`, `has_save(slot)`, `list_saves() -> Array[Dictionary]`, `get_slot_info(slot)`, `delete_save(slot)`, `gather(slot) -> Dictionary`.
- `save_settings()`, `load_settings()` (user://settings.json, applied at boot, debounced on `Events.settings_changed`), `set_flag(key, value)` / `get_flag(key, default)` (generic persistent flags), `handles_quick_keys() -> false` (F5/F9 stay with the UI).
- Files: `user://saves/slot_N.json` (N 0..9; 0 = quick save, 1 = autosave every 5 min when the setting `autosave` is on). Written atomically (tmp + rename), previous file kept as `.bak` and used when the main file is damaged.
- Format: JSON with `version`, `meta` (money, hour, district, play_time, weather), `world` (cash, time_of_day, weather, wanted_level), `player` (Player.serialize: pos, yaw, health, armor, stamina, parachute, scuba, weapons), `player_extra` (appearance, scuba), `vehicle` (current/last owned vehicle: id, transform, paint, finish, mods, health ratio, inside), `systems/<key>` (every `Game.systems` node with serialize()/deserialize(), except player/world/environment/audio), `flags`, `settings`. Variants are encoded by `SaveCodec` (Vector2/3/4, Color, Transform3D, Basis, Quaternion, packed arrays).
- Load flow resets police/traffic/peds/wildlife/emergency (`despawn_all`/`clear_all`/`reset`), wanted level (0 unless setting `restore_wanted`), dropped loot and the player's old vehicles; a dead/busted player is revived. Damaged/missing files: toast, `last_error`, `load_finished(slot, false)`, the game keeps running.

## 3. EconomySystem (`Game.sys(&"economy")`) + PickupPlacer

- Cash API: `get_cash()`, `set_cash(n)`, `add_cash(n)`, `spend(n, warn := false) -> bool`, `can_afford(n)`; `total_earned` / `total_spent` follow `Events.cash_changed`.
- `PickupPlacer.build_spots()` resolves ~62 spots against the real colliders with a fixed seed: 37 cash stashes (rooftops incl. ladder roofs, alleys, pier tips, hill road + summit, beach dunes, park/pond, industrial yards, airport, underwater at the dive wreck), 15 supply points (health/armor/ammo/range pistol at hospital, weapon shop, police HQ, shooting range, park, beach, safehouse, viewpoint, construction site, garage, hangar), 5 weapon crates (construction, industrial, viewpoint, hangar, docks; random mid-tier weapon, respawn 10 min), 5 gear pickups (parachute at `parachute_pickup_a/b`, downtown tower roof, hospital roof; scuba set on the beach above `diving_wreck`).
- Respawn: cash 15 min, crates 10 min, supplies 100 s, gear 120 s (only taken when not owned). Collected state is saved (`serialize` -> `collected` with seconds left).
- Pickups are the weapons module classes (`CashPickup`, `HealthPickup`, `ArmorPickup`, `AmmoPickup`, `WeaponPickup`) + `PickupPlacer.ParachutePickup/ScubaPickup/WeaponCrate`, with the Blender GLBs (`props/pickup_*.glb`, `scuba_gear.glb`). EconomySystem turns off CombatSystem's own world pickups (`world_pickups_enabled`).
- Debug: `goto_spot(id)`, `respawn_all()`, `get_spot(id)`, `get_pickup(id)`, `count_active()`; signals `world_ready`, `spot_collected`.
- NPC cash drops (Peds agent) are plain `CashPickup` nodes; nothing to do here.

## 4. World interactions (`Game.sys(&"interactions")`, class `InteractionManager`, hosted by EconomySystem)

One manager and bare `InteractionPoint` anchors (group `interactable`, read by the Player's interaction scan): no per-prop scripts.
- 8 roof ladders (`props/ladder_wall.glb` as one MultiMesh each, picked from the building lots by ray/capsule/roof tests; districts downtown/residential/industrial/...), prompts `[E] Climb ladder` at the bottom and `Climb down the ladder` at the top, driven by `Game.player.traversal.start_ladder`; every roof carries a cash stash.
- Downtown tower elevator (`[E] Take the elevator to the rooftop helipad`): door slides open, fade, 1.4 s ride with camera shake, teleport to the roof house next to `helipad_downtown`, fade in; a second point on the roof goes down. Props `props/elevator_door.glb` / `props/elevator_roof.glb` (see Limits).
- 9 phone booths (`props/phone_booth.glb` with a collider): `[E] Use the phone (save game)` saves to slot `phone_slot` (default 0).
- Benches: 24 baked MultiMesh benches are served by a pool of 3 prompt anchors that follow the player; `[E] Sit down`, pelvis pose via the rig's `sit_car` stance; E / jump / move / crouch / damage stands up.
- 33 fire hydrants: water jets (CPUParticles3D pool of 4) when shot (`Events.projectile_impact`), blown up (`Events.explosion`) or rammed by a vehicle > 5 m/s.
- Test helpers: `ladders`, `elevator`, `booths`, `points`, `ride(player, to_roof)`, `spray_hydrant(i)`, `get_bench_seats()`, `_sit(player, idx)`.

## Shared-file edits (all additive, duck typed)
- `gta/code/vehicles/car_vehicle.gd`: `skill_grip`, `skill_recovery` fields used in the tyre grip / drift grip floor.
- `gta/code/player/player.gd`: fall damage multiplied by `get_modifier(&"fall_damage")` (line ~818).
- `gta/code/weapons/weapon_controller.gd`: `_player_skill_mod()` applied to spread, recoil, reload time and melee damage.

## Verified
- Headless tests (all green): `skills_test.gd` (46: growth curve, caps, modifiers 15-25 % at 100, lung 20 -> 60 s, hooks into the real WeaponController / Player / CarVehicle, persistence), `save_test.gd` (43: round trips of cash / position / yaw / health / armor / weapons+ammo+mods / time / weather / skills / flags / stored pickups / appearance / vehicle incl. re-entering it, missing / empty / garbage / wrong-shape / header-less files, .bak fallback, dead player revived, settings file round trip + damaged settings + broadcast), `economy_test.gd` (38: 62 spots on real ground, 37 cash stashes, crates / parachutes / scuba / health / armor / ammo behaviour, respawn timers 15 min / 10 min, serialize + deserialize, NPC drops, 28 us per frame for 62 pickups), `interactions_test.gd` (62: 8 ladders climbed up AND down with the real Player, elevator round trip, phone booth save, bench sit / stand, hydrant jets from bullets / explosions / ramming, none of the props overlapping baked street furniture; 183 us per 0.25 s tick, 125 us per prompt scan).
- Windowed `--perf` run of the full game (21 systems, traffic + peds on, other agents sharing the GPU): 73-88 fps, ~4.5k draw calls, 8.4k nodes, 320 MB; the Systems-A share is the measured microseconds above (pickups are 62 nodes, hidden beyond 120 m and animated only within 45 m; ladders / benches / hydrants add no per-frame cost while the player is away).
- Boot cost: Interactions build 65-97 ms and Economy 30-35 ms, spread over deferred physics frames after the world is built (no hitch).
- Screenshots (1280x720, GPU renderer, `tools\gd.ps1 shot ... --exec=res://gta/tests/interactions_shot.gd --scene=<name>`): `elev_ground.png`, `elev_ground_night.png`, `elev_roof.png`, `tower_roof.png`, `ladder_mid.png`, `ladder_top.png`, `roof_reward.png`, `pickups_day.png`, `pickups_night.png`, `cash_beach.png`, `booth.png`, `bench.png`, `hydrant.png` in `screenshots/sysa/`. Scenes: pickup (--id), pickups_row, ladder (--n, --u), ladder_top, roof, elevator_ground, elevator_roof, booth, bench, hydrant, tower_roof.

## Limits / not done
- Automatic sliding doors for the hospital / police entrance are NOT implemented: the landmark GLBs only export an empty `Door` anchor (the door geometry is baked into `Body`), so there is no separate door node to animate. The new elevator doors are the only sliding doors.
- No vending machine prop exists in the Blender library; phone booths are the only "use" props (save). Breakable street lamps are not done (static props are MultiMeshes without per-instance physics).
- Prop GLBs: `props/elevator_door.glb` and `props/elevator_roof.glb` were authored in this module (`tools/blender/sysa_elevator.py`, 244 + 712 tris, nodes Body / DoorL / DoorR + empties Stand / UsePoint). Every other visual is an existing Blender GLB (ladder_wall, phone_booth, bench, fire_hydrant, pickup_*, scuba_gear); the code fallbacks (box ladder / booth / door) only log a warning when a GLB is missing.
- Baked street furniture (bus stops, benches, lamps, bins) has no colliders, so the planners (elevator door, phone booths, ladders) reject spots within 1-3 m of a furniture entry; parked cars are dynamic and can still stand in front of the lift door.
- The elevator is not an animated cab: the door slides open, the screen fades, the player is teleported and the roof door opens (as the spec describes).
- Loading never restores the wanted level unless the setting `restore_wanted` is true; NPCs, traffic and police are despawned and respawn through their own systems.
- Known issue outside this module: `AudioSystem._is_female` / `PedBrain._decide` print "previously freed" script errors when a pedestrian is freed while an `await`ed handler still holds it (seen during headless tests that despawn peds).

## Resume notes
Nothing is pending. To extend: add spots to `PickupPlacer._services/_gear/_cash`, new interactables as `InteractionManager._make_point(kind, ...)` + a case in `describe()` / `activate()`.
