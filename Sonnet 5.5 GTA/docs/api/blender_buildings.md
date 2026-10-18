# Blender buildings (lane 6) - kits and complete houses

Authored in Blender (`GTA_GODOT/Buildings`), exported to `res://gta/generated/models/buildings/`. Rebuild scripts: `tools/blender/lane6_*.py`
(see "Rebuild" at the end). Reference assembly + visual check: `gta/tests/buildings_preview.gd` (works through `tools\gd.ps1 shot`).

## 1. Files

| GLB | contents | tris |
|---|---|---|
| `buildings/kit_office.glb` | 11 modules (curtain-wall tower) | 838 |
| `buildings/kit_apartment.glb` | 10 modules (brick / stucco mid-rise) | 1972 |
| `buildings/kit_shop.glb` | 10 modules (1-2 storey commercial strip) | 1359 |
| `buildings/kit_roof.glb` | 11 rooftop props | 3030 |
| `buildings/kit_industrial.glb` | 11 modules (sheds, doors, roofs, silo, tank) | 2252 |
| `buildings/bld_house_a.glb` | gable house, cross-gable porch, chimney | 813 |
| `buildings/bld_house_b.glb` | modern flat-roof house, cantilevered upper volume, terrace, PV array, courtyard screen | 888 |
| `buildings/bld_house_c.glb` | two-storey house, full-width porch, bay window | 1470 |
| `buildings/bld_house_d.glb` | bungalow + attached garage (hip roofs) | 860 |
| `buildings/bld_duplex.glb` | two-unit townhouse, 15 x 10.7 m (mirrored units, different accent colours) | 1360 |
| `buildings/bld_apartment_small.glb` | 4-storey walk-up, 20.6 x 17 m, stoop, balconies, parapet, bulkhead | 1418 |

Every module is <= 400 tris. All modules of a kit are direct children of the GLB root, **each node sits at identity (position 0)**, the node name
is the module name (`find_child("Office_Bay_Window", true, false)` -> `MeshInstance3D`; use its `mesh`). Surfaces carry the Blender material
names (see section 5) so `Util.replace_material(root, "Window", mat)` etc. works. UVs are box-projected in metres (module space).

## 2. Module space (kits)

Blender frame = Godot frame converted by the glTF exporter: Blender (x, y, z) -> Godot (x, z, -y). **Facade faces Blender +Y = Godot -Z.**
* origin = bottom-centre of the FRONT plane (the wall face, Blender y = 0). The 0.35 m slab sits behind (Godot +Z, Blender -Y). Details protrude
  to the front (sills, fins, cornices, balconies, awnings, canopies: up to 1.6 m), window reveals/glass go behind the plane (-0.07 .. -0.3).
* bay width 4.0 m (x -2..2), floor height 3.6 m (z 0..3.6); ground modules (`*_Ground_*`, `Apt_Bay_Door_Stoop`, `Apt_Bay_Shop_Ground`,
  `Office_Podium_Base`) are 4.8 m tall. Industrial wall bays are 4.0 x 6.0 m.
* modules are **open shells** (front, reveals, glass, trim only - no back/top/bottom faces, no interiors). Put a plain core box behind the facade
  (y <= -0.35, Godot z >= 0.35) in the building builder; otherwise you see through the back. Faces are single sided (cull back).
* thin dark strips on the facade are real quads 1.2 cm in front of the wall (panel lines) - do not scale the modules non-uniformly.

### Assembly (walk the footprint clockwise, ONE chiral corner module)
Using Blender-style coordinates `(bx, by, bz)` and yaw `rz` (deg, CCW seen from above) -> Godot `position = (bx, bz, -by)`, `rotation_degrees.y = rz`:

| face | normal | rz | bay i centre (W x D bays, footprint x [-2W, 2W], y [-4D, 0]) |
|---|---|---|---|
| 0 front | +Y (Godot -Z) | 0 | `(-2W + 2 + 4i, 0)` |
| 1 right | +X | -90 | `(2W, -2 - 4i)` |
| 2 back | -Y | 180 | `(2W - 2 - 4i, -4D)` |
| 3 left | -X | +90 | `(-2W, -4D + 2 + 4i)` |

