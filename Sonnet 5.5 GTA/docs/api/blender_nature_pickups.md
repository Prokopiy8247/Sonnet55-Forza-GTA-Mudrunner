# Blender lane 10 - Nature, pickups, scuba / parachute items

Authored in Blender through MCP, exported with `gta_lib.export_glb`. Build scripts (idempotent, `clear_asset` first) live in `tools/blender/lane10_*.py`
(`lane10_lib.py` = helpers/materials, `lane10_trees_a|b.py`, `lane10_small_a|b|c.py`, `lane10_pickups_a|b.py`); the objects stay in the master `.blend`
under `GTA_GODOT/Nature` (nature) and `GTA_GODOT/VFX_HelperMeshes` (pickups / items). Workshop slots: `workshop(10, i, 14)`.

All models: origin = base centre on the ground (pickups: base centre of the item), front = +Y Blender = -Z Godot, metres, flat shaded, colours only (named materials).
Every GLB root has the contract nodes below as direct children (`<id>__` prefix stripped). Triangle counts are real (probe-verified in Godot).

## Nature (`res://gta/generated/models/nature/<id>.glb`)

| id | size m (x, z, h) | tris | nodes | notes |
|---|---|---|---|---|
| palm_a | 5.9 x 6.3 x 9.1 | 427 | `Trunk`, `Canopy` | curved coconut palm, trunk leans +X (crown at x=1.2, y=7.4) |
| palm_b | 6.9 x 6.9 x 9.4 | 422 | `Trunk`, `Canopy` | straight royal palm, green crownshaft, `Accent` date clusters |
| tree_oak_a | 8.2 x 6.0 x 8.8 | 425 | `Trunk`, `Canopy` | round 3-tone canopy |
| tree_oak_b | 9.5 x 7.8 x 10.1 | 438 | `Trunk`, `Canopy` | taller, wider, buttress roots |
| tree_pine_a | 4.3 x 4.4 x 10.1 | 128 | `Trunk`, `Canopy` | 6 star-faceted tiers |
| tree_pine_b | 4.0 x 4.6 x 12.1 | 226 | `Trunk`, `Canopy` | slim spruce, 7 concave tiers |
| tree_birch | 3.5 x 3.3 x 9.0 | 312 | `Trunk`, `Canopy` | white trunk (`BirchWhite`/`BarkDark` bands), yellow-green crown |
| tree_dead | 4.7 x 3.3 x 7.1 | 257 | `Trunk`, `Canopy` | bare limbs in `Trunk`, fine twigs in `Canopy` |
| `<tree>_lod` (palm_a, palm_b, tree_oak_a, tree_oak_b, tree_pine_a, tree_pine_b, tree_birch) | same silhouette | 45-60 | `Body` | impostor mesh for far range (swap `<id>` -> `<id>_lod`) |
| bush_a | 2.3 x 1.7 x 1.2 | 200 | `Body` | low round shrub |
| bush_b | 2.1 x 2.0 x 1.4 | 190 | `Body` | spiky leafy shrub (agave look) |
| bush_c | 2.1 x 1.6 x 1.4 | 332 | `Body` | flowering, `Accent` + `FlowerPink` blossoms |
| hedge_segment | 3.0 x 0.9 x 1.2 | 116 | `Body` | runs along X, tile every 3.0 m |
| rock_a | 1.8 x 1.3 x 0.9 | 100 | `Body` | |
| rock_b | 1.9 x 1.5 x 0.6 | 120 | `Body` | flat slab + pebbles |
| rock_c | 1.5 x 1.0 x 1.4 | 100 | `Body` | tall angular chunk |
| rock_d | 1.6 x 1.3 x 0.6 | 200 | `Body` | cluster of 4 |
| boulder_large | 4.8 x 3.5 x 2.9 | 180 | `Body` | mossy cap (`Leaf` faces on top) |
| cliff_chunk | 7.3 x 3.7 x 5.5 | 228 | `Body` | layered strata, grass top, flatter +Y face |
| grass_tuft | 0.7 x 0.7 x 0.6 | 66 | `Body` | radial blade ribbons, double sided |
| flower_patch | 1.0 x 1.0 x 0.6 | 230 | `Body` | 9 flowers (Accent/FlowerPink/White/Blue/Yellow) on a leaf mound |
| reeds | 0.9 x 0.9 x 2.0 | 147 | `Body` | 18 blades + 3 cattails |
| log | 1.4 x 2.3 x 0.7 | 198 | `Body` | lies along Y |
| stump | 1.5 x 1.5 x 0.7 | 154 | `Body` | cut ring face on top |
| driftwood | 1.9 x 1.2 x 1.0 | 113 | `Body` | beach prop |
| shell | 0.6 x 0.3 x 0.1 | 120 | `Body` | two scallops + a whelk, beach prop |
| sand_dune_patch | 4.8 x 3.2 x 0.8 | 121 | `Body` | low mound with grass blades |

