# DEVELOPMENT.md — Unity 6 MudRunner-style off-road mud simulation (working title: **Mire & Iron**)

Original game; MudRunner / Spintires / SnowRunner were used only as a mechanics/feature-scope reference (see `RESEARCH_NOTES.md`).
Primary focus: **the physics of mud and of vehicle suspension/wheels**; the player must read the terrain and find a path so the vehicle does not get stuck.

## 1. Environment (verified)
| Item | Value |
|---|---|
| Project | `W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner` (single Unity project; no nested projects) |
| Unity | 6000.6.0f1, URP 17.6.0, Input System 1.20 (Input System *only*: `activeInputHandler: 1`), Burst 2.0, Collections 6.6, Test Framework 1.8, **com.unity.pipeline 0.8.0-exp.1** (added per Unity CLI docs) |
| Machine | Windows 11, RTX 5070, 64 GB RAM, 16 logical cores |
| Language | C# (asmdefs `MudRunner.Runtime`, `MudRunner.Editor`, `MudRunner.Tests.PlayMode`; namespaces `MudRunner.*`) |
| Git | initialised in the project folder; milestone commits; `Library/ Temp/ Obj/ Logs/ UserSettings/ Builds/` ignored |
| Start | run id `run-20261016-184652`, start 2026-10-16 18:46:52 +0200 (`.sonnet-5.5-mudrunner-runs/…/start_time.txt`) |

### Blender MCP (verified before any change)
* Server/tool namespace: `mcp__blender-mudrunner-unity__*` (declared in `.mcp.json` as `uvx mcp-for-blender --port 9891`), host `localhost`, **port 9891**.
* Real read-only call `bpy.data.filepath` returned `W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner\UnitySonnet5.5Mudrunner.blend` (= the master file in the project folder, Blender 5.2.2 LTS, add-on 1.8, protocol 13; scene was the default Cube/Light/Camera).
* Backup before the first modification: `Backups/UnitySonnet5.5Mudrunner_baseline_20261016-1847.blend` (git-ignored). External asset libraries/generators (`search_assets`, `import_asset`, `generate_3d`) are **never used**.
* Axis/scale convention proven with a Unity import test (Section 8).

## 2. Repository layout
```
Assets/Game/Runtime/        Ground/ (map, mud field, soil table, water map, service) Vehicles/ (wheel, drivetrain, vehicle, winch, water, factory)
                            Game/ (GameManager, input, camera placeholder, bootstrap) Cargo/ (trailer, cargo) Atmosphere/ Objectives/
                            Rendering/ (ground renderer + shaders: render worker)  World/ (procedural worlds)  UI/ CameraSystem/ Audio/  Testing/ (bots, arenas)
Assets/Game/Art/            Blender-exported FBX (Vehicles/ Trailers/ Props_Nature/ Props_Structures/ Cargo/)
Assets/Game/Shaders/        Ground shader etc.
Assets/Editor/              ProjectSetup, GameSceneBuilder, FbxInspector, prefab builders, capture harnesses
Assets/Game/Tests/PlayMode/ automated physics + game tests
Docs/                       ART_SPEC, RENDER_SPEC, WORLD_SPEC, UI_SPEC (contracts between workers)
Tools/                      ub.sh (locked batch Unity), rt.sh (tests), qc.py (no-Unity compile check), test_summary.py, blender_helpers.py
```

## 3. Mud & terrain physics design (the heart)
### 3.1 Decision: smooth physical ground + virtual sinkage field
* The **physical ground** is a static, smooth height map (`GroundMap`, 1 m cells, float heights; optional `TerrainCollider` for rocks/logs/cargo only).
  It is never modified at run time, so there is no `TerrainData` persistence problem, no collider rebuilds and no popping.
* The **virtual surface** the wheels roll on is `height(x,z) + dh(x,z)`, with `dh` from the **`MudField`**: a CPU-authoritative field of 0.25 m cells.
  Vehicle bodies do **not** collide with the terrain layer (layer matrix); they are carried by the wheel solver plus *belly/body contact points* sampled against the deformed surface (so ground clearance, high-centring and rollover on mud are physical).
* Why: the research (pitfalls verified in `RESEARCH_NOTES.md` §4.1) shows `SetHeights` on big regions is slow, collider updates are expensive, and runtime edits persist into the asset; the visible and physical surface need not be the same data. The field is local, cheap, persistent and renders through vertex displacement.

