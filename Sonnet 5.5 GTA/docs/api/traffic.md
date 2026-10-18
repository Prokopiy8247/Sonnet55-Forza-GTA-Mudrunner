# Traffic module (`Game.sys(&"traffic")`, `gta/code/traffic/*`)

Owner: Traffic agent. Everything described below exists and was exercised in the headless simulations / scenario tests listed under
"Verification" (numbers measured in the last run); "Known limits" lists what is not done or only approximate.

## What it is
Civilian lane-graph traffic for Halcyon Bay: one `TrafficManager` node (a Main system, `setup(main)` + `post_setup()`), one
`_physics_process` that ticks every `TrafficDriver` (a `RefCounted` AI brain, NOT a per-car node/script) in distance tiers, a spawn
ring around the player, recycling, parked cars, crash / flee / carjack reactions and an obstacle registry shared by all drivers.

| file | class | role |
|---|---|---|
| `traffic_manager.gd` | `TrafficManager` (Node) | system, main loop, spawn/recycle, events, public API |
| `traffic_driver.gd` | `TrafficDriver` (RefCounted) | AI of ONE car: lane following, speed control, obstacles, signals, junctions, reactions |
| `traffic_spawner.gd` | `TrafficSpawner` | vehicle mix by district, Halcyon paint palette, density by district x hour x setting |
| `parked_cars.gd` | `ParkedCars` | ~45-56 curb-side parked cars (sleeping VehicleBase, spawned/despawned by distance) |
| `intersection_manager.gd` | `IntersectionManager` | reservation based right-of-way for junction boxes (signalised and unsignalised) |
| `traffic_net.gd` | `TrafficNet` (static) | tables derived once from `WorldLayout.lanes`: junction chains, conflicts, dead ends, near-junction flags, turn weights |
| `traffic_grid.gd` | `TrafficGrid` | flat packed-array spatial hash of all vehicles + pedestrians (rebuilt ~30 Hz) |
| `lane_clearance.gd` | `LaneClearance` (static) | lazy per-lane-point test "is there a pole in the lane?" -> FREE / DODGE (shift) / BLOCKED |

## Public API (TrafficManager)
```
state: State.WAIT_WORLD | State.RUNNING     enabled: bool     drivers: Array[TrafficDriver]     clock: float (signal clock)
get_active_count() -> int                    get_stats() -> Dictionary (see below)    spike_log: Array[String]
get_driver(v: Node) -> TrafficDriver|null    is_traffic_vehicle(v: Node) -> bool
get_traffic_vehicles() -> Array[VehicleBase] get_parked_vehicles() -> Array[VehicleBase]
spawn_at_lane(lane_idx: int, vehicle_id := &"") -> VehicleBase     # tests / debug menu
make_flee(v: Node, seconds := 15.0)          # police chases, scripted events: the car runs reds and escapes
release_vehicle(v: Node)                     # give a traffic car to someone else without despawning it
set_enabled(bool) / clear_traffic()          # clear_traffic recycles every traffic car (parked stay)
is_seen(p: Vector3) -> bool                  # inside the camera frustum AND not occluded by world geometry
get_signal_time() -> float                   # the clock handed to ContentManager.set_signal_clock
add_orphan(v)                                # hand a vehicle over for distance-based cleanup
density_override / cap_override              # tests: force the target count / cap
```
Tunables (consts in `traffic_manager.gd`): `HARD_CAP 28`, `ABS_CAP 40`, `SPAWN_MIN 90`, `SPAWN_MAX 170`, `INITIAL_MIN 45`
(first fill / teleport only), `DESPAWN_DIST 205`, `TIER_NEAR 60`, `TIER_MID 140`, `WRECK_CLEAR_S 90`. `TrafficDriver`: `MAX_CRUISE 21 m/s`,
`A_LAT 3.3`, `B_STOP 2.7`. `Game.settings["traffic_density"]` scales the target, `Game.cheats["traffic"] = false` removes all traffic
(cars that are visible and close are not popped; everything else is recycled immediately). `--no-traffic` (DevHarness) sets the cheat.

`get_stats()` keys: `spawned recycled released wrecks_cleared stuck_recycled tt_collisions crashes flee honks red_runs junction_blocks
reverse_recoveries breakdowns parked_live parked_slots active target avg_speed tick_us_avg tick_us_max drivers_updated
junction_grants junction_denied junction_timeouts junction_holders orphans`.

## Behaviour summary
* **Spawn**: `_find_spawn_point` picks lane points 90-170 m from the player (45 m during the very first fill / after a teleport > 120 m),
  half of the picks biased ahead of the player's direction of travel, never in water, never on BLOCKED lane points or alleys, only
  where `is_seen()` is false (frustum + occlusion ray), with a free corridor (no vehicle 22 m behind .. 26 m ahead / no ped within 8 m / nothing
  spawned there in the last 2 s). Vehicle ids from `VehicleDefs` (non-police, implemented) weighted per district (`TrafficSpawner.MIX`),
  paint from the curated palette. Spawned through `VehicleFactory.spawn(id, xf, {ai, engine_on, headlights, paint, paint2, finish})`;
  a driver is created with `PedManager.create_driver(vehicle)` (falls back to a driverless-but-driving car when unavailable).
