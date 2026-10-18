# Benchmark / debug menu (`Game.sys(&"debug")`, F1 or `)

Owner: Debug agent. Mandatory testing tool for demo videos - **not a mission system**. Everything below was run in-game (headless test + real-renderer screenshots).

## Benchmark menu (F1) - player-facing

**Open / close:** `F1` or backquote (`). `Esc` also closes. The game keeps running behind the menu (the mouse is freed while it is open and recaptured on close);
tick *System -> Pause the game while this menu is open* to freeze it. Works while driving / flying (spawning while driving puts the new vehicle ahead of you).
While the menu is open the player's own movement / fire input is ignored (UI rule) - the vehicle keeps rolling.
`PgUp` / `PgDn` change tab, `Tab` / arrows move focus, `Enter` presses, mouse works everywhere. Every action shows a toast; buttons whose target system is missing are greyed (hover for the reason).

| tab | controls |
|---|---|
| **Teleport** | all 7 district centres + every `WorldLayout.locations` entry grouped (start & services, shops, airport & helipads, docks / beach / diving wreck, viewpoints / parachute peak, activities / stunt jumps, transport, any other location lands in "Other"); *Teleport to map waypoint*; "close menu after teleport / spawn" toggle. Snaps to the ground with a physics ray, finds a free capsule spot if the exact point is blocked, water locations put you at the surface, the vehicle comes along when driving. |
| **Vehicles** | all 20 implemented vehicles in groups Cars / Bikes / Trucks & emergency / Boats / Helicopters / Airplanes + search box; paint colour (random or 9 swatches); "get in after spawning". Ground vehicles spawn on the road ahead (lane point) or on free ground; **helicopters at the nearest free helipad, planes on the runway, boats in the nearest deep water**. Current vehicle: Repair, Flip upright, Delete nearby (80 m), Open customization garage (GarageSystem session for the current / nearest vehicle), Vehicle god mode, Unlock ALL mod options (free), Engine / speed boost slider x1-x4. |
| **Weapons** | Give ALL weapons, Remove all, Refill ammo, Give parachute, Infinite ammo, Scuba gear (unlimited air), Refill lungs, Heal (health + armor + lungs), Health / Armor sliders, attachment toggles for the equipped weapon, one button per weapon (all 16, full ammo, `*` = owned). |
| **Player** | Money (+$10k, +$1M, $0, exact value box), Health / Armor sliders, Invulnerable, Never wanted, Wanted 0-5 + Clear, skills (Max all / Reset all + one slider per skill), Hour slider + Dawn / Noon / Dusk / Midnight + Freeze time + Clock speed slider, Weather buttons. |
| **World** | spawn at crosshair or 16 m ahead; Police: patrol car, officer, SWAT, sniper, tactical van, helicopter, roadblock; Gang group (3), Wake all gang turfs, Pedestrians x10, Call taxi, Ambulance, Fire truck, Explosion at crosshair, Slow motion; toggles Traffic / Pedestrians / Wildlife / Never wanted; traffic + pedestrian density sliders; "Knock out NPCs within 40 m" (confirm dialog, off by default). |
| **Overlays** | FPS (HUD, = F2 stage 1), Coordinates (HUD), **Benchmark stats panel** (FPS, frame ms + max, draw calls, objects, triangles, node count, active physics bodies, memory, XYZ, 100 m sector, district, heading, speed, wanted / traffic / ped / police counts), Wanted debug (last-known marker + search circle + police sight cones), Lane graph lines, Pedestrian graph lines (70 m around you), HUD visible, viewport render mode (Normal / Unshaded / Lighting only / Overdraw / Normals). |
| **System** | Save 0, 2-4 / Load (SaveSystem slots; slot 0 = F5 quick save), Photo mode, Reset to spawn plaza, Respawn at hospital, Regenerate traffic, Clear all dynamic entities, Print state dump to log, **Run self checks** (PASS / FAIL list), pause-while-open, version / build info, hotkey list. |

### Hotkeys (work with the menu closed; chosen not to clash: Ctrl = crouch / descend, plain keys are gameplay, Alt is only the slow-walk modifier, numpad is unbound)
| key | action |
|---|---|
| `F1` / `` ` `` | open / close the menu |
| `Alt+1..5` (`Alt+0` clear) or `Numpad 0..5` | wanted level |
| `Alt+T` or `Numpad *` | cycle time: dawn / noon / dusk / midnight (`Numpad +/-` = +-1 h) |
| `Alt+W` or `Numpad /` | cycle weather |
| `Alt+V` or `Numpad Enter` | spawn the last spawned vehicle (default sedan) ahead and get in |
| `Alt+R` or `Numpad .` | repair + flip the current vehicle |
| `Alt+H` or `Numpad 7` | heal (health + armor + lungs) |
| `Alt+M` / `Alt+Shift+M` or `Numpad 8` | +$10,000 / +$1,000,000 |
| `Alt+G` or `Numpad 9` | invulnerability + vehicle god mode |
| `Alt+K` or `Numpad 6` | give all weapons, full ammo |
| `Alt+B` | teleport to the map waypoint |
| `Alt+X` | delete nearby vehicles |
| `Alt+Z` | slow motion |
| `Alt+P` | spawn a police patrol car |
| `Alt+E` | explosion at the crosshair |
| `Alt+F` | stats panel on / off |
F2 / F3 / F5 / F9 belong to the UI / photo mode / save and are not touched. Hotkeys are ignored while a text box has focus or another menu (pause, map ...) is open.

## Code
| file | class | role |
|---|---|---|
| `gta/code/debug/debug_menu.gd` | `DebugMenu` (Node, boot key `debug`) | F1 / ` toggle, hotkey layer, stats-panel overlay (CanvasLayer 12), gizmo + god / boost ticks. `open(tab)`, `close()`, `toggle()`, `is_open()`, `refresh_state()`, `spawn_at_crosshair` |
| `debug_menu_ui.gd` | `DebugMenuUI` (MenuBase, UIRoot menu id `&"debug"`) | the 7-tab panel built with UIKit (1560 x 900 design px, `pauses_game = false`, `dim_background = false`) |
| `debug_cmds.gd` | `DebugCmds` (static) | **every action** as a UI-free function returning `{ok, msg, ...}` (teleport_*, spawn_vehicle, remove_vehicle, delete_nearby_vehicles, repair_current, flip_current, set_vehicle_god, set_speed_boost, open_customization, set_unlock_all_mods, give_weapon, give_all_weapons, remove_all_weapons, refill_ammo, set_attachment, give_parachute, set_scuba, refill_lungs, set_health / armor, heal_full, set_money / add_money, set_invulnerable, set_never_wanted, set_wanted, clear_wanted, skills_max / reset / set_skill, set_time, set_time_frozen, set_clock_speed, set_weather, spawn_police, spawn_gang, activate_gang_turfs, spawn_pedestrians, call_taxi, spawn_service, explode_at_crosshair, set_traffic / pedestrians / wildlife, set_density, kill_nearby_npcs, set_slowmo, set_cheat, set_hud_visible, set_render_mode, stats_text, save_slot, load_slot, open_photo_mode, reset_to_spawn, respawn_hospital, regenerate_traffic, clear_all_dynamic, state_dump, run_self_checks, version_info) |
| `debug_catalog.gd` | `DebugCatalog` | tables: location groups / labels, vehicle groups (unlisted ids go to "More vehicles"), paints, presets, hotkey list |
| `debug_gizmos.gd` | `DebugGizmos` (Node3D) | one ImmediateMesh for wanted debug / lane graph / ped graph lines, rebuilt at 4 Hz **only while a `dbg_*` flag is on** |

Cheat flags written to `Game.cheats`: `show_fps show_coords` (read by the HUD), `invulnerable infinite_ammo traffic pedestrians wildlife never_wanted scuba` (read by their systems), `unlock_all_mods` (GarageSystem), plus menu-owned `vehicle_god vehicle_boost slowmo dbg_stats dbg_wanted dbg_lanes dbg_peds`.
Systems used (all duck-typed, null-checked): VehicleFactory / VehicleSystem, GarageSystem (`begin_session`, `can_customize`, `unlock_all`, `start_photo_mode`), WeaponController, WantedSystem (`set_level`, `clear`), PoliceUnits / PoliceHeliAI / HostileManager / GangNpc,
PedManager (`spawn_crowd`, `clear_all`), TrafficManager (`clear_traffic`, `get_active_count`), EnvironmentSystem (`set_time`, `set_weather`), SkillsSystem (`max_all`, `reset_all`, `set_skill`), CombatSystem (`explode`), TransitSystem (`call_taxi`, greyed until it exists), SaveSystem, Player (`respawn_at`, `teleport_to`, `has_parachute`, `has_scuba`, `lungs`).

## Cost
Closed menu: two `_input` callbacks, `_process` OFF (verified by test `overlay_idle_no_process`), gizmos process OFF, no per-frame allocations. The panel is built when a tab is opened (UI nodes, ~ms). With the stats panel on, one string is built at 4 Hz.

## Tests / verification
* `gta/tests/debug_menu_test.gd` (headless, calls every action without UI and asserts the effect): `powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/debug_menu_test.gd -Seconds 200 -GameArgs "--no-intro"` - final run 70 of 70 PASS (0 FAIL) after the teleport fix below; the first run had 1 FAIL (all 44 locations teleported, all 20 vehicles spawned / entered / removed, 16 weapons, wanted 0-5, traffic 22 -> 0, peds 66 -> 0, all 7 tabs build, search, F1 toggle, Alt+3 hotkey, self checks 11/11); the one failure (`parachute_pickup_b`: the player was pushed 1.9 m below the apron by a hidden collider) was fixed by the free-capsule snap and verified with a probe (player stays at y 0.03, 3 m beside the pickup point).
* Screenshots (real renderer): `screenshots/debug/tab1_vehicles_driving.png` (1920x1080, menu over gameplay while driving a Vanta GT) and `tab1_vehicles_720.png` (1280x720, readable, no overlap). `gta/tests/debug_menu_shot.gd` renders any tab (`--tab=0..6`, `--drive=<vehicle id>`).

## Known limits / honest notes
* Only the Vehicles tab was screenshotted (usage-limit wrap-up); the other six tabs build without errors (headless) but were not visually reviewed.
* **Wireframe render mode is not offered**: Godot generates wireframe data only for meshes uploaded after `RenderingServer.set_debug_generate_wireframes(true)`; the city is already built when the menu exists.
* `Call taxi` is greyed until `Game.sys(&"transit")` has `call_taxi()` (the stub has none; the test `call_taxi_graceful` returned ok because the parallel Transit agent's method already existed in the last run). Wildlife toggle writes `Game.cheats["wildlife"]` and calls `set_enabled(on)` / `enabled` on the wildlife system when it has one, otherwise only the flag.
* Customization garage: needs a car / bike / bicycle (current or within 12 m). Garage `sites` are discovered by GarageSystem ~30 frames after the world is built; the debug call falls back to a bay-less session.
* Debug-spawned gang members are not managed by `HostileManager` caps (max 9 debug gang alive); police spawned from the menu are NOT registered with the director (they patrol / follow `Game.wanted_*` themselves; the unit caps of `PoliceUnits` apply).
* Vehicle god mode keeps the CURRENT vehicle at full health (meta `invulnerable` + repair when damaged); speed boost scales `mod_power` / `mod_topspeed` (cars, bikes, boats; aircraft ignore `mod_power`).
* While the menu is open the player ignores movement input (UI rule), so spawn-and-enter closes the menu by default ("close menu after teleport / spawn").
* Another (stopped) Debug instance left files `debug_panel / pages / ui / overlay / selfcheck.gd`; they were renamed to `*.gd.orphan` in `gta/code/debug/` (not deleted, not used).
