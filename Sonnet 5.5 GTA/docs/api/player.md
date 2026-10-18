# Player module (Player agent) - controller, camera, interaction, death / respawn

Files (all under `gta/code/player/`; the CharacterRig files belong to the Rig agent, see `docs/api/character_rig.md`):

| file | class | role |
|---|---|---|
| `player_system.gd` | `PlayerSystem` (Node) | boot entry: spawns Player + PlayerCamera, sets `Game.player` / `Game.gameplay_camera`, registers extra input actions, fade overlay fallback, `respawn_at()` |
| `player.gd` | `Player extends CharacterBase` | the body: movement, stances, swimming, vehicle driver proxy, weapons wiring, death / arrest / respawn |
| `player_camera.gd` | `PlayerCamera extends Camera3D` | orbit / aim / first person / vehicle chase / aircraft chase / death camera, shake, recoil |
| `player_interaction.gd` | `PlayerInteraction` | interactable + vehicle scan, prompt, `E` / `F` handling |
| `player_traversal.gd` | `PlayerTraversal` | vault, mantle, climb out of water, ladders, parachute |
| `player_cover.gd` | `PlayerCover` | wall / low cover (Q) |

Tests: `gta/tests/player_test.gd` (`exec`, ~110 asserts, `-GameArgs "--only=camera,swim"` filters), `gta/tests/player_shot_scene.gd` (screenshot scenarios).

```
powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/player_test.gd -Seconds 200
powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\p.png -GameArgs "--exec=res://gta/tests/player_shot_scene.gd --scene=side_run --delay=4 --time=11 --no-peds --no-traffic"
# scenes: stand run sprint crouch aim aim_rifle fp cover swim dive chute vehicle death, and side_<scene> (free camera, --dist --ang --yaw)
```

## Boot / spawn
`PlayerSystem.setup()`: registers extra actions `walk` (Alt, hold: slow walk) and `shoulder_swap` (Z), creates `PlayerCamera` and `Player` as children of the system node
(**the camera is not a child of the body**), spawns at `WorldLayout 'player_spawn'` (fallback `(0,2,0)`), joins group `player`, sets `Game.player`, `Game.gameplay_camera` (= the PlayerCamera, a `Camera3D`).
`post_setup()` gives the starter loadout (`pistol` 36 rounds) if the player owns nothing but fists.
**Ground guard:** after every teleport / spawn the player stays frozen until a collider (or water) exists below it, so it never free-falls through a world that is still being built (logs a warning after 5 s).

## Player (CharacterBody3D, `class_name Player`)
Collision: layer `GC.L_PLAYER`, mask `GC.M_CHARACTER_MOVE`, capsule r 0.35 (stand 1.8 m, crouch 1.25 m, swim 0.9 m). Faction `GC.F_PLAYER`.
Visuals: `player.visual` (top-level Node3D, interpolated between physics ticks - smooth on any refresh rate) contains `player.rig` (CharacterRig, variant `CharacterVariants.player_default()`).
If the rig had no geometry a clearly named `FallbackCapsule` is shown and a warning is logged (not the case since `characters/human.glb` exists).
`player.weapons` = `WeaponController` child "Weapons".

### Movement (m/s)
walk 2.0 (Alt, or analog < 0.55) · run 4.8 · sprint 7.6 (Shift, stamina) · crouch 2.1 (C / Ctrl toggle, headroom checked) · aim/strafe 3.0 · swim 2.6 / fast 4.2 / dive 2.6.
Acceleration 26 m/s^2, deceleration 34, air control 5. Camera-relative movement; the body turns to the move direction (13 /s) and faces the camera when aiming, firing a ranged weapon or in first person.
Jump: 1.15 m (sprint jump +6%), coyote time 0.12 s, buffer 0.12 s, releasing the key early shortens the hop. Gravity 24. Step-up 0.45 m (stairs / curbs), floor snap 0.4 m, max slope 50 deg.
Landing: `fall drop` = peak height - landing height. Free up to 4 m, then 8.4 HP per metre (>= 16 m kills from 100 HP), armor does not absorb it; > 6.5 m also ragdolls the player (`ragdoll_for`), no damage when landing in > 0.6 m of water.
Stamina: 100, sprint drains 15/s, regen 24/s after 0.9 s; after exhaustion sprint stays locked until 25. Skills `stamina` stretch it.
Footsteps: stride-based `Sfx.play_3d(&"step_<surface>")` (concrete / grass / sand / wood / water; surface from collider meta `surface` (up to 3 parents), piers = wood, district beach = sand / park = grass); silent when the sound does not exist.
`noise_radius` (m) is now published by `PlayerStealth` (see `docs/api/player_advanced.md`: foot / swim / vehicle / melee / gunshot incl. suppressor; plus `visibility01`, `detection_range`, `get_visibility_from(pos)`).