**Sway contract (trees):** `Trunk` and `Canopy` are separate meshes. The `Canopy` node's origin sits at the trunk/crown attach point
(palm_a (1.2, 7.4), palm_b crown top, oak_a z=3.0, oak_b z=3.4, pine_a z=1.6, pine_b z=1.8, birch z=4.0, dead z=3.5), so a small rotation of `Canopy`
(or a vertex-shader sway keyed to `VERTEX.y` relative to that node) never detaches it from the trunk. Trunk collision is not baked: use a thin capsule
of radius ~0.3 (oak/palm), 0.25 (pine), 0.2 (birch) at the origin.

Nature materials: STD `Leaf`, `LeafLight`, `Bark`, `Accent` + lane-10 customs `LeafDeep`, `LeafYellow`, `PalmLeaf`, `PalmLeafLt`, `BarkPale`,
`BarkMid`, `BarkDark`, `BirchWhite`, `RockPale`, `RockMid`, `RockShade`, `DuneSand`, `SandWet`, `WoodCut`, `Wood`, `Flower*`, `Reed*`, `CattailBrown`, `Shell*`.
Godot may re-tint by name (e.g. seasonal `Leaf`/`LeafLight`).

## Pickups & items (`res://gta/generated/models/props/<id>.glb`, single `Body` mesh, emissive `Pickup*` surfaces for night readability)

| id | size m (x, y(height), z(depth)) | tris | emissive material | notes |
|---|---|---|---|---|
| pickup_cash | 0.56 x 0.25 x 0.52 | 240 | `PickupGreen` (band under the $ glyph) | 5 banknote bundles + loose notes |
| pickup_health | 0.38 x 0.32 x 0.18 | 220 | `PickupRed` | white medkit, red cross on both faces |
| pickup_armor | 0.46 x 0.50 x 0.18 | 288 | `PickupBlue` | vest, shield icon on the +Y (front) plate, glowing hem |
| pickup_ammo | 0.39 x 0.39 x 0.22 | 234 | `PickupAmber` | olive ammo crate + 3 brass rounds on the lid |
| pickup_weapon | 0.51 x 0.27 x 0.31 | 260 | `PickupCyan` | steel crate, glowing pistol badge front and back |
| pickup_parachute | 0.34 x 0.50 x 0.23 | 260 | `PickupAmber`, `PickupRed` | backpack with emblem on +Y, straps on -Y, red ripcord |
| scuba_tank | 0.25 x 0.72 x 0.28 | 300 | `PickupCyan` band + gauge | tank 0.64 m + valve/regulator/hose (0.72 m total) |
| scuba_gear | 0.28 x 0.72 x 0.33 | 318 | `PickupCyan` band, `MaskLens` | tank + hanging mask (+Y side) + snorkel |
| parachute_pack | 0.41 x 0.49 x 0.32 | 208 | none | WORN variant, see below; node `Attach` |
| parachute_canopy | 7.1 x 7.5 x 7.5 | 370 | none | deployed canopy, see below; nodes `Body`, `Lines`, `Attach` |
| life_vest | 0.45 x 0.58 x 0.25 | 286 | `Reflective` strips (weak glow) | orange horse-collar vest |

Pickups are modelled on the ground at origin; the game floats/spins them (spin around Y; the glowing emblem is on +Y and on -Y for pickup_weapon/cash/health).
Godot can multiply the emission of the `Pickup*` materials by name (`PickupGreen/Red/Blue/Amber/Magenta/Cyan`) for pulsing.

**parachute_pack (worn)**: origin is the centre of the attachment plane (the face that touches the character's back). The pack extends to -Y (behind the
character, 0.17 m deep, 0.34 w x 0.44 h, vertically centred on the origin) and the two shoulder straps arc forward (+Y, up to y=0.13) over the shoulders and down the
chest (z -0.2). Place the node at the character's mid-back (about (0, -0.12, 1.22) in the character frame, i.e. the Chest bone's back) and scale 1.0.
`Attach` empty = origin.

**parachute_canopy (deployed)**: origin = harness attach point (the spreader bar at the bottom, `Attach`). Hem ring 4.6 m above the origin with radius 3.5 m, dome top
at 7.5 m, 10 gores alternating `CanopyA` (orange-coral) / `CanopyB` (cream), dark hem skirt (`Trim`), vent cap at the apex. `Lines` mesh = 10 thin suspension lines
(`LineCord`) -> 4 risers (`Strap`) -> 4 D-links (`Chrome`) + spreader bar (`Webbing`). Parent it to the player (offset so the player's hands/torso hang at `Attach`);
scale Y/XZ for the inflate animation (`Body`+`Lines` share the origin). Double sided materials.

## Visual QA / tests
`gta/tests/blender10_nature_showcase.gd` (shot helper): `$env:L10_SHOW="nature/palm_a,props/pickup_cash"; tools\gd.ps1 shot -Out screenshots\x.png -GameArgs "--exec=res://gta/tests/blender10_nature_showcase.gd --delay=4 --time=12"`
(env: `L10_YAW`, `L10_ZOOM`, `L10_GAP`, `L10_EMIT=1` for a night look).
