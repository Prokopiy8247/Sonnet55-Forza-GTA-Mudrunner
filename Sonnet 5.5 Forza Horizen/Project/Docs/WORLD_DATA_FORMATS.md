# World data formats ("Roamline: Open Roads" terrain + road network)

Everything in this document is produced by `Tools/world/build_world.py` (pure Python 3.13 + numpy, deterministic, fixed seed `20260516`; see `Tools/world/README.md`). Nothing here is hand-edited. Consumers: the Blender road builder (`roads.json`, `river.json`), the Unreal importer (heightmap, weightmaps, `world_meta.json`), traffic / AI (`roads.json` graph + `routes`), the minimap (`region_id.r8`, `roads.json`, preview PNGs).

## 1. Conventions

| Item | Convention |
|---|---|
| World axes | UE metres: **X = north, Y = east, Z = up**, origin = map centre, playable square X, Y in [-2016, +2016] |
| Blender conversion | `bl = (X_ue, -Y_ue, Z)` (see WORLD_SPEC.md section 1) |
| Sea level | z = 0 m |
| Units | metres, degrees, 1/metres (curvature) |
| Heading | compass bearing of travel in degrees: **0 = +X (north), 90 = +Y (east)**, clockwise seen from above, range [0, 360) |
| Curvature | signed 1/R, **positive = turning right** (bearing increasing along `s`) |
| Bank | `bank_deg` positive = right edge lower than the left edge (road rolls into a right-hand curve) |
| Raw grids | 4033 x 4033, 1 m vertex spacing, vertex `(i, j)` is at `X = i - 2016`, `Y = j - 2016` |
| Raw layout | row-major, **row `j` = +Y direction, column `i` = +X direction** (`array[j, i]`, `offset = (j * 4033 + i) * itemsize`) |
| Preview images | north-up (X up, Y to the right), 1008 px = 4033 m |

## 2. File inventory

Unreal-bound raw files live in `Content/Forza/World/Source/` (git-ignored, regenerated); small JSON products are written to `Tools/world/out/` and copied to `Content/Forza/World/Source/`.

| File | Type | Size | Content |
|---|---|---|---|
| `heightmap_4033.r16` | uint16 LE | 32 530 178 B | terrain height, carved around the roads |
| `layer_Grass.r8`, `layer_ForestFloor.r8`, `layer_Farmland.r8`, `layer_Rock.r8`, `layer_Sand.r8`, `layer_RedClay.r8`, `layer_Snow.r8`, `layer_RoadVerge.r8` | uint8 | 16 265 089 B each | landscape layer weights (sum = 255 per vertex) |
| `density_forest.r8`, `density_scrub.r8`, `density_crops.r8` | uint8 | 16 265 089 B each | vegetation scatter density 0..255 |
| `slope.r8` | uint8 | 16 265 089 B | slope angle, `degrees * 255 / 90` |
| `region_id.r8` | uint8 | 16 265 089 B | region index (see 5) |
| `world_meta.json` | JSON | ~5 KB | encoding constants, landscape setup, layer order, regions, sites (POIs) |
| `roads.json` | JSON | ~1.3 MB | all road centre lines (2 m samples), junction graph, edges, routes |
| `river.json` | JSON | ~25 KB | Silverrun centre line, brooks, Great Bay description |
| `road_metrics.json` | JSON | ~6 KB | acceptance metrics of the build (see 9) |
| `Tools/world/out/heightmap_4033_16bit.png` | 16-bit grey PNG | ~9 MB | the same heightmap for quick inspection (not Unreal-bound) |
| `Tools/world/out/previews/*.png` | PNG | | overview, route zooms, elevation profiles, slope map, grade histogram, layer / density previews |

## 3. Heightmap (`heightmap_4033.r16`)