### Water
Water is detected by (a) `Area3D` volumes on `GC.L_WATER` overlapping the player's sensor (surface = meta `surface_y`, else the top of its `BoxShape3D`, else `GC.WATER_LEVEL`) or (b) `WorldLayout.is_water(x,z)` (surface `GC.WATER_LEVEL`).
Wading (feet below the surface): slower, `step_water`. Swimming starts when the water column is deeper than 1.3 m and the feet are > 0.25 m under the surface (hysteresis 1.05 m on the way out).
Surface swim: the body origin sits 0.9 m below the surface, bobbing; Space = rise / climb out onto a ledge up to ~3 m above the water (quays), C / Ctrl (hold) = dive, looking down while moving dives too.
`head_underwater` (lungs drain), `is_underwater` (**camera** below the surface: Environment / Audio post effect flag, set by PlayerCamera), `water_surface_y` (NAN when dry).
Lungs 20 s (`lung_capacity()`, skill `lung` extends it; scuba drains at 0.04x), `_update_lungs` runs every tick (full lung stays full when the capacity changes, so the HUD air bar no longer shows at spawn), refill 6 /s at the surface / 14 /s on land, then drowning damage 12 HP/s (ignores armor). Cheats `infinite_lungs` / `scuba` disable the drain. The weapon is holstered while swimming and redrawn afterwards.
HUD-readable fields: `stamina` + `max_stamina`, `lungs` + `max_lungs`, `crouching`, `noise_radius`, `head_underwater`, `is_swimming`, `sprinting`, `aiming`, `wading_depth`.