### 3.2 Data layout (`Assets/Game/Runtime/Ground`)
| Data | Layout | Notes |
|---|---|---|
| `GroundMap.height` | `float[size²]`, 1 m (2049² for the 2 km world) | macro terrain, bilinear |
| `GroundMap.weights` | `byte[size²·8]` surface weights | Rock, FirmSoil, Grass, Gravel, ShallowMud, DeepMud, Bog, Sand → blended `SurfaceParams` |
| `GroundMap.extraDepth` / `baseWet` / `fluidity` | `byte[size²]` | hidden extra soft depth (0–2 m, designer-painted traps), base wetness, derived rut-relax rate |
| `WaterMap` | `float[]` surface Y + `sbyte[]` flow x/z | rivers/ponds/swamp water; buoyancy, current, fording |
| `MudField` window | `MudCell{dh, churn, compact}[1024²]`, 0.25 m → 256 m, **toroidal** | follows the player in 16 m steps; GPU mirror = RGBAHalf `Texture2D` (Repeat), 64² dirty tiles via `Graphics.CopyTexture` |
| `MudField` store | `Dictionary<tile, MudCell[64²]>` sparse | evicted tiles persist for the session ⇒ ruts survive across the whole map; snapshot/restore API for save games |

### 3.3 Soil model (per wheel, every 10 ms) — `TireSoilModel.cs`, `Wheel.cs`
Reduced Bekker–Wong–Janosi (units SI/kN, see `SurfaceParams.cs`):
* pressure–sinkage `p = (kc/b + kφ)·zⁿ`; equilibrium sinkage `z_eq` solves `F_z = k·zⁿ·b·l(z)` by bisection, `l = 2√(2R·z_tot − z_tot²)`, `z_tot = z + δ_tyre/(1+6z/R)` (tyre deflection relaxes in soft soil); soft-layer depth (surface table + hidden `extraDepth`) caps it. Compaction (`1+gain·compact`) and churn (`1−0.45·churn`) scale the stiffness.
* shear/thrust `H = A·τ_max·[1 − K/(i·l)(1 − e^(−i·l/K))]`, `τ_max·A = c·A·cohMul + F_z·tanφ·fricMul`; tyre tread type (highway / all-terrain / mud-terrain / flotation) multiplies cohesion/friction; hard-surface grip `μ·F_z` for rock/gravel; wet soil lowers `c`, `φ`, `k` (`wetnessSensitivity`).
* resistances: compaction `R_c = b·k·zⁿ⁺¹/(n+1)`, bulldozing `R_b = f·b·z·(c·K_c + ½γz·K_γ(1+tanφ))` evaluated at the *incremental* sinkage at the leading edge (so riding in an existing rut is easy, pushing a berm is hard), plus rolling resistance. Applied as vehicle forces (not wheel torque).
* **sinking is dynamic and plastic**: the wheel carves the field toward `max(rut depth, z_eq)` with a viscosity-limited rate (`τ = 0.04 + 0.5·viscosity` s); only plastic depth is written, nothing rebounds.
* **spin digging**: `ṡ_dig = digRate·(|v_slip| − 0.25|v| − 0.35)·room²·(0.4+0.6·load)·(0.5+churn)`, i.e. a spinning wheel carves itself down (positive feedback through resistance & bulldozed front pile) — stuck-ness emerges from `thrust < resistance + slope`, never from a flag.
* displaced volume: `MudField.CarvePatch` removes volume from the footprint, deposits 55 % into side berms and 20–40 % into a front pile (capped), churns the surface (visual + softening) and compacts it (stiffer second pass); ruts relax (flow back) at `fluidity·(0.25+1.5·wetness)` via diffusion+decay (firm soil: almost never; bog: seconds–minutes).