The LAST bay of every face (i = n-1) is the **`*_Corner_Out`** module: it is an ordinary 4 m bay whose right edge is the building corner; its pier
wraps the corner and its return arm covers the first ~1 m of the next face (so the next face's bay 0 is simply the normal bay, no gap, no overlap
problem). `*_Corner_In` (concave L-corner) is for the START of a face: its pier is at the left edge (x -2) and hugs the wing wall that runs along
x = -2 towards +Y (the wing's last bay, rotated -90 deg, ends at the corner). Floors stack at `z = 0, 4.8 (ground), +3.6 ...`; finish with
`*_Cornice` (and `Apt_Cornice_Corner` on corner bays; its mitre square sticks out to x = 2.38). `Office_Crown_A` stacks on `Office_Cornice` (z + 1.45).
Reference implementation: `buildings_preview.gd::block()` (apartment 4x3 bays, office 5x3 bays, both validated visually in Godot).

Overlays (placed on top of ground/first floor modules, same origin plane): `Office_Pilaster` (0.8 m wide, put it ON a bay boundary x = +-2),
`Shop_Awning_A/B` (z 2.1..3.1 above the shop window), `Shop_Sign_Board` (z 3.0..4.05, on the fascia, blank `Neon` face), `Shop_Sign_Blade`
(1.25 m arm along +Y, double sided `Neon`), `Apt_FireEscape_Bay` (platform at the module bottom, stair rises to the next bay's platform;
alternate with `scale.x = -1` per floor for a zig-zag).

## 3. Kit modules (w = width m, h = height m, depth = extent in front of / behind the front plane)

### kit_office (Office_*)
`Office_Bay_Window` 4x3.6 (76) - glazed bay, mullions, sill, tinted spandrel (WallC), floor band. `Office_Bay_Solid` 4x3.6 (56) - solid bay, 2 inset
WallB panels + louvre. `Office_Bay_Spandrel_Stripe` 4x3.6 (56) - continuous ribbon window with WallC spandrel stripes. `Office_Bay_Ground_Lobby`
4x4.8 (140) - glass double doors + side lights, entry slab, canopy (reaches y +1.56) with NeonCyan lip. `Office_Bay_Ground_Window` 4x4.8 (94) - tall
storefront glazing on a stone plinth. `Office_Corner_Out` 4x3.6 (93, pier + return arm to y -1.0), `Office_Corner_In` 4x3.6 (81), `Office_Pilaster` 0.8x3.6
(32), `Office_Cornice` 4x1.45 (46, roof parapet bay, back face included), `Office_Crown_A` 4x3.2 (80, 3 stepped tiers back to y -2.7 with NeonCyan lines),
`Office_Podium_Base` 4x4.8 (84, rusticated base with slit windows).

### kit_apartment (Apt_*)
`Apt_Bay_Window` 4x3.6 (142) twin windows + sills/lintels + brick spandrel, `Apt_Bay_Balcony` (178, slab 1.4 m deep, glass + metal rail, French doors),
`Apt_Bay_Solid` (126, brick panels, drain pipe), `Apt_Bay_Door_Stoop` 4x4.8 (346, 3 steps + rails, canopy, door `WallC`), `Apt_Bay_Shop_Ground` 4x4.8 (118),
`Apt_Corner_Out` (200, brick quoins on both faces), `Apt_Corner_In` (222), `Apt_Cornice` 4x1.48 (114, dentils), `Apt_Cornice_Corner` (134),
`Apt_FireEscape_Bay` 4x3.6 (392, platform 1.2 m deep + rails + stair).

### kit_shop (Shop_*)
`Shop_Front_Glass` 4x3.6 (102), `Shop_Front_Door` (206, glass door + side lights + step), `Shop_Front_Wide` **8 m wide** (246, two windows + door),
`Shop_Awning_A` (92, striped sloped awning WallB/WallD with scalloped valance, projects 1.6 m), `Shop_Awning_B` (114, quarter-round WallC/WallD),
`Shop_Sign_Board` 3.6 wide (92, blank emissive `Neon` face + 3 lamps), `Shop_Sign_Blade` (74), `Shop_Upper_Window` 4x3.6 (186, shutters, flower box),
`Shop_Parapet` 4x1.63 (92, stepped centre gable + finials), `Shop_Corner` (155, pier + wrapped fascia + corner lamp).

### kit_industrial (Ind_*)
`Ind_Wall_Corrugated` 4x6 (60, real zig-zag ribs 0.25 m / 7 cm), `Ind_Wall_Windows_Band` (126), `Ind_Door_Roller` (252, 3.2 x 4.5 m shutter, coil box, bollards),
`Ind_Door_Man` (152), `Ind_Loading_Dock` (200, door raised to z 1.2, bumpers, dock seal), `Ind_Corner` (108), `Ind_Roof_Sawtooth_Bay` **4 wide x 12 deep** (156; sits on
the wall top: z = 0 is the eave line, roof extends to y -12, glazed faces `Window`), `Ind_Roof_Flat_Edge` 4 wide x 4 deep (156, parapet + skylight + vent + downspout down to z -3.05),
`Ind_Pipe_Run` 4 m (328, wall mounted at z 2.8..5.5, stand-off 0.5), `Ind_Silo_Small` (350, **origin = base centre**, r 1.55, h 8.85, ladder on +Y), `Ind_Tank` (364, origin = base centre,
r 2.4 (+foundation 2.6), h 6.2, ladder on +Y, manhole on -X).

### kit_roof (Roof_*) - all origin = footprint centre on the roof surface, front +Y
`Roof_AC_A` 2.0x1.4x1.1 (296), `Roof_AC_B` 2.7x1.4 + stack (246, h 2.7), `Roof_Tank` r 1.3, h 5.3 (396, wooden tank on steel tower, ladder on +Y), `Roof_Antenna_A` h 9.0
(312, lattice mast with `LightRed` beacon), `Roof_Antenna_B` h 5.5 (344, mast + dish tilted 30 deg towards +Y, guy wires), `Roof_Stairs_Box` 3.2x2.6x2.6 (160, door on +Y),
`Roof_Vent_Row` 4 m along X (236), `Roof_Solar_Panels` 5 x 3.3 (296, `SolarPanel` faces +Y), `Roof_Helipad_Pad` **12 x 12** (328, 0.3 thick, yellow ring + H as `Accent`/`Plate`, 12 `NeonCyan`
rim lights, 4 `LightRed` corner beacons), `Roof_Billboard_Frame` 8 wide x 7.35 high (274, face quad = material `BillboardFace`, 4 `LampGlow` flood lights),
`Roof_Chimney` 1.2x1.2x3.4 (142).

## 4. Complete houses (own GLB each)
Nodes: `Body` (single mesh) + empty `Door` (ground point in front of the entrance steps, Godot -Z side). `bld_house_d` also has `Garage` (drive-in point), `bld_duplex` has `Door` (unit +X) and
`Door_B` (unit -X). Origin = centre of the main building volume at ground level (porches/steps/driveway stick out towards the front). Front faces Godot -Z.
Materials: `WallA/B/C/D`, `RoofTile` (pitched) or `Roof` (flat), `Window`, `Trim`, `Concrete`, `Metal`, plus `Wood`, `Glass`, `LampGlow`, `NeonCyan` where used. All have a plinth, windows with reveals/frames/sills,
doors with step; extents (x, y, z) in metres: house_a 11.0 x 6.6 x 12.4, house_b 11.4 x 7.0 x 11.3, house_c 10.8 x 9.0 x 11.9, house_d 13.7 x 6.0 x 10.8, duplex 15.0 x 8.8 x 10.7, apartment_small 20.6 x 16.3 x 17.0.
Door positions (Godot): house_a (0, 0, -7.45), house_b (-4.1, 0, -5.9), house_c (0, 0, -6.9), house_d (3.5, 0, -6.4) / Garage (-3.5, 0, -6.2), duplex (1.4, 0, -6.3) / (-1.4, 0, -6.3), apartment_small (0, 0, -9.2).
No collision shapes are baked: use a box per building volume (the bodies are open-bottomed shells that are visually closed).

## 5. Materials (replace by NAME)
`Window` (all glass panes: shader), `WallA` (main facade), `WallB` (accent / brick), `WallC` / `WallD` (trims, shutters, doors), `Roof`, `RoofTile`, `Trim` (frames, mullions, dark panel lines),
`Metal`, `MetalDark`, `Concrete`, `Plate` (appliance white), `Neon` / `NeonCyan` (emissive signs and lights), `LampGlow` (lamps), `LightRed` (beacons), `Glass` (balcony / terrace rails, translucent),
`Accent` (safety yellow, helipad paint), `Wood`, `Leaf`, `SolarPanel`, `BillboardFace` (blank billboard), `Asphalt` (helipad pad surface). All are plain Principled BSDF colours (no textures).

## 6. Known limits / honest notes
* Facade modules have no back faces and no collision; the building builder must add a core + collider. No interiors.
* `Office_Crown_A`, `Roof_*` props and the industrial roof modules are straight (no corner variants); `Apt_Cornice_Corner` is the only cornice with a mitred corner.
* `Shop_Front_Wide` is 8 m (the only non-4 m bay besides the 0.8 m pilaster and the 4x12 m sawtooth roof).
* Validated: all GLBs imported in Godot 4.7.2 and probed (`glb_probe`), and rendered through `buildings_preview.gd` + `gd.ps1 shot` (screenshots/lane6_*.png).

## 7. Rebuild
`tools/blender/lane6_kitlib.py` (KB mesh builder with explicit-outward-normal faces, Kit class), `lane6_houselib.py` (WallRef), `lane6_kit_office.py`, `lane6_kit_apartment.py`, `lane6_kit_shop.py`,
`lane6_kit_roof.py`, `lane6_kit_industrial.py`, `lane6_houses.py` (set `EXPORT_KITS = True` / `EXPORT_HOUSES = True` before exec to export), test assemblies `lane6_test_office.py`, `lane6_test_apartment.py`.
Run inside Blender: `exec(open(r"...\tools\blender\gta_lib.py").read(), globals()); assert_master(); EXPORT_KITS=True; exec(open(r"...\tools\blender\lane6_kit_office.py").read(), globals())`.
