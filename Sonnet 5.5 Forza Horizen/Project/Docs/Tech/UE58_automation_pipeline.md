# UE 5.8 automation and asset pipeline (Windows) - research notes

Date of research: 2026-10-16. Nothing in this document was executed against the editor: this task forbade
launching Unreal, building, or touching Blender. Everything marked [SRC] was verified by reading the LOCAL
engine / Blender install (engine ships Runtime/Editor/Developer/Plugins source, so `Grep` over it is ground
truth). [DOC] = official documentation page. [LOG] = seen in a local log. [NOT RUN] = reasoned from source,
must be confirmed by the first real run (a calibration step is given for each such risk).

Paths used below (always written with forward slashes when they go through Unreal's command line, see 7.2):

```
ENGINE   = W:/Unreal Engine 5/UE_5.8
EDITORC  = W:/Unreal Engine 5/UE_5.8/Engine/Binaries/Win64/UnrealEditor-Cmd.exe
EDITORW  = W:/Unreal Engine 5/UE_5.8/Engine/Binaries/Win64/UnrealEditor.exe
BUILDBAT = W:/Unreal Engine 5/UE_5.8/Engine/Build/BatchFiles/Build.bat
PROJDIR  = W:/YouTube/Claude Sonnet 5.5/Forza Horizen/Sonnet55Forza/UnrealSonnet55Forza
UPROJECT = PROJDIR/Sonnet55Forza.uproject
BLENDER  = W:/Blender/blender.exe  (5.2; FBX add-on io_scene_fbx 5.15.0, Python exporter)
```

---------------------------------------------------------------------------------------------------

## 0. Verified environment facts

* Engine 5.8.2, CL 56702186, launcher ("promoted") build [SRC Build.version]. Python embedded = 3.11.8 [LOG, DOC].
* `UnrealEditor-Cmd.exe` is a CONSOLE-subsystem PE, `UnrealEditor.exe` is GUI-subsystem (read PE header). Consequence:
  in PowerShell `& UnrealEditor-Cmd.exe ...` blocks and sets `$LASTEXITCODE`; `& UnrealEditor.exe ...` returns
  immediately (use `Start-Process -Wait -PassThru`). Always use `-Cmd` for automation.
* Both exes are the same size (512,952 bytes): they are thin launchers; the engine is in the DLLs.
* uproject today: modules `Sonnet55Forza` (Runtime, Default); plugins ModelingToolsEditorMode (editor only),
  PythonScriptPlugin, EditorScriptingUtilities, Niagara, Metasound, PCG, Water. Plugin names verified against
  `*.uplugin` file names [SRC]: `PythonScriptPlugin` (Experimental/, IsBetaVersion), `EditorScriptingUtilities`
  (Editor/, beta, EnabledByDefault=false), `Water` (Experimental), `PCG`, `Niagara`, `Metasound`, `EnhancedInput`
  (default on), `ProceduralMeshComponent` (default on), `GeometryScripting` (NOT default-on), `ChaosVehiclesPlugin`
  (EnabledByDefault=false, IsExperimentalVersion=true), `ChaosModularVehicle` (experimental), `FunctionalTestingEditor`
  (EnabledByDefault=false), `StateTree`/`MassGameplay` (off by default).
* Targets: `DefaultBuildSettings = BuildSettingsVersion.V7`, `IncludeOrderVersion = Unreal5_8` (both are the
  newest values: TargetRules.cs `Latest = V7`, `Latest = Unreal5_8`) [SRC]. See 5.3 for what that means.
* DefaultEngine.ini already has `[/Script/PythonScriptPlugin.PythonScriptPluginSettings] bDeveloperMode=True`
  (so Python stub generation is already armed, see 2). Rendering: DX12 SM6, Lumen, VSM, RayTracing=True, Substrate=True
  (`r.Substrate=True` matters for material creation, see 3.5). GameDefaultMap = /Engine/Maps/Templates/OpenWorld.
* Toolchain [LOG Tools/Logs/build_baseline.log]: VS at `W:/Visual Studio`, MSVC 14.51.36231 (engine "preferred" is
  14.50, so a harmless "not a preferred version" warning), Windows SDK 10.0.26100.0, bundled .NET 10.0 (Build.bat says
  "Using bundled DotNet SDK", no system dotnet needed), ISPC 1.24. 5.8 recommended: VS 2026 (min VS2022 17.14),
  MSVC 14.50 (min 14.38), SDK 26100 (min 22621) [DOC release notes].
* Baseline: `Sonnet55ForzaEditor Win64 Development` empty module = 63 s, "Result: Succeeded". Existing script
  `Tools/build_editor.ps1` passes `-NoHotReload`, which is NOT a UBT option in 5.8 (the real one is
  `-NoHotReloadFromIDE`, BuildConfiguration.cs); UBT silently ignores unknown switches, so it is harmless but useless.
* OS locale is Russian. MSVC diagnostics AND some UE LOCTEXT log lines are localized (e.g. the Python startup-script
  lines in the previous editor log). Do not parse localized prose. Parse stable tokens: log category + verbosity
  (`LogPython: Error:`), UBT's English `Result: Succeeded` / `Result: Failed (...)`, MSVC `error C####`. Add
  `-culture=en` (also `-language=`/`-locale=`) to force English UE strings [SRC TextLocalizationManager.cpp].
* Previous editor session in the log: ~80 s from start to exit with no work; first-run shader/DDC work adds more.
  Budget: Python commandlet 5 min, editor+Python 15-30 min, full module rebuild 10-30 min.

---------------------------------------------------------------------------------------------------

## 1. Command-line automation

### 1.1 Which binary

| Need | Use | Why |
|---|---|---|
| Python that needs a loaded world / level editor / asset registry fully ready | `UnrealEditor-Cmd.exe <uproject> -ExecutePythonScript=...` | runs inside the real editor loop; waits for GWorld + GEditor + finished asset scan [SRC EditorPythonExecuter.cpp] |
| Pure asset jobs (import, create DataTable/Material, set props, save) | `-run=PythonScript -Script=...` commandlet | faster, no editor UI, but NO level loaded, no GWorld [DOC, SRC] |
| C++ automation tests | `UnrealEditor-Cmd.exe <uproject> -ExecCmds="Automation RunTests X; Quit"` (editor context) or `... -game ...` (client context) | see 1.3 D |
| Run the game uncooked for scripted drive tests / screenshots | `UnrealEditor-Cmd.exe <uproject> /Game/Maps/X -game ...` | editor binary + `-game` plays uncooked content; the standalone `Sonnet55Forza.exe` target needs cooked data |
| Package | `RunUAT.bat BuildCookRun` | final step only |

### 1.2 Flags (verified in engine source unless noted)

| Flag | Effect | Source |
|---|---|---|
| `-unattended` | `FApp::IsUnattended()` true (also forced true while automation runs); no modal dialogs; Windows SetErrorMode suppresses crash/GP-fault boxes | App.cpp:274, LaunchWindows.cpp:211 |
| `-nullrhi` | NullRHI, no rendering (also disables tests flagged `NonNullRHI`). Cannot take screenshots. Physics/gameplay still run | AutomationTest.cpp:841, WindowsPlatformCrashContext.cpp |
| `-nosplash` | no splash window | WindowsPlatformSplash.cpp:706 |
| `-nosound` | no audio device (`-enablesound` overrides). Matters because 5.8 switched the default Windows audio backend from XAudio2 to WASAPI [DOC] | App.h:436 |
| `-stdout` | initializes the stdout log device early. `-AllowStdOutLogVerbosity` lets `Log` level through; `-FullStdOutLogOutput` lets everything through; `-JsonStdOut` = JSON lines | LaunchEngineLoop.cpp:1892, OutputDeviceStdOut.cpp |
| `-abslog=<abs path>.log` | log file at an absolute path. File name MUST end in `.log` or `.txt` or it is silently ignored. `-log=<name>.log` is relative to `Saved/Logs`. Bare `-log` opens a console window (do not use headless) | GenericPlatformOutputDevices.cpp:80-100 |
| `-culture=en` | English strings | TextLocalizationManager.cpp:254 |
| `-ExecCmds="a,b,c"` | deferred console commands; SEPARATOR IS COMMA; single quotes inside become double quotes (`-ExecCmds="Foo 'a,b'"`); ignored in Shipping | ParseExecCommands.cpp |
| `-EXEC=file` | executes a text file of console commands | UnrealEngine.cpp:2546 |
| `-game` | game (non-editor) mode inside the editor exe; GIsEditor=false so tests with `ClientContext` run, `EditorContext`-only tests do not | AutomationTest.cpp:~805 |
| `-windowed -ResX=1280 -ResY=720` | window size; `-Res=1280x720` shorthand; ResX alone infers Y at 16:9 | GameEngine.cpp:310-340 |
| `-ForceRes` | do not clamp the requested size to the desktop | GameEngine.cpp:414 |
| `-ExecutePythonScript="<script.py> [args]"` | editor-only (errors out in a commandlet). Value unquoted = up to first space; quoted = full string, `.py` parsed out so paths with spaces work | EditorPythonExecuter.cpp:144-212 |
| `-ScriptErrorsAreFatal` | an uncaught Python exception logs `Fatal` (process dies non-zero) instead of `Error` | EditorPythonExecuter.cpp:195 |
| `-run=PythonScript -Script="..."` | commandlet; returns -1 on exception, 0 on success. `-Script` may be a file path or inline Python (`\n` for newlines) | PythonScriptCommandlet.cpp |
| `-ForceEnablePython` / `-DisablePython` / `-EnablePython` | override Python enablement (plugin enabled in uproject is enough: "Python enabled via CVar Engine.Python.IsEnabledByDefault") | PythonScriptPlugin.cpp:106-156 |
| `-ReportExportPath="<dir>"` | automation results as JSON (+html) | [DOC] |
| `-AllowCommandletRendering` | required by WorldPartition builders that render (HLOD, minimap) | WorldPartitionBuilder.cpp:83 |
| `-LiveCoding=false` / `-LiveCoding` | disable/enable Live Coding at startup | LiveCodingModule.cpp:490 |
| `-fixedseed`, `-deterministic` (= `-UseFixedTimeStep -FixedSeed`), `-FPS=60` | deterministic drive tests | [DOC cmdline reference] |
| `-dx12`/`-dx11` | pick RHI (project default is DX12) | standard [NOT RUN] |

Notes: `-UTF8Output` is deprecated (output is UTF-8 by default since 5.6) [SRC LaunchEngineLoop.cpp:1898].
Do NOT use `-ExecCmds="py script.py"` for startup scripts: the command can run before the editor is ready [DOC];
use `-ExecutePythonScript`.

### 1.3 Recipes (PowerShell, copy-paste; Section 1.7 has a hardened wrapper)

A. Python inside the editor (level building, anything touching worlds / World Partition):

```powershell
$ue   = 'W:\Unreal Engine 5\UE_5.8\Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$proj = 'W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Sonnet55Forza.uproject'
$py   = 'W:/YouTube/Claude Sonnet 5.5/Forza Horizen/Sonnet55Forza/UnrealSonnet55Forza/Tools/py/build_world.py'
$log  = 'W:/YouTube/Claude Sonnet 5.5/Forza Horizen/Sonnet55Forza/UnrealSonnet55Forza/Tools/Logs/build_world.log'
& $ue $proj "-ExecutePythonScript=$py" -unattended -nosplash -nullrhi -stdout -FullStdOutLogOutput -culture=en "-abslog=$log" -ScriptErrorsAreFatal
$LASTEXITCODE
```

Behaviour [SRC EditorPythonExecuter.cpp]: a ticker waits until `GWorld && GEngine && GEditor && DeltaTime>0` and the
asset registry finished loading, runs the file with `EPythonCommandFlags::Unattended`, and on the next tick queues
`QUIT_EDITOR` UNLESS `unreal.EditorPythonScripting.set_keep_python_script_alive(True)` was called (class
`UEditorPythonScriptingLibrary`, ScriptName "EditorPythonScripting"). If your script starts async work (timers,
slate tick callbacks, `ScriptedImportAssetAsync`) keep it alive and later call
`unreal.SystemLibrary.quit_editor()`. `sys.argv` holds only the tokens after the script path (the plugin builds it with
`FParse::Token`; there is no script-name entry) [SRC PythonScriptPlugin.cpp:196-215] - print it once to confirm;
simplest is to read parameters from a JSON file at a fixed project path instead of argv. `__file__` is set.
Exit code of this mode is 0 even when the script raised (unless `-ScriptErrorsAreFatal`): detect failure by the log
line `LogEditorPythonExecuter: Error: Python script executed with errors` plus any `LogPython: Error:` line, and by a
result JSON the script writes in `finally:`.

B. Python commandlet (assets only; fastest):

```powershell
& $ue $proj -run=PythonScript "-Script=$py" -unattended -nosplash -nullrhi -stdout -culture=en "-abslog=$log"
```

No level is loaded; first line of a script that needs one:
`unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level('/Game/Maps/X')` [DOC]. Exit code -1 if the
script raised, 0 otherwise [SRC]. `-Script` goes through `FParse::QuotedString` (escape hazards, 7.2).

C. Console commands: `-ExecCmds="stat fps,r.ScreenPercentage 100"` (comma separated). Commands run on the first
engine ticks, so anything needing a loaded map must be queued from inside the game (use an automation latent
command or a C++ subsystem), not via ExecCmds.

D. Automation tests (C++ tests registered via `IMPLEMENT_SIMPLE_AUTOMATION_TEST`, see section 6):

```powershell
& $ue $proj -unattended -nosplash -nullrhi -stdout -culture=en "-abslog=$log" `
  '-ExecCmds=Automation RunTests Sonnet55Forza; Quit' "-ReportExportPath=W:/.../Saved/Automation/Report"
```
* List: `-ExecCmds="Automation List; Quit"`.
* Selection grammar [SRC AutomationCommandline.cpp:131-200]: names split on `+`; plain token = substring match; prefix `^`
  / suffix `$` anchor; `StartsWith:Sonnet55Forza.Vehicle` = prefix; `Group:Name` = group from `[/Script/AutomationController.AutomationControllerSettings]`.
  Other commands (all `;`-separated inside the single Automation command): `RunAll`, `RunFilter Smoke|Engine|Product|Perf|Stress|Negative|Standard|All`,
  `SetMinimumPriority Critical|High|Medium|Low`, `SetTagFilter`, `AllowZeroTestResults`, `Quit`, `SoftQuit`, `IgnoreLogEvents`.
* Timing: the runner waits `DefaultDelayTimer = 5 s` then looks for workers (timeout 30 s per attempt), so tests start
  roughly 5-10 s after init.
* **Exit code**: `Quit` ends with `FPlatformMisc::RequestExitWithStatus(force, GIsCriticalError ? -1 : 0)` and logs
  `**** TEST COMPLETE. EXIT CODE: -1 ****` on failure. The parameter is `uint8`, so the OS-visible exit code is
  **255**, not -1; success is 0 [SRC AutomationCommandline.cpp:495-503, WindowsPlatformMisc.cpp:1474]. "No automation
  tests matched" counts as an error (255) unless `Automation AllowZeroTestResults` was queued. `SoftQuit` = same code
  without force-exit. Never put `Quit` as a separate comma command before the tests are queued.
* Tests only exist if the module that defines them is loaded: game module loads at Default phase so fine; lazily loaded
  modules must be listed in `[/Script/Engine.AutomationTestSettings] EditorTestModules=` [SRC AutomationTest.cpp:~780].
* Context filter [SRC AutomationTest.cpp:795-850]: editor run = `EditorContext`; `-game` = `ClientContext`; `-nullrhi`
  drops tests flagged `NonNullRHI`; `-unattended` drops `RequiresUser`. Give every test a filter flag
  (`ProductFilter`) or `RunFilter` won't see it.

E. Run the game (scripted drive test / screenshots), real RHI:

```powershell
& $ue $proj /Game/Maps/Forza_Main -game -windowed -ResX=1920 -ResY=1080 -ForceRes -nosound -nosplash -unattended `
  -culture=en "-abslog=$log" -deterministic -FPS=60 '-ExecCmds=Automation RunTests Sonnet55Forza.Drive; Quit'
```
(`/Game/...` as an argument gets mangled by Git Bash, run this from PowerShell, see 7.3.) For logic-only drive tests add
`-nullrhi` and drop the window flags.

F. Screenshots: console `HighResShot 1920x1080 filename="W:/.../shot.png"` (`HighResShot 2` = 2x multiplier; the
`filename=` value is read with `FParse::Value`, so quotes/spaces ok; optional trailing args: region x y w h, mask,
dump-buffers, HDR, datetime-name) [SRC UnrealClient.cpp:2433-2506]. Needs a real RHI and at least a couple of rendered
frames; queuing it and `Quit` back to back races (the file is written a frame or more later). From Python/Blueprint use the
latent `unreal.AutomationLibrary.take_high_res_screenshot(res_x, res_y, filename, camera=None, mask_enabled=False,
capture_hdr=False, comparison_tolerance, comparison_notes, delay=0.0, force_game_view=True)` which returns a
`UAutomationEditorTask`; poll `task.is_task_done()` before quitting [SRC AutomationBlueprintFunctionLibrary.h:143]. Default
output dir `Saved/Screenshots/WindowsEditor` [NOT RUN]. `-nullrhi` cannot screenshot.

G. World Partition builders (HLOD / minimap / navmesh), late polish step:
`-run=WorldPartitionBuilderCommandlet /Game/Maps/Forza_Main -Builder=WorldPartitionHLODsBuilder -AllowCommandletRendering`
(also `WorldPartitionMiniMapBuilder`, `WorldPartitionNavigationDataBuilder`) [SRC]. Needs a real RHI (no `-nullrhi`).

### 1.4 Exit-code cheat sheet

| Process | Success | Failure |
|---|---|---|
| UBT / Build.bat | 0 (`Result: Succeeded`) | enum CompilationResult: 1 Canceled, 2 UpToDate, 3 CrashOrAssert, 4 FailedDueToHeaderChange, 5 FailedDueToEngineChange, 6 OtherCompilationError, 7 LiveCodingLimitError, 8 RulesError, 9 ActionGraphInvalid, 10 ConflictingInstance [SRC UnrealEngineTypes.cs]. Log line `Result: Failed (OtherCompilationError)` |
| `-run=PythonScript` | 0 | -1 (exception) |
| `-ExecutePythonScript` | 0 | 0 unless `-ScriptErrorsAreFatal` (then crash exit 1 or 3) |
| Automation `Quit` | 0 | 255 |
| Crash caught by SEH | - | 1 (LaunchWindows.cpp:286) ; `RequestExit` with GIsCriticalError = 3 |

### 1.5 Logs

* Default log: `Saved/Logs/Sonnet55Forza.log` (UTF-8 with BOM), previous runs rotated to `...-backup-<date>.log`. Use
  `-abslog` per run so logs are never rotated away. Crash reports: `Saved/Crashes/`.
* Grep list that means failure: `LogPython: Error`, `Python script executed with errors`, `LogAutomationController: Error`,
  `LogAutomationCommandLine: Error`, `Fatal error`, `Assertion failed`, `Ensure condition failed`, `LogWindows: Error:`,
  `Unhandled Exception`, `Shader compile`+`error`, `LogInterchangeImport: Error`.
* Timestamps in the file look like `[2026.10.15-17.12.56:988][  0]LogX:`; the console copy has no timestamps.

### 1.6 Timeouts and cleanup

UE has no global watchdog in automation. Always wrap in an external timeout and kill the TREE (editor spawns
ShaderCompileWorker, CrashReportClient, InterchangeWorker, UnrealTraceServer): `taskkill /PID <pid> /T /F`. Never run two
editors on the same project simultaneously, and never run Build.bat while an editor/game holds
`UnrealEditor-Sonnet55Forza.dll` (link error LNK1104 or UBT "Unable to build while Live Coding is active").

### 1.7 Hardened wrapper (PowerShell 5.1 compatible; save as Tools/Invoke-UE.ps1)

```powershell
param(
  [Parameter(Mandatory=$true)][string[]]$UeArgs,
  [string]$Name = 'run',
  [int]$TimeoutSec = 900,
  [string]$Exe = 'W:\Unreal Engine 5\UE_5.8\Engine\Binaries\Win64\UnrealEditor-Cmd.exe',
  [string]$Project = 'W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Sonnet55Forza.uproject',
  [string]$LogDir = 'W:/YouTube/Claude Sonnet 5.5/Forza Horizen/Sonnet55Forza/UnrealSonnet55Forza/Tools/Logs'
)
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ueLog = "$LogDir/$Name.log"; $so = "$LogDir/$Name.stdout.txt"; $se = "$LogDir/$Name.stderr.txt"
function Q([string]$s) { if ($s -match '\s') { '"' + $s + '"' } else { $s } }   # quote WHOLE token, UE re-quotes after '=' (7.2)
$all = @($Project) + $UeArgs + @('-unattended','-nosplash','-stdout','-FullStdOutLogOutput','-culture=en',"-abslog=$ueLog")
$argLine = ($all | ForEach-Object { Q $_ }) -join ' '
$p = Start-Process -FilePath $Exe -ArgumentList $argLine -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$null = $p.Handle                       # PS 5.1: cache the handle or ExitCode can be $null after WaitForExit
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
  & taskkill.exe /PID $p.Id /T /F | Out-Null
  Write-Host "TIMEOUT after $TimeoutSec s"; exit 124
}
$code = $p.ExitCode
$bad = Select-String -Path $ueLog -SimpleMatch -Pattern 'LogPython: Error','Python script executed with errors','Fatal error','Assertion failed','Ensure condition failed','LogAutomationController: Error' -ErrorAction SilentlyContinue
Write-Host "exit=$code errorLines=$(@($bad).Count) log=$ueLog"
if ($code -ne 0 -or $bad) { $bad | Select-Object -First 20 | ForEach-Object { Write-Host $_.Line }; exit 1 }
exit 0
```
Usage: `.\Tools\Invoke-UE.ps1 -Name world -UeArgs '-ExecutePythonScript=W:/.../Tools/py/build_world.py','-nullrhi'`.

---------------------------------------------------------------------------------------------------

## 2. Python API reference ("stubs")

* Generated by the editor itself, not by a command: `Intermediate/PythonStub/unreal.py` (type-hinted, PEP 484).
  Written by `FPyWrapperTypeRegistry::GenerateStubCodeForWrappedTypes` 2 s after the last module load.
* Conditions [SRC PythonScriptPlugin.cpp:1600-1608]: `bDeveloperMode` true (project: already set in DefaultEngine.ini
  `[/Script/PythonScriptPlugin.PythonScriptPluginSettings]`; per-user alternative `[/Script/PythonScriptPlugin.PythonScriptPluginUserSettings] bDeveloperMode=True`
  in EditorPerProjectUserSettings) AND `GIsEditor` AND NOT a commandlet. So it is produced by the first
  `-ExecutePythonScript` / normal editor start, NOT by `-run=PythonScript`. `TypeHintingMode` (user settings) =
  `AutoCompletion` default or `TypeChecker`. Currently absent (no editor run since the project moved): the first Python job
  will create it; after it exists, `Grep` it instead of guessing API names.
* Dev mode also enables extra Python warnings (deprecations) - good, keep it on.
* Python naming rules for property/function names: `bBuildNanite` -> `build_nanite`, `bGenerateLightmapUVs` ->
  `generate_lightmap_u_vs` (UE splits "UVs" oddly), `bOneConvexHullPerUCX` -> `one_convex_hull_per_ucx`; enums
  `FBXIT_STATIC_MESH` -> `unreal.FBXImportType.FBXIT_STATIC_MESH`. Only properties with Edit*/Blueprint* flags are visible to
  Python (e.g. `MaterialInstanceConstantFactoryNew.InitialParent` is a bare `UPROPERTY()` so it is NOT settable from
  Python; use `MaterialEditingLibrary.set_material_instance_parent`). Same rule for our own C++ `UDataAsset` fields: mark
  them `UPROPERTY(EditAnywhere, BlueprintReadWrite)`.
* Python only exists in the editor: not in PIE-less runtime, not in `-game` standalone, not cooked [DOC].
* pip: `bRunPipInstallOnStartup=true` but log shows "No pip-enabled plugins with python dependencies found, skipping" [LOG];
  no network activity. Interpreter is isolated (`bIsolateInterpreterEnvironment=true`): PYTHONPATH ignored, use
  `UE_PYTHONPATH` env var or `Content/Python` (+ `init_unreal.py`) or settings `AdditionalPaths`.

---------------------------------------------------------------------------------------------------

## 3. Python editor scripting recipes (5.8 API, names verified in headers [SRC])

### 3.1 Subsystems to use (EditorLevelLibrary is deprecated since 5.0)

`unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)` (new_level, new_level_from_template, load_level, save_current_level,
save_all_dirty_levels, set_current_level_by_name, editor_play_simulate, ...), `unreal.EditorActorSubsystem`
(spawn_actor_from_class, spawn_actor_from_object, destroy_actor, get_all_level_actors, set_actor_transform ...),
`unreal.EditorAssetSubsystem` or the still-valid static `unreal.EditorAssetLibrary` (load_asset, does_asset_exist,
make_directory, delete_asset, duplicate_asset, rename_asset, save_loaded_asset, save_asset, save_directory, list_assets),
`unreal.StaticMeshEditorSubsystem` (module StaticMeshEditor: set_nanite_settings, add_simple_collisions, set_convex_decomposition_collisions,
set_generate_lightmap_uvs (ScriptName set_generate_lightmap_uv), set_lods, enable_section_collision, add_uv_channel, generate_box_uv_channel ...),
`unreal.AssetToolsHelpers.get_asset_tools()` (create_asset, import_asset_tasks), `unreal.MaterialEditingLibrary`,
`unreal.EditorLoadingAndSavingUtils`, `unreal.SystemLibrary` (quit_editor), `unreal.Paths` (project_dir(), project_saved_dir(), convert_relative_path_to_full).

### 3.2 Create a World Partition level from the engine template

```python
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
# Template lives in the engine: Engine/Content/Maps/Templates/{OpenWorld,Template_Default,TimeOfDay_Default,VR-Basic}.umap
ok = les.new_level_from_template('/Game/Maps/Forza_Main', '/Engine/Maps/Templates/OpenWorld')   # already World Partition
# or an empty partitioned world:
ok = les.new_level('/Game/Maps/Forza_Main', is_partitioned_world=True)
assert ok
...  # spawn actors (below)
les.save_current_level()          # writes the .umap AND the __ExternalActors__ files (OFPA)
```
`new_level*` closes the current level WITHOUT saving it. In World Partition worlds actors are saved as external files: always
save after spawning (`save_current_level` / `save_all_dirty_levels`). Run in `-ExecutePythonScript` mode (not the commandlet)
because the WP editor subsystems need the full editor [NOT RUN].

### 3.3 Spawn / edit actors

```python
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
a = eas.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0,0,100), unreal.Rotator(0,0,0))
a.set_actor_label('RoadSegment_000'); a.set_folder_path('/Roads')
smc = a.get_component_by_class(unreal.StaticMeshComponent)
smc.set_static_mesh(unreal.EditorAssetLibrary.load_asset('/Game/Meshes/SM_Road'))
smc.set_editor_property('mobility', unreal.ComponentMobility.STATIC)
```
For hundreds/thousands of props use `HierarchicalInstancedStaticMeshComponent.add_instances(...)` or ISM/PCG, not one actor
each (WP external-actor file count and editor time explode). Structs returned from properties are copies: modify then
`set_editor_property` again.

### 3.4 Create data assets / tables

```python
at = unreal.AssetToolsHelpers.get_asset_tools()
# Data asset: needs a CONCRETE C++ subclass (UDataAsset itself is abstract), fields must be EditAnywhere/BlueprintReadWrite
f = unreal.DataAssetFactory(); f.set_editor_property('data_asset_class', unreal.ForzaCarDefinition)
da = at.create_asset('DA_Car_Sedan', '/Game/Data/Cars', unreal.ForzaCarDefinition, f)
da.set_editor_property('max_speed_kph', 240.0)
unreal.EditorAssetLibrary.save_loaded_asset(da)
# DataTable (row struct = C++ USTRUCT : FTableRowBase, or a Blueprint struct)
f = unreal.DataTableFactory(); f.set_editor_property('struct', unreal.ForzaRoadRow.static_struct())
dt = at.create_asset('DT_Roads', '/Game/Data', unreal.DataTable, f)
unreal.DataTableFunctionLibrary.fill_data_table_from_json_file(dt, 'W:/.../Content/Data/roads.json')   # also ..._from_csv_file / _string
unreal.EditorAssetLibrary.save_loaded_asset(dt)
```
`create_asset` returns None if the asset exists; check `EditorAssetLibrary.does_asset_exist` first (or delete).

### 3.5 Materials

Project has Substrate enabled (`r.Substrate=True`); `EMaterialProperty` has `MP_FrontMaterial` in 5.8. Legacy property wiring
(`MP_BASE_COLOR`, `MP_ROUGHNESS` ...) is still accepted and converted, but for reproducibility prefer a handful of hand-authored
parent materials (or parents created once by script with a Substrate Slab node) and then only create MaterialInstanceConstants.
```python
mel = unreal.MaterialEditingLibrary
m = at.create_asset('M_Base', '/Game/Materials', unreal.Material, unreal.MaterialFactoryNew())
c = mel.create_material_expression(m, unreal.MaterialExpressionVectorParameter, -400, 0)
c.set_editor_property('parameter_name', 'BaseColor'); c.set_editor_property('default_value', unreal.LinearColor(0.5,0.5,0.5,1))
mel.connect_material_property(c, '', unreal.MaterialProperty.MP_BASE_COLOR)   # '' = FName None = first output [SRC MaterialEditingLibrary.cpp:81-93]; named outputs: 'R','G','B','A' or the pin name
mel.recompile_material(m)                      # returns list of errors
mi = at.create_asset('MI_RoadAsphalt', '/Game/Materials', unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
mel.set_material_instance_parent(mi, m)        # InitialParent is NOT reachable from Python
mel.set_material_instance_vector_parameter_value(mi, 'BaseColor', unreal.LinearColor(0.1,0.1,0.1,1))
mel.update_material_instance(mi)
```
Other verified calls: `connect_material_expressions`, `set_material_instance_scalar/texture/static_switch_parameter_value`,
`layout_material_expressions`, `delete_all_material_expressions`. With `-nullrhi` shader compilation is skipped (materials
save fine, shaders are built the first time a real-RHI editor/game loads them); do the final shader warm-up run with a real RHI.

### 3.6 Procedural meshes saved as real StaticMesh assets (preferred for roads/props)

GeometryScripting plugin (add `{"Name":"GeometryScripting","Enabled":true}` to the uproject; editor module GeometryScriptingEditor; Python
class names `unreal.GeometryScript_*`): build a `DynamicMesh` (`unreal.GeometryScript_MeshPrimitives.append_box`, `append_sweep_polygon`,
`append_simple_swept_polygon`, `append_revolve_path`, ... in MeshPrimitiveFunctions.h), then create the asset in one call:
`opts = unreal.GeometryScriptCreateNewStaticMeshAssetOptions()` (fields: `enable_recompute_normals`, `enable_recompute_tangents`,
`enable_nanite`, `nanite_settings`, `enable_collision`, `collision_mode`, `use_original_vertex_order`) then
`sm, outcome = unreal.GeometryScript_NewAssetUtils.create_new_static_mesh_asset_from_mesh(dyn_mesh, '/Game/Meshes/SM_Road_000', opts)`
(also `..._from_mesh_lods` for LOD arrays) [SRC GeometryScriptingEditor/CreateNewAssetUtilityFunctions.h:48-200]. To overwrite an existing
asset use `unreal.GeometryScript_AssetUtils.copy_mesh_to_static_mesh(dyn_mesh, static_mesh, unreal.GeometryScriptCopyMeshToAssetOptions(), target_lod)`
(MeshAssetFunctions.h:301). There is no `StaticMeshFactory`, so `AssetTools.create_asset(..., unreal.StaticMesh, ...)` is not an option.
Materials: assign afterwards with `static_mesh.set_material(slot, mi)` or pass material lists in the copy options.
Result: Nanite/Lumen/distance-field capable cooked assets, no runtime generation cost. Runtime-generated geometry
(`ProceduralMeshComponent`, `UDynamicMeshComponent`) has no Nanite and costs CPU/GPU upload: keep it for things that truly
change at runtime. **Landscape has no Python creation API** (`ALandscape::Import(...)` and
`LandscapeEditorUtils::SetHeightmapData` are C++-only, module `LandscapeEditor`); options: an editor-module C++ function
exposed via `UFUNCTION(BlueprintCallable)` on a `UBlueprintFunctionLibrary` (then callable from Python), spline-mesh/mesh-based
terrain generated with GeometryScript, or 5.8's experimental Mesh Terrain [DOC release notes].

### 3.7 FBX import: what actually happens in 5.8 (read from source)

* `AssetTools.import_asset_tasks` routes FBX/OBJ/glTF to **Interchange** whenever Interchange import is enabled AND the task
  has no explicit `factory` (AssetTools.cpp:3564-3570). `Interchange.FeatureFlags.Import.FBX` defaults true
  (InterchangeFbxTranslator.cpp:34). Setting `task.factory = unreal.FbxFactory()` forces the LEGACY importer.
* For Interchange the legacy `unreal.FbxImportUI` you put in `task.options` is CONVERTED in memory into an
  `InterchangeGenericAssetsPipeline` (InterchangeFbxAssetImportDataConverter.cpp:791+). Mapped: import_materials,
  import_textures, static mesh `build_nanite`, `combine_meshes` (-> CombineStaticMeshesBehavior All/DoNotCombine),
  `generate_lightmap_u_vs`, `one_convex_hull_per_ucx`, `auto_generate_collision` (-> Collision Convex18DOP fallback),
  `remove_degenerates`, `transform_vertex_to_absolute` (-> bBakeMeshes), `normal_import_method` (-> bRecomputeNormals /
  import normals), `import_rotation/translation/uniform_scale` (-> ImportOffset*). NOT forwarded in the task path:
  the translator settings (`convert_scene`, `convert_scene_unit`, `force_front_x_axis`) - they come from the translator CDO,
  loaded from `GEditorPerProjectIni` section `[Interchange_Translator_ClassName_InterchangeFbxTranslatorSettings]`
  (InterchangeTranslatorBase.cpp:20-25). Defaults: `bConvertScene=True`, `bForceFrontXAxis=False`, `bConvertSceneUnit=True`
  (InterchangeFbxTranslator.h:44-52). To pin them put them in `Config/DefaultEditorPerProjectUserSettings.ini`:
  ```
  [Interchange_Translator_ClassName_InterchangeFbxTranslatorSettings]
  bConvertScene=True
  bForceFrontXAxis=False
  bConvertSceneUnit=True
  ```
* Legacy defaults that bite if you ever use `FbxFactory`: `bConvertSceneUnit=false` (!), `bAutoGenerateCollision=true`,
  `bGenerateLightmapUVs=true`, `bBuildNanite=false`, `NormalImportMethod=ComputeNormals`, `bTransformVertexToAbsolute=true`,
  `bCombineMeshes` default false, `bReorderMaterialToFbxOrder=true` (FbxStaticMeshImportData.cpp, FbxAssetImportData.cpp,
  FbxMeshImportData.cpp). A default `FbxImportUI` also has `automated_import_should_detect_type=True`, `import_materials=True`,
  `import_textures=True`: always override explicitly.
* Interchange pipeline defaults (UInterchangeGenericMeshPipeline / SharedSettings): `bBuildNanite=true`,
  `bGenerateLightmapUVs=false`, `CombineStaticMeshesBehavior=DoNotCombine`, `bCollision=true` + fallback `Convex18DOP`,
  `bImportCollisionAccordingToMeshName=true` (UCX_/UBX_/UCP_/USP_ prefixes), `bOneConvexHullPerUCX=true`, `bImportSockets=true`
  (SOCKET_ prefix), `bBakeMeshes=true`, `bRecomputeNormals=true`, `bRecomputeTangents=true`, `bUseMikkTSpace=true`,
  `bKeepSectionsSeparate=false`, `bUseSourceNameForAsset=true`.

Recommended import function (legacy options object, Interchange engine; sets everything explicitly):

```python
def import_static_fbx(fbx_path, dest_path, dest_name=None, nanite=True, collision=False, unit_check=None):
    at = unreal.AssetToolsHelpers.get_asset_tools()
    ui = unreal.FbxImportUI()
    ui.set_editor_property('automated_import_should_detect_type', False)
    ui.set_editor_property('mesh_type_to_import', unreal.FBXImportType.FBXIT_STATIC_MESH)
    ui.set_editor_property('import_mesh', True)
    ui.set_editor_property('import_as_skeletal', False)
    ui.set_editor_property('import_animations', False)
    ui.set_editor_property('import_materials', False)        # we bind our own MIs; avoids junk materials
    ui.set_editor_property('import_textures', False)
    d = ui.static_mesh_import_data
    d.set_editor_property('combine_meshes', False)           # keep each Blender object its own StaticMesh
    d.set_editor_property('auto_generate_collision', collision)
    d.set_editor_property('generate_lightmap_u_vs', False)   # Lumen/VSM project, no static lighting (r.AllowStaticLighting=False)
    d.set_editor_property('build_nanite', nanite)
    d.set_editor_property('one_convex_hull_per_ucx', True)
    d.set_editor_property('remove_degenerates', True)
    d.set_editor_property('transform_vertex_to_absolute', True)
    d.set_editor_property('normal_import_method', unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS)  # see note
    d.set_editor_property('import_uniform_scale', 1.0)
    d.set_editor_property('import_rotation', unreal.Rotator(0, 0, 0))
    t = unreal.AssetImportTask()
    t.set_editor_property('filename', fbx_path)
    t.set_editor_property('destination_path', dest_path)               # '/Game/Cars/Sedan'
    if dest_name: t.set_editor_property('destination_name', dest_name)
    t.set_editor_property('automated', True); t.set_editor_property('save', True)
    t.set_editor_property('replace_existing', True); t.set_editor_property('replace_existing_settings', True)
    t.set_editor_property('options', ui)                               # leave bAsync at its default (false): synchronous import
    at.import_asset_tasks([t])
    objs = list(t.get_objects())
    assert objs, 'import produced nothing: ' + fbx_path
    return objs
```
Notes: (1) `AssetImportTask.bAsync` would be exposed under a reserved-word-safe name in Python; we never touch it (default false = synchronous).
(2) With Interchange, `normal_import_method` maps to `bRecomputeNormals=False` only for `FBXNIM_IMPORT_NORMALS*`; keep Blender
export as "Normals Only" (custom normals kept). (3) The call is synchronous (`bAllowAsyncImport` false for tasks); with
`ScriptedImportAssetAsync` you would need to tick, avoid it. (4) ALWAYS verify after import (see 3.9) because option mapping
is the place where silent regressions happen. (5) Fallback if results look wrong: `t.factory = unreal.FbxFactory()` and set
`ui.static_mesh_import_data.convert_scene_unit` explicitly.

### 3.8 Naming, sockets, material slots

* Asset name: single mesh in the file and `bUseSourceNameForAsset` -> the FBX FILE name (`Sedan_Body.fbx` -> `Sedan_Body`);
  with several mesh nodes each asset takes its FBX node (Blender OBJECT) name. Override with `destination_name` /
  pipeline `AssetName`. `.`, spaces and other illegal characters in Blender names are sanitized to `_`
  (`Wheel.001` -> `Wheel_001`). Prefix hygiene: name objects `SM_...` in Blender, materials `M_/MI_` free.
* Collision (static meshes only; cars use code-generated primitives): Blender objects named `UCX_<RenderName>_NN`
  (convex), `UBX_` (box), `UCP_` (capsule), `USP_` (sphere); `<RenderName>` must match the render object name exactly; export
  in the same FBX; closed convex hulls; with several render meshes in one FBX only the first mesh's custom collision is
  imported [DOC FBX static mesh pipeline; SRC InterchangeLODDataParser.cpp:131-193].
* Sockets: Empty objects named `SOCKET_<RenderName>_NN` (e.g. `SOCKET_Sedan_Body_WheelFL`); only ONE render mesh with sockets per
  FBX [DOC]; also needs `object_types` to include EMPTY on export. Sockets are the cleanest way to ship wheel hub / light /
  exhaust positions to code: read with `static_mesh.sockets` / `GetSocketTransform` at runtime.
* Material slot names = Blender material names (not indices); `bReorderMaterialToFbxOrder=true` in the legacy path. Rebind via
  `static_mesh.set_material(i, mi)` or by name: `mats = static_mesh.static_materials` then `mats[i].material_slot_name`.
  Keep Blender material names stable and unique (`Paint`, `Glass`, `Tire`, `Chrome`, `Interior`, `Light_Head`, `Light_Tail`) so
  Python can bind MIs by name.
* Pivot: FBX has no per-mesh pivot concept in this flow; with bake on (default), mesh vertices keep the object transform, so the
  pivot ends up at the FBX origin (DOC: "The pivot is placed at the origin on export"). Always export each part with its Blender
  origin at the desired pivot AND the object location/rotation/scale applied or cleared (recipe in 4.3).

### 3.9 Post-import assertions (make the pipeline self-checking)

```python
def verify_mesh(sm, expect_len_cm=None, tol=0.05, nanite=None, min_tris=1):
    box = sm.get_bounding_box()                   # local space, cm
    ext = box.max - box.min                       # unreal.Vector
    unreal.log('BOUNDS %s %s ext=%s' % (sm.get_name(), box.min, ext))
    if expect_len_cm: assert abs(max(ext.x, ext.y, ext.z) - expect_len_cm) / expect_len_cm < tol, 'scale wrong'
    sms = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    assert sms.get_number_verts(sm, 0) >= min_tris
    if nanite is not None: assert sms.get_nanite_settings(sm).enabled == nanite
    return ext
```

### 3.10 Skeletal vs static for the 10-car garage - decision

Default: STATIC meshes, one FBX for the body (with `SOCKET_` empties for 4 wheel hubs, lights, exhaust) + one FBX for the
wheel (centered at origin, spin axis fixed; left/right by 180 deg yaw) + optional brake disc/caliper; custom arcade-sim vehicle
component with raycast/sphere-cast suspension (deterministic, headless-testable). Reasons: no armature/bind-pose/root-bone
pitfalls, 4 separate wheel meshes are trivially spun/steered from code, no physics asset needed. Glass (translucent) must be a
separate mesh/section without Nanite (Nanite is opaque/masked only). If Chaos Vehicles is chosen instead
(`ChaosVehiclesPlugin`, experimental; modules `ChaosVehicles`, `ChaosVehiclesCore`, `ChaosVehiclesEngine`, `PhysicsCore`, `Chaos`)
the car must be a SKELETAL mesh with wheel bones + physics asset (Armature named root, `add_leaf_bones=False`, `primary_bone_axis='Y'`,
`secondary_bone_axis='X'`, `use_armature_deform_only=True`, `bake_anim=False`, import as skeletal with Interchange
`bCreatePhysicsAsset=true`). 5.8's Modular Vehicle / "vehicle from skeletal mesh" (dynamic scene graph) is new and experimental: skip.

---------------------------------------------------------------------------------------------------

## 4. Blender 5.2 -> Unreal export recipe

### 4.1 Real operator signature (read from W:/Blender/5.2/scripts/addons_core/io_scene_fbx/__init__.py, add-on 5.15.0)

`bpy.ops.export_scene.fbx(filepath, check_existing=True, filter_glob='*.fbx', use_selection=False, use_visible=False,
use_active_collection=False, collection='', global_scale=1.0, apply_unit_scale=True, apply_scale_options='FBX_SCALE_NONE'
[default is the FIRST enum item], use_space_transform=True, bake_space_transform=False, object_types={'EMPTY','CAMERA','LIGHT','ARMATURE','MESH','OTHER'},
use_mesh_modifiers=True, use_mesh_modifiers_render=True, mesh_smooth_type='OFF', colors_type='SRGB', prioritize_active_color=False,
use_subsurf=False, use_mesh_edges=False, use_tspace=False, use_triangles=False, use_custom_props=False, add_leaf_bones=True,
primary_bone_axis='Y', secondary_bone_axis='X', use_armature_deform_only=False, armature_nodetype='NULL', bake_anim=True,
bake_anim_use_all_bones=True, bake_anim_use_nla_strips=True, bake_anim_use_all_actions=True, bake_anim_force_startend_keying=True,
bake_anim_step=1.0, bake_anim_simplify_factor=1.0, path_mode='AUTO', embed_textures=False, batch_mode='OFF', use_batch_own_dir=True,
use_metadata=True, axis_forward='-Z', axis_up='Y')`.
Enums: `apply_scale_options` in {FBX_SCALE_NONE "All Local", FBX_SCALE_UNITS, FBX_SCALE_CUSTOM, FBX_SCALE_ALL "FBX All"};
`mesh_smooth_type` {OFF "Normals Only", FACE, EDGE, SMOOTH_GROUP}; axes {X,Y,Z,-X,-Y,-Z}; `colors_type` {NONE,SRGB,LINEAR};
`path_mode` {AUTO,ABSOLUTE,RELATIVE,MATCH,STRIP,COPY}. Differences from older docs: `collection`, `use_visible`, `colors_type`,
`prioritize_active_color`, `use_triangles`, `bake_anim_use_all_actions` are present; `add_leaf_bones` default is TRUE (set False).
Never hardcode enums blindly: read them with
`[i.identifier for i in bpy.types.ExportFBX.bl_rna.properties['apply_scale_options'].enum_items]` if unsure (the class is
registered as `bpy.types.EXPORT_SCENE_OT_fbx`).
The FBX IMPORT in the menu is labeled "FBX (.fbx) (Legacy)": Blender 5.2 ships a new native importer; the exporter is still this Python one.

### 4.2 What the exporter does with scale and axes (export_fbx_bin.py:3541-3554, 3295-3322)

* Blender unit = 1 m, FBX default unit = cm. With `apply_unit_scale=True` the factor is 100.
* `FBX_SCALE_NONE`: global_matrix gets `Scale(100*global_scale)`, header `UnitScaleFactor=1.0` (file unit = cm). Scaling lives in
  each object's node transform (mesh data is untouched because `bake_space_transform=False`). Independent of Unreal's
  "convert scene unit" setting. **Recommended default.** It relies on the importer baking node transforms into the mesh
  (legacy `bTransformVertexToAbsolute=true`, Interchange `bBakeMeshes=true`, both default).
* `FBX_SCALE_ALL`: node scale stays 1, header `UnitScaleFactor=100`; Unreal must convert units (Interchange translator default
  `bConvertSceneUnit=True` ok; legacy default `bConvertSceneUnit=false` would import 100x too small). Cleaner file, but
  dependent on that setting.
* Axes: `axis_forward`/`axis_up` rotate node transforms by `axis_conversion(from_forward='Y', from_up='Z', to_...)` and write
  matching header axes (RIGHT_HAND_AXES table, fbx_utils.py:105-131: `('Z','Y')` is "Blender system", Front axis = -Y).
  `('Z','Y')` (UI: "Y Forward, Z Up") produces an IDENTITY global rotation = nothing baked. The default `-Z`/`Y` bakes a
  -90 deg X rotation into every node. Both are valid because Unreal converts using the header; pick `Y`/`Z`.

### 4.3 What Unreal does with those axes - and the car orientation rule (derived from source, [NOT RUN])

Interchange FBX (FbxConvert.cpp:84-111, FbxConvert.h:134): target axis system = Z up, front = `-ParityOdd` (= -Y) right-handed
(or front = ParityEven = +X when `bForceFrontXAxis`), then right->left handed by negating Y (`Pos(x, -y, z)`). With defaults and a
Blender-system file this is: **UE = (Bx, -By, Bz) * 100**. glTF is the same mapping (GLTF/ConversionUtilities.h:
glTF (x,y,z) -> UE (x,z,y), and Blender's glTF exporter maps Blender (x,y,z) -> glTF (x,z,-y), net UE = (Bx, -By, Bz)).
Therefore a car authored with its nose toward Blender -Y (Blender convention) arrives pointing UE **+Y** (needs a -90 yaw), and
**a car authored with its nose toward Blender +X (right side toward -Y) arrives pointing UE +X** with zero configuration
(and its right side is UE +Y). Rule for this project: **build/orient all vehicles in Blender facing +X, up +Z, origin at ground
level centered on the wheelbase/track footprint, apply all transforms**. Alternative: author facing -Y and set translator
`bForceFrontXAxis=True` (config section in 3.7) which rotates -Y-front to +X.
**Calibration (do this once before building the garage):** export `AxisTest.fbx` containing a non-symmetric mesh (a 4.5 x 1.8 x 1.4
m wedge: pointed nose at +X, roof at +Z, a small bump on the Blender -Y side), import with the 3.7 function, then check
`get_bounding_box()`: expect extent X=450, Y=180, Z=140 and nose/bump on the expected sides (box.min/max asymmetry). If the
nose is on the wrong side set `ui.static_mesh_import_data.import_rotation = unreal.Rotator(0,0,+/-90)` (mapped to the pipeline
ImportOffsetRotation) or fix the Blender side. Do not guess; commit the result into the pipeline doc.

### 4.4 Reproducible Blender export script (run through the 9889 MCP `execute_blender_code`, or `blender -b file.blend -P`)

```python
import bpy, os, json
from mathutils import Matrix

OUT = r'W:/YouTube/Claude Sonnet 5.5/Forza Horizen/Sonnet55Forza/UnrealSonnet55Forza/Intermediate/BlenderExport'

FBX_KW = dict(
    use_selection=True, use_visible=False, use_active_collection=False,
    object_types={'MESH', 'EMPTY'},                 # EMPTY for SOCKET_*; add 'ARMATURE' only for skeletal cars
    global_scale=1.0, apply_unit_scale=True, apply_scale_options='FBX_SCALE_NONE',
    axis_forward='Y', axis_up='Z',                  # Blender-native system: nothing rotated, UE flips Y on import
    use_space_transform=True, bake_space_transform=False,
    use_mesh_modifiers=True, use_mesh_modifiers_render=True,
    mesh_smooth_type='OFF',                         # "Normals Only": keep Blender custom normals (import normals in UE)
    colors_type='SRGB', prioritize_active_color=False,
    use_subsurf=False, use_mesh_edges=False, use_tspace=False,   # tangents: let UE MikkTSpace compute them
    use_triangles=True,                             # UE wants tris; exporter triangulation after modifiers
    use_custom_props=False,
    add_leaf_bones=False, primary_bone_axis='Y', secondary_bone_axis='X',
    use_armature_deform_only=True, armature_nodetype='NULL',
    bake_anim=False,
    path_mode='AUTO', embed_textures=False,         # textures are built/imported separately
    batch_mode='OFF',
)

def export_part(objs, name, origin_matrix=None):
    """Export objs as <name>.fbx with the part moved so its pivot is the FBX origin.
       Works on throw-away linked copies, the scene is left untouched."""
    scn = bpy.context.scene
    tmp = bpy.data.collections.new('__export_tmp__'); scn.collection.children.link(tmp)
    copies = []
    inv = (origin_matrix or Matrix.Identity(4)).inverted()
    for o in objs:
        c = o.copy()                                    # shares mesh data (modifiers copied)
        if o.type == 'MESH': c.data = o.data
        c.matrix_world = inv @ o.matrix_world           # re-pivot
        tmp.objects.link(c); copies.append(c)
    bpy.ops.object.select_all(action='DESELECT')
    for c in copies: c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.fbx').replace('\\', '/')
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    for c in copies: bpy.data.objects.remove(c, do_unlink=True)
    bpy.data.collections.remove(tmp)
    return path
```
Checklist before export (assert in the script): all transforms applied on the source meshes (scale 1, no negative scale; apply
mirror modifiers or flip normals fixed), consistent normals, no n-gons survive (triangulate), no empty material slots, unique
material names, object names `SM_<Car>_Body` etc. without dots, UVs: one clean UV0 (0-1, non-overlapping for baked masks), second UV
channel only if a lightmap is wanted (not needed: Lumen + VSM, `r.AllowStaticLighting=False`). Textures: export separately as
PNG/EXR/TGA with sRGB / linear flags, import with `unreal.TextureFactory` / Interchange texture pipeline and set
`srgb` and `compression_settings` explicitly (normal map = `TC_NORMALMAP`, masks = `TC_MASKS`).
Wheels: pass the single wheel object with `origin_matrix = wheel_hub_matrix`, spin axis along the FBX axis you decide (e.g. Blender
Y -> UE -Y; rotate in code around that axis, verify with the calibration mesh). Emit a sidecar `<car>.json` with hub/socket
transforms in UE space `(x, -y, z) * 100` so code is not dependent on socket import.

### 4.5 glTF alternative (Blender 5.2 `bpy.ops.export_scene.gltf`)

Real property names in the local add-on: `export_format` ('GLB'|'GLTF_SEPARATE'|'GLTF_EMBEDDED'), `export_yup`, `export_apply`
(apply modifiers), `export_texcoords`, `export_normals`, `export_tangents`, `export_materials` ('EXPORT'|'PLACEHOLDER'|'NONE'),
`export_image_format`, `export_vertex_color`, `export_cameras`, `export_lights`, `export_extras`, `use_selection`,
`use_visible`, `collection`, `export_animations`, `export_skins`, `export_draco_mesh_compression_enable` (leave False).
Pros: meters-correct and axis-correct by spec; PBR materials arrive as `M_GLTF` instances through the Interchange glTF pipeline
(`DefaultGLTFAssetsPipeline`, `GLTFPipelineSettings.MaterialParents`); one self-contained file. Cons: no UCX_ collision convention,
no SOCKET_ convention, less control over per-mesh naming/pivots, Interchange glTF pipeline has fewer static-mesh knobs. Use for
pure-visual PBR props only; FBX for cars and anything with collision/sockets.

---------------------------------------------------------------------------------------------------

## 5. C++ build

### 5.1 Command lines (Windows, paths with spaces; run from PowerShell)

```powershell
$bat  = 'W:\Unreal Engine 5\UE_5.8\Engine\Build\BatchFiles\Build.bat'
$proj = 'W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Sonnet55Forza.uproject'
$log  = 'W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Tools\Logs\build_editor.log'
& $bat Sonnet55ForzaEditor Win64 Development "-Project=$proj" -WaitMutex "-Log=$log" -NoHotReloadFromIDE
if ($LASTEXITCODE -ne 0) { throw "UBT failed: $LASTEXITCODE" }
```
* Positional args to Build.bat: `<Target> <Platform> <Configuration> [UBT options]`; it just runs
  `dotnet UnrealBuildTool.dll %*` after taking a file lock (so two Build.bat runs queue). `-WaitMutex` makes UBT wait for another
  UBT instead of exiting with ConflictingInstance(10); `-NoMutex` allows parallel (do not). [SRC GlobalOptions.cs]
* Game target: `Sonnet55Forza Win64 Development` (standalone exe, cooked-data only). Editor target: `Sonnet55ForzaEditor Win64 Development`.
  Test/Shipping: `Test`, `Shipping`. `DebugGame` for debugging.
* Useful UBT switches [SRC BuildConfiguration.cs / BuildMode.cs]: `-Log=<file>`, `-Verbose`, `-Timestamps`, `-Progress`, `-NoUBA`,
  `-NoXGE`, `-MaxParallelActions=N`, `-NoUBTMakefiles`, `-ForceHeaderGeneration`, `-SingleFile=<cpp>` (compile one file),
  `-FailIfGeneratedCodeChanges`, `-Clean`/`-Mode=Clean`. UBA local executor is on by default ("Using Unreal Build Accelerator local
  executor", 8 actions on this 8-core CPU). `Rebuild.bat` / `Clean.bat` exist next to Build.bat.
* Regenerate project files: `& $bat -ProjectFiles "-Project=$proj" -Game -2026` (UBT mode GenerateProjectFiles; format flags
  `-2022`/`-2026`/`-VSCode`/`-Rider`; it writes both .sln and .slnx) [SRC ProjectFiles/VisualStudio/VCProjectFileGenerator.cs]. Generated
  files are only needed for an IDE; building from the command line does NOT require them. Adding/removing .cpp/.h files needs no
  regeneration for Build.bat (UBT globs the module dirs), but any Build.cs/Target.cs/uproject module change re-triggers makefile
  rebuild automatically.
* The `.uproject` is the source of truth: new module = add to `Modules` AND add the `ExtraModuleNames.Add(...)` in BOTH Target.cs
  files (editor module only in the Editor target).
* Packaging later: `& 'W:\Unreal Engine 5\UE_5.8\Engine\Build\BatchFiles\RunUAT.bat' BuildCookRun "-project=$proj" -platform=Win64 -clientconfig=Development -build -cook -stage -pak -archive "-archivedirectory=W:/.../Packaged"`
  (5.8: Zen server is the default cook output store and stays resident; automated builds should account for it [DOC release notes]).

### 5.2 Live Coding vs full build vs hot reload

* Live Coding (Windows, editor/PIE): `LiveCoding.Compile` / `LiveCoding.CompileSync` console commands, Ctrl+Alt+F11, `-LiveCoding[=bool]` startup flag
  [SRC LiveCodingModule.cpp]. Structural changes (new functions, new UPROPERTYs, layout changes) without Object Reinstancing are
  unreliable/crash-prone; header changes need reinstancing; new UCLASS files need a restart [DOC].
* While an editor/game with Live Coding is running, Build.bat REFUSES to build with "Unable to build while Live Coding is active. Exit the editor and
  game, or press Ctrl+Alt+F11 if iterating on code in the editor or game". The check (HotReload.CheckForLiveCodingSessionActive, [SRC HotReload.cs:270-279])
  runs only when `bAllowHotReloadFromIDE` is true, i.e. passing `-NoHotReloadFromIDE` disables the check - but then the link would fight the locked DLL, so
  do not use it to "force" builds. Plan: for autonomous work always close editors, build with Build.bat, then run headless `-Cmd` jobs.
  Live Coding is a human-iteration tool: SKIP for the pipeline.
* "Live Coding cannot be enabled while hot-reloaded modules are active" [SRC]: never mix IDE hot reload and Live Coding in one editor session.

### 5.3 5.8-specific compile pitfalls (the project uses V7 / Unreal5_8)

* **BuildSettingsVersion V7 turns these into ERRORS in our module** [SRC TargetRules.cs:162-170, CppCompileWarnings.cs]: missing return
  value (C4716), dangling reference/pointer to temporary (C4172/C4686), unreachable code (C4702, `/we4702`). Example of the last: code after
  `return`, after `checkNoEntry()`, after `UE_LOG(..., Fatal, ...)`, or a `default:` after exhaustive returns. V6: undefined identifier in
  `#if` (C4668) is an error; V5: `bValidateFormatStrings=true` (printf-style format strings are checked at compile time: `%s` with FString
  without `*` fails); V4: strict conformance (`/permissive-`), C++20.
* **IncludeOrderVersion Unreal5_8 removes transitive includes**: e.g. `HAL/VirtualAllocator.h` no longer drags in `HAL/CriticalSection.h` and
  `Misc/ScopeLock.h`; `IoHash.h` no longer drags `Containers/UnrealString.h`/`Serialization/Archive.h`; `Async/Future.h` no longer drags
  `Templates/Models.h` [SRC `UE_ENABLE_INCLUDE_ORDER_DEPRECATED_IN_5_8` guards]. Include what you use. Typical fixes: `Misc/ScopeLock.h`,
  `HAL/CriticalSection.h`, `Containers/UnrealString.h`, `Serialization/Archive.h`, `Templates/Models.h`.
* Logging: `UE_LOG(Cat, Verbosity, TEXT("... %s"), *Str)` still works; 5.8 prefers `UE_LOGF(Cat, Verbosity, "... %ls", *Str)` with ASCII/UTF-8
  literals ("require less memory"); engine itself now uses UE_LOGF. Mixing: UE_LOG needs `TEXT()`, UE_LOGF must NOT use `TEXT()`; wide strings
  need `%ls` in UE_LOGF [SRC LogMacros.h:272-304].
* Deprecation noise: the baseline build prints dozens of C4996 warnings from ENGINE headers (GetAssetRegistryTags, GetMargin -> GetMarginf, etc.)
  - they come from engine code, ignore; warnings in our module should be zero.
* Compiler is 14.51 > preferred 14.50: one-line warning only. Do not "fix" by switching toolchains.
* Adaptive unity build uses `git status`; the project is not a git repo, so UBT falls back to non-adaptive: fine.
* Stale DLL: after a failed link, delete `Binaries/Win64/UnrealEditor-Sonnet55Forza.dll` + `.modules` before retry only if the editor refuses to load it.
* Regenerating UHT output is automatic. If you see "UHT" errors about `generated.h` not being last include: it must be the LAST include in the header.
* Hot-reload/reinstancing fails when a Blueprint derives from a changed C++ class and the editor is open - another reason to always close editors before builds.

### 5.4 Module names verified to exist in 5.8 (Build.cs files found) and the plugin each needs in the .uproject

Runtime (engine, always available): Core, CoreUObject, Engine, InputCore, Slate, SlateCore, UMG, RenderCore, RHI, Renderer, PhysicsCore,
Chaos, ChaosSolverEngine, ChaosVehiclesCore + ChaosVehiclesEngine (under Runtime/Experimental/ChaosVehicles), Landscape, Foliage, AIModule,
NavigationSystem, AudioMixer, AudioExtensions, SignalProcessing, CinematicCamera, LevelSequence, MovieScene, GameplayTags, DeveloperSettings,
Json, JsonUtilities, ImageWriteQueue, AssetRegistry, Projects, MeshDescription, StaticMeshDescription, GeometryCore, GeometryFramework,
MassEntity, ClothingSystemRuntimeCommon, AnimGraphRuntime, AnimationCore, TraceLog. (`Engine` already PUBLICLY depends on Slate, SlateCore, InputCore,
Json, JsonUtilities, GameplayTags, AssetRegistry, RenderCore, RHI.)
From plugins (add the plugin to the uproject, else UBT cannot find the module): `EnhancedInput` (plugin EnhancedInput, default on),
`Niagara`+`NiagaraCore` (Niagara, default on), `MetasoundEngine`/`MetasoundFrontend`/`MetasoundStandardNodes`/`MetasoundGraphCore` (Metasound, default on),
`PCG` (+`PCGEditor`) (PCG, default on), `Water`+`WaterEditor` (Water, experimental, in uproject), `ProceduralMeshComponent` (default on),
`ChaosVehicles`+`ChaosVehiclesEditor` (plugin **ChaosVehiclesPlugin**, off by default), `ChaosModularVehicle`, `ChaosMover`, `GeometryScriptingCore`+
`GeometryScriptingEditor` (plugin GeometryScripting, off by default), `DynamicMesh` (GeometryProcessing, via the plugin), `Synthesis`, `AudioSynesthesia`,
`CommonUI`, `GameplayCameras`, `StateTreeModule` (plugin StateTree), `MassCommon` (plugin MassGameplay), `InterchangeImport`/`InterchangePipelines`/
`InterchangeNodes`/`InterchangeFactoryNodes`/`InterchangeCommon` (plugin Interchange, on) and engine-side `InterchangeCore`/`InterchangeEngine`, `AutomationUtils`.
Editor-only (put in a Type=Editor module): UnrealEd, EditorFramework, EditorSubsystem, LevelEditor, AssetTools, ContentBrowser, MaterialEditor,
StaticMeshEditor, LandscapeEditor, LandscapeEditorUtilities, ToolMenus, PythonScriptPlugin (interface `IPythonScriptPlugin`), EditorScriptingUtilities
(deprecated surface), InterchangeEditor*, LandscapePatch.
Developer modules (non-shipping only): AutomationController, AutomationDriver, FunctionalTesting (needs plugin FunctionalTestingEditor for editor maps), AssetTools.
Tests themselves need only Core + Engine (macros are in Core `Misc/AutomationTest.h`, helpers in Engine `Tests/AutomationCommon.h`).

Suggested layout: keep runtime module `Sonnet55Forza` (Slate/UMG/EnhancedInput/PhysicsCore/Niagara/Metasound/AIModule/NavigationSystem/Landscape/ProceduralMeshComponent as needed)
and ADD a second module `Sonnet55ForzaEditor` (`Type: Editor`, `LoadingPhase: Default`, listed ONLY in `Sonnet55ForzaEditor.Target.cs`) for Landscape generation, procedural asset baking,
BlueprintCallable editor functions callable from Python. Runtime code that touches editor APIs must be inside `#if WITH_EDITOR` or it breaks the Game target.
Skeleton Build.cs for the editor module:
```csharp
PublicDependencyModuleNames.AddRange(new[]{ "Core","CoreUObject","Engine","Sonnet55Forza" });
PrivateDependencyModuleNames.AddRange(new[]{ "UnrealEd","EditorSubsystem","LevelEditor","AssetTools","AssetRegistry","MaterialEditor","StaticMeshEditor",
  "Landscape","LandscapeEditor","MeshDescription","StaticMeshDescription","GeometryScriptingCore","InterchangeEngine","InterchangeCore","Slate","SlateCore","Projects","DeveloperSettings" });
```

---------------------------------------------------------------------------------------------------

## 6. C++ automation tests (drive tests without PIE)

### 6.1 Macros [SRC AutomationTest.h]

```cpp
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"         // Engine module: FTestWorldWrapper, AutomationOpenMap, FWaitLatentCommand...
#if WITH_DEV_AUTOMATION_TESTS               // non-shipping only; wrap the whole file
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FForzaDriveStraightTest, "Sonnet55Forza.Vehicle.DriveStraight",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)
```
Other macros: `IMPLEMENT_COMPLEX_AUTOMATION_TEST` (+ `GetTests(TArray<FString>& Names, TArray<FString>& Cmds)` to fan out cases),
`IMPLEMENT_CUSTOM_SIMPLE_AUTOMATION_TEST`, spec style `BEGIN_DEFINE_SPEC(...)/Describe/It/LatentIt/END_DEFINE_SPEC`,
`DEFINE_LATENT_AUTOMATION_COMMAND[_ONE|_TWO|_THREE|_FOUR|_FIVE_PARAMETER](Name, Type, Member...)` (you implement `bool Name::Update()`, return true when
done, params are private members), `ADD_LATENT_AUTOMATION_COMMAND(FName(args))`, engine-latent variants `DEFINE_ENGINE_LATENT_AUTOMATION_COMMAND*`. Flags:
contexts Editor/Client/Server/Commandlet/Program; features NonNullRHI, RequiresUser; priorities Critical/High/Medium/Low; filters Smoke/Engine/Product/Perf/Stress/Negative;
`Disabled`, `SupportsAutoRTFM`. Test pretty names are dot paths used by `RunTests` filtering. Assertions: `TestTrue/TestFalse/TestEqual/TestNearlyEqual/TestNotNull/AddError/AddWarning/AddExpectedError`.

### 6.2 PIE-less vehicle test with the engine's own test-world helper

`FTestWorldWrapper` creates a real `UWorld` + `UGameInstance` you tick manually: `CreateTestWorld(EWorldType::Game)`, `BeginPlayInTestWorld()` (creates the
GameMode, calls BeginPlay), `TickTestWorld(1/60.f)` (= `World->Tick(LEVELTICK_All, dt)` + frame counter), `EndPlayInTestWorld()`, `DestroyTestWorld(true)`
[SRC AutomationCommon.cpp:59-236]. Fully synchronous inside `RunTest`, deterministic fixed step, works under `-nullrhi`, no viewport or PIE.

```cpp
bool FForzaDriveStraightTest::RunTest(const FString& Parameters)
{
    FTestWorldWrapper W;
    if (!W.CreateTestWorld(EWorldType::Game)) { W.ForwardErrorMessages(this); return false; }
    UWorld* World = W.GetTestWorld();

    // Floor: an engine cube scaled flat (collision from the asset) - or spawn a generated ground actor from the project
    UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
    AStaticMeshActor* Floor = World->SpawnActor<AStaticMeshActor>(FVector(0,0,-50), FRotator::ZeroRotator);
    Floor->GetStaticMeshComponent()->SetStaticMesh(Cube);
    Floor->SetActorScale3D(FVector(1000.f, 100.f, 1.f));                 // 100 m x 10 km slab, 1 m thick
    Floor->GetStaticMeshComponent()->SetCollisionProfileName(TEXT("BlockAll"));

    AForzaVehiclePawn* Car = World->SpawnActor<AForzaVehiclePawn>(FVector(0,0,60), FRotator::ZeroRotator);
    TestNotNull(TEXT("car"), Car); if (!Car) return false;
    W.BeginPlayInTestWorld();
    Car->SetThrottle(1.0f); Car->SetSteer(0.0f);
    for (int32 i = 0; i < 60 * 8; ++i) { W.TickTestWorld(1.f/60.f); }     // 8 s sim
    const double SpeedKph = Car->GetVelocity().Size() * 0.036;          // cm/s -> km/h
    TestTrue(*FString::Printf(TEXT("speed %.1f km/h > 60"), SpeedKph), SpeedKph > 60.0);
    TestTrue(TEXT("stayed on lane"), FMath::Abs(Car->GetActorLocation().Y) < 100.0);
    W.EndPlayInTestWorld(); W.DestroyTestWorld(true);
    W.ForwardErrorMessages(this);
    return !W.HasFailed();
}
```
Caveats [NOT RUN]: physics runs at the project's Chaos settings (substepping / async physics tick), so assert with tolerances; call `GEngine->...` only if
needed; a Landscape/WP map is NOT loaded in this mode - for terrain-dependent tests use a map test: `AutomationOpenMap(TEXT("/Game/Maps/DriveTestMap"))`
then latent commands (`FWaitForMapToLoadCommand`, a custom `DEFINE_LATENT_AUTOMATION_COMMAND_ONE_PARAMETER(FDriveCheckCommand, FAutomationTestBase*, Test)`
whose `Update()` samples `GetAnyGameWorld()` each frame and returns true after N seconds) and finish with `FRequestExitCommand`/nothing (the `Quit` queued by
ExecCmds ends the process). `AutomationOpenMap` works in editor context; in `-game` pass the map on the command line instead.

### 6.3 Functional tests (map-based) - SKIP for now

`AFunctionalTest` actors in a map are registered via an asset-registry tag written when the map is saved (`TestNames`/`TestNamesEditor`) and appear as
`Project.Functional Tests.<MapPath>.<TestName>` (FunctionalTestingModule.cpp, ClientFuncTestPerforming.cpp:159). Needs plugin `FunctionalTestingEditor`
+ module `FunctionalTesting`. Good later for "drive the spline through the whole map" smoke test; C++ tests above are enough first.

### 6.4 Running them headless

* Editor context, no render: `& $ue $proj -unattended -nullrhi -nosplash -stdout -culture=en "-abslog=$log" '-ExecCmds=Automation RunTests Sonnet55Forza.Vehicle; Quit'`
* Client context uncooked: same with `-game /Game/Maps/DriveTestMap` (tests need `ClientContext`; flag both contexts as in 6.1).
* Success = process exit 0 AND log contains `**** TEST COMPLETE. EXIT CODE: 0 ****` AND `Found N automation tests` with N >= 1 (a typo in the filter gives 255).
* Results JSON: `-ReportExportPath="W:/.../Saved/Automation/Report"` (`index.json`); `-ResumeRunTest` continues after a crash [DOC].
* Per-test log lines [SRC AutomationControllerManager.cpp:43,1672-1680]: `LogAutomationController: Display: Test Completed. Result={<State>} Name={<pretty name>} Path={<full path>}`;
  a failed test is logged at Error level (so the `LogAutomationController: Error` grep catches it); state strings come from `AutomationStateToString` (Success / Fail / Skipped ...).

---------------------------------------------------------------------------------------------------

## 7. Windows pitfalls (spaces in project and engine paths)

### 7.1 General
* Every path in the task contains spaces: `W:\Unreal Engine 5\UE_5.8` and `...\Claude Sonnet 5.5\Forza Horizen\...`. Quote every token; prefer building arg arrays
  in PowerShell over hand-assembled strings. 260-char path limit applies to UBT intermediate files (`Intermediate/Build/Win64/x64/UnrealEditor/Development/<Module>/...`):
  keep module/class names short; current project root is ~90 chars, OK.
* `Build.bat` already handles the space in its own location (it `pushd`s into Engine/Source) - call it with a quoted full path.
* Prior editor runs used a different project root (`.../Sonnet55Forza/Sonnet55Forza`); stale absolute paths may linger in `Saved/`, `Intermediate/` and in `.sln`.
  If anything references the old root, delete `Intermediate/` and regenerate.

### 7.2 How Unreal parses the Windows command line [SRC] - why forward slashes are mandatory
1. `LaunchWindows.cpp:147-183 ProcessCommandLine()` rebuilds the command line from `argv`: any token containing a space gets quotes injected right after the first `=` if it starts with `-`
   (`-ExecutePythonScript=C:/a b/x.py` becomes `-ExecutePythonScript="C:/a b/x.py"`), otherwise around the whole token. So PowerShell's own quoting of a whole `-key=value with spaces` token is
   exactly right; you do NOT need to embed quotes yourself.
2. Values that UE reads with `FParse::QuotedString` (`-ExecutePythonScript="..."`, `-Script="..."` of the Python commandlet) are ESCAPE-PROCESSED: `\n`, `\r`, `\t`, `\\`, `\"`, octal `\0..7`,
   hex `\x..`, `\u....`, `\U........` are interpreted [SRC Parse.cpp:380-497]. A Windows path like `W:\tools\new\run.py` silently becomes TAB/newline/CR characters.
   Rule: **use forward slashes in every path that goes through Unreal's command line** (`-ExecutePythonScript=`, `-Script=`, `-abslog=`, `-ReportExportPath=`, `filename=` of HighResShot).
   Windows accepts them everywhere.
3. Script arguments with spaces: `-ExecutePythonScript="W:/x/s.py --out \"W:/a b/c\""` works per the plugin's own table (EditorPythonExecuter.cpp:154-163) but is brittle
   through PowerShell; pass a JSON path without spaces or have the script derive paths from `unreal.Paths.project_dir()`.
4. `-ExecCmds` splits on commas; a console command that needs a comma must be single-quoted inside.
5. `-abslog` needs `.log`/`.txt` extension and a writable folder (it will not create parents) - create the directory first.

### 7.3 Shells
* **PowerShell 5.1** (this machine): `&&`/`||` do not exist; use `;` and `if ($?)`. Native-argument quoting is the weak point: pass an ARRAY of arguments to `&`, each token as one
  element (PS quotes tokens with spaces itself); do not wrap an argument in extra literal `"` unless the token must contain quotes. Never use `2>&1` on native exes in 5.1 (turns stderr into
  ErrorRecords and sets `$?` false; the existing `Tools/build_editor.ps1` uses `*>&1 | Out-File` which works but mixes streams). `Out-File`/`>` write UTF-16 LE with BOM in 5.1 unless
  `-Encoding utf8`; `Set-Content` uses ANSI: always pass `-Encoding utf8` (Python then reads fine with `encoding='utf-8-sig'`). `Start-Process -PassThru` + `$p.Handle` trick for `ExitCode` (1.7).
  Use `Start-Process -Wait` or the Cmd exe; the GUI exe returns immediately.
* **Git Bash / MSYS** (the other shell here): MSYS rewrites POSIX-looking arguments before they reach Windows programs. Verified in this session:
  `cmd.exe //c echo /Game/Maps/Foo -ExecutePythonScript=/w/x.py` printed `W:/Git/Git/Game/Maps/Foo -ExecutePythonScript=W:/x.py`. So `/Game/Maps/X` and any `/w/...` argument is corrupted.
  Fixes: run UE from PowerShell (preferred), or `export MSYS_NO_PATHCONV=1` (also `MSYS2_ARG_CONV_EXCL='*'`), and always use `W:/...` style drive paths. Also in Git Bash `;` inside an argument can be treated as a path-list separator;
  keep `-ExecCmds=...;Quit` quoted. Use Git Bash only for grep/sed style work.
* `cmd.exe` consoles here are OEM cp866: do not rely on console encoding; read the UE log file (UTF-8) instead of stdout when you need exact text.

### 7.4 Other
* The shader/DDC caches: project-local `DerivedDataCache/` exists; first run of a new asset type compiles shaders for minutes (`ShaderCompileWorker`). Do not time out the first real-RHI run at < 20 min.
* Antivirus/Defender real-time scanning of `Intermediate/` slows builds massively and can cause sporadic LNK1104; exclude the project folder and `W:\Unreal Engine 5` if possible [general experience, NOT verified here].
* UBT runs a single instance per machine (mutex, 1.4). The editor also runs UBT on startup (`-Mode=ValidatePlatforms`, seen in the log) and UAT Turnkey SDK detection: if a Build.bat runs at the same moment the editor start can stall waiting; run steps sequentially.
* Crash Report Client pops up on crash in attended mode; `-unattended` suppresses dialogs, but still kill leftovers (`taskkill /IM CrashReportClient.exe /F`).

---------------------------------------------------------------------------------------------------

## 8. Decisions for THIS project (scope: one autonomous session, 4x4 km, code-generated assets, Blender cars)

| Feature | Decision | One-line reason |
|---|---|---|
| `-ExecutePythonScript` in `UnrealEditor-Cmd` | ADOPT | only reliable way to drive level/WP/asset building with a ready editor and no UI |
| `-run=PythonScript` commandlet | ADAPT | great for pure asset batches; no world, exit code -1 on error; use for imports/data tables |
| `-ExecCmds="Automation RunTests ...; Quit"` | ADOPT | the CI-style test runner; exit 255 on failure, 0 on success |
| `FTestWorldWrapper` PIE-less ticked world | ADOPT | deterministic fixed-step vehicle tests, headless, no map needed |
| Map-based Functional Tests | SKIP (later) | needs extra plugin and saved maps; C++ tests cover the loop |
| `-game` + `-nullrhi` drive runs | ADOPT | logic/physics validation without GPU; real RHI only for screenshots |
| `HighResShot` / `AutomationLibrary.take_high_res_screenshot` | ADAPT | needs real RHI and frame delay; poll task done before quit |
| Python stub (`Intermediate/PythonStub/unreal.py`) | ADOPT | already armed (`bDeveloperMode=True`); generated by first non-commandlet editor start |
| FBX import via `AssetImportTask` + `FbxImportUI` (Interchange engine) | ADOPT | supported scripted path in 5.8; set every option explicitly and assert results |
| Legacy `FbxFactory` | ADAPT | fallback only; watch `convert_scene_unit=false` default |
| Interchange pipeline-asset / `ScriptedImportAssetAsync` | SKIP | async, needs pipeline assets, no benefit here |
| Blender FBX, `FBX_SCALE_NONE`, `Y`/`Z` axes, cars facing +X, parts exported at origin | ADOPT | scale-safe, nothing rotated, matches UE=(x,-y,z) mapping (verify with AxisTest) |
| glTF export | ADAPT | PBR props only; no UCX/SOCKET conventions |
| Cars as static meshes + `SOCKET_` empties + shared wheel mesh | ADOPT | simplest, headless-testable with custom raycast vehicle |
| Chaos Vehicles / skeletal cars / Modular Vehicle | SKIP (unless physics lead chooses Chaos) | experimental plugin, needs skeleton + physics asset; modular vehicle is new in 5.8 |
| UCX_/UBX_ collision naming | ADOPT for props, SKIP for cars | cars use code primitives |
| GeometryScripting -> StaticMesh assets in the editor | ADOPT | Nanite-capable generated roads/props without Blender |
| `ProceduralMeshComponent` at runtime | ADAPT | only for runtime-varying geometry; no Nanite |
| Landscape creation from Python | SKIP | no Python API; use C++ editor module (`ALandscape::Import`) or mesh-based terrain |
| New WP level via `NewLevelFromTemplate(.../OpenWorld)` | ADOPT | one call gives a partitioned world; save to flush external actors |
| `WorldPartitionBuilderCommandlet` (HLOD, minimap) | ADAPT | late polish; needs real RHI + `-AllowCommandletRendering` |
| `MaterialEditingLibrary` material authoring | ADAPT | Substrate is on: few parents + MIs; recompile and check errors |
| Second `Type: Editor` module | ADOPT | keeps editor APIs out of the Game target; BlueprintCallable bridge to Python |
| Live Coding | SKIP | blocks Build.bat while active, unreliable for structural changes; full builds with editor closed |
| `Build.bat ... -WaitMutex -Log=` wrapper | ADOPT | deterministic exit codes (0/6/8/10) and a log file |
| UBA/XGE/FASTBuild distribution | SKIP | single machine, local UBA already on |
| PowerShell wrapper with timeout + tree kill | ADOPT | no engine-side watchdog exists |
| Forward-slash paths + PowerShell launcher | ADOPT | avoids FParse escape bug and Git Bash path rewriting |
| RunUAT BuildCookRun | ADAPT | final packaging only |

---------------------------------------------------------------------------------------------------

## 9. Open questions / things that must be confirmed by the first real run

1. Axis/orientation mapping (4.3) and unit scale are derived from source reading, not observed. Run the AxisTest calibration first.
2. `unreal.GeometryScript_NewAssetUtils.create_new_static_mesh_asset_from_mesh` return shape (tuple of mesh + outcome expected); confirm with the generated stub.
3. `sys.argv` contents with `-ExecutePythonScript` (no script name element per source) - print once.
4. Whether `FbxImportUI.static_mesh_import_data.normal_import_method` fully controls normals in the Interchange path or `bRecomputeNormals` (pipeline default true) wins; check
   shading on the calibration car and set translator/pipeline config if needed.
5. `NewLevelFromTemplate` under `-nullrhi` and the first-time WP external-actor save speed with thousands of actors.
6. Exact `HighResShot` output directory and frame delay in `-game`.
7. Whether `Interchange` honors `bBakePivotMeshes` for multi-part single-FBX imports; the recommended workflow avoids it (one part per FBX).
8. No Landscape Python API: confirm the editor-module bridge compiles under V7 warning-as-error rules.
9. Whether UnrealEd's startup UBT `ValidatePlatforms`/Turnkey calls add noticeable time to every headless run (log shows both on 2026-10-15); if so test `-NoTurnkeyRefresh`-style options by reading `TurnkeySupportModule`.

---------------------------------------------------------------------------------------------------

## 10. Sources actually used

Local (ground truth):
* W:/Unreal Engine 5/UE_5.8/Engine/Build/Build.version, Build/BatchFiles/Build.bat
* Engine/Plugins/Experimental/PythonScriptPlugin/Source/PythonScriptPlugin/Private/EditorUtilities/EditorPythonExecuter.cpp, EditorPythonScriptingLibrary.h, PythonScriptCommandlet.cpp, PythonScriptPlugin.cpp, PythonScriptPluginSettings.h, PyWrapperTypeRegistry.cpp
* Engine/Source/Developer/AutomationController/Private/AutomationCommandline.cpp; Runtime/Core/Public/Misc/AutomationTest.h, Private/Misc/AutomationTest.cpp; Runtime/Engine/Public/Tests/AutomationCommon.h + Private/Tests/AutomationCommon.cpp; Developer/FunctionalTesting/*
* Runtime/Engine/Private/ParseExecCommands.cpp, UnrealEngine.cpp, GameEngine.cpp, UnrealClient.cpp (HighResShot); Runtime/Launch/Private/LaunchEngineLoop.cpp, Windows/LaunchWindows.cpp; Runtime/Core/Private/Misc/{Parse.cpp,App.cpp,OutputDeviceStdOut.cpp}, GenericPlatform/GenericPlatformOutputDevices.cpp, Windows/WindowsPlatformMisc.cpp
* Engine/Source/Programs/UnrealBuildTool/{GlobalOptions.cs,Configuration/BuildConfiguration.cs,Configuration/Rules/TargetRules.cs,Configuration/Rules/CppCompileWarnings.cs,System/HotReload.cs,Modes/BuildMode.cs,ProjectFiles/VisualStudio/VCProjectFileGenerator.cs}; Programs/Shared/EpicGames.Core/UnrealEngineTypes.cs
* Engine/Source/Developer/Windows/LiveCoding/Private/LiveCodingModule.cpp; Runtime/Core/Public/Logging/LogMacros.h
* Interchange: Engine/Source/Runtime/Interchange/Engine/{Public/InterchangeManager.h,Private/InterchangeManager.cpp}; Engine/Source/Developer/AssetTools/Private/AssetTools.cpp; Engine/Plugins/Interchange/Runtime/Source/{Import/Public/Fbx/InterchangeFbxTranslator.h,Import/Private/Fbx/InterchangeFbxTranslator.cpp,Pipelines/Public/*.h,Pipelines/Private/InterchangeLODDataParser.cpp,Parsers/Fbx/Private/FbxConvert.{cpp,h},Parsers/GLTFCore/Private/GLTF/ConversionUtilities.h}; Plugins/Interchange/Editor/Source/InterchangeEditor/Private/InterchangeFbxAssetImportDataConverter.cpp; Runtime/Interchange/Core/Private/InterchangeTranslatorBase.cpp
* Editor/UnrealEd (Factories/Fbx*, AssetImportTask.h, EditorActorSubsystem.h, EditorAssetSubsystem.h, WorldPartition builders), Editor/LevelEditor/Public/LevelEditorSubsystem.h, Editor/StaticMeshEditor/Public/StaticMeshEditorSubsystem.h, Editor/MaterialEditor/Public/MaterialEditingLibrary.h, Editor/LandscapeEditor/Public/LandscapeEditorUtils.h, Runtime/Landscape/Classes/LandscapeProxy.h, Plugins/Runtime/GeometryScripting (MeshAssetFunctions.h), Plugins/Editor/EditorScriptingUtilities
* W:/Blender/5.2/scripts/addons_core/io_scene_fbx/{__init__.py,export_fbx_bin.py,fbx_utils.py}, io_scene_gltf2/__init__.py
* Project: Sonnet55Forza.uproject, Config/*.ini, Source/*.cs, Tools/build_editor.ps1, Tools/Logs/build_baseline.log, Saved/Logs/Sonnet55Forza.log

Web (official unless noted):
* https://dev.epicgames.com/documentation/en-us/unreal-engine/scripting-the-unreal-editor-using-python
* https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5-8-release-notes
* https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-command-line-arguments-reference
* https://dev.epicgames.com/documentation/en-us/unreal-engine/run-automation-tests-in-unreal-engine
* https://dev.epicgames.com/documentation/en-us/unreal-engine/using-live-coding-to-recompile-unreal-engine-applications-at-runtime
* https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-static-mesh-pipeline-in-unreal-engine
* https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/FbxImportUI and .../InterchangeGenericAssetsPipeline (search results)
* https://docs.blender.org/api/5.0/bpy.ops.export_scene.html (search result; signature cross-checked against the local 5.2 add-on)
* Community (unofficial, cross-checked against source): https://app.cinevva.com/guides/blender-to-unreal-export-checklist ;
  https://raw.githubusercontent.com/EpicGamesExt/BlenderTools/main/send2ue/dependencies/unreal.py (Epic's Send2UE add-on: confirms task fields automated/replace_existing/save and FbxImportUI usage)
