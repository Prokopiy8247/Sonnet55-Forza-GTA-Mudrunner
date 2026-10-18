# DEVELOPMENT.md — Roamline: Open Roads (UE 5.8 + Blender MCP)

> Living document. Original open-world arcade-sim racing game "in the spirit of" a festival-style racing game; no third-party game assets, names, logos or code are used.

## 1. Environment (verified on 2026-10-16)

| Item | Value |
|---|---|
| Project folder | `W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza` |
| Project file | `Sonnet55Forza.uproject` (C++ project, module `Sonnet55Forza`) |
| Engine | Unreal Engine **5.8.2** (changelist 56702186), `W:\Unreal Engine 5\UE_5.8` |
| Toolchain | Visual Studio (W:\Visual Studio), MSVC 14.51.36231, Windows SDK 10.0.26100.0; baseline editor build OK (63 s) |
| Git | 2.51.1 (`W:\Git\Git\cmd\git.exe`), repo initialised in the project folder (baseline commit `423cd71`) |
| Machine | Ryzen 7 5700X3D (8C/16T), 64 GB RAM, RTX 5070, Windows 11 Enterprise; other unrelated Claude sessions share the machine |
| Python (plain) | `W:\Blender\5.2\python\bin\python.exe` 3.13 + numpy 2.3 (used as a plain interpreter for generators, never as a Blender instance) |
| Editor Python | UE 5.8 PythonScriptPlugin (Python 3.11.8); API stub generated at `Intermediate/PythonStub/unreal.py` |

### Blender MCP connection (mandatory routing rule, Section 2.1 of the task)
* MCP server: **`blender-forza-unreal`** declared in the project's `.mcp.json` as `uvx mcp-for-blender --port 9889`; tool namespace actually used: `mcp__blender-forza-unreal__*` (`get_addon_status`, `get_scene_info`, `execute_blender_code`, `look`, ...).
* Endpoint: **localhost:9889** (listening process = `blender.exe` PID 25876, window title `UnrealSonnet5.5Forza`). Other Blender instances on the machine (ports 9890/9891, other projects) are never touched.
* Verified by real read-only calls: `bpy.data.filepath` = `W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\UnrealSonnet5.5Forza.blend`, Blender **5.2.2 LTS**, add-on protocol 13 (up to date), default scene only (Camera, Cube, Light) at session start. Path equals the master file in the project folder (not just the basename).
* Backups before the first modification: `Backups/Blender/UnrealSonnet5.5Forza_pre-modification_*_sonnet55.blend` (byte-identical to the untouched master; SHA-256 `56173FEB…EF526`). A second backup from an earlier aborted session of another model (`…_20261016-1842.blend`) is identical too.
* Default scene objects were moved (not deleted) into the excluded collection `_SceneDefaults`; asset collections live under `FORZA_UE/{Cars,Traffic,Props,Settlements,Roadside,Nature,Roads,Bridges_Tunnels,Collision,_Staging}`.

