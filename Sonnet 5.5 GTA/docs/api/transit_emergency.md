# Transit + Emergency services (Transit agent, wave 3)

Files (`gta/code/systems/`): `route_planner.gd` (RoutePlanner), `route_driver.gd` (RouteDriver), `taxi_service.gd` (TaxiService), `taxi_menu.gd` (TaxiMenu),
`transit_system.gd` (TransitSystem, boot key `transit`), `emergency_system.gd` (EmergencySystem + inner `Unit`, boot key `emergency`), `emergency_crew.gd` (EmergencyCrew).
Tests (`gta/tests/`): `transit_route_test.gd`, `transit_taxi_test.gd`, `emergency_test.gd`.

## STATUS (honest)
| feature | status |
|---|---|
| Lane-graph routing (RoutePlanner) | WORKING - 552 ordered pairs of 24 key locations all routable, continuous, sane (test) |
| Taxi service: phone Taxi app -> cab -> pickup -> destination menu -> ride -> fare -> exit -> cab leaves | WORKING (headless full trip PASS, 17 checks) |
| Taxi ride skip (hold E) with fade | WORKING (headless: arrives 0.8 s after the skip) |
| Ambulance response (siren, paramedics treat + take the body, leaves) | WORKING (headless PASS) |
| Fire engine response (siren, firefighters spray water particles, fire out, leaves) | WORKING (headless PASS) |
| Trains (shuttle, viaduct, doors, riding, stations access) | NOT IMPLEMENTED (no code; `TransitSystem` loads `train_service.gd` only if it exists) |
| Hail a passing taxi / tow truck | NOT IMPLEMENTED (stretch) |
| Screenshots of taxi/ambulance/fire truck | NOT TAKEN (no renderer run) |

## 1. RoutePlanner (`route_planner.gd`, all static)
A* over `WorldLayout.lanes` following successor links (junction connectors included). Cost = travel time (length / speed limit) + 0.7 s per junction
+ 3 s per stop line. Lane points that `LaneClearance` marks BLOCKED (a pole stands in the lane) are never used (otherwise a planned route dead-ends at the pole).
Results cached (96 entries). No lane-change edges: routes stay in their lane, `plan()` takes several start / goal lanes and returns the best pair.
```
plan(starts: PackedInt32Array, goals: PackedInt32Array) -> PackedInt32Array            # lane indices start..goal ([] = unreachable)
plan_positions(from, to, start_dir := ZERO) / get_route_points(from, to) -> PackedVector3Array   # UI route line (straight-line fallback)
is_reachable / route_length(route) / route_time(route) / cumulative(route)
nearest_lane / lane_candidates(pos, radius, limit, include_connectors, dir_hint)
is_stoppable(idx, strict := true) / find_curb_stop(pos, max_dist, dir_hint, strict := true) -> idx   # plain lane, no stop line / junction / pole near
reverse_reach(goal, max_m) / find_spawn_point(goal, min_m, max_m, seen_cb, rng) -> idx    # connected, unseen spawn lane
```
Cost: 4.5 ms per uncached plan (headless, 552 plans = 2.5 s); typical use is 1-20 plans per call.

## 2. RouteDriver (`route_driver.gd`, extends TrafficDriver)
The normal TrafficDriver (lane following, junction reservations, signals, leaders, pedestrians, siren yield) following a planned route and stopping at its end.
Ticked by its owner (`drv.update(dt, TrafficManager.clock)`), NOT by TrafficManager (it is not in `tm.drivers`). `setup(vehicle, lane, rng, tm.grid, tm.junction, tm.clock)`,
`set_route(route, stop_at_end := true)`, `arrived`, `remaining()`, `pull_over`, `jump_ahead(m)` (unstick: jumps ahead along the path when blocked), `release_arrival()` (wander as traffic),
`replan()` stays on the route. Stopping: constant-decel profile over the last 60 m, the car drifts 1 m towards the curb in the last 26 m, then holds with hazards.

## 3. Taxi (`TaxiService`, `Game.sys(&"transit").call_taxi() -> bool`)
Flow: `call_taxi()` (refuses when `Game.wanted_level > 0`, in a vehicle, no connected unseen spawn lane) -> City Cab with an NPC driver (`PedManager.create_driver`) spawns on a lane
110-260 m away, unseen, connected to the curb stop nearest the player (80 m) -> drives there (re-targets if the player walks > 35 m away) -> hazards + horn beep + toast ->
**F next to the cab boards the rear-right seat** (the service intercepts `enter_exit` in `_input`, which runs before the Player's, so the driver is never carjacked; the vehicle prompt reads
"Get in the cab" through the additive `taxi_prompt` meta hook in `VehicleBase.get_interaction`) -> `TaxiMenu` (menu id `taxi`, MenuBase list of named locations + the map waypoint with distance, ETA, fare) ->
the cab drives the route (normal traffic behaviour) -> arrival: fare `6 + 0.022 $/m` via `Game.spend_cash` (free with `Game.cheats["free_taxi"]` or `unlock_all_mods`), toast, `ui_cash` ->
F (only when the cab is stopped) gets out at the curb -> the cab waits 2 s, drives off as traffic, despawns when unseen and > 130 m away (or 110 s).
Cancel: wanted level > 0 while approaching / waiting (driver bails), player takes another vehicle, 170 s approach timeout, 90 s wait timeout, driver killed / cab taken (`seat 0`) -> forgotten (becomes a normal orphan vehicle).
Hold `interact` (E) for 0.9 s during the ride: fade out, the cab is placed at the destination curb, fade in, arrived. A stuck watchdog (idle > 9 s, not at a signal) calls `RouteDriver.jump_ahead`.
Public: `state` (enum `S`), `taxi`, `drv`, `fare`, `trips`, `unsticks`, `debug`, `reset()`, `fare_for(m)`, `open_menu()`.

