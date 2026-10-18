# Player-Advanced (wave 3) - stealth, cover, traversal, melee, passenger / drive-by, first person, parachute, scuba

Second pass on the Player module (owner: Player-Advanced agent). Base module: `docs/api/player.md`, rig: `docs/api/character_rig.md`.
Files added / changed under `gta/code/player/`; tests `gta/tests/player_adv_test.gd` (+ `player_adv_shots.gd` for screenshots).

STATUS (final for this session - the lead ended the wave early, so only stealth + the two bug fixes were completed):

| area | state |
|---|---|
| lung bar at spawn | FIXED, headless-tested (`lungs_full_at_rest`, `hud_air_bar_hidden_at_spawn`) |
| 'Interpolated Camera3D triggered from outside physics process' | FIXED (interpolation mode OFF on camera + visual); property-tested only, no 144 fps visual jitter run was done |
| stealth: noise model, visibility score, per-viewer visibility, detection range | WORKING (headless, 20 asserts) |
| stealth takedown from behind (fists / blunt = knock-out, knife = kill, hold X flips) | WORKING headless with a dummy NPC; NOT yet run against real pedestrians / police in the full city, no screenshot |
| scuba air drain (`has_scuba` -> 0.04x, cheats scuba / infinite_lungs -> 0) | WORKING (code path, not separately asserted) |
| cover corner transitions, vault from cover, vehicle cover, blind-fire penalty, peek camera, AI sharing `CoverFinder` | NOT IMPLEMENTED (wave-1 cover unchanged) |
| ladder verification, dodge / roll, landing reactions, ledge hang | NOT IMPLEMENTED (ladders are driven by Systems-A through `traversal.start_ladder`, tested by them) |
| melee block, finisher, directional reactions, knockdown | NOT IMPLEMENTED beyond the takedown (weapons module still provides light / heavy / combo knockdown) |
| passenger entry (`enter_as_passenger`), drive-by verification | NOT IMPLEMENTED (F still takes the driver seat; passenger seats already tick `_tick_passenger` -> drive-by) |
| first-person arms / ADS / cockpit view | NOT IMPLEMENTED (wave-1 FP: head hidden, body visible below the camera) |
| parachute canopy GLB / flare / base-jump verification | NOT IMPLEMENTED (procedural canopy from wave 1 still used; `props/parachute_canopy.glb` and `parachute_pack.glb` exist and are unused) |
| gamepad | NOT IMPLEMENTED |

## 1. Bug fixes
* **Air bar at spawn.** `Player.lungs` started at 20 s while `max_lungs` (= `lung_capacity()`) grows with the `lung` skill, which only exists after the skills system boots,
  so the HUD saw `lungs < max_lungs` and drew the air bar. `_update_lungs()` now runs every physics tick in every move mode: a full lung stays full when the capacity changes,
  dry land refills 14 /s, swimming at the surface 6 /s. The HUD (unchanged) shows the bar only while `head_underwater` or `lungs < max_lungs`.
* **'Interpolated Camera3D triggered from outside physics process'.** `PlayerCamera` and `Player.visual` now have `physics_interpolation_mode = OFF`: both are placed in `_process`
  from targets that are already interpolated by hand (`Player.get_visual_position()`, the vehicle prev / curr pair and `Engine.get_physics_interpolation_fraction()`), so nothing is smoothed twice.

## 2. Stealth (`player_stealth.gd`, `class_name PlayerStealth`, child "Stealth" of the Player)
Published on `Game.player` every physics tick (peds / police / gangs may read them duck-typed; none of them is required to):

