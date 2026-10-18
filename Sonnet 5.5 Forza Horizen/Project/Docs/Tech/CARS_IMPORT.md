# Vehicle import, materials and data (agent I "car-import")

Status date 2026-10-17. Everything below is produced by re-runnable scripts in `Tools/ue/cars_*.py`; the assets under
`Content/Forza/Cars`, `Content/Forza/Traffic`, `Content/Forza/Materials/Cars` and `Content/Forza/Data` are their output (committed).

## 1. What exists

| Area | Assets | Script |
|---|---|---|
| 10 player cars, 8 static meshes each | `/Game/Forza/Cars/<id>/SM_<id>_{Body,Glass,Interior,SteeringWheel,Wheel_FL,Wheel_FR,Wheel_RL,Wheel_RR}` (80 meshes) | `cars_import.py` |
| 6 traffic vehicles (4 / 4 / 10 / 6 / 4 / 4 wheels) | `/Game/Forza/Traffic/<id>/SM_<id>_{Body,Glass,Interior,Wheel_*}` (36 meshes) | `cars_import.py` |
| Vehicle materials | 21 masters `M_Roam_*` + 25 instances `MI_*` in `/Game/Forza/Materials/Cars/` | `cars_materials.py` |
| Car data | `/Game/Forza/Data/DA_Car_<id>` x10 (`URoamCarDefinition`), `DA_CarCatalog` (`URoamCarCatalog`, roster order) | `cars_data.py`, `cars_spec.py` |
| Traffic data | `/Game/Forza/Data/DA_TrafficVehicles` (`URoamTrafficCatalog`, new class, see 6) | `cars_data.py` |
| Verification | showroom captures `Saved/CarsShowroom/<id>__<view>.png` | `cars_showroom.py` |
| One-session driver | stages `materials,import,data,showroom` in a single editor start | `cars_build_all.py` |

`Config/DefaultGame.ini [/Script/Sonnet55Forza.RoamSettings] CarCatalog=/Game/Forza/Data/DA_CarCatalog.DA_CarCatalog` was already registered by the lead
(soft reference); the asset now exists at that path, so `URoamGameInstance::GetCarCatalog()` resolves. `DefaultCarId=car01_hatch_pulse` matches.

## 2. How to run

All commands from the project root in PowerShell. The editor start dominates (1-8 minutes), so use the shared job server when it is up
(`Tools/ue/ue_job.ps1`, see `Saved/MatJobs/README.txt`; a job must never call `QUIT_EDITOR`) and `cars_build_all.py` for standalone runs:

```powershell
# everything (materials -> import -> data), then the showroom; one editor start
$env:ROAM_STAGES='materials,import,data,showroom'; powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/cars_build_all.py -LogName cars_all -TimeoutSec 3600
# only some vehicles / only re-bind materials: environment ROAM_ARGS="only=car01,traffic02 skip_import=1"   (job server: -Args0 "only=car01 skip_import=1")
# offline tuning table (plain Python, no editor):  "W:\Blender\5.2\python\bin\python.exe" -I Tools/ue/cars_spec.py
```
Log markers: `CARS_IMPORT`, `CARS_VALIDATE` (one row per check), `CARS_RESULT`, `CARS_MAT`, `CARS_DATA`, `CARS_PI`, `CARS_SHOW`.
The editor exits with code 3 after `QUIT_EDITOR` in these standalone runs (the known `ModeManagerInteractiveToolsContext` shutdown assert of 5.8.2 when no
level editor was started): all assets are saved before that, ignore it.

## 3. Import recipe and what was learned (5.8.2)

* **Only a legacy `unreal.FbxImportUI` in `task.options` is honoured** by `AssetTools.import_asset_tasks` (it is converted into the Interchange pipeline,
  `UInterchangeManager::ConvertImportData`). An `InterchangeGenericAssetsPipeline` object put into `options` is silently ignored (defaults are used:
  Nanite on everything, materials imported, recompute normals) - `Tools/ue/import_test2.py` did not prove otherwise. `cars_import.py::make_import_options` sets every option.
* `auto_generate_collision` is mapped to Interchange's *import collision* switch. It must be **True for the Body**, otherwise the `UCX_` hulls are skipped
  (a re-import of an existing mesh kept its old hulls, which hid the bug in the first test). Parts without hulls get a fallback 18-DOP that
  `apply_mesh_settings` removes again, so only the Body has simple collision (`CTF_USE_SIMPLE_AS_COMPLEX`).
