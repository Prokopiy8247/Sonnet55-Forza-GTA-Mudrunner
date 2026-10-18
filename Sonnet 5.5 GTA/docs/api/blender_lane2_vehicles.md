# Blender lane 2 - motorcycle, bicycle, ambulance, truck, firetruck, police_tactical

GLBs: `res://gta/generated/models/vehicles/<id>.glb`. Sources live in the master .blend (`GTA_GODOT/Vehicles/Motorcycles`: motorcycle, bicycle; `GTA_GODOT/Vehicles/Cars`: ambulance, truck,
firetruck, police_tactical; workshop slots = lane 2, index 0..5, spacing 14 m, root empties `<id>__root`). Rebuild everything with `tools/blender/lane2_build_all.py`
(after `gta_lib.py` + `lane2_common.py`); one asset = `tools/blender/lane2_<id>.py` (idempotent, ends with `l2_A.export("vehicles/<id>")` in the build-all script).
Godot front = -Z, driver on the LEFT (-X seats), origin = ground point at wheelbase centre, tyre bottoms at Y=0. Quick visual QA:
`gta/tests/vehicles_lane2_showcase.gd` (raw GLBs) and `gta/tests/vehicles_lane2_ingame.gd` (spawned through VehicleFactory, runtime paint applied; env `VEH_SHOW`, `VEH_ENTER=1`).

## Common contract
`Body` (one mesh), separate wheel meshes (origin = wheel centre, spin axis X, outer face away from the centre line, radius readable from the AABB), `DoorL/DoorR` (hinge = origin at the FRONT
edge of the door, vertical hinge axis; the door skin overlaps the body wall, window glass stays in `Body`), empties `HeadlightL/R`, `TaillightL/R`, `SeatDriver`, `SeatPassenger`, `SeatRearL/R`,
`ExitL/R` (on the ground ~1 m outside the cab door), `Exhaust`. Seat empties are PELVIS points (cushion top + ~0.09 m; floor + 0.37 m in the trucks).

**Materials / paint:** Godot repaints `Paint` (primary) and `Paint2` (secondary, DARK by default: `VehicleFactory` passes `Color(0.1,0.1,0.12)`) at runtime. Livery graphics that must keep
their colour therefore use fixed materials that Godot does not touch: `LiveryRed` (ambulance stripes / star), `LiveryWhite` (truck cargo box, fire-engine trim, tactical stripes).
Other runtime-swapped names used: `Glass`, `LightHead`, `LightTail`, `LightAmber`, `LightBlue`, `LightRed` (siren bars + strobe boxes flash with the siren), `Tire`, `Rim`.
Decal details (panel lines, roller-shutter ribs, chevrons) are single double-sided quads (glTF materials are double sided).

## Per asset
| id | size L x W x H (m) | tris (whole model) | nodes beyond the common contract |
|---|---|---|---|
| motorcycle | 2.15 x 0.85 x 1.23 | 2328 (Body 1436, Fork 492, wheels 200 each) | `Wheel_F`, `Wheel_R` (fat rear tyre), `Fork` (origin at the steering-head top, rotated about the vertical axis by `BikeVehicle`: handlebar, grips, mirrors, fork legs, headlight + lens, flyscreen, front fender), `HeadlightF`, `TaillightR`, `SeatDriver`, extra `SeatPassenger` (pillion), `ExitL/R`, `Exhaust` (twin shorty cans). Paint = tank/tail/side panels, Paint2 = belly pan/fenders/cowl |
| bicycle | 1.77 x 0.61 x 1.09 | 1464 (Body 500, Fork 436, Pedals 136, wheels 196 each) | `Wheel_F/R` (diamond tyre+rim ring, 8 spokes), `Fork` (origin at the head-tube top: fork, stem, swept bars, dynamo lamp, front fender), `Pedals` (origin at the bottom bracket, spins around X: cranks, chainring, pedals), `SeatDriver`, `HeadlightF`, `TaillightR`, `ExitL/R` |
| ambulance | 2.17 x 5.82 x 2.65 | 3288 | box body + lower cab, `SirenBar` (cab roof, children `SirenBar_L` LightBlue / `SirenBar_R` LightRed), roof/rear strobes (LightBlue/LightRed in Body), rear doors + side compartment seams, 4 seats (driver, passenger, rear bench in the cab), 4 wheels |
| truck | 2.56 x 8.10 x 3.59 | 3264 | cab-over cab (Paint) + cargo box (LiveryWhite) with ribs / roll-up door, roof deflector, exhaust stack, big mirrors on the doors, 6 wheels `Wheel_FL/FR` (front), `Wheel_ML/MR` (y = -1.7), `Wheel_RL/RR` (y = -2.9), front axle y = +2.3, 2 seats |
| firetruck | 2.62 x 9.04 x 3.38 | 3490 | crew cab, 7 roller-shutter compartments, roof ladder with 15 rungs on posts, hose reel, pump panel, chevron rear, `SirenBar` (+`SirenBar_L` LightRed, `SirenBar_R` LightBlue), 6 wheels (front y = +2.5, ML -1.9, RL -3.1), 4 seats |
| police_tactical | 2.57 x 5.99 x 2.61 | 2716 | armoured hull (V belly, sloped shoulders), slit windows, windscreen panes, ram bumper + bull bars, roof turret ring with shield plates, floodlights + searchlight, spare wheel on the rear door, `SirenBar` (+L LightBlue / R LightRed), 4 seats (hidden inside the armour: the hull is solid) |

## Known limits
No `_lod` files and no `Hood`/`Trunk` nodes (the code does not load LODs yet). Truck/firetruck cabs are solid below the belt line (seats are visible through the glass only above it);
the tactical hull is solid, so its occupants are invisible. Wheel hubs are simple hex caps. `Fork` rotates about a vertical axis through its origin (the real steering axis is raked 25 deg / 18 deg),
so large steering angles show a small offset between fork legs and wheel.