* uint16 little endian, 4033 x 4033, no header.
* `Z_m = (h16 - 32768) * 300 / 128 / 100` (metres), i.e. `h16 = round(Z_m / 0.0234375) + 32768`. Resolution 0.0234 m, representable range -768 .. +767.98 m. Actual content: about -51 .. +680 m (spec window -60 .. +760).
* This is exactly the Unreal Landscape convention for **Scale Z = 300** (UE units = cm): `Z_cm = (h16 - 32768) / 128 * 300`. Landscape import: 4033 x 4033, 32 x 32 components, 127 quads / component (2 x 2 sub-sections of 63), actor scale `(100, 100, 300)`, actor location `(-201600, -201600, 0)` cm so that vertex (2016, 2016) is the world origin. All values are also in `world_meta.json -> heightmap / landscape`.
* The terrain is the **final, already carved** surface (road beds, cuttings, embankments, portal cuttings are baked in). `Z_road_centre - 0.05 m` equals the terrain on the road bed (flat across paved width + shoulders, with banking; the carved flat bed is a further 1.3 m wider on each side so that a wall or embankment of a neighbouring leg never starts at the shoulder edge), except under bridges and inside tunnels (see 6.5). Over the first / last 15 m of every bridge run the terrain is kept at least 0.3 m below the deck.
* A soft ring along the map edge falls to the sea / rock border; the playable square is the full grid.

## 4. Weight, density, slope and region maps

All are uint8, 4033 x 4033, same layout as the heightmap.

* **Layer weights** (`layer_<Name>.r8`): order is `Grass, ForestFloor, Farmland, Rock, Sand, RedClay, Snow, RoadVerge` (also stored in `world_meta.json -> layers.order`). The eight weights sum to **exactly 255** at every vertex (largest-remainder quantisation). Sea floor is Sand. `RoadVerge` is a band around the road bed (asphalt roads up to ~3 m beyond the bed edge, gravel / dirt roads ~6.5 m) so the verge texture follows the carving.
* **Density maps**: `density_forest.r8` (trees), `density_scrub.r8` (bushes, cacti, dry scrub), `density_crops.r8` (wheat / crop rows only on farmland). 0 = nothing, 255 = maximum density. Already cleared on and next to roads (fade 7..22 m from the bed edge), on water and on steep ground.
* **`slope.r8`**: slope angle in degrees `= value * 90 / 255` (rise over run measured on the 1 m grid, lightly blurred).
* **`region_id.r8`** (hard classification of the blended region masks): `0 Greenvale`, `1 Highcrest`, `2 Plateau` (Sunbaked Plateau), `3 Coast` (Saltcliff Coast), `4 Basin` (Crossroads hub basin). Colours for the minimap are in `world_meta.json -> regions[].color`. Area shares of dry land: Greenvale 24 %, Highcrest 22 %, Plateau 19 %, Coast 21 %, Basin 14 %.

## 5. `world_meta.json`

```
version, name
coordinate_system { axes, origin, extent_m:[-2016,2016] }
heightmap { file, width:4033, height:4033, vertex_spacing_m:1.0, encoding, layout, z_scale_ue:300.0,
            metres_per_unit:0.0234375, zero_level:32768, formula, z_range_m:[-768, 767.98], sea_level_m:0 }
landscape { components:[32,32], quads_per_component:127, sections_per_component:[2,2], quads_per_section:63,
            scale_ue_units:[100,100,300], location_ue_units:[-201600,-201600,0], note }
layers { order:[8 names], files:[8 file names], encoding }
density_maps { files:[3], encoding }
other_maps { slope, region_id }
regions [ { id, key, name, color:[r,g,b] } ]
sites   [ { name, kind, x, y, z } ]      # points of interest, UE metres; z = finished terrain height at the point (seabed for the Great Bay Bridge site, road bed height for the tunnel site)
files   { <file>: bytes }
build   { macro_step_m:2.0, detail_noise:true, seed:20260516, numpy, python }
```

