# ART_SPEC — Blender → Unity contract (single source of truth for all Blender work)

Project: original MudRunner-style off-road sim, Unity 6 URP. All 3D art is **authored by us through the Blender MCP**
(`mcp__blender-mudrunner-unity__*`, localhost:9891, master file `UnitySonnet5.5Mudrunner.blend` in the project root).
No Asset Store / Poly Haven / Sketchfab / AI generation / downloaded models. **Never call `search_assets`, `import_asset`, `generate_3d`.**
Original designs only, no real manufacturer names, logos or recognisable licensed vehicle designs.

## 0. Rules of engagement
* Only ONE agent talks to Blender at a time (the art pipeline). Work only in your asset collection; do not delete or modify other assets.
* Save the master file after every finished asset: `bpy.ops.wm.save_mainfile()`.
* Do not modify the Blender add-on, preferences or Safe Mode settings.
* Use `look` (angles / wireframe / material shading) to inspect your work. **An asset is not finished because a file exists**: it must look
  like a deliberate, reasonable, detailed game asset from every angle (no floating parts, no z-fighting, no inverted normals, no stray `Cube.001`).
* Prefer Python (bmesh / bpy) generators with helper functions; reuse `Tools/blender_helpers.py` (create it if it does not exist yet, test it,
  and extend it; load it inside Blender with `exec(open(r"<project>\Tools\blender_helpers.py", encoding="utf-8").read())`).

## 1. Units, axes, origin (VERIFIED with a Unity import test)
* 1 Blender unit = 1 metre, unit scale 1.0. Z up in Blender.
* **A vehicle's FRONT points toward Blender −Y** (it faces you in the numpad-1 "Front" view). Its **left side is Blender +X**, right side −X.
  Unity result of the export below: Unity(x, y, z) = (−Blender x, Blender z, −Blender y) → front = +Z, left = −X, right = +X, rotation 0, scale 1.
* Object origin of the asset root: on the ground plane (z = 0 = lowest point of the tyres at normal ride height), centred on the centre line (x = 0),
  y = 0 at the middle of the wheelbase. So hub centres are at z = tyre radius.
* Apply rotation and scale on every mesh before export (`bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)`); no negative scales (mirror by rotating a duplicate 180° about Z, then apply).
* Meshes: triangulation not required, but quads/tris only (no n-gons > 8), consistent outward normals, smooth shading with a sensible auto-smooth/edge angle (use shade smooth + split by angle ≈ 40°).
* **Every renderable mesh needs UVs** (Smart UV Project or hand unwrap; scale so a 1×1 texel density is consistent — ≈ 1 m of surface per UV unit for large panels is fine).

### Export recipe (use exactly this)
```python
bpy.ops.object.select_all(action='DESELECT')
for o in objs: o.select_set(True)          # all objects of the asset (meshes + empties + collision proxies)
bpy.ops.export_scene.fbx(filepath=out_path, use_selection=True, object_types={'MESH','EMPTY'},
    apply_scale_options='FBX_SCALE_ALL', global_scale=1.0, axis_forward='-Z', axis_up='Y',
    bake_space_transform=True, use_mesh_modifiers=True, mesh_smooth_type='FACE',
    add_leaf_bones=False, bake_anim=False, path_mode='STRIP', use_custom_props=False)
```
Write to a temp file first (`BlenderExports/_scratch/<name>.fbx`), then `shutil.move` it to the final path
`Assets/Game/Art/<Category>/<AssetName>/<AssetName>.fbx` (categories: Vehicles, Trailers, Props_Nature, Props_Structures, Cargo).
Do **not** create `.meta` files; Unity creates them.

## 2. Blender file organisation
```
MUDRUNNER_UNITY
 ├─ Vehicles          (one child collection per vehicle: Veh_Scout, Veh_Utility, Veh_Hauler)
 ├─ Trailers_Cargo    (Trl_LogTrailer, Cargo_*)
 ├─ Props_Nature      (Nat_Spruce, Nat_Rock_01 ...)
 ├─ Props_Structures  (Str_Cabin, Str_Bridge ...)
 └─ Collision         (COL_<Asset> collision proxies, one child collection per asset)
```
Each asset: a root Empty named exactly like the asset (`Scout`), children parented under it. Work with only your own asset collection
visible in the view layer (hide/exclude the others); every asset is modelled at the world origin.
No default names (`Cube`, `Cylinder.003`) may remain in an exported asset.

