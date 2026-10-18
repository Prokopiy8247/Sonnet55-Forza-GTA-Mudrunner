# Blender landmarks (lane 7) - hero landmark buildings

Producer: Blender lane 7 (collection `GTA_GODOT/Buildings`, workshop slots `workshop(7, i, 60)`). Scripts: `tools/blender/lane7_lib.py` (helpers) and
`tools/blender/lane7_<id>.py` (one idempotent builder per asset, each starts by clearing `<id>__*`). Export: `export_glb(root, "buildings/<id>")`.

Conventions (all assets): origin = footprint centre at ground level, front door toward Blender +Y (= -Z in Godot), flat shaded low poly,
materials by name (`Window`, `Roof`, `Neon*`, `Glass`, `Light*`, `LampGlow` get Godot shader materials via `FacadeMaterials.for_glb`;
every other name is a generic colour material from the Blender colour). Each GLB contains `Body` (all visuals merged), `Collision`
(plain box/prism proxy mesh - skipped by `ContentLib.flatten`, used as trimesh collider by `LandmarkBuilder`) and the empties below.
`Window` faces are UV-mapped so every window quad is exactly one pane of the window shader grid (independent night lighting).
Signs are non-text emissive geometry (shield, cross, crosshair, droplet, hanger, scissors, spanner + wheel, P ...).

| id (`buildings/<id>.glb`) | footprint W x D, height | tris (Body + Collision) | empties (Blender local, front = +Y) | extra nodes |
|---|---|---|---|---|
| `police_station` | 30.9 x 22.5, 20.6 (mast) | 1996 | `Door` (0,10.4,0), `GarageDoor` (10,9.6,0), `RoofHelipad` (8,-4.5,11.7) | |
| `hospital` | 40.7 x 28.3, 27.9 (cross sign) | 2326 | `Door` (0,13.4,0), `AmbulanceBay` (15,12,0), `RoofHelipad` (14.5,-3.5,11.9) | |
| `weapon_shop` | 14.9 x 12.4, 10.0 | 1332 | `Door` (0,5.75,0) | |
| `garage_shop` | 24.6 x 18.3, 10.6 | 1542 | `Door` (0,8,0), `BayEntry` (-8,7,0), `BayInside` (-8,-1.5,0), `BayEntry_B` (8,7,0), `BayInside_B` (8,-1.5,0) | bays are open (drive-in) |
| `safehouse` | 16.5 x 14.4, 17.6 | 2082 | `Door` (-1.3,6.5,0), `GarageDoor` (6.7,-0.1,0) (door on the +X side wall) | |
| `gas_station` | 16.5 x 22.3, 9.8 | 1258 | `Door` (0,-1.9,0), `PumpPoint_1..4` (+-1.5 m beside each pump on the aisle side) | `Pump_1..4` meshes, origin = base centre |
| `clothing_store` | 12.4 x 14.2, 10.7 | 1322 | `Door` (0,6.8,0) | glass storefront (`Glass`) with mannequins inside |
| `barber` | 8.5 x 10.3, 7.1 | 963 | `Door` (1.8,4.8,0) | `BarberPole` mesh, origin = pole centre, axis Z (helical red/blue stripes, `Accent` caps) |
| `scuba_shop` | 12.5 x 10.4, 11.2 | 1635 | `Door` (2.5,5,0) | |
| `train_station_a` / `train_station_b` / `train_station` (same model) | 28.8 x 24.2, 21.4 (spire) | 1786 | `Door` (0,12.3,0), `PlatformA` (0,-1.5,0.9), `PlatformB` (2.5,-10,0.9) | platforms are 0.9 m high with ramps at their ends, canopies are not solid |
| `parking_garage` | 36.0 x 24.6, 14.2 | 1950 | `Door` (0,12.7,0) | Collision = decks + 3 wedge ramps + pillars + barriers + tower (ramps are drivable slopes, ~20 %) |

Notes for integration
* The world lots are bigger than the models (see `gta/tests/landmark_fit_dev.gd`, `tools\gd.ps1 exec -Script res://gta/tests/landmark_fit_dev.gd`):
  models are centred on the lot centre; `train_station_b` lot (21.2 m deep) is ~3 m shallower than the 24.2 m model.
* Vehicle-accessible interiors: only `garage_shop` (two open bays) and the `parking_garage` decks. All other buildings are solid.
* Materials unique to lane 7 (colour values live in `lane7_lib.CUSTOM`): TrimWhite, PoliceBlue/Navy, HospWhite/Teal/TealDk, NeonGreen/Amber/Red/White,
  Bunker, ConcreteDk, Hazard, SandBag, ShopOrange, Stucco/StuccoDk, Terracotta, ShutterTeal, GasRed, AwningCoral/White, BarberRed/Blue,
  TileTeal/TileDark, Mannequin, PlumDk, BrickRed, Copper, Slate, Cream, ClockFace, FlagRed/Blue, LineWhite, GarageWall/GarageDark/ToolRed.
