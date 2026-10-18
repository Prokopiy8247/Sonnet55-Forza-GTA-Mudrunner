# Blender lane 11 - vehicle customisation parts (`models/vehicle_parts/*.glb`)

30 modular GLBs for the garage / `VehicleBase.apply_mods` visual layer: **20 body parts + 10 wheel styles**, authored in Blender (collection `GTA_GODOT/Vehicles/Parts`, workshop slots lane 11, rebuilt by `tools/blender/lane11_*.py`, batch = `lane11_build_all.py`). All files: `res://gta/generated/models/vehicle_parts/<id>.glb`; machine-readable twin of this document: `res://gta/generated/models/vehicle_parts/parts_catalog.json` (parts, sedan mounts, per-vehicle fit transforms in Blender AND Godot axes).
Total 7 494 tris for all 30 files. Probe / contract test: `powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/vehicle_parts_probe.gd` (loads every GLB, checks nodes + budgets: parts <= 400 tris, wheels <= 500).

## 1. Conventions (read this first)
- **One part per GLB.** Node `Body` = the part mesh (one mesh, several surfaces = materials), empty `Mount` = the mount point and **also the GLB origin (0,0,0)**. Wheels: nodes `Tire` + `Rim` + `Mount`. A few wings carry an extra empty `Wing`.
- **Part frame = vehicle frame**: Blender +Y forward (becomes Godot **-Z**), +Z up, centred on X, metres, sized for the mid-size **sedan** (1.82 m wide, 4.77 m long, 1.45 m tall). The part ORIGIN is the point where the part touches the car (table in section 3: where z=0 is the panel surface, y=0 the front/rear face ...). So fitting = `part_node.transform = Transform3D(basis, position)` as a child of the vehicle root; no per-part offsets inside the mesh.
- **Axis conversion** (Blender -> Godot): position `(x, y, z) -> (x, z, -y)`; rotation about X (`pitch`, + = nose up) is identical; **scale `(sx, sy, sz) -> (sx, sz, sy)`** (Blender Y = length becomes Godot Z). Transform order T * R * S (scale in the part's local axes): `Basis(Vector3.RIGHT, deg_to_rad(pitch)).scaled_local(scale_godot)`.
- **Materials (runtime replace-by-name)**: `Paint` (body colour, `Util.replace_material(part, "Paint", mat)` or the vehicle's paint material), `Paint2` (secondary; dark default, spoiler blades / stripes / canards), `Trim`, `Chrome`, `Metal`, `MetalDark`, `Glass`, `LightHead` (fog lamps), `LightTail` (rear fog bar), `LampGlow` (light bar lamps, emissive), `NeonCyan` (underglow, emissive; **recolour by replacing / re-tinting the `NeonCyan` material**, the STD palette also has magenta `Neon`), `Tire`, `Rim` (wheel rim colour = `Rim` material; `Chrome` lip/hub stay chrome). Same material names as the vehicle GLBs, so one paint override covers car + parts.
- Origin Z of every roof / hood / deck part is the **panel surface**; bases sink 2-4 cm below z=0 on purpose (no gaps on crowned panels). Hard-edged, flat shaded; tyres smooth shaded (40 deg).
- Parts are **static** (no animation). Keep them in the vehicle's body node tree so they follow suspension roll / damage / hide with the car; for LOD simply hide parts beyond ~60 m.

```gdscript
# example: fit one part on a vehicle (sedan transform from parts_catalog.json)
func fit_part(vehicle: Node3D, id: String, fit: Dictionary) -> Node3D:
    var n := (load("res://gta/generated/models/vehicle_parts/%s.glb" % id) as PackedScene).instantiate() as Node3D
    var s: Array = fit["scale_godot"]; var p: Array = fit["pos_godot"]
    var b := Basis(Vector3.RIGHT, deg_to_rad(float(fit["pitch_deg"]))).scaled_local(Vector3(s[0], s[1], s[2]))
    n.transform = Transform3D(b, Vector3(p[0], p[1], p[2]))
    vehicle.add_child(n)
    return n
```

## 2. Body parts (20)
| id | tris | size X x Y x Z (m, Blender) | materials | origin / z=0 | what it is |
|---|---|---|---|---|---|
| `spoiler_lip` | 80 | 1.36 x 0.19 x 0.14 | Paint, Trim | centre of the footprint on the trunk lid; z=0 = lid top (ends droop 5 cm onto the crowned lid) | small blade on the rear edge of the boot lid |
| `spoiler_ducktail` | 148 | 1.52 x 0.38 x 0.24 | Paint, Paint2, Trim | centre of the footprint on the trunk lid; z=0 = lid top | kicked-up duck tail, wider at the tail than at the base, Paint2 insert |
| `spoiler_wing_low` | 160 | 1.53 x 0.38 x 0.31 | MetalDark, Paint, Paint2, Trim | centre of the footprint on the deck; z=0 = deck top (feet sink 2 cm) | GT wing on two struts (blade z 0.17..0.23); Paint2 blade, Paint end plates; extra empty `Wing` at the blade centre |
| `spoiler_wing_high` | 240 | 1.76 x 0.48 x 0.57 | MetalDark, Paint, Paint2, Trim | centre of the footprint on the deck; z=0 = deck top | two-element wing on swan-neck struts (blade z 0.34..0.46), tall Paint end plates; extra empty `Wing` |
| `splitter_front` | 96 | 1.64 x 0.33 x 0.10 | MetalDark, Paint2, Trim | centre of the plate top at the nose bottom; plate spans y -0.20..+0.13 (rear part hides under the bumper) | front lip with Paint2 edge and canards |
| `bumper_front_sport` | 260 | 1.72 x 0.42 x 0.28 | LightHead, Metal, Paint, Paint2, Trim | front face centre at the shell bottom (y=0 is the FRONT face, the shell extends 0.15..0.4 behind it, z 0..0.275) | shell ON the nose: slatted central intake, side intakes, fog lamps (LightHead), black chin lip |
| `bumper_rear_diffuser` | 136 | 1.44 x 0.35 x 0.21 | LightTail, MetalDark, Paint, Paint2, Trim | rear face of the valance at the bumper bottom (y=0; the valance is body coloured, the plate runs 0.20 behind it) | central 5-fin diffuser, Paint2 end strakes, red fog bar (LightTail); exhaust tips stay outboard |
| `hood_scoop_a` | 108 | 0.56 x 0.63 x 0.16 | Metal, Paint, Paint2, Trim | centre of the footprint on the hood; z=0 = hood surface (base sinks 4 cm) | ramp scoop, black intake + 2 vanes on the front face, Paint2 stripe; pitch it to the hood slope |
| `hood_vents_b` | 144 | 1.00 x 0.50 x 0.05 | Paint, Trim | centre between the two louvre banks (x = +-0.10..0.50); z=0 = hood surface | two banks of 5 louvres over a black recess |
| `roof_scoop` | 120 | 0.46 x 0.60 x 0.19 | Chrome, Paint, Paint2, Trim | centre of the footprint on the roof; z=0 = roof top | Paint2 air box with twin vaned intakes on the front face |
| `roof_rack` | 204 | 1.15 x 1.04 x 0.10 | Metal, MetalDark, Trim | centre of the rack footprint on the roof; z=0 = roof top (rails z 0.05..0.075, cross bars at 0.077) | 2 rails, 3 cross bars, 4 feet (Metal / MetalDark / Trim) |
| `roof_light_bar` | 144 | 1.02 x 0.11 x 0.12 | LampGlow, MetalDark, Paint2, Trim | centre of the base on the roof; lamps face +Y | off-road bar: 6 lamps + 2 side lamps in LampGlow (emissive), Paint2 cap |
| `skirt_side_sport` | 200 | 1.94 x 2.00 x 0.19 | Paint, Paint2, Trim | x=0 centre line, y=0 mid-sill, z=0 = bottom of the sill; BOTH skirts in one mesh (x +-0.84..0.97, y +-1.0) | blades with black lip and Paint2 stripe, tapered ends |
| `exhaust_tip_single` | 110 | 0.11 x 0.30 x 0.11 | Chrome, Metal, MetalDark, Trim | centre of the OUTLET opening; the pipe runs towards +Y (into the car) for 0.29 m | chrome flared tip, slash cut, dark inner disc, clamp + stub |
| `exhaust_tip_dual` | 196 | 1.18 x 0.30 x 0.10 | Chrome, Metal, MetalDark, Trim | centre line at the outlet plane; tips at x = +-0.54, pipes towards +Y | two single tips + hidden cross pipe |
| `exhaust_tip_quad` | 256 | 1.30 x 0.27 x 0.08 | Chrome, Metal, MetalDark, Trim | centre line at the outlet plane; tips at x = +-0.47 and +-0.60, pipes towards +Y | two pairs of smaller tips with brackets |
| `underglow_strip` | 144 | 1.52 x 3.84 x 0.10 | NeonCyan, Trim | centre of the ring on the centre line; z=0 = tube axis; ring 1.48 x 3.80 m | NeonCyan emissive hex-tube loop (+4 black clips); change the NeonCyan emission colour for other glow colours |
| `grille_mesh` | 204 | 0.68 x 0.04 x 0.16 | Chrome, Metal, MetalDark, Trim | centre of the grille opening, faces +Y (y=0 = back plate, the frame protrudes 0.026) | chrome frame + diamond lattice, drops in front of the stock grille (0.68 x 0.16) |
| `mirror_sport` | 160 | 2.24 x 0.10 x 0.11 | Chrome, Paint, Paint2, Trim | centre line at the mirror height; mirrors at x = +-(0.86..1.12), glass faces -Y | PAIR in one mesh: stalk, Paint housing, Chrome glass, Paint2 fin |
| `antenna` | 140 | 0.05 x 0.14 x 0.65 | Chrome, Metal, MetalDark, Trim | centre of the base on the surface; the mast leans 11 deg backwards, 0.65 m tall | whip antenna: base, spring, 3 telescopic sections, tip |

Notes: `skirt_side_sport` and `mirror_sport` are **pairs in one mesh** (mirrored across X). `exhaust_tip_dual/quad` are mirrored pairs too (`single` is one tip: place it at x = +0.56 for the sedan's right-hand pipe, or at x = 0 / any x). `bumper_front_sport` and `bumper_rear_diffuser` can be combined with `splitter_front` / exhaust tips (tips sit outboard of the diffuser). Spoilers are mutually exclusive, so are `hood_scoop_a` / `hood_vents_b` (they overlap).

## 3. Recommended mount transforms on the SEDAN (`vehicles/sedan.glb`; checked visually in Blender on a linked, read-only copy of the sedan meshes - all 20 parts incl. `exhaust_tip_quad`, which sits outboard of the diffuser)
Blender frame (what `parts_catalog.json` calls `pos_blender`), scale = (1,1,1) for every part on the sedan. `pitch` = rotation about X in degrees (+ nose up, same value in Godot).
| part | pos Blender (x, y, z) | pitch | pos Godot (x, y, z) | note |
|---|---|---|---|---|
| `spoiler_lip` | (0, -2.13, 0.962) | 0 | (0, 0.962, 2.13) | trunk lid rear edge |
| `spoiler_ducktail` | (0, -2, 0.968) | 0 | (0, 0.968, 2) | trunk lid rear edge |
| `spoiler_wing_low` | (0, -1.98, 0.968) | 0 | (0, 0.968, 1.98) | trunk lid, rear third |
| `spoiler_wing_high` | (0, -2, 0.968) | 0 | (0, 0.968, 2) | trunk lid, rear third |
| `splitter_front` | (0, 2.3, 0.285) | 0 | (0, 0.285, -2.3) | under the nose, plate top flush with the bumper underside |
| `bumper_front_sport` | (0, 2.385, 0.27) | 0 | (0, 0.27, -2.385) | shell sits ON the nose, covers bumper bar + lower valance |
| `bumper_rear_diffuser` | (0, -2.31, 0.27) | 0 | (0, 0.27, 2.31) | under / on the rear bumper |
| `hood_scoop_a` | (0, 1.35, 0.912) | -5.1 deg | (0, 0.912, -1.35) | hood centre, pitched to the hood slope |
| `hood_vents_b` | (0, 1.55, 0.892) | -5.1 deg | (0, 0.892, -1.55) | hood centre, pitched to the hood slope |
| `roof_scoop` | (0, -0.3, 1.45) | 0 | (0, 1.45, 0.3) | flat roof centre |
| `roof_rack` | (0, -0.3, 1.45) | 0 | (0, 1.45, 0.3) | flat roof centre |
| `roof_light_bar` | (0, 0.1, 1.45) | 0 | (0, 1.45, -0.1) | front edge of the flat roof |
| `skirt_side_sport` | (0, 0, 0.2) | 0 | (0, 0.2, 0) | between the wheel arches, bottom of the sill |
| `exhaust_tip_single` | (0.56, -2.36, 0.262) | 0 | (0.56, 0.262, 2.36) | at the sedan's Exhaust empty (right side) |
| `exhaust_tip_dual` | (0, -2.36, 0.262) | 0 | (0, 0.262, 2.36) | one tip each side (x = +-0.54) |
| `exhaust_tip_quad` | (0, -2.36, 0.262) | 0 | (0, 0.262, 2.36) | two tips each side (x = +-0.47, +-0.60) |
| `underglow_strip` | (0, 0, 0.175) | 0 | (0, 0.175, 0) | under the body, centred on the wheelbase |
| `grille_mesh` | (0, 2.345, 0.632) | 0 | (0, 0.632, -2.345) | in front of the stock grille |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (0, 0.99, -0.62) | replaces the door mirrors (x = +-0.86..1.12) |
| `antenna` | (0.47, -0.65, 1.45) | 0 | (0.47, 1.45, 0.65) | roof, rear right |

Wheels on the sedan: place the wheel GLB on each `Wheel_*` node (origin = wheel centre, so **identity position**), scale `(1, 0.971, 0.971)` for the sedan's 0.33 m tyres (see section 5).
A ready-made contact sheet lives in the master .blend: `vpref__root` (sedan wearing the sporty set at these transforms: `spoiler_wing_low`, `bumper_front_sport`, `splitter_front`, `skirt_side_sport`, `bumper_rear_diffuser`, `hood_vents_b`, `mirror_sport`, `exhaust_tip_dual`, `underglow_strip`, `roof_light_bar` + `wheel_turbine`) and `vpsheet__root` (all non-wheel parts in a row), wheel overview rows at (-20, 1880). Fixtures are QA only and not exported.

## 4. Fit hints for the other ground vehicles
`parts_catalog.json -> vehicles.<id>.fit.<part>` holds ready transforms (Blender + Godot axes). They come from **ray-cast anchors on the Wave-1 vehicle bodies** (table below) and one formula set; the sedan is the only body I checked visually - for the others treat them as a good first fit and re-tune per vehicle in `VehicleDefs` if something clips. Width scale `ws = half_width / 0.885` is applied to X for every width-spanning part (spoilers, splitter, bumpers, skirts, light bar, vents, underglow, mirrors).
| vehicle | half width | ws (x scale) | nose y | tail y | bumper z | roof z | roof y span | rear-spoiler anchor (y, z) | hood anchor (y, z, pitch) | wheel scale (1,s,s) |
|---|---|---|---|---|---|---|---|---|---|---|
| compact | 0.840 | 0.949 | 1.840 | -1.876 | 0.29 | 1.500 | -1.30 .. 0.00 | (-1.66, 0.953) | (0.90, 0.870, -7.0) | 0.882 |
| sedan | 0.885 | 1.000 | 2.369 | -2.394 | 0.27 | 1.450 | -0.95 .. 0.25 | (-2.00, 0.968) | (1.35, 0.912, -5.1) | 0.971 |
| sports | 0.940 | 1.062 | 2.150 | -2.150 | 0.21 | 1.200 | -1.00 .. -0.25 | (-1.95, 1.120) | (1.25, 0.830, -1.5) | 1.015 |
| muscle | 0.937 | 1.059 | 2.460 | -2.440 | 0.26 | 1.380 | -1.00 .. -0.15 | (-2.05, 1.000) | (1.90, 0.940, -5.0) | 1.029 |
| suv | 0.957 | 1.081 | 2.400 | -2.349 | 0.29 | 1.765 | -2.00 .. 0.40 | (-2.00, 1.765) | (1.50, 1.134, -5.1) | 1.118 |
| pickup | 0.947 | 1.070 | 2.580 | -2.708 | 0.37 | 1.846 | -1.15 .. 0.45 | (-2.50, 0.900) | (1.70, 1.180, -3.3) | 1.118 |
| van | 0.970 | 1.096 | 2.520 | -2.652 | 0.34 | 2.250 | -2.50 .. 0.30 | (-2.45, 2.220) | (2.10, 1.250, 0.0) | 1.000 |

Per-vehicle remarks:
- **compact**: short rear deck + steep hatch glass: lip / ducktail only; short hood (scoop OR vents)
- **sedan**: reference body: every mount was checked visually on it (rear / underside close-ups incl. exhaust_tip_quad + diffuser)
- **sports**: integrated tail lip at y=-1.95 (z 1.12): prefer spoiler_wing_low/high anchored on it; low flat hood
- **muscle**: already has a hood bulge/scoop at y=1.26..1.56 (z up to 1.07): skip hood_scoop_a, hood_vents_b goes on the front hood
- **suv**: no trunk deck: spoilers sit on the roof rear edge (y=-2.0); roof_rack scales to the long flat roof
- **pickup**: no trunk deck: only lip / ducktail on the tailgate top (z 0.90); high bumper (0.37)
- **van**: no real hood (windscreen starts at y=1.6): no hood parts; spoilers on the roof rear edge; high bumper

Formulas (Blender frame; `nose`, `tail`, `bz` = bumper z, `(dy, dz)` = deck anchor, `(hy, hz, hp)` = hood anchor, `cy` = roof span centre, `y1` = roof front end):
- spoilers `(0, dy + {-0.13 lip, 0 ducktail, +0.02 wing_low, 0 wing_high}, dz)`, scale `(ws,1,1)`; `splitter_front (0, nose-0.069, bz+0.015)`; `bumper_front_sport (0, nose+0.016, bz)`; `bumper_rear_diffuser (0, tail+0.084, bz)`;
- `hood_scoop_a (0, hy, hz)` pitch `hp`; `hood_vents_b (0, hy+0.20, hz-0.02)` pitch `hp`; `roof_scoop`, `roof_rack (0, cy+0.05, roof_z)`, rack scale `(ws, clamp((roof_len-0.15)/1.04, 0.6, 2.4), 1)`; `roof_light_bar (0, y1-0.15, roof_z)`; `antenna (0.47 ws, roof_y0+0.30, roof_z)`;
- `skirt_side_sport (0, 0, bz-0.07)` scale `(ws, (wheelbase - 2.42 r_wheel)/2.0, 1)` (between the arches); exhausts `(x, tail+0.034, bz-0.008)` (single x = 0.56 ws, dual/quad x = 0 scale `(ws,1,1)`); `underglow_strip (0, (nose+tail)/2, bz-0.095)` scale `(ws, length/4.763, 1)`; `grille_mesh (0, nose-0.024, bz+0.362)`;
- `mirror_sport`: sedan value (0, 0.62, 0.99); on the other cars use `DoorL.position + (0, -0.18, +0.39)` for y,z (x stays 0, scale `(ws,1,1)`), i.e. the A-pillar base next to the front door hinge.
- Bikes / boats / aircraft are not covered (only `wheel_mc_sport` is for motorcycles: scale X for fat rear tyres, e.g. `(1.25, 1, 1)`).

## 5. Wheel styles (10)
GLB = nodes `Tire` (material `Tire`, smooth shaded) + `Rim` (materials `Rim`, `Chrome`, `MetalDark`/`Trim`/`Metal`) + `Mount`. **Radius 0.34 m, width 0.24 m, spin axis X, origin = wheel centre, tyre bottom at y = -0.34** (same convention as `make_wheel` and the vehicle wheels; `wheel_mc_sport`: radius 0.31, width 0.17). **Both faces carry the same detail**, so one mesh fits the left and the right side of any car - never flip or mirror it.
| id | tris | size X x Y x Z | style |
|---|---|---|---|
| `wheel_stock` | 324 | 0.24 x 0.66 x 0.68 | dished plain cover, 5 black slots, chrome centre cap (OEM look) |
| `wheel_five_spoke` | 424 | 0.24 x 0.66 x 0.68 | classic 5-spoke alloy with chrome hub |
| `wheel_split_six` | 480 | 0.24 x 0.66 x 0.68 | 6 split (Y) spokes = 12 thin spokes |
| `wheel_mesh` | 480 | 0.24 x 0.66 x 0.68 | chrome lip + 6-point lattice (mesh) face |
| `wheel_dish` | 384 | 0.24 x 0.66 x 0.68 | deep dish with chrome lip and 5 bolts |
| `wheel_turbine` | 448 | 0.24 x 0.66 x 0.68 | 9 swept turbine blades |
| `wheel_steel_basic` | 328 | 0.24 x 0.66 x 0.68 | pressed steel wheel, 6 holes, hub cap |
| `wheel_offroad` | 476 | 0.24 x 0.66 x 0.68 | chunky staggered tread, tall sidewall (rim r 0.205), 5 fat spokes, beadlock bolts |
| `wheel_lowprofile` | 448 | 0.24 x 0.66 x 0.68 | 10 thin spokes, chrome lip, very thin sidewall (rim r 0.285) |
| `wheel_mc_sport` | 452 | 0.17 x 0.60 x 0.62 | motorcycle: r 0.31, width 0.17, round-section tyre, 5 spokes + brake disc on both faces |

How to apply: the vehicle code's `Wheel_FL/FR/RL/RR` nodes are `MeshInstance3D`s that the code spins (X) and steers (Y). Two good options: (a) hide the original mesh (`mesh = null`) and **add the part GLB instance as a child** of each wheel node, with scale `(1, s, s)`, `s = vehicle_wheel_radius / 0.34` (sedan 0.971, compact 0.882, sports 1.015, muscle 1.029, suv/pickup 1.118, van 1.0 - X stays 1.0, or 0.96..1.2 for a stance/width look); (b) take `Tire`/`Rim` meshes out of the GLB and add two `MeshInstance3D` children. Rim colour = override the `Rim` material (`rim_color` mod); `Chrome` parts keep their look. The wheel set tri cost is 324..480 per wheel (x4 per car, <= 2 000 per customised car).

## 6. Gotchas
- Do not rely on mesh bounding boxes for placement: parts are authored around their own mount origin (e.g. `exhaust_*` extends 0.29 m to +Y from the origin, `bumper_front_sport` 0.4 m behind it).
- Overlaps by design: `bumper_front_sport` hides the stock bumper bar/valance (its shell sits 1.6 cm in front of the nose at z 0.5 and ~7 cm at the chin); `grille_mesh` is an overlay in front of the stock grille; `mirror_sport` covers the stock door mirrors; the hood parts and `roof_*` parts are surface decals/solids on top of the body. Hide nothing in the vehicle mesh.
- `underglow_strip` is only the glowing tube. The ground glow itself needs the vehicle code (OmniLight / decal under the car, `NeonCyan` emission energy).
- `LampGlow` (light bar) and `LightHead`/`LightTail` (fog lamps / rear fog bar) are emissive materials by name: switch them with the vehicle's lights like the rest of the car.
- Wheel meshes are 14-segment (as the Wave-1 wheels): `s` scaling of the radius is fine, do NOT scale X by more than ~1.3 (the faces are flat).
- Tri budgets: every body part <= 400 (max 260), every wheel <= 500 (max 480). No UV unwrap / textures (colours by material only).

## 7. Rebuild
```python
LIB = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender"
exec(open(LIB + r"\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
for f in ("lane11_common.py", "lane11_catalog.py", "lane11_spoilers.py", "lane11_aero.py", "lane11_topside.py", "lane11_misc.py", "lane11_wheels.py", "lane11_fit.py", "lane11_build_all.py"):
    exec(open(LIB + "\\" + f, encoding="utf8").read(), globals())
l11_build_all(export=True); l11_dump_stats(); l11_showcase(); l11_sheet(); save_master()
```
then `python tools\blender\lane11_docgen.py` (regenerates this file and `parts_catalog.json`) and `powershell -NoProfile -File tools\gd.ps1 import`. Every builder is idempotent (`clear_asset("<id>__")` first); one part = one function (`l11_spoiler_lip()` ... `l11_wheel(...)`).
Source files: `lane11_common.py` (helpers, part context), `lane11_catalog.py` (order, sedan mounts), `lane11_vehicles.py` (anchors, fit formulas, descriptions), `lane11_spoilers.py`, `lane11_aero.py`, `lane11_topside.py`, `lane11_misc.py`, `lane11_wheels.py`, `lane11_fit.py` (QA fixtures), `lane11_build_all.py`, `lane11_docgen.py`.

## 8. Per-vehicle fit tables (generated)
### compact  (ws 0.949, wheel scale 0.882)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -1.79, 0.947) | 0 | (0.949, 1, 1) | (0, 0.947, 1.79) | (0.949, 1, 1) |
| `spoiler_ducktail` | (0, -1.66, 0.953) | 0 | (0.949, 1, 1) | (0, 0.953, 1.66) | (0.949, 1, 1) |
| `spoiler_wing_low` | (0, -1.64, 0.953) | 0 | (0.949, 1, 1) | (0, 0.953, 1.64) | (0.949, 1, 1) |
| `spoiler_wing_high` | (0, -1.66, 0.953) | 0 | (0.949, 1, 1) | (0, 0.953, 1.66) | (0.949, 1, 1) |
| `splitter_front` | (0, 1.771, 0.305) | 0 | (0.949, 1, 1) | (0, 0.305, -1.771) | (0.949, 1, 1) |
| `bumper_front_sport` | (0, 1.856, 0.29) | 0 | (0.949, 1, 1) | (0, 0.29, -1.856) | (0.949, 1, 1) |
| `bumper_rear_diffuser` | (0, -1.792, 0.29) | 0 | (0.949, 1, 1) | (0, 0.29, 1.792) | (0.949, 1, 1) |
| `hood_scoop_a` | (0, 0.9, 0.87) | -7.0 | (1, 1, 1) | (0, 0.87, -0.9) | (1, 1, 1) |
| `hood_vents_b` | (0, 1.1, 0.85) | -7.0 | (0.949, 1, 1) | (0, 0.85, -1.1) | (0.949, 1, 1) |
| `roof_scoop` | (0, -0.6, 1.5) | 0 | (1, 1, 1) | (0, 1.5, 0.6) | (1, 1, 1) |
| `roof_rack` | (0, -0.6, 1.5) | 0 | (0.949, 1.106, 1) | (0, 1.5, 0.6) | (0.949, 1, 1.106) |
| `roof_light_bar` | (0, -0.15, 1.5) | 0 | (0.949, 1, 1) | (0, 1.5, 0.15) | (0.949, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.22) | 0 | (0.949, 0.837, 1) | (0, 0.22, 0) | (0.949, 1, 0.837) |
| `exhaust_tip_single` | (0.532, -1.842, 0.282) | 0 | (1, 1, 1) | (0.532, 0.282, 1.842) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -1.842, 0.282) | 0 | (0.949, 1, 1) | (0, 0.282, 1.842) | (0.949, 1, 1) |
| `exhaust_tip_quad` | (0, -1.842, 0.282) | 0 | (0.949, 1, 1) | (0, 0.282, 1.842) | (0.949, 1, 1) |
| `underglow_strip` | (0, -0.018, 0.195) | 0 | (0.949, 0.78, 1) | (0, 0.195, 0.018) | (0.949, 1, 0.78) |
| `grille_mesh` | (0, 1.816, 0.652) | 0 | (1, 1, 1) | (0, 0.652, -1.816) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (0.949, 1, 1) | (0, 0.99, -0.62) | (0.949, 1, 1) |
| `antenna` | (0.446, -1, 1.5) | 0 | (1, 1, 1) | (0.446, 1.5, 1) | (1, 1, 1) |

### sedan  (ws 1.000, wheel scale 0.971)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.13, 0.962) | 0 | (1, 1, 1) | (0, 0.962, 2.13) | (1, 1, 1) |
| `spoiler_ducktail` | (0, -2, 0.968) | 0 | (1, 1, 1) | (0, 0.968, 2) | (1, 1, 1) |
| `spoiler_wing_low` | (0, -1.98, 0.968) | 0 | (1, 1, 1) | (0, 0.968, 1.98) | (1, 1, 1) |
| `spoiler_wing_high` | (0, -2, 0.968) | 0 | (1, 1, 1) | (0, 0.968, 2) | (1, 1, 1) |
| `splitter_front` | (0, 2.3, 0.285) | 0 | (1, 1, 1) | (0, 0.285, -2.3) | (1, 1, 1) |
| `bumper_front_sport` | (0, 2.385, 0.27) | 0 | (1, 1, 1) | (0, 0.27, -2.385) | (1, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.31, 0.27) | 0 | (1, 1, 1) | (0, 0.27, 2.31) | (1, 1, 1) |
| `hood_scoop_a` | (0, 1.35, 0.912) | -5.1 | (1, 1, 1) | (0, 0.912, -1.35) | (1, 1, 1) |
| `hood_vents_b` | (0, 1.55, 0.892) | -5.1 | (1, 1, 1) | (0, 0.892, -1.55) | (1, 1, 1) |
| `roof_scoop` | (0, -0.3, 1.45) | 0 | (1, 1, 1) | (0, 1.45, 0.3) | (1, 1, 1) |
| `roof_rack` | (0, -0.3, 1.45) | 0 | (1, 1.01, 1) | (0, 1.45, 0.3) | (1, 1, 1.01) |
| `roof_light_bar` | (0, 0.1, 1.45) | 0 | (1, 1, 1) | (0, 1.45, -0.1) | (1, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.2) | 0 | (1, 1.016, 1) | (0, 0.2, 0) | (1, 1, 1.016) |
| `exhaust_tip_single` | (0.56, -2.36, 0.262) | 0 | (1, 1, 1) | (0.56, 0.262, 2.36) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.36, 0.262) | 0 | (1, 1, 1) | (0, 0.262, 2.36) | (1, 1, 1) |
| `exhaust_tip_quad` | (0, -2.36, 0.262) | 0 | (1, 1, 1) | (0, 0.262, 2.36) | (1, 1, 1) |
| `underglow_strip` | (0, -0.012, 0.175) | 0 | (1, 1, 1) | (0, 0.175, 0.012) | (1, 1, 1) |
| `grille_mesh` | (0, 2.345, 0.632) | 0 | (1, 1, 1) | (0, 0.632, -2.345) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1, 1, 1) | (0, 0.99, -0.62) | (1, 1, 1) |
| `antenna` | (0.47, -0.65, 1.45) | 0 | (1, 1, 1) | (0.47, 1.45, 0.65) | (1, 1, 1) |

