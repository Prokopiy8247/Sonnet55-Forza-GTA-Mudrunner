# World materials (masters, instances, MPC, tooling)

Agent M "world-materials" (two instances worked on it: M-A = nature / fx / instances registry, M-B = roads / buildings / roadside / tooling; see
`Tools/ue/M_STATUS_MB.md`).  Everything is generated from Python and is idempotent: one command builds / refreshes it all.

| document | content |
|---|---|
| this file | tooling, MPC layout, textures, road / building / glass / roadside masters and their instances, known engine quirks |
| `MATERIALS_nature.md`, `MATERIALS_nature_fx.md` | foliage, bark, grass, flowers, rocks, far tree cards, water, particles, decals, glass instances (M-A) |

## 1. Build and test commands

```
# everything (needs the editor; through the persistent job server - see section 2)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/materials_build.py -TimeoutSec 1800 -Args0 "mpc textures masters instances"
# only some masters / only the instances / only a few texture groups
... -Args0 "masters=M_Roam_Road,M_Roam_Building instances"          ... -Args0 "textures=Road,Building"        ... -Args0 "textures force"
# stand-alone (own editor start, 2-10 min, quits when done)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/materials_build.py -LogName materials_build
# test sheet screenshots (Saved/MatShots/<shot>.png, look at them with the Read tool)
... Tools/ue/ue_job.ps1 Tools/ue/materials_sheet.py -Args0 "road,bld,struct,roadside"      (nature: "trees,ground,treemesh")
# slot coverage (plain python): every non-car Blender slot of Exports/**/*.json has an instance in Tools/ue/materials_slot_map.json
"W:/Blender/5.2/python/bin/python.exe" -I Tools/ue/materials_check_slots.py
```
Steps of `materials_build.py` (default `mpc textures masters instances`): `mpc` = `MPC_Roam_World`; `textures` = import `Content/Forza/Textures/Source/**` into
`/Game/Forza/Textures/<Group>/T_<name>_BC|N|ORM|D` (re-imports only when the source changed, `force` overrides); `masters` = every master of the modules listed in
`materials_masters.MODULES`; `instances` = every `MI_*` registered by `materials_instances*.py` (+ writes the slot map); `testsheet=a,b` = renders stations.
Log markers: `MAT_BUILD`, `MAT_ERR`, `MAT_SUMMARY`, `MAT_SHEET_SHOT`.

Files: `materials_lib.py` (node-graph DSL over MaterialEditingLibrary: `Graph`, `E` expression handle with operators, `custom()` HLSL nodes, `new_material`, `new_instance`),
`materials_masters.py` (registry + shared HLSL / helpers), `materials_m_road.py`, `materials_m_surface.py` (building, glass, roadside, billboard), `materials_m_nature.py`,
`materials_m_fx.py` (water, particles, skid decal, rain-on-lens), `materials_instances.py` (registry; nature) + `_fx.py` + `_surface.py`, `materials_textures.py`,
`materials_mpc.py`, `materials_testsheet*.py` + `materials_testmesh*.py`, `materials_check_slots.py`, job server: `materials_server.py`, `materials_job.ps1`, `ue_job.ps1`,
`job_drop.ps1`, `_server_lib.ps1`.

## 2. Editor access (job server)
`ue_job.ps1 <script.py> -Args0 "..."` submits a python script to a persistent editor ("job server": `materials_server.py` inside `UnrealEditor-Cmd`), prints the log lines
of the job and `---- job result ----`.  The server starts on demand (an editor start costs 3-8 minutes), serves jobs of all agents in file-name order, exits after
`Saved/MatJobs/idle_limit_s` (300) seconds without jobs, and yields to C++ builds (`build_editor.ps1`) and to `ue_cmd.ps1` runs through `Saved/MatJobs/quit` /
`build_lock`.  Jobs run on the game thread, `JOB_ARGS` (string) is injected, a job must never call `QUIT_EDITOR`.  `job_drop.ps1` only drops a job into a server that is
already running (no start logic; read the result in `Tools/Logs/matserver.log`, or `matserver-backup-*.log` when the server restarted).  A second start request while one is
queued behind another Unreal run is ignored (`_server_lib.ps1: Test-JobServerStarting`).

