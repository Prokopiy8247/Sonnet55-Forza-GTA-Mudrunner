# Vehicle physics: model, drive tests and tuning guide

Owner: vehicle-physics agent (A1). Code: `Vehicle/RoamVehicleMovement*.{h,cpp}` (+ `RoamVehicleMovementPhysics.cpp`), `RoamTireModel`, `RoamDrivetrain`,
`RoamVehicleBody`, `RoamTestCars` (+ generated `RoamTestCarData.inl`), tests `Tests/RoamVehiclePhysicsTests.cpp`.
Measured on the first tuning round; every number below comes from `Automation RunTests Roam.Vehicle` (headless, `-NullRHI`, ~45 s for all).

## 1. The model in one page

* **Body.** The root `Body` (`URoamVehicleBody`, a static mesh component) is a Chaos rigid body, mass/COM/inertia from the car definition
  (inertia = `GetEstimatedInertia()` applied through `InertiaTensorScale`, inertia conditioning off, CCD on, sleeping off). Real cars keep the UCX
  hulls of their Blender body; a car without a body mesh (tests, placeholder) gets a hidden engine cube with a runtime **box proxy** shape sized
  from the geometry (`URoamVehicleBody::SetProxyBox`).
* **Stepping.** `StepPhysics()` runs from `AsyncPhysicsTickComponent` at the fixed 120 Hz step (game thread, physics thread parked). It reads the
  particle through `FBodyInstanceAsyncPhysicsTickHandle` (`X/R/V/W/CenterOfMass`), applies forces with `AddForce/AddTorque` (cm and
  kg*cm/s^2: N x 100). Wheel traces are `LineTraceSingleByChannel` on `Roam_Wheel` (PT data with GT objects, see UE58_vehicle_gameplay 1.5.2).
  The game-thread tick only wakes the body, caches the weather wetness and moves the wheel meshes (suspension travel; the visuals component keeps
  rotation/steer/spin). Telemetry is written by the step itself.
* **Suspension.** One ray per wheel from the top of the travel. `F = F_static + k*compression + damper (bump/rebound, speed of the mount point) +
  bump-stop (k_stop*(c - travel_up))`, `F_static` = this corner's share of the weight from the COM position, so the car rests exactly at the
  geometry ride height. Anti-roll bar couples the compressions of an axle. Force acts along body up at the mount point. Tuning: spring/damper
  scale, anti-roll index (30 = stock), ride-height offset.
* **Tyres** (`RoamTireModel`, pure functions, unit-tested): normalised-slip friction circle. `kappa = (omega*R - vx)/max(|vx|, 2.5 m/s)`,
  `tan(alpha) = vy/max(|vx|, 2.5)`, `s = hypot(kappa/kappa_peak, tan(alpha)/tan(alpha_peak))`, `F = mu*Fz*f(s)`, direction (kappa, -alpha).
  `f(s) = 1-(1-s)^2` to the peak, then `slide + (1-slide)*exp(-((s-1)/1.2)^2)`. `mu = peak * (Fz/Fnominal)^-loadSensitivity * SurfaceBias *
  Roam::SurfaceGripMultiplier(surface, wetness) (the compound's WetGripBias scales the wet loss) * pressure effect * upgrade grip`. The force is
  limited so it cannot reverse the slip velocity inside one step, rolling resistance has a per-surface factor (asphalt 1 ... sand 4.5).
* **Wheel dynamics** are solved implicitly: tyre force linearised with `K = max(tangent, secant to the zero-slip wheel speed)` (the secant term is
  what removed a +-5 kN standstill chatter), the engine inertia reflected through the clutch (`Ie*ratio^2`) is shared by the driven wheels in one
  Sherman-Morrison solve, brakes clamp at zero speed. Open diff = equal torque split with shared engine inertia (spinning inside wheel unloads),
  LSD/locked = torque bias `min(lock*|T|/2 + preload, |T|/2 + preload) * tanh(dw/4)`; AWD centre diff shifts the rear share the same way.
