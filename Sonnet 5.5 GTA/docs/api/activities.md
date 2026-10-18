# Activities (Activities agent) - optional free-roam activities, NEVER missions

Owner files: `gta/code/systems/activity_*.gd` (11 files), tests `gta/tests/activity_test.gd` (+ `activity_probe.gd` world probe), this doc.
`Game.sys(&"activities")` = `ActivitySystem` (boot key `activities`). Check: `tools\gd.ps1 check` -> VALIDATE OK (407 files, 0 fails).

## 1. Design
* Activities start ONLY when the player deliberately interacts: `[E] Shooting Range`, `[E] Ring Street Race` (an `ActivityPoint`, group `interactable`, so
  the Player's normal interaction scan shows the prompt). Stunt jumps are passive (drive up the ramp).
* One active activity at a time. State machine `IDLE -> COUNTDOWN -> RUNNING -> FINISHED | ABORTED -> IDLE` (`ActivitySystem.State`).
* Quit any time: hold E for 0.9 s (must be released once after the start). Auto abort: player dead / busted, left the area, left the vehicle (races),
  vehicle destroyed, each activity's `check_abort()`.
* Never gates progress. Rewards: small cash ($50-300 range, $100-500 race, $400 first / $60 repeat per stunt jump, repeat plays at the same medal pay half)
  + skill use (`Game.sys(&"skills").record`): shooting, driving.
* Best scores / medals / first-time flags persist through `serialize()` / `deserialize()` (SaveSystem: `systems/activities`).
* Map: the range and the three stunt jumps already have `UIIcons.LOC` icons; the race registers `WorldLayout.locations[&"race_start"]` at runtime and
  `ui_icons.gd` got one additive line (`&"race_start"`). Start markers (`ActivityMarker`: neon ground ring + spinning ring + faint pillar) are visible only within 60 m.

## 2. API (`ActivitySystem`)
`activities: Dictionary` (id -> `ActivityBase`), `get_activity(id)`, `start(id, opts := {"option": "pistol"}) -> bool`, `abort(reason, act := null)`,
`complete(act, result)`, `complete_passive(act, result)`, `state`, `active`, `is_active()`, `best` (key -> {value, medal, plays}), `flags`, `hud: ActivityHud`,
`play_sfx(id)`, `best_text(key)`, signals `state_changed(state, id)`, `activity_finished(id, result)`, `activity_aborted(id, reason)`. `ready_ok` is true once the
activities were built (they wait for `WorldLayout.built` + 6 physics frames). Game meta `activity_active` (id) while one runs.
`ActivityBase` (extend it to add an activity): hooks `setup_activity can_start prompt_text begin on_go tick check_abort on_abort cleanup poll_passive marker_spots`,
helpers `finish_activity(result)`, `abort_activity(reason)`, `medal_for(value, gold, silver, bronze, higher_better)`, `cash_for(medal, table)`.
Result dictionary: `key value higher_better medal cash skill{} title subtitle main rows[[label,value,Color]] hint`.
`ActivityHud` (reusable widget, CanvasLayer 9): `begin(title, sub, color)`, `set_cells/set_cell`, `set_progress`, `banner`, `countdown`, `popup`, `show_results`, `ActivityHud.format_time`, `ActivityHud.group`.
`ActivityMenu` (`MenuBase`, id `activity`): pre-start option list (weapon set / vehicle). `ActivitySfx`: procedural beeps / chimes (AudioStreamWAV, no files).

## 3. Activities
| id | file | what |
|---|---|---|
| `shooting_range` | `activity_range.gd`, `activity_target.gd` | 3 rounds of pop-up targets at the `shooting_range` landmark (stands at 10/15/20/25 m placed from the GLB `Lane_*/Target_*` empties, hostile silhouettes, bullseye plates, cyan civilian no-shoot silhouettes), real bullets: `ActivityTarget` is a `damageable` AnimatableBody3D with a trimesh on the `Plate`, scoring from the hit position in plate space (head 120/150, bull 100, rings 85/70/55, round plate rings 40-100), speed bonus, accuracy, civilian penalty -150, medal gold/silver/bronze, loaned weapon (pistol / SMG / rifle / shotgun / own), inventory snapshot restored afterwards, explosives removed while active |
| `stunt_jumps` | `activity_stunt.gd` | passive detector for `stunt_jump_1..3` (cars and bikes): armed on the ramp at >= 8 m/s, airborne tracking (airtime, distance, rotation), landing check (upright, not destroyed, inside the landing radius), toast + banner + popup, $400 first time / $60 repeat, Driving skill |
| `street_race` | `activity_race.gd` | 2 laps of the Halcyon Ring (828 m/lap, 10 checkpoints/lap built from the `Halcyon Ring` road polylines), `race_checkpoint` rings (next bright, next-next dim), `finish_line_banner` on the line, 3-2-1 countdown, loaned sports car / muscle car / motorcycle, lap + checkpoint counters, flipped car reset (+5 s), off-route warning (abort after 25 s), medals by time |
Police: `WantedSystem._at_shooting_range()` (existing hook, 28 m around the `shooting_range` location) ignores gunshots there; `ActivityRange` also keeps Game meta `gun_range_zone` true within 60 m of the lane.

## 4. Tunables
`ActivityRange.ROUNDS / SETS / MEDAL_SCORES / CASH / CIV_PENALTY / FIRE_FORWARD`, `ActivityStunt.MIN_SPEED / MIN_AIR / MIN_DIST / LAND_RADIUS / FIRST_CASH`,
`ActivityRace.LAPS / CP_SPACING / PASS_RADIUS / GOLD_SPEED / SILVER_SPEED / BRONZE_SPEED / CASH`, `ActivitySystem.QUIT_HOLD / RESULT_SECONDS`.

## 5. Status (verified by `gta/tests/activity_test.gd`, headless `exec`, `--part=basic|range|stunt|race`)
* basic (18/18): registry, save round trip + tolerant load, medal maths, interaction points, race map location, target ring scoring with fake hits, state machine
  (start/abort/idle, one at a time), weapons restored after abort, leaving the area aborts.
* range, real bullets through `WeaponController` (bot aims the player camera, ADS + trigger): 47 shots, 46 hits, 3776 pts = gold, $300 + 5000 -> 5300, shooting skill recorded, best saved, weapons restored.
* stunt jumps with the real sports car on the real ramps: jump 2 (concrete run-up) 133 km/h, 52 m, 1.57 s air, landed OK, $400; jump 1 (36 m grass run-up) 18 m, 1.05 s air, landed OK.
* race with a driving bot (22 m/s cap, pure pursuit on the road polyline): 20/20 checkpoints, 76.0 s, gold; medal times 78 / 95 / 120 s.
## 6. Limits / NOT done
* Not visually reviewed (no screenshots were taken in this wave): the range HUD, results card, markers, rings and banner are untested on a real renderer.
* Stunt jump 3 (beach pier into the sea) and bikes on the ramps are implemented but NOT driven in a test; jump 1 needs a car with ~36 m of run-up on the grass.
* Hip-firing at the range from behind the counter is blocked by its 1.07 m collider (found with the bot): the player is placed 1.25 m in front of `Lane_3` instead.
* The race uses a loaned vehicle (the player's own vehicle is not used), no AI rivals and no ghost; the best time is shown in the menu only.
* NOT IMPLEMENTED: sea race, airfield race, off-road/hill time trial, triathlon, base-jump / parachute challenge, golf, darts. No `Events` signals were added.