| member | meaning |
|---|---|
| `noise_radius` | metres within which the player can be HEARD right now. still 0 / crouch-walk 2 (x`get_modifier(&"noise")`, stealth skill -45 %) / walk 5 / run 8 / sprint 13 (x0.8 on grass, sand, dirt; x1.2 on wood, metal; x0.85 in rain) / swim surface 6, underwater 1.5 / vehicle 10 + km/h / 5 (max 36) / cover move 2.2 / ladder, mantle 3.5 / landing spike up to 14 / melee swing 7, connected blow 18 / gunshot = the weapon's loudness incl. suppressor (pistol 65 m, suppressed x0.25) held 0.35 s then decaying linearly over 1.8 s / takedown <= 2.5 |
| `visibility01` | 0..1 conspicuousness at close range = light x posture x motion + muzzle flash. light: 1 - 0.8 x gloom (`EnvironmentSystem.get_gloom()`, fallback `Game.daylight()`), + street lamps within 12 m, + torch, 0.75 inside interiors (y < -100). posture: stand 1, crouch 0.62, sprint 1.2, aiming x1.1, cover 0.45-0.62, swimming 0.85, underwater 0.3, vehicle 0.9. motion: 0.8 standing still .. 1.0 at 4 m/s. muzzle flash +0.45 (suppressed +0.12) fading in 1.2 s |
| `detection_range` | metres at which a viewer WITH line of sight can notice the player: `lerp(6, 75, visibility01^0.8)` x (1 - 0.35 fog - 0.15 rain). Standing in daylight ~64 m, crouching at night ~15-22 m |
| `stealth_exposed` | `visibility01 >= 0.55` |
| `get_visibility_from(viewer_pos) -> float` | per-viewer score: 0 beyond the detection range, falls off with distance, x0.2 when the viewer is on the wall side of the current cover, x0.6 for high cover seen from the flank |
| `takedown_target` | the NPC a press of X would silently take down right now (or null) |

Suggested NPC rule: `sees = LOS and dist < player.detection_range` (optionally scale a reaction timer by `get_visibility_from`), `hears = dist < player.noise_radius` (no LOS needed).
`Events.gunshot` is still emitted by the weapon controller for shots (loudness = audible radius, suppressors included); melee takedowns emit NO gunshot.

**Takedown from behind.** X (`melee`) with an unaware NPC within 2.6 m, in front of the player, facing away (`vf . dir_to_victim > 0.12`), line of sight, player on foot and not sprinting.
"Unaware" (`PlayerStealth.is_unaware(node)`, static, duck typed): alive, not knocked down, not panicked / fleeing (`is_panicked()`, `is_fleeing()`, `panic > 0.25`),
`brain.target_visible == false` and `brain.state` in IDLE / SEARCH / HOLD for CombatBrain NPCs (police, gang), `provoked == false`.
Knife = silent kill (`apply_damage(1000, {zone head, silent, stealth, weapon &"takedown"})`); fists / bat / firearms = knock-out (`apply_damage(1)` + `knock_down(impulse, 9 s)`; hold X flips kill <-> knock-out.
The player glides behind the victim (0.85 m), the rig plays `melee_swing` (blades / blunt) or `punch`. The interaction prompt shows `[X] Silent kill (hold: knock out)` / `[X] Knock out (hold: kill)`.
Crimes and witnesses are left to WantedSystem (it derives them from the damage / death events as for any other kill).

## 3. Tests
`gta/tests/player_adv_test.gd` (`--only=bugs,stealth,takedown,...`): see the PASS lines; run
`powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/player_adv_test.gd -Seconds 200 -GameArgs "--no-traffic --no-peds --no-hostiles"`.

## 4. Backlog / known limits
* Everything marked NOT IMPLEMENTED in the table above. Suggested next steps in priority order: passenger entry (hold F near a door -> `request_enter(player, seat)` + `enter_as_passenger(vehicle, seat)` wrapper), cover corner transitions + AI reuse of `ai/cover_finder.gd`,
  canopy / pack GLBs in `PlayerTraversal._build_canopy` (canopy GLB: origin at the harness point, height 7.5 m, nodes `Body`, `Lines`, `Attach`), FP arms, melee block / dodge roll.
* Peds, police and gang AI do NOT read `noise_radius` / `visibility01` / `detection_range` yet (they have their own perception); the values are published for them. `CombatBrain` hearing uses `Events.gunshot` only.
* The takedown only recognises NPCs through duck typing (`is_dead`, `is_knocked_down()`, `is_panicked()`, `is_fleeing()`, `panic`, `brain.target_visible`, `brain.state`, `provoked`); a ped whose `brain` is a RefCounted without these members is treated as unaware.
* Takedown knock-out uses `knock_down(impulse, 9.0)` (Pedestrian / PoliceOfficer / GangNpc all implement it); other characters fall back to `rig.start_ragdoll`.
* No new InputMap actions were added; no edits outside `gta/code/player/*`, `gta/tests/player_adv_test.gd`, `docs/api/player_advanced.md`.
