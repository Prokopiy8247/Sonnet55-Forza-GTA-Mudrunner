# Vehicles module API (Vehicles agent)

Ground vehicles: cars, SUV, pickup, van, police cruiser, taxi, ambulance, fire truck, truck, tactical vehicle, motorcycle, bicycle.
Air / sea ids (`speedboat heli_civil heli_police plane_prop plane_jet`) exist in `VehicleDefs` with `implemented = false`;
`VehicleFactory.spawn` refuses them (logged once) until the later wave adds `BoatVehicle` / `HeliVehicle` / `PlaneVehicle`
(subclass `VehicleBase`, override `_simulate(dt)`, add a `class` branch in `VehicleFactory._build`).

Files (`gta/code/vehicles/`): `vehicle_defs.gd` (table) · `vehicle_factory.gd` (spawn/despawn, model info, collision boxes) ·
`vehicle_base.gd` (contract, seats, damage, water, run-over) · `car_vehicle.gd` (raycast-suspension physics, gearbox) ·
`bike_vehicle.gd` (motorcycle + bicycle) · `vehicle_lights.gd` · `vehicle_audio.gd` · `vehicle_damage.gd` · `vehicle_fx.gd`
(skid marks + smoke/fire/spark puff pools) · `vehicle_materials.gd` (paint finishes, glass, lamp states) · `vehicle_wheel.gd` ·
`vehicle_fallback.gd` (code-built model, only used while a GLB is missing) · `vehicle_system.gd` (container, pool, LOD, showroom).

## Spawning

```gdscript
var v := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, yaw), pos), opts)   # VehicleBase or null
VehicleFactory.despawn(v)                         # recycles undamaged vehicles through a pool (max 3 per id / 14 total)
```
`opts` (all optional): `paint: Color`, `paint2: Color`, `finish: gloss|matte|metallic|pearl|chrome`, `faction`, `ai: bool`
(traffic-driven: `is_ai_controlled = true`, engine on, joins group `traffic_vehicle`), `with_driver: bool` (calls
`PedManager.create_driver(vehicle) -> CharacterBase` when the NPC module offers it, otherwise logs once),
`mods: Dictionary`, `health_ratio`, `engine_on`, `headlights`, `keep_engine_on`, `parked: bool` (settles and sleeps until touched),
`snap_ground` (default true: drops onto the collider below), `require_ground` (freeze until a collider appears below),
`abandoned` (free to take, no theft crime; default true for non-AI non-parked spawns), `owned` (player garage vehicle), `name`.
The vehicle is added under `Game.sys(&"vehicles").get_container()` (`Vehicles` Node3D under `Game.world`).
`VehicleDefs`: `get_def(id)`, `has(id)`, `ids()`, `implemented_ids()`, `traffic_ids()`, `random_traffic_id()` (weighted), `DEFS`,
`DEFAULTS` (documents every tunable), `MOD_EFFECTS`.

## VehicleBase (RigidBody3D) - everything others use
* Controls (write every physics frame): `input_throttle input_brake input_steer input_handbrake input_horn` (+ `input_pitch` for
  bike wheelie / stoppie, aircraft inputs reserved). `W` = throttle, `S` = brake, and reverse when nearly stopped; throttle while
  rolling backwards brakes first. Unoccupied non-AI vehicles ignore throttle and hold themselves (parking brake feel on slopes).
* State: `health max_health is_destroyed on_fire engine_on headlights_on siren_on driver seats is_stolen is_player_owned
  is_ai_controlled faction paint_primary paint_secondary mods vclass def def_id gear rpm water_depth visual_lod`.
  `get_speed() get_speed_kmh() get_forward_speed() get_rpm01() get_health_ratio() is_flipped_over() is_submerged()`.
* Seats: `seats[i] = {name, character, entry, exit, pos, side, can_shoot}` (positions are vehicle-local). `get_free_seat()`,
  `get_seat_of(c)`, `get_occupants()`, `get_entry_position(i)`, `get_exit_position(i)`, `get_seat_transform(i)`,
  `get_weapon_socket(i)` (world Transform3D near the window for drive-by, -Z = aim side), `can_shoot_from_seat(i)`.
  **Seat* empties are PELVIS points**; the seated character origin is placed `SIT_HIP_DROP` (0.085 m) below them (matches the CharacterRig sit pose);
  the occupant is parented under `SeatAnchor<i>`, collision layer/mask zeroed, `character.set_vehicle(v, seat)` called, rig stance
  `sit_car` / `sit_bike` (+ `rig.set_seat(role)` when offered).
