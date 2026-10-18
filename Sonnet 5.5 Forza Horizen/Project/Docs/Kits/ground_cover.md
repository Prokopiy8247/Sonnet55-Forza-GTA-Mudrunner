# Ground cover kit (bushes, rocks, cliffs, cacti, grass, crops, wood, beach props)

Generator: `Tools/blender/nature/ground_cover.py` (+ `gc_lib.py`, `gc_rocks.py`, `gc_plants.py`, `gc_misc.py`), idempotent, runs in the shared Blender 5.2 session. Docs generator: `Tools/blender/nature/make_ground_cover_doc.py`.
Exports: `Exports/Nature/Cover/<id>.fbx` + `<id>.json` (one FBX per asset, `fbx_export.export_fbx(..., center_on="self")`, UCX hulls included, pivots = base centre at ground). Machine-readable QA: `Exports/Nature/Cover/validation_report.json`.

Staging in the master .blend: collection `FORZA_UE/Nature/Cover`, row y = 60 m, starting x = 1200 m (tree row occupies x = 400..1100), assets spaced by footprint.

42 assets, 114335 tris in total. All assets: origin = base centre on the ground (z = 0, rocks sunk 3-5 cm), +Z up, +X front, transforms applied, UVMap present, vertex colour `Col` present.

## Conventions

* Vertex colour `Col` (FBX exported LINEAR): **R** = flex (0 at root / ground, 1 at tips and outer shell), **G** = flutter (0 stem, 1 free leaf/blade tips), **B** = baked AO-like occlusion (1 = open), **A** = per-element random 0-1 (hue / phase variation per leaf, blade or flower). Rocks/cliffs/wood: only B (AO) is meaningful.
* Foliage (`wind: true` in the JSON) is modelled geometry (leaf shapes, blades, petals) - no alpha cards needed, Nanite friendly; use **two-sided** materials for leaves, blades and petals. Tufts/blades have no custom normals (smooth by face).
* UVs: foliage elements map 0-1 per leaf/blade (u across, v along); rocks, bales and bark use box projection at 2 m per UV unit (tiling textures); no atlas.
* Collision: `UCX_<id>_NN` convex hulls (<= 24 verts, verified convex) for solid assets only (rocks, cliffs, cacti trunks, bales, logs, stump, pole, sign post). No collision on foliage, grass, flowers, reeds, crops, towel. UE: Collision Complexity = Use Simple As Complex.
* Materials (Blender names = UE material instance names): `M_Rock`, `M_Rock_Slate`, `M_Rock_Sandstone`, `M_Rock_SandstoneDark`, `M_Rock_Beach`, `M_Bush_Leaf`, `M_Bush_Leaf_Evergreen`, `M_Bush_Dry`, `M_Bush_Berry`, `M_Wood_Log`, `M_Wood_LogEnd`, `M_Wood_Plank`, `M_Cactus`, `M_Cactus_Spine`, `M_Cactus_Fruit`, `M_Grass_Blade`, `M_Grass_Dry`, `M_Reed`, `M_Reed_Head`, `M_Flower`, `M_Flower_B`, `M_Flower_Center`, `M_Crop`, `M_Crop_Ear`, `M_Crop_Soil`, `M_Hay`, `M_Hay_Twine`, `M_Beach_Red/White/Blue/Metal`, `M_Sand`, `M_Sign_Paint`, `M_Metal_Galv`. Max 4 slots per asset. Blender previews use procedural noise tints x vertex AO; UE recreates them by name.

