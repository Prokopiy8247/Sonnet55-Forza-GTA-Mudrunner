# World (World-Layout agent) - map, graphs, geometry

Owner: `gta/code/world/world_root.gd`, `world_layout.gd`, `layout_*.gd`, `terrain_builder.gd`, `road_builder.gd`, `water_builder.gd`,
`airport_builder.gd`, `pier_builder.gd`, `rail_builder.gd`, `stunt_builder.gd`, `world_boundary.gd`, `sector_manager.gd`,
`generated/shaders/world_*.gdshader`, tests `gta/tests/world_*.gd`.
Boot: `WorldRoot.setup()` -> `WorldLayout.generate()` (deterministic, ~0.3 s, idempotent: any module may call it earlier) -> terrain,
water, boundary, roads/sidewalks/paint, airport, piers, rail, stunt ramps -> `CityBuilder.build(world)` (World-Content). Whole world builds in
about 1.5 s headless (test `world_layout_test.gd` asserts < 6 s). Sets `Game.world`.

## 1. Map (x east, z south, y up; playable ground [-300,300]^2, sea continues to z = 398; urban plateau y = 0, sea level -1.5)
| district (`GC.D_*`) | rect (x0,z0 .. x1,z1) | notes |
|---|---|---|
| downtown | -108,-92 .. 108,134 | 4x4 line grid (x = -105,-35,35,105; z = -90,-20,50,120), 70 m blocks, 16 signalised junctions, 3 one-way alleys, central plaza + 28-floor tower (helipad) |
| residential (Westbrook) | -300,-250 .. -108,90 | houses/apartments on frontage lots, cul-de-sacs (Cedar/Oak Court), loop (Linden Loop), pocket park with path circle, safehouse |
| industrial (Foundry District) | 108,-62 .. 300,86 | warehouses, factories, yards, garage, shooting range, station B; 50 km/h roads, truck turn-arounds |
| waterfront (Harbor) | -300,90 .. -100,200 | quay (seawall 1.5 m above water), dock streets, 3 piers + marina fingers, warehouses, marina office, scuba shop |
| beach | -100,134 .. 76,200 | sand slope (z 156..176), promenade z~157, palms, beach pier (x 0, z 168..212), Seaview Drive (z 148) |
| airport (Halcyon Airfield) | 76,86 .. 300,200 | runway z=165 x 76..296 (220 m, 26 m wide), taxiway z=138, apron x 128..250 z 110..132, 3 hangars, terminal, tower, helipad (238,121) |
| park_hills | -108,-300 .. 300,-92 (+ north strip) | Greenhill Park (x -100..40, z -200..-95, pond at (-80,-152) r 21), NE hills peak (215,-228) ~48-55 m, Summit Road switchbacks, viewpoint |
| sea | terrain < -1.5 | `WorldLayout.district_at` returns `GC.D_SEA` (piers report waterfront) |

Roads (class, speed): **Halcyon Ring** arterial 2+2 80 km/h (rectangle x +-105, z -90..120, rounded SE corner, signals at all junctions), Ridge Road
(105,-90)->(190,-90) and **Eastern Link** x=190 z -90..85 arterial 80 km/h, downtown streets (Alder x=-35, Birch x=35, Cedar z=-20, Dune z=50) 50 km/h,
alleys one-way 25 km/h, Foundry St / Industrial Ave / Depot St / Terminal Rd (airport + industrial, 50), Northern Ave (z=-215), Parkway (x=-35, park),
Greenway loop, Westside Road (x=-262), Parkside, Westbrook, Harbor Road (z=120), Maple Lane (x=-185), Seaview Drive (coastal, z=148), dock streets
(Crane Way x=-225, Pier Road x=-146), residential streets 40 km/h, **Summit Road** (hill, 395 m of switchbacks to the viewpoint, ~10 % grade, cut into the hill).
Loops for chases: Ring (829 m), Ring + Eastern Link + Industrial Ave / Terminal Rd (85 m x 140 m), Ring + Parkway + Northern Ave + Westside + Harbor Road (~1.6 km).
All 68 road-net nodes are connected; the lane graph is 100 % reachable from the player spawn (test).