### sports  (ws 1.062, wheel scale 1.015)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.08, 1.114) | 0 | (1.062, 1, 1) | (0, 1.114, 2.08) | (1.062, 1, 1) |
| `spoiler_ducktail` | (0, -1.95, 1.12) | 0 | (1.062, 1, 1) | (0, 1.12, 1.95) | (1.062, 1, 1) |
| `spoiler_wing_low` | (0, -1.93, 1.12) | 0 | (1.062, 1, 1) | (0, 1.12, 1.93) | (1.062, 1, 1) |
| `spoiler_wing_high` | (0, -1.95, 1.12) | 0 | (1.062, 1, 1) | (0, 1.12, 1.95) | (1.062, 1, 1) |
| `splitter_front` | (0, 2.081, 0.225) | 0 | (1.062, 1, 1) | (0, 0.225, -2.081) | (1.062, 1, 1) |
| `bumper_front_sport` | (0, 2.166, 0.21) | 0 | (1.062, 1, 1) | (0, 0.21, -2.166) | (1.062, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.066, 0.21) | 0 | (1.062, 1, 1) | (0, 0.21, 2.066) | (1.062, 1, 1) |
| `hood_scoop_a` | (0, 1.25, 0.83) | -1.5 | (1, 1, 1) | (0, 0.83, -1.25) | (1, 1, 1) |
| `hood_vents_b` | (0, 1.45, 0.81) | -1.5 | (1.062, 1, 1) | (0, 0.81, -1.45) | (1.062, 1, 1) |
| `roof_scoop` | (0, -0.575, 1.2) | 0 | (1, 1, 1) | (0, 1.2, 0.575) | (1, 1, 1) |
| `roof_rack` | (0, -0.575, 1.2) | 0 | (1.062, 0.6, 1) | (0, 1.2, 0.575) | (1.062, 1, 0.6) |
| `roof_light_bar` | (0, -0.4, 1.2) | 0 | (1.062, 1, 1) | (0, 1.2, 0.4) | (1.062, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.14) | 0 | (1.062, 0.883, 1) | (0, 0.14, 0) | (1.062, 1, 0.883) |
| `exhaust_tip_single` | (0.595, -2.116, 0.202) | 0 | (1, 1, 1) | (0.595, 0.202, 2.116) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.116, 0.202) | 0 | (1.062, 1, 1) | (0, 0.202, 2.116) | (1.062, 1, 1) |
| `exhaust_tip_quad` | (0, -2.116, 0.202) | 0 | (1.062, 1, 1) | (0, 0.202, 2.116) | (1.062, 1, 1) |
| `underglow_strip` | (0, 0, 0.115) | 0 | (1.062, 0.903, 1) | (0, 0.115, 0) | (1.062, 1, 0.903) |
| `grille_mesh` | (0, 2.126, 0.572) | 0 | (1, 1, 1) | (0, 0.572, -2.126) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1.062, 1, 1) | (0, 0.99, -0.62) | (1.062, 1, 1) |
| `antenna` | (0.499, -0.7, 1.2) | 0 | (1, 1, 1) | (0.499, 1.2, 0.7) | (1, 1, 1) |

