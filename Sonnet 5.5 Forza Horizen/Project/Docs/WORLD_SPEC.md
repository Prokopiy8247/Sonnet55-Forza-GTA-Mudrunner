# World specification — "Roamline: Open Roads" (4.03 × 4.03 km, 40–60 km of road)

Single source of truth for the procedural world pipeline. The data lives in `Tools/world/worlddef.py`; every other artefact is generated from it (reproducible, seeded).

## 1. Coordinates
* **UE world axes in metres**: X = north, Y = east, Z = up. Origin = map centre. Playable square X, Y ∈ [−2016, +2016] m.
* Landscape: **4033 × 4033 vertices, 1 m spacing** (4032 m), 32 × 32 components of 127 quads (2×2 sub-sections of 63). Landscape actor scale (100, 100, ZScale), location chosen so the middle of the grid is the origin. Heightmap array `H[j, i]` ↔ vertex (i → +X, j → +Y).
* Z range −60 … +760 m; sea level z = 0 m (ocean plane / Water body).
* Blender builds road/bridge/tunnel geometry in Blender world axes using the conversion `bl = (X_ue, −Y_ue, Z)` (the exporter's handedness fix flips Y back), so pieces land at their true UE position. Chunk meshes are exported centred on their own chunk centre (JSON stores the chunk centre in UE metres).

## 2. Regions (4 biomes + hub)
| Region | Area (X north, Y east) | Terrain | Look |
|---|---|---|---|
| **Greenvale** (farmland & forest valley) | X −2016…+100, Y −2016…−150 | rolling hills 30–160 m, river *Silverrun* flowing W→E, fields (crop patches), hedgerows, mixed forest | lush green, oak/birch/pine groves, wheat, hay bales, village **Millbrook** (X −900, Y −900), farms |
| **Highcrest** (mountain highlands) | X +100…+2016, Y −2016…−250 | mountains to 700 m, pass summit ≈ 560 m at (1180, −1180), cliff edges, snow above ≈ 480 m | pines, rocks, snow patches, **tunnel** through a ridge near (850, −620), summit **viewpoint**, hamlet **Frostholm** (ski lodge) near the pass |
| **Sunbaked Plateau** (arid canyon / desert) | X +100…+2016, Y −250…+1250 | plateau 220–320 m with mesas and canyons, wide basins | orange/red soil, dry scrub, cacti, dust, long straight **highway**, dirt shortcuts, **gas station** near (900, 420), wind farm on the plateau edge |
| **Saltcliff Coast** (cliffs, beach, harbour) | Y +1000…+2016 (all X) and the south-east | sea on the east edge (z ≤ 0), cliffs 30–90 m, beach in the south, bay/inlet crossed by the **Great Bay Bridge** (≈ 380 m) near (−350, 1300) | blue water, rocks, grasses, palms near the beach, harbour hamlet **Tidewick** (−1180, 1420), **lighthouse** at (−600, 1850), cliff road |
| **Crossroads hub** | around (0, 0) | broad valley floor ≈ 90 m | junction of highway / regional roads, diner + gas station, warm "festival" feel |

Region transitions are blended (smooth masks), so the soil/vegetation changes gradually along the roads.

## 3. Road network (≥ 40 km, ≤ 60 km total; one continuous scenic loop ≥ 20 km)
Classes: `HIGHWAY` (2 lanes per direction, 100–130 km/h limit), `REGIONAL` (1+1 lanes, 80), `MOUNTAIN` (1+1, narrow, guard rails, 60), `DIRT` (unpaved gravel, 1+1 narrow, 50), `SHORTCUT` (cross-country, 40), `VILLAGE` (1+1, 30).

Routes are defined as waypoint lists in `worlddef.py` and **planned on the terrain** by a slope-limited path finder (max grade: highway 6 %, regional 9 %, mountain 12 %, dirt 14 %), which produces natural switchbacks/hairpins on steep terrain; the result is smoothed into Catmull-Rom/clothoid-like splines and given a smoothed elevation profile (grade-limited), banking on curves, cut/fill terrain carving (cuttings and embankments, not floating strips), **bridges** where the profile is > 4 m above the terrain over > 20 m (river, bay, canyon), **tunnels** where the profile is > 6 m below the terrain over > 80 m.

| Id | Class | Rough route | Target length |
|---|---|---|---|
| `LOOP` | mixed (REGIONAL/MOUNTAIN/HIGHWAY) | Crossroads → east highway across the plateau → NE canyon sweepers → down to the coast → coast road south over Great Bay Bridge → Tidewick → west through Greenvale → north along the Silverrun valley → Millbrook → climb the Highcrest pass (hairpins, tunnel, summit viewpoint) → descend → Crossroads | 22–28 km |
| `HWY_EAST` | HIGHWAY | straight-ish 5.5 km from Crossroads across the plateau to the east edge (sweeping gentle curves, a few crests) | 5–6 km |
| `PASS_SPUR` | MOUNTAIN | extra switchback ascent to Frostholm ski lodge & viewpoint | 5–7 km |
| `COAST_SPUR` | REGIONAL | cliff road between Tidewick and the lighthouse | 3–4 km |
| `DIRT_*` | DIRT/SHORTCUT | ≥ 4 gravel/dirt tracks (desert wash, forest logging track, farm track, cliff-top track) linking roads | 8–10 km total |
| `LOCAL_*` | REGIONAL/VILLAGE | village streets, farm access roads, gas-station links | 6–8 km |

Intersections: T and 4-way junctions with proper junction pads and stop/give-way logic nodes; roundabout optional at Crossroads.

## 4. Settlements & POIs (small only)
Millbrook (village, ≈ 14 buildings + church + farmland), Frostholm (lodge + 6 chalets), Tidewick (harbour hamlet, pier, boats, 8 houses), farms ×4, gas stations ×3 (Crossroads, plateau, coast), diner ×2, lighthouse, ruined castle on a hilltop above Greenvale, wind farm (6 turbines), viewpoints ×3, tunnel portals, stone bridge in Greenvale, rest areas ×2.

## 5. Generated artefacts (all under the project, reproducible by `Tools/world/build_world.py`)
* `Content/Forza/World/Source/heightmap_4033.r16` (little-endian uint16; 32768 = z 0 m with ZScale giving ±256·ZScale/100 m… exact mapping stored in `world_meta.json`), weightmaps `layer_<Name>.r8`, `world_meta.json`.
* `Tools/world/out/roads.json`: per road: class, width profile, lane counts, speed limit, sample list (position, tangent, bank, width), section flags (bridge/tunnel/junction), junction nodes.
* `Tools/world/out/placements/*.json|bin`: per-cell scatter lists (trees, bushes, rocks, props), settlement building placements, road furniture (guard-rail runs, signs, posts, lamp posts), activity gate positions.
* Blender: road/bridge/tunnel chunk meshes generated from `roads.json` by `Tools/blender/world/build_roads.py` (collection `FORZA_UE/Roads`), exported to `Exports/Roads/`.
* Textures: procedurally generated tileable PNGs (`Tools/textures/*.py`) → imported to `/Game/Forza/Textures/`.