## 2. Public API (`WorldLayout`, all static)
- Data: `lanes: LaneGraph`, `ped_graph: PedGraph`, `signals`, `locations`, `districts`, `roads`, `building_footprints`, `lots`, `furniture`,
  `nature_zones`, `airport`, `piers`, `water_polys`, `built` (true after `generate()`), `build_ms`. Additive: `rail`, `water_volumes`.
- Queries: `terrain_height(x,z)` (triangle-exact with the mesh/collider, 3 m grid), `is_water(x,z)` (terrain < -1.5 and not on a pier),
  `on_pier(x,z)`, `pier_height(x,z)`, `district_at(x,z)`, `surface_at(x,z)` (&"grass" &"sand" &"concrete" &"rock" &"water" &"wood" for bare ground),
  `road_at(x,z,max_d=14) -> {edge, dist, dir, name, class, half_width, on_road, on_sidewalk}` or `{}`,
  `get_location(id)`, `location_pos(id)`, `has_location`, `locations_of_kind`, `is_inside_world`.
- Signals: `signal_state(sig_id, phase, t) -> 0 green / 1 yellow / 2 red` (phase 0 = green first half of the 26 s cycle, yellow 2.5 s at the end of each half,
  no all-red gap), `red_time_left(sig, phase, t)`, `crossing_open(ped_point_idx, t, min_left=4.0)`.
- `signals[i] = {id, pos, cycle, yellow, offset, node}` (25 junctions).

### LaneGraph (`WorldLayout.lanes`, 4.4 k points)
Points on lane centres every ~7 m, tangent `dirs`, `speed_limit` (m/s), `road_id` (= road-net edge id), `kind` (STRAIGHT / CONNECTOR / HIGHWAY for the 80 km/h
arterial lanes). Right-hand traffic: lane 0 is the one next to the centre line; `right_of[i]` / `left_of[i]` link same-direction neighbour lanes (arterial 2+2).
Junction connectors are Bezier paths (straight / left / right; left turns use the innermost lane, right turns the outermost); dead-end bulbs have U-turn connectors,
so every point has a successor and a predecessor (test). Stop lines: `signal_id[i] >= 0` marks the point 6.6 m before the junction mouth (car centre; the painted
line is 2.2 m ahead), `signal_phase[i]` = the signal phase (0/1) that lets that approach go (arms along z are phase 0, along x phase 1). Unsignalised minor roads have stop signs
(furniture) but no stop line in the graph. Hill road and alleys are in the graph too (alleys one-way, 25 km/h).

### PedGraph (`WorldLayout.ped_graph`, 2.1 k points, 96 % connected)
Sidewalk points every 8 m on both sides of every road with sidewalks (zone SIDEWALK, y = ground + 0.15), corner nodes, crossings (zone CROSSING) at every junction
arm (points across the whole road incl. a middle point on wide roads), park paths (PARK: pond ring, lawn paths, pocket park), plaza, beach promenade + sand spokes
(BEACH), quay promenade + pier centre lines (DOCK). Crossing points carry `signal_id` (-1 = uncontrolled) and `walk_phase` = the **traffic phase of the vehicles being
crossed**: pedestrians may enter while `signal_state(signal_id, walk_phase, t) == 2`, helper `WorldLayout.crossing_open(idx, t)` also requires >= 4 s of red left.

### Lots (`WorldLayout.lots`, 120+) / footprints
`{id, rect (axis aligned, x,z), yaw (front faces the street; Util convention, multiples of 90 deg), district, kind, landmark, floors, height, palette, side ("n","s","e","w" = facing),
ground}`. `ground` (additive) is "" or &"parking"/"plaza"/"yard"/"lawn" for flat paved/grass pieces drawn by the world (kind `empty`/`park`, nothing else to build).
Landmark lots (kind `landmark`, id = location id): police_station, gas_station, weapon_shop, barber, clothing_store, train_station_a/b, dealer_lot, hospital, garage_shop,
shooting_range, airport_terminal, airport_tower, marina_office, scuba_shop, safehouse. Downtown tower lot (28 floors, kind office) hosts `helipad_downtown`.
`dealer_lot` forecourt: the 12 m deep parking strip right in front of the showroom (kind `empty`, ground "parking"); the location sits in its centre.

