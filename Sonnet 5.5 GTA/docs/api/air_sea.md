# Air & Sea module API (Air/Sea agent)

Helicopters (`heli_civil`, `heli_police`), fixed-wing aircraft (`plane_prop`, `plane_jet`), the speedboat (`speedboat`), the police helicopter
brain and an AI autopilot. Everything lives in `gta/code/vehicles/` and plugs into the existing `VehicleBase` contract (docs/api/vehicles.md):
`VehicleFactory.spawn(id, xform, opts)`, seats, `request_enter / exit`, `get_camera_hints()`, damage / `explode`, `Game.sys(&"vehicles")`.

| file | class | role |
|---|---|---|
| `heli_vehicle.gd` | `HeliVehicle extends VehicleBase` | rotor-craft physics, rotor rpm state, skids, strikes, bail-out, searchlight |
| `plane_vehicle.gd` | `PlaneVehicle extends VehicleBase` | aerodynamics, stall, 3-wheel gear, take-off assist, bail-out |
| `boat_vehicle.gd` | `BoatVehicle extends VehicleBase` | hull-point buoyancy, planing, wake / spray, boarding from water |
| `air_common.gd` | `AirCommon` (static) | gear raycast suspension + tyre friction, ground / water probes, wave height, airspace limits, bail-out, skills hooks |
| `air_fx.gd` | `AirFx` (Node3D, one instance) | pooled downwash dust / sand / spray / mist puffs + foam patches (3 draw calls) |
| `air_searchlight.gd` | `AirSearchlight` (Node3D) | spot light + faceted volumetric cone + ground circle |
| `air_autopilot.gd` | `AirAutopilot` (Node) | waypoint / orbit / follow / take-off AI pilot for helis and planes (usable by any module) |
| `police_heli_ai.gd` | `PoliceHeliAI` (Node) | police helicopter director side (patrol / pursue / search, sightings, door gunner) |

