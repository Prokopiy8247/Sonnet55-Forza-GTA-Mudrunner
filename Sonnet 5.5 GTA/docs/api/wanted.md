# Wanted + Police director (Police-A) - `docs/api/wanted.md`

Files (all `gta/code/police/`): `wanted_system.gd` (WantedSystem, boot key `wanted`), `police_manager.gd` (PoliceManager, boot key `police`),
`police_director.gd` (PoliceDirector, decision logic, RefCounted), `crime_rules.gd` (CrimeRules, tunable data), `roadblock_planner.gd`
(RoadblockPlanner). Tests: `gta/tests/wanted_test.gd`, `police_director_test.gd` (+ `wanted_mock.gd` mock units).
Police-B (units) owns `police_units.gd`, `police_officer.gd`, `police_car_ai.gd`, `police_roadblock.gd`, `spike_strip.gd`; the director only calls
`PoliceUnits.spawn_*`/`despawn` and `unit.set_order(order)` (vehicles: meta `police_ai`).

> Resume note: section 5 "Status / what is left" at the bottom is refreshed at every milestone (last: end of the resumed run).

## 1. WantedSystem (`Game.sys(&"wanted")`)

State: `level` 0..5, `state` (`&"clear" &"pursuit" &"search"`), `heat`, `search_radius`, `last_known`. Mirrors `Game.wanted_level / wanted_state`
and emits `Events.wanted_changed(level, state)` on every change, `Events.wanted_search_progress(0..1)` every tick while searching,
`Events.crime_reported(crime, pos, perpetrator)` when the police learn about a crime.

Public API
- `set_level(n)` (debug/cheat; instant, PURSUIT around the player), `clear()` (instant), `add_wanted(points)`.
- `report_crime(crime, pos, perpetrator := null, seen_by_police := false, severity := 1.0, loudness := -1.0) -> bool`: full pipeline.
- `report_sighting(pos, officer := null)`: units that see the player call this (PURSUIT resumes at once, timer reset).
- `get_last_known_position()`, `get_search_radius()`, `is_player_seen()`, `escape_progress()` (0..1), `get_escape_time_needed()`,
  `get_escape_multiplier()`, `notify_appearance_changed()` (clothes/paint changed; also `Game.set_meta(&"appearance_changed_at", seconds)`),
  `is_busted_pending()`, `get_bust_progress()`, `get_recent_crime_age()`, `get_debug_string()`, `serialize()` / `deserialize(d)`.
- Tests: `manual = true` stops `_physics_process`, drive with `tick(dt)`.

Crime derivation (listens to Events; modules need not emit these): `character_damaged` / `character_died` (source = player: civilians ->
ASSAULT / MURDER, police -> POLICE_ASSAULT / POLICE_KILL, gang/hostile = no crime), `gunshot` (loudness; below `CrimeRules.quiet_loudness` it is quiet),
`explosion`, `vehicle_damaged` / `vehicle_destroyed` (police vehicle destroyed within 12 s of the player damaging it -> POLICE_VEHICLE_DESTROYED),
`vehicle_collision` (player vehicle vs police/traffic vehicle above an impulse), DMG_RUNOVER -> HIT_AND_RUN. Explicit `Events.crime_committed`
(vehicle module): CARJACK, VEHICLE_THEFT, POLICE_VEHICLE_THEFT, AIRCRAFT_THEFT, ROBBERY, VANDALISM, HIT_AND_RUN (`info.severity`, `info.seen_by_police`).
Crimes of the player only. Shooting at the `shooting_range` location is no crime. Crimes inside `bundle_window` (3 s) merge: strongest + 35 % of the rest.

Who knows about a crime
1. Police with line of sight (<= 60 m to the crime or the player): immediate heat + PURSUIT.
2. `broadcast` crimes (police are the victim): immediate, the radio carries it.
3. Civilian witnesses (`PedManager.get_witnesses` + `Pedestrian.witness`, duck-typed; built-in fallback scan if absent): the phone call ends in
   `Events.crime_reported`; the heat then becomes real and the state is SEARCH around the crime. Witness dies first -> no report.
4. Loud crimes (gunshot/explosion): an indirect report after 6-10 s if any pedestrian is in hearing range; police only in range -> they `investigate()`.
5. Nobody: the crime sits in the "unreported" list for 45 s and is applied when a police unit later recognises the player.

State machine: PURSUIT (any unit sees the player: LOS inside day/night sight range, `track_radius` 35 m with LOS, `blind_radius` 14 m without, helicopters
see everywhere in range) -> after `lose_track_time` (6 s) unseen -> SEARCH (stars flash, radius grows `search_growth` m/s) -> escape bar fills only
while truly unseen (x multiplier for interior 2.6 / underwater 2.0 / swimming 1.25 / covered 1.2 / vehicle abandoned > 10 s 1.5 / appearance 1.35,
max 3.6) -> CLEAR (`Game.notify("Wanted level lost")`). Re-sighting = PURSUIT immediately, bar reset. Heat decays during SEARCH so the level drops
by one star at about half of the bar (`search_decay_fraction` 0.40, never below 1 star until the bar is full). Escape time per level: 15 / 25 / 40 / 55 / 75 s.
**Search-area rule** (`search_area_rule`, default on): while the player is still INSIDE the circle the police comb (last known position, `search_radius`), the bar only
advances at `CrimeRules.mult_inside_area` (0.25) unless he is hidden (interior / underwater). Getting out of the circle (it grows 2.4 m/s up to 240 m) is what lets him escape;
a player who just stands at the crime scene is found long before the bar fills.

