# Blender lane 13 - trains, shooting range, dealer lot, police / race / beach / park props, rocket

Authored in Blender through MCP, exported with `gta_lib.export_glb`. Objects stay in the master `.blend` under `GTA_GODOT/Vehicles` (trains),
`GTA_GODOT/Buildings` (shooting_range, dealer_lot), `GTA_GODOT/StreetProps` (props) and `GTA_GODOT/Weapons` (rocket); workshop row `workshop(13, slot, spacing)` (y = 2160).
All GLBs: `res://gta/generated/models/<category>/<id>.glb`, metres, flat shaded, colours only (named materials), origin / front per ARCHITECTURE s7
(front = Blender +Y = **-Z in Godot**, `<assetid>__` prefix stripped, root children are the top level nodes).
**Materials import with `cull_mode = DISABLED`** (glTF `doubleSided`), so flags, tapes, nets, glass etc. are single quads that show from both sides.

## 1. Files, nodes, sizes (tris are probe-verified in Godot 4.7.2)

| GLB | size X x Y(up) x Z m | tris | nodes (exact names) |
|---|---|---|---|
| `vehicles/train_car` | 2.80 x 3.65 x 16.0 | 2704 | `Body`, `Door_L1 Door_L2 Door_R1 Door_R2`, `Bogie_F`, `Bogie_R`, empties `SeatPoint_1..6`, `ExitL1 ExitL2 ExitR1 ExitR2`, `CoupleF`, `CoupleR`, `InteriorLight` |
| `vehicles/train_locomotive` | 2.80 x 4.36 (with pantograph; body 3.6) x 16.04 | 2808 | `Body`, `DoorL1`, `DoorR1`, `Pantograph`, `Bogie_F`, `Bogie_R`, empties `HeadlightL/R`, `TaillightL/R`, `SeatDriver`, `SeatPassenger`, `SeatPoint_1..6`, `ExitL`, `ExitR`, `CoupleF`, `CoupleR`, `Horn`, `PantographTip`, `InteriorLight` |
| `buildings/shooting_range` | 37.3 x 7.1 x 34.2 (x -17..20.3, z -17.2..17) | 2865 (Body 2700 + Collision 165) | `Body`, `Collision`, empties `Door`, `Lane_1..5`, `Target_1..5`, `FiringLine`, `RangeBeacon` |
| `buildings/dealer_lot` | 60.0 x 8.4 x 40.15 | 2604 (Body 2468 + Collision 136) | `Body`, `Collision`, empties `Door`, `Stall_1..12`, `Showroom`, `PriceBoard` |
| `props/range_target` | 0.8 x 1.85 x 0.6 | 302 | `Body` (stand + housing), `Plate` (hit mesh), `Hinge` |
| `props/range_target_round` | 0.9 x 1.2 x 0.6 | 320 | `Body`, `Plate`, `Hinge` |
| `props/spike_strip` | 4.4 x 0.135 x 0.32 | 288 | `Body` |
| `props/police_barrier` | 3.08 x 1.2 x 1.0 | 224 | `Body`, `LightBar` (origin = bottom centre, at z 1.0), `LightPoint` |
| `props/police_tape` | 2.42 x 1.17 x 0.42 | 268 | `Body` |
| `props/roadblock_sign` | 1.0 x 2.32 x 0.8 | 267 | `Body`, `LightPoint` |
| `weapons/rocket` | 0.38 x 0.38 x 1.535 (body 1.015 + flame 0.5) | 266 | `Body`, `Flame`, empties `Exhaust`, `Tip` |
| `props/shell_casing` | 0.011 x 0.011 x 0.020 | 80 | `Body` |
| `props/stunt_ramp_sign` | 1.98 x 1.79 x 0.6 | 212 | `Body` |
| `props/finish_line_banner` | 13.4 x 8.58 x 1.2 | 466 | `Body`, empty `Line` |
| `props/race_checkpoint` | 6.7 x 6.2 x 0.6 | 376 | `Ring`, `Body` (base pads), empty `Centre` |
| `props/beach_umbrella` | 2.3 x 2.44 x 2.29 | 142 | `Body` |
| `props/beach_towel` | 0.85 x 0.14 x 1.95 | 90 | `Body` |
| `props/deck_chair` | 0.7 x 1.0 x 1.02 | 196 | `Body` |
| `props/surfboard_rack` | 2.5 x 2.08 x 0.76 | 346 | `Body` |
| `props/volleyball_net` | 12.4 (net 9.5 + guy ropes) x 3.24 x 0.36 | 360 | `Body` |
| `props/campfire` | 1.45 x 1.2 x 1.46 | 243 | `Body` (stones, logs, ash), `Flame` (emissive), `LightPoint` |
| `props/tent` | 3.85 (with guy ropes; tent 2.2 x 2.8) x 1.53 x 5.45 | 150 | `Body`, `Entrance` |
| `props/picnic_table` | 1.9 x 0.77 x 1.7 | 148 | `Body`, `SeatPoint_1..4` |
| `props/trash_can_park` | 0.61 x 0.92 x 0.61 | 142 | `Body`, `UsePoint` |
| `props/swing_set` | 3.5 x 2.27 x 2.17 | 324 | `Body`, `Swing_1`, `Swing_2` (origin = top pivot, hang down -Z_blender), `SeatPoint_1..2` |
| `props/slide` | 0.91 x 2.17 x 4.13 | 292 | `Body`, `LadderPoint`, `SlideStart`, `SlideEnd` |
| `props/ice_cream_cart` | 2.04 x 3.18 x 1.64 | 448 | `Body`, `ServePoint` (customer side, front), `VendorPoint` (behind) |
| `props/hotdog_stand` | 2.04 x 2.78 x 1.64 | 518 | `Body`, `ServePoint`, `VendorPoint` |