## 2. Reproducible tooling (checked in)
| Script | Purpose |
|---|---|
| `Tools/build_editor.ps1` | UnrealBuildTool wrapper (Editor target by default, `-Target Sonnet55Forza` for game), per-project mutex, error summary |
| `Tools/ue_cmd.ps1` | Headless/windowed Unreal runner: `-PythonScript`, `-ExecCmds`, `-Game -Map`, log capture in `Tools/Logs/` (always pass script paths with forward slashes — UE's argument parser mangles some `\x` sequences) |
| `Tools/blender/lib/fbx_export.py` | Blender → FBX recipe (verified: 4 m body → 400 uu, +X forward kept, left side → −Y, per-part pivots) |
| `Tools/blender/...` | Idempotent asset build scripts executed inside the verified Blender session |
| `Tools/world/...` | Procedural terrain + road network generator (pure Python/numpy) |
| `Tools/textures/...` | Procedural PBR texture library generator |

## 3. Docs map
`Docs/ARCHITECTURE.md` (C++ contract) · `Docs/BLENDER_CONTRACT.md` (asset rules) · `Docs/CAR_ROSTER.md` · `Docs/WORLD_SPEC.md` · `Docs/Tech/*` (research and technical notes) · `RESEARCH_NOTES.md` · `FEATURE_MATRIX.md` · `SONNET_5.5_FINAL_REPORT.md`.

## 4. Architecture (C++ module `Sonnet55Forza` + editor module `Sonnet55ForzaEditor`)

Binding contract: `Docs/ARCHITECTURE.md` (section 10 = what was actually built). All game classes are prefixed `Roam`; content root `/Game/Forza/`.

| Area | Key classes | Notes |
|---|---|---|
| Core | `ARoamGameMode`, `ARoamPlayerController`, `URoamGameInstance`, `URoamSettings`, `RoamTypes.h` | spawn on the loop road (saved transform > POI > road > PlayerStart); Enhanced Input created at runtime in C++ (no input assets) |
| Data | `URoamCarDefinition` / `URoamCarCatalog`, `URoamRoadNetwork`, `URoamWorldDefinition`, `URoamTrafficCatalog` | one data asset per car (mass, COM, torque curve, gearbox, drivetrain, tyres per surface, suspension, aero, steering, brakes, assists, sound, paint); PI formula in `ComputePerformance()` |
| Vehicle | `ARoamVehicle`, `URoamVehicleMovement` (+ `RoamTireModel`, `RoamDrivetrain`, `RoamVehicleMovementPhysics.cpp`), `URoamCameraRig`, `URoamEngineSynth`, `URoamVehicleVisuals`, `URoamVehicleFX` | **project-owned raycast/spring vehicle on a Chaos rigid body, stepped from `AsyncPhysicsTickComponent` at a fixed 120 Hz** (Chaos Vehicles is experimental and asset-heavy: skipped, see RESEARCH_NOTES.md) |
| World | `URoamTimeWeatherSubsystem` (logic), `ARoamSkyManager` + `RoamWeatherFX` (visuals), `URoamRegionSubsystem` | sun/moon/atmosphere/clouds/fog/sky light/exposure, rain streak pool, lightning, wetness MPC |
| Traffic | `URoamTrafficSubsystem`, `RoamLaneGraph`, `RoamTrafficSim`, `ARoamTrafficVehicle` | lane graph from the road network, IDM following, junction tokens, rings (physics < 120 m after a hit / kinematic 120-450 m / data-only 450-900 m), pooling |
| Activities | `URoamActivitySubsystem`, `RoamActivityLogic`, `ARoamActivityMarkerActor` | speed traps, speed zones, drift zones, danger-sign jumps, checkpoint races, time trial on the loop, collectibles/photo spots; runtime placement on the real road network |
| UI (Slate) | `URoamUISubsystem`, `SRoamSpeedCluster`, `SRoamMinimap`, `SRoamNotifications`, `SRoamConsole`, `SRoamGarageMenu`, `SRoamDebugMenu`, `SRoamPauseMenu` | no UMG/Blueprint assets; generic screen registry |
| Console / Save | `URoamConsoleSubsystem` (`ROAM_REGISTER_CONSOLE_COMMAND`), `URoamSaveSubsystem` | integrity envelope (magic + CRC) around `USaveGame`, graceful fallback |
| Editor module | `RoamWorldBuilder`, `RoamEditorLibrary` | `ALandscape::Import` wrapper (C++ only), layer infos, visibility-layer holes, World Partition runtime grid, data-asset builders; driven from Python |

## 5. Controls (keyboard / gamepad)
Throttle `W`/`Up`/RT · brake/reverse `S`/`Down`/LT · steer `A`,`D`/arrows/left stick · handbrake `Space`/B · shift up/down `E`,`Q`/bumpers (manual) · cycle camera (chase, hood, cockpit, bumper) `C`/right-stick click · free look: right mouse button / right stick · reset to road `R`/Y · **console `~` (tilde/backtick)** · **garage / car select `F1` or `Tab`** · **debug/benchmark menu `F2`** · map `M` (stub) · photo mode `P` (stub) · pause `Esc`.
Console commands (type `help`): `cars`, `car <n|name>`, `respawn`, `tp <region|poi>`, `time <hour>`, `weather <clear|cloudy|rain|fog|storm>`, `traffic <0..1>`, `speed`, `fps`, `assist <name> on|off`, `paint <colour>`, `reset`, `repair`, `save` / `load` / `resetprofile`, `act.list`, `act.tp <n>`, `autodrive` (if present in this build, see FEATURE_MATRIX.md), `phys`, `testcar`, `ui.*`.

## 6. Map layout (4.03 x 4.03 km; UE metres: X north, Y east, origin = map centre)
Regions: **Greenvale** (farmland/forest valley, Silverrun river, village Millbrook) SW · **Highcrest** (alpine massif, hairpin pass, 298 m tunnel, summit viewpoint, Frostholm lodge) NW · **Sunbaked Plateau** (mesas, canyons, 5.5 km highway, gas station, wind farm) NE · **Saltcliff Coast** (cliffs, bay with the 422 m cable-stayed Great Bay Bridge, Tidewick harbour, lighthouse, beach) E/SE · **Crossroads hub** (diner + gas station) in the centre.
Road network (final generator build): **45.6 km**, scenic LOOP **23.1 km, closed**, longest uninterrupted stretch HWY_EAST 5.54 km, 22 bridges, 1 tunnel (298 m), 9 hairpins on the pass; classes highway / regional / mountain / dirt / village; grade limits 6/9/12/14/10 %, minimum radius 262/75/20/27/23 m. Landscape 4065 x 4065 vertices at 1 m (16 x 16 components, Nanite, 8 weight layers); World Partition 256 m cells / 1000 m loading range; landscape + road chunks always loaded, props streamed (foliage actors).

## 7. Blender workflow (verified MCP `blender-forza-unreal`, localhost:9889)
`UnrealSonnet5.5Forza.blend` (master) -> idempotent scripts in `Tools/blender/**` executed inside Blender through the MCP -> `Tools/blender/lib/fbx_export.py` (one FBX per part, centred pivots, axis -Y/Z, unit scale) -> `Exports/**` (+ JSON sidecars) -> UE Python importers (`Tools/ue/cars_import.py`, `props_import.py`, `import_roads.py`; legacy `FbxImportUI` options, `auto_generate_collision` for UCX hulls) -> materials bound by slot name -> data assets. The master `.blend` is never loaded at runtime. Contract: `Docs/BLENDER_CONTRACT.md`; kit docs in `Docs/Kits/`.
Blender assets created: 10 player cars (~110k tris each), 6 traffic vehicles, 21 tree meshes (+21 far cards), 42 ground-cover meshes, 61 roadside-kit meshes, 23 settlement/landmark meshes, 217 road/bridge/tunnel/junction chunks (498k tris): roughly 400 exported meshes. One incident: the Blender instance hung (unresponsive main thread) and was restarted from the master file; the settlement and ground-cover kits were rebuilt from their scripts and the master was re-saved.

## 8. Build / run
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/build_editor.ps1                          # editor target
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/build_editor.ps1 -Target Sonnet55Forza    # game target
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -ExecCmds "Automation RunTests Roam; Quit" -LogName tests -ExtraArgs "-nullrhi"
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -Game -Map /Game/Forza/Maps/L_Main -LogName game   # windowed run (default map is L_Main)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 <script.py>                # python job in the persistent editor server
"W:\Blender\5.2\python\bin\python.exe" -I Tools/world/build_world.py       # regenerate terrain/roads (2 min); then Tools/ue/world_rebuild.ps1 (~13 min)
"W:\Blender\5.2\python\bin\python.exe" -I Tools/ue/placement_gen.py        # regenerate prop placements; Tools/ue/props_apply.py applies them
```
Docs: `Docs/Tech/BUILD_AND_RUN.md`, `WORLD_BUILD.md`, `ROADS_PIPELINE.md`, `CARS_IMPORT.md`, `MATERIALS.md`, `PROPS_PIPELINE.md`, `UI_NOTES.md`, `DRIVE_TESTS.md`.

## 9. Drive-test numbers (automated; dry asphalt, stock assists, 120 Hz async physics; `Docs/Tech/DRIVE_TESTS.md`)
| Car | 0-100 km/h (s) | Top speed (km/h) | 100-0 km/h (m, ABS) |
|---|---|---|---|
| Pulse | 7.68 | 225.5 | 48.0 |
| Cadence | 10.80 | 205.3 | 49.9 |
| Thunderline | 5.72 | 258.3 | 44.2 |
| Vesper | 5.12 | 305.2 | 38.1 |
| Meridian GT | 4.79 | 332.7 | 36.7 |
| Aether | 2.56 | 336.8 | 32.2 |
| Ridge | 5.16 | 242.0 | 53.1 |
| Ranger | 8.00 | 205.9 | 52.4 |
| Mule | 8.33 | 205.6 | 49.1 |
| Brisa | 12.35 | 153.4 | 53.6 |

Skidpad (r = 50 m): Pulse 0.83 g, Thunderline 0.99 g, Aether 1.32 g, Ranger 0.76 g. 250 km/h stability: a 0.4 s steering perturbation decays within 6 s (Vesper, Meridian GT, Aether). Jump from a 5 degree ramp at 122 km/h lands upright (Pulse, Aether, Ranger). Wet braking Pulse 48.1 -> 69.6 m. Frame rate in L_Main (RTX 5070, 1920x1080, Nanite landscape, 217 road actors, one car): 124-130 fps average. These numbers were measured on the test world / with placeholder bodies; see the QA addendum in `Docs/Tech/DRIVE_TESTS.md` for real-mesh results if present.

## 10. Known limitations (honest list; see FEATURE_MATRIX.md for per-feature status)
* Photo mode, full map screen and GPS route line are NOT implemented (keys/hooks only). Seasons, wildlife/ambient life, damage and rewind are not implemented.
* Upgrades are saved and shown as a stat preview but the physics hook is a stub; tuning sliders are not implemented.
* The tunnel portal head-wall does not fully cover the landscape hole (sky visible through the gap); one ~1 m junction bump.
* Generated-art limits: car bodies are loft + boolean models (clean but generic), interiors are simple, building windows are nearly opaque, Highcrest hairpin fills read as earth dams from some angles, distant mountains look dark.
* No packaged build was made (editor + `-game` only). No HLOD (landscape and road chunks are always loaded; props stream via foliage actors).
* Metal car materials look dark without a good reflection capture; the engine shows a Lumen/EyeAdaptation on-screen debug message on some maps (suppress it for recording).
