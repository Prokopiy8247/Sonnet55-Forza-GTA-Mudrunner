# Settlements kit (buildings + landmarks)

Script source of truth: `Tools/blender/settlements/settlements_kit.py` (parts: `bld_lib.py`, `bld_houses.py`, `bld_farm.py`, `bld_civic.py`, `bld_coast.py`, `bld_landmarks.py`, `bld_ruins.py`). Idempotent: `_g = {"__name__":"bld_kit"}; exec(compile(open(path).read(), path, "exec"), _g); _g["build"]([...]); _g["validate_all"](); _g["export"](id)`.

Blender staging: row `y = 100 m`, collections under `FORZA_UE/Settlements/<asset_id>`; exports `Exports/Settlements/<id>.fbx` + `<id>.json` (axis_forward -Y, axis_up Z, FBX_SCALE_ALL, one FBX per asset, `UCX_<id>_NN` hulls in the same FBX).

## Conventions

* 1 BU = 1 m, origin = ground centre of the footprint (bbox centre), +X = front/door side. All transforms applied, no negative scale.
* UV: `UVMap` = metric box projection (1 UV unit = 1 m) for tiling UE materials; vertex colour `Col` = per-part tint (multiplied by the UE material, white default).
* Materials (UE master-material instances by NAME): `M_Bld_Plaster, M_Bld_RoofTile, M_Bld_Wood, M_Bld_Stone, M_Bld_Metal, M_Bld_Window, M_Bld_Brick` + extras `M_Bld_PaintRed, M_Bld_PaintWhite, M_Bld_PaintBlue, M_Bld_Neon, M_Bld_Rubber` (<= 6 slots per asset).
* `M_Bld_Window` = dark reflective glass with an emission colour parameter (strength 0 in Blender): drive it from the UE day/night cycle. `M_Bld_Neon` is emissive.
* Tinted materials (Plaster, RoofTile, Wood, Stone, Brick, Paint*) multiply the `Col` vertex colour in Blender; mirror that in the UE master material (use `VertexColor` node).
* Nanite: all opaque, no manual LODs. Use standard LODs only if the window material is set translucent.

## Assets