* `request_enter(character, seat := -1) -> bool`: nearest free seat (or driver seat when occupied = carjack). Free driver seat taken by
  the player: `crime_committed(CRIME_VEHICLE_THEFT, pos, player, {vehicle, witnessed_by_npc:false})` once per vehicle
  (`CRIME_POLICE_VEHICLE_THEFT` for police faction; nothing for `abandoned` / player-owned). Occupied driver seat: occupant is pulled out
  (`exit(forced)`, `victim.on_carjacked(thief)` if it has that method else knockback + hands_up), `CRIME_CARJACK` (or police theft) is
  emitted and the thief glides through the opening door into the seat (0.45-0.55 s blend, door swings via `DoorL/R/RearL/RearR`).
  `enter(c, seat, animated := false)` seats immediately; `exit(c, forced := false)` places the character at the exit empty
  (ground-snapped + capsule-checked, fallbacks: other side, behind, front, roof), restores parent/collision, applies fall damage above 7.5 m/s.
  Occupants that die or are freed leave the seat automatically. The engine starts 0.35 s after the driver sits and stops 0.7 s after he leaves.
* Damage (`apply_damage(amount, info)` - group `damageable`): `info.zone` honoured (`tire` punctures the nearest wheel unless
  bulletproof tyres, `glass` cracks then shatters and may hurt an occupant, `engine` x1.6), otherwise classified from the hit point.
  Collision damage comes from velocity change per tick (> 3 m/s): `(dv-3) * 21 * collision_mult * armour`; occupants hurt above 9 m/s.
  Below 35 % health: smoke + power loss, steering pull below 60 %; below 15 %: fire (health drains 4.5 %/s, occupants burn) then
  `explode(killer)`. `explode()` ejects/damages occupants, hops the wreck, calls `CombatSystem.explode(...)` (falls back to a
  built-in blast when absent), swaps to burnt materials, emits `destroyed(killer)` + `Events.vehicle_destroyed`, despawns after 60 s.
  `repair()` restores health, tyres, glass, lights, paint. `unflip()`, `place_at(xf)`, `set_velocity(v)` (no fake crash).
* Customisation: `set_paint(primary, secondary, finish)`, `set_rim_color(c)`, `set_window_tint(0..3)`,
  `apply_mods(dict)` with integer levels `engine 0-4, brakes 0-3, suspension 0-3, transmission 0-3, turbo 0-1, armor 0-5,
  tires 0-3 (3 = bullet-proof), spoiler 0-3, weight 0-2, window_tint 0-3, rim_color: Color, headlight_color: &"xenon"`
  (data in `VehicleDefs.MOD_EFFECTS`; they really change power / brake / grip / downforce / damage taken / mass).
* Lights / sound: `toggle_headlights()`, `toggle_siren()` (only vehicles with a siren def / SirenBar), `honk(hold)` or
  `input_horn`; `Events.vehicle_horn` is emitted every 0.55 s while held. AI vehicles switch headlights on at night / rain / fog (`auto_headlights`, never forced off by day).
* `get_camera_hints() -> {distance, height, look_ahead, fov, shake, speed_kmh, first_person_offset, lean (bikes)}`.
* Extra signals: `collided(other, impact)`, `tire_punctured(wheel_index)`.
* Pedestrians: moving vehicles (> 3.2 m/s) query a box ahead of the bumper (layers NPC/PLAYER/ANIMAL); hits call
  `apply_damage(type=DMG_RUNOVER, source=driver)` + `knockback` and emit `Events.vehicle_collision(vehicle, ped, impulse)`.
  `run_over_enabled = false` switches it off if the NPC module takes over.