Test sheet etiquette (several agents share one editor): sheet jobs are asynchronous (they keep shooting after the job returned), so a sheet holds the server with
`Saved/MatJobs/hold_sheet` (released when the last queued sheet is done) and a second sheet job that arrives meanwhile is queued by `materials_testsheet.run`; always start sheets through
`materials_sheet.py` (or the `testsheet` step); the exposure of a scene capture is fixed (1.0): the sheet scales the sun instead (`sun_lux`, default 8 lux; night shots use `sun_lux` 0.02 -
a shot-level `ev` override persists into the following shots).  Walls of the test meshes are one-sided: rotate them to face the camera.

## 3. Engine quirks found while building these (5.8.2)
* `MaterialEditingLibrary.delete_all_material_expressions` removes only about half of the expressions per call (130 -> 64 -> 31 -> ...): every "wipe and rebuild" left stale
  orphan nodes with duplicate parameter names.  `materials_lib.new_material` now repeats the call until `get_num_material_expressions() == 0`.  Never delete + recreate a master
  that has instances (the editor crashed in MaterialEditor.dll when it recompiled the new asset).
* `set_material_instance_*_parameter_value` return False although the value is applied: `new_instance` verifies by reading back.
* Single Layer Water needs `blend_mode = Opaque` (no Opacity pin); its output node pins are named `Scattering Coefficients`, `Absorption Coefficients`, `Phase G`.
* `VectorParameter` / `ParticleColor` main output is float3: the alpha is the separate output `"A"` (`tint["A"]`, not `.a`).  `E.g` is the Graph, use `E.g_` for green.
* Custom (HLSL) nodes: additional outputs are plain variables; the main output is the `return` value (declare it yourself, e.g. `float3 Normal = ...`).
* UE flips V when it imports an FBX (every UV channel arrives as `(u, 1 - v)`).  The road master therefore reads `s = 1 - UV1.y`, `lane width = 1 - UV2.y`, `zone = 1 - UV3.y`
  (parameter `UVFlipV` = 1; `d`, `P`, `median` live in U and are untouched).  Found with the test strips: without the un-flip `zone` read 0, so no paint was drawn and the dirt road
  looked like plain dirt.  Anything that writes more data into the V of a UV channel must expect the flip.
* Substrate is on: the masters use the legacy pins and compile / convert fine (every master reports `compiled OK` with its instruction count).

## 4. MPC_Roam_World  (`/Game/Forza/Materials/MPC_Roam_World`)
Scalars (default): `Wetness` 0 (surface wetness), `PuddleAmount` 0 (roads use `Wetness^2*0.5` when it stays 0), `RainIntensity` 0 (ripples, water, lens drops),
`SnowAmount` 0, `DustAmount` 0, `TimeOfDay` 12 (hour 0..24), `NightFactor` -1 (negative = derive from `TimeOfDay`: dusk 18.5-21 h, dawn 4.5-7 h), `WindStrength` 0.35,
`WindSpeed` 5 (m/s), `FoliageSeason` 0, `Headlights` 1 (0..1 player headlights on: scales the retro-reflective response of signs / reflectors at night; the vehicle visuals may write it), `GlobalTime` 0.  Vectors: `WindDirection` (xyz unit vector), `SeasonTint` (rgb multiplier).
Writer: the weather / sky manager (`UKismetMaterialLibrary::SetScalarParameterValue(World, MPC, "Wetness", v)`); the defaults are a dry, calm day so everything looks right without a writer.

## 5. Textures
`materials_textures.py` imports the 57 procedural sets (`Tools/textures/generate_all.py`): BC = sRGB + mips + streaming (no virtual textures); N = normal-map compression, sRGB off,
DirectX green-down as generated (no flip); ORM = linear BC7 (R=AO G=roughness B=metallic); masked atlases keep alpha with alpha-coverage in the mips; sprites / decals are clamped.
Groups: Terrain, Road, Building, Nature, FX, Roadside (billboard ads).  Tile sizes in metres: `Content/Forza/Textures/Source/manifest.json` (`tile_metres`).