| id | bbox X x Y x Z (m) | footprint | tris | collision hulls (tris) | file |
|---|---|---|---|---|---|
| bld_house_a | 8.3 x 9.6 x 6.6 | 7.0 x 9.0 | 7132 | 2 (20 tris) | `Exports/Settlements/bld_house_a.fbx` |
| bld_house_b | 13.4 x 10.2 x 7.7 | 11.0 x 9.0 | 9464 | 3 (32 tris) | `Exports/Settlements/bld_house_b.fbx` |
| bld_house_c | 7.3 x 8.6 x 9.7 | 6.0 x 8.0 | 12220 | 2 (20 tris) | `Exports/Settlements/bld_house_c.fbx` |
| bld_house_l | 11.3 x 11.9 x 6.1 | 10.0 x 11.0 | 10488 | 4 (40 tris) | `Exports/Settlements/bld_house_l.fbx` |
| bld_farmhouse | 10.3 x 11.6 x 10.1 | 9.0 x 11.0 | 16088 | 3 (32 tris) | `Exports/Settlements/bld_farmhouse.fbx` |
| bld_barn | 19.8 x 12.6 x 9.7 | 18.0 x 12.0 | 4486 | 2 (28 tris) | `Exports/Settlements/bld_barn.fbx` |
| bld_silo | 7.3 x 6.3 x 16.2 | dia 5.6 | 2976 | 2 (66 tris) | `Exports/Settlements/bld_silo.fbx` |
| bld_church | 18.5 x 8.7 x 19.4 | 18.0 x 7.5 | 24600 | 5 (58 tris) | `Exports/Settlements/bld_church.fbx` |
| bld_diner | 9.1 x 16.9 x 7.1 | 7.0 x 16.0 | 5252 | 3 (36 tris) | `Exports/Settlements/bld_diner.fbx` |
| bld_gas_station | 18.7 x 16.6 x 7.5 | 16.0 x 14.4 | 6484 | 7 (164 tris) | `Exports/Settlements/bld_gas_station.fbx` |
| bld_chalet | 13.2 x 11.5 x 11.9 | 10.0 x 9.0 | 13440 | 4 (44 tris) | `Exports/Settlements/bld_chalet.fbx` |
| bld_harbour_hut | 7.4 x 4.9 x 4.6 | 5.0 x 4.0 | 3160 | 2 (20 tris) | `Exports/Settlements/bld_harbour_hut.fbx` |
| bld_pier_4m | 4.0 x 2.6 x 4.0 | 4.0 x 2.4 | 1812 | 5 (92 tris) | `Exports/Settlements/bld_pier_4m.fbx` |
| bld_boat_row | 3.9 x 1.5 x 0.8 | 3.8 x 1.4 | 2376 | 1 (60 tris) | `Exports/Settlements/bld_boat_row.fbx` |
| bld_boat_fishing_8m | 8.4 x 2.9 x 6.8 | 8.2 x 2.9 | 2466 | 2 (72 tris) | `Exports/Settlements/bld_boat_fishing_8m.fbx` |
| bld_lighthouse | 8.6 x 8.6 x 22.0 | dia 6.8 | 3968 | 2 (90 tris) | `Exports/Settlements/bld_lighthouse.fbx` |
| bld_windmill | 8.7 x 7.9 x 9.7 | 8.7 x 7.9 | 4742 | 2 (66 tris) | `Exports/Settlements/bld_windmill.fbx` |
| bld_windmill_blades | 1.2 x 8.9 x 8.9 | dia 8.6 | 1068 | 0 (0 tris) | `Exports/Settlements/bld_windmill_blades.fbx` |
| bld_wind_turbine | 12.0 x 12.0 x 64.8 | 12.0 x 12.0 | 2020 | 2 (56 tris) | `Exports/Settlements/bld_wind_turbine.fbx` |
| bld_wind_turbine_rotor | 4.5 x 63.4 x 55.0 | 4.5 x 63.4 | 1806 | 0 (0 tris) | `Exports/Settlements/bld_wind_turbine_rotor.fbx` |
| bld_castle_wall_6m | 6.0 x 3.2 x 4.6 | 6.0 x 1.2 | 1720 | 3 (36 tris) | `Exports/Settlements/bld_castle_wall_6m.fbx` |
| bld_castle_tower_ruin | 10.2 x 11.2 x 9.9 | dia 6.0 | 5188 | 8 (120 tris) | `Exports/Settlements/bld_castle_tower_ruin.fbx` |
| bld_castle_arch | 7.6 x 4.8 x 6.7 | 7.6 x 1.2 | 1380 | 3 (36 tris) | `Exports/Settlements/bld_castle_arch.fbx` |

### bld_house_a - Village house A (7x9 m, plaster, gabled)