## Bushes and shrubs

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_bush_leafy_a` | 1.76 x 1.60 x 1.34 | 5510 | `M_Wood_Log`, `M_Bush_Leaf` | none | 0.8-1.4 | temperate, forest, meadow, farmland, park |
| `nat_bush_leafy_b` | 1.20 x 1.19 x 1.88 | 5625 | `M_Wood_Log`, `M_Bush_Leaf` | none | 0.8-1.3 | temperate, forest, meadow, farmland, park |
| `nat_bush_leafy_c` | 2.21 x 2.09 x 1.05 | 5315 | `M_Wood_Log`, `M_Bush_Leaf`, `M_Bush_Berry` | none | 0.8-1.4 | temperate, forest, meadow, farmland, park |
| `nat_shrub_evergreen_a` | 1.47 x 1.56 x 1.12 | 4340 | `M_Wood_Log`, `M_Bush_Leaf_Evergreen` | none | 0.8-1.4 | temperate, mediterranean, urban, park |
| `nat_shrub_evergreen_b` | 1.51 x 1.42 x 1.81 | 2946 | `M_Wood_Log`, `M_Bush_Leaf_Evergreen` | none | 0.8-1.5 | alpine, highland, mediterranean, park |
| `nat_bush_tumble` | 0.97 x 1.01 x 0.89 | 3806 | `M_Bush_Dry` | none | 0.7-1.5 | desert, steppe, badlands, savanna |

* `nat_bush_leafy_a` - Leafy bush - round mound. no collision (foliage / decoration)
* `nat_bush_leafy_b` - Leafy bush - tall vase shrub. no collision (foliage / decoration)
* `nat_bush_leafy_c` - Leafy bush - low spreading with berries. no collision (foliage / decoration)
* `nat_shrub_evergreen_a` - Evergreen shrub - dense dome (boxwood). no collision (foliage / decoration)
* `nat_shrub_evergreen_b` - Evergreen shrub - conical juniper. no collision (foliage / decoration)
* `nat_bush_tumble` - Dry tumble scrub bush. no collision (foliage / decoration)

## Rocks - granite boulders (rounded)

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_rock_granite_a` | 2.39 x 2.13 x 1.70 | 1280 | `M_Rock` | 1 x UCX | 0.7-1.6 | temperate, forest, highland, meadow |
| `nat_rock_granite_b` | 4.69 x 3.19 x 2.20 | 2880 | `M_Rock` | 3 x UCX | 0.7-1.4 | temperate, forest, highland, meadow |
| `nat_rock_granite_c` | 3.87 x 2.86 x 1.10 | 1600 | `M_Rock` | 2 x UCX | 0.7-1.5 | temperate, highland, meadow, coast |

* `nat_rock_granite_a` - Granite boulder - single rounded. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_granite_b` - Granite boulder - cluster of three. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_granite_c` - Granite slab - flat topped. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex

## Rocks - jagged mountain rocks

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_rock_jagged_a` | 2.41 x 2.04 x 3.80 | 5120 | `M_Rock_Slate` | 1 x UCX | 0.7-1.5 | alpine, highland, mountain |
| `nat_rock_jagged_b` | 6.77 x 4.48 x 2.60 | 7680 | `M_Rock_Slate` | 3 x UCX | 0.7-1.4 | alpine, highland, mountain |
| `nat_rock_jagged_c` | 4.15 x 2.84 x 2.40 | 6400 | `M_Rock_Slate` | 2 x UCX | 0.7-1.5 | alpine, highland, mountain |

* `nat_rock_jagged_a` - Mountain rock - tall spire. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_jagged_b` - Mountain rock - broad outcrop with satellites. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_jagged_c` - Mountain rock - leaning wedge. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex

## Rocks - sandstone mesa chunks (real strata geometry, 2 materials)

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_rock_mesa_a` | 5.84 x 4.39 x 3.69 | 2448 | `M_Rock_Sandstone`, `M_Rock_SandstoneDark` | 1 x UCX | 0.8-1.5 | desert, canyon, badlands |
| `nat_rock_mesa_b` | 3.55 x 2.95 x 6.12 | 2560 | `M_Rock_Sandstone`, `M_Rock_SandstoneDark` | 1 x UCX | 0.8-1.4 | desert, canyon, badlands |
| `nat_rock_mesa_c` | 7.49 x 6.47 x 3.50 | 3944 | `M_Rock_Sandstone`, `M_Rock_SandstoneDark` | 3 x UCX | 0.8-1.4 | desert, canyon, badlands |