Over the soft prop budget (300): range_target_round 320, surfboard_rack 346, volleyball_net 360, swing_set 324, ice_cream_cart 448, hotdog_stand 518, race_checkpoint 376, finish_line_banner 466. They are single draw
sets of flat colours; none is a hot-path asset. Buildings are 2.6-2.9 k tris (lane 7 landmarks are 1.0-2.3 k).

## 2. Trains (`vehicles/train_car`, `vehicles/train_locomotive`)

Frame (Godot): train forward = **-Z**, origin = ground point under the car centre **on the rail head** (y = 0 is the rail top / wheel tread), x = 0 on the track centre line.
Rail gauge 1.435 m (wheel tread centres x = +-0.7175, wheel radius 0.45; flanges dip 5 cm below y = 0 as a real flange does).
NOTE: `WorldLayout.rail` uses gauge 1.5 (rail centres +-0.75); the 3 cm difference is invisible, but you can scale `Bogie_*` x by 1.045 if you want it exact.

* Body: 16.0 m long (`CoupleF/CoupleR` at +-8.0, y 0.7), 2.66 m wide shell (2.8 m with the hung doors), floor top y = **1.0**, ceiling y = 3.0, roof apex 3.46, rooftop gear to 3.6.
  The locomotive has a raked faceted nose (+Y_blender, windscreen `Glass`), cab with console and 2 seats, saloon with 12 bench seats, `Pantograph` (separate mesh, origin = base centre on the roof, y 3.46;
  folded low, tip at y 4.3 = `PantographTip`), twin air horns (`Horn`), head lamps (`LightHead` / `LightAmber`), rear red marker lamps (`LightTail`).
* `Bogie_F` (Godot z = -5.0) and `Bogie_R` (z = +5.0): meshes whose origin is the bogie centre ON the rail head -> rotate them about local Y for curves. Wheels (tread, flange, hub), axles, motors,
  frames and springs are part of the bogie mesh (axle spin is not separately animated).
* Doors (`Door_L1/L2/R1/R2`, loco `DoorL1/DoorR1`): single leaves that hang **outside** the wall (x = +-1.335..1.40) and slide **along the car length (Godot Z), not along X** (a plug-style door cannot slide along X
  without cutting through the wall). Origin = bottom centre of the closed leaf (Godot (+-1.33, 1.0, z_door)). Open offset ~1.45 m into the blank pocket: `Door_*1` (rear half, Godot z = +4.0) opens towards +Z (the rear),
  `Door_*2` (front half, z = -4.0) opens towards -Z; loco `DoorL1/DoorR1` (z = -2.6) opens towards +Z. Left = -X.