* **Drivetrain** (`RoamDrivetrain`, pure state machine): throttle lag, turbo spool + lag torque fraction, torque curve from the definition, engine
  braking, rev limiter with hysteresis; clutch is rigid while the wheel-driven RPM is above the floor (idle -> 0.65 x peak-torque RPM with the
  pedal), otherwise it slips at the floor RPM (the launch model of the PI estimator). Automatic gearbox: upshift at `lerp(0.6, UpshiftFraction, thr^0.6)
  x redline`, downshift at `lerp(0.28, DownshiftFraction, thr)`, kickdown, 0.4 s minimum per gear, shift time cuts the torque. Reverse is engaged
  by the brake pedal below 1 m/s (and the pedals swap meaning), forward again by the throttle. Manual: `ShiftUp/ShiftDown`.
* **Brakes**: `PeakDecelerationG * m * g` total, split half by the (tunable) static bias and half by the live axle load (EBD, otherwise the rear
  locks first and caps the stop at ~0.8 g), proportional ABS (modulates the pressure around 0.9 x ABSSlipRatio), handbrake torque on the rear.
* **Aero**: drag `0.5*rho*CdA*v^2`, front/rear downforce applied at the axle points, ground effect with compression, active wing deploys by speed.
* **Assists**: TCS = slip-targeting integrator on the driven wheels (target 1.1 x grip peak, more on loose surfaces, floor `1-(0.35+0.6*strength)`);
  STM = oversteer detection against a bicycle-model yaw rate, brakes the outer front wheel; steering assist = counter-steer proportional to the body
  slip angle + steering damper at speed; speed-sensitive lock from the car's curve, Ackermann, rate limit; ABS as above.
* **Air control**: while no wheel touches the ground for 0.1 s the spin is damped and the nose is aligned with the flight path (jumps land flat).
* **Telemetry** is complete (see `FRoamVehicleTelemetry`); added for the visuals/FX agents: `WheelAngVelRadS[4]`, `WheelTravelCm[4]`,
  `WheelSteerDeg[4]`, `WheelCamberDeg[4]`, `WheelSlideNorm[4]` (1 = grip peak, skid marks/smoke above ~1.3), `WheelSurface[4]`, `bBrakeLightsOn`,
  `EngineTorqueNm`, `bClutchSlipping`, `SteerAssistDeg`, `DownforceN`. `OnImpact` fires from the body hit events (> 1.5 m/s velocity change).

## 2. Measured drive tests (stock assists + TCS on, dry asphalt, 120 Hz)

`Roam.Vehicle.Drive.Straight`: full throttle from standstill on a straight runway (lane-keeping driver), then 100 -> 0 km/h with full brake.
Cars come from `Tools/ue/cars_spec.py` through `Tools/ue/drive_test_cars_gen.py` (same numbers as the DA_Car_* assets).

| Car | drive | 0-60 s | 0-100 s | 0-200 s | top km/h | target 0-100 / top | 100-0 m (ABS) | 100-0 m (no ABS) | avg decel g |
|---|---|---|---|---|---|---|---|---|---|
| Pulse | FWD | 4.20 | **7.68** | 31.8 | **225.5** | 7-8 / 220-235 | 48.0 | 49.7 | 0.82 |
| Cadence | FWD | 4.87 | 10.80 | 64.9 | 205.3 | - | 49.9 | 51.6 | 0.79 |
| Thunderline | RWD | 2.97 | **5.72** | 17.9 | **258.3** | 5-5.5 / ~245 | 44.2 | 44.0 | 0.89 |
| Vesper | RWD | 2.75 | **5.12** | 14.6 | **305.2** | ~4.8 / ~275 | 38.1 | 38.8 | 1.03 |
| Meridian GT | RWD | 2.79 | **4.79** | 12.6 | **332.7** | ~4.2 / ~310 | 36.7 | 37.9 | 1.07 |
| Aether | AWD | 1.46 | **2.56** | 7.5 | **336.8** | ~3.0 / 330+ | 32.2 | 32.0 | 1.21 |
| Ridge | AWD | 2.70 | **5.16** | 20.8 | 242.0 | ~4.5 tarmac / - | 53.1 | 52.2 | 0.75 |
| Ranger | AWD | 3.83 | **8.00** | 47.2 | **205.9** | ~8-9 / ~190 | 52.4 | 51.0 | 0.77 |
| Mule | RWD | 4.07 | **8.33** | 45.4 | 205.6 | ~7.5 / ~185 | 49.1 | 48.7 | 0.80 |
| Brisa | RWD | 5.41 | **12.35** | - | 153.4 | ~13 / ~140 | 53.6 | 53.4 | 0.72 |