### Furniture (`WorldLayout.furniture`, ~1000)
lamps every ~30 m (staggered), signal heads (`signal_id`, `phase` = traffic phase of the approach the head faces; 2 heads on arterial approaches), stop / speed signs, hydrants, benches,
bins, bollards (quay + pier tips), bus stops, cones/barriers at 2 work sites + hill-road guard barriers, fences (yards, airfield), utility boxes, mailboxes, parking meters,
billboards, palms (promenade), street trees.

### Locations (all required ids exist; `pos` y = ground/deck; `yaw` = direction a person faces when leaving the door / a vehicle should face)
| id | pos (x, y, z) | yaw deg | kind | name |
|---|---|---|---|---|
| `player_spawn` | (14.0, 0.1, 38.0) | 0 | spawn | Central Plaza |
| `safehouse` | (-208.0, 0.2, -14.4) | 0 | safehouse | Safehouse |
| `hospital` | (96.4, 0.2, 77.3) | -90 | service | Halcyon General Hospital (respawn) |
| `police_station` | (-68.3, 0.2, -81.4) | 0 | service | Harbor Police HQ (arrest respawn) |
| `weapon_shop` | (-83.4, 0.2, -14.4) | 0 | shop | Gunsmith |
| `clothing_store` | (-54.9, 0.2, -14.4) | 0 | shop | Threads |
| `barber` | (-95.9, 0.2, 14.6) | 90 | shop | Clip & Co Barber |
| `garage_shop` | (134.8, 0.2, -16.0) | 0 | service | Foundry Garage |
| `gas_station` | (-11.7, 0.1, -70.8) | 0 | service | Halcyon Fuel (canopy centre) |
| `dealer_lot` | (0.0, 0.1, 63.8) | 0 | shop | Showroom Motors, extra `extent` (26, 5) |
| `scuba_shop` | (-127.8, 0.2, 154.1) | 0 | shop | Reef Dive Shop |
| `marina_office` | (-165.4, 0.2, 154.1) | 0 | service | Marina Office |
| `shooting_range` | (254.5, 0.2, 3.5) | 90 | activity | Shooting Range |
| `train_station_a` / `_b` | (-68.3, 0.2, 55.6) / (222.1, 0.2, 54.8) | 0 | transport | stations (rail viaduct above, see 4) |
| `taxi_stand` | (96.4, 0.1, 12.0) | 90 | transport | Taxi Stand (ring east side) |
| `airport_runway_start` / `_end` | (82, 0.1, 165) / (290, 0.1, 165) | -90 | airport | runway 09 (heading +X) |
| `airport_hangar` | (148.0, 0.1, 111.4) | 0 | airport | Hangar 1 (apron side) |
| `helipad_airport` | (238.0, 0.1, 121.0) | 0 | helipad | on the apron |
| `helipad_downtown` / `helipad_hospital` | roof of the tower (0, ~102, 4.3) / hospital roof (68.3, ~22, 77.3) | 0 | helipad | y corrected from the real roof after CityBuilder |
| `dock_boat_spawn` | (-117.0, -1.5, 214.0) | 180 | water | open water east of the marina pier |
| `marina_pier` | (-146.0, 0.1, 204.0) | 180 | water | pier deck |
| `beach_spawn` | (0.0, 0.0, 164.0) | 180 | spawn | sand |
| `diving_wreck` | (-22.0, -13.6, 268.0) | 0 | water | seabed 14 m deep |
| `viewpoint` | (205.0, 39.4, -224.0) | 180 | nature | end of Summit Road |
| `parachute_peak` | (215.0, 47.6, -228.0) | 0 | nature | summit (walkable) |
| `parachute_pickup_a` / `_b` | (211, 39.6, -219) / (148, 0.4, 113) | 0 | pickup | |
| `park_center` | (-12.0, 0.1, -122.0) | 0 | nature | |
| `stunt_jump_1..3` | (-26,0.1,-130) -> east / (140,0.1,121) -> east / (0,0.23,186) -> south | -90/-90/180 | activity | extras `land`, `ramp` (ramps are built by `StuntBuilder`) |
| `district_center_<id>` | downtown (0,36) residential (-185,-90) industrial (190,-20) waterfront (-185,120) park_hills (-60,-125) airport (189,121) beach (0,157) | | district | |