* `import_materials=False`: the static-material **slot names stay `M_Paint`, `M_Chrome`...**; `bind_materials` assigns `MI_<name without M_>` by slot name
  after every import (stray `M_*`/`MI_*` assets in a vehicle folder are deleted). Slots without an instance are reported as `unbound_slots` failures.
* Nanite ON for every opaque part, OFF for `Glass` (translucent). Lightmap UV generation off, `recompute_normals` off (Blender normals kept), tangents
  recomputed with MikkTSpace, degenerate triangles removed. `apply_mesh_settings` re-checks and fixes the build settings after the import.
* Asset names: `destination_name = SM_<fbx stem>` (e.g. `SM_car03_muscle_thunderline_Wheel_RR`).
* Coordinates: the exports are already centred per part, so no pivot fix is needed: body/glass/interior pivot = car origin, wheel and steering-wheel pivot = axle / hub.
  UE position = (x*100, -y*100, z*100) from the sidecar JSON (left wheels have **negative Y**). FR/RR meshes are mirror-built: they need no rotation.
* `MaterialEditingLibrary.set_material_instance_*_parameter_value` **always returns False** in 5.8.2 (engine bug, `bResult` never set) although it applies the
  value; the scripts verify by reading the value back instead.
* A job that waits on the shared server can be killed by a standalone `ue_cmd.ps1` run of anybody (it asks the server to quit): jobs must finish quickly or be
  re-submitted. The tick-driven showroom therefore runs standalone.

### Validation table (all 16 vehicles; printed as `CARS_VALIDATE`)
Per part: body length / width (with mirrors) / top height equal the JSON values to < 0.1 cm for all 16 vehicles; Body centre x ~ 0, centre y = 0, underbody between
ground and ride height; `ucx_hulls` equals `len(json.ucx)`; wheel bounds = 2 x radius, width = JSON width, pivot offset 0.00 cm; steering-wheel bounds centre within
3 cm of the hub; no simple collision on any non-body part; Nanite on/off as specified; every JSON material slot present and bound to an instance.
The scale/orientation rules therefore hold: nose +X, wheel pivots at the axle centres, 1 Blender m = 100 UE cm.

## 4. Material system (Substrate)

Masters (`/Game/Forza/Materials/Cars/`): `M_Roam_CarPaint`, `M_Roam_CarGlass`, `M_Roam_Chrome`, `M_Roam_TrimBlack` (generic plastic), `M_Roam_Rubber`, `M_Roam_Tyre`,
`M_Roam_Rim`, `M_Roam_BrakeDisc`, `M_Roam_Caliper`, `M_Roam_Plate`, `M_Roam_Exhaust`, `M_Roam_Headlight/Taillight/Reverse/Indicator`,
`M_Roam_IntDash/IntSeat/IntTrim/IntCarpet`, `M_Roam_Rust`, `M_Roam_Wood` (traffic extras). All end in a Substrate front material (`Slab`, `Simple Clear Coat`, or `Weight` for the glass
coverage); heavy shading is in one `Custom` HLSL node per master whose inputs are parameter nodes, so every value is overridable on instances and on dynamic instances.
Opaque masters carry `used_with_nanite`. **Weather** (wet film, dust/dirt, snow on up-facing paint, rain droplets on the glass) is driven by four scalars present on every
master: `Wetness`, `RainIntensity`, `SnowAmount`, `DustAmount` (per-instance values, set by `RoamVehicleVisuals` from `URoamTimeWeatherSubsystem` when the weather changes). Optionally the
masters can read them from `MPC_Roam_World` (static switch `UseWorldMPC`, default OFF): material nodes reference collection parameters by **GUID**, and the owner of the MPC rewrites its
parameter list (new GUIDs) whenever it rebuilds it - every master that pointed at the old GUIDs then fails to compile at the next load ("CollectionParameter has invalid parameter None", the car
renders with the grey default material). With the switch off only the scalar branch is compiled, so a rebuilt MPC cannot break the vehicles; to switch to the MPC re-run `cars_materials.py`
after the MPC is final and set `UseWorldMPC` on the instances.