BUSTED: player on foot, not violent for > 2 s (`bust_quiet_time`), not just hurt, an officer in LOS within 6 m (armed) / 3 m (unarmed), slow, for 1.1 s
(0.5 s when surrendering: unarmed, standing still, no violence for 4 s); in a vehicle: speed < 2.2 and boxed in (foot officer + car, or 3 cars)
for 2.8 s. -> `Game.player.arrest(by)` (fallback `Events.player_busted`). Attacking while the arrest is imminent = CRIME_RESIST_ARREST.
Death / arrest: `Events.player_died` / `player_busted` freeze the system; `player_respawned` -> `clear()`.
Optional 1-star hail: an officer in sight of an unarmed suspect says "Freeze!" via `Events.subtitle`; running away = resisting arrest.
`Game.cheats["never_wanted"]` keeps everything at 0.

## 2. CrimeRules (tunables, all `static var`, change at runtime)

`star_heat` [10,40,90,160,260], `hysteresis` 0.8, `heat_max` 420, `escape_time` [15,25,40,55,75], `search_base` [55..120], `search_growth` 2.4,
`search_radius_max` 240, `search_decay_fraction` 0.95, `repeat_window` 30, `repeat_floor` 0.3, `mult_*` (escape multipliers), `quiet_loudness` 24, and
`rules[GC.CRIME_*] = {heat, min_level, cooldown, broadcast, phone, loud, repeat_decay, label}`.
Instance tunables on WantedSystem: `search_area_rule`, `dedupe_window` (25 s: several witnesses reporting one incident count once), `debug_clear`, `lose_track_time`, `scan_interval`, `sight_range_day/night`, `heli_sight_*`, `track_radius`, `blind_radius`,
`witness_police_range`, `witness_radius`, `indirect_delay_min/max`, `unreported_ttl`, `bust_*`, `bundle_*`, `heat_decay_idle`, `hail_enabled`.

## 3. PoliceManager (`Game.sys(&"police")`) + PoliceDirector

`PoliceDirector.force_table[level] = {cars, vans, foot, swat, heli, blocks, aggr, lethal}`:
1* 1 car + 2 foot, 2* 3 cars + 2 foot (lethal), 3* 4 cars + 3 foot (1 swat) + 1 heli + 1 roadblock, 4* 5 cars + 1 van + 4 foot (3 swat) + heli + 2 blocks,
5* 6 cars + 2 vans + 4 foot (4 swat) + 2 helis + roadblock. SEARCH: 75 % of the cars, not lethal, no NEW roadblocks after the first 25 s of a search
(`ROADBLOCK_SEARCH_WINDOW`; existing blocks stay, the pursuit table decides how many). Hard caps `MAX_VEHICLES` 10, `MAX_OFFICERS` 20 (seated + on foot), `MAX_HELIS` 2, all
counted on the real `police` group (the parked showroom cruiser / van / helicopter and stolen or abandoned police cars are NOT counted: they take no part); `MIN_SPAWN_DIST` 80 m.
Officer budget: a patrol car takes 2 officers, or 1 when the cap would starve the reserve kept for the roadblock (player driving) and the foot team; vans need 4 free slots.