## 6. M_Roam_Road  (`/Game/Forza/Materials/M_Roam_Road`, Nanite-compatible, opaque)

### mesh contract (R's road chunks, `Exports/Roads/chunks.json` -> `uv_channels`, `Docs/Tech/ROADS_PIPELINE.md`)
| UV | meaning |
|---|---|
| UV1 = (d, s) | lateral metres from the CENTRE LINE (right = +) and arc length in metres (continuous along a road): all texture tiling, paint, wheel tracks and ripples are metric |
| UV2 = (P, lw) | paved (carriageway) half width and lane width in metres. `P = 0` (junction pads, structures) = no paint |
| UV3 = (median, zone) | median width in metres; zone 1.0 carriageway, 0.66 shoulder, 0.5 kerb, 0.33 barrier, 0 skirt (paint mask and shoulder blend) |

Paint is procedural: edge lines at `|d| = P - EdgeLineInset - width/2`, dashed lane dividers at `|d| = median/2 + k*lw` (k = 1 .. lanes-per-direction-1), centre line (dashed /
solid / double, `CentreStyle`) when there is no median, wear mask from noise, wet paint darker, puddles over everything.  Wheel paths (oily, polished) follow the lane geometry, shoulders
blend towards `ShoulderTint` (and optionally a second texture set).  Wetness darkens + lowers roughness, puddles from noise (`PuddleAmount`), rain ripples (normal) when
`RainIntensity > 0`, snow whitens shoulders but keeps the lanes clear (`SnowRoadClear`), dust tints dry roads.

### parameters
Surface: `TileMetres`, `AcrossMode` (1 = texture spans the paved width, mirrored outside: dirt ruts), `AntiTileAmount` (rotated second sample, static switch `AntiTile`), `BaseTint`,
`NormalStrength`, `RoughnessScale`, `RoughnessBias`, `AOStrength`, `MacroVariation`, `SpecularBase`, `WheelTrackDarkening`, `WheelTrackSpacing`.
Shoulder: `ShoulderSetMix` + static switch `UseShoulderSet` (+ textures `ShoulderBaseColorTex/ShoulderNormalTex/ShoulderORMTex`), `ShoulderTint`, `ShoulderTintAmount`.
Markings: `MarkingsEnabled`, `FallbackLaneWidth`, `CentreStyle` (0 dashed, 1 solid, 2 double, 3 none), `EdgeLineWidth`, `EdgeLineInset`, `CentreLineWidth`, `LaneLineWidth`, `DashLength`,
`DashGap`, `DashPhase`, `DoubleLineGap`, `MarkingWear`, `MarkingRoughness`, `MarkingColor`, `CentreLineColor`.
Weather: `WetnessResponse`, `PuddleResponse`, `RippleStrength`, `SnowResponse`, `SnowRoadClear`, `DustResponse`, `SnowColor`, `DustColor`.
Textures: `BaseColorTex`, `NormalTex`, `ORMTex`, `NoiseTex` (tileable perlin).

### instances  (folder `/Game/Forza/Materials/Roads/`: the names R's `import_roads.py` looks for)
| slot (Blender) | instance | what |
|---|---|---|
| M_Road_Asphalt | MI_Road_Asphalt | asphalt, dashed centre line |
| - | MI_Road_AsphaltNew / MI_Road_AsphaltWorn / MI_Road_AsphaltMountain | clean highway / cracked worn / worn with solid centre line (assign per road class if wanted) |
| M_Road_Concrete | MI_Road_Concrete | concrete slabs, no paint |
| M_Road_Dirt | MI_Road_Dirt | rut texture across the paved width (`AcrossMode`), plain dirt on the shoulders |
| M_Road_Gravel | MI_Road_Gravel | gravel |
| M_Road_Marking | MI_Road_Marking | solid white paint strips (M_Roam_Roadside paint) |
| M_Curb | MI_Curb | concrete kerb (`UseUV1`) |
| M_Bridge_Concrete / M_Bridge_Steel | MI_Bridge_Concrete / MI_Bridge_Steel | deck, piers, abutments / girders, cables (`UseUV1`) |
| M_Tunnel_Wall / M_Tunnel_Light | MI_Tunnel_Wall / MI_Tunnel_Light | liner (`UseUV1`) / always-on emissive lamp strip |