`sites[].kind` is one of `hub, village, hamlet, farm, gas, diner, lighthouse, castle, windfarm, viewpoint, tunnel, bridge, rest, harbour`. Sites are **positions only** (not snapped to the road edge); the nearest road node for a station / village is the node of the same name in `roads.json` (`CROSS`, `GAS_X`, `DINER_X`, `GAS_P`, `GAS_H`, `MILL`, `TIDE`, `PIER`, `FROST`, `LODGE`, `SUMMIT`, `LH`, `FARM_A..D`, `WASH_END`, `WIND_END`, `BEACH_END`). The `Highcrest Tunnel` site is the midpoint of the longest generated tunnel (its z is the road bed height); the `Plateau Diner` has no dedicated road, it sits about 60 m from the end of `LOCAL_PGAS` at the Plateau Gas plaza. Site pads are flattened in the terrain (platforms listed in `worlddef.py -> PLATFORMS`).

## 6. `roads.json`

### 6.1 Top level

```
version:1, coordinate_system, units
sample_fields: ["s","x","y","z","heading_deg","curvature","bank_deg","width","flags"]
sample_notes:  { field: description }
flag_bits:     { "BRIDGE":1, "TUNNEL":2, "CULVERT":4, "JUNCTION":8, "HAIRPIN":16, "PORTAL":32 }
roads:  [ road ... ]      # 33 roads in build order, 50 nodes, 57 edges
nodes:  [ node ... ]
edges:  [ edge ... ]
routes: { "LOOP", "HWY_EAST", "PASS_SPUR", "COAST_SPUR", "DIRT_*", "LOCAL_*" }
```

### 6.2 Road object

```
id, name, class                        # class: HIGHWAY | REGIONAL | MOUNTAIN | DIRT | SHORTCUT | VILLAGE
lanes_per_direction, lane_width, shoulder_width, median_width     # metres
speed_limit_kmh, surface               # asphalt | gravel | dirt
length_m, paved_width, bed_half_width  # paved_width = 2*lanes*lane_width + median ; bed_half_width = paved_width/2 + shoulder_width
min_radius_m, max_grade                # DESIGN limits of the class (hairpins on MOUNTAIN/DIRT roads may go down to 18/25 m), not measured values
sample_count
bridges:  [ { s0, s1, length, deck_height_min, deck_height_max } ]   # deck height = road z - natural terrain z
tunnels:  [ { s0, s1, length } ]
culverts: [ s ]                                                      # arc length of every culvert (brook crossing)
hairpins: [ { s, x, y, min_radius } ]                                # one entry per hairpin turn
samples:  [ [s, x, y, z, heading_deg, curvature, bank_deg, width, flags], ... ]
```

Class table (all metres):

| Class | lanes/dir | lane w | shoulder | median | paved w | bed half w | speed | max grade | min radius (hairpin) | surface |
|---|---|---|---|---|---|---|---|---|---|---|
| HIGHWAY | 2 | 3.6 | 2.5 | 1.0 | 15.4 | 10.2 | 120 | 6 % | 250 | asphalt |
| REGIONAL | 1 | 3.4 | 1.5 | 0 | 6.8 | 4.9 | 80 | 9 % | 70 | asphalt |
| MOUNTAIN | 1 | 3.2 | 1.0 | 0 | 6.4 | 4.2 | 60 | 12 % | 40 (18) | asphalt |
| DIRT | 1 | 2.8 | 0.6 | 0 | 5.6 | 3.4 | 50 | 14 % | 25 | gravel |
| SHORTCUT | 1 | 2.4 | 0.4 | 0 | 4.8 | 2.8 | 40 | 16 % | 25 | dirt |
| VILLAGE | 1 | 2.9 | 1.0 | 0 | 5.8 | 3.9 | 30 | 10 % | 20 | asphalt |

(SHORTCUT is defined for later cross-country tracks; the current network uses the other five.)

### 6.3 Samples

