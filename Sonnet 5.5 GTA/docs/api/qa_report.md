# QA report (cross-cutting QA + fixes agent, wave 3) - `docs/api/qa_report.md`

Scope was cut by the lead mid-run (usage limit): the known-defect fixes were done and verified, the long play-test scenarios A-H and the 10-minute
soak were NOT run (listed below as "not run"). Tests: `gta/tests/qa_core_test.gd` (exec, `--only=booths,heli,arrest`), `gta/tests/vehicle_interact_test.gd`.

```
powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/qa_core_test.gd -Seconds 170 -GameArgs "--no-traffic --no-peds --no-hostiles"
powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/vehicle_interact_test.gd -Seconds 120 -GameArgs "--no-vehicles --no-traffic --no-peds"
```

## Known defects

| # | defect | fix | verified |
|---|---|---|---|
| 1 | AudioSystem `_on_character_damaged/_died`: `_is_female(freed node)` after an `await`; same pattern in vehicle door/horn handlers | gender is read BEFORE the await; `is_instance_valid(vehicle)` after every await (`audio_system.gd` ~807-868) | 25 s full-game headless boot + `vehicle_interact_test` (49/49): no "previously freed" lines. NOT re-run against a ped-killing test, so the damaged/died path itself is only code-reviewed |
| 1b | `Sfx` "Cannot call method 'lock' on a null value" at exit | `_ensure`, `_gen_item`, `is_sound_ready` return early when `_mutex == null` (`sfx.gd`) | boot/exit logs of the runs above contain no `lock` error (the error was never reproduced on demand, so this is a guard, not a confirmed root cause) |
| 1c | `CombatBrain._chest` / `PedBrain._decide` + `react` / pend_src with freed nodes | `_chest(c)` untyped + `is_instance_valid`; `_decide/react` take an untyped source and null it when freed; the delayed-reaction source is validated | code only (compiles, ran in the arrest scenario with real officers: no script errors) |
| 2 | `plane_vehicle.setup_air` `global_position` before the node is in the tree (`!is_inside_tree()` at boot) | `takeoff_x = global_position.x if is_inside_tree() else transform.origin.x` | the boot log before the fix had 2 such errors from `setup_air`; the 25 s boot after the fix has none. A third `!is_inside_tree()` line (get_global_transform, no GDScript frame) still appears at exit in some runs: NOT from `plane_vehicle`/`minimap` as far as the backtrace shows (see remaining issues) |
| 3 | `TrafficDriver` kept stale `lead_node` and tested it with `is` | `_lead_veh()` accessor validates + clears (`traffic_driver.gd`); the scan loop already checked `is_instance_valid` | code + boot; the junction (105, 85) stall re-run was NOT done (see 4) |
| 4 | phone booth at (98.6, 86.2), 0.8 m from a lane | `InteractionUtil.lane_distance/lane_clear` (distance to lane CENTRE LINES, segment based), `InteractionProps.LANE_CLEARANCE = 2.6` m rejects candidates in `plan_phone_booths` | `qa_core_test`: 9/9 booths placed, nearest lane centre line 2.71 m; the old spot measures 0.77 m (PASS both). Traffic-junction stall test not re-run |
| 5 | `vehicle_interact_test mods_effects` | test aligned to the real table (`gta/resources/data/vehicle_mods.gd` merged over `VehicleDefs.MOD_EFFECTS`): engine 4 = x1.35, turbo = separate +24 % boost (`mod_turbo_boost`, peak x1.67), brakes x1.40, armour x0.5, mass 1276 | `vehicle_interact_test` 49/49 PASS |
| 6 | police heli searchlight cone veils the screen | cone fades out when the camera is inside the beam volume (+7 m margin) or within 40-75 m of the lamp (`air_searchlight._camera_cone_visibility`); softer base / near-apex alpha; pursue now keeps a 56 m stand-off ring (`PoliceHeliAI.pursue_min_radius`, `AirAutopilot.follow_min_radius`, slow orbit around a stationary target), 58 m up, 58 m trail; search orbit radius >= 56 m | `qa_core_test heli_standoff_ring` PASS: stationary player, heli spawned directly overhead, 52 m closest horizontal distance after the settle. The dusk wanted-3 SCREENSHOT of the cone was NOT taken (no time): visual check outstanding |
| 7 | police 1-star reliability | (a) first foot officer at level <= 2 is spawned 45-72 m from the player (out of view) when a site exists (`PoliceManager.FIRST_FOOT_MIN/MAX`); (b) `WantedSystem` postpones "wanted level lost" up to 30 s (`CLEAR_HOLD_MAX`) while a living foot officer within 110 m is still working the case; (c) `PoliceOfficer._closein_watchdog`: a foot suspect that is not getting closer by 3 m for 6 s (`STANDOFF_S`) makes the officer drop cover, learn the suspect's position and sprint (APPROACH) for 8 s. Foot speeds were already 5.2 run / 6.5 sprint in the code (the old 3.2 m/s in the docs is outdated) | `qa_core_test one_star_standstill_arrest` PASS: standing player at `player_spawn`, `set_level(1)`, BUSTED by real officers after 28.8 s (no clear before the arrest). NOT verified: that the near-spawn was used (the first registered officer was 148 m away - probably the cruiser crew), that the watchdog fired (`PoliceOfficer.standoff_breaks` counts it), crossing roads without waiting, stuck cars on street furniture, spawn hitches 6-23 ms (no pre-warm pool added), the 3-star dusk chase screenshot |
| 8 | minimap empty circle indoors | the UI agent implemented it in `ui/minimap.gd` meanwhile (dimmed map around the last street position + INTERIOR label via `Game.get_meta(&"indoors")`); my parallel edit was backed out. Sun-shadow pass indoors is the Environment agent's (`EnvironmentSystem` rewrites `sun.visible` every frame) | not verified by me |
| 9 | whole-suite sweep | NOT run | - |