## 7. M_Roam_Building  (generic textured solid, Nanite-compatible)
Mapping: UV0 metric (default, `TileMetres` metres per texture tile; roadside kit + buildings), static switch `UseUV1` (road-chunk structures: UV1 is metric), static switch
`Triplanar` (world-aligned, `BlendSharpness`; the world normal is converted to tangent space with a Transform node).  `SwapUV` rotates the texture 90 degrees.
Parameters: `TileMetres`, `SwapUV`, `BaseTint`, `VertexColorTint` (0..1; the kits ship a neutral-white `Col` set carrying per-part tint / dirt), `NormalStrength`, `RoughnessScale`,
`RoughnessBias`, `MetallicScale`, `MetallicBias`, `AOStrength`, `MacroVariation` (world-space noise, hides tiling), `SpecularBase`, `BlendSharpness`, weather `WetnessResponse` /
`SnowResponse` (up-facing surfaces) / `DustResponse`, `SnowColor`, `DustColor`; textures `BaseColorTex`, `NormalTex`, `ORMTex`.
Instances: `MI_Bld_Plaster, PlasterOchre, Brick, Stone, Concrete, Wood, WoodDark, RoofTile, RoofSlate, Corrugated, MetalPainted` (slots `M_Bld_*`) and the textured roadside slots
(`MI_RS_Concrete, ConcreteDark, Wood, WoodPale, Stone, Mortar, Hay, Soil, Rust`), tinted so that the mean texture colour equals the Blender kit colour.

## 8. M_Roam_Glass_Building  (translucent, surface lighting, two sided)
Window grid from UV0 metres (`WindowWidth`, `WindowHeight`, `FrameWidth`), per-window random lit state (`LitFraction`, `LitIntensity`, warm / cool / TV colours `LitColorWarm/Cool`)
that switches on at night (MPC `TimeOfDay` / `NightFactor`), fresnel opacity (`OpacityFacing`, `OpacityGrazing`, `FresnelExponent`), `GlassColor`, `GlassRoughness`, dirt overlay
(`glass_dirt_overlay`, `DirtAmount`, `DirtTileMetres`), `WindowGridEnabled` (0 = plain glass, e.g. the bus-stop shelter).
Instances: `MI_Bld_Glass`, `MI_Bld_Glass_Shop`, `MI_RS_Glass`, `MI_Glass_Tinted`.

## 9. M_Roam_Roadside  (flat colour paint / plastic / metal / signs / reflectors / lens)
Parameters: `BaseColor`, `Metallic`, `Roughness`, `VertexColorTint`, `ColorBreakup`, `RoughnessBreakup` (world-space noise), `SpecularBase`, `WetnessResponse`, `SnowResponse`; night:
`RetroReflective` (retro-reflective boost: night x MPC `Headlights` x head-on angle^3 x squared distance falloff over `RetroRangeMetres`), `EmissionMode` (0 off, 1 always, 2 night only), `EmissiveColor`,
`EmissiveIntensity`.  Instances: one `MI_RS_<name>` per `M_RS_*` slot of `Exports/Roadside` (colour / metallic / roughness / emission are the Blender kit values of
`Tools/blender/roadside/rs_lib.py`), `MI_Metal_Galv`, `MI_Sign_*`.  `M_Roam_Billboard`: `AdTex` (UV 0..1 over the face), `NightGlow`; instances `MI_RS_BillboardFace`, `_B`, `_C` = ads A / B / C.

## 10. Water, particles, decals, post-process (`materials_m_fx.py`)
Described in `MATERIALS_nature_fx.md`.  Additionally `M_Roam_PP_RainOverlay` (post-process, after tonemapping): refracting rain drops with trails on the lens, density from MPC
`RainIntensity` (parameters `DropCells`, `RefractionStrength`, `RainScale`); add it to a post-process volume / camera `PostProcessSettings.WeightedBlendables` with weight 1.