Spawn rules (`find_road_site`): lane-graph point (no junction connector, has a successor), >= 80 m from player AND camera, outside the camera frustum (or
hidden behind world geometry), nothing overlapping (box shape query), >= 28 m from other units; roles `tail` (behind), `intercept` (ahead of the predicted
path), `flank` (side), `block` (rolling blocker at 5 stars); the first response comes from the `police_station` location when 100-450 m away; response
delay 2-8.5 s by distance; staggered 1.4 s; reinforcement wave every 20 s while the target is known. Foot officers spawn on the ped graph.
Roadblocks (3*+, player driving > 6.5 m/s, state PURSUIT): `RoadblockPlanner` walks the lane graph ahead of the heading 190-340 m, straight piece, off-screen,
>= 150 m from the player; `PoliceUnits.spawn_roadblock(center, dir, level)`; removed when the level drops, after 80 s or when passed.
Helicopters: `PoliceHeliAI.spawn(pos)` (resolved by class name; absent = no heli) 230-300 m away, mode via `set_mode/set_target` + `set_order`.
Despawn: dropping force -> surplus units flagged `leaving` one per 2 s (furthest first); leaving units are removed when out of sight and > 60 m; idle > 20 s
out of sight are recycled; units > 300 m away and unseen are recycled once they had 45 s to arrive (a station response starts 100-450 m away); dead units cleaned
after 30 s; everything leaves at level 0.
Orders: pursuit orders are re-sent when they change (mode / target position > 9 m / level) or every 6 s; SEARCH orders (they restart a unit's route) every 15 s. A search order first
converges on the last known position (`radius` 35 m) and widens to the full `search_radius` over 25 s (`CONVERGE_RADIUS`, `CONVERGE_TIME`).
`get_stats()` includes `spawn_ms_max` (slowest PoliceUnits call per kind, ms); `post_setup` pre-resolves PoliceUnits / PoliceHeliAI so the first chase does not compile them.

API: `spawn_units(count, around)` (debug, pinned), `despawn_all()`, `investigate(pos, radius)`, `register_unit(node, role, kind)`, `get_units()`, `get_records()`,
`get_stats()`, `force_for_level(n)`, `set_factory(obj)` (tests: any object with `spawn_officer/spawn_patrol_car/spawn_tactical_van/spawn_roadblock/despawn`),
`heli_spawner` (Callable hook), `manual` + `tick(dt)`.

Order sent to `unit.set_order`: `{mode: pursue|search|hold|patrol|leave, target: Node, pos, radius, aggression 0..1, lethal, role, tactic (tail|pit|box|intercept|flank|block|close_in|overwatch), level}`.

## 4. Interplay with the other modules (facts verified in-game)

- **Police-B units**: orders go through `unit.set_order` (officers) / meta `police_ai` (cars). Officers also arrest on their own (`PoliceOfficer.arrest_enabled`, default true: close, still,
  not aiming); the BUSTED rules of WantedSystem additionally cover armed officers within 6 m, surrender and boxed-in vehicles. Both end in `Player.arrest(by)` -> `Events.player_busted`
  (WantedSystem freezes) -> respawn at the station -> `Events.player_respawned` -> `clear()`.
- **Air**: `PoliceHeliAI.spawn(pos)` is called by class name; `set_mode/set_target` on the vehicle or its child. Known visual issue (Air module): the searchlight cone veils the whole screen
  when the helicopter hovers right over the camera (the screenshot scenes disable helicopters for that reason, `--heli=1` re-enables them).
- **Peds**: `PedManager.get_witnesses` + `Pedestrian.witness` are used as documented (verified with 12-15 real witnesses: report after 4-7 s, one crime counted once, no report when all
  witnesses die).
- **Interiors**: `InteriorSystem` refuses doors while `Game.wanted_state == pursuit`; hiding inside gives the 2.6x escape multiplier. **Shops**: the clothing shop calls `notify_appearance_changed()`.

## 5. Status / what is left

Verified in this run (headless `exec`, `--no-traffic --no-peds` unless noted):
- `wanted_test.gd` 131/131: crimes, witnesses (incl. three witnesses = one crime), indirect reports, timings per level, re-sighting, modifiers, search-area rule, events, bundles, cheat,
  serialize, busted, hail, death.
- `police_director_test.gd` 107/107 with mock units: force table, site rules (>= 80 m, outside frustum, on lane graph), per-level response, orders, calm-down, excess fade-out, idle recycle,
  roadblocks, helis, refusing factory, station response, caps.
- `police_director_live_test.gd` with the real Police-B units, the real PoliceHeliAI and the real PedManager: foot pursuit (officer killed -> 3 stars, units spawned legally, caps respected,
  units reach the player after ~20-30 s), driving pursuit at 4 stars (roadblock 190-250 m ahead after ~20-26 s, tail / intercept / flank roles, 2 helis), escape (SEARCH -> one star less -> CLEAR,
  units leave), arrest by real officers (~30 s), real witnesses. Cost: director avg 12-70 us per physics tick, wanted 16-32 us; slowest factory calls: patrol car 6-10 ms, officer 2-6 ms,
  van 9 ms, roadblock 15 ms, heli 3 ms.
- Screenshots (`gta/tests/police_director_shots.gd`, output in `screenshots/police/`): `pursuit.png` / `hud_search.png` (dusk, 3 stars, HUD in its SEARCHING state with the dimmed, flashing stars),
  `roadblock.png` (4 stars, sunset, roadblock + spike strip 26 m ahead). The chase-from-a-car camera scene (`--scene=chase`) exists but its picture was not good enough to keep.

Live-test flakiness (all caused by the other modules' behaviour, not by the director): the real-officer arrest happened in 3 of 4 runs after 30-37 s; once the two officers stood still at ~37-41 m
from the player for 40+ s (Police-B pathing) and nothing happened within 150 s. With traffic on, the driving pursuit built its roadblock after ~20-45 s (the scripted test car is slowed by traffic).

Known limits: officers on foot approach at ~3.2 m/s (Police-B tuning), cars can get stuck on street furniture next to the player (Police-B), the station first response only fires when the
station is 100-450 m from the crime, tactics (PIT, boxing, spike strips) are Police-B's decision from the `tactic` hint, spawning a unit costs up to ~15 ms in one frame (factory cost).