## 3. Geometry / physics contract
- Terrain: one mesh + trimesh colliders split by surface (`Terrain_grass|sand|rock|concrete`, `StaticBody3D` layer `GC.L_WORLD`, meta `surface`). Roads (`asphalt`),
  sidewalks/curbs/apron/quay (`concrete`), piers (`wood`), park paths (`dirt`), rail viaduct, ramps: trimesh / convex colliders per 100 m sector with meta `surface`.
  Road top y = ground + 0.04, sidewalks +0.15 (0.15 m curb), paint +0.075, runway +0.03. Hill road is cut into the terrain.
- Water: `Water/SeaSurface` (stylised shader `world_water.gdshader`: depth colour, foam, waves; group `water_surface`) + far ocean; swim/boat volumes are `Area3D`
  nodes in group `water_volume` on layer `GC.L_WATER` (meta `water_level` = `surface_y` = -1.5, `is_sea`, `kind` sea|pond; sea box is 660 x 70 x 300 m from z = 120).
- Boundary: invisible walls at |x|,z = 302 (north/west/east) and z = 398 (south, boats) on `L_WORLD`, 30 m high; the east wall is only 6 m high over the runway extension
  (z 132..198) so aircraft can leave; berms + a mountain/hill ring (`Boundary/BackdropRing`) and a far ocean surround the playable area (aircraft may fly out).
- Sectors: `WorldRoot.get_sector_parent(pos)` (100 m cells `S_ix_iz`, static content), `get_dynamic_parent(pos)` (child `Dynamic`, process disabled while far),
  `sectors` (`SectorManager`: `show_radius` 430 / `hide_radius` 470 from the gameplay camera or player, updates 4x/s). Emits `Events.sector_activated/deactivated(Vector2i)`.
  Colliders stay active in hidden sectors; only visibility (and `Dynamic`) toggles.
- Shaders: `world_terrain` (faceted, vertex-colour driven), `world_road` (asphalt + markings from UV, junction asphalt, sidewalk, paint, dirt, apron, runway/taxiway,
  parking, planks, plaza, helipad; globals `gta_wetness`, `gta_night`), `world_water` (globals `gta_night`, `gta_rain`, `gta_sun_energy`). Materials are shared `ShaderMaterial`s.

## 4. Extras for other agents
- `WorldLayout.rail = {points: PackedVector3Array (rail head, every 8 m, y 8.6), stations: {train_station_a: 0, train_station_b: last}, deck_y 8.4, gauge 1.5, z 50, speed 16, platform_a, platform_b}`:
  an elevated viaduct from x=-84 to 236 along Dune/Industrial Avenue (z=50) with rails, sleepers, pillars on the sidewalks and two platform slabs. The train is the Systems agent's job.
- Stunt ramps/landings are static meshes with colliders (jump 1 and 2 have landing ramps, jump 3 launches from the beach pier into the sea).
- `WorldRoot.build_report` = `{total_ms, marks, road_stats}`.

## 5. Tunables / limits / known gaps
- `SectorManager.show_radius/hide_radius`, `LayoutLanes.STEP/CYCLE/YELLOW/STOP_BACK`, `LayoutRoadNet.CLASSES` (lane width, speed, sidewalk), `LayoutTerrain` height functions.
- Terrain grid is 3 m: the quay seawall is a vertical concrete rim (`PierBuilder`), not terrain. Lot rects are axis-aligned; residential lots are filled along streets only (block
  interiors stay lawn). Lane graph has no yield rules for unsignalised junctions (stop signs are furniture only). Piers: no collision under the deck.
- All hero buildings, props and trees are fallbacks until the Blender GLBs exist (World-Content logs them); the world agent itself uses no GLBs.
- Tests: `world_layout_test.gd` (graphs, locations, colliders, sectors, timing), `world_gen_test.gd`, `world_dump.gd`; screenshot helper `world_shot_prep.gd`
  (`--exec=res://gta/tests/world_shot_prep.gd --lanes=1 --peds=1 --fog=1 --hud=1`).