## 3. Materials (use ONLY these names; Unity remaps them to project materials with procedural textures)
Create each as a Principled BSDF material (base colour + roughness + metallic so the viewport looks right). Unity decides final look.
| name | use | base colour (sRGB) | rough | metal |
|---|---|---|---|---|
| MR_Paint | main body paint (Unity overrides colour per vehicle) | 0.55,0.42,0.18 | 0.5 | 0.1 |
| MR_PaintSecondary | secondary colour (bumpers, roof, stripes) | 0.15,0.15,0.15 | 0.55 | 0.1 |
| MR_MetalDark | frame, axles, springs, underbody | 0.10,0.10,0.11 | 0.6 | 0.8 |
| MR_MetalBright | machined / bright steel, rods, bolts | 0.55,0.56,0.58 | 0.35 | 1.0 |
| MR_Chrome | chrome trim | 0.8,0.8,0.82 | 0.12 | 1.0 |
| MR_Rust | rusty steel (old props) | 0.35,0.17,0.08 | 0.85 | 0.4 |
| MR_Rubber | tyres, mud flaps, hoses | 0.035,0.035,0.035 | 0.9 | 0 |
| MR_Rim | wheel rims | 0.2,0.2,0.2 | 0.5 | 0.9 |
| MR_Glass | windows | 0.2,0.28,0.3 (alpha 0.35) | 0.05 | 0 |
| MR_LightHead | headlight lens (emissive white) | 0.95,0.95,0.85 | 0.1 | 0 |
| MR_LightTail | tail/brake lens (emissive red) | 0.8,0.05,0.04 | 0.2 | 0 |
| MR_LightAmber | indicators/work light (amber) | 0.9,0.5,0.05 | 0.2 | 0 |
| MR_InteriorDark | dash, door cards, floor | 0.08,0.08,0.08 | 0.8 | 0 |
| MR_SeatFabric | seats | 0.14,0.12,0.09 | 0.95 | 0 |
| MR_PlasticBlack | bumper plastics, trims, grilles | 0.05,0.05,0.05 | 0.6 | 0 |
| MR_Cable | winch cable / chains | 0.3,0.3,0.32 | 0.5 | 0.9 |
| MR_Wood | planks, posts, log bunks | 0.42,0.28,0.15 | 0.85 | 0 |
| MR_Bark | tree trunks, logs | 0.22,0.15,0.1 | 0.95 | 0 |
| MR_LogEnd | cut log ends | 0.55,0.4,0.22 | 0.9 | 0 |
| MR_Foliage | needles / leaves | 0.1,0.25,0.08 | 0.9 | 0 |
| MR_Rock | rocks | 0.4,0.39,0.36 | 0.95 | 0 |
| MR_Moss | moss patches | 0.17,0.27,0.1 | 1.0 | 0 |
| MR_Concrete | concrete / plaster | 0.5,0.5,0.48 | 0.95 | 0 |
| MR_RoofMetal | corrugated roofs | 0.3,0.18,0.12 | 0.7 | 0.5 |
| MR_Hazard | hazard yellow/black, signs | 0.9,0.7,0.05 | 0.6 | 0 |
| MR_Canvas | tarps, tents | 0.35,0.38,0.25 | 0.95 | 0 |
| MR_Sand | – (reserved) | 0.6,0.52,0.35 | 1 | 0 |

## 4. Vehicles
All are **drivable physics bodies**; the Unity prefab builder discovers parts BY NAME. Required names (case-sensitive):