## 11. Verification (06:37, job-server build + test-sheet screenshots in `Saved/MatShots/`)
Full default build (`mpc textures masters instances`): textures 171 files present / 0 re-imported (idempotent), **18 masters compile OK**, **163 instances, 0 failures, no parameter warnings**; all 57 non-car Blender slot names
of `Exports/**/*.json` map to an instance (`materials_check_slots.py`).  Screenshots that were looked at: `road_reg_close` (edge lines + dashed centre line), `road_hwy_close` (2+2 lanes, dashed dividers, no centre line
on the median), `road_dirt_close` (ruts + grass edges), `road_wet_rain` (puddles reflecting the sky, ripples), `road_snow` (shoulders white, lanes cleared), `road_dust`, `road_gravel_concrete`, `bld_day` (plaster / brick / stone /
concrete / roofs), `bld_windows_day` + `bld_windows_night` (glass grid, lit windows), `struct_day` (kerb, bridge concrete, bridge steel, tunnel wall, tunnel lamp), `struct_triplanar`, `roadside_day` / `roadside_night`
(all `MI_RS_*` on spheres, reflectors and lamp lens glow at night).  Not exercised in a screenshot: `M_Roam_Billboard`, `M_Roam_PP_RainOverlay` (compile only), water in the sheet (M-A's `water` station), junction pad.

## 12. Known limitations
* Road paint has no arrows / zebra crossings / stop lines (stop lines are geometry in the `M_Road_Marking` slot); `road_markings_atlas` is imported but not used by the master.
* `M_Roam_Glass_Building` is translucent (not Nanite); building kits with thousands of windows should use one merged window mesh.
* The retro-reflective response is an approximation (night + view angle + distance), not tied to the actual headlight cones.
* Material shader compile happens inside `recompile_material`; the first editor load of a fresh derived-data cache compiles every permutation (minutes).

## 12. Test sheet notes (scene capture in the headless editor; added by the nature author)
`Tools/ue/materials_sheet.py -Args0 "<stations>"` (stations: `road`, `trees`, `ground`, `treemesh`, `evcal`, plus the surface ones) fills a world with the test meshes and writes
`Saved/MatShots/<shot>.png`.  What had to be learned the hard way:
* A `SceneCapture2D` renders with **exposure 1.0** unless the capture component has `show_flag_settings = [EyeAdaptation on]` *and* `always_persist_rendering_state = True`; with
  both set, the normal eye adaptation works (auto exposure) and per-shot `"ev": <EV100>` pins it (`auto_exposure_min/max_brightness` = ev / ev + 0.01 in this project's
  extended luminance range; higher EV = darker; physical sun 110000 lux ~ EV 14-15).  `AEM_MANUAL` + bias, and min == max, had no effect.
* A capture gets no sky-light / Lumen indirect light (shadowed sides were pitch black): the sheet adds a weak shadowless blue directional "fill" light opposite to the sun.
* `EditorLoadingAndSavingUtils.new_blank_map` called repeatedly crashed the editor (`EXCEPTION_ACCESS_VIOLATION` in `python311.dll` right after `CleanupWorld`); the sheet now reuses
  the editor world and only destroys the actors tagged `matsheet`.  The world object returned by `new_blank_map` can be stale: use `UnrealEditorSubsystem.get_editor_world()`.
* The capture is asynchronous (tick callbacks, ~40 frames per shot): `materials_sheet.py` writes `Saved/MatJobs/hold_sheet` so the job server neither quits nor starts another
  job (which could replace the world) until `MAT_SHEET_DONE`; a crashed server leaves the file behind (delete it; it also expires after 20 minutes).
* `unreal.RenderingLibrary.export_render_target` writes OpenEXR for float render targets (even with a `.png` name): the sheet uses `RTF_RGBA8`.
* Tree check on real meshes: station `treemesh` imports `Exports/Nature/Trees/tree_*_a.fbx` and assigns the `MI_Tree_*` instances by slot name (`materials_slot_map.json`).