### 3.4 Wheel/suspension solver (project-owned, no `WheelCollider`/`ArticulationBody`)
* Per wheel: the wheel *circle* (7 arc × 3 width samples) is solved against the **deformed** height field with 4 Newton-like iterations (softmax-weighted penetration ⇒ no flicker), limited by suspension travel; props/rocks/logs via a `SphereCast` on the Props/DynamicProps layers. Contact normal from the surface gradient over the tyre footprint (rut walls steer the wheel).
* Spring + bump/rebound damper (low-passed length for the damper) + bump stop; per-axle anti-roll bars; per-wheel static load from the CoM; independent travel left/right ⇒ solid-axle articulation (wheel droops while the other climbs); forces applied with `AddForceAtPosition` at 100 Hz (fixed step 0.01 s, TGS solver, 12 iterations).
* Tyre force uses impulse-limited friction (`|F| ≤ m_eff·|v_slip|/dt`) so there is no sign chatter at rest; friction ellipse for combined slip.
* Weight transfer, pitch/roll and slides emerge from forces applied at the contact patch / hub height.

### 3.5 Drivetrain (`Drivetrain.cs`)
Engine torque curve + inertia + friction/engine braking + idle governor + stall; clutch/converter engagement by rpm with an **implicit lock solve** against the wheels' ground torques (stable even when wheels spin free); 5–6 gears, reverse, low/high range, auto (wheel-equivalent-rpm shifting) and manual; AWD switch; open/locked axle differentials (impulse coupling, no cap) and centre-lock; fuel from idle/full-load rates; engine off when fuel runs out or the intake is under water.

### 3.6 Recovery, water, cargo
* **Winch** (`Winch.cs`): unilateral rope with stiffness, damping and a rated pull cap; reel speed drops under load; anchors = `WinchAnchor` (trees/posts/stumps, static or dynamic) or another vehicle; auto-anchor cone; cable rendered with sag.
* **Water** (`WaterMap.cs`, `VehicleWater.cs`): 9-column hull buoyancy + tyre buoyancy, drag against the current, floating when net buoyancy > weight, engine intake flooding (stall + 12 s drying).
* **Trailer & cargo** (`TrailerSystem.cs`): trailer = a `Vehicle` without engine; `ConfigurableJoint` hitch (yaw 75°, pitch 20°, roll 15°); surge brakes; logs/barrels/crates as dynamic bodies whose weight loads the trailer suspension.

## 4. Vehicles (data: `VehicleDefinition` ScriptableObject; factories bake `.asset` files)
| | Scout (Pathfinder 4×4) | Utility (Bruiser 4×4) | Hauler (Mammoth 6×6) | Log trailer |
|---|---|---|---|---|
| mass | 2.0 t | 4.2 t | 9.0 t | 1.5 t (+≈3 t logs) |
| tyres (R × w) | 0.40 × 0.235 all-terrain | 0.54 × 0.375 mud-terrain | 0.76 × 0.60 flotation | 0.54 × 0.375 |
| engine | 255 Nm @ 2500 | 700 Nm @ 1800 | 1900 Nm @ 1500 | – |
| gearbox | 5 + R, low ×2.5 | 5 + R, low ×2.7 | 6 + R, low ×2.4 | – |
| winch | – | 45 kN / 30 m | 70 kN / 35 m | – |
| fording rating (intake) | 0.55 m | 0.85 m | 1.2 m | – |
Full numbers: `VehicleDefinition.cs` factories (`CreateScout/Utility/Hauler/LogTrailer`) — mass & CoM, torque curve, ratios, per-axle tyre/spring/damper/travel/anti-roll, fuel, winch, fording, damage.

