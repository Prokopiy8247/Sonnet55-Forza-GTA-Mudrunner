# FEATURE_MATRIX.md

Status vocabulary: `WORKING` (functional in-game path exists and was verified by a test or capture) · `PARTIAL` · `NOT IMPLEMENTED`.
"Verified" below names the evidence: the in-game automated physics suite (`Docs/PHYSICS_SUITE_REPORT.txt`, run by `Tools/rt.sh <name> RuntimeSuite`), PlayMode tests, or GPU captures. Visual-only claims that were not re-captured inside the final Game scene are marked PARTIAL.

| Feature | Status | Notes |
|---|---|---|
| **Ground / mud physics** | | |
| Per-cell surface types (rock, firm soil, grass, gravel, shallow mud, deep mud, bog, sand) | WORKING | `GroundMap` weights + `SurfaceDatabase` Bekker/Janosi table; static sinkage table in the suite |
| Viscosity/softness, wetness (rain), hidden extra depth | WORKING | `SoilSample` wetness softening, `extraDepth` map used by the world generator for traps |
| Dynamic sinkage / rut field, persistent ruts + berms | WORKING | `MudField` toroidal 256 m window, 0.25 m cells, sparse store; verified in captures with real vehicles |
| Ruts fill back with time/wetness | WORKING | relaxation step (diffusion + decay by fluidity x wetness); no dedicated numeric test |
| Wheel sinkage from load / contact area / softness; narrow vs wide tyres | WORKING | `TireSoilModel.SolveSinkage`; hauler (wide) floats where scout (narrow) bogs |
| Wheel spin digs deeper than controlled throttle | WORKING | suite check "spin vs controlled" (spinning moves less and digs deeper in deep mud) |
| Rolling + bulldozing resistance, compaction | WORKING | `Wheel.ResistanceAt`; compaction stiffens ruts |
| Belly / body high-centring on mud | WORKING | `Vehicle.ApplyBodyContacts` against the deformed surface |
| Stuck emerges from physics (no flag) | WORKING | detector is HUD/analytics only; crossing matrix shows light vehicle stuck, heavy passes |
| Diff lock / AWD / low range improve mud climbs | WORKING | suite hill check: 2WD/open stall on 18 degree mud, locked + low range climb |
| **Rendering** | | |
| Visible deformation (GPU vertex displacement, normals, puddles) | WORKING | `GroundRenderer` + `Ground.shader`, 5-LOD chunk system; ruts from real vehicles visible in captures |
| Ground collider for rocks/logs/cargo | WORKING | `GroundColliderBuilder` (never an asset) |
| **Vehicles** | | |
| Three data-driven vehicle classes (scout 2.0 t, utility 4.2 t, hauler 9.0 t) | WORKING | `VehicleDefinition`; all drive in the Game scene (smoke tests) |
| Blender-authored vehicles with visible suspension, imported to Unity | WORKING | 3 vehicles + log trailer FBX (51-190 mesh objects, LODs, collision proxies); prefabs built by `VehiclePrefabBuilder`; spring/shock/link/axle parts follow the wheels (`SuspensionVisuals`) |
| Independent suspension, spring/damper/bump stops, anti-roll, articulation | WORKING | project-owned solver; settle tests, rock-course articulation numbers |
| Stability on rocks / props | WORKING | rock-course scenario for all three vehicles (no jitter/explosion) |
| Engine torque curve, stall, auto + manual gearbox, low/high range, reverse | WORKING | `Drivetrain`; auto-shift fixed to avoid hunting |
| AWD, front/rear/centre diff locks | WORKING | impulse-coupled locks; fuel use per load |
| Fuel consumption + refuel at garage | WORKING | consumption in suite/tests; refuel via garage menu (UI test) |
| Damage / repair | PARTIAL | repair button and `damage01` state exist; no damage model |
| Headlights, brake/reverse lights | PARTIAL | `VehicleLights` (spot lights, emissive lenses); not visually verified at night |
| **Recovery / water / cargo** | | |
| Winch (anchor, rope, rated pull, reel in/out, cable visual) | WORKING | suite: bogged utility pulled out of bog |
| Towing by a second vehicle | PARTIAL | winch to another vehicle works; no strap mode |
| Recover (flip/reset) with cost | WORKING | `GameManager.RecoverPlayer` (fuel + time penalty) |
| Shallow water drag/current, deep water buoyancy, floating, swept away, engine flooding | WORKING | suite ford test: pass below rating, fail/float above (rating from intake height and float depth) |
| Trailer with hitch joint + log/barrel/crate cargo | WORKING | suite: 2.9 t logs through shallow mud, 5/5 kept |
| **World** | | |
| Proving ground (6 mud pits, 12/20/28 degree hill, side slope, articulation course, ford with current, log pile, measuring area) | WORKING | `WorldTests` 25/25, geometry measured |
| 1.5 km wilderness (3 routes, rivers, swamp, fords, bridges, landmarks, hidden traps, ruts on tracks) | WORKING | route lengths 2544 / 2130 / 1874 m, generation 3.4-4.4 s |
| Instanced vegetation / props | PARTIAL | 83k instances; procedural stand-in meshes (Blender trees/rocks exist but are not yet wired into the world's prop library) |
| Water surface rendering | PARTIAL | simple transparent mesh (VFX worker may improve; see report) |
| Weather: rain raises wetness, puddles, time of day | WORKING | `AtmosphereController` (sun, fog, wetness); ground shader puddles |
| **Game / UI** | | |
| Free drive + scenarios (timer, fuel limit, cargo) | WORKING | `ObjectiveManager` + 4 scenarios; main menu starts them |
| Chase / cockpit / wheel / top / free cameras | WORKING | `CameraRig` (UI tests: mode switching, ground clamp) |
| HUD, minimap, full map, compass, physics overlay, stuck warning | PARTIAL | HUD, minimap, compass, objective panel, stuck banner seen on standalone-player screenshots (`Docs/screenshots/play_*.png`); full map and physics overlay not seen |
| Debug/benchmark menu (teleport, spawn, trailer, mud multipliers, rain/time, overlays, suite) | PARTIAL | built and unit-tested; IMGUI layout not visually reviewed |
| Procedural audio (3 engines, mud/water/gravel, suspension, winch, rain, ambience) | WORKING | 48 audio tests, offline renders verified numerically; not listened to |
| Save / load (vehicle, position, fuel, time, weather, objective, mud field) | PARTIAL | `SaveSystem` implemented (F5/F9); no dedicated round-trip test |
| Automated physics test suite (CLI + debug menu) | WORKING | `RuntimePhysicsSuite`, PlayMode tests |
| Gamepad | PARTIAL | basic driving, shifts, locks |
| VFX: wheel mud/dust/water spray, hull wake, exhaust, rain streaks, water shader, procedural sky | PARTIAL | installed automatically (`VfxDirector`), VFX tests pass; only mud spray + rain were seen on screen; vehicle dirt shader not implemented |