Instances are named after the Blender slots: `M_Paint -> MI_Paint`, `M_Paint2 -> MI_Paint2`, `M_Chrome -> MI_Chrome`, ... `M_Traffic_Rust -> MI_Traffic_Rust`.
`MI_TrimGrey`, `MI_Underbody` share `M_Roam_TrimBlack`; `MI_Rim`, `MI_RimDark` share `M_Roam_Rim`; paint and paint2 share `M_Roam_CarPaint`.

### Parameter contract for `Vehicle/RoamVehicleVisuals` (create `UMaterialInstanceDynamic` per slot and set exactly these names)

| Slot (instance) | Parameter | Type | Meaning / defaults |
|---|---|---|---|
| `M_Paint` (`MI_Paint`) | `PrimaryColor` | vector | `FRoamPaint.Primary` |
| `M_Paint` | `StripeColor` | vector | `FRoamPaint.Secondary` (stripes are drawn in the same slot) |
| `M_Paint` | `StripeStyle` | scalar 0..4 | `FRoamPaint.StripeStyle`: 0 none, 1 twin stripes (|y| 8..20 cm), 2 wide centre stripe, 3 centre + pinstripe, 4 side belt-line band. Object-space masks (LocalPos/LocalNormal), independent of UVs; styles 1-3 appear on up-facing surfaces only |
| `M_Paint2` (`MI_Paint2`) | `PrimaryColor` | vector | `FRoamPaint.Secondary` (roof/accent parts) |
| both paint slots | `Metallic` / `BaseRoughness` / `ClearCoat` / `ClearCoatRoughness` / `FlakeIntensity` / `FlakeScale` / `MatteFlatness` | scalar | finish presets below |
| every master | `Dirt` (0..1), `Wetness`, `RainIntensity`, `SnowAmount`, `DustAmount` (0..1) | scalar | per-car dirt and the weather state (see above); `Dirt` also exists on all non-paint masters |
| `M_Headlight`, `M_Taillight`, `M_Reverse`, `M_Indicator` | **`Intensity`** | scalar | 0 = off, 1 = on at design brightness (may exceed 1 for bloom). Emission = `EmissiveColor * Intensity * EmissiveScale`. Suggested: head 1 at night, tail 0.25 running / 1.0 braking, reverse 1, indicator blink 0/1 |
| `M_Rim` (`MI_Rim`) | `BaseColor` | vector | `FRoamPaint.WheelColor` (instances `MI_RimDark` keep their own dark colour) |
| `M_Caliper` | `BaseColor` | vector | caliper colour |
| `M_BrakeDisc` | `HeatGlow` | scalar 0..1 | red-hot glow on the friction ring (heavy braking) |
| `M_Glass` (`MI_Glass`) | `TintColor`, `Opacity`, `FresnelPower`, `RainStrength`, `Dirt` | vec/scalar | glass tint (default 22 % opacity + Fresnel); rain droplets/haze come from `RainIntensity`/`DustAmount`/`Dirt` |

Finish presets (set these on both paint slots; the hatch of `FRoamPaint.Finish`):

| Finish | Metallic | BaseRoughness | ClearCoat | ClearCoatRoughness | FlakeIntensity | MatteFlatness |
|---|---|---|---|---|---|---|
| Gloss | 0.0 | 0.38 | 1.0 | 0.035 | 0.0 | 0.0 |
| Matte | 0.0 | 0.80 | 0.0 | 0.035 | 0.0 | 1.0 |
| Metallic | 0.85 | 0.33 | 1.0 | 0.035 | 0.65 | 0.0 |

`FlakeScale` (default 700 cells per metre) is the size of the micro-facets; they fade out beyond ~13 m so they never shimmer.

## 5. Data assets and tuning method

Geometry comes from the sidecar JSON, never from constants: wheel centres / radii / widths, steering-wheel hub + axis (axis points **at the driver**, so
`FQuat(Axis, +angle)` turns clockwise as seen by the driver), camera anchors (hood, cockpit, bumper), head/tail/reverse/exhaust anchors, length/width/height/wheelbase/track/ride height.
`cars_spec.py` holds the physics layer; `derive()` turns it into UE numbers:

* torque curve `shape(x) = max(floor, 1 - k (x - xp)^2)`, x = rpm/redline, scaled so max(T*omega) = roster power (same family as `BuildSyntheticTorqueCurve`, with per-car peak position `xp`; 32 samples);
* gears: drag-limited top speed from `eta*P = 0.5 rho CdA v^3 + Crr m g v`, top gear = 1.04..1.10 x that speed at redline, first gear from "speed at redline in 1st", geometric spacing with a closer top end;
* springs `k = 0.88 m_axle/2 (2 pi f)^2`, f = 1.1 (SUV/sedan) .. 2.2 Hz (supercar); damping `c = 2 zeta sqrt(k m)` with bump zeta 0.28-0.42, rebound 0.45-0.68; anti-roll = 0.1-1.1 x spring rate; bump-stop 8 x spring rate;
* tyres: peak mu street 0.9-1.0, sport 1.15-1.2, supercar 1.42-1.45, rally 0.85 on asphalt but `SurfaceBias` 1.3-1.4 on dirt/gravel (Ridge), all-terrain 1.12-1.25 (Ranger, Mule), vintage 0.8; nominal load = static axle load;
* brakes: peak decel 0.78 g (drums) .. 1.40 g, bias front 0.52-0.66; handbrake torque = 1.35 x lock torque of the static rear wheel load;
* centre of mass x from the front weight fraction (`COM.X = (wf - 0.5) * wheelbase`), z from the roster class (44-88 cm).