Tests (all `exec`, arguments in each file's header; last full run: heli 50/50, plane 41/41, boat 15/15, real Player 46/46, police AI 29/29, real director 9/9, fleet cost 2/2):
`gta/tests/air_heli_test.gd`, `air_plane_test.gd`, `boat_test.gd`, `air_player_test.gd` (real Player: F / E / Input actions), `air_police_test.gd` (PoliceHeliAI + AirAutopilot),
`air_police_director_test.gd` (the real PoliceManager / WantedSystem at level 4), `air_perf_test.gd` (physics cost: 68 us per aircraft tick, 0.34 ms per frame for 5 aircraft);
visual QA `air_shots.gd` (`--scen=heli|runway|flight|jet|boat|police|police2|cabin|dust|pad`, run through `tools\gd.ps1 shot`), scratch telemetry `air_dbg.gd` (not a regression test).

## Spawning / showcase
```gdscript
var h := VehicleFactory.spawn(&"heli_civil", Transform3D(Basis(Vector3.UP, yaw), pos), {"snap_ground": true})   # any of the 5 air/sea ids
var p := PoliceHeliAI.spawn(Vector3(120, 90, 160))        # police helicopter in flight (VehicleBase, cap 2) - see below
```
`VehicleSystem.spawn_air_sea()` (called from `post_setup`, skipped by `--no-air` or `--no-vehicles`; helicopters look for a flat spot free of collider clutter with `AirCommon.find_clear_pad`) puts a Skylark on `helipad_downtown` and `helipad_airport`,
a police Patrol Helicopter on `helipad_hospital`, the Sparrow prop plane (left) and the Falcon jet (right) at the start of the runway (`airport_runway_start`,
facing +X, both within the first 3 m), and the Tide Runner at `dock_boat_spawn` (floating). They are listed in `VehicleSystem.air_sea_vehicles`. All can be entered with F.

## Player controls (written by the Player module, documented here)
Helicopter: `air_pitch_down/up` (W / S) = nose down / up, `air_roll_left/right` (A / D), `air_yaw_left/right` (Q / E, tail rotor), `air_throttle_up` (Shift / Space) climbs, `air_throttle_down` (Ctrl) descends,
L = landing light / searchlight (police heli), H horn. Plane: Shift / Space raise and Ctrl lowers the throttle (integrated), W / S pitch, A / D roll, Q / E rudder (and nose-wheel steering), Ctrl with the throttle at zero = brakes.
Boat: W throttle, S reverse / brake, A / D rudder, L lights. F enters / exits; a swimmer boards a boat with E ("Board Tide Runner") within 5.2 m.
**Leaving mid-air is refused** (toast); HOLD F for 0.9 s above 8 m AGL to bail out (parachute, see `AirCommon.bail_out_character`). Helicopters can only be left when on the skids / below 3 m,
planes when stopped on the ground (< 9 m/s).

## HeliVehicle
Arcade-realistic: `rotor_rpm` 0..1 (spool-up 3-3.6 s, spool-down 8-9 s) drives lift (rpm^2), ground effect, translational lift. Collective = climb-rate command
(`climb_rate` 7.5 m/s, `descend_rate` 6) with altitude hold when released; cyclic = attitude command (W / S tilt up to `tilt_max` 24 deg, A / D bank up to 27 deg) with
hover assist (`assist`: auto-level, velocity hold, GPS-style position hold, wind feed-forward) - `assist = 0` is raw cyclic; yaw pedals command a rate through the tail rotor (`tail_hp`), banked flight
turns the nose. Skids are 4 raycast legs (`AirCommon.step_gears`): soft landing under 2.6 m/s, damage above (`hard_landing`), destroyed above 8.5 m/s (`crash_landing`). Rotor strikes (6 rays at the blade tips against `L_WORLD | L_PROP`) cost
`rotor_hp` + health + rpm and shake the camera; tail rotor strikes kill the tail rotor (the cabin spins). Health below 22 % = engine failure -> autorotation (windmilling rotor, flare with collective).
Downwash: pooled dust / sand / spray from the surface type under the skids. Rotor + tail rotor blur discs (radial gradient shader) fade in with rpm. Wind: `AirCommon.wind_ms()` from `Game.wind` / weather, gusts reduced by the flying skill.
Inputs (write every physics frame): `input_pitch` (+1 nose up), `input_roll` (+1 right), `input_yaw` (+1 right), `input_collective` (-1..1), `input_throttle` (ignored; the engine runs while `engine_on`).
Members: `rotor_rpm rotor_hp tail_hp engine_failed grounded_count agl collective_state bail_progress searchlight ai direct_cyclic assist alt_hold`. Methods: `set_engine(on)`, `start_airborne(speed)` (spawn straight into flight),
`bail_out(character)`, `is_airborne()`, `get_camera_hints()` (distance 17 m, height 6 m, fov 72+, shake with speed; chase camera mode AIRCRAFT in the Player).
`heli_police` has a `Searchlight` node: `searchlight: AirSearchlight` - key L toggles it for a human pilot (beam follows the camera, never above the horizon); PoliceHeliAI drives it otherwise.
Tunables (`VehicleDefs` row): `rotor_radius tail_rotor_radius thrust_g climb_rate descend_rate tilt_max_deg bank_max_deg yaw_rate spool_up spool_down hard_landing crash_landing drag_fwd drag_fwd2 com inertia gear[] col_boxes[] cam_*`.

## PlaneVehicle
Thrust (prop: static thrust fading with airspeed to `thrust_v0`; jet: dry + afterburner above 75 % throttle), lift = `0.5 rho V^2 S CL(alpha)` with a real stall (lift collapses past `alpha_stall`, nose drops, control authority -60 %),
induced + parasite drag, sideslip restoring force, authority scaled by dynamic pressure (prop slipstream helps at low speed). Controls are rate commands with arcade assist: neutral stick = flight-path hold (the nose never rises past 82 % of the stall angle),
roll stick commands a bank angle up to `bank_limit_deg` (56, jet 68) and holds it (hold the limit > 0.8 s for a barrel roll), coordinated turns by weathervane, turn-rate feed-forward so turns do not sink.
**Automatic flaps** (`flap_alpha`) add lift below 1.75 x the stall speed; **arcade take-off**: throttle wide open + neutral stick rotates the nose at `rot_speed_k` x stall speed (`rot_rate`), pitch is capped so the tail never touches
the runway (computed from the collision boxes, `tail_clear`); a tail strike (pitch stick, collision) scrapes: damage grows with time, destroyed after 2.2 s of dragging. Gear: 3 raycast legs (nose-wheel steering, brakes, rolling resistance, static load from the CoG),
touchdown sink-rate damage (`hard_landing` 3.2 / jet 3.8 m/s, `crash_landing` 9.5 / 10.5), crash on terrain / buildings above ~14 m/s of velocity change. Control surfaces (ailerons, elevator, rudder), prop spin + blur disc, jet afterburner cones, nav lights animate.
Airspace: `AirCommon.airspace_tick` - toast "Leaving airspace" beyond 900 m from the map centre, "turn back NOW" beyond 1500 m, hard return to 700 m facing the centre beyond 2500 m (player-flown only).
Inputs: `input_throttle` (target 0..1), `input_brake`, `input_steer` / `input_yaw`, `input_pitch` (+1 nose up), `input_roll` (+1 right). Members: `airspeed aoa sideslip stalled g_load agl throttle_state flap burner on_ground grounded_count tail_clear stall_speed`.
Measured (headless): prop take-off 80-95 m (airborne by x~170 on the 220 m runway, clears the 6 m airfield wall at x=302 with 10 m), jet 100 m; climb-out 150 m in 12 s; prop top speed ~280 km/h (def 260), jet 870 km/h (def 900).
Tunables: `wing_area stall_kmh cl_slope alpha0 flap_alpha cd0 induced_k thrust_n thrust_v0 engine_lag pitch_rate roll_rate yaw_rate afterburner rot_rate rot_speed_k climb_deg bank_limit_deg hard_landing crash_landing prop_radius`.

## BoatVehicle
18 hull sample points against `GC.WATER_LEVEL + AirCommon.wave_height(x, z, t)` (the same wave function as the water shader; amplitude grows toward the open sea, rain adds chop). Buoyancy = spring + damper per submerged point
(keel floats ~0.2 m deep), outboard thrust at the stern (bow-up trim), planing above ~6-13 m/s (drag drops, lift unloads the hull), rudder yaw rate scaled by speed with inward heel, keel side grip, flip guard
(righting torque beyond 50 deg), grounding on shallow terrain (hull collider rests on the seabed, heavy scrape friction), sinking when destroyed (buoyancy fades over 7 s), unattended boats are anchored (damped).
Effects (AirFx): bow wave + V wake foam patches, planing spray, prop churn, exhaust mist. Boarding: pier / quay via F, swimmers via E (`get_interaction` only while the player swims); exit snaps onto the nearest quay / pier / ground within 5 m else the water beside the hull.
Top speed 110 km/h (`top_speed_kmh`), 0-planing in ~3.4 s, 84 deg turn in 3 s at speed. Inputs: `input_throttle`, `input_brake` (water brake / reverse), `input_steer`.

## PoliceHeliAI (ARCHITECTURE 14.4)
```gdscript
var heli: VehicleBase = PoliceHeliAI.spawn(pos)        # heli_police in flight, faction police, siren lights, searchlight; null at the cap (2) -> opts {"force": true}
var ai := PoliceHeliAI.of(heli)                        # also heli.ai and heli.get_meta(&"police_ai")
ai.set_mode(&"patrol" | &"pursue" | &"search" | &"hold" | &"leave");  ai.set_target(node)     # PoliceManager._heli_apply calls exactly these on the vehicle's children
ai.set_order({"mode":, "target":, "pos":, "radius":, "aggression":, "lethal":})                # PoliceManager._deliver() reaches it through meta police_ai
```
* **patrol**: orbit the city (`patrol_center/radius/alt` ~150 m radius, 105 m altitude, alternate directions for two helis); searchlight sweeps ahead at night.
* **pursue**: AirAutopilot FOLLOW with a smooth lag (`follow_lag` 1.5 s) 18 m behind and ~50 m above the target (raised over buildings: `min_agl` 28), nose to the suspect, beam locked on him (target lead 0.35 s).
* **search**: orbit radius `clamp(search_radius * 0.5, 38, 110)` at 62 m above the ground around `search_center` (order pos / `wanted.get_last_known_position()`), beam sweeping a Lissajous curve over the area, locks on when the player is found.
* **leave**: flies away at 130 m and despawns itself beyond 520 m from the map centre / 500 m from the player.
* **Sightings**: every 0.4 s, if the beam covers the player (cone angle test) with a clear ray (or plain LOS within 140 m in daylight, or within 60 m while pursuing) it calls `WantedSystem.report_sighting(player_pos, heli)` and emits `player_sighted`.
* **Door gunner**: wanted level >= 4 (`Game.wanted_level`, test override `level_override`), pursuit mode, `lethal`, player lit and within 150 m: bursts of 3-5 rounds at 10 Hz every 2.6-4.8 s (shorter with aggression, x0.7 at level 5),
  `Ballistics.shoot` (damage 6, range 180, deliberately poor aim: 3.6 deg cone + target speed), chunky orange tracers through `CombatSystem.get_fx().tracer`, `Events.gunshot(muzzle, 140, heli)`, `shot_smg` sound. ~1 round/s on average.
* The brain retires for good (the node frees itself) when a human takes the pilot seat of the police helicopter (stolen: `CRIME_POLICE_VEHICLE_THEFT`, key L = searchlight, beam follows the camera). A destroyed helicopter stops all behaviour (VehicleBase explodes / wreck as usual).
`PoliceHeliAI.active_count()`, `get_status()`, `stats {bursts, rounds, sightings, mode_changes}`, signals `mode_changed(mode)`, `player_sighted(pos)`.

## AirAutopilot
```gdscript
var ap := AirAutopilot.attach(aircraft)                 # child node "AirAutopilot"; sets is_ai_controlled while flying
ap.goto(pos, speed := -1, alt := NAN) / ap.orbit(center, radius, alt, speed, clockwise) / ap.follow(node, offset, trail, speed)
ap.set_waypoints([Vector3...], loop) / ap.hover(pos) / ap.takeoff(alt) / ap.stop()
ap.look_at_point, ap.heading_target, ap.cruise_speed, ap.max_speed, ap.min_agl, ap.follow_lag      # signals arrived(point), takeoff_done
```
Helicopters: velocity command -> cyclic (the autopilot sets `HeliVehicle.direct_cyclic = true`), probes buildings / hills ahead (10 Hz) and keeps `min_agl` above them. Planes: heading -> bank, altitude -> pitch, speed -> throttle, take-off roll with rotation.

## AirSearchlight
`AirSearchlight.create(vehicle)` (null without a `Searchlight` model node) -> `set_enabled(on)`, `aim_at(point)` / `aim_dir(dir)`, `covers(point, tol_deg)`, `hit_pos hit_normal hit_dist`, `slew_deg` (48 deg/s), `half_angle_deg` (6.5), `range_m` (200), `shadows`.
Visuals: SpotLight3D (energy 16-18), an 8-sided additive cone (fresnel-soft rim, fades with length and when the camera is inside) and a lit ellipse on the surface the beam hits; brightness follows the daylight.

## AirFx / AirCommon (for other modules)
`AirFx.get_fx()` -> `downwash(ground, surface, strength, radius, n)`, `spray_burst`, `mist_puff`, `wake_patch`, `exhaust_smoke`. `AirCommon.wave_height(x, z, t, rain)`, `water_surface(x, z)`, `probe_down(node, from, max)`, `agl_of(node)`,
`wind_ms()`, `stability_mult()` (flying skill: 1.0 -> 0.65 through `get_modifier(&"aircraft_stability")`), `bail_out_character(vehicle, character)`.

## Events / integration
Emits through VehicleBase: `vehicle_entered/exited/damaged/destroyed`, `explosion` (via `explode`); `crime_committed(CRIME_AIRCRAFT_THEFT | CRIME_POLICE_VEHICLE_THEFT)` when a player takes a non-abandoned aircraft;
`notification` (toasts: Leaving airspace, STALL, Hard landing, Rotor strike, Engine failure, Land first - or HOLD F to bail out ...); `gunshot` from the police door gunner.
Skills: the flying skill is trained by `SkillsSystem._sample_vehicle` while airborne (> 4 m AGL, > 5 m/s) plus +1.5 / +2 per clean touchdown here; `aircraft_stability` softens turbulence and weathervane penalties.
Audio: `VehicleAudio` plays `EngineSound` profiles `heli_rotor` / `prop_plane` / `jet` / `boat` fed by `get_rpm01()` and `get_engine_load()` (collective, throttle).

## Limits / honest notes
* Helicopters / planes are single RigidBody3D with analytic forces (no per-blade or per-wing simulation); stall is a lift-curve model, spins are not modelled. Hover assist is on by default (arcade) - set `assist = 0` for raw cyclic.
* Landing gear is static (no retraction); planes have no flaps animation (automatic flap lift only), no propeller torque, jets are single-engine thrust with two exhaust cones.
* The world's east boundary wall over the runway extension is only 6 m high (x = 302): take-off must be airborne and > 6 m by then (the assist achieves it); flying low over the water south of the airport hits the 30 m walls.
* Waves are the shader's function re-evaluated on the CPU (no real water volume); the boat does not collide with other boats' wakes; no jet-ski / diving / swimming-under logic here (Player module).
* Police helicopters are capped at 2 (`MAX_ACTIVE`); the door gunner only targets the player.
* `helipad_hospital` is a cluttered roof (air-conditioners, a tank, a stair block, no marked pad): the showcase police helicopter is parked on the nearest clear deck 3-4 m from the location; the rotor passes close to a (collider-less) tank. A cleaner pad would need the World-Content roof kit to leave a 10 x 10 m area empty.
* Gang NPCs of the Foundry Yard turf (x 222, z 30) shoot at aircraft passing over the industrial area (seen in the real-player test as `bullet` damage on the helicopter).
* `PoliceHeliAI` uses the wanted level of the game, not a per-unit order level; `aggression` only shortens burst gaps.
