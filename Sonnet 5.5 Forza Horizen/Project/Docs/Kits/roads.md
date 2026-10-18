# Road kit (Blender -> Unreal): surfaces, junction pads, bridges, tunnels

Generated geometry of the whole road network (33 roads, 42.4 km) from `Tools/world/out/roads.json`: 183 chunks, 387 056 triangles. Pipeline, conventions and measured validation: `Docs/Tech/ROADS_PIPELINE.md`. Binding Blender rules: `Docs/BLENDER_CONTRACT.md` (collections `FORZA_UE/Roads`, `FORZA_UE/Bridges_Tunnels`; one idempotent script, `Tools/blender/world/build_roads.py`).

## 1. Chunks

| Kind | Prefix | Count | Triangles | Content |
|---|---|---|---|---|
| Surface | `RC_<ROAD>_<nn>` | 140 | 316 858 (251 .. 6 580 per chunk) | 300-420 m of one road: slab with shoulders, curbs / kerbs, median barrier (HIGHWAY), bevel skirt, flat underside; free ends capped |
| Junction pad | `RJ_<NODE>` | 27 | 31 282 | trimmed arm ends + Bezier fillets, polar-grid surface draped over the terrain, skirt, stop / give-way lines |
| Bridge | `RB_<ROAD>_<nn>` | 14 (11 bridges) | 30 684 | deck + parapet bases + piers + abutments (+ pylons and cables on Great Bay) |
| Tunnel | `RT_<ROAD>_<nn>` | 2 | 8 232 | floor, liner, shell, light strips, two portal head-walls |

Origin of every mesh = centre of its bounding box; `Exports/Roads/chunks.json` has `centre_ue_m` (UE metres) and `bounds_ue_m` for each; UE actor location = centre x 100 cm, no rotation. FBX: `Exports/Roads/<chunk id>.fbx` (Blender -> UE axes via `Tools/blender/lib/fbx_export.py`, Y flipped back). One mesh object and one static mesh per chunk.

## 2. Surface cross-sections (dimensions from roads.json, metres)

| Class | Carriageway | Shoulder | Extras | Slots |
|---|---|---|---|---|
| HIGHWAY | 2 x 2 lanes x 3.6, median 1.0 | 2.5 asphalt | New-Jersey barrier 0.80 high in the median | Asphalt, Concrete |
| REGIONAL | 2 x 3.4 asphalt | 1.2 gravel | flush concrete curb strip 0.30 | Asphalt, Gravel, Curb, Dirt |
| MOUNTAIN | 2 x 3.2 asphalt | 1.0 gravel | - | Asphalt, Gravel, Dirt |
| VILLAGE | 2 x 2.9 asphalt | 1.0 concrete pavement at +0.12 | raised kerb (15 cm top) | Asphalt, Concrete, Curb, Dirt |
| DIRT | 2 x 2.8 gravel | 0.6 dirt | - | Gravel, Dirt |

All: cross fall 12-16 mm, 0.30 m slab thickness with a 0.30 m 45 degree bevel, top surface >= 2.8 cm above the carved terrain bed, centre line = profile z (0 mm deviation by construction, 3.7 mm worst ray-cast deviation on the real meshes).

## 3. Structures

| Bridge | Style | s range | Length m | Supports |
|---|---|---|---|---|
| HWY_EAST (Great Bay Bridge) | cable-stayed | 4964 .. 5386 | 421.9 | 2 pylons (44 m above the deck, A-frame), 56 cables, 6 approach piers, 2 abutments |
| DIRT_WASH | box girder | 1684 .. 2036 | 352 | 12 piers (2 chunks) |
| DIRT_DUST | box girder | 601 .. 675, 795 .. 1067 | 74, 272 | 2 + 9 piers (the long one in 2 chunks) |
| BASIN_ROAD | box / slab | 1621 .. 1753 / 957 .. 999 | 132 / 42 | 4 / 1 |
| LOOP_DESC | box | 5247 .. 5311 | 64 | 1 |
| LOOP_VALLEY | box / slab | 2109 .. 2165 / 1405 .. 1441 | 56 / 36 | 1 / 1 |
| PASS_SPUR | box | 3467 .. 3509 | 42 | 1 |
| CASTLE_ROAD | slab | 499 .. 537 | 38 | 1 |

Parapet base: 0.45 m wide, 0.55 m above the deck surface, centre at +-(B + 0.225). Piers stand on the heightmap (feet sunk 1.4 m below the lowest terrain point under the footprint).

| Tunnel | Run in roads.json | Built (hillside closes over the road) | Clear height | Lamps |
|---|---|---|---|---|
| LOOP_DESC | 166 .. 416 | 209 .. 371 (162 m) | 5.9 m, half width 5.1 m | 26 (positions in the manifest) |
| PASS_SPUR | 3613 .. 3729 | 3655.8 .. 3685.8 (30 m) | 5.9 m, half width 5.1 m | 4 |

Landscape visibility holes are required at the 4 tunnel mouths (5.0-5.5 m x 11.4 m rectangles, listed per tunnel chunk and at the top level of `chunks.json`) and at the bridge ends, where the natural terrain (not carved under bridge runs) stands up to 0.7 m above the deck (`deck_buried` per bridge chunk): 1 637 heightmap vertices in `chunks.json -> landscape_hole_vertices`; `Tools/blender/world/make_hole_mask.py` writes them as a 4033 x 4033 raster. A carve change in `Tools/world/carve.py` would make the bridge-end holes unnecessary.

## 4. Materials / UV

Slots: `M_Road_Asphalt`, `M_Road_Concrete`, `M_Road_Dirt`, `M_Road_Gravel`, `M_Curb`, `M_Bridge_Concrete`, `M_Bridge_Steel`, `M_Tunnel_Wall`, `M_Tunnel_Light` (contract list) and `M_Road_Marking` (stop / give-way line geometry). UE binds `MI_<name>` in `/Game/Forza/Materials/Roads` by slot name (fallback instances are created when missing).

UV0 = (u across, s/10); UV1 = (lateral metres, s metres); UV2 = (paved half width, lane width) (0 on pads); UV3 = (median width, zone). Structures: metric box projection. Details: pipeline doc section 3.

## 5. Collision / import

Complex as simple (render triangles), Nanite on, collision profile `RoamWorldStatic`, no hulls. `Tools/ue/import_roads.py` (not run yet) imports all chunks, binds materials, spawns the actors (tags `RoamRoad`, `RoamDrivable`, `RoamRoadChunk:<id>`; spatially loaded = False).