### Weapons wiring (all through the WeaponController API, duck typed)
LMB `fire` -> `set_trigger`, RMB `aim` -> `set_aiming`, `reload`, wheel `weapon_next/prev` (while a scope is active the wheel calls `cycle_zoom`), keys 1..9 -> `equip_slot(n)`, `grenade` -> `throw_grenade`,
`melee` (X): tap = light, hold > 0.28 s = heavy -> `melee_attack(heavy)`; behind an unaware NPC (within 2.6 m, facing away) = silent takedown via `PlayerStealth` (knife kill, otherwise knock-out; hold X flips). `flashlight` (T) -> weapon flashlight when the model has one, else a head torch SpotLight on the camera.
`look_back` (B) on foot = `toggle_fire_mode()`; Shift while scoped = `hold_breath`. Every physics tick the camera centre ray is passed to `set_aim_ray(origin, dir)` (origin pushed forward to the player's plane so geometry behind the player cannot block shots), also while driving.
The rig gets `set_aim(active, camera_pitch, yaw_offset)`, `look_at_point(aim point)`, `set_weapon_pose` (on `Events.weapon_changed`), `set_grounded`, `set_steering` (seated).

### Vehicles
`F` (`enter_exit`): on foot -> `vehicle.enter_vehicle(veh, 0)` (driver seat; occupied = carjack, handled by `VehicleBase.request_enter`); seated -> `vehicle.exit(player)`.
While seated (`move_mode == VEHICLE`) `player.current_vehicle` is set by the vehicle (`set_vehicle`); the vehicle re-parents the body under its seat anchor; the player forwards input each physics tick:
cars / bikes / boats: `input_throttle` (W), `input_brake` (S), `input_steer` (A/D raw, the vehicle smooths), `input_handbrake` (Space), `input_horn` (H hold), `toggle_headlights` (L), `toggle_siren` (N); bikes: Shift = `input_pitch` +1 (wheelie), C = -1 (stoppie).
Aircraft (`vclass` heli / plane): `input_pitch/roll/yaw` from the `air_*` actions, helicopter `input_collective` (Shift/Space up, Ctrl down), plane `input_throttle` integrated from `air_throttle_up/down`.
Drive-by: when `vehicle.can_shoot_from_seat(seat)` and `weapons.can_fire_from_vehicle()`, RMB aims (camera free-look from the vehicle) and LMB fires.
Camera: `VehicleBase.get_camera_hints()` -> `distance`, `height`, `look_ahead`, `fov`, `first_person_offset`; heading-following with drift blend, mouse look-around that decays after 1.7 s idle, `B` = look back, `V` = hood camera (first person).

### Death / arrest / respawn
`apply_damage` -> `die()` (CharacterBase) -> `_on_death`: forced vehicle exit, rig ragdoll (`rig.start_ragdoll(impulse)`), collider off, `Events.player_died`, death camera (orbit around the ragdoll). After `DEATH_RESPAWN_DELAY` = 3.7 **real** seconds (the UI slows time while the death screen runs, so timers use `dt / Engine.time_scale`):
`respawn_at(&"hospital", {penalty: min($500, cash)})`. `Player.arrest(by)` (call from police): hands up, `Events.player_busted`, after 2.9 s -> `respawn_at(&"police_station", {penalty: 10% of cash (100..1000), confiscate_ammo: 0.5})`.
`respawn_at(location_id, opts)` (also `PlayerSystem.respawn_at`): opts `penalty:int`, `reason`, `confiscate_ammo:float` (fraction of reserve ammo lost), `silent:bool`, `keep_health:bool`. It revives (full health, armor 0 after death / bust), keeps the weapons, clears wanted (`Game.sys(&"wanted").clear()`), teleports to the location (fallback `player_spawn`, then `(0,2,0)`), grants 2 s spawn protection, emits `Events.player_respawned(pos)` and `fade_requested(false, 0.9)`.
Fade: the UI's `DeathScreen` owns the real fade; `PlayerSystem` only draws its own black overlay (layer 90) when `Game.ui` has no `fade()`.
`respawn_started(location, reason)` / `respawned(pos)` signals exist on the Player.
Safety net: falling below y = -120 outside water respawns at `player_spawn` (with a warning).

### Traversal & cover (headless-tested, visually verified for ladder-less cases)
* **Vault / mantle** (Space while moving into a 0.52 - 2.3 m obstacle): thin obstacle <= 1.25 m with a free landing -> vault; otherwise mantle on top (clearance checked with a capsule). **Climb out of water** onto quays (<= 3.1 m above the swimmer).
* **Ladder**: `player.traversal.start_ladder(bottom, top, face_dir)` - W/S climb (Shift faster), Space jumps off, climbs off at the top / bottom. No ladder props exist yet; world content should call this from the ladder's `interact(player)`.
* **Parachute**: `player.has_parachute = true` (pickup locations call `player.has_parachute = true`; `Game.cheats["parachute"]` also works). Space in the air above 7 m with fall speed > 5.5 m/s opens a procedural canopy (4.6 m/s descent, steer with camera + A/D, S brakes); Space again cuts away; no fall damage under canopy.
* **Cover (Q)**: finds a wall (ray fan around the camera yaw) or low cover 0.7 - 1.3 m, snaps against it, A/D slide along it, stops at corners, RMB aims out (rig `set_cover_peek`), LMB without aim = blind fire (`weapons.set_blind_fire(true)` when the weapon controller supports it). Leaves on Q, sprint, back-press, or jump (vaults low cover).
* **Ragdoll hook**: `player.ragdoll_for(seconds, impulse)`; the body follows the ragdoll position, then gets up.

## PlayerCamera (`Game.gameplay_camera`)
Third-person orbit 3.45 m (sprint 3.8, crouch 3.0, swim 4.0), over-the-shoulder offset 0.38 m (swap with Z or `camera.swap_shoulder()`), aim camera (RMB) 1.65 m / shoulder 0.62 / FOV x0.8, sprint FOV +7, first person (V, `camera.first_person`; head hidden through `rig.set_first_person`).
Collision: sphere cast (r 0.22) from the head pivot against `GC.M_CAMERA`, snaps in fast (45 /s) and eases out (3.5 /s); the rig hides when the camera is closer than 0.75 m. Mouse sensitivity / invert from `Game.settings` (`mouse_sensitivity`, `invert_y`, `fov`, `camera_shake`).
Mouse is captured while playing and released when `Game.ui.is_menu_open()` or paused (no UI: Esc releases, click recaptures).
Public API: `yaw`, `pitch`, `mode` (`Mode.FOLLOW/VEHICLE/AIRCRAFT/DEATH`), `get_aim_forward()`, `get_aim_origin()`, `first_person_active()`, `toggle_first_person()`, `swap_shoulder()`,
`add_shake(strength 0..1, seconds)` (auto from `Events.explosion`, `vehicle_collision` of the driven vehicle, player hurt, landings, nearby gunshots), `add_recoil(pitch_up_rad, yaw_rad)` (the WeaponController already calls it), `set_fov_override(deg)` / `clear_fov_override()` (scopes), `set_flashlight(on)`, `snap_behind(yaw)`.
Weapon scope sway (`weapons.scope_sway`) is applied to the aim.
The physics-interpolated player / vehicle positions are used for the follow point (the camera and `Player.visual` have engine physics interpolation OFF and interpolate by hand, which removes the engine warning), so the camera is jitter free at any display rate.

## Interaction
`PlayerInteraction` scans every 0.1 s: nodes of group `interactable` within `INTERACT_RANGE` 2.5 m (override per node with property / meta `interact_range`), |dy| < 2.6 m, in front (dot > -0.25), score = distance - 0.8 * facing; nodes need `get_interaction(player) -> {text, key, enabled}` and `interact(player)`.
Enterable vehicles (group `vehicle`) within 3.2 m of their body box. The prompt goes out through `Events.interaction_prompt(text)` as ONE line ("[E] Buy weapons     [F] Enter Marlin Sedan"; the vehicle text comes from `VehicleBase.get_interaction`), `""` hides it. Prompts hide while seated, dead, in a menu or during traversal.

## Events
Emits: `player_died`, `player_busted`, `player_respawned`, `interaction_prompt`, `projectile_impact(pos, UP, &"water", player)` on hard water entry, damage through the damage contract (`DMG_FALL`, `DMG_DROWN`), `notification` on respawn.
Listens: `weapon_changed`, `vehicle_exited`, `explosion`, `vehicle_collision`, `gunshot`.
Signals on the Player: `landed(drop, damage)`, `stance_changed`, `swim_changed`, `respawn_started`, `respawned`, `fade_requested`, `traversal_started`.

## Public API cheat sheet
`Player`: `respawn_at(id, opts)`, `arrest(by)`, `teleport_to(pos, yaw)`, `ragdoll_for(s, impulse)`, `melee(heavy)`, `throw_grenade()`, `stow_weapon()/unstow_weapon()`, `stealth_takedown()`, `get_stamina01()`, `get_lung01()`, `lung_capacity()`, `get_noise_radius()`, `get_visual_position()`, `is_on_foot()`, `serialize()/deserialize()` (health, armor, position, weapons), `move_mode` (`Player.Move.*`), `stance`, `input_locked` (cutscenes).
Test / scripting input: `set_input(move, sprint, aim, walk)`, `press_jump()`, `press_crouch()`, `release_input()`, `use_real_input`, `move_yaw_override`.
Tunables are constants at the top of `player.gd` (speeds, gravity, jump, fall damage, stamina, lungs, swim depths, respawn delays) and `player_camera.gd` (distances, offsets, FOV).

## Skills hook (duck typed, optional)
Reads `skills.get_skill01(id)` (also tries `get_level01`, `get_skill_ratio`, `get_skill(id)`) for `stamina`, `lung`, `stealth`; reports use through the first existing of `train / add_xp / record_use / add_progress / use_skill (id, amount)` with ids `stamina` `lung` `stealth` `strength`.
(The SkillsSystem is still a stub at the time of writing, so nothing is trained yet.)

## Known limits
* Hanging from ledges mid-air, dodge / roll, blocking and directional melee reactions are NOT implemented (melee = WeaponController swing + takedown).
* Cover works on any `L_WORLD` / `L_PROP` wall segment; there is no corner-to-corner transition and no AI use yet.
* Passenger entry (seats other than the driver seat) is not exposed on a key (F always takes the wheel).
* Ladders need world props that call `traversal.start_ladder`; parachute pickups must set `has_parachute`.
* Camera: no gamepad look; first person shows the body below the camera (no dedicated viewmodel).
* Input while a vehicle is `is_ai_controlled` is ignored (police / traffic own the controls).