* One row per **2 m of arc length** (`s = 0, 2, 4, ...`), ordered along the direction of travel of the road definition. `s` is measured on the 2D (X, Y) centre line.
* `z` = finished road surface height on the centre line (metres, 3 decimals). Grade between rows = `dz / ds`; it never exceeds the class limit (verified independently from the exported samples: max 6.0 / 9.0 / 12.0 / 14.0 / 10.0 % for HIGHWAY / REGIONAL / MOUNTAIN / DIRT / VILLAGE).
* `heading_deg`, `curvature`, `bank_deg`: see section 1. Banking is in degrees: at most 3.4 (HIGHWAY), 2.9 (REGIONAL / MOUNTAIN), 1.7 (DIRT), 0 (VILLAGE).
* `width` = paved width (lanes + median); shoulders are extra (`shoulder_width` on each side).
* `flags` is a bit mask:

| Bit | Name | Meaning |
|---|---|---|
| 1 | BRIDGE | deck > 4 m above terrain over > 20 m, or a forced span (Great Bay, river / canyon crossings); terrain below is **not** carved |
| 2 | TUNNEL | the forced Highcrest tunnel (a straight bore through a ridge shoulder; the run starts / ends where the natural terrain is at least 2.5 m above the deck); terrain above is untouched except portal cuttings |
| 4 | CULVERT | the road crosses a brook / dry wash here (terrain is carved normally, put a culvert mesh) |
| 8 | JUNCTION | within 22 m of a junction node (any arm), or (up to 150 m from the node) where the bed of a road that meets at that node overlaps this road's bed at nearly the same height (< 3 m): a branch that leaves its parent at a shallow angle shares bed width with it |
| 16 | HAIRPIN | inside a hairpin turn |
| 32 | PORTAL | the 2 samples around each end of a tunnel run (portal frame goes here) |

### 6.4 Nodes (junction graph)

```
node: { id, kind, x, y, z, arm_count,
        connections: [ { road, s, role, control } ],
        arms:        [ { road, s, role, heading } ] }
```

* `kind`: `node` (named hub / village / station / dead end), `T` (anonymous T-junction where a road ends on another road; id `T_<ROAD>_<start|end>`), `X` (crossing of two roads that was not planned, id `X_<A>_<B>_<n>`; currently one: `CASTLE_ROAD x DIRT_FARM`). `z` is the finished road height at the node (both roads are pinned to it with a short flat zone).
* `connections[].role`: `start` / `end` (the road begins / ends at the node) or `mid` (the road passes through the node; then `s` is the arc length of the pass-through point). `s` is the arc length on that road.
* `arms[]`: one entry per road arm, `heading` = compass bearing pointing **away from the node** along that arm (a `mid` connection yields two arms, 180 degrees apart).
* `control`: `priority` (main road at a multi-arm node or a through road), `yield` (minor arm of a HIGHWAY / REGIONAL / MOUNTAIN road), `stop` (minor arm of a VILLAGE / DIRT / SHORTCUT road), `free` (a plain 2-arm node with no priority question). The best road class at a node always has priority.
* All roads meet at junctions with the same z and (for T-junctions) a perpendicular approach over the last ~60 m (the minor road ends straight, at right angles to the major road). Junction pad meshes should use `z`, the arm headings, and the two bed half-widths.

### 6.5 Edges and routes

* `edges[]`: `{ id "<road>#k", road, from_node, to_node, s0, s1, length }` - the road is cut at every node it touches (start, end, mid); edges are directed along increasing `s` (the traffic system makes them bidirectional: 1 + 1 lanes). The graph is a single connected component.
* `routes`: named drive sequences `{ segments:[{road, direction:1, s0, s1, start_node?, end_node?}], closed, length_m }`.
  * `LOOP`: `HWY_EAST -> LOOP_COAST -> LOOP_SOUTH -> LOOP_VALLEY -> LOOP_PASS -> LOOP_DESC`, `closed = true` (Crossroads to Crossroads), 22.3 km.
  * `HWY_EAST`, `PASS_SPUR`, `COAST_SPUR`: single roads.
  * `DIRT_*`, `LOCAL_*`: the set of all dirt / local roads (not a drive sequence).