### 4.1 Required nodes
* `Chassis` — frame/underbody mesh (MR_MetalDark). Body panels may be separate objects (`Body_*`, `Cab`, `Bed`, `Hood`, `Bumper_F`, `Bumper_R`, `Roof`, `Fender_*`, `Doors`, `Snorkel`, `Winch`, `SpareWheel` …) — any names, parented under the root; join per material to keep the object count reasonable (< 60 mesh objects, < 120k tris total for the high LOD).
* Wheels: `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`; 6×6 adds `Wheel_ML`, `Wheel_MR` (naming F = front axle, M = middle, R = rear; L = vehicle left = Blender +X).
  Each wheel = ONE mesh object (tyre with tread blocks/sidewall lettering-free + rim with bolts + hub; 2–3 material slots: MR_Rubber, MR_Rim, MR_MetalBright),
  **origin exactly at the hub centre**, axle along the **X axis**, outer rim face toward the outside of the vehicle. Left and right wheels are NOT mirrored copies with negative scale
  (duplicate, rotate 180° about Z, apply). Real tread: 24–40 tread blocks around the circumference (mud-terrain lugs), visible sidewall bulge. ≤ 12k tris per wheel.
* Axles: `Axle_Front`, `Axle_Rear` (`Axle_Mid` for 6×6): the beam / differential housing / driveshaft stub as one object, **origin at the axle centre on the centre line at hub height**.
* Suspension (visible & articulating — the main show-off of this project):
  * Coil springs `Spring_<Axle>_<Side>` (e.g. `Spring_Front_L`): real helical coil mesh (6–9 turns), **origin at its upper (chassis-side) end**.
  * Shock absorbers: `Shock_<Axle>_<Side>_Body` (origin at upper mount, cylinder + reservoir/bracket) and `Shock_<Axle>_<Side>_Rod` (origin at lower mount, bright rod + lower eye).
  * Links/arms (control arms, trailing arms, panhard/track bar, steering tie rod, drag link): `Link_<Name>` mesh with **origin at the chassis-side pivot**, modelled along its length.
  * Leaf spring packs (heavy hauler): `Leaf_<Axle>_<Side>` origin at its centre bolt; bolted to the axle.
  * Markers (Empties, plain axes, size 0.05) in REST pose: `Mount_Spring_<Axle>_<Side>_Top`, `Mount_Spring_<Axle>_<Side>_Bot`, `Mount_Shock_<Axle>_<Side>_Top`, `Mount_Shock_<Axle>_<Side>_Bot`,
    `Mount_Link_<Name>_Body` (chassis end), `Mount_Link_<Name>_Axle` (axle end). `<Axle>` ∈ Front/Mid/Rear, `<Side>` ∈ L/R. Top = chassis side, Bot = axle side.
  * Wheel travel visible in the model: leave ≥ 0.2 m of clearance between tyre top and wheel arch; wheel arches must be large enough for ~0.45 m total wheel travel.
* `SteeringWheel` (origin at the hub of the wheel, axis = column direction), `Dash`, `Seat_Driver`, `Seat_Passenger`, interior (MR_InteriorDark/MR_SeatFabric) good enough for a cockpit camera (dashboard with gauges as simple geometry, A-pillars, mirrors).
* Lights as emissive mesh lenses: `Light_Head_L`, `Light_Head_R`, `Light_Tail_L`, `Light_Tail_R` (+ `Light_Work_*` on the roof for utility/hauler).
* Empties (plain axes) at the exact useful points: `Anchor_Winch` (fairlead/rope exit; for vehicles without winch: `Anchor_TowFront`), `Anchor_Hitch` (rear tow ball/pintle), `Cam_Cockpit` (driver eye point), `Intake` (top of snorkel/air intake — used for water-fording depth),
  `Exhaust`, `CargoOrigin` (centre of cargo deck/bed, on its surface), `Fuel_Cap`.
* Collision proxies (no render): box meshes (8 verts, name prefix `COL_`) e.g. `COL_Chassis`, `COL_Cab`, `COL_Bed`, `COL_Hood`; 3–6 boxes per vehicle, material none; they live in `Collision`.