## 5. Controls (keyboard + mouse; gamepad partial)
`W/S` throttle/brake-reverse · `A/D` steer · `Space` handbrake · `LShift/LCtrl` shift up/down (manual) · `M` auto/manual · `R` low/high range · `T` AWD · `F` front diff lock · `G` rear diff lock(s) · `V` centre lock · `I` ignition · `Z` winch hook/release · `Q/E` winch out/in · `C` camera · `Tab` map · `H` help · `Backspace` recover (costs fuel + time) · `` ` `` debug menu · `F2` physics overlay.

## 6. Build / run
```bash
Tools/ub.sh compile -                                           # import + compile (batch, no graphics)
python -I Tools/qc.py                                            # 10 s compile check without Unity
Tools/ub.sh scene MudRunner.EditorTools.GameSceneBuilder.BuildAllFromCli
Tools/rt.sh tests ""                                            # all PlayMode tests (logs numbers with [MudRunner])
GFX=1 Tools/ub.sh shot <Class.Method>                           # rendering / screenshots on the GPU
```
Open `Assets/Scenes/Game.unity` and press Play (the scene is tiny; the world and vehicles are generated by code).

## 7. Other modules (written by parallel workers, integrated by the lead)
| Module | Folder | Notes |
|---|---|---|
| Ground renderer | `Runtime/Rendering`, `Shaders/Ground*.shader|hlsl` | 32 m chunks, 5 shared grid LOD meshes with skirts (0.25 m ... 4 m), vertex displacement from the mud-field texture, 8-layer texture arrays generated procedurally (0.9 s), puddles in ruts, wet gloss; 0 B GC per frame, LOD sweep 0.3 ms for 4096 chunks; `GroundColliderBuilder` creates a runtime-only `Terrain` collider |
| World | `Runtime/World` | deterministic generator (seed 20260611), 2049² map at 1 m: hills, mountain ring, swamp, river Silverrun + creek (WaterMap with current), 3 routes (north 2544 m, central 2130 m, swamp 1874 m), 556 structures, 83k instanced props, hidden-depth traps, pre-carved ruts; proving ground: 6 mud pits, hill 12/20/28 degrees, side slope, articulation course, ford with current, log pile; generation 3.4-4.4 s; `WorldTests` 25/25 |
| UI / camera | `Runtime/UI`, `Runtime/CameraSystem` | code-built uGUI HUD (gauges, compass, minimap/full map, physics overlay, stuck warning, toasts), main/pause/garage menus, IMGUI debug menu, `CameraRig` (chase, cockpit, wheel close-up, top, free) |
| Audio | `Runtime/Audio` | 100 % procedural: 3 engine timbres, mud/gravel/grass/water, suspension creaks, winch, rain, wind, ambience; 48 tests, 39 offline renders verified numerically |
| VFX | `Runtime/Vfx`, `Shaders/Vfx` | pooled wheel mud/dust/water spray, hull wake, exhaust, rain streaks, water surface shader, procedural sky, `VfxDirector` |
| Blender art | `Assets/Game/Art`, `Docs/ART_SPEC.md`, `Tools/blender_helpers.py` | 3 vehicles + log trailer + log/barrel/crate/stump + 3 spruce, birch, dead tree, bush, reeds, 4 rocks, anchor post; LODs, collision proxies, suspension markers |

## 8. Blender -> Unity workflow
`UnitySonnet5.5Mudrunner.blend` -> Blender MCP edits (all through `mcp__blender-mudrunner-unity__`, helpers in `Tools/blender_helpers.py`) -> save -> FBX (`Docs/ART_SPEC.md` section 1 recipe: forward -Z, up Y, `FBX_SCALE_ALL`, bake space transform) -> `Assets/Game/Art/**` -> `ModelPostprocessor` (import settings, `MR_*` material remap to `Assets/Game/Materials`) -> `VehiclePrefabBuilder` (definition assets in `Assets/Resources/Vehicles`, prefabs in `Assets/Resources/VehiclePrefabs`: wheels bound by name, `COL_*` boxes -> colliders, hub/axle/tyre numbers measured from the model, intake height -> fording rating, per-vehicle paint colours, LODGroup) -> `VehicleVisualBinder` / `SuspensionVisuals` / `VehicleLights` at run time.
Proven axis mapping: Unity(x,y,z) = (-Blender x, Blender z, -Blender y) -> vehicles face **Blender -Y**. Exported node names carry an `Asset__` prefix; runtime code ignores it (`ModelNames.Norm`).
Rebuild everything: `Tools/ub.sh prefabs MudRunner.EditorTools.VehiclePrefabBuilder.BuildAllFromCli` then `Tools/ub.sh scene MudRunner.EditorTools.GameSceneBuilder.BuildAllFromCli`.

## 9. Tooling notes (lessons learned)
* `Tools/ub.sh` serialises every Unity batch run with a lock (Windows PID owner, stale detection), waits while any other editor has the project open, and kills runs after 25 minutes; `Tools/retry.sh` re-runs on foreign compile errors or licence-client clashes; `python -I Tools/qc.py` compiles the three assemblies in ~10 s without Unity.
* Several parallel writers on one Unity project cost many minutes of queueing and occasional foreign compile errors; the work was nonetheless parallelised (renderer, world, UI, audio, VFX, Blender) behind written contracts in `Docs/*_SPEC.md`.
* `-burst-disable-compilation` (`NOBURST=1`) avoids a hang when the Burst compile server does not start in a batch editor.

## 10. Test results (final numbers: `Docs/PHYSICS_SUITE_REPORT.txt`, `Logs/cli/final1.*`)
In-game automated physics suite (`RuntimePhysicsSuite`, also the debug-menu button), 21/21 checks as expected:
* static sinkage / thrust margin per vehicle and surface; scout stuck in deep mud and bog, utility passes deep mud only with diff locks + low range, hauler passes deep mud by momentum or locks, nobody crosses bog without a winch;
* spinning wheels dig deeper and progress less than controlled throttle (deep mud);
* 18 degree mud hill: 2WD and open diffs stall, locked + low range climbs (utility 36 s, hauler 42 s);
* winch pulls a bogged utility out of the bog (peak tension 17 kN of 45 kN);
* fording with a 1.5 m/s current: below the rating (min of intake height and float depth) every vehicle crosses; above it vehicles stall or float away (scout rated 1.66 m, utility 1.72 m, hauler 2.58 m);
* rock course (8 rocks alternating sides): all three complete, max angular velocity 1.1 rad/s, tilt <= 7 degrees, axle articulation up to 0.31 m strut difference;
* trailer with 2.9 t of logs through shallow mud: crossed, 5/5 logs kept, max hitch angle 1 degree;
* performance: vehicle physics 0.74 ms per fixed step for 4 vehicles churning mud (about 0.19 ms per vehicle), frame average 7.4 ms at timescale x3.
Other suites: `WorldTests` 25/25, `AudioTests` 48/48, UI tests 10/12 at last run (two fixes not re-run), `GameSmokeTests` (all three vehicles drive in the Game scene).

## 11. Known limitations
* HUD (speedometer, tacho, minimap, compass, objective panel, vehicle panel, help overlay, stuck banner) and the main menu were reviewed on player screenshots (`Docs/screenshots/play_*.png`); the full map, pause menu, garage and the IMGUI debug menu were not seen.
* Audio was verified only numerically (nobody listened); gains will need a first listen.
* Real Blender props (trees, rocks, logs) exist as FBX but the world still instances procedural stand-in meshes (`IPropLibrary` seam is in place); Blender buildings/bridges/signs were not modelled (procedural stand-ins are used).
* Vehicle dirt shader, windscreen droplets, lightning, dynamic wake texture, damage model and tow-strap mode are not implemented.
* Save/load has no automated round-trip test; the mud-field snapshot is stored but untested across a reload.
* The ground shader's SRP-Batcher compatibility was not confirmed; wet specular makes the swamp look pale from above.
* Soil parameters are gameplay-tuned values loosely based on published terramechanics ranges, not measurements (see RESEARCH_NOTES.md).

## 12. Standalone-player verification and the "car falls into the void" bug
* **Bug (fixed):** starting Free Drive "Wilderness" or any scenario from the menu calls `GameManager.StartWorld` while a world already exists. `Teardown` used `Destroy(GroundService)`, which only takes effect at the end of the frame, so the new `GroundService.Awake` still saw the old `Instance`, destroyed itself, and both were gone after the frame: no ground height, no deformation field, the vehicle fell forever. It never showed in the tests because they started a world only once. Fix: `GroundService.Retire()` releases the singleton immediately (called by `Teardown`); regression test `GameSmokeTests.StartWorld_Twice_KeepsGroundAndVehicleStaysOnIt`.
* **Player automation** (`Runtime/Testing/PlayerAutomation.cs`): `MireAndIron.exe -mrworld wilderness|proving|arena [-mrvehicle scout|utility|hauler] [-mrdrive m/s] [-mrfull] [-mrroute N] [-mrswitch wilderness|proving] [-mrscenario N] [-mrswitchat s] [-mrshots dir] [-mrinterval s] [-mrquit s]` skips the menu, optionally drives the scripted bot (along route N of the wilderness), starts another world/scenario through the real UI start routine, logs the vehicle state every second to `Player.log` (`[Automation]`) and writes screenshots with the HUD. Used to confirm: wilderness north road driven for 450 m, proving ground, world switch and scenarios keep the vehicle on the ground.
