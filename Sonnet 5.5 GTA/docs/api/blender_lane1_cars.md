# Blender lane 1 - cars (police_cruiser, suv, pickup, van, taxi)

GLBs: `res://gta/generated/models/vehicles/<id>.glb`. Sources live in the master .blend (collection `GTA_GODOT/Vehicles/Cars`, workshop slots lane 1 index 0..4) and are rebuilt by
`tools/blender/lane1_<id>.py` (shared toolkit `tools/blender/lane1_common.py`, batch: `lane1_build_all.py`). Godot front = -Z, driver on the LEFT (-X seats), origin = ground point at wheelbase centre.
Visual QA helper: `gta/tests/vehicles_lane1_showcase.gd` (see header for the `tools\gd.ps1 shot` command).

## Common node contract (all five)
`Body` (one mesh: Paint, Paint2, Glass, Trim, Chrome, LightHead, LightTail, LightAmber, Interior, Plate, ...), `Wheel_FL/FR/RL/RR` (origin = wheel centre, spin axis X, ~176 tris each),
`DoorL/DoorR` (hinge at the door's FRONT edge, origin = hinge, hinge axis = vertical; door skin + window frame + handle + mirror; the Body's glass stays in place),
LOD = separate file `vehicles/<id>_lod.glb` (same convention as lane 0: one mesh `Body`, exact outer silhouette incl. light boxes, no interior/arches/doors/wheels, 12-20 % of the Body triangles; there is NO `BodyLOD` node in the main GLB, so nothing double-renders),
empties `HeadlightL/R`, `TaillightL/R`, `SeatDriver`/`SeatPassenger` (x = -0.40 / +0.40), `SeatRearL/R` (not on the van: only `SeatRearL`), `ExitL/R` (on the ground ~1 m outside the front door, at the door's y), `Exhaust`.
Seat empties are the PELVIS height (character head clears the roof): police 0.48, taxi 0.50, suv 0.85, pickup 0.86, van 1.20 (floor of the cabin: 0.30 / 0.28 / 0.40 / 0.38 / 0.80).
Runtime replace-by-name materials used: Paint, Paint2, Glass, LightHead, LightTail, LightAmber, LightBlue, LightRed, LampGlow.

## Per asset
| id | size (m) | tris (whole model / LOD file) | extras |
|---|---|---|---|
| police_cruiser | 1.93 x 4.94 x 1.49 (mirrors included) | 2940 / 356 | `SirenBar` (mesh, origin on the roof) with children `SirenBar_L` (LightBlue) and `SirenBar_R` (LightRed); `Spotlight` mesh on the A pillar; push bar; rear-window light bar + grille LEDs use LightBlue/LightRed in Body (flash with the siren); Paint = white, Paint2 = dark door panels/hood/trunk |
| suv | 2.01 x 4.87 x 1.80 | 3022 / 254 | roof rails, side steps, tail-mounted spare tyre, fender flares, 5 seats |
| pickup | 1.99 x 5.36 x 1.84 | 3176 / 232 | separate `Bed` mesh (open cargo bed with floor ribs, tailgate is in Body), bull bar, roll bar + light bar (LightHead), crew cab, 5 seats |
| van | 2.05 x 5.21 x 2.24 | 2894 / 232 | sliding door lines + window (right), rear double doors with windows, roof vent, seats: driver, passenger, `SeatRearL` only |
| taxi | 1.86 x 4.63 x 1.65 (with sign) | 2962 / 288 | `TaxiSign` mesh (LampGlow + Trim), checker stripe on the doors (Paint2 / Paint), estate/hatch silhouette, default Paint yellow |

Default exported Paint/Paint2 colours: police white / navy-black, suv blue / charcoal, pickup mustard / charcoal, van off-white / grey, taxi yellow / black (Godot overrides Paint at runtime).

## Known limits
No `Hood`/`Trunk` stretch nodes. Door glass is part of Body (stays when a door swings). Body has no collision helpers (use a hull from the AABB). Rim/brake detail is a 5-spoke star on a dished face (no separate brake discs).
