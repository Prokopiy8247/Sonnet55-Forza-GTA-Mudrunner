# WORLD_BUILD - how the open world of Roamline is built in Unreal (UE 5.8.2)

Owner: world-builder agent F1 (two instances worked on it, see `Tools/ue/F1_COORD.md`). Everything here is reproducible from the generated data:
`Tools/world/build_world.py` -> `Content/Forza/World/Source/*` -> `Tools/ue/world_build.py` (editor python) + `Source/Sonnet55ForzaEditor/RoamWorldBuilder.*` (editor C++).

## 1. Files

| What | Where |
|---|---|
| Editor C++ (callable from python as `unreal.RoamWorldBuilder.*`) | `Source/Sonnet55ForzaEditor/RoamWorldBuilder.h/.cpp` |
| Orchestrator, step flags | `Tools/ue/world_build.py` (+ `world_lib.py` constants/helpers) |
| Landscape material builder | `Tools/ue/world_material.py` -> `/Game/Forza/Materials/Landscape/M_Roam_Landscape` |
| Sea | `Tools/ue/world_water.py` -> `M_Roam_Sea` + water plane |
| Region rectangles (input of the world definition) | `Tools/ue/world_regions_gen.py` -> `Tools/ue/world_regions.json` |
| **Whole world after a generator run (one command)** | `Tools/ue/world_rebuild.ps1` |
| Data re-import only (regions + DA_* + check) | `Tools/ue/world_data.ps1` |
| Read-only checks (assets, landscape-vs-road alignment, wheel-channel traces); also the `verify` step of `world_build.py` | `Tools/ue/world_verify.py` |
| Offline sanity check of the raw generator files (orientation, weights, road bed vs terrain), plain numpy | `Tools/ue/world_check_offline.py` |
| Game tour: teleport + screenshots + frame chart | `Tools/ue/world_tour.ps1` |
| Experimental SceneCapture screenshots from the job server (comes out white: see section 9) | `Tools/ue/world_shots.py` |
| How the two F1 agent instances shared the work (history) | `Tools/ue/F1_COORD.md` |
| Output assets | `/Game/Forza/Maps/L_Main` (+ `__ExternalActors__`), `/Game/Forza/World/Landscape/LI_*`, `/Game/Forza/Materials/Physical/PM_Roam_*`, `/Game/Forza/Data/DA_RoadNetwork`, `DA_WorldDefinition` |
| Raw generator output (git-ignored) | `Content/Forza/World/Source/` (`heightmap_4033.r16`, `layer_<Name>.r8` x 8, `roads.json`, `world_meta.json`, density maps, `region_id.r8`, `slope.r8`) |

## 2. Coordinates and landscape layout

* 1 uu = 1 cm, +X north, +Y east, +Z up, the world origin is the centre of the map. The source grid is 4033 x 4033 vertices at 1 m (row = +Y, column = +X, no flips).
* Heightmap encoding: uint16 little endian, `Z_m = (h - 32768) * 300 / 128 / 100`, i.e. landscape `Scale = (100, 100, 300)`, actor Z = 0, sea level 0 m, range -768 .. +768 m.
* UE landscape sizes must be `components * 254 + 1` (127-quad sections, 2 x 2 sections per component): 4033 is padded (edge replication, 16 vertices each side) to **4065 x 4065 = 16 x 16 components**. The actor is placed at `X = Y = -203200 cm` so that the source centre vertex (2016, 2016) is the world origin.
* World Partition (5.8 runtime hash set): landscape split into 16 streaming proxies of 4 x 4 components (+ the main landscape actor); proxies are *not* spatially loaded (the terrain is always resident), everything else streams: main grid cell 256 m, loading range 1000 m (about 14 s of look-ahead at 250 km/h). The values live in `ConfigureWorldPartition(World, 25600, 100000, true)`; the default of 5.8 (128 m cells / 256 m range) is far too small for driving.
* Collision: landscape + proxies use the `RoamWorldStatic` profile (blocks `Roam_Wheel`, `Roam_Camera`, `Roam_Vehicle`, `Roam_Traffic`); `DefaultPhysMaterial` = `PM_Roam_Asphalt`, each weight layer has its own physical material (below).