### muscle  (ws 1.059, wheel scale 1.029)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.18, 0.994) | 0 | (1.059, 1, 1) | (0, 0.994, 2.18) | (1.059, 1, 1) |
| `spoiler_ducktail` | (0, -2.05, 1) | 0 | (1.059, 1, 1) | (0, 1, 2.05) | (1.059, 1, 1) |
| `spoiler_wing_low` | (0, -2.03, 1) | 0 | (1.059, 1, 1) | (0, 1, 2.03) | (1.059, 1, 1) |
| `spoiler_wing_high` | (0, -2.05, 1) | 0 | (1.059, 1, 1) | (0, 1, 2.05) | (1.059, 1, 1) |
| `splitter_front` | (0, 2.391, 0.275) | 0 | (1.059, 1, 1) | (0, 0.275, -2.391) | (1.059, 1, 1) |
| `bumper_front_sport` | (0, 2.476, 0.26) | 0 | (1.059, 1, 1) | (0, 0.26, -2.476) | (1.059, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.356, 0.26) | 0 | (1.059, 1, 1) | (0, 0.26, 2.356) | (1.059, 1, 1) |
| `hood_scoop_a` | (0, 1.9, 0.94) | -5.0 | (1, 1, 1) | (0, 0.94, -1.9) | (1, 1, 1) |
| `hood_vents_b` | (0, 2.1, 0.92) | -5.0 | (1.059, 1, 1) | (0, 0.92, -2.1) | (1.059, 1, 1) |
| `roof_scoop` | (0, -0.525, 1.38) | 0 | (1, 1, 1) | (0, 1.38, 0.525) | (1, 1, 1) |
| `roof_rack` | (0, -0.525, 1.38) | 0 | (1.059, 0.673, 1) | (0, 1.38, 0.525) | (1.059, 1, 0.673) |
| `roof_light_bar` | (0, -0.3, 1.38) | 0 | (1.059, 1, 1) | (0, 1.38, 0.3) | (1.059, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.19) | 0 | (1.059, 1.026, 1) | (0, 0.19, 0) | (1.059, 1, 1.026) |
| `exhaust_tip_single` | (0.593, -2.406, 0.252) | 0 | (1, 1, 1) | (0.593, 0.252, 2.406) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.406, 0.252) | 0 | (1.059, 1, 1) | (0, 0.252, 2.406) | (1.059, 1, 1) |
| `exhaust_tip_quad` | (0, -2.406, 0.252) | 0 | (1.059, 1, 1) | (0, 0.252, 2.406) | (1.059, 1, 1) |
| `underglow_strip` | (0, 0.01, 0.165) | 0 | (1.059, 1.029, 1) | (0, 0.165, -0.01) | (1.059, 1, 1.029) |
| `grille_mesh` | (0, 2.436, 0.622) | 0 | (1, 1, 1) | (0, 0.622, -2.436) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1.059, 1, 1) | (0, 0.99, -0.62) | (1.059, 1, 1) |
| `antenna` | (0.498, -0.7, 1.38) | 0 | (1, 1, 1) | (0.498, 1.38, 0.7) | (1, 1, 1) |