* **Density**: `HARD_CAP * time_factor(hour) * (0.55 + 0.45 * district_factor) * Game.settings.traffic_density` (rush hours 8 / 17:30 busiest, ~0.22 at 04:00).
* **Recycle**: > 205 m and unseen, stuck (idle > 26 s / 40 s behind a leader) and unseen (or idle > 60 s), fell out of the world, wreck (MODE_CRASHED) older than 90 s and unseen.
  Destroyed cars are left to `VehicleSystem` (wreck handling).
* **Driving**: pure-pursuit steering on the lane path with speed dependent look-ahead and lateral offset track, curve speed `sqrt(A_LAT/kappa)`,
  speed limit x personality (0.85-1.15) x weather scale, time-gap following with emergency braking, stopping profiles for stop lines /
  leaders / pedestrians, smooth pedals (rate limited), feed-forward + acceleration trim. Static clutter: `LaneClearance` + 3 down-range rays
  (`GC.L_WORLD | GC.L_PROP`) for tier-0 cars. Parked/stopped cars beside the lane are passed by a lateral shift; small obstacles are dodged.
* **Signals**: stop line = lane point with `signal_id >= 0`; state from `WorldLayout.signal_state(sig, phase, clock)` (0 green 1 yellow 2 red);
  yellow decision is made once (can stop at <= 4.4 m/s^2 else go); never enter the junction box unless the exit has room.
  `ContentManager.set_signal_clock(get_signal_time)` keeps the 3D lenses on the same clock.
* **Junctions**: `IntersectionManager` reservations on connector chains (conflict test geometric), priority = waiting time > 4 s, road rank, left turns yield to
  oncoming, yield to the right, then first-come. Holders lose the reservation after 16 s.
* **Reactions**: honk at blockers (`vehicle.input_horn` -> `Events.vehicle_horn` emitted by the vehicle), brake for pedestrians/player on foot, yield to
  sirens (pull right, stop, within 70 m behind), flee when shot at / damaged by gunfire or explosions (accelerate away, run reds, ~10-18 s),
  crash stop with hazards (MODE_CRASHED, 5-10 s) then resume or stay a wreck, breakdown cars (45-90 s with hazards, random, out of view), reverse recovery (7 s idle) then replan,
  slower in rain / fog (`Game.wetness`, `rain_intensity`, `fog_amount`), headlights per `EnvironmentSystem.headlights_wanted()`.
* **Carjack / theft**: when anything other than the AI driver enters a traffic car (`Events.vehicle_entered`) the driver is released
  (`is_ai_controlled=false`, controls reset) and forgotten; the NPC reaction (`Pedestrian.on_carjacked`) is the vehicle/peds logic. Cars that left our books become "orphans"
  that are despawned only when > 280 m away, unseen and empty (player-owned/driven cars are never touched).
* **Parked cars**: 45-56 slots on the right edge of ordinary streets (never near junctions or on the arterial), quota per district
  (downtown 20, residential 16, industrial 9, harbour 4, airport 3, beach 2, park 2). Spawned within 135 m (not while visible and 25-95 m away), despawned beyond 170 m
  unless visible; `parked` flag = asleep; full `VehicleBase` so the player can steal them (F -> engine starts). Slots blocked by poles are marked bad.

## Events
Consumes: `vehicle_collision`, `vehicle_entered`, `vehicle_exited`, `vehicle_damaged`, `gunshot`, `explosion`.
Emits: nothing of its own (the vehicle emits `vehicle_horn`; WantedSystem derives crimes from collisions/damage itself).

## Test / tooling (gta/tests, all run with `powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/<file> -Seconds N -GameArgs "..."`)
| test | what it checks |
|---|---|
| `traffic_test.gd` (`--secs=120 --spot=x,z --density=N --verbose`) | 120+ s city simulation: spawned / recycled counts, average speed, traffic-vs-traffic collisions, red-light crossings (own detector on the 124 stop lines), stuck cars, cars stalled in junction boxes, tick cost, spike log, parked cars; prints per-car history around every collision / red run |
| `traffic_signal_test.gd` (`--sig=8 --nstops=5 --flip=S --trace --list`) | scripted approach to a signalised stop line at 5 different green-to-yellow timings per stop line: must stop on red, never cross > 1 s into the red, go on green |
| `traffic_reaction_test.gd` (`--trace`) | siren yield (pulls right, stops, resumes), person standing in the lane (stops, keeps distance, resumes), gunfire damage (flee mode, speeds up), night headlights, storm slows the traffic (speed scale / headway), breakdown (hazards, stop, recover) |
| `traffic_carjack_test.gd` | player takes a moving traffic car with the driver NPC (F): released from the AI, NPC out of the seat, car drives off; blocker car in the lane (no collision, honks); ramming a traffic car (crash reaction, player ok) |
| `traffic_spot_test.gd` (`--lane=N --model=a,b --secs=S --every=F`) | debug: spawn one car on a lane point and print its driver state |
| `traffic_probe.gd` (`--at=x,z --r=R`) | debug: furniture / colliders (with shapes) / lane points around a position |
| `traffic_shot_prep.gd`, `traffic_perf.gd` | helpers for `shot` (raise the cap, wait) and a windowed A/B fps probe (traffic on / off) |