## 4. Emergency (`EmergencySystem`, `Game.sys(&"emergency")`)
Listens: `Events.character_died` (any non-player, not under water), `Events.explosion` (radius >= 3.5), `Events.vehicle_destroyed`, burning vehicles (poll every 2 s). Incidents are queued (max 4, merged within 18 m,
dropped after 150 s or when the body is gone, ignored beyond 300 m from the player). At most ONE ambulance (`medical`) and ONE fire engine (`fire`) at a time; response delay 7 s / 5 s; cooldown 30 s / 45 s after a unit is gone;
no dispatch while `Game.wanted_state == &"pursuit"`; `Game.cheats["no_emergency"]` disables.
Unit: spawns at its station lane (hospital / `district_center_industrial`) if it is >= 75 m from the player, unseen and the route is <= 650 m, else on a connected unseen lane 110-260 m away; the vehicle (`ambulance` / `firetruck`) has
`siren_on`, group `emergency_vehicle`, NPC driver; traffic yields to the siren (TrafficDriver does that). Arrival at the curb stop nearest the incident (non-strict lane choice) -> 2 `EmergencyCrew` rigs (paramedic: white/teal; firefighter: red/charcoal,
yellow helmet, orange vest) get out and walk (`CharacterRig` locomotion) -> medical: kneel 6 s, the body is released through `PedManager.release` (counted in `stats.bodies`), crew carries on to the rear, back to the cab -> fire: crew walks to ~8 m
from the fire, 2 `CPUParticles3D` hoses (70 particles each) spray for 9 s, at 70 % every burning vehicle within 16 m is extinguished (`on_fire = false`, health >= 30 %; wrecks: burn timer cleared) -> unit drives off, siren off after 7 s,
despawns when unseen and > 130 m away. The wreck a fire engine is heading for is kept alive (`_despawn_timer` >= 25 s) until the fire is out. The unit aborts (becomes an orphan vehicle) if it is destroyed or stolen.
Public: `report_incident(kind, pos, node)`, `despawn_all()` / `reset()` (SaveSystem calls these on load), `get_state()`, `stats`, `units`, `incidents`, `enabled`.

## 5. Shared-file edits (all additive)
* `gta/code/vehicles/vehicle_base.gd` `get_interaction()`: 2 lines - when the vehicle has meta `taxi_prompt` the prompt text comes from it (so a hailed cab says "Get in the cab", not "Carjack").

## 6. Verification (headless, this machine, other agents running)
* `transit_route_test.gd` (12 checks PASS): 24 key locations, 552 pairs routable, no broken links, longest route 945 m, 4.5 ms/plan, cache hit, UI points, curb stop, connected spawn.
* `transit_taxi_test.gd -GameArgs "--no-traffic --time=12"` (17 checks PASS): call, spawn 100+ m away, arrives and stops at the curb 33-55 s later (hazards), prompt, F boards seat 3 and the driver is NOT carjacked (wanted stays 0), menu opens,
  16-18 destinations, trip of 158 m takes 22 s (peak 13.9 m/s), ends 13 m from the named place, $9 charged, F exits, cab despawns, refused at wanted 2, skip works.
* `emergency_test.gd` (`--fire-only` for the fire half): dead pedestrian -> incident -> ambulance after 7 s, siren, arrives, 2 paramedics, body collected, unit gone after ~80-120 s; destroyed car -> fire engine after 5 s, arrives ~52 s later, 2 firefighters spraying,
  fire out, unit gone. All PASS (the two halves were run in separate runs; the medical half's last run ended with `emg_ambulance_gone PASS`).

## 7. Known limits
* No trains (see status), no tow truck, no hailing of passing taxis, no screenshots taken.
* The cab can stop up to ~35-80 m from the player when the nearest stoppable lane is that far (stop lines / junctions / poles near the player); the toast does not say where it stopped (prompt appears within 3 m of the car).
* Ambulance / fire engine stop at the nearest plain lane which can be ~35-100 m from the incident (crew walks; the walk timeout scales with distance, capped 55 s).
* Start cars parked next to `player_spawn` intrude into the lane (they block a standing cab): the stuck watchdog jumps the cab ~28 m ahead after 9 s.
* RouteDriver cars do not change lanes by themselves (same as traffic); routes avoid lane points blocked by poles.
* Fire engine / ambulance cost: one RouteDriver tick per frame each (same cost as one traffic car) + 2 crew rigs while working; nothing runs when idle (no units).