## 3. Pipeline (one script, step flags)

```powershell
# ONE COMMAND (regions json -> all steps -> verify; dedicated editor process, ~13 min incl. 2-5 min editor start):
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_rebuild.ps1
# single steps are fast in the shared editor job server (e.g. after editing the landscape material: 5 s)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_build.py -TimeoutSec 7200 -Args0 "material"
# same thing standalone with the environment variable
$env:ROAM_WORLD_STEPS = "phys,layers,material,data,map,landscape,wp,lighting,ocean,playerstart,roads,nanite,save,verify"
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/world_build.py -LogName world_build -TimeoutSec 7200
```

Do NOT run the heavy steps (`map`, `landscape`, `nanite`, `save`, or anything that loads L_Main) inside the shared job server while other agents run asynchronous capture jobs there: loading a map under their scripts crashed the server once (python311 access violation, 2026-10-17 05:15). The material step does not touch the map and is safe.

| step | what it does |
|---|---|
| `phys` | `PM_Roam_Asphalt/Concrete/Dirt/Gravel/Grass/Sand/Snow/Mud/Rock` (`UPhysicalMaterial`, friction/density, `SurfaceType1..8` = `ERoamSurface` order; `Rock` maps to the Gravel surface type) via `RoamEditorLibrary.configure_roam_physical_material` |
| `layers` | landscape layer infos `LI_Grass, LI_ForestFloor, LI_Farmland, LI_Rock, LI_Sand, LI_RedClay, LI_Snow, LI_RoadVerge` (`UE::Landscape::CreateTargetLayerInfo`, weight-blended, physical material per layer: Grass->Grass, ForestFloor/Farmland/RedClay->Dirt, Rock->Rock, Sand->Sand, Snow->Snow, RoadVerge->Gravel) |
| `material` | builds `M_Roam_Landscape` (section 5) |
| `data` | `DA_RoadNetwork` + `DA_WorldDefinition` (section 4) |
| `map` | **deletes and recreates** `/Game/Forza/Maps/L_Main` (World Partition, `LevelEditorSubsystem.new_level(path, True)`, including its `__ExternalActors__`), sets the world GameMode override to `ARoamGameMode` |
| `landscape` | `RoamWorldBuilder.create_landscape_from_heightmap` (reads the raw files, pads, `ALandscape::Import`, layers, material, collision profile, proxies, Nanite flag; **landscape holes** = `hole_vertices` from `chunks.json -> landscape_hole_vertices` written as weight 255 on the visibility layer, option `holes=0` skips them) |
| `wp` | `configure_world_partition` (cell 256 m, range 1000 m) |
| `lighting` | basic lighting actors tagged `RoamBasicLighting`: sun (movable, atmosphere light 0), sky atmosphere, sky light (real-time capture), exponential height fog with volumetric fog - the sky manager of the weather agent replaces/drives them later |
| `ocean` | the sea at z = 0 (section 6) |
| `playerstart` | `PlayerStart` on the right lane of `HWY_EAST` 220 m after the Crossroads, heading along the road, 150 cm above the road (the game mode snaps it to the ground with a `Roam_Wheel` trace) |
| `roads` | imports every chunk of `Exports/Roads/chunks.json` (`Tools/ue/import_roads.py`, section 10): Nanite static meshes with a full-resolution fallback, complex-as-simple collision, `MI_*` with `PM_Roam_*`, one `StaticMeshActor` per chunk (not spatially loaded); stale chunk actors / meshes not in the manifest are deleted. Options `roads_only=<ids>`, `roads_refresh=1` (re-apply mesh settings without re-importing), `roads_no_actors=1` |
| `nanite` | `build_landscape_data(world, grass, physmat, nanite)`: Nanite landscape meshes, physical-material data and grass maps (slow, synchronous) |
| `save` | `save_dirty_packages` + `save_map` |
| `verify` | `world_verify.py`: DA assets load, POI list (duplicate ids are a failure), default spawn road ids, landscape height vs road bed Z and a wheel-channel line trace at 100 road points |
| `load` | (not in the default list) loads L_Main first - needed for `nanite`/`save`/`verify` in a fresh editor |

Options: `ROAM_WORLD_MAP` (default `/Game/Forza/Maps/L_Main`), `ROAM_WORLD_CROP="x,y,n"` (build only an n-vertex window of the source, e.g. `1762,1762,509` = 2 x 2 components, 7 s: the proving ground used for `/Game/Forza/Maps/L_WorldTest`), `ROAM_WORLD_NANITE=0`.
Log markers: `ROAM_WORLD ...` (python), `ROAM_LANDSCAPE_*`, `ROAM_ROADNET`, `ROAM_WORLDDEF`, `ROAM_WP_CONFIG` (C++), `ROAM_VERIFY ...` (checks).

**Re-running when the world generator produced new data** (all steps are idempotent): `Tools/ue/world_data.ps1` re-imports the data assets only (regions json regenerated first); for terrain changes run `map landscape wp lighting ocean playerstart nanite save` (the `map` step starts from an empty L_Main, the landscape import takes ~1 min). `phys layers material` only need a re-run when their definitions change.

## 4. Data assets

* `CreateRoadNetworkAsset(roads.json, /Game/Forza/Data/DA_RoadNetwork)`: one `FRoamRoad` per **edge** of the junction graph (`roads.json` `edges`); a road with a single edge keeps its id (`HWY_EAST`, so `DefaultSpawnRoadIds` works), the others are `<ROAD>#<k>`. Samples every 4 m (exact start/end), flags mapped to `ERoamRoadSection` (bridge -> Bridge + Guardrail, tunnel, junction; hairpins on mountain roads -> Guardrail), lane convention = ARCHITECTURE section 10 deviation 5 (positive lane indices on the right of the road direction, right-hand traffic), `FRoamJunction` per node with arm priorities from the connection control (priority/free/yield/stop), spatial grid rebuilt (`BuildSpatialIndex`) and `Validate()` run (the report is printed). `RoamSettings.DefaultSpawnRoadIds` lists road ids; ids that are only routes of `roads.json` (`LOOP`) are skipped by the game mode.
* `CreateWorldDefinitionAsset(world_meta.json, roads.json, Tools/ue/world_regions.json, /Game/Forza/Data/DA_WorldDefinition)`: regions are axis aligned rectangles with a priority (several rectangles per region id, the first one is the teleport target), points of interest come from `world_meta.json` `sites` snapped to the nearest road (`site_kind_to_poi_type`) plus the start of every road; default spawn POI `loop_start`.
* `world_regions_gen.py` approximates the organic `region_id.r8` with <= 16 prioritised rectangles (greedy 2-D Kadane search on a 64 m grid, deterministic; accuracy is printed: 98.6 % of the 64 m cells, 97.6 % of the 1 m vertices for the first generator drop). Hand-authored: names, subtitles, climate zones, traffic scale, POI kinds. Re-run it whenever `region_id.r8` changes (`world_data.ps1` does).

## 5. Landscape material `M_Roam_Landscape`

See the header of `Tools/ue/world_material.py` (design notes live next to the code so that they stay true). Summary: 8 weight layers (landscape layer sample nodes named like the layers of `world_meta.json`), all UVs from the world position (tile sizes from the texture manifest, no mesh UVs -> the same material works for every proxy and for Nanite, nothing stretches), anti-tiling with a second rotated 5.3x larger colour sample + three tileable noise scales (30 / 140 / 900 m), height-blended transitions (ORM AO as the height proxy), steep ground switches to a triplanar cliff rock, wetness from `MPC_Roam_World`. One HLSL custom node does the shading; the textures are the procedural sets imported by the materials agent into `/Game/Forza/Textures/Terrain`.

## 6. Sea

`Tools/ue/world_water.py`: one static plane (60 x 60 km, z = 0) with the shared `/Game/Forza/Materials/M_Roam_Water_Simple` of the materials agent (`M_Roam_Sea`, built by `world_water.py`, is only the fallback when that material is missing). The heightmap already contains the sea floor, so the shore gradient comes from the water depth. The experimental Water plugin (`WaterZone` + `WaterBodyOcean`) can be tried with `ROAM_WORLD_OCEAN=plugin`; the plane is the default because it is robust headless and needs no landscape carving (Water is Experimental in 5.8).

## 7. Verification tools

* `world_verify.py` (editor, read-only, also the `verify` step): `data` (assets load, counts, POI list, duplicate POI ids, default spawn road), `map` (landscape stats), `ground` (N points per road class: landscape height vs road bed Z of `roads.json` and a wheel-channel line trace through the editor world).
* `world_check_offline.py` (plain python, 6 s): raw file sizes, weight maps sum to 255, terrain height under every road sample vs the road z (orientation/encoding check), sea fraction.
* `world_tour.ps1` (real game run, 1920x1080, real RHI): `roam tp <poi>` + `HighResShot` per stop, optional frame chart while driving; screenshots are collected in `Saved/Screenshots/world_tour/<LogName>/NN_<poi>.png` (only the last N files of the screenshot folder are taken, other agents write there too). Default stops: `loop_start, highway_plateau, pass_switchbacks, great_bay_bridge, crossroads, summit_viewpoint, tidewick`. `-DriveSeconds 25` adds a driven frame-time chart (`StartFPSChart`/`StopFPSChart`, summary in the log).
  **If the terrain (and the cars) show the engine's checkerboard `WorldGridMaterial`, a material failed to compile**: look for `Failed to compile Material ... Default Material will be used in game` in the log. The cause found here: `CollectionParameter has invalid parameter None` - the materials agent rebuilt `MPC_Roam_World` (new parameter GUIDs) after `M_Roam_Landscape` had been compiled; fix = re-run `ue_job.ps1 Tools/ue/world_build.py -Args0 material` (the `material` step now stops with an error when the material has compile errors).

## 8. Measured results (2026-10-17, RTX 5070, Ryzen 7 5700X3D, machine shared with 4 other agents)

| Item | Result |
|---|---|
| Landscape | 4065 x 4065 vertices, 16 x 16 components of 254 quads, 17 actors (landscape + 16 streaming proxies), padding 16 + 16 vertices, 8 weight layers |
| Import (`create_landscape_from_heightmap`) | read 0.2 s + import 58-60 s (50 s in a warm job server) |
| Steps (standalone rebuild `world_rebuild1`) | phys 0.5 s, layers < 0.1 s, material 7 s, data 1.1 s, map 9 s, landscape 61 s, wp/lighting/ocean/playerstart < 1 s, nanite 382 s (cold derived-data cache; 31 s when cached), save 44 s (the very first save of the 17 new packages took 354 s), verify < 1 s; **whole rebuild 768 s wall time including the editor start** (2-8 min depending on machine load) |
| Disk | `L_Main` external actors 25 files 727 MB (Nanite meshes included), `L_Main.umap` 13 KB, `DA_RoadNetwork` 3.3 MB, `DA_WorldDefinition` 31 KB, `M_Roam_Landscape` 168 KB; raw generator source 246 MB (git-ignored) |
| Landscape material | 0 compile errors, 320 pixel-shader instructions, 53 texture samples, 2 samplers |
| Data (drop of 05:21) | `DA_RoadNetwork` 81 edge roads, 61 junctions, 11 932 samples, 47.8 km, `Validate()` ok; `DA_WorldDefinition` 16 region rectangles (5 regions), 45 POIs, default spawn POI `loop_start` |
| Game run on L_Main (1920x1080, Development, Lumen + VSM + Nanite, 1 car, 25 s driving) | **127-130 fps average** (3214-3278 frames), GPU 4.9-5.2 ms, render thread 3.6 ms, game thread 1.9 ms, 0 % of syncs missed at the 30/60/120 fps targets, 1 hitch of 0.32 s |
| Spawn / teleports | spawn through the world POI `loop_start` (`ROAM_GROUND_DROP` on the landscape proxy); 16 `tp` stops (loop_start, crossroads, highway_plateau, pass_switchbacks, great_bay_bridge, summit_viewpoint, tidewick, greenvale, farm_b, sunset_beach, ...) all dropped onto the terrain, none fell through |
| Wheel-channel traces (`world_verify ground`) | 100 of 100 hit the landscape (all road classes) |
| Not measured | editor peak memory during the Nanite build; frame rate with traffic / vegetation / road meshes (not built yet) |

## 9. Known issues / open points (honest list)

1. **(RESOLVED 2026-10-17, section 10: the final data is built, `world_verify ground` reports 0.13 m)** **The generator outputs were still changing while this was built.** L_Main contains the terrain of the 03:57 drop, `DA_RoadNetwork`/`DA_WorldDefinition` the roads of 05:21: `world_verify ground` therefore reports the landscape up to 174 m off the road bed (the `verify` step fails on purpose, it is the gate). Re-run `Tools/ue/world_rebuild.ps1` on the final data (13 min); the check must then report < 1 m (`world_check_offline.py` does the same test in 6 s without Unreal).
2. 16-bit heightmap terracing: on very gentle slopes (beaches) the 2.34 cm height steps show as long light/dark stripes parallel to the contour lines. The material flattens the shading normal for ground flatter than ~2 degrees (fades out at 5.5), which helps only partly. The proper fix is in the generator: dither the quantisation (blue noise, +-0.5 LSB) or use a smaller Z range / scale.
3. Cliff texture repetition (one 8 m tile of strata + cracks repeated like a plaid on far cliffs): the triplanar cliff UVs have a slow analytic domain warp and a sharper planar blend; judge again on the final terrain.
4. `tp <region>` goes to the centre of the region's first rectangle, which can be a mountain flank (a car on a cliff in the Greenvale shot): use `tp <poi>`. `RoamWorldDefinition::ResolveTeleportTarget` was fixed (first rectangle per region only, an exact POI match beats a region of the same name) - the only change made in the runtime module.
5. `RoamSettings.DefaultSpawnRoadIds` (`LOOP`, `HWY_EAST`) are no longer road ids once `HWY_EAST` is split at a junction (`HWY_EAST#0`, `#1`) and `LOOP` is a route, not a road: the game still spawns correctly through the default spawn POI `loop_start`. Update the ini if a road-based spawn is wanted.
6. Grass maps: `BuildGrassMapsNowForComponents() took too long` (warning of one build); no landscape grass types are assigned yet (vegetation is a later wave), so nothing depends on them.
7. The material samples 53 textures per pixel regardless of the layer weights; it costs well under the 5 ms frame budget measured above at 1080p. For a lower-end target branch on the layer weights with `SampleGrad` inside the custom node (not done).
8. `world_shots.py` (SceneCapture2D in the job server) renders white in `L_Main` (fixed EV100 did not help); the game tour is the supported way to look at the world. The job server also crashed once when a map was loaded under another agent's asynchronous job (section 3).
9. **(PATCHED 2026-10-17: `materials_mpc.py` keeps existing parameters and their GUIDs; all 41 master materials recompile with 0 errors, `Tools/ue/world_matcheck.py` re-checks that in 7 s)** **`M_Roam_Landscape` reads `Wetness` from `MPC_Roam_World`**. Whenever the materials agent rebuilds that collection (`materials_mpc.py` / `materials_build.py mpc`) the parameter GUIDs change and every material that references it (this one, the road/car materials) stops compiling until it is rebuilt: the world then renders as the checkerboard. Re-run the `material` step afterwards (5-10 s in the job server); ideally `materials_mpc.py` should keep the existing GUIDs.
10. One standalone `world_build.py` run ended with exit code 0xC0000005 after `LogExit: Exiting` (shutdown crash of the commandlet host, results had been saved); later runs exited 0.

## 10. Final-data rebuild, landscape holes, road chunks (W1, 2026-10-17)

Data: final generator drop (heightmap / layers / roads.json of 08:19) and the 217-chunk road manifest (`Exports/Roads/chunks.json`, 498 181 triangles).

**Commands used** (shared job server, `Tools/ue/ue_job.ps1 Tools/ue/world_build.py -Args0 "<steps>"`): `phys layers material data map landscape wp lighting ocean playerstart nanite save` (7.5 min: landscape 51 s, Nanite 308 s on a cold cache, save 40 s), then `load roads save` (217 chunks, 707 s), then `load roads save roads_refresh=1 roads_no_actors=1` (99 s, Nanite full-resolution fallback, see below). `world_rebuild.ps1` now includes `roads` (before `nanite`) in its default step list.

| Item | Result |
|---|---|
| `DA_RoadNetwork` | 72 edge roads, 57 junctions, 11 444 samples, 45.7 km, `Validate()` ok (3.0 MB) |
| `DA_WorldDefinition` | 16 region rectangles, 46 POIs (23 world sites snapped to roads, 21 road POIs incl. the new `desc_tunnel`), default spawn POI `loop_start` (HWY_EAST s = 220, the first segment of the LOOP route) |
| Landscape | 4065 x 4065 (16 x 16 components, 17 actors), Nanite 17/17, 8 weight layers + the visibility layer; import 49 s |
| Landscape holes | 277 source vertices of `chunks.json` (tunnel mouths + bridge-end quads) written to the visibility layer (`ROAM_LANDSCAPE_HOLES 277`). Collision: Roam_Wheel traces straight down through both tunnel mouths do not touch the Landscape (they hit the portal / tube mesh) and hit the Landscape 12 m to either side (`world_holecheck.py`); render: the mouths are open in the -game shot `desc_tunnel` (tube, lamps, exit light visible) |
| Road chunks | 217 meshes `/Game/Forza/World/Roads/Meshes/SM_<id>` (39 MB), 217 actors `Road_<id>` (folder `Roads/<Kind>/<ROAD>`, tags `RoamRoad`, `RoamDrivable`, `RoamRoadChunk:<id>`), spatially loaded = False, profile `RoamWorldStatic`, Nanite, complex-as-simple; 0 problems; no stale road assets existed in UE (nothing to delete) |
| Physical materials | `PM_Roam_*` set (override flag + material) on `MI_Road_Asphalt` / `Marking` (Asphalt), `MI_Road_Concrete` / `Curb` / `Bridge_*` / `Tunnel_*` (Concrete), `MI_Road_Dirt` (Dirt), `MI_Road_Gravel` (Gravel): a Roam_Wheel trace on complex collision returns them (histogram printed by `world_verify wheels`) |
| `L_Main` on disk | `L_Main.umap` 16 KB, external actors 242 files 704 MB |
| Terrain vs road bed (`world_verify ground`, 189 bed samples, bridge / tunnel samples excluded) | worst 0.13 m (limit 1 m) |
| Wheel probes (`world_verify wheels`: Roam_Wheel trace from 1.5 m above the right-lane centre) | 83 probes (all road classes, 42 bridge-deck samples on 12 bridges incl. Great Bay, 3 tunnel-floor samples): 0 misses, every hit is a road chunk actor (never the landscape), deck / tunnel-floor error 2-4 mm; 1 outlier (issue 11) |
| Teleports | 16 stops (`loop_start`, `crossroads`, `highway_plateau`, `pass_switchbacks`, `great_bay_bridge`, `desc_tunnel`, `highcrest_tunnel`, `summit_viewpoint`, `tidewick`, `sunset_beach`, `lighthouse`, `millbrook`, `frostholm`, `greenvale_castle_ruin`, `silverrun_stone_bridge`, `coast_road`) all landed on the ground, none fell through; the spawn (`ROAM_SPAWN_SOURCE WorldPoi`) drops onto the road mesh (`ROAM_GROUND_DROP hit=StaticMeshActor`, `Road_RC_HWY_EAST_01`) |
| Frame rate (`world_tour.ps1 -DriveSeconds 25`, 1920x1080, RTX 5070, Lumen + VSM + Nanite, 217 road actors, 1 car) | **123.9 fps average** (3134 frames / 25.3 s), GPU 6.33 ms, render thread 3.74 ms, game thread 1.97 ms, 0 % of syncs missed at 30 / 60 / 120 fps, 1 hitch of 0.45 s |
| Config | `GameDefaultMap` and `EditorStartupMap` = `/Game/Forza/Maps/L_Main` (`L_Test` stays in Content: `open L_Test`) |

**What was learned on the first run of the road importer** (it ran without API problems; the substantive findings):
* The physics triangle mesh of "use complex as simple" is cooked from the **Nanite fallback mesh**. The default fallback target (AUTO) reduced a 3 100-vertex road chunk to 326 vertices: bridge decks were missed by the wheel traces and plain roads were hit up to 2.9 m off. `import_roads.py configure_mesh` now sets `NaniteFallbackTarget.PERCENT_TRIANGLES` = 1.0 (full resolution; the whole network is 0.5 M triangles). After that every probe lands within 4 mm of the road profile.
* `MaterialInstanceConstant.phys_material` is only used when `override_phys_material` is set too; the importer sets both (the materials agent's `MI_Road_*` carried no physical material).
* The importer purges meshes / actors of chunks that are no longer in the manifest (`purge_stale`); `Exports/Roads/` still holds 24 obsolete FBX files that are not in the manifest and are not imported.
* Landscape holes through `ALandscape::Import`: the visibility layer (`ALandscapeProxy::VisibilityLayer`, `__LANDSCAPE_VISIBILITY__`) is just one more import layer; Nanite landscape meshes drop the hidden quads, the heightfield collision opens the cell owned by a vertex with weight > 170. The holes are baked at import time (to change them re-run `landscape nanite save`).

**Known issues added by this run**
10. **Tunnel portal look (cosmetic, PARTIAL):** the hole (generator rectangle 5 x 11.4 m + 0.8 m margin + one Nanite quad) is larger than the portal head-wall body: from the road the sky shows through the Landscape hole above the head-wall (a light jagged shape on the `desc_tunnel` screenshot) because the heightfield has no thickness. Fixes: a smaller hole (no margin, only the rear half of the rectangle) or a back-cap mesh behind the head-wall in the Blender road kit.
11. **Junction pad step (data):** at `X_LOOP_COAST_LOOP_SOUTH_0` the two arms meet at heights that differ by ~1 m (LOOP_COAST z 20.89 vs LOOP_SOUTH z 21.92 at 5.9 m distance in `roads.json`, a `profile.py` matter): the pad follows one of them, so a wheel probe on the other arm hits the pad 0.95 m above its profile - a bump for the car. The `wheels` check reports it (the only failure of the run).
12. The `sunset_beach` POI sits on a flat cliff-top pad above the sea, not on a beach (site snapping, data); `coast_road` is inland farmland. Use `tidewick` / `lighthouse` for coast shots.
13. Landscape holes are invisible in the editor viewport until the Nanite landscape is built (no `LandscapeVisibilityMask` node in `M_Roam_Landscape`; not needed for Nanite / the game).