Engine-side estimator numbers (the engine's own `ComputePerformance`, identical to the offline port) and the roster target class:

| # | Car | kg | kW | Drive | 0-60 s | 0-100 s | vmax km/h | lat g | 100-0 m | PI | Class | Roster target |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Pulse | 1250 | 155 | FWD | 3.78 | 6.72 | 234 | 0.91 | 42.7 | 600 | C | D/C |
| 2 | Cadence | 1480 | 120 | FWD | 4.13 | 9.21 | 215 | 0.74 | 44.3 | 496 | D | D |
| 3 | Thunderline | 1650 | 310 | RWD | 2.98 | 5.58 | 293 | 0.91 | 39.3 | 685 | B | B |
| 4 | Vesper | 1380 | 285 | RWD | 2.57 | 4.73 | 314 | 1.22 | 33.2 | 766 | A | A |
| 5 | Meridian GT | 1700 | 410 | RWD | 2.66 | 4.51 | 343 | 1.20 | 32.3 | 785 | A | A/S1 |
| 6 | Aether | 1450 | 540 | AWD | 1.25 | 2.19 | 350 | 1.66 | 27.4 | 925 | S2 | S2 |
| 7 | Ridge | 1260 | 235 | AWD | 2.36 | 4.36 | 255 | 0.79 | 45.2 | 697 | B | B |
| 8 | Ranger | 2150 | 220 | AWD | 3.13 | 6.76 | 214 | 0.75 | 42.7 | 600 | C | C |
| 9 | Mule | 2350 | 250 | RWD | 3.60 | 7.37 | 226 | 0.75 | 44.7 | 577 | C | C |
| 10 | Brisa | 900 | 70 | RWD | 4.41 | 10.01 | 170 | 0.69 | 50.4 | 395 | D | D |

Notes: the PI *numbers* of `CAR_ROSTER.md` (380, 330, 580 ...) cannot be matched together with the roster power/mass under the binding PI formula (a 155 kW / 1250 kg hatch is C/B by
construction); the class **letters** were the target and all ten land in them (Pulse at the C/B edge 600, Ranger at 600, Ridge at 697). The estimator is optimistic for
heavy cars (0-100 of the SUV 6.8 s; a real one needs 8-9 s): the physics agent calibrates with `DRIVE_TESTS`, the numbers in the data assets are a *first pass*.
Sound presets named in `FRoamSoundSpec.Profile`: `inline4` (Pulse, Cadence, Ridge, Brisa), `v8` (Thunderline, Mule), `flat6` (Vesper), `v12` (Meridian), `v8_flatplane` (Aether), `v6` (Ranger);
cylinders, harmonic mixes, turbo whine (Pulse, Aether, Ridge, Ranger), blow-off and crackle are per-car data.
Makers are invented placeholders (Nordvik Motors, Alder Motorworks, Bannock Automotive, Corvane Coachworks, Lorien GT, Zephyra Hypercars, Tarn Rally Works, Highmoor Overland, Coldwater Truck Co., Brisa Motor Co.) - rename freely, nothing refers to them.

## 6. Traffic data (`URoamTrafficCatalog`)

The traffic subsystem header only had the registry struct `FRoamTrafficVehicleSpec` (one wheel mesh, no glass/interior, no per-wheel placement), so a small data class was added
in the runtime module **without touching any traffic header**: `Source/Sonnet55Forza/Data/RoamTrafficCatalog.h/.cpp` (`FRoamTrafficWheelDef`, `FRoamTrafficVehicleDef`,
`URoamTrafficCatalog`). `DA_TrafficVehicles.Vehicles[i].Spec` is the ready-made `FRoamTrafficVehicleSpec` for `URoamTrafficSubsystem::RegisterVehicleType` (`URoamTrafficCatalog::GetSpecs`),
the rest (glass, interior, **all** wheels with centre / radius / width / axle / steering / driven / side, light and camera anchors in UE cm, exhausts, paint variants from the JSON, cruise speed range, axle count)
is for `ARoamTrafficVehicle` when it builds its component set. IDM numbers (max speed, acceleration, comfort decel, headway, min gap), mass and spawn weights are first-pass values in `cars_spec.py::TRAFFIC`
(lorry and coach only on Highway/Regional/Mountain, tractor only on Dirt/Village/Regional). Loading: `LoadObject<URoamTrafficCatalog>(nullptr, TEXT("/Game/Forza/Data/DA_TrafficVehicles.DA_TrafficVehicles"))`
(`RoamSettings` has no field for it; the traffic owner may add one with the append-only rule). Both targets compile warning-free with the new class.

## 7. Showroom findings (what the screenshots show)

Method: `Tools/ue/cars_showroom.py` builds every car from its `DA_Car_<id>` (static meshes, geometry anchors, `MI_*` slot instances, suggested paint) in a blank map with sun + fill + HDR sky and shoots
7 views per car (`front34, side, front, rear34, wheel, cockpit, interior` with body and glass hidden) with a `SceneCapture2D`; `finish=1` adds matte/metallic variants, `night=1` lights the lamps
(`Intensity` = 1 on head/tail lights), `traffic=1` shoots the six civilian vehicles. 91 + 24 + 6 images in `Saved/CarsShowroom/` (not committed). A windowed `-game` run on `L_Test`
(`ue_cmd.ps1 -Game ... -ExecCmds "roam delay 5 car 1, ..., roam delay 11 car 6, ..., roam delay 17 car 10, ..."`) confirmed the real runtime path: `ROAM_CAR_APPLIED car06_super_aether (Aether) S2 925`,
`ROAM_VEHICLE_READY ... placeholder=0`, the catalog resolves from `DefaultGame.ini`, `car <n>` switches the meshes. 22/22 `Roam.*` automation tests still pass.

Honest status per car (all ten and all six traffic vehicles import, validate, bind materials and render; nothing is missing or inside out):

| # | Car | Imported / validated | Looks right in the showroom | Notes |
|---|---|---|---|---|
| 1 | Pulse | yes (3 UCX hulls) | yes: smooth hatch, 5-spoke alloys, calipers, wipers, door seams, fuel flap, tail light | default roof accent is black (`M_Paint2` = secondary paint) |
| 2 | Cadence | yes (4 hulls) | yes: grille + blank plate, chrome-less trim, 10-spoke wheels | |
| 3 | Thunderline | yes (4 hulls) | yes: hood scoop, grille, quad lamps, centre+pinstripes (`StripeStyle` 3) draw correctly in object space | |
| 4 | Vesper | yes (4 hulls) | yes: hood vents, ducktail, 19" wheels | |
| 5 | Meridian GT | yes (3 hulls) | yes: long hood, tail strip, quad exhaust | roof is the silver accent in paint 0 |
| 6 | Aether | yes (3 hulls) | yes: wing, side intakes, perforated engine glass, diffuser | stripe style 1 also paints the wing's up-facing surfaces (object-space mask: no per-part mask yet) |
| 7 | Ridge | yes (3 hulls) | yes: wing, roof pod, spotlight bar, mud flaps, race number "7" (modelled), knobbly 15" tyres | |
| 8 | Ranger | yes (3 hulls) | yes: roof rack, snorkel, spare wheel, bull bar, side steps | |
| 9 | Mule | yes (4 hulls) | yes: bed with tailgate, roll bar, beacon lights, mud flaps | |
| 10 | Brisa | yes (4 hulls) | yes: separate wings, spoked wheels, round lamps, folded soft-top | headlamp lenses read black in daylight (lens albedo 0.06, no reflector) |
| T1-T6 | compact, van, lorry (10 wheels, 3 axles), coach (6), tractor, pickup (rust + wood extras) | yes | yes: wheel placement and dual wheels correct, rust patches show on the pickup | tail-light anchors of coach/tractor missing (JSON bug, section 8) |

Things the screenshots taught (all fixed UE-side, listed because they change how to test):
* **Nanite streams in asynchronously**: a freshly spawned car renders with Nanite's very coarse *fallback* (faceted bodies, octagonal tyres) until its pages arrive, which needs several *captures/frames that actually draw it*
  (not seconds of idling). The first screenshots looked like a low-poly model; they were not. The showroom now renders 10 warm-up frames per car before shooting.
* **Shaders of a rebuilt master compile asynchronously** (minutes on this machine); until then the car shows the grey default material. The showroom probes the picture's colourfulness and waits.
* **Scene captures ignore eye-adaptation exposure** (`auto_exposure_bias` has no effect): light intensities must be display-range (sun 30, fill 14, cubemap sky 3.0) - the 110 000 lux physical sun blows everything out.
* **Metals need an environment** to look like metal; with a black sky the rims read black. The showroom uses `/Engine/MapTemplates/Sky/DaylightAmbientCubemap`.
* **Tail lights**: emissive red at scale 14 tone-mapped to orange; scale 6 with (1, 0.008, 0.004) reads red.
* Interior/arch plastics looked like sandpaper with a high-frequency normal grain: the grain is now a smooth two-field tilt with low defaults.


## 8. Blender-side problems for the lead

Found while importing (none blocks the pipeline; geometry, pivots, scale and slots of all 16 vehicles validate):

1. **`Exports/Traffic/traffic04_bus/traffic04_bus.json` and `traffic05_tractor.json`**: the `lights` block has a corrupted key `"_"` (control characters, a regex back-reference artefact in the JSON writer) where `tail_l`/`tail_r` should be, so the
   tail-light anchors of the coach and the tractor are missing (`DA_TrafficVehicles` leaves them at zero). Fix the writer in `Tools/blender/lib/fbx_export.py` / the traffic export step and re-export the two JSON files.
2. The sidecar JSON of the **traffic** vehicles uses a different schema from the player cars (`wheels` is a list, not `FL/FR/RL/RR`); the importer handles both, but `Docs/BLENDER_CONTRACT.md` section 5 only documents the car schema.
3. `ride_height` in the traffic JSON is the frame height, not the underbody clearance (lorry 0.62 m while the body bottom is at 0.225 m): the data asset keeps it as given.
4. Player-car JSON has no `paint_variants`; the suggested paints in `DA_Car_*` are defined in `Tools/ue/cars_spec.py`.

## 9. Tooling notes (several agents share this folder)

* The project has ONE Unreal process at a time (mutex in `ue_cmd.ps1`/`build_editor.ps1`). Another agent runs a persistent editor "job server" (`Tools/ue/materials_server.py`, protocol in `Saved/MatJobs/README.txt`):
  `Tools/ue/ue_job.ps1 <script> -Args0 "<JOB_ARGS>"` runs a script inside it (jobs must never call `QUIT_EDITOR`, `JOB_ARGS` carries `key=value` tokens). `cars_import.py`, `cars_materials.py`, `cars_data.py` run unchanged
  as jobs or standalone; `Tools/ue/cars_submit.sh <script> "<args>"` drops a job file straight into the inbox without waiting for the server. A multi-frame job (the showroom) must write `Saved/MatJobs/hold_<name>` and touch it at least every 20 minutes
  (`hold_cars` in `cars_showroom.py`), otherwise the server quits between jobs when anybody asks and kills it.
* Standalone `-ExecutePythonScript` quits the editor the moment the script returns unless `unreal.EditorPythonScripting.set_keep_python_script_alive(True)` was called (the showroom does); a Python error also quits it (`Python script executed with errors`).
* `MaterialParameterCollection` references are GUID based - see section 4 for why the vehicle masters do not depend on `MPC_Roam_World` by default.
* `MaterialEditingLibrary.set_material_instance_*_parameter_value` returns False although it works (verify by reading back); `unreal.MaterialInstanceDynamic.create` does not exist in Python: use `StaticMeshComponent.create_dynamic_material_instance(slot, parent)`.
* A scene-capture showroom run costs ~5 minutes standalone; the same job inside the server costs the same but waits for other agents' jobs (a stuck job of another agent blocked the queue for 40 minutes once).