* Livery: materials `Paint` (cream white #ece8dc) and `Paint2` (teal #2f9c95) are the SHARED names, baked with those colours - recolour by name if you want a different line colour. `Neon` = magenta accent stripe.
  Interior: `TrainFloor`, `TrainInner`, `TrainCeil`, `TrainGlow` (ceiling strips - toggle emission at night), `TrainSeat`, `TrainSeatDk`, `TrainCoral`, `Chrome` poles, `CabConsole` (emissive).
* Passenger anchors: `SeatPoint_1..3` left bench (x = -0.98, facing +X: the empty's -Z axis points across the aisle), `SeatPoint_4..6` right bench (x = +0.98, facing -X); y of the empty = cushion top + 0.2 (1.68),
  Godot z = +2.15 / 0 / -2.15 (car) or +5.0 / +2.8 / +0.62 (loco). `Exit*` empties are on the platform side at |x| = 2.25 at rail-head height (y = 0); the real floor is 1.0 m above the rail head -
  teleport the player to the `Exit*` empty or step them down.
* No collision shapes are baked: use a floor box (x +-1.23, y 1.0, z +-7.8) + wall boxes, or the gameplay ride can be a kinematic carrier. `InteriorLight` = where to hang an OmniLight (y 2.85).

## 3. Shooting range (`buildings/shooting_range`)

Footprint ~37 x 34 m (booth back wall + hut face the street = Godot -Z of the model). Origin = footprint centre at ground.
* Firing line booth: 5 lanes of 3.2 m, back wall (street side) with a neon bullseye emblem, flat roof on posts with `LampGlow` strips, 6 divider panels (4 interior + the 2 end walls - the brief asked for 5), counters 1.07 m high with sandbag
  rest and a small controller box (`LightRed` + `NeonGreen` buttons), lane number plates (tally marks) on the roof fascia, hearing-protection boards on the back wall, red/green status beacons.
* `Lane_1..5` = firing positions (x = -10.4, -7.2, -4.0, -0.8, 2.4 blender; y 13.3 blender, on the apron at 0.10 m). The empties are rotated 180 deg about Z: their **-Z axis (Godot forward) points down range**.
  `Target_1..5` = 25.0 m down range (same x, blender y -11.7), unrotated, front faces the shooters: put `props/range_target` there. A hanging gantry rail (`Metal`) with trolleys runs along the target line, floor distance bars at 5/10/15/20/25 m.
* Backstop: stepped sandbag berm (3.4 m) + sandbag side walls with hazard caps; flags (`FlagRed` on the roof = live fire, `FlagBlue` pole at the entrance), 5 warning-sign triangles + a red "no entry" roundel, roadside pylon with a big neon bullseye (two sided).
* Office hut (8 x 8 m, x 9..17, y 6..14): `Door` empty is 1.9 m in front of the door (blender (13, 15.9, 0)), small canopy, windows (`Glass`), bench, bin.
* `Collision` = box proxies (back wall, dividers, counters, roof band, side walls, berm, hut) - use as trimesh like lane 7. The world lot (`LayoutLots`: 39 x 34 m, yaw "w") matches; everything is inside x -17..20.3.

`props/range_target`: stand with housing (`Body`) + `Plate` (faceted human silhouette, 1.55 m tall, 126 tris: black plate, scoring rings `TargetRed`/`TargetWhite` on the +Y face, head ring). **`Plate` origin = hinge bottom centre**
(blender (0,0,0.30) above the ground). Stand it up = rotation 0; flip down = rotate `Plate` about local X by **+90 deg** (Godot: falls backwards away from the shooter, face up, lies at hinge height on top of the housing) - never -90
(that would fold it towards the shooter). `Hinge` empty = same point. Hit test: trimesh from `Plate` (0.03 m thick). `range_target_round` has the same stand and a 0.9 m bullseye `Plate` (rings white/black/white/red/white/red).

## 4. Dealer lot (`buildings/dealer_lot`)

60 x 40 m paved lot (kerbs, 12 m gate gap at the front), glass sales office (18 x 9.3 m, x -9..9, y -19.3..-10 blender = BACK of the lot) under a 21 x 14 m canopy on 4 columns with emissive underside and a neon car sign on the roof (two sided),
12 stall markings, string-light poles (`LampGlow` bulbs) + pennant strings along the front, 2 flag poles at the gate, a price board (non-text), a showcase ramp (x 14..23), a low fence frame on 3 sides, a lobby with desk and chairs.
* `Stall_1..12`: stall centres at the nose-to-street row y = 10.75 blender (Godot z = -10.75): x = -21.1, -17.9, ..., -5.1 (Stall_1..6) and +5.1 ... +21.1 (Stall_7..12), stall 3.2 x 5.5 m, empty has no rotation: a car placed at the empty with identity
  rotation faces the street (-Z Godot = blender +Y). Car origin = wheelbase centre, so cars sit centred in the stall.
* `Door` = approach point in front of the office glass door (blender (0, -8.4, 0.25)). `Showroom` = top of the ramp (blender (18.5, -4, 0.9)). `PriceBoard` = board centre.
* **Size caveat:** the world's `dealer_lot` landmark rect is only ~12.6 m deep (LayoutLots), the model is 40 m deep: either enlarge the lot or place the GLB so that the front kerb is at the street and let it overlap the empty parking strip.

## 5. Police, race, rocket and misc props

* `spike_strip`: 8 hinged plates 4.0 m long with 40 chrome spikes (z up to 0.135) and hazard end handles. `police_barrier`: sawhorse-style barricade, `LightBar` (`LightBlue` left half, `LightRed` right half - flash by material name) mounted at z 1.0.
  `police_tape`: two weighted stands 2.0 m apart, two sagging tape strands (`Hazard` / `TargetBlack` chevrons). `roadblock_sign`: detour diamond (`SafetyOrange` + black bent arrow) + chevron plaque on a weighted stand, `LightAmber` beacon (`LightPoint`).
* `weapons/rocket`: projectile along +Y blender (-Z Godot), origin = body centre, body 1.015 m (dark body `Rocket`, `RocketOrange` nose + 4 fins, `Hazard` ring, `MetalDark` nozzle), `Flame` = emissive exhaust cone (material `Flame`, behind the nozzle; hide/scale it for the rocket's burn), `Exhaust` empty at the nozzle (smoke trail), `Tip`.
* `shell_casing`: 9 mm brass case 0.019 m long lying along +Y (mouth +Y), `Brass`.
* `stunt_ramp_sign`: 1.98 x 1.79 yellow `Hazard` board with 3 black chevrons (front +Y), on 2 posts behind the board, `NeonAmber` studs.
* `finish_line_banner`: 12 m gate (posts at x = +-6.0) with a 12.4 x 0.9 m chequered banner (both faces, `ChequerBlack`/`ChequerWhite`), neon arch (`NeonCyan`), `Neon` underline, `LampGlow` spots, red/amber/green pods on both posts (`SignalRed/Amber/Green` - light by name for a start sequence). Drive through along blender Y. `Line` = ground line centre.
* `race_checkpoint`: `Ring` = 6 m diameter thin torus in the XZ plane (hole along Y: drive through along +-Z Godot), material `RingGlow` (translucent emissive `#34e0ff`, alpha 0.55, emission 4), centre at y = 3.12; `Body` = two small base pads with `NeonCyan` strips; `Centre` empty. Scale the `Ring` node to resize.

## 6. Beach / park set pieces

All 0.0 at the footprint centre, front +Y, no collision. `beach_umbrella` (8 coral/white panels, leans 8 deg to +Y, sand mound base), `beach_towel` (striped, fringe, rolled pillow), `deck_chair` (striped sling),
`surfboard_rack` (5 boards, 2.5 m wide), `volleyball_net` (9.5 m net on two padded posts + guy ropes; centred), `campfire` (8 stones, 4 logs, `Flame` emissive mesh + `LightPoint` for the OmniLight), `tent` (A-frame 2.2 x 2.8 m, door +Y, `Entrance` empty 1 m in front),
`picnic_table` (long axis X; `SeatPoint_1/2` on the +Y bench rotated 180 deg so they face the table, `SeatPoint_3/4` on the -Y bench facing +Y), `trash_can_park` (slatted bin, `UsePoint`), `swing_set` (rotate `Swing_1/2` about their local X to swing; chains 1.6 m, `SeatPoint_n` at rest),
`slide` (platform 1.3 m, `LadderPoint` at the foot of the ladder (-Y), `SlideStart`, `SlideEnd`), `ice_cream_cart` and `hotdog_stand` (2 m wide push-cart stalls with striped canopy and a roof sign; `ServePoint` in front where customers stand, `VendorPoint` behind the counter).

## 7. Materials introduced by lane 13 (plain Principled colours, replace by name where useful)

Train: `TrainFloor TrainInner TrainCeil TrainGlow TrainSeat TrainSeatDk TrainCoral CabConsole`. Range / police: `TargetRed TargetWhite TargetBlack TargetTan SandBag Hazard RailYellow ConcreteDk PoliceNavy PoleGrey PoleGreen FlagRed FlagBlue
TrimWhite LineWhite NeonAmber NeonRed NeonGreen NeonWhite WoodLight WoodDark WoodPale ConeOrange SafetyOrange Reflector ReflectRed RopeTan PlateRed/White/Blue/Yellow MetalLt` (names shared with lanes 7 / 9 use identical values).
Dealer / race / misc: `DealerTeal DealerNavy StallPaint PavingDark PavingLight ChequerWhite ChequerBlack RingGlow Rocket RocketOrange Flame Brass`. Godot replace-by-name candidates: `Glass`, `LampGlow`, `LightHead/LightTail/LightAmber/LightBlue/LightRed`,
`Neon*`, `RingGlow`, `Flame`, `TrainGlow`, `Paint/Paint2` (train livery), `WallA/WallD`, `Roof`, `SignalRed/Amber/Green`.

## 8. Gotchas for code

1. Models are not resized by the exporter - dimensions in section 1 are real metres. Train height 3.6 m body, 4.36 m with the pantograph.
2. Train doors slide along the car LENGTH (see 2). Door meshes are separate nodes with their own origin on the wall plane.
3. `Bogie_*` positions are z = -5.0 (F) / +5.0 (R) in Godot; the loco/car are symmetric front/back except the nose and lamps (car: `LightHead` at +Y, `LightTail` at -Y end).
4. Buildings contain `Collision` (skip it when flattening visuals, use it as trimesh); props have none.
5. `Lane_n` empties face DOWN RANGE (rotated 180 deg), `Target_n` and `Stall_n` empties are unrotated (face -Z Godot).
6. Everything is flat shaded with duplicated vertices (weld disabled so explicit normals survive); that is why vertex counts are ~3x the triangle counts.
7. Not verified in-game: nothing here has been spawned by gameplay code; GLBs were probed (`glb_probe`) and the trains / range were rendered through `blender10_nature_showcase.gd` (`screenshots/l13_train.png`, `l13_range.png`).

## 9. Rebuild

Scripts (`tools/blender/`): `lane13_lib.py` (HB explicit-normal builder, lathe, torus, A13 asset container), `lane13_traincommon.py`, `lane13_train_car.py`, `lane13_train_locomotive.py`, `lane13_range_target.py`,
`lane13_shooting_range.py`, `lane13_dealer_lot.py`, `lane13_police_props.py`, `lane13_misc_a.py` (rocket, shell_casing, race_checkpoint, finish_line_banner, stunt_ramp_sign), `lane13_beach.py`, `lane13_park.py`, runner `lane13_run.py`.
Inside Blender: `exec(open(r"...\tools\blender\gta_lib.py").read(), globals()); assert_master(); LANE13_SCRIPT = "lane13_train_car.py"; exec(open(r"...\tools\blender\lane13_run.py").read(), globals()); A.export("vehicles/train_car")`
(every builder script clears its own `<id>__*` objects first and leaves the asset object(s) in `A` / `A1..`).