Every 0-100 is within 15 % of the target (Aether 15 % quicker, Meridian GT 14 % slower, Ridge 15 % slower); tops are within 5-17 % (Mule +11 %,
Brisa +10 %, Thunderline +5 %); the targets themselves are the brief's, the physics gives what the spec's power/CdA/gearing allow. ABS barely shortens
the stop on a dry road by design (locked slide level 0.82-0.94 of the peak, ABS then costs a little to cycle); its value is steering during the
stop and on wet/loose ground. (Brisa has no ABS: 0.37 maximum lock slip means it never locks.)

Other tests (all pass):

| Test | Result |
|---|---|
| `Settle` | Pulse/Ranger rest at 0 cm travel on 4 wheels, wheel loads add up to the weight (Pulse 3798/2327 N front/rear), pitch/roll 0, speed < 0.6 km/h |
| `Skidpad` (r = 50 m, TCS on) | peak sustained lateral g: Pulse **0.83**, Thunderline **0.99**, Aether **1.32** (grip + downforce), Ranger **0.76** |
| `Stability250` | Vesper/Meridian/Aether at 250 km/h, 10 % steer for 0.4 s: max yaw rate 10.3 / 8.0 / 7.5 deg/s, back to 0 deg/s and 0 deg slip within 6 s, roll < 1 deg, no divergence |
| `Jump` (5 deg ramp, 122 km/h) | Pulse/Aether/Ranger fly 1.2-1.3 s, land with all four wheels, end pitch 0.6 / 0.1 / 1.5 deg, roll 0; smoothed vertical-g spike 14 / 14 / 12 g (5 m drop onto the bump stops) |
| `Surfaces` (0-60 / 60-0, asphalt = 1) | Pulse: accel x1.27 dirt, x1.42 gravel, x1.68 grass, x1.98 sand; braking x1.13 / 1.24 / 1.41 / 1.49. Ridge (rally tyres): x0.99 / 1.03 on dirt/gravel, x1.35-1.48 on grass/sand. Ranger (all-terrain): x1.03-1.06 on dirt/gravel. Surface detection from the physical material is exact |
| `Wet` | Pulse 100 -> 0: dry 48.1 m, wetness 0.98 -> 69.6 m (x1.45, the grip table says 1/0.72) |
| `Drift` | handbrake after a left flick: > 89 deg body slip on Thunderline and Brisa (controller is crude: it spins out, see known issues) |
| `Assists` | ABS flag only with the assist on; TCS flag lights up and cuts the wheelspin on a gravel launch (Thunderline max slip 7.8 off -> 0.4 on, 49 vs 40 km/h after 4 s); toggles reach the movement component |
| `TireModel`, `Drivetrain` | curve/direction/friction-circle invariants, gearbox upshifts through the gears, reverse by the brake pedal, LSD bias sign |

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -ExecCmds "Automation RunTests Roam.Vehicle; Quit" -LogName tests -NullRHI`
(add `-ExtraArgs "-RoamTestCars=1,3,6 -RoamTestTrace"` to pick cars by roster number and print per-0.5 s traces). Rows are logged as `ROAM_DRIVETEST ...`.

In-game smoke (`-game`, L_Test, placeholder body, `testcar 3`, 60 s of `drive` commands): 125 km/h in 3rd at 20 s, 148 km/h in 4th at 58 s, braking to a stop
engages reverse (brake pedal held), a 0.6/0.6 circle keeps TCS active; screenshot shows the car at 143 km/h, gear 4, 5508 RPM, chase camera.

### Changes made to the car data (Tools/ue/cars_spec.py, first tuning round, for agent I / the lead to merge)
Thunderline `cda 0.80 -> 1.05` (fastback Cd 0.46 x 2.3 m2), tyres `mu 1.02/1.00 -> 1.08/1.15` (fat rear tyres), `shift 0.26 -> 0.22`;
Ranger `shift 0.40 -> 0.28`, `eff 0.85 -> 0.88`; Mule `cda 1.30 -> 1.55`, `shift 0.36 -> 0.26`, `eff 0.88 -> 0.90`; Brisa `cda 0.85 -> 1.00`.
Re-run `drive_test_cars_gen.py` after any change to the table.

## 3. Tuning guide

| Want | Knob (car definition unless noted) |
|---|---|
| Faster/slower 0-100 | engine torque curve (`BuildSyntheticTorqueCurve` peak kW), `Gearbox.ForwardRatios` (1st gear), `ShiftTimeSec`, `Efficiency`; traction-limited cars: tyre `PeakFriction`, `LoadSensitivity` |
| Top speed | `Aero.CdA` (v ~ CdA^-1/3), last gear / `FinalDrive`, power; rolling resistance `Tire.RollingResistance` |
| More/less grip, drifting | tyre `PeakFriction`, `SlideFrictionRatio` (higher = stickier slides), `PeakSlipAngleDeg` (higher = more progressive), `HandlingFactor` only affects the PI estimate |
| Loose surfaces | tyre `SurfaceBias[Dirt/Gravel/...]` on top of the world table (rally ~1.3, all-terrain ~1.2) |
| Wet grip | tyre `WetGripBias` (scales the wet loss of `SurfaceGripMultiplier`) |
| Body roll / squat / dive | spring rate (2*pi*f)^2 * sprung mass, damper ratio, `AntiRollNPerM`, COM height, `TravelUp/Down` |
| Landing harshness | `BumpStopNPerM`, `TravelUpCm` |
| Braking | `Brakes.PeakDecelerationG` (total), `BiasFront` (half effect, EBD does the rest), `ABSSlipRatio`, tuning `BrakePressureScale` |
| Launch behaviour | `Engine.InertiaKgM2`, `ThrottleResponseSec`, assists `TCSStrength` (0.35 + 0.6 x strength = maximum torque cut) |
| Steering feel | `Steering.MaxSteerAngleDeg`, `SpeedReduction` curve, `SteerRateDegPerSec`, assist `SteeringAssist` |
| Aero balance | `ClAFront/ClARear`, `GroundEffect`, active wing |
| Model constants (code) | `TyreV0` 2.5 m/s (standstill regularisation), TCS target 1.1 (+1.5 x looseness), EBD blend 0.5, ABS threshold 0.9 x `ABSSlipRatio`, air-control gains in `RoamVehicleMovementPhysics.cpp` |

Upgrades (`SetUpgrades`) map first-pass to: `Engine.Tune` +4 % torque/tier, `Engine.Intake/Exhaust` +2 %, `Platform.Brakes` +6 % brake, `Platform.Springs`
+5 %, `Platform.AntiRoll` +10 %, `Platform.Weight` -3 % mass, `Tires.Compound` +4 % grip, `Tires.Width` +2 %, `Drivetrain.Transmission` shorter shift,
`Aero.*` +4 %. Tuning (`SetTuning`): final drive multiplier + gear spacing, tyre pressure (optimum 32 psi), camber (visual), anti-roll/spring/damper
scales, ride-height offset, brake balance/pressure, aero levels, diff accel/decel lock, centre split.

## 4. Test infrastructure notes (things that cost time)

* A bare world ticked in a loop must `++GFrameCounter` before every `World->Tick`: the tick task manager skips tick functions that already ran in the
  current engine frame, so otherwise only the first tick runs actors AND physics (this is why the older activity test stepped the car by hand).
* The Water plugin subscribes `GEngine->OnActorMoved` per world; creating and destroying several game worlds in one process leaves stale bindings and the
  next moving actor crashes inside `UnrealEditor_Water`. The drive tests therefore share one never-destroyed world and cars are destroyed individually.
* The physics model needs `RoamWorldStatic` (or a Block response on `Roam_Wheel`) on everything the wheels drive on; `RoamActivityTests` keeps the
  kinematic placeholder (`SetSimMode(KinematicPlaceholder)` now also switches the body's simulation off).

## 5. Known issues / not done

* Real Blender cars were not available in this worktree: the real-hull path (UCX hulls, COM nudge and inertia scale against the computed tensor) is
  implemented but only the box-proxy path has been exercised. Check `ROAM_VEH` verbose log "Vehicle physics body: ... inertia computed/wanted" with a real car.
* The scripted drift test spins the cars (89 deg); a controlled drift needs a better driver model or a human; stability control is oversteer-only
  (no understeer correction), steering assist is first-pass.
* Camber is telemetry/visual only (no camber thrust), no tyre temperature/wear, no anti-dive/anti-squat geometry, no weight-dependent wheel inertia.
* The visuals component still spins the wheels from the vehicle speed; `Telemetry.WheelAngVelRadS` is there for burnouts. Wheel rotation is not mine.
* Landing spike of ~14 g (smoothed) after a 5 m drop: survivable, softer bump stops would feel better.
* `FlipUpright`/`ResetToRoad` use `TeleportVehicle` (velocity zero, wheel state reset); `TeleportVehicle(bKeepSpeed)` uses `RestoreForwardSpeed` (not covered by a test).
* No changes to `Config/DefaultEngine.ini` were necessary: the existing 120 Hz async step is what the model uses.

## 6. Appendix: integration pass on the real world (L_Main, real meshes) - agent Q1 "driving + loop"

Code: `Vehicle/RoamAutoDrive.{h,cpp}` (console `autodrive`, `cartest`), `Vehicle/RoamVehicleVisuals.cpp` (paint / lamp / rim / disc / weather material control, wheel spin from the physics), body mass setup in `RoamVehicleMovementPhysics.cpp`,
`ARoamGameMode::SnapOffMedian`. Logs: `Tools/Logs/q1_cartest3.log` (10 cars), `q1_loop1.log`, `q1_spots1.log`, `q1_cams_top.log`, `q1_loop3.log` (markers `ROAM_CARTEST_*`, `ROAM_AUTODRIVE_*`, `ROAM_VEHICLE_BODY|HIT|MASSFRAME`).

### 6.1 Fixes found by the real-mesh run
* **Parked car never moved again.** A body that rests for ~3 s fell asleep in Chaos and `StepPhysics` returns early for a sleeping particle (full throttle, rpm 800, speed 0, three of ten cars). `EnsureBodyReady` now sets `ESleepType::NeverSleep` on the particle.
* **Mass properties of real hull bodies.** The UCX hulls give a principal frame that is rotated (roll 180 deg, pitch 3-8 deg) and a hull-uniform tensor with roll > pitch; scaling it per axis left Meridian/Aether with 95 % / 83 % of the weight on one axle at rest and a 4 km/h creep. The final mass properties (centre of mass, inertia in the body frame) are now written on the physics proxy directly. Result at rest, all ten cars: hub height = tyre radius (+- 0.0-0.5 cm), 4 wheels loaded, load split left/right within 2 %, speed 0.0-0.4 km/h, no jitter (z range < 0.6 cm).
* **Spawn / teleports on the highway median barrier.** `loop_start`, `highway_plateau` ... sit on the HIGHWAY centreline = on the 0.8 m New-Jersey barrier: wide or low cars landed on it (3 wheels, 40-60 degree rolls). `ARoamGameMode::SnapOffMedian` moves the transform into the forward lane (spawn POI path and `ARoamVehicle::TeleportVehicle`, i.e. `tp`).
* Paint / lamps: `RoamVehicleVisuals` was a stub; it now creates dynamic instances for `M_Paint`, `M_Paint2`, `M_Headlight`, `M_Taillight`, `M_Reverse`, `M_Indicator`, `M_Rim`, `M_BrakeDisc`, `M_Glass` and drives the parameter contract of `CARS_IMPORT.md` (colours, 3 finishes, stripe style, lamp `Intensity`, `HeatGlow`, `Wetness`/`RainIntensity`). A car without a saved paint starts in `SuggestedPaints[0]`.

### 6.2 Ten cars on the real map (`cartest 1 10 9`, lane of HWY_EAST, ~3 % grade)
Rest stance PASS for 10/10 (limits: hub - radius < 3 cm, 4 wheels, tilt < 2.5 deg, < 3 cm jitter). Per car (3 s settle, autopilot at full throttle for 9 s, then full brake), measured with the first build of the autopilot
(speeds are limited by the road curvature and by the bumps below, not by the cars): wheel animation `meshYawFL == telemetrySteerFL` for all cars, steering-wheel mesh angle = steer x ratio, rear wheel spin 1.0-1.1 x telemetry
(`ROAM_CARTEST_WHEELVIS/SPINVIS`); tail lamp material 0.10 -> 1.00 while braking for 10/10 (`ROAM_CARTEST_LAMPS`), `M_Paint` PrimaryColor read back equals `FRoamPaint.Primary`, `grey=0` material slots on every car.
Braking from 95-120 km/h on the road: 0.56-1.02 g average over the whole stop (Ranger 0.56, Mule 0.58, Aether 1.4 from 182 km/h).

### 6.3 Autopilot (`autodrive [on|off|stat|at <road> <sM> [kmh] [km]|over <f>|grip <f>|lane <n>|loop on|off] [speedKmh] [stopAfterKm] [quit]`)
Pure pursuit on the lane of the road network (look-ahead 0.7 s + 3.5 m), speed = min(cruise cap, limit x 1.3 [x1.0 without cap]) lowered by horizontal curvature (0.45 x car lateral g), by the vertical crest table of the road samples
(`z''` -> a = 0.5 g) and by traffic ahead (sweep on `Roam_Traffic`, 1.3 s gap). Recovers by teleporting back into the lane after stuck 4 s / off-road 2.5 s / below the road. `cartest ... cams` also shoots chase/hood/cockpit/bumper.
HWY_EAST at 150 km/h cap: 5.34 km in 147 s (avg 131 km/h, 122-147 km/h), 0 stuck / 0 off-road / 0 fall, lateral error < 1.3 m, p99 frame 22 ms (`q1_loop3`).

### 6.4 Loop test results and open problems (not fixed here: world data, not vehicle code)
1. **Junction pad `X_LOOP_COAST_LOOP_SOUTH_0` (LOOP_COAST s ~ 675 m, world (-1121, 1070) m, z 21.5)**: the known 1 m step (WORLD_BUILD issue 11) is a wall for a car: `ROAM_VEHICLE_HIT SM_RJ_X_LOOP_COAST_LOOP_SOUTH_0 dv 3.6 m/s at 83 km/h`, car lifted onto the pad, stuck. Every run stops here.
2. **Vertical kinks in the road profile**: `roads.json` has crests with `z''` up to -0.08 1/m (radius 12 m) at LOOP_PASS s = 3123, 3141, 3339, 3465, 3865, 3867, 4173 and 1002 m (similar on LOOP_DESC): the car leaves the ground at 60 km/h ( `ROAM_AUTODRIVE_BUMP`, wheelsOnGround 0, vertG 0.05, +20..+140 cm). The autopilot now slows for them (untested after the change); the profile should be smoothed in the generator.
3. HWY_EAST bumps of 2.2-3.5 g at 125-216 km/h every 100-300 m (first at s = 213-300 m next to the start, bridge ends s = 4956 / 5445, seams of `SM_RC_HWY_EAST_04` s = 1373 and `_09` s = 2852): launches of 50-270 cm; with them the Aether weaves +-5-10 m and reached only 221 km/h (the 250 km/h / 30 s target was NOT reached on the real road; the flat-map Stability250 test passes).
4. Roadside furniture on the mountain pass blocks cars that cut a hairpin: `SM_rs_parapet_mountain_3m`, `SM_rs_guardrail_4m`, `SM_rs_sign_chevron_*` (foliage-instanced actors with blocking collision), also `SM_nat_rock_mesa_b` on LOOP_DESC.
5. Tidewick: after LOOP_SOUTH#0 the autopilot turned into the dead-end `LOCAL_TIDE_HIGH` (lorry parked at its end); the continuation rule was relaxed afterwards (alignment > -0.5), NOT re-run.
6. First 24 km run (`q1_loop1`, build before the planner changes): 24.0 km in 1235 s game time (avg 70 km/h, max 150), 26 recoveries, 94 bumps, p99 frame 18.7 ms, 18 frames > 250 ms (max 853 ms, World Partition streaming), no frame > 50 ms between streaming events at the highway; no fall-through caused by a collision hole was found (the one `fell_below_road` was after the Tidewick pad), cars stay on the ground mesh everywhere they were driven.