## Handling model (CarVehicle)
Project-owned RigidBody3D with custom centre of mass / inertia. Per wheel a ray along the body's up axis (mask `GC.M_GROUND`),
spring (frequency from def, sprung mass from the CoM lever rule), asymmetric damper, bump stop, anti-roll bar per axle. Tyre force:
slip-angle curve with `Fy = mu*Fz*x/sqrt(1+x^2)` clamped by a stiction term (stable at low speed), friction ellipse with longitudinal
priority (RWD power-oversteer, FWD understeer), grip fall-off to `drift_grip` once the slip ratio exceeds 0.14 (drift friendly),
handbrake locks the rear axle and cuts rear grip to `handbrake_grip`, ABS braking with load-proportional distribution,
stationary hold (no creeping on slopes), surface multipliers via collider meta `surface` (`road grass dirt sand gravel mud snow ...`,
also guessed from collider names) and wet roads (`Game.wetness` lowers grip by up to 28 %). Steering lock shrinks with speed
(`steer_gain * wheelbase * grip / v^2`). Engine: parabolic torque curve from `power_kw`, automatic gearbox with ratios derived from
`top_speed_kmh`, launch clutch, rev limiter, shift cut, engine braking, drag (`cda`), downforce, air levelling, damaged power/steering.
Water: below the sea surface the engine dies, buoyancy ~ 0.95 weight + drag (sinks slowly), occupants bail out after 1.2 s.
Parked / unoccupied vehicles go to sleep (zero cost) after 0.9 s of rest and wake on contact.
BikeVehicle: same wheel model with 2 wheels + PD lean controller (leans into corners, upright at rest), wheelie at full throttle in gears 1-2,
falls over on impacts > 8.5 m/s (bicycle 6) or lean > 66 deg: rider ejected with damage, bike lies down, entering it picks it up.
Bicycle: pedal force (`pedal_force`), no engine.

## VehicleSystem (`Game.sys(&"vehicles")`)
`get_container()`, `find_nearest_vehicle(pos, max_dist, exclude)`, `get_vehicles()`, `dealer_vehicles`, `start_vehicles`,
`spawn_showroom()`, `spawn_start_cars()`, `clear_pool()`, `stats`. `post_setup()` waits for `WorldLayout.built` + 8 physics frames, then spawns the
showroom at `dealer_lot` (ONE display row along X on the forecourt strip, width from the lot's `parking` rect: one of every ground vehicle, parked, `require_ground`) and a cyan `sports` + magenta `sedan` near `player_spawn`
(abandoned = free to take). Disabled by the user arg `--no-vehicles`. A 0.3 s LOD pass sets `visual_lod = 1` beyond 120 m (no wheel visuals / audio / fx)
and gives real headlight spots / siren lights to the 6 nearest lit vehicles within 65 m. Falling below y = -45 despawns.
`VehicleFx.inst`: shared skid marks (640 quads, 45 s life, 1 draw call) and 3 puff pools (smoke, fire, sparks).

## Events
Emits: `vehicle_spawned/removed/entered/exited/damaged/destroyed/collision/horn`, `explosion` (through `CombatSystem.explode`),
`crime_committed` (carjack / vehicle theft / police vehicle theft). Listens to nothing except its own bodies.
Extra integration expected from others: Player writes `input_*`; Traffic / Police set `is_ai_controlled` (or use `ai:true`) and write inputs;
Weapons call `apply_damage` with `zone` (tire/glass/engine/body) - already honoured; Garage calls `set_paint / apply_mods / repair`.

## Tunables / limits
All per-vehicle numbers live in `VehicleDefs.DEFAULTS` + the table (mass, power_kw, top_speed_kmh, grip, drift_grip, front/rear_grip, grip_lift,
steer_lock/min/gain, brake, handbrake_grip, susp_freq/damp/travel, arb, cda, downforce, health, collision/bullet/explosion/runover_mult).
Global: `CarVehicle.SLIP_STIFF, LAT_DAMP_RESP, CRR, ABS_FRAC`, `VehicleBase.IMPACT_MIN`.
Limits: ground vehicles only; 2/4/6 wheels (Wheel_FL/FR/ML/MR/RL/RR, Wheel_F/R); doors are hinged meshes only (no sliding doors);
no soft-body deformation (cosmetic glass / smoke / fire / wreck only); skid marks are flat quads (no decal projection on slopes);
convertible roofs and trunk/hood interaction are not implemented; visual body-kit parts (spoilers, bumpers) await Blender part models
(handling effects of mods are live). Enable `physics/common/physics_interpolation` in project settings for smooth rendering above 60 Hz.