### suv  (ws 1.081, wheel scale 1.118)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.13, 1.759) | 0 | (1.081, 1, 1) | (0, 1.759, 2.13) | (1.081, 1, 1) |
| `spoiler_ducktail` | (0, -2, 1.765) | 0 | (1.081, 1, 1) | (0, 1.765, 2) | (1.081, 1, 1) |
| `spoiler_wing_low` | (0, -1.98, 1.765) | 0 | (1.081, 1, 1) | (0, 1.765, 1.98) | (1.081, 1, 1) |
| `spoiler_wing_high` | (0, -2, 1.765) | 0 | (1.081, 1, 1) | (0, 1.765, 2) | (1.081, 1, 1) |
| `splitter_front` | (0, 2.331, 0.305) | 0 | (1.081, 1, 1) | (0, 0.305, -2.331) | (1.081, 1, 1) |
| `bumper_front_sport` | (0, 2.416, 0.29) | 0 | (1.081, 1, 1) | (0, 0.29, -2.416) | (1.081, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.265, 0.29) | 0 | (1.081, 1, 1) | (0, 0.29, 2.265) | (1.081, 1, 1) |
| `hood_scoop_a` | (0, 1.5, 1.134) | -5.1 | (1, 1, 1) | (0, 1.134, -1.5) | (1, 1, 1) |
| `hood_vents_b` | (0, 1.7, 1.114) | -5.1 | (1.081, 1, 1) | (0, 1.114, -1.7) | (1.081, 1, 1) |
| `roof_scoop` | (0, -0.75, 1.765) | 0 | (1, 1, 1) | (0, 1.765, 0.75) | (1, 1, 1) |
| `roof_rack` | (0, -0.75, 1.765) | 0 | (1.081, 2.163, 1) | (0, 1.765, 0.75) | (1.081, 1, 2.163) |
| `roof_light_bar` | (0, 0.25, 1.765) | 0 | (1.081, 1, 1) | (0, 1.765, -0.25) | (1.081, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.22) | 0 | (1.081, 0.99, 1) | (0, 0.22, 0) | (1.081, 1, 0.99) |
| `exhaust_tip_single` | (0.606, -2.315, 0.282) | 0 | (1, 1, 1) | (0.606, 0.282, 2.315) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.315, 0.282) | 0 | (1.081, 1, 1) | (0, 0.282, 2.315) | (1.081, 1, 1) |
| `exhaust_tip_quad` | (0, -2.315, 0.282) | 0 | (1.081, 1, 1) | (0, 0.282, 2.315) | (1.081, 1, 1) |
| `underglow_strip` | (0, 0.025, 0.195) | 0 | (1.081, 0.997, 1) | (0, 0.195, -0.025) | (1.081, 1, 0.997) |
| `grille_mesh` | (0, 2.376, 0.652) | 0 | (1, 1, 1) | (0, 0.652, -2.376) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1.081, 1, 1) | (0, 0.99, -0.62) | (1.081, 1, 1) |
| `antenna` | (0.508, -1.7, 1.765) | 0 | (1, 1, 1) | (0.508, 1.765, 1.7) | (1, 1, 1) |

