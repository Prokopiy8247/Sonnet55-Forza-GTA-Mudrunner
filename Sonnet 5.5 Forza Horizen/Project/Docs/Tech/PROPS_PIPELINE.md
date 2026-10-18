# Props pipeline (agent P1 "props"): import, placement generator, apply

Status 2026-10-17. Scope: every FBX of `Exports/Nature/Trees`, `Exports/Nature/Cover`, `Exports/Roadside`, `Exports/Settlements` (168 meshes: 21 trees + 21 far cards, 42 ground cover, 61 roadside,
23 settlement) become static meshes, a deterministic generator turns the terrain masks + road network into instance lists, and an editor job spawns them into a level.
Nothing here touches `L_Main`, `Tools/world/**`, `Source/**` or the road / car / material scripts of other agents.

| Step | File | Runs in | Output |
|---|---|---|---|
| shared catalog of the sidecar JSONs | `Tools/ue/props_catalog.py` | plain python / editor | normalised entry per asset id |
| settlement material instances | `Tools/ue/props_materials_fix.py` | editor job | `MI_Bld_{Metal,Neon,PaintBlue,PaintRed,PaintWhite,Window,Rubber}` |
| import | `Tools/ue/props_import.py` | editor job | `/Game/Forza/Props/<Category>/<AssetId>/SM_<AssetId>` (168 meshes) |
| placement generator | `Tools/ue/placement_gen.py` (+ `placement_lib.py`, `placement_settle.py`, `placement_roadside.py`) | plain python + numpy, no Unreal | `Content/Forza/World/Placements/*` (git-ignored raw data) |
| apply | `Tools/ue/props_apply.py` | editor job (or standalone for the test) | foliage instances + building actors in the open level |

## 1. Commands

```powershell
# 1) materials the settlement kit lacks (idempotent; props_import.py calls it itself when MI_Bld_Window is missing)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_materials_fix.py
# 2) import / re-import all meshes (8 min for 168 assets; resumable: -Args0 "skip_existing=1", filters: "cat=Trees,Cover only=pine,oak")
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_import.py -TimeoutSec 3600
# 3) placements (5 s; re-run after EVERY regeneration of the world data - the masks, roads and heights are read from Content/Forza/World/Source)
"W:\Blender\5.2\python\bin\python.exe" -I Tools/ue/placement_gen.py            # options: --tree-budget N --tree-step 4.0 --seed S --only trees,cover,furniture,settlements --preview 0
# 4) apply to the OPEN level (lead, on L_Main; see 4 for options)
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_apply.py -TimeoutSec 3600 -Args0 "allow_main=1 save=1"
```
If the world data is missing: `python Tools/world/build_world.py --no-previews` (raw files are git-ignored).

## 2. Import rules (`props_import.py`)

* Legacy `FbxImportUI` only (Interchange honours nothing else, see `CARS_IMPORT.md` section 3); `auto_generate_collision` must be True for the `UCX_` hulls to be kept.
* **Nanite** from the sidecar flag: ON for all opaque meshes (trees, bushes, grass cards, rocks, buildings, roadside kit), OFF for the 21 `_Far` 4-triangle billboard cards (masked) and the
  bus-stop shelter (translucent glass). Lightmap UVs off, Blender normals kept, vertex colours imported (wind R/G, AO B, tint A; checked: every tree / bush has them).
* **Collision**: UCX hulls kept where the sidecar lists `collision.hulls` (trees: trunk hull(s) only, 1-3 per tree; rocks / cliffs / cacti / buildings / signs / posts: simple),
  none where it says `none` (bushes, grass, reeds, crops, wires, delineators ...; the importer's fallback hull is removed). Complexity = USE_SIMPLE_AS_COMPLEX.
  Note: `StaticMeshEditorSubsystem.get_simple_collision_count` returns 0 for imported UCX hulls in 5.8.2, the scripts count `body_setup.agg_geom` instead.
* **Material slots -> `MI_*` by name**: `Tools/ue/materials_slot_map.json`, then `/Game/Forza/Materials/Instances|Roads/MI_<slot without M_>`. The settlement kit's six slots without instances
  (`M_Bld_Metal, Neon, PaintBlue, PaintRed, PaintWhite, Window`) are created by `props_materials_fix.py`: flat colours = `M_Roam_Roadside` (BaseColor / Metallic / Roughness / emission,
  neon emissive at night only), window = `M_Roam_Glass_Building` with the grid off and 93 % opacity (the buildings are hollow shells: a clear pane would show the back faces).
* Validation row per asset (`PROPS_VALIDATE`): bounds against the sidecar (3 %), hull count, Nanite flag, vertex colours, unbound slots. Last full run: **168 assets, 0 problems, 480 s**
  (report `Saved/PropsImport/report.json`). 14 settlement meshes carry the translucent window slot and are Nanite meshes anyway: UE renders such a mesh through its Nanite fallback
  mesh (full LOD0, no Nanite culling) - acceptable for ~100 actors; if it matters, make `MI_Bld_Window` opaque (masked) in the materials agent's master.
* Option `voxelize=1` sets Nanite shape preservation VOXELIZE on trees (Nanite Foliage is experimental in 5.8, off by default).

## 3. Placement generator (`placement_gen.py`)

Inputs `Content/Forza/World/Source/`: `heightmap_4033.r16`, `layer_{Sand,Farmland,Rock,Snow}.r8`, `density_{forest,scrub,crops}.r8`, `slope.r8`, `region_id.r8`, `world_meta.json`, `roads.json`, `river.json`.
Fully deterministic (seed 20261017, every family has its own stream; identical inputs give identical files). ~5 s, 1.5 GB RAM peak.
Order: settlements first (their footprints become an exclusion field), then trees, ground cover, roadside furniture.

Outputs `Content/Forza/World/Placements/`:
* `trees.f32`, `cover.f32`, `furniture.f32`: little-endian float32, **10 per instance**: `asset index` (into `placements_index.json -> groups.<g>.assets.list`), `x, y, z` (**cm**, UE axes: X north, Y east),
  `yaw, pitch, roll` (degrees, UE rotator; yaw = compass heading), `sx, sy, sz`. Sorted by (256 m cell, asset).
* `placements_index.json`: `groups.<g>.{file, count, record, cells{"cx,cy":[start,count]}, assets{list, counts}}`, `buildings[]` and `rotors[]` (`asset, mesh, x, y, z (cm), yaw, scale, sz?, name, group, tag`;
  rotors add `deg_per_s, axis, pivot, kind`), `summary`, `notes` (one line per settlement: what was placed / not placed and why).
* `preview_placements.png`: north-up overview (hill-shade, roads white, trees green, cover olive, furniture yellow, buildings red).

### Counts (current world data)

| Family | Instances | Notes |
|---|---|---|
| **Trees** | **60 586** (59 626 forest + 960 farm rows / orchards) | well below the 120 k cap; `--tree-step 3` roughly doubles the forest (density-limited, not budget-limited: expected 66.8 k at gain 1.0). Species by region / altitude / sand / river: oak 15.8 k, pine 15.2 k, birch 10.3 k, olive 7.8 k, poplar 6.2 k, dead 5.4 k, palm 0.9 k |
| Ground cover | 106 671 | bushes + shrubs 55 127, rocks 23 932 (slope driven, per region family), cliff pieces 1 057 (slope > 38 deg, canyon / coast), cacti 9 077 (plateau), crop rows 15 765 (field-aligned blocks, 5.2 x 2.8 m), reeds 1 345 (river banks), hay 119, logs / stumps 169, beach props 80 |
| Roadside furniture | 12 629 | guard rails 3216 (4 m segments with terminals, parapets), bridge rails 3364, delineators 2713, signs 1725 (speed, curve, hairpin, chevron, bridge, tunnel, steep descent, junction, stop / give way, direction, village, km marker), utility poles + wires 209, street lamps 41, fences / stone walls 1347, bus stops 4, billboards 4, speed cameras 2, cairns 6 |
| Settlement actors | 87 + 7 rotors | Millbrook church + 16 houses + windmill, Frostholm lodge + 6 chalets, Tidewick 14 huts / houses (pier skipped, see 5), 4 farms (farmhouse, barn, silo), 3 gas stations + 2 diners, lighthouse, castle ruin (4 towers, wall segments, arch), 6 wind turbines (+6 rotor actors), 3 beach huts |

### Rules

* **Trees**: lattice candidates (4 m, jitter) with probability = `density_forest`, faded by slope (> 28 deg), tree line (500 m), distance to the road bed edge (hard 6 m clear, thinning to 22 m), bridges (12 m), river
  channel, settlements, water (z < 0.8 m); one tree per species-specific bin (4.5 - 8 m) so canopies do not stack. Poplar / oak rows 7.5 m off farmland roads (13 m spacing, random on / off runs), olive orchards (rows) beside
  `ORCHARD_ROAD` and 60 - 120 m from every farm node.
* **Cover**: scrub density (+ forest undergrowth) bushes by region; rocks from slope + `layer_Rock` (jagged / granite in Highcrest, mesa on the plateau, coast rocks below 25 m, granite elsewhere) with 6 deg tilt;
  cliffs face downhill; cacti on the plateau; reeds along `river.json` banks (+ `streams` when present); crops in 128 m field blocks with a random row direction per block (spacing adapts to a 38 k budget);
  hay bales in crop fields; beach props in clusters on sand near Sunset Beach.
* **Roadside** (all from `roads.json` samples; side +1 = right of the direction of travel; panels face +X so `yaw = heading + 180` for the driver who reads them): rails on the outer edge of curves (R < 220 m with a drop)
  and wherever the ground falls > 2.5 m within 5 m of the shoulder, skipped in tunnels / junctions / portals, plus bridge rails on both deck edges; terminals at run ends (`end_terminal` / `end_terminal_R`);
  delineators 14 m in bends, 8 m in hairpins, 40 - 60 m on straights; speed signs at road starts / ends and every 2.2 km (nearest of 30 / 50 / 70 / 90 / 110), curve signs 75 m before bends in both directions,
  hairpin signs 90 m before, chevrons on the outside of tight bends, bridge signs 70 m, tunnel signs 110 m, steep-descent signs, give-way / stop signs 16 m before minor arms, direction signs 60 m before named
  junctions, village signs 110 m before `MILL / TIDE / FROST / LODGE`; km markers every km; utility poles every 30 m (+ `rs_utility_wire_span_30m` scaled / pitched to every span) along regional / village roads with
  farmland beside them; lamps every 36 m in villages (arm towards the road) and at gas stations / diners; wood / wire fences and stone walls along farmland roads (runs of 40 - 200 m with gaps, end posts); culvert head-walls
  on both sides of every `culverts[]` entry, oriented along the nearest brook (none exist in the current roads.json).
* **Settlements**: building footprints = sidecar bounds; a spot is accepted when the terrain range under the (2.5 m grid sampled) footprint is <= 1.3 m (hill-top landmarks up to 9 m, base sinks into the high side),
  no water, >= 4 m clear of every road bed, 1.5 m of other footprints, no river. Houses are placed in frontage rows along village streets with the door (+X) facing the road, church first, farms in a yard layout
  behind their road end, gas stations / diners at their road end facing the arriving traffic, wind turbines on the highest flat ground within 340 m of the wind-farm site (120 m spacing, 30 m from roads),
  rotors as separate actors with the pivot at the hub (`(5.6, 0, 61.85)` m turbine, `(2.8, 0, 8.15)` m windmill, rotate about local X). Nothing is flattened and no foundation blocks exist in the kit.

## 4. Apply (`props_apply.py`)

Technique (researched in `UE58_world.md` 6.2 / 9): foliage types `/Game/Forza/Props/FoliageTypes/FT_<id>` (Nanite mesh, cull distances, WPO disable distance, Nanite programmable-raster distance for leaves,
collision profile `RoamWorldStatic` only on hull assets else `NoCollision`, no HLOD, no decals) and `unreal.InstancedFoliageActor.add_instances(world, type, transforms)` in batches of 20 000.
In a World Partition level the instances are partitioned into foliage actors automatically (grid = `WorldSettings.instanced_foliage_grid_size`, default 25 600 cm). Buildings, pier, castle and landmarks are
`StaticMeshActor`s in `Roam/Props/Settlements/<Group>` (tags `RoamProp`, `RoamBuilding`), rotors in `Roam/Props/Rotors/<Group>` tagged **`RoamRotor`** (+ `RoamRotorDegPerSec=30`, `RoamRotorAxis=X`, `RoamRotorKind=turbine|windmill`),
collision off. Options (`-Args0 "key=value ..."`): `cats=trees,cover,furniture,buildings` (resumable per category; each applied category is cleared first, `clear=0` appends, `clear=all` removes every prop),
`far=1|0` (trees also get their `_Far` card, Nanite tree culled at 320 m, card visible 300 m - 1100 m), `region=x0,y0,x1,y1` (UE metres), `fraction=0.1`, `zshift=<m>`, `batch=`, `save=1`, `allow_main=1` (required on L_Main).

### Measured (standalone, throw-away blank world, headless editor, nothing saved)

| | |
|---|---|
| trees 60 586 (+ 60 586 far cards) | 1.4 - 4.0 s |
| ground cover 106 671 | 1.2 - 3.3 s |
| roadside furniture 12 629 | 0.1 - 2.5 s (first pass creates + saves the 121 foliage types, 2.5 s) |
| 87 building actors + 7 rotor actors | 0.3 s |
| **total, first pass** | **10.4 s for 179 886 placed instances = 240 472 foliage instances with far cards** (121 foliage components, 1 foliage actor in the non-partitioned test world) |

Self test (built into `testmap=1`): second pass with `clear=1` gives identical totals (idempotent), `clear=all` leaves 0 instances and 0 tagged actors, then the world is filled again.
Estimate for `L_Main`: well below the 10-minute target; the World Partition path additionally partitions every transform into the foliage grid (up to ~250 foliage actors, one file each with OFPA) and
`save=1` writes them, so plan on 1 - 3 minutes instead of 10 s. Not measured on L_Main (forbidden for this agent).

Standalone test (the only way to test safely; waits until the shared job server has finished its current job and quits):
```powershell
$env:ROAM_PROPS_TESTMAP='1'; powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/props_apply.py -LogName props_apply_test -TimeoutSec 1800
# optional: $env:ROAM_PROPS_CATS='trees'; $env:ROAM_PROPS_REGION='-1000,-1000,-800,-800'; $env:ROAM_PROPS_ZSHIFT='-100'; $env:ROAM_PROPS_FAR='0'
```
Log markers: `PROPS_APPLY`, `PROPS_APPLY SELFTEST`, `PROPS_APPLY_DONE` in `Tools/Logs/props_apply_test.log`.

## 5. Honest limits

* The generator works on the masks as they are: forest density is lower in Highcrest than the brief suggests (pines 6 k there), farmland is patchy along the roads (poles / fences only where farmland is within 12 m).
  Everything is re-runnable on the final world files (5 s); `--tree-step 3.0` doubles the forest, `--tree-budget` caps it.
* Tidewick: the heightmap has no harbour water within ~140 m of the quay node, so the pier and boats are skipped (note in `placements_index.json`); they appear automatically when the water arrives.
* Windows are near-opaque dark panes (hollow shells, no interiors), and meshes with a translucent slot are rendered through the Nanite fallback mesh (see 2).
* No LOD chain exists for non-Nanite parts (bus stop, far cards); wires are straight spans of the fixed 30 m mesh scaled in X (sag does not adapt to slope).
* Rotor spin, street lamp lights, window lighting and neon are material / component work for later; the actors are tagged for it. Tests: only the apply job on a throw-away blank world (never on L_Main).
* Do not load other levels inside the shared job server (`LevelEditorSubsystem.load_level` after `duplicate_asset` crashed it with "World Memory Leaks"): use a standalone `Tools/ue_cmd.ps1` run for tests (section 4).
