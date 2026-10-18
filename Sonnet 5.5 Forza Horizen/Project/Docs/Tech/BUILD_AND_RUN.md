# Build and run - exact commands (UE 5.8.2, Windows, project path with spaces)

All commands run from the project root `W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza` in **PowerShell**
(`/Game/...` arguments get mangled by Git Bash). Logs always go to `Tools\Logs\<LogName>.log` (the scripts pass `-abslog`).
**One Unreal/UBT process per project folder at a time**: `Tools\build_editor.ps1` and `Tools\ue_cmd.ps1` share a named mutex and
queue behind each other, so parallel agents simply wait.

## 1. Build

```powershell
# editor target (also builds the runtime module Sonnet55Forza and the editor-only module Sonnet55ForzaEditor)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/build_editor.ps1 -LogName build_editor
# game target (runtime module only; proves the editor module is not part of the game)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/build_editor.ps1 -Target Sonnet55Forza -LogName build_game
```

Exit code 0 = `Result: Succeeded`. Errors are summarised by the script; MSVC output is Russian-localised, parse `error C####`.
The own-code warning audit: `Select-String Tools\Logs\<log>.log -Pattern "UnrealSonnet55Forza\\Source\\.*(warning|error)"` must print nothing.
Incremental builds of this module take 20-60 s; a full rebuild of the module ~1.5 min.

Build-system facts learned the hard way (5.8.2):
* **Shadowing is an error** (`C4458`): a parameter named like a member (`bEnabled` vs member `bEnabled`) fails the build.
* `PI` is a macro: never name a variable/field `PI`. `PREPROCESSOR_JOIN` is deprecated, use `UE_JOIN`.
* UHT rejects static arrays and bool arrays in Blueprint-visible structs (`FRoamVehicleTelemetry` keeps its per-wheel arrays as plain members).
* `TRingBuffer` uses `Add/PopFront`, not `PushBack`.
* A module with a Public dependency on `Sonnet55Forza` must also depend on `PhysicsCore` if it reflects `UPhysicalMaterial` (editor module does).
* `SynthComponent.h` drags in an engine header with a C4996 warning; `RoamEngineSynth.h` wraps the include in `PRAGMA_DISABLE_DEPRECATION_WARNINGS`.

## 2. Automation tests (headless, no rendering)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -ExecCmds "Automation RunTests Roam; Quit" -LogName tests -NullRHI -TimeoutSec 600
Select-String Tools\Logs\tests.log -Pattern "Test Completed|Error: Expected"
```

22 tests in `Source/Sonnet55Forza/Tests`, all `Roam.*`: Console (tokenizer, commands), TimeWeather (HourWrap, Sun, WeatherBlend, Wetness, GripTable,
AutoWeather, Lights), RoadNetwork (SyntheticNetwork, Nearest, GridMatchesBruteForce, Lanes, Route), CarDefinition (ClassBands, TorqueCurve,
PerformanceIndex, Validate, Catalog), Save (RoundTrip, Sanitize), Types (Helpers). Exit code 0 = all passed (255 on failure).
Notes: subsystem objects must be created inside a `UGameInstance` (ClassWithin) - see `RoamConsoleTests.cpp`; `UGameplayStatics::LoadGameFromMemory`
**asserts on garbage input** in 5.8.2, which is why saves are wrapped in a CRC envelope (`URoamSaveSubsystem::PackEnvelope`).

## 3. Python smoke tests and the test map

```powershell
# editor module loaded + URoamEditorLibrary callable from Python (expects ROAM_EDITOR_LIB_SMOKE result=PASS)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/editor_lib_smoke.py -LogName editor_lib_smoke
# builds /Game/Forza/Maps/L_Test and the 8 PM_Roam_* physical materials (re-runnable; overwrites)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/make_test_map.py -LogName make_test_map
```

Python gotchas: `unreal.Rotator(roll, pitch, yaw)` - **roll first** (a sun created with `Rotator(-45, 35, 0)` pointed UP and rendered the whole map black);
script paths must use forward slashes; only `EditAnywhere/BlueprintReadWrite` properties are visible; `URoamSettings` (a developer-settings class) is
not exposed to Python, use `unreal.RoamEditorLibrary.describe_roam_settings()`.

## 4. Run the game (windowed 1280x720) + screenshot + physics statistics

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/game_smoke.ps1            # all checks + screenshot path, exit 0 = pass
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/game_smoke.ps1 -Map /Game/Forza/Maps/Main -DriveSeconds 15 -LogName game_main
```

Underlying command (what the script runs):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -Game -Map /Game/Forza/Maps/L_Test -ResX 1280 -ResY 720 `
  -ExecCmds "roam delay 3 drive 0.5 0, roam delay 8 phys, roam delay 8.5 ue HighResShot 1280x720, roam delay 12 ue Quit" -LogName game_smoke
```

* `-ExecCmds` separates commands with **commas** (not semicolons) and runs ALL of them in the first frame - there is no "wait". The Roam console command
  `delay <seconds> <command...>` schedules a command on the real-time ticker; this is how a screenshot is taken after the map has rendered.
  `ue <cmd>` runs an engine console command through the player controller (the same path as the typed console - needed for viewport commands like
  `HighResShot`).
* Screenshots land in `Saved\Screenshots\WindowsEditor\HighresScreenshotNNNNN.png` (view with the Read tool). The first launch after a code change costs 1-2.5 minutes of
  editor start-up before the map loads; screenshots need a real RHI (never `-NullRHI`).
* Useful test commands inside a running game (type them in the Roam console or pass `roam <cmd>` / `-ExecCmds`):
  `help`, `drive <throttle> [steer] [brake]` / `drive off`, `phys`, `car <n|name>`, `cars`, `camera [mode]`, `time 18`, `weather rain 10`, `tp <poi>`, `save`, `load`,
  `ue stat fps`, `ue ViewMode Unlit`.