### 6.6 Geometry relations the Blender builder can rely on

* Bridge decks follow the centre-line `z` exactly; in a bridge run the natural terrain is below the deck (`deck_height_*`). No carving is applied under a bridge run, so piers go down to the local terrain (`terrain z` is in the heightmap).
* Outside bridges / tunnels the terrain on the bed equals `z - 0.05 m` (plus banking: `bed = z - 0.05 - tan(bank) * lateral_offset`, flat within the bed half-width). Cuttings are at most 1:2, embankments at most 1:3; both blend smoothly into the natural terrain.
* Tunnel portals: the first / last 36 m of a tunnel run are cut into the hillside with a steep 1:0.6 cutting so that the portal headwall can sit on it. Between the portals the terrain is untouched (mountain mass above, roughly 6 m or more).
* The vertical profile is smoothed (grade-limited, no kinks), so a mesh generated at the 2 m station spacing needs no extra smoothing.
* `HAIRPIN` runs are the only places where radius < the class minimum is allowed (MOUNTAIN 18 m design, measured >= 20.8 m; DIRT 25 m, measured >= 26.6 m).

## 7. `river.json`

```
version, sea_level_m
river:   { name:"Silverrun", fields:["x","y","water_z","width","water_depth"], points:[[x,y,water_z,width,depth], ...], length_m }
streams: [ { name, fields:["x","y","water_z","width"], points:[[x,y,water_z,width], ...] } ]   # Brook A/B/C, Frost Brook, Highcrest Burn
great_bay: { centre_line:[[x,y]...], half_width:[m...], floor_z:[m...], water_z:0 }
```

The river flows west to east (x of the points is near -400..-700 m) and drops from 100 m to 1 m. `water_z` is the water surface height; `width` the water width; `water_depth` the depth. The river valley is carved into the heightmap (hard channel 70..125 m, soft banks up to ~560 m wide). `great_bay` describes the sea inlet crossed by the Great Bay Bridge (the heightmap already contains the inlet; `floor_z` is the seabed along the centre line).

## 8. Reading the data (examples)

```python
import numpy as np, json
H = np.fromfile("heightmap_4033.r16", dtype="<u2").reshape(4033, 4033)       # H[j, i]
Z = (H.astype(np.float32) - 32768) * 300 / 128 / 100                          # metres
def z_at(X, Y):                                                                # nearest vertex
    return Z[int(round(Y)) + 2016, int(round(X)) + 2016]
roads = json.load(open("roads.json"))["roads"]
r = next(r for r in roads if r["id"] == "HWY_EAST")
s, x, y, z, hdg, kap, bank, width, flags = np.array(r["samples"]).T
bridge = (flags.astype(int) & 1) > 0
```

## 9. `road_metrics.json` (acceptance numbers of the build)

Keys: `total_length_km`, `length_km_by_class`, `loop_length_km`, `loop_closed`, `longest_uninterrupted_km` (+ `_road`), `hwy_east_length_km`, `grade_max_by_class`, `grade_p99_by_class`, `grade_limit_by_class`, `min_radius_by_class`, `min_radius_hairpin_by_class`, `min_radius_nonhairpin_by_class`, `network_components`, `junction_nodes`, `road_samples`, `samples_outside_1990`, `samples_terrain_below_0p5m_nonbridge`, `bridge_count` / `bridges` (`[length, road]`), `great_bay_bridge_length_m`, `tunnel_count` / `tunnels`, `hairpins_by_road`, `hairpins_pass`, `carve_*` (deviation between the finished terrain and the road bed: max, p99, share within 0.2 m, per-road maxima with the three worst locations), `gradient_near_roads_*`, `heightmap_min_m` / `heightmap_max_m`, `region_land_fraction`, `build_seconds_so_far`. The same numbers are printed as a PASS / FAIL table at the end of `build_world.py`.