### 4.2 Dimensions that MUST match the physics data (hub heights/axles/tyres are read from the model)
| | Scout | Utility | Hauler 6×6 |
|---|---|---|---|
| role | light 4×4 scout, nimble | mid-size utility truck, winch | heavy 6×6 hauler, big tyres |
| overall L × W × H (m) | 3.75 × 1.80 × 1.90 | 5.40 × 2.20 × 2.35 | 7.60 × 2.60 × 3.25 |
| axle positions y (Blender; front = −Y) | −1.25, +1.25 | −1.60, +1.50 | −2.40, +0.50, +2.00 |
| track (centre to centre of wheels) | 1.50 | 1.85 | 2.00 |
| tyre radius / width | 0.40 / 0.235 | 0.54 / 0.375 | 0.76 / 0.60 |
| hub height z | 0.40 | 0.54 | 0.76 |
| chassis underside clearance | 0.26 | 0.34 | 0.55 |
| mass (for scale sense) | 2.0 t | 4.2 t | 9.0 t |
| silhouette | short boxy open-back wagon, roll cage, flat hood, bull bar, spare on tail gate, round headlights, side snorkel | crew-cab pick-up with cargo box, winch bumper, snorkel, roof light bar, side steps | cab-forward heavy truck, flat deck with log bunks/stakes, tall exhaust stack, winch bumper, huge mud flaps, steps |
Axles z-order in the table are Blender y (front = −Y). Wheels must be centred at those y values exactly (±0.01).

### 4.3 Trailers (Trailers category)
Drawbar log trailer: 2 axles, same tyre family as the Utility, `Wheel_FL/FR/RL/RR`, `Axle_*`, leaf springs, drawbar with eye (`Anchor_Hitch_Front` empty), log bunks, `CargoOrigin`, `COL_*`. Length ≈ 6.5 m.

## 5. Props
* Nature: spruce tree (3 variants of the same species: tall/medium/young, ~14 / 10 / 5 m, trunk + branch whorls + foliage cards, ≤ 6k tris), birch or dead tree, bushes, reed clump, stump, fallen log (straight 6 m log, 2.2 m short log with cut ends and bark), 4 rock types (small 0.5 m, medium 1.2 m, large 2.5 m boulder, flat slab), moss patch card.
  Pivot at the base, origin on the ground at the centre. Trunks/rocks get `COL_` proxies (capsule-ish box/convex hull, ≤ 24 verts hull named `COL_<Asset>`).
* Structures: log cabin (porch, stone chimney, door, windows, roof — interior not needed), workshop/garage building with a roll door (the base camp), fuel station (two pumps + canopy + storage tank), watchtower (8 m), wooden plank bridge (intact 10 m span with railings, plus a broken/fragile variant missing planks), signposts (arrow sign, warning sign, route marker posts), fences, barrels, crates, pallets, tent, camp fire pit, concrete road barrier, winch anchor post (heavy timber post with an iron ring).
* All props: single mesh per material, ≤ 8k tris unless it is a hero building (≤ 25k), origin at base centre, `COL_` proxies for anything a vehicle can touch.
* LODs: provide `<Mesh>_LOD1` (≈ 45 % tris) and `<Mesh>_LOD2` (≈ 18 %) for vehicles (per major mesh, wheels included) and for trees/buildings, built with Decimate (collapse) then applied; same origin/naming rules. Trees additionally get a `<Name>_Billboard` quad (2 m wide aspect-correct) with UVs 0..1 for impostor use.

## 6. QA gate (every asset, in this order)
1. Build → 2. `look` from front / rear / left / right / top / three-quarter + wireframe/closeup of wheel and suspension → 3. fix everything that looks wrong, flat, floating, intersecting or placeholder-ish →
4. verify numbers with `get_scene_info` / bmesh (dimensions vs table, origin, apply-transform, names, UVs present, no n-gons, tri count) →
5. save master file → 6. export FBX (recipe above) → 7. print a one-line report: path, tris, object count, dimensions.
A separate reviewer will independently inspect the result with fresh eyes; expect to be sent a defect list and fix it.