DevHarness: `--no-traffic` disables traffic; `--no-peds` removes pedestrians (traffic cars then drive without a driver NPC).

## Verification (last run, this machine: shared with ~10 other agents, so absolute fps is noisy)
Headless `traffic_test.gd`, 120-150 s of game time, 23-28 cars active, rush hour 09:30, pedestrians off / on:
* spawned 48-57 cars per 120-150 s, recycled 25-31 (almost all because they left the ring), avg active 23.0 of 23 (27.9 of 28 with `--density=28`); avg speed of moving cars 6.5-6.7 m/s (24 km/h; dense downtown with 36 signalised junctions), free-flow speed / limit 0.73.
* traffic-vs-traffic collisions **0**, crashes 0, red-light crossings (> 1.2 s after the light turned red) **0** (was 2 + 20 forced runs before the fixes below), junction-box stalls 0, stuck recycles 0-1 per 120 s (the last 28-car run with pedestrians still ended with 3 cars waiting > 8 s in a queue at the junction (105, 85) - phone booth, see limits).
* traffic tick cost (all drivers + grid + housekeeping + spawning): **avg 1.3 ms per physics frame for 23 cars (pedestrians off), 2.5 ms for 28 cars with pedestrians in the grid**; target < 3 ms met. Spikes: the first fill spawns 3 cars per frame (8-12 ms for ~0.6 s after boot / teleport), later single ticks of 14-25 ms happen a few times per 2 minutes (lazy LaneClearance shape queries, grid rebuild GC); `TrafficManager.spike_log` records them. Spawn cost is 1.1 ms (factory) + 1.7 ms (driver NPC) per car.
* signal scenario test: 20 of 20 approaches stop or clear correctly (no crossing later than 0.5 s after the red).
* reaction scenarios: siren yield, person in lane, flee, night headlights, storm slow-down, breakdown all PASS.
* carjack scenarios (with driver NPCs): carjack, release, NPC out, drive off 49 m, blocker, ram: PASS (the ram scenario retargets if the victim was recycled).
Windowed A/B probe (`traffic_perf.gd`, downtown junction, 39 cars because the test raised the density setting to 1.4): fps avg 76 / min 59 with traffic, 144 / 108 without, draw calls 2766 vs 1699 (about 27 draw calls and ~0.15 ms per car, almost all of it vehicle meshes / physics, not AI). At the default setting (28 cars) the cost is ~4 ms of the frame.
Screenshots (real renderer, `screenshots/`): `traffic_day_busy.png`, `traffic_day_busy2.png` (rush hour 08:00), `traffic_dusk_junction.png` (19:23, headlights on, taillights, a truck crossing the junction), `traffic_rain_junction.png` (rain, wet road); cars sit in their lanes, stop lines respected, no wobble or corner cutting visible, no visible spawn pop-in.

Bugs found and fixed in this run: cars spawned 5 m before a red light with 15 m/s (now `safe_spawn_speed`), green decision carried over into the yellow phase (cars ran reds with 11 m/s; now one decision per phase), reverse recovery reversed at 10 m/s into traffic (now 2.4 m/s max, checks behind, never inside a moving queue), cars crept 3 m past the stop line (brake released under 1.25 m/s, stop margin 1.3 m), siren yield never triggered near junctions, people were approached to 1.7 m, freed grid nodes raised script errors, mid-range cars skipped the static-obstacle probe.

## Known limits / not done
* Free-flow speed is conservative (measured 0.73 of the limit in dense downtown, queues at the 36 signals keep the average low); no overtaking at speed, lane changes only to pass stopped or very slow vehicles.
* `HARD_CAP` 28 is the default ceiling; `Game.settings["traffic_density"]` above 1.0 can raise the target up to the absolute cap of 40 (frame cost grows ~0.15 ms per car).
* Far cars (> 140 m) keep full vehicle physics (only their AI tick rate drops); cars are not frozen. Vehicle meshes are ~27 draw calls each (Vehicles/Blender side), which is the dominant per-car cost.
* The phone booth at the junction (105, 85) (Systems/interaction prop) stands about 0.8 m from a lane centre: traffic dodges it by 0.9 m and slows down, queues form there and an occasional scrape is possible (should be moved by the Systems agent). Cul-de-sac bulbs are avoided (spawn + turn weights) but a car that is already inside still clips the fence on the tight U-turn.
* Parked cars: 45 slots exist, ~16-17 are alive near the start; slots next to poles are skipped, so quotas per district are not always met.
* Hit-and-run / carjack crimes are derived by WantedSystem; traffic itself emits no crime events. Pedestrian reactions to a carjacked driver come from `Pedestrian.on_carjacked`.
* Not implemented: trams / buses with stops, one-way streets, school-zone or construction scenarios, traffic on the airport taxiways (not in the lane graph).