* Usage: Village house, ridge along Y, door on +X eave side
* Dimensions: bbox 8.3 x 9.6 x 6.6 m, footprint 7.0 x 9.0 m; tris 7132; material slots: Plaster, Stone, Window, Wood, Metal, RoofTile
* UE collision: `box` (2 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: village, temperate, greenvale
* Extra: {"height": 6.78}

### bld_house_b - Village house B (9x11 m, front gable + porch)

* Usage: Larger village house, gable faces +X, porch over the door
* Dimensions: bbox 13.4 x 10.2 x 7.7 m, footprint 11.0 x 9.0 m; tris 9464; material slots: Plaster, Stone, Window, Wood, Metal, RoofTile
* UE collision: `box` (3 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: village, temperate, greenvale
* Extra: {"porch": true}

### bld_house_c - Village house C (6x8 m two-storey, brick)

* Usage: Narrow two-storey brick town house, ridge along Y
* Dimensions: bbox 7.3 x 8.6 x 9.7 m, footprint 6.0 x 8.0 m; tris 12220; material slots: Brick, Stone, Wood, Metal, Window, RoofTile
* UE collision: `box` (2 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: village, town, temperate
* Extra: {"floors": 2}

### bld_house_l - Village house L-shape (10x11 m)

* Usage: L-shaped farm/village house, front arm along +X, door on the arm
* Dimensions: bbox 11.3 x 11.9 x 6.1 m, footprint 10.0 x 11.0 m; tris 10488; material slots: Plaster, Stone, Wood, Metal, Window, RoofTile
* UE collision: `box` (4 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: village, temperate, greenvale
* Extra: {"shape": "L"}

### bld_farmhouse - Farmhouse (9x11 m, two-storey, veranda)

* Usage: Two-storey farmhouse with front veranda, door on +X, ridge along Y
* Dimensions: bbox 10.3 x 11.6 x 10.1 m, footprint 9.0 x 11.0 m; tris 16088; material slots: Plaster, Stone, Window, Wood, Metal, RoofTile
* UE collision: `box` (3 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: farm, rural, temperate
* Extra: {"floors": 2, "veranda": true}

### bld_barn - Barn (18x12 m, gambrel roof, red boards)

* Usage: Gambrel barn; sliding doors on the +X gable end; ridge along X
* Dimensions: bbox 19.8 x 12.6 x 9.7 m, footprint 18.0 x 12.0 m; tris 4486; material slots: PaintRed, Stone, PaintWhite, Window, Metal
* UE collision: `box` (2 UCX hulls in the FBX); recommended scale range 0.85-1.20; biome tags: farm, rural, temperate
* Extra: {"roof": "gambrel"}

### bld_silo - Grain silo (5.6 m dia, 15.4 m)

* Usage: Corrugated grain silo with cone roof, ladder and fill pipe on +X
* Dimensions: bbox 7.3 x 6.3 x 16.2 m, footprint dia 5.6 m; tris 2976; material slots: Stone, Metal
* UE collision: `convex` (2 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: farm, rural, industrial
* Extra: {"diameter": 5.6, "height": 16.05}

### bld_church - Small church with bell tower

* Usage: Village church: nave along X, bell tower + door on +X, apse on -X
* Dimensions: bbox 18.5 x 8.7 x 19.4 m, footprint 18.0 x 7.5 m; tris 24600; material slots: Plaster, Stone, Window, RoofTile, Wood, Metal
* UE collision: `box` (5 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: village, temperate, landmark
* Extra: {"tower_height": 19.4}

### bld_diner - Roadside diner (16x7 m, flat roof, neon sign)

* Usage: Roadside diner, glazed front on +X, rooftop neon sign board
* Dimensions: bbox 9.1 x 16.9 x 7.1 m, footprint 7.0 x 16.0 m; tris 5252; material slots: PaintWhite, Stone, Window, Metal, PaintRed, Neon
* UE collision: `box` (3 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: roadside, usa, town
* Extra: {"sign": "DINER / OPEN 24H (neon relief M_Bld_Neon)"}

### bld_gas_station - Gas station (canopy with 4 pump islands + shop)

* Usage: Canopy over 4 pump islands + small shop (back), price pole at the front-left
* Dimensions: bbox 18.7 x 16.6 x 7.5 m, footprint 16.0 x 14.4 m; tris 6484; material slots: PaintWhite, Stone, Window, Metal, PaintRed, Neon
* UE collision: `box` (7 UCX hulls in the FBX); recommended scale range 0.90-1.15; biome tags: roadside, usa, highway
* Extra: {"pumps": 8, "islands": 4}

### bld_chalet - Mountain chalet / ski lodge (10x9 m, timber, steep roof)

* Usage: Timber chalet, gable and balcony face +X, stone ground floor
* Dimensions: bbox 13.2 x 11.5 x 11.9 m, footprint 10.0 x 9.0 m; tris 13440; material slots: Stone, Wood, Metal, Window, RoofTile
* UE collision: `box` (4 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: alpine, snow, mountain
* Extra: {"balcony": true}

### bld_harbour_hut - Harbour fisherman hut (5x4 m)

* Usage: Weathered timber hut with metal roof, door on +X; props (crates, barrels, rope) included
* Dimensions: bbox 7.4 x 4.9 x 4.6 m, footprint 5.0 x 4.0 m; tris 3160; material slots: Wood, Stone, Window, PaintBlue, Metal
* UE collision: `box` (2 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: coast, harbour, fishing

### bld_pier_4m - Pier segment (4 m, tileable along +X)

* Usage: Tileable pier segment: starts at x=0 on the centreline, runs 4 m along +X; z=0 = water surface, deck top at z=1.25
* Dimensions: bbox 4.0 x 2.6 x 4.0 m, footprint 4.0 x 2.4 m; tris 1812; material slots: Wood, Metal
* UE collision: `box` (5 UCX hulls in the FBX); recommended scale range 1.00-1.00; biome tags: coast, harbour, tileable
* Extra: {"length": 4.0, "width": 2.4, "deck_z": 1.25, "water_z": 0.0}

### bld_boat_row - Rowing boat (3.8 m, clinker)

* Usage: Clinker rowing boat, bow on +X, keel at z=0 (waterline ~ z=0.15)
* Dimensions: bbox 3.9 x 1.5 x 0.8 m, footprint 3.8 x 1.4 m; tris 2376; material slots: PaintBlue, Wood, Metal
* UE collision: `convex` (1 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: coast, lake, harbour
* Extra: {"length": 3.8, "beam": 1.42, "waterline_z": 0.16}

### bld_boat_fishing_8m - Fishing boat (8 m)

* Usage: Small trawler, bow on +X, keel at z=0 (waterline ~ z=0.75)
* Dimensions: bbox 8.4 x 2.9 x 6.8 m, footprint 8.2 x 2.9 m; tris 2466; material slots: PaintWhite, PaintRed, PaintBlue, Wood, Window, Metal
* UE collision: `convex` (2 UCX hulls in the FBX); recommended scale range 0.90-1.25; biome tags: coast, harbour, fishing
* Extra: {"length": 8.2, "beam": 2.9, "waterline_z": 0.75}

### bld_lighthouse - Lighthouse (22 m, white/red, lantern room)

* Usage: Coastal lighthouse; door on +X; lantern glass uses M_Bld_Window (emissive at night, rotate a light there)
* Dimensions: bbox 8.6 x 8.6 x 22.0 m, footprint dia 6.8 m; tris 3968; material slots: Stone, PaintWhite, PaintRed, Window, Wood, Metal
* UE collision: `convex` (2 UCX hulls in the FBX); recommended scale range 0.80-1.60; biome tags: coast, landmark, harbour
* Extra: {"height": 22.0, "tower_radius": 3.4, "lantern_z": 18.2}

### bld_windmill - Windmill (stone tower + cap, blades separate)

* Usage: Stone tower windmill; blades are bld_windmill_blades (pivot at hub, rotate about X); socket blades_hub
* Dimensions: bbox 8.7 x 7.9 x 9.7 m, footprint 8.7 x 7.9 m; tris 4742; material slots: Stone, Wood, Metal, Window, RoofTile
* UE collision: `convex` (2 UCX hulls in the FBX); recommended scale range 0.85-1.40; biome tags: rural, landmark, temperate
* Sockets (Blender metres, asset-local): {"blades_hub": [2.8, 0.0, 8.15]}
* Extra: {"height": 9.65, "hub": [2.8, 0.0, 8.15], "blade_radius": 4.2}

### bld_windmill_blades - Windmill blades (4 lattice sails, pivot at hub)

* Usage: Rotate about local X (rotor axis +X). Attach at windmill socket blades_hub = (2.8, 0, 8.15)
* Dimensions: bbox 1.2 x 8.9 x 8.9 m, footprint dia 8.6 m; tris 1068; material slots: Wood, Metal
* UE collision: `none` (0 UCX hulls in the FBX); recommended scale range 0.85-1.40; biome tags: rural, landmark, rotor
* Extra: {"blades": 4, "radius": 4.3}

### bld_wind_turbine - Wind turbine tower + nacelle (60 m tower, rotor separate)

* Usage: Tower 60 m + nacelle; rotor is bld_wind_turbine_rotor (pivot at hub; rotate about X); socket rotor_hub
* Dimensions: bbox 12.0 x 12.0 x 64.8 m, footprint 12.0 x 12.0 m; tris 2020; material slots: Stone, Metal, PaintWhite, PaintRed
* UE collision: `convex` (2 UCX hulls in the FBX); recommended scale range 0.70-1.40; biome tags: energy, landmark, highland, coast
* Sockets (Blender metres, asset-local): {"rotor_hub": [5.6, 0.0, 61.85]}
* Extra: {"tower_height": 60.0, "hub_height": 61.85, "hub": [5.6, 0.0, 61.85], "rotor_diameter": 73.0}

### bld_wind_turbine_rotor - Wind turbine rotor (3 blades x 35 m, pivot at hub)

* Usage: Rotate about local X. Attach to the turbine at socket rotor_hub = (5.6, 0, 61.85). Blade length 35 m from hub radius 1.5 m
* Dimensions: bbox 4.5 x 63.4 x 55.0 m, footprint 4.5 x 63.4 m; tris 1806; material slots: PaintWhite, PaintRed, Metal
* UE collision: `none` (0 UCX hulls in the FBX); recommended scale range 0.70-1.40; biome tags: energy, landmark, rotor
* Extra: {"blades": 3, "blade_length": 35.0, "hub_radius": 1.5}

### bld_castle_wall_6m - Castle ruin wall segment (6 m)

* Usage: Ruined curtain wall: starts at x=0 on the centreline, runs 6 m along +X, ends are full height (4.7 m) so segments chain
* Dimensions: bbox 6.0 x 3.2 x 4.6 m, footprint 6.0 x 1.2 m; tris 1720; material slots: Stone
* UE collision: `box` (3 UCX hulls in the FBX); recommended scale range 0.90-1.20; biome tags: ruin, castle, medieval
* Extra: {"length": 6.0, "thickness": 1.2, "max_height": 4.7}

### bld_castle_tower_ruin - Castle corner tower ruin (round, 9.5 m, wall stubs)

* Usage: Round corner tower ruin with doorway facing +X and two wall stubs running to -X and -Y; origin = tower centre
* Dimensions: bbox 10.2 x 11.2 x 9.9 m, footprint dia 6.0 m; tris 5188; material slots: Stone
* UE collision: `convex` (8 UCX hulls in the FBX); recommended scale range 0.90-1.25; biome tags: ruin, castle, medieval
* Extra: {"radius": 3.0, "height": 9.9}

### bld_castle_arch - Castle ruin arch (7.6 m wide, 6.9 m high)

* Usage: Free-standing ruined arch; opening 4.4 m wide, passable; axis through the arch = Y
* Dimensions: bbox 7.6 x 4.8 x 6.7 m, footprint 7.6 x 1.2 m; tris 1380; material slots: Stone
* UE collision: `box` (3 UCX hulls in the FBX); recommended scale range 0.90-1.30; biome tags: ruin, castle, medieval
* Extra: {"opening_width": 4.4, "opening_height": 5.4, "height": 6.9}

## UE usage notes

* Buildings: place with the door facing the road (+X = front). Footprints in the table above are wall footprints; add the roof overhang (bbox) when checking clearance to roads/neighbours (keep >= 1 m).
* Collision: import the FBX with its `UCX_*` hulls (Custom collision, no auto-generate). Rotor parts have no collision.
* `bld_windmill_blades` / `bld_wind_turbine_rotor`: separate static meshes with pivot at the hub; attach to a Scene component at the documented socket and rotate about local X (RotatingMovement, ~20-40 deg/s for the turbine, ~15 deg/s for the windmill).
* `bld_pier_4m`: chain along +X every 4.0 m (piles every 2 m keep the spacing uniform); z=0 is the water surface. `bld_castle_wall_6m` chains along +X every 6.0 m.
* Boats: keel at z=0; set the actor so the waterline height (see Extra) sits on the water plane. No buoyancy/physics shipped.
* Lighthouse: lantern glass (`M_Bld_Window`) is a separate material slot - add a spot light / rotating beam at `lantern_z` for night.
* Randomise `Col`-tint-independent variety in UE via material instance parameters (plaster hue, roof hue) - geometry variants: 4 houses + farmhouse + chalet.

## Known weaknesses

* Buildings are hollow shells without interiors (windows are opaque dark glass); no interior floors/rooms.
* Roof tiles are modelled as stepped courses (silhouette + shading) - the fine tile pattern must come from the UE material.
* Church windows/clock/belfry openings are applied relief (not real openings); houses/barn/diner/shop windows and doors are real openings with reveals.
* Ruin masonry uses 12-tri stone blocks with chamfered fronts: reads well at game distance, close-ups need a stone normal map.
* Wind-turbine blades are a stylised NACA-like airfoil loft (no internal structure); tower is a smooth tapered tube with flange rings.
* Boats are single static hulls (no interior detail below the thwarts, no rigging ropes); fishing boat hull is closed above the deck.
* No LOD chains were authored (Nanite assumed); `M_Bld_Window` translucency not used.
* Lighthouse/windmill/turbine bounding boxes are tall: check UE bounds scale / shadow distance settings.