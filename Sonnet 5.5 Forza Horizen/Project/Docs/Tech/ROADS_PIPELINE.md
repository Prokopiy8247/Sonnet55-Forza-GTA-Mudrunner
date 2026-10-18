# Road geometry pipeline (roads.json -> Blender -> FBX chunks -> Unreal)

Agent R "road-meshes". Everything in this document is produced by code in the project; nothing is hand-modelled. Companion doc: `Docs/Kits/roads.md` (kit sheet: chunk kinds, cross-sections, materials, numbers).

## 1. What is delivered

| Item | Value |
|---|---|
| Source data | `Tools/world/out/roads.json` (33 roads, 42.4 km, 50 nodes) + carved heightmap `Content/Forza/World/Source/heightmap_4033.r16` (read for pier feet, abutments, portal walls, junction draping) |
| Blender collections | `FORZA_UE/Roads` (surface chunks `RC_*`, junction pads `RJ_*`), `FORZA_UE/Bridges_Tunnels` (`RB_*`, `RT_*`) |
| Chunks | **183**: 140 road, 27 junction pad, 14 bridge, 2 tunnel; one mesh object, one FBX, one UE static mesh each |
| Triangles | **387 056** in total (budget 4 M). Per chunk min 251 / mean 2 115 / max 6 580. Roads 316 858, junctions 31 282, bridges 30 684, tunnels 8 232 |
| FBX | `Exports/Roads/<chunk id>.fbx` (49 MB, git-ignored, regenerated), manifest `Exports/Roads/chunks.json` (tracked) |
| Hero | Great Bay Bridge: cable-stayed, 421.9 m, two A-frame pylons 44 m above the deck, 200 m main span (chunks `RB_HWY_EAST_01/02`) |
| UE importer | `Tools/ue/import_roads.py` (written, API names checked against `Intermediate/PythonStub/unreal.py`, **not run** as instructed) |
| Docs | this file, `Docs/Kits/roads.md` |

## 2. Files and how to run

| File | Role |
|---|---|
| `Tools/blender/world/roadgeo.py` | pure numpy core (no bpy): frames, stations, cross-section profiles, ribbon extrusion, caps, junction clustering / trimming / pads, chunk planning |
| `Tools/blender/world/roadstruct.py` | pure numpy: bridges (slab / box girder / cable-stayed, piers, abutments, wing walls, parapet bases) and tunnels (floor, liner, shell, light strips, portals) |
| `Tools/blender/world/roadbuild.py` | pure numpy: `make_plan`, `chunk_data`, `chunk_record` shared by Blender and the tests |
| `Tools/blender/world/build_roads.py` | **the Blender script** (idempotent): materials, collections, objects, `validate()`, `export()`, `write_manifest()`, QA helpers (`qa_terrain`, `qa_focus`) |
| `Tools/blender/world/verify_roads.py` | plain-Python acceptance report (no Blender) |
| `Tools/blender/world/make_hole_mask.py` | Landscape visibility holes needed by the geometry (tunnel mouths + bridge ends, section 7 / 7b): vertex list and 4033 x 4033 raster |
| `Tools/ue/import_roads.py` | UE editor importer |

Rebuild from the Blender MCP console (localhost:9889, ~3 s for the whole network):

```python
p = r"<project>/Tools/blender/world/build_roads.py"
g = {"__file__": p}
exec(compile(open(p, encoding="utf8").read(), p, "exec"), g)
g["build"]()                       # all chunks;  g["build"](only=["HWY_EAST"], kinds=["road"]) for a subset
g["validate"]()                    # ray casts on the real meshes: surface Z vs profile Z, normals, NaN, budgets
g["export"](); g["write_manifest"]()          # 183 FBX (~15 s) + chunks.json
bpy.ops.wm.save_mainfile()
```

Plain Python (no Blender): `"W:\Blender\5.2\python\bin\python.exe" -I Tools\blender\world\verify_roads.py` (checks manifest vs files vs a fresh build, NaN, budgets, terrain fit; exit 0 = pass).
UE: `powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/import_roads.py -Map <world map>` (switches in the script header).

## 3. Conventions

* **Axes.** roads.json is UE metres (X north, Y east). Blender geometry is `(x, y, z) = (X_ue, -Y_ue, Z)`; the FBX recipe of `Tools/blender/lib/fbx_export.py` (`axis_forward='-Y'`, `center_on="self"`) flips Y back, so a chunk lands at `centre_ue_m * 100` cm with rotation 0, scale 1. Each chunk's origin is the centre of its bounding box (rounded to 1 cm); the manifest stores that centre and the bounds in UE metres.
* **Road frame.** At arc length s: tangent T = (cos h, -sin h) in Blender axes (h = `heading_deg`), right R = (T_y, -T_x), lateral offset d > 0 to the right. Surface height `z(s, d) = z_c(s) - d*tan(bank) + h_profile(d)`; bank > 0 lowers the right edge. Verified against the heightmap before building: the carved bed equals `z - 0.05 - d*tan(bank)` with mean error 0.000 m (std 0.01-0.03), the correlation of the lateral slope with the banking sign is 0.97-0.9999, and `heading_deg` equals the finite-difference heading to 0.02 degrees.
* **The road sits exactly on the profile.** Centre line h_profile = 0; the cross fall is tiny (HIGHWAY 16 mm over the half carriageway, others 12 mm, shoulders a further 6 mm) so that the whole top surface stays >= 2.8 cm above the 5 cm deep terrain bed (the heightmap quantum is 2.3 cm). Measured against the final heightmap on 64 650 samples (excluding bridges, tunnels, junction pads): surface minus terrain p50 = +4.5 cm, p5 = -2.1 cm, p1 = -4.1 cm; 0.23 % of the samples are buried by more than 5 cm and 0.03 % by more than 30 cm (hairpin apexes, where the carve itself deviates up to 0.6 m).
* **Winding.** Triangles are counter-clockwise seen from outside, top surfaces face +Z (checked by 9 360 ray casts, 0 bad normals; upward rays under all bridges hit down-facing soffits).
* **Stations (cross-sections along the road).** 2 m in curves, hairpins, junction zones and wherever the height or bank of a skipped 2 m sample would deviate more than 4 mm / 0.02 degrees from the chord of its neighbours; 4 m on straights; structures use 3 m plus every such sample. Chunk boundaries are forced stations, so neighbouring chunks share identical vertices (no cracks, no caps at chunk joints).
* **UV channels** (UE `TexCoord 0..3`, Blender `UV0..UV3`, all four on every mesh, Nanite allows 4):

| Channel | Content |
|---|---|
| UV0 | `(u, v)`: u = lateral position over the mesh width 0..1, v = s / 10 (s in metres) |
| UV1 | `(d, s)`: lateral metres from the centre line (right +), arc length in metres (global per road, no per-chunk reset: dash patterns stay continuous across chunks). Feed this to the marking atlas (`Content/Forza/Textures/Source/road_markings_atlas`, 2048 px = 16 m, cell rectangles in `Tools/textures/recipes/markings.py`). The Blender preview material paints an edge line at \|d\| = P - 0.25 and a dashed lane line at \|d\| = median/2 + lane width (or at d = 0 on undivided roads), 3 m paint every 9 m |
| UV2 | `(paved half width, lane width)` metres, constant per road; `(0, 3)` on junction pads = **no lane markings** (structure soups: `(0, 0)`) |
| UV3 | `(median width m, zone)`; zone: 1.0 carriageway, 0.66 shoulder, 0.5 curb / pavement / walkway, 0.33 barrier / parapet / structure, 0 skirt and underside |

  Structures (piers, pylons, cables, portals) use metric box-projected UV0 = UV1 (1 unit = 1 m) so a triplanar-looking tiling material works; UV2 = (0,0), UV3 = (0, 0.33).
  The Blender preview material `M_Road_Asphalt` already draws edge lines, dashed lane lines and centre lines from these channels with a node graph; it is the executable reference for the UE master material.

## 4. Cross-sections (surface chunks)

One closed loop per station set: top surface left to right, 0.30 m outward/downward bevel ("skirt", dips under the terrain on cuts and fills), flat underside. All dimensions are taken from roads.json (`lane_width`, `shoulder_width`, `median_width`); P = paved half width, B = bed half width = P + shoulder.

| Class | Top surface (outside -> centre) | Materials (slots) |
|---|---|---|
| HIGHWAY (P 7.7, B 10.2) | bevel, asphalt shoulder 2.5, lanes 3.6 + 3.6 (vertex at the lane divider), concrete apron, **New-Jersey median barrier** 0.80 m high (base 0.60, top 0.17 m, in the 1 m median), mirrored | `M_Road_Asphalt`, `M_Road_Concrete` |
| REGIONAL (P 3.4, B 4.9) | bevel (dirt), gravel shoulder 1.2, **flush concrete curb strip 0.30**, asphalt lane, mirrored | `M_Road_Dirt`, `M_Road_Gravel`, `M_Curb`, `M_Road_Asphalt` |
| MOUNTAIN (P 3.2, B 4.2) | bevel, gravel shoulder 1.0, asphalt lane | `M_Road_Dirt`, `M_Road_Gravel`, `M_Road_Asphalt` |
| VILLAGE (P 2.9, B 3.9) | 0.45 m bevel, concrete pavement 1.0 m at +0.12 m, **raised kerb** (0.15 m top, vertical face), asphalt lane | `M_Road_Concrete`, `M_Curb`, `M_Road_Asphalt` |
| DIRT (P 2.8, B 3.4) | bevel, dirt shoulder 0.6, gravel carriageway (`M_Road_Gravel`; a `surface: dirt` road such as SHORTCUT would use `M_Road_Dirt`) | `M_Road_Dirt`, `M_Road_Gravel` |

Wide flat segments are subdivided to <= 1.9 m. Ends of a road piece that meet a junction pad or the free end of a road get a flat end cap (ear-clipped, so the barrier and kerb ends are closed); joints between chunks have none.

Chunking: each road is cut at junction trims, bridges and tunnels; the remaining runs are split into equal pieces of <= 420 m (target 360 m). Ids: `RC_<ROAD>_<nn>` surface, `RJ_<NODE>` junction, `RB_<ROAD>_<nn>` bridge, `RT_<ROAD>_<nn>` tunnel (`nn` counts per road and kind, in driving order).

## 5. Junctions (27 pads)

* Nodes within 6 m of each other form one cluster (the data has duplicate T / named nodes at the same spot). A cluster with >= 3 arms becomes a pad; 2-arm nodes (end-to-end roads such as PFOOT, SUMMIT) and dead ends need none. Arms come from the road samples, not from the straight node headings: a `mid` connection yields two arms.
* **Trim distance.** For every pair of adjacent arms (sorted clockwise) with included angle th: `x_i = B_i/tan(th) + B_j/sin(th)` (corner of the two bed edges along arm i) plus the fillet tangent length `R_f/tan(th/2)` (R_f 14 / 8 / 7 / 6 / 5 m for HIGHWAY / REGIONAL / MOUNTAIN / DIRT / VILLAGE), clamped to 7 .. 40 m. The 90 degree T's trim ~10-13 m; the acute 5-arm harbour node TIDE trims 40 m.
* The arm surfaces are removed over the trim interval (so nothing overlaps or z-fights), the arm end cross-sections (carriageway + shoulders, identical vertices to the road strip) become boundary vertices of the pad polygon, and adjacent arms are joined by cubic Bezier fillets tangent to both bed edges.
* **Tessellation.** Polar grid (centre + rings every ~2.5 m) so the pad can follow the terrain. Heights: fan height from the node z (pinned by the world builder) to the arm edge heights, smooth-maxed with `terrain + 7 cm` so the pad is never buried by the carve deviation (the heightmap blends beyond the beds, up to 1.5 m in the corners between arms): on 109 076 samples the pad minus terrain is min -0.14, p5 +0.04, p50 +0.06, p95 +0.18 m, buried by more than 10 cm = 0.015 %. The Landscape triangulation differs from bilinear sampling by 1.6 cm (p99) / 5 cm (p99.9); that is what the 7 cm covers.
* Skirt: 0.6 m bevel along the curved edges only; slab bottom; flat. No lane markings on the pad (UV2 = (0, 3)).
* **Stop / give-way lines** are real quads in slot `M_Road_Marking` (1.2 cm above the surface, 0.55 m deep) on the approaching half of every arm whose node `control` is `stop` (solid) or `yield` (0.5 m dashes), 1.2 m outside the trim line.

## 6. Bridges (14 chunks, 11 bridges)

Style selection per bridge: **cable** (HWY_EAST > 300 m), **slab** (deck < 5.2 m above the terrain and < 70 m long: LOOP_VALLEY 1405, BASIN_ROAD 957, CASTLE_ROAD 499; 0.6 m slab), **box** (everything else: concrete box girder).

* Deck cross-section (closed loop, same top points as the road, asphalt on asphalt roads, concrete deck on gravel / dirt roads): **parapet base** 0.45 m wide, 0.55 m above the deck surface at lateral +-(B + 0.225) (the roadside kit's `rs_bridge_rail_2m` / `rs_guardrail_4m` stands on it; the JSON carries `parapet.lateral` / `parapet.height`), fascia 0.40 m, sloped webs to a box soffit 0.55 x the deck width (4..12 m), depth `D0 = clamp(0.035 * span + 0.03 * width, 0.75, 1.8)` with a cubic haunch over the piers.
* Supports: box / slab piers every 28 m (`round(L / 28)` spans); a pier = hammer-head cap beam (2.2 m long), one tapered column (twin columns on the 21 m highway deck, with a cross strut when taller than 14 m), footing block sunk 1.4 m below the **heightmap minimum under the footprint** (the real terrain / sea bed), so every pier stands on the ground whatever the slope.
* Abutments at both bridge ends: block under the deck end running 2.8 m back, two angled wing walls (22 degree flare, 7.5 m) that descend to the terrain.
* **Great Bay Bridge** (`RB_HWY_EAST_01/02`, s 4964.3 .. 5386.2 = 421.9 m, cut at the middle of the main span): deck 21.3 m wide with the highway barrier, 111 + 200 + 111 m (side spans / main span), pylons at s0 + 111 and s0 + 311: two A-shaped legs (lateral +-12.35 m at the deck, leaning to +-7.4 m at the top, 44 m above the deck, 2.4 x 3.0 m tapering to 1.5 x 1.9 m) from the sea bed, three cross beams, **56 steel cables** (7 per side per direction per pylon, 0.22 m dia., fan from 50 % to 95 % pylon height, deck anchors every 14 m from 16 m with steel sleeves), 6 approach piers (3 per side span, twin columns up to 43 m tall with mid struts), shallow constant-depth deck between the pylons.
* Chunk records of bridges list `piers`, `abutments`, `pylons` (positions in UE metres) and `parapet`.

## 7. Tunnels (2 chunks)

* **The portals are not where roads.json puts the run ends.** The data's tunnel runs start inside the portal cutting (an open trench with 1:0.6 side slopes): LOOP_DESC 166..416, PASS_SPUR 3613..3729. The hillside only closes over the road further in. The builder reads the heightmap: the tube and head-walls start at the **foot of the cut face** (first station where the terrain on the centre line is >= 0.6 m above the road): LOOP_DESC **209 .. 371 (162 m)**, PASS_SPUR **3655.8 .. 3685.8 (30 m)**; the stretches in the trench stay ordinary road chunks. The chunk record keeps `run_s0/run_s1` (data) next to the real portal stations.
* Tube: floor (the road's own carriageway and shoulder points, asphalt; 0.18 m high concrete walkways between the kerb at B and the wall), vaulted inner liner (half width B + 0.9 = 5.1 m, straight walls to 2.3 m, half-ellipse crown, **5.9 m clearance**), outer shell 0.9 m thick (closed, Lumen-proof), **two emissive light strips** (`M_Tunnel_Light`) along the vault; lamp positions for UE lights every 12 m on both lines are in `lights_ue`.
* Portal head-wall (both ends): a block standing in front of the cut face: vertical front face with the arch opening, 8.2 m high, wide enough to reach the trench slopes (17-18 m), a horizontal ledge on top and a body that runs back (5.5-6 m) until the hillside buries it, a ring of **stone voussoirs** around the arch (varying width 0.72-0.98 m and projection, 4 cm joints, wide keystone).
* **Landscape holes (required).** The Landscape is a surface without thickness: at the mouth the carved terrain rises through the tube cross-section, so it would block the view into the tunnel. Every tunnel chunk lists oriented rectangles (`landscape_holes`: centre, heading, 5.0-5.5 m long, 11.4 m wide; 4 in total, also collected at the top level of chunks.json) where the Landscape visibility mask must be set (356 heightmap vertices). The Blender QA terrain (`qa_terrain(..., holes=...)`) shows the intended result.

### 7b. Bridge ends: natural terrain above the deck (found by measuring, same remedy)

The world builder does not carve under bridge runs. At the first / last 3-12 m of most bridges the natural terrain stands **above the deck surface** (up to 0.70 m; Great Bay 0.53 / 0.54 m, a hump across the whole carriageway, visible in the QA view as a half disc of terrain growing out of the road). 17 such ranges in 13 of the 14 bridge chunks; each bridge chunk lists them in `deck_buried` (`ranges: [{s0, s1, max_m}]`, threshold 3 cm). The geometry stays on the profile, so the only fixes are (a) hide those Landscape quads: `make_hole_mask.hole_vertices()` returns the 1 281 heightmap vertices (1 637 together with the tunnel mouths; stored in `chunks.json -> landscape_hole_vertices`, rasterisable with `make_hole_mask.py`), or (b) change `Tools/world/carve.py` to keep the terrain >= 0.3 m below the deck over the first / last 15 m of every bridge run (cleaner: no holes). Verified: with the vertices removed the deck is clean (QA view `qa_terrain(..., hole_vertices=...)`).

## 8. Culverts
`chunks.json -> culverts` (8 entries: road, s, position, heading, bed half width): put `rs_culvert_headwall_a/b` there (the road is plain surface, the terrain brook channel is carved by the world builder).

## 9. Materials

Blender material = UE slot name = match key. Names: `M_Road_Asphalt`, `M_Road_Concrete`, `M_Road_Dirt`, `M_Road_Gravel`, `M_Curb`, `M_Bridge_Concrete`, `M_Bridge_Steel`, `M_Tunnel_Wall`, `M_Tunnel_Light`, plus **`M_Road_Marking`** (an addition to the contract list: stop / give-way lines are geometry). Blender: simple Principled previews (asphalt with procedural markings, `M_Tunnel_Light` emissive). UE: the importer binds `/Game/Forza/Materials/Roads/MI_<name without M_>`; when missing it creates a fallback parent `M_RoadFallback_<Asphalt|Concrete|Dirt|Gravel>` (parameters `BaseColor`, `Roughness`, `EmissiveColor`; **physical material `PM_Roam_*` set on the parent**, which is what the wheel traces read on complex collision) and `MI_*` instances. The real world materials replace the MI assets by name; set the matching `PM_Roam_*` on them (Asphalt: asphalt + markings, Concrete: concrete / curb / bridge / tunnel, Gravel, Dirt).

## 10. Collision, Nanite, import

* **Collision = use complex as simple** (the render triangles; roads are ribbons, hulls would be wrong). The importer sets `body_setup.collision_trace_flag = CTF_USE_COMPLEX_AS_SIMPLE`, collision profile `RoamWorldStatic` on the actors (blocks `Roam_Wheel`, `Roam_Camera`, `Roam_Vehicle`, `Roam_Traffic`), no UCX hulls. Per-slot physical materials as in section 9.
* **Nanite on** (`build_nanite`), lightmap UVs off, imported normals, `has_navigation_data` off.
* Surfaces are closed solids (0.30 m slab with bevel) to avoid Lumen light leaks; bridge decks are box girders, piers closed prisms.
* One StaticMeshActor per chunk at `centre_ue_m * 100`, label `Road_<id>`, folder `Roads/<Kind>/<ROAD>`, tags `RoamRoad`, `RoamDrivable`, `RoamRoadChunk:<id>`, `RoamRoad_<kind>`, static mobility, `is_spatially_loaded = False` (as specified; `ROAM_ROADS_SPATIAL=1` makes them stream with World Partition). Actors are found by their `RoamRoadChunk:` tag, so a re-run replaces them.
* Meshes: `/Game/Forza/World/Roads/Meshes/SM_<chunk id>`. After import the script compares each static-mesh bounds with the manifest size (2 %) and checks Nanite.

## 11. Validation results (all measured)

| Check | Result |
|---|---|
| Surface Z = profile Z, rays on lane centres of every road / bridge / tunnel chunk (60 per chunk, real Blender meshes) | 9 360 rays, 0 misses, **max deviation 3.7 mm** (tolerance 10 mm), 0 up-facing failures (`bad_normal` 0) |
| NaN / Inf in positions or UVs | 0 |
| Triangle budget | 387 056 total (< 4 M); per chunk max 6 580 (< 40 k) |
| Chunk count | 183 (= 183 FBX files = 183 manifest entries; `verify_roads.py` cross-checks) |
| Road surface vs terrain | p50 +4.5 cm, p5 -2.1 cm (64 650 samples) |
| Junction pad vs terrain | buried by > 10 cm: 0.015 % |
| FBX check | binary FBX parsed: positions centred on the origin, 4 UV layers, 1 normal layer, material names = slot names, UnitScaleFactor 100 (same recipe as the cars) |

Visual QA with `look`: hairpin (LOOP_PASS), highway deck with barrier and lane lines, village kerb, junction pads (4-arm CROSS, 3-arm T, 5-arm TIDE, Y at J_BAY_S), Great Bay pylon from three sides, box bridge on the heightmap terrain, both tunnel mouths on the heightmap terrain with and without the landscape hole, tunnel interior.

## 12. Known limitations / things the lead must do

1. **(IMPLEMENTED 2026-10-17 in `URoamWorldBuilder::CreateLandscapeFromHeightmap`, parameter `HoleVertices`; WORLD_BUILD.md section 10, issue 10: the portal look wants a smaller hole)** **Landscape holes** at the 4 tunnel mouths (section 7) and at the bridge ends (section 7b), 1 637 heightmap vertices in total (`chunks.json -> landscape_hole_vertices`, `make_hole_mask.py`): without them the terrain closes the tunnel mouths and humps up to 0.7 m through the first / last metres of the bridge decks. Alternative for the bridges: a carve change in `Tools/world/carve.py`.
   Related, informational: 29 short ranges (107 m of 42 389 m) where the carved terrain stands more than 10 cm above the road somewhere across the bed (`terrain_above_road` in the road chunk records): 4 are the V-shaped portal clefts, the others are hairpin apexes (0.2-0.63 m) and the 2-arm node PFOOT (LOOP_VALLEY s 2193-2213, up to 0.97 m). The mesh is on the profile there; the carve should be adjusted if those bumps matter.
2. **Chunk triangle counts are below the 8 k lower guideline** (mean 2.1 k): a 360 m ribbon needs 1.5-6.5 k triangles; padding it with more tessellation would only add collision / memory cost. Nothing exceeds 40 k.
3. **(UPDATE 2026-10-17: the importer HAS been run in Unreal: 217 / 217 chunks, 0 problems, Nanite + complex-as-simple collision, `PM_Roam_*` on the `MI_Road_*`; the Nanite fallback had to be set to 100 % triangles for the physics mesh; results in `Docs/Tech/WORLD_BUILD.md` section 10.)** The importer had not been run inside Unreal when this document was written (as instructed). What was done instead: every `unreal.*` name and member was checked against `Intermediate/PythonStub/unreal.py` (all resolve except `BodySetup.invalidate_physics_data`, which is wrapped in try/except), the dry-run mode (`ROAM_ROADS_DRY=1`) and a 4-chunk pass of the full control flow were executed against a stub / mock `unreal` module (manifest parsing, FBX paths, material slot mapping, actor placement maths). Each chunk is processed in its own try/except, so one API surprise costs a warning (`ROADS_WARN` lines), not the run. Likeliest first-run fixes: the `phys_material` of the fallback parent (instances are expected to inherit it), `is_spatially_loaded`, the `FbxImportUI` options mapping.
4. Lane markings come from the master material (UV1..UV3 recipe in section 3); until it exists the roads are plain colours. Stop lines are geometry in `M_Road_Marking` (needs a flat white / yellow material instance).
5. No guard rails, delineators, signs, lamps on roads or bridges: the roadside kit covers them (bridge parapet bases, culvert and hairpin positions are in the manifest / roads.json).
6. Junction pads have no painted lane continuation, and arms of acute junctions (TIDE, GAS_H, T_PASS_SPUR_start, T_LOCAL_FARM_D_start: 18-40 degrees) merge into a wide plaza (trim up to 40 m) - acceptable there, not a normal crossing.
7. The road surface follows roads.json exactly, including a sharp V-shaped sag in the PASS_SPUR profile at s = 3493 (grade changes from -12 % to +12 % within 6 m, on the 42 m bridge). The mesh keeps every 2 m sample there; fixing it belongs to the profile solver in `Tools/world/profile.py`.
8. Wing walls are thin retaining planks and abutments are plain blocks; piers / pylons are untextured concrete (metric UVs, tile in the material).
9. There are no LODs (Nanite); no hand-made collision proxies; vertex normals at chunk joints are computed per chunk (sub-degree differences on these gentle ribbons).

## 13. Why some choices were made
* The tunnel portal rule and the Landscape holes come from looking at the data: the first attempt (head-walls at the data's run ends) put the walls 44 m before the hillside, and the second one (walls at the point where the terrain covers the tube) hid the opening behind the Landscape. The foot-of-slope wall with a hole is the only variant that works with a heightfield.
* The pad draping came from measuring: with a plain fan, 43 % of the pad surface was buried by > 10 cm (up to 1.57 m) in the corner regions between the arms.
* Cross-fall amplitudes were chosen against the heightmap quantum and bed offset (see section 3).