* The engine console moved to **F10**; the backtick/tilde key belongs to the Roam console (`Config/DefaultInput.ini`).

## 5. Physics stepping - decision and evidence (engine source 5.8.2)

**Decision: asynchronous fixed-step physics, 120 Hz** (`Config/DefaultEngine.ini [/Script/Engine.PhysicsSettings]`: `bTickPhysicsAsync=True`,
`AsyncFixedTimeStepSize=0.008333`), with sub-stepping configured as the fallback (`bSubstepping=True`, `MaxSubstepDeltaTime=0.008333`, `MaxSubsteps=8`).
The vehicle model hooks `UActorComponent::AsyncPhysicsTickComponent` (`URoamVehicleMovement`), not `AddCustomPhysics`.

Verified in the 5.8.2 source:
1. `FBodyInstance::AddCustomPhysics` -> `FPhysScene_Chaos::AddCustomPhysics_AssumesLocked` just executes the delegate **once per frame** with the frame delta
   (`PhysScene_Chaos.cpp:1665`). It is no longer a per-substep hook (it was with PhysX). Not usable for tyre/suspension integration.
2. `AsyncPhysicsTickComponent` is run by `FAsyncPhysicsTickCallback` (`Presimulate | RunOnFrozenGameThread`): the solver dispatches a game-thread task
   (`FPhysicsSolverFrozenGTPreSimCallbacks`, `PhysicsSolverBase.h:131`) before **every** solver step, with the physics thread parked, so the callback may read and write
   physics-thread data. Per-body physics-thread access: `FBodyInstance::GetBodyInstanceAsyncPhysicsTickHandle()` (`BodyInstance.h:336`).
3. `bTickPhysicsAsync` makes the solver use the fixed `AsyncFixedTimeStepSize` (`FPhysicsSolverBase::AdvanceAndDispatch_External`: the fixed-dt branch wins over the
   sub-stepping branch). So while async is on, `bSubstepping` is inert; flip `bTickPhysicsAsync` to False and the same callback fires per substep (dt <= 1/120) instead.
4. In 5.8.2 `UPhysicsSettings` states both features are still "experimental"; the cost is a game-thread/physics-thread sync per step - profile `stat unit` at 60 vs 120 Hz
   once the real vehicle model exists. If 120 Hz is too expensive, raise `AsyncFixedTimeStepSize` to 0.016667 (still fixed-step, 60 Hz).

**Empirical proof in this skeleton** (`roam phys`, placeholder car, 40 s run): `steps=4820 avgHz=120.0 avgDt=0.00833 minDt=0.00833 maxDt=0.00833` - exactly 120 Hz, constant dt,
independent of the ~50-60 FPS render rate. `game_smoke.ps1` asserts avgHz > 100 on every run.

Rules for the vehicle owner: apply forces EVERY step (the evolution zeroes the accumulators), re-read the body state from the physics-thread handle inside the callback (never the
component transform), set `bReturnPhysicalMaterial=true` on ground rays, use the `Roam_Wheel` trace channel (`RoamCollision::TraceWheel`; it defaults to Ignore, only
`RoamWorldStatic` blocks it), wake sleeping bodies from the game thread.

## 6. Config summary (what to change where)

| Need | File | Key |
|---|---|---|
| Default map, game mode, game instance | `Config/DefaultEngine.ini` `[/Script/EngineSettings.GameMapsSettings]` | `GameDefaultMap`, `GlobalDefaultGameMode`, `GameInstanceClass` |
| 60 FPS tuning (Lumen, VSM, streaming, Nanite, WP) | `Config/DefaultEngine.ini` `[SystemSettings]` | every line is commented with reason and default |
| Collision channels / profiles | `Config/DefaultEngine.ini` `[/Script/Engine.CollisionProfile]` | mirrored in `Core/RoamCollision.h` |
| Physics stepping, gravity, surface names | `Config/DefaultEngine.ini` `[/Script/Engine.PhysicsSettings]` | |
| Frame smoothing off | `Config/DefaultEngine.ini` `[/Script/Engine.Engine]` | `bSmoothFrameRate=False` |
| Project name, Roamline data asset paths, spawn, time/weather defaults | `Config/DefaultGame.ini` | `[/Script/EngineSettings.GeneralProjectSettings]`, `[/Script/Sonnet55Forza.RoamSettings]` |
| Enhanced Input classes, console key | `Config/DefaultInput.ini` | `DefaultPlayerInputClass`, `ConsoleKeys` |
| Plugins / modules | `Sonnet55Forza.uproject` | Chaos Vehicles plugin deliberately NOT enabled (project-owned vehicle model) |

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Game starts but the 3D view is black (HUD text visible) | check the sun: `unreal.Rotator(roll, pitch, yaw)` argument order in map scripts; `ue ViewMode Unlit` shows whether geometry renders |
| Car falls through the world / spawns high | ground must use profile `RoamWorldStatic` (or answer Block to `Roam_Wheel`); `ROAM_GROUND_DROP hit=<actor>` in the log names what the spawn trace hit |
| `ExecCmds` command ignored | commands are comma separated; commands run in frame 1 - use `roam delay N ...` |
| `Automation RunTests` runs nothing | tests need `ProductFilter` + a context flag; `-NullRHI` is fine for `Roam.*` |
| `Object ... was created in invalid Outer` (ensure) in a test | game-instance subsystems need a `UGameInstance` outer |
| Editor start-up takes minutes | first run after a code change compiles/loads many plugins; shaders are cached in `DerivedDataCache` afterwards |