* `nat_rock_mesa_a` - Sandstone mesa chunk - blocky. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_mesa_b` - Sandstone butte - caprock spire. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_mesa_c` - Sandstone terrace cluster - stepped. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex

## Rocks - coast / beach rocks

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_rock_coast_a` | 2.52 x 1.53 x 0.80 | 1920 | `M_Rock_Beach` | 3 x UCX | 0.7-1.6 | coast, beach, riverside |
| `nat_rock_coast_b` | 2.12 x 1.82 x 0.55 | 1920 | `M_Rock_Beach` | 3 x UCX | 0.7-1.6 | coast, beach, riverside |
| `nat_rock_coast_c` | 2.36 x 2.27 x 0.70 | 2560 | `M_Rock_Beach` | 5 x UCX | 0.7-1.6 | coast, beach, riverside |

* `nat_rock_coast_a` - Coast rocks - pebble trio. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_coast_b` - Coast rocks - tilted slab with stones. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_rock_coast_c` - Coast rocks - tidal fragments. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex

## Cliff formations (canyon + coast)

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_cliff_canyon_a` | 14.00 x 7.01 x 12.73 | 8376 | `M_Rock_Sandstone`, `M_Rock_SandstoneDark` | 4 x UCX | 0.8-1.3 | desert, canyon, badlands |
| `nat_cliff_coast_b` | 11.98 x 7.58 x 10.20 | 9624 | `M_Rock`, `M_Rock_Beach` | 5 x UCX | 0.8-1.3 | coast, beach, highland |

* `nat_cliff_canyon_a` - Canyon cliff wall - layered sandstone. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex
* `nat_cliff_coast_b` - Coastal cliff - tilted strata with sea stack. UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex

## Cacti

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_cactus_saguaro_a` | 0.98 x 2.20 x 4.92 | 2480 | `M_Cactus`, `M_Cactus_Spine` | 1 x UCX | 0.8-1.3 | desert, canyon, badlands, savanna |
| `nat_cactus_saguaro_b` | 2.46 x 1.42 x 6.02 | 3168 | `M_Cactus`, `M_Cactus_Spine` | 1 x UCX | 0.8-1.3 | desert, canyon, badlands, savanna |
| `nat_cactus_barrel` | 0.75 x 0.74 x 0.56 | 1092 | `M_Cactus`, `M_Cactus_Spine`, `M_Cactus_Fruit`, `M_Flower_Center` | 1 x UCX | 0.7-1.6 | desert, canyon, badlands, savanna |
| `nat_cactus_pricklypear` | 1.03 x 1.09 x 1.17 | 1640 | `M_Cactus`, `M_Cactus_Spine`, `M_Cactus_Fruit` | 1 x UCX | 0.7-1.5 | desert, canyon, badlands, savanna, mediterranean |

* `nat_cactus_saguaro_a` - Saguaro cactus - two arms. UCX_01: single convex hull around the trunk + arm roots (arms/tips have no collision). UE: Simple As Complex
* `nat_cactus_saguaro_b` - Saguaro cactus - tall three arms. UCX_01: single convex hull around the trunk + arm roots (arms/tips have no collision). UE: Simple As Complex
* `nat_cactus_barrel` - Barrel cactus with crown flowers. UCX_01 single hull
* `nat_cactus_pricklypear` - Prickly pear cactus cluster. UCX_01 single hull

## Grass, flowers, reeds

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_grass_lush` | 0.90 x 0.93 x 0.46 | 550 | `M_Grass_Blade` | none | 0.7-1.6 | temperate, forest, meadow, farmland, park, riverside |
| `nat_grass_dry` | 0.92 x 0.93 x 0.70 | 569 | `M_Grass_Dry` | none | 0.7-1.6 | desert, steppe, savanna, badlands |
| `nat_grass_reeds_tall` | 1.30 x 1.25 x 1.56 | 550 | `M_Reed`, `M_Grass_Dry` | none | 0.7-1.4 | riverside, wetland, meadow, coast |
| `nat_flowers_a` | 1.13 x 1.12 x 0.44 | 641 | `M_Grass_Blade`, `M_Flower_Center`, `M_Flower` | none | 0.8-1.6 | temperate, forest, meadow, farmland, park |
| `nat_flowers_b` | 1.19 x 1.05 x 0.52 | 479 | `M_Grass_Blade`, `M_Flower_Center`, `M_Flower_B` | none | 0.8-1.6 | temperate, forest, meadow, farmland, park, highland |
| `nat_reeds_a` | 1.92 x 1.92 x 1.63 | 843 | `M_Reed`, `M_Reed_Head` | none | 0.8-1.5 | riverside, wetland, coast |
| `nat_reeds_b` | 2.21 x 1.83 x 1.70 | 564 | `M_Reed`, `M_Reed_Head` | none | 0.8-1.5 | riverside, wetland, coast |