### pickup  (ws 1.070, wheel scale 1.118)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.63, 0.894) | 0 | (1.07, 1, 1) | (0, 0.894, 2.63) | (1.07, 1, 1) |
| `spoiler_ducktail` | (0, -2.5, 0.9) | 0 | (1.07, 1, 1) | (0, 0.9, 2.5) | (1.07, 1, 1) |
| `spoiler_wing_low` | (0, -2.48, 0.9) | 0 | (1.07, 1, 1) | (0, 0.9, 2.48) | (1.07, 1, 1) |
| `spoiler_wing_high` | (0, -2.5, 0.9) | 0 | (1.07, 1, 1) | (0, 0.9, 2.5) | (1.07, 1, 1) |
| `splitter_front` | (0, 2.511, 0.385) | 0 | (1.07, 1, 1) | (0, 0.385, -2.511) | (1.07, 1, 1) |
| `bumper_front_sport` | (0, 2.596, 0.37) | 0 | (1.07, 1, 1) | (0, 0.37, -2.596) | (1.07, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.624, 0.37) | 0 | (1.07, 1, 1) | (0, 0.37, 2.624) | (1.07, 1, 1) |
| `hood_scoop_a` | (0, 1.7, 1.18) | -3.3 | (1, 1, 1) | (0, 1.18, -1.7) | (1, 1, 1) |
| `hood_vents_b` | (0, 1.9, 1.16) | -3.3 | (1.07, 1, 1) | (0, 1.16, -1.9) | (1.07, 1, 1) |
| `roof_scoop` | (0, -0.3, 1.846) | 0 | (1, 1, 1) | (0, 1.846, 0.3) | (1, 1, 1) |
| `roof_rack` | (0, -0.3, 1.846) | 0 | (1.07, 1.394, 1) | (0, 1.846, 0.3) | (1.07, 1, 1.394) |
| `roof_light_bar` | (0, 0.3, 1.846) | 0 | (1.07, 1, 1) | (0, 1.846, -0.3) | (1.07, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.3) | 0 | (1.07, 1.165, 1) | (0, 0.3, 0) | (1.07, 1, 1.165) |
| `exhaust_tip_single` | (0.599, -2.674, 0.362) | 0 | (1, 1, 1) | (0.599, 0.362, 2.674) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.674, 0.362) | 0 | (1.07, 1, 1) | (0, 0.362, 2.674) | (1.07, 1, 1) |
| `exhaust_tip_quad` | (0, -2.674, 0.362) | 0 | (1.07, 1, 1) | (0, 0.362, 2.674) | (1.07, 1, 1) |
| `underglow_strip` | (0, -0.064, 0.275) | 0 | (1.07, 1.11, 1) | (0, 0.275, 0.064) | (1.07, 1, 1.11) |
| `grille_mesh` | (0, 2.556, 0.732) | 0 | (1, 1, 1) | (0, 0.732, -2.556) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1.07, 1, 1) | (0, 0.99, -0.62) | (1.07, 1, 1) |
| `antenna` | (0.503, -0.85, 1.846) | 0 | (1, 1, 1) | (0.503, 1.846, 0.85) | (1, 1, 1) |