## Play-test scenarios
A (walk/drive/shoot/2 stars/escape), B (steal police car, roadblock, arrest flow beyond the 1-star arrest above), C (death/hospital), D (save/load mid-chase),
E (10 interiors), F (helicopter flight), G (swim/dive), H (10-minute soak, error census before/after): **not run** (lead cut the scope). Only the
1-star standstill arrest (part of B/A) and the heli overwatch were exercised end to end.

## Error census (25 s full-game headless boot)
Before: `plane_vehicle.gd:153` `!is_inside_tree()` x2 (boot), `!is_inside_tree()` at exit (ui/minimap or plane), Jolt/Renderer RID leaks at exit, "previously freed" in
`_on_character_damaged/_died` in ped-killing tests, `Sfx` mutex null at exit in `--script` runs.
After: the two `setup_air` errors and the freed-node errors are gone from the boot/vehicle/arrest runs; the RID / ObjectDB "leaked at exit" lines (engine shutdown of a
headless run, 15-21 Jolt shapes, ~480-590 ObjectDB instances) and one exit-time `!is_inside_tree()` without a GDScript frame remain.

## Remaining issues by owner
- **Wildlife / Activities / Debug agents (in flight)**: `tools\gd.ps1 check` currently fails only on their files (`systems/animal_anim.gd`, `activity_system.gd`, `activity_range.gd`, `activity_stunt.gd`, `debug/debug_selfcheck.gd`; parse errors "Cannot infer the type of ...", missing `WildlifeBrain` / `FillAnimator` / `ActivitySystem._group()`), and `Main` logs `system 'activities' failed to load` while that file is broken. None of these are in QA-owned files. (Another activities agent asked by message who writes `activity_*.gd`: it is not me.)
- **World-content**: runs show `Invalid call. Nonexistent function 'landmark_roof_pad' / 'place_hero_lot' / 'reset'` (in-flight refactor of the content builders), unrelated to the QA fixes.
- **Environment**: disable the sun shadow pass while `Game.get_meta(&"indoors")`.
- **Police-B / Vehicles (open from the brief, not done)**: police cars stuck on alley bins (needs a stuck-recovery test in the alley around (-5..26, -55)), spawn hitches (patrol car 6-10 ms, roadblock 15 ms: pre-warm in `post_setup`), officers do not wait at crossings.
- **Visual**: dusk 3-star chase shot with the cone fade (police car behind, heli overhead, flashing stars in SEARCH) still to be taken: `gta/tests/police_director_shots.gd`.

## Shared-file edits (outside the strict ownership list, all minimal)
`gta/code/npc/ped_brain.gd` (`react`/`_decide` freed-source tolerance, pend_src validation), `gta/code/systems/interaction_util.gd` + `interaction_props.gd`
(lane clearance), `gta/code/audio/sfx.gd` (mutex null guards). Everything else is in owned areas (audio_system, plane_vehicle, air_*, police_heli_ai,
traffic_driver, police/*, ai/combat_brain, tests).