* `nat_grass_lush` - Grass tuft - lush. no collision (foliage / decoration)
* `nat_grass_dry` - Grass tuft - dry. no collision (foliage / decoration)
* `nat_grass_reeds_tall` - Tall reed grass 1.5 m. no collision (foliage / decoration)
* `nat_flowers_a` - Flower patch - white daisies. no collision (foliage / decoration)
* `nat_flowers_b` - Flower patch - purple wildflowers. no collision (foliage / decoration)
* `nat_reeds_a` - Reed clump - cattails. no collision (foliage / decoration)
* `nat_reeds_b` - Reed clump - sedge with plumes. no collision (foliage / decoration)

## Farm: crops and hay

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_crop_wheat_row` | 4.64 x 1.34 x 1.15 | 5088 | `M_Crop_Soil`, `M_Crop`, `M_Crop_Ear` | none | 0.9-1.2 | farmland, temperate, meadow |
| `nat_hay_round` | 1.72 x 1.21 x 1.72 | 1856 | `M_Hay`, `M_Hay_Twine` | 1 x UCX | 0.8-1.3 | farmland, temperate, meadow |
| `nat_hay_stack` | 0.99 x 2.77 x 1.11 | 3792 | `M_Hay`, `M_Hay_Twine` | 1 x UCX | 0.8-1.3 | farmland, temperate, meadow |

* `nat_crop_wheat_row` - Wheat crop row segment 4 m. no collision (foliage / decoration)
* `nat_hay_round` - Round hay bale. UCX_01 12-sided cylinder hull. UE: Simple As Complex
* `nat_hay_stack` - Stacked square hay bales (pyramid 3-2-1, two deep). UCX_01 single hull around the stack

## Wood

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_logpile` | 1.81 x 2.30 x 1.34 | 1120 | `M_Wood_Log`, `M_Wood_LogEnd` | 1 x UCX | 0.8-1.3 | forest, temperate, farmland, highland |
| `nat_log_fallen` | 4.92 x 1.26 x 1.12 | 612 | `M_Wood_Log`, `M_Wood_LogEnd` | 3 x UCX | 0.7-1.4 | forest, temperate, highland, wetland |
| `nat_stump` | 1.22 x 1.22 x 0.77 | 440 | `M_Wood_Log`, `M_Wood_LogEnd` | 1 x UCX | 0.7-1.5 | forest, temperate, highland, farmland |

* `nat_logpile` - Log pile (14 logs). UCX_01 single hull around the pile
* `nat_log_fallen` - Fallen log with broken end. UCX_01..03 three hulls along the trunk (stubs ignored)
* `nat_stump` - Tree stump with growth rings. UCX_01 single hull

## Beach props and signage

| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |
|---|---|---|---|---|---|---|
| `nat_beach_umbrella` | 2.29 x 2.30 x 2.64 | 680 | `M_Beach_Metal`, `M_Beach_Red`, `M_Beach_White` | 1 x UCX | 0.9-1.2 | coast, beach |
| `nat_beach_lounger` | 1.78 x 0.71 x 0.91 | 336 | `M_Wood_Plank`, `M_Beach_Blue` | 2 x UCX | 0.9-1.2 | coast, beach |
| `nat_beach_towel_ball` | 2.40 x 0.80 x 0.40 | 944 | `M_Beach_Red`, `M_Beach_White`, `M_Beach_Blue` | 1 x UCX | 0.9-1.2 | coast, beach |
| `nat_beach_bucket` | 0.95 x 0.52 x 0.36 | 952 | `M_Beach_Blue`, `M_Sand`, `M_Beach_Metal`, `M_Beach_Red` | 2 x UCX | 0.9-1.3 | coast, beach |
| `nat_sign_arrow` | 0.17 x 1.00 x 2.16 | 85 | `M_Wood_Plank`, `M_Sign_Paint`, `M_Metal_Galv` | 1 x UCX | 0.8-1.3 | temperate, farmland, forest, highland, coast |

* `nat_beach_umbrella` - Beach umbrella (striped, tilted). UCX_01 pole only (canopy has no collision)
* `nat_beach_lounger` - Wooden sun lounger. UCX_01 seat, UCX_02 backrest
* `nat_beach_towel_ball` - Beach towel and ball. UCX_01 ball only (towel is walkable decoration)
* `nat_beach_bucket` - Beach bucket, spade and sandcastle. UCX_01 bucket, UCX_02 sandcastle
* `nat_sign_arrow` - Wooden arrow sign post 2 m. UCX_01 post box (board has no collision)

## Recommended UE usage

* Rocks / cliffs: static meshes with Nanite ON, Use Simple As Complex, random yaw, scale within the listed range (non-uniform scale up to +-10 % for variety), sink 5-20 cm into terrain. Use `M_Rock*` instances with a rock tiling texture; the Blender previews only carry procedural tints.
* Bushes / grass / flowers / reeds / wheat: foliage-actor or PCG instances, no collision, two-sided foliage material, WPO driven by `Col`: sway = R^2 * low-frequency wind, flutter = G * high-frequency noise, darken by lerp(0.35, 1, B), hue-shift by A. Cull distance ~60-120 m (grass tufts ~40 m); no far-card impostors were generated for this group (bushes/grass are cheap modelled geometry; see weaknesses).
* `nat_crop_wheat_row`: 4.0 m tileable along +X (origin at the start of the row centreline) - place end to end with 0.9-1.1 m row spacing; rotate around Z per field.
* Cliffs: place as hero kit pieces at canyon walls and coast; combine 2-3 copies with different yaw/mirroring and blend the base with terrain/scatter rocks. Origin = footprint centre, cliff face toward -Y.
* Beach props: static meshes without Nanite requirements; umbrella collision is the pole only.

## Known weaknesses

* Granite and coast rocks are smooth soft-polyhedra (fbm + weathering cracks), good at game distance but they rely on the UE rock material/normal map for micro detail; they are flat-bottomed and expect partial burial.
* Cliff faces are a heightfield-style shell (48 x 30 grid per side) with two strata materials: at close range the quad faceting shows; they have no overhang caves and a simple closed back. Scree stones are small separate lumps without collision.
* Bushes: single-sided oriented leaves (4 tris each) read well from > 3 m; close-ups show uniform leaf shapes. Twigs are thin 4-5 sided tubes. No far-LOD card meshes (`_Far`) were produced; rely on Nanite/foliage culling or add impostors later.
* Grass/reeds are flat blade strips (3-5 segments) without custom up-normals; very dense scattering will need LOD/culling. Flower petals are flat quads with a slight cup.
* Cacti spines are tiny tri fans on rib crests (visible only < 5 m); saguaro arms do not collide. Prickly pear pads are simple discs.
* Wood: bark is geometry noise + procedural material only; log end rings are a material tint, not carved geometry (the stump top has modelled growth-ring steps).
* Text on the sign post is not modelled (arrow glyph only). Beach towel is a single sheet (no thickness). Sandcastle is a simple stylised cluster.
* Not individually hand-iterated 3x per asset (speed brief): one build + one visual pass per family; remaining polish candidates: cliff overhangs, rock moss/lichen masks (use vertex colour B), per-leaf normal bending for bushes.