### van  (ws 1.096, wheel scale 1.000)
| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |
|---|---|---|---|---|---|
| `spoiler_lip` | (0, -2.58, 2.214) | 0 | (1.096, 1, 1) | (0, 2.214, 2.58) | (1.096, 1, 1) |
| `spoiler_ducktail` | (0, -2.45, 2.22) | 0 | (1.096, 1, 1) | (0, 2.22, 2.45) | (1.096, 1, 1) |
| `spoiler_wing_low` | (0, -2.43, 2.22) | 0 | (1.096, 1, 1) | (0, 2.22, 2.43) | (1.096, 1, 1) |
| `spoiler_wing_high` | (0, -2.45, 2.22) | 0 | (1.096, 1, 1) | (0, 2.22, 2.45) | (1.096, 1, 1) |
| `splitter_front` | (0, 2.451, 0.355) | 0 | (1.096, 1, 1) | (0, 0.355, -2.451) | (1.096, 1, 1) |
| `bumper_front_sport` | (0, 2.536, 0.34) | 0 | (1.096, 1, 1) | (0, 0.34, -2.536) | (1.096, 1, 1) |
| `bumper_rear_diffuser` | (0, -2.568, 0.34) | 0 | (1.096, 1, 1) | (0, 0.34, 2.568) | (1.096, 1, 1) |
| `hood_scoop_a` | (0, 2.1, 1.25) | 0 | (1, 1, 1) | (0, 1.25, -2.1) | (1, 1, 1) |
| `hood_vents_b` | (0, 2.3, 1.23) | 0 | (1.096, 1, 1) | (0, 1.23, -2.3) | (1.096, 1, 1) |
| `roof_scoop` | (0, -1.05, 2.25) | 0 | (1, 1, 1) | (0, 2.25, 1.05) | (1, 1, 1) |
| `roof_rack` | (0, -1.05, 2.25) | 0 | (1.096, 2.4, 1) | (0, 2.25, 1.05) | (1.096, 1, 2.4) |
| `roof_light_bar` | (0, 0.15, 2.25) | 0 | (1.096, 1, 1) | (0, 2.25, -0.15) | (1.096, 1, 1) |
| `skirt_side_sport` | (0, 0, 0.27) | 0 | (1.096, 1.239, 1) | (0, 0.27, 0) | (1.096, 1, 1.239) |
| `exhaust_tip_single` | (0.614, -2.618, 0.332) | 0 | (1, 1, 1) | (0.614, 0.332, 2.618) | (1, 1, 1) |
| `exhaust_tip_dual` | (0, -2.618, 0.332) | 0 | (1.096, 1, 1) | (0, 0.332, 2.618) | (1.096, 1, 1) |
| `exhaust_tip_quad` | (0, -2.618, 0.332) | 0 | (1.096, 1, 1) | (0, 0.332, 2.618) | (1.096, 1, 1) |
| `underglow_strip` | (0, -0.066, 0.245) | 0 | (1.096, 1.086, 1) | (0, 0.245, 0.066) | (1.096, 1, 1.086) |
| `grille_mesh` | (0, 2.496, 0.702) | 0 | (1, 1, 1) | (0, 0.702, -2.496) | (1, 1, 1) |
| `mirror_sport` | (0, 0.62, 0.99) | 0 | (1.096, 1, 1) | (0, 0.99, -0.62) | (1.096, 1, 1) |
| `antenna` | (0.515, -2.2, 2.25) | 0 | (1, 1, 1) | (0.515, 2.25, 2.2) | (1, 1, 1) |

