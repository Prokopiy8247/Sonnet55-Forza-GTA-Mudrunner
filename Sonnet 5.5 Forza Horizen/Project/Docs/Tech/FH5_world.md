# Forza Horizon 5 - World Structure Research and Translation to a 4 x 4 km Map

Scope: FH5 is used only as a structure / mechanics / scope reference. Everything below is paraphrased.
Date of research: 2026-10-16. Reliability tags: [OFFICIAL] = Xbox Wire / forza.net / Epic docs / engine source;
[PRESS] = journalism; [FAN] = fan guide / wiki-style site (numbers approximate); [INFERENCE] = my own reasoning or design number.

---------------------------------------------------------------------------------------------------

## 1. What FH5's world is (facts)

### 1.1 Size and shape
- Fictionalised Mexico. Creative director Mike Brown states only a ratio: the map is about 1.5x the size of FH4's map. [OFFICIAL/PRESS]
- Absolute area is NOT official. Fan/press estimates: FH4 ~ 71-72 km2, FH5 ~ 107 km2. [FAN]
  - Caution: one guide claims a near-straight coast-to-coast drive at 150+ mph takes 7-8 minutes. That is ~30 km, which does not fit a
    ~10 x 10 km square. Either the map is elongated / the figure is loose, or the area estimate is low. Treat both as order-of-magnitude only. [FAN]
- Geography: Pacific-side coast in the west to Gulf/Caribbean-side coast in the east. "Greatest hits of Mexico" rather than a 1:1 recreation. [PRESS]
- A very long highway runs diagonally across the map (roughly from the south-west corner to the north-east). It is the series' longest highway. [PRESS]
- The map is built so that high-speed cross-map cruising is a first-class activity (Sand Desert has the longest straight roads; the highway is the spine).
- Dev process: scouting trip + photogrammetry + Street View used for small lived-in details; the creative director says the team designs "from the driver's seat"
  (only things visible from a road/vehicle get built, e.g. murals yes, museum interiors no). [PRESS]

### 1.2 The 11 official biomes (Xbox Wire)
| Biome | Terrain / dressing | Driving character / roads | Notable features |
|---|---|---|---|
| Canyon | layered rock, hoodoos (only here) | two of the biggest switchback roads in the series, tarmac and dirt variants; railway and river on the canyon floor; strongest echo | hoodoos, train line, cable car |
| Tropical Coast | palms, white beaches, calm water | palm-lined coast roads; storm season blows palms into the road | postcard scenery |
| Farmland | rolling hills, fruit trees, wide shallow rivers | fences to smash, farm tracks, homesteads | rainy season in spring |
| Arid Hills | dry grass hills and plains | wide-open off-road freedom; a lake that dries up in winter and opens shortcuts | seasonal shortcut |
| Jungle | dense tall trees, canopy light, waterfalls, rivers | narrow tree-lined dirt/asphalt, hidden temples | Mayan-style ruins (Ek' Balam, Tulum) |
| Living Desert | saguaro cactus, rock piles, flowers, wildlife | mixed paved/dirt, seasonal river | series' first cactus desert |
| Rocky Coast | few trees, open ocean views, sunsets | cliff-edge coast roads, drive-through golf course | resort / golf |
| Sand Desert | huge dunes (Dunas Blancas) | long straights for top-speed runs, deformable sand | gypsum white sand, dune-buggy zone |
| Swamp | shallow water, mangroves with smashable roots | water crossings, route choice by car capability | mangrove roots reshape routes |
| Urban (Guanajuato) | colourful dense old city on steep hills | tunnel network under the city, narrow echoing streets | the only fully urban biome |
| Volcano (La Gran Caldera) | tallest point in the game, next to the Living Desert | winding paved road up one side, dirt course on the other; long climb to the summit; lava fields and a buried church on the flanks | the only place with snow; radio-telescope at the top |
- Seasons (4) affect biomes differently (rainy season in jungle/farmland in spring, tropical storms on coasts in summer/fall, dust storms in the dry season);
  seasons rotate weekly online. A local-weather system can put a storm on one part of the map while the rest stays clear. [OFFICIAL/PRESS]
- Rule observed: biome contrast is created by ALTITUDE and distance to coast/moisture. Snow on the summit while the coast is hot is the headline example. Biomes are
  adjacent in clusters (volcano beside desert, canyon above coast, farmland-swamp-beach chain in the south-east), so one drive crosses several biomes in minutes.

### 1.3 Named regions and landmarks (mostly fan taxonomy, positions partly speculative)
- A fan guide names 8 regions: Tierra Prospera (farmland), Gran Pantano (swamp woodland), Cordillera (hilly fields), La Selva (jungle road), Baja California (desert plains),
  Dunas Blancas (dunes), La Gran Caldera (volcano), Riviera Maya (beaches). [FAN, not an official count - the official count is 11 biomes]
- Other landmarks: Copper Canyon (railway), Sierra Verde Dam and reservoir, Mulege oasis village, Playa Azul coastal village, Cabo San Lucas resorts, La Gran Puente (big bridge),
  Teotihuacan (pyramids + drag strip), Tulum / Ek' Balam / Uxmal / Atlantes de Tula (ruins), an airfield in the jungle, Estadio Horizon (custom-event stadium, just south of Guanajuato),
  a pre-built dune off-road facility (oval + figure-eight) near Dunas Blancas, a golf course, Lago Blanco.
- Approximate layout (pre-release maps, contradictory in places): volcano + dunes in the north-west/west; Guanajuato + canyon in the north/north-east or centre-north; farmland -> swamp -> beach chain
  in the south-east; main festival site and Mulege in the south-west; diagonal highway SW -> NE. Do not rely on exact positions.
- Takeaway: landmarks are big, iconic and visible from the road (volcano cone, dam, bridge, pyramids, canyon walls), and each is used as the anchor/name of events.

### 1.4 Road / surface vocabulary in FH5
- Asphalt highway, regional asphalt, mountain switchback asphalt (volcano, canyon), city streets + tunnels, dirt trails (jungle, farmland, volcano dirt course), mud (swamp, green-hill dirt after rain),
  deformable sand roads (dunes; Rally Adventure DLC adds sand roads with pre-made tyre tracks), shallow fords/rivers (farmland, swamp), grass/open terrain for cross-country, crushable props
  (fences, mangrove roots, palms in storms, pins in the stadium), jumps built into natural features (temple jump, lake jumps).
- Rally Adventure DLC (Sierra Nueva): separate map reached by fast travel, 6 biomes (pueblo in the middle with cable cars, desert gorge with twisting asphalt and a wooden bridge, green hills with dam and muddy dirt,
  palm forest with waterfall, abandoned quarry, rugged dunes with a town inside a crater). A press snippet quotes ~38 in-game miles of new area (unverified). [OFFICIAL map post + PRESS]

---------------------------------------------------------------------------------------------------

## 2. How events use the world (the key structural insight)

FH5's roads exist independently of events; events are named routes (waypoint chains) laid over the road network and open terrain. Every event type has a "home" outpost.

### 2.1 Event classes and lengths [FAN numbers, from a guide listing ~85 events; 1 mile = 1.609 km]
| Class | Format | Length range | Notes |
|---|---|---|---|
| Road circuits | 3 laps | 1.2-2.5 mi (1.9-4.0 km) per lap | village back-streets, stadium ring road, plateau loop, seaside loop (water on an apex) |
| Road sprints | point-to-point | 3.7-6.1 mi (6.0-9.8 km) | often "descend from canyon/volcano to the coast"; Volcan Sprint = hairpin-heavy climb; Copper Canyon Sprint follows river + railway |
| Dirt trails | point-to-point | 3.8-5.4 mi (6.1-8.7 km) | loose-surface descents with switchbacks, mixed paved/dirt, jungle/waterfall, desert |
| Dirt scrambles | 3-4 laps | 1.1-2.6 mi per lap | loops around a landmark (volcano church ruins, pyramid, hill town, river valley) |
| Cross-country routes | point-to-point | 3.2-4.8 mi (5.1-7.7 km) | open terrain: dunes, farmland, river, stadium, hotel courtyard + beach + golf course, big jumps |
| Cross-country circuits | 2-3 laps | 1.3-2.4 mi per lap | airfield, dunes, ruins, stadium |
| Street races | point-to-point | 3.5-5.7 mi (5.6-9.2 km) | city + countryside, tunnels, coastal runs |
| Mega events | single long run | 16.6 mi (26.7 km, cross-country "Titan"), 18 mi (29 km, street "Marathon"), 33.9 mi (54.6 km, "Goliath" one-lap tour of canyon, jungle and both coasts), 34.3 mi (55.2 km, "Colossus" zig-zag across the map), 36.5 mi (58.7 km, dirt "Gauntlet" alternating paved/dirt through jungle, farmland, caldera, desert) | each one tours nearly every biome |
- Pattern 1: event names/starts/ends are landmarks; the finish often is a hub or a photogenic location (stadium, beach, festival site).
- Pattern 2: the favourite race geometry is a DESCENT from high biome (canyon/volcano/hill) to low (coast/valley): speed, views, and contrast.
- Pattern 3: routes deliberately cross the main highway ("above and below the highway") - the highway acts as the connective spine and a navigation reference.
- Pattern 4: mixed-surface routes (paved + dirt + sand + water) are common even in "road" or "dirt" classes.
- Pattern 5: seasonal state changes open/close shortcuts (dry lake, seasonal river). FH5 reuses the same road network; water levels change but road network and event locations do not.
- Ratio [INFERENCE]: mega event length / sqrt(map area) ~ 55 km / ~10 km ~ 5; sprints ~ 0.6-1.0 of map "side". Applying the first ratio to 4 km gives a ~21 km grand tour (matches the 20 km+ loop requirement).

### 2.2 Campaign skeleton (useful as a structure template, not to be copied)
- Main festival site + 5 themed outposts (Apex = road, Wilds = dirt, Baja = cross-country, Street Scene = street, Rush = PR stunts). Each outpost opens via an "Expedition" - a story-flavoured
  long drive/trek across the map to a significant location where the new site is "founded" (e.g. Ek' Balam -> Tulum). 5 expeditions. Expeditions are the way the game makes you drive the world.
- Accolades (thousands, 11 categories) gate chapters; "snackable" design (the player picks what to chase).
- PR Stunts (speed traps, speed zones, drift zones, danger signs/jumps, Trailblazer off-road sprints) appear on the map after the Rush outpost; Trailblazers number 13 (fan count).
- Collectible boards: 50 fast-travel boards + ~200 XP boards (fan counts, density ~2.3 per km2 on a ~107 km2 map); each fast-travel board cuts the fast-travel fee by 200 CR from a 10,000 CR base, 50 boards = free.
- Houses (7 on the map; prices 0 - 5,000,000 CR) give perks; the 2,000,000 CR "Buenas Vistas" house = fast travel to any road.
- Multiplayer density is biome-tuned: up to 11 other players visible; cities feel busier than jungle. (Sources checked do not describe civilian AI traffic.)

---------------------------------------------------------------------------------------------------

## 3. Translation to our 4 x 4 km map

### 3.1 Scale comparison
- FH5 ~ 107 km2 (est.) vs ours 16 km2 -> ~15% of the area, ~39% of the linear dimension. Highway-to-event ratios therefore shrink by ~2.6x linearly.
- Time at speed: 250 km/h = 69 m/s -> crosses 4 km in ~58 s. A 22 km loop at an average 120 km/h takes ~11 min. A single biome cannot be allowed to be bigger than ~1.2 km across or the map becomes four
  empty rectangles. The 20+ km loop is what restores the "long road" feeling (this is FH5's mega-event idea scaled by sqrt(area)).
- Road density: 40-60 km on 16 km2 = 2.5-3.75 km/km2 = a road within ~300-500 m of most places. Good for countryside; keep roads mostly on ridges/valley floors and leave large road-free areas for
  scenery and cross-country.

### 3.2 Regions (4 required + 1 optional), adapted from FH5 biome logic (altitude + moisture + coast distance)
Design coordinates: E = 0..4032 m, N = 0..4032 m, origin south-west corner (see 3.6 for the engine mapping). Elevations are relative to sea level 0.

| # | Region (working name) | FH5 analogue | Footprint (E, N) | Elevation | Look | Signature landmark | Road character |
|---|---|---|---|---|---|---|---|
| A | Coast and headlands | Tropical/Rocky Coast | south strip and south-west corner, N 0-900 | 0-70 m, cliffs | sea, cliffs, beach, lighthouse, harbour hamlet, mild haze | long coastal bridge over the estuary (400-600 m) + lighthouse | scenic coast road, cliff-edge, bridge, short dirt spur to lighthouse |
| B | Farmland valley and forest | Farmland / Arid Hills / Swamp edge | centre-south to centre, E 1300-3200, N 700-2300 | 40-130 m, river running north -> south to the estuary | fields, hedgerows, orchards, forest patches, river with bridges, village | stone bridge + ruined castle on a hill | regional roads, fords, farm tracks, village crossroads |
| C | Highlands and mountain pass | Volcano / Canyon switchbacks | north and north-west, N 2300-4032, E 200-2400 | 150-700 m, peak ~700 m with snow above ~580 m | conifers, alpine meadow, rock, snow cap, cold light | peak with radio mast + wind farm on the ridge | 6-8 km hairpin climb, tunnel (300-500 m), viewpoint, descent |
| D | Arid canyon and plateau | Canyon / Living Desert / Sand Desert | east and north-east, E 2700-4032, N 1700-3900 | 220-320 m plateau, canyon floor 100-140 m | red/ochre soil, mesas, sparse scrub, dust, hard light | mesa arch / canyon rim + gas station + railway line or dry riverbed | fast wide highway, canyon descent, dirt shortcuts, cross-country mesas |
| E (optional) | Marsh / river mouth | Swamp | around estuary E 2200-2900, N 300-700 | 0-10 m | reeds, shallow water, boardwalk | boardwalk | low roads, fords |

- Transition bands: 200-400 m, handled by weighted blends in vegetation/soil layers; never a hard seam. Altitude bands drive vegetation (like the FH5 snow-on-summit rule): sea level - beach/cliff grass;
  40-200 m - farmland / broadleaf; 200-450 m - conifer / dry scrub depending on the moisture mask; 450+ - alpine, rock; 580+ snow cap.
- Adjacency (each pair must be linked by at least one road): A-B, B-C, B-D, C-D (north rim), A-C (west descent). Suggested ring: A -> B -> D -> C -> A.
- Weather per region [INFERENCE from FH5 local-weather]: coast = fog/storm bias, highlands = cold/snow-at-altitude, canyon = dust/clear bias, valley = rain bias. Implement as a per-region multiplier on the global weather state.

### 3.3 Road network budget (target ~50 km, all numbers are my design proposal)
| Road | Class | Length | Width (total / lanes) | Surface | Notes |
|---|---|---|---|---|---|
| H1 diagonal "spine" highway SW coast -> NE canyon plateau | highway | ~7.0 km (straight line ~4.9 km, with long S-curves) | ~12-14 m, 2 lanes + wide shoulders (passing lanes optional; dual carriageway optional on a straight) | asphalt | min radius ~400-500 m, grade <= 5%, crosses the loop twice (grade-separated or roundabouts) |
| Scenic loop ("grand tour") counter-clockwise A -> B -> D -> C -> A | regional + mountain | 23-24 km | 7-8 m, 2 lanes + 1 m shoulders; mountain 6-6.5 m | asphalt (some concrete bridges) | contains: coast road 4.5 km, valley road 4.0 km, canyon road 4.5 km, mountain pass 7.0 km, west descent 3.5 km |
| Secondary valley / village roads | regional | ~6 km | 6 m | asphalt, some chip-seal | feeds village, farms, castle |
| Dirt and gravel tracks | track | ~9 km total | 4-5 m | dirt / gravel | canyon shortcut ~2.5 km, ridge forest road ~2.5 km, farm track ~2 km, coastal lighthouse track ~2 km |
| Spurs to POIs (gas station, diner, viewpoint, wind farm) | spur | ~5 km | 5-6 m | asphalt / gravel | |
| Total | | ~50 km | | | in the 40-60 km requirement |
- Required sets: at least two 5 km+ uninterrupted stretches (H1 and the valley+canyon section of the loop); one 20 km+ continuous loop; at least 2 bridges (coast bridge, river bridge), 1 tunnel, 1-2 fords.
- Pass design: 450-550 m climb at ~7% mean grade -> ~6.5-8 km of road; hairpin centreline radius 18-25 m with ~1.5 m widening, <= 9% grade through hairpins; carve a flat bench per hairpin.
- Min radius sanity (R = v^2 / (g (mu + e)), mu = 0.8 tyre friction, e = 0.05 banking) [INFERENCE, computed]:
  250 km/h -> ~580 m; 190 km/h -> ~330 m; 120 km/h -> ~130 m; 80 km/h -> ~60 m. Use these to decide where a road is "flat-out", "fast" or "technical".
- Event-class distances suited to this map: road sprints 3-6 km; road circuits 1.2-2.5 km/lap (only where a loop exists: village ring, headland, canyon mesa); dirt trails 2.5-4 km; cross-country
  routes 1.5-3 km; grand tour 20-24 km. (FH5 values scaled by about 0.4-0.5 for sprints, circuits left near original because they are about driving feel, not map size.)

### 3.4 Activity placement density [INFERENCE: ~1 discoverable per kilometre of road]
- Speed traps 10-12, speed zones 5-6, drift zones 4-5 (hairpins/village ring), danger-sign jumps 5-6 (canyon rim, ridge crests, coast), checkpoint races 6-8, time trials 1-2 (grand tour + pass),
  hub/rest areas 4-5 (one per region + gas station). Each activity references a road ID + parameter range, not world coordinates, so the road graph can be regenerated without breaking content.
- FH5's lesson: events/discoverables sit in recognisable, visually distinct spots (landmark, bridge, tunnel mouth, hairpin), and descents are the preferred race geometry.

### 3.5 Fast travel and hubs (FH5: fee + boards + house)
- ADAPT: free instant travel to 5 named hubs (1 per region + spawn) from the map or the console `tp <region|poi>`; no credits economy. After teleport, wait for streaming to complete (see 3.7) before
  releasing the vehicle.

### 3.6 Terrain construction (engine facts and recommendations)
Engine facts [OFFICIAL, Epic Landscape Technical Guide]:
- Recommended sizes (vertices / quads per section / sections per component / component size / components): 4033 x 4033 / 63 / 4 (2x2) / 126 / 1024 (32x32); 2017 x 2017 / 63 / 4 / 126 / 256 (16x16);
  1009 x 1009 / 63 / 4 / 126 / 64 (8x8); 8129 x 8129 / 127 / 4 / 254 / 1024. Sections are capped at 256 x 256 verts; 1024 components is the recommended ceiling.
- Height is 16-bit; Z scale 100 gives roughly +-256 m (512 m total). Linear in Z scale, so total range (m) = 5.12 x ZScale and required ZScale = (total height range in m) / 5.12
  (matches Epic's Mauna Kea example: 4207 m -> ~821.7).
  Example: -50..+750 m -> 800 m -> ZScale ~156; set the actor's Z offset so sea level lands where intended; vertical resolution ~1.2 cm.
- Landscape memory ~4 bytes per vertex (about 6-7x cheaper than a static mesh at the same density); LOD via mip-based geomipmapping; collision is a heightfield; collision resolution can be halved to save memory;
  each Landscape layer can carry a Physical Material and the dominant layer wins at a point -> usable for surface type under the wheels.
- World Partition: the Landscape is subdivided into streaming proxies; import-time options "Grid Size" and "Region Size" exist (the docs describe the two options in opposite directions in different pages - test in
  the editor before relying on it).
- Landscape resolution choice for us: 4033 x 4033 at 100 cm/vertex = 4032 m side, 1 m heightmap resolution, 32 MB heightmap data. Good enough for crisp road cut/fill. A 2017 x 2017 landscape at 200 cm spacing is a
  fallback if performance or generation time is an issue (road shoulders become coarse).
- Coordinate mapping pitfall: heightmap row index increases with +Y in UE (a left-handed X-forward, Y-right system). Put a distinctive marker (peak/coast) in the generated map and verify orientation in the editor
  (the import helper even has a `bFlipYAxis` flag). Map design coordinates -> UE: X_ue = E * 100, Y_ue = (4032 - N) * 100 (or any consistent mapping), landscape actor at the origin.

Programmatic creation (engine source checked in W:\Unreal Engine 5\UE_5.8):
- `ALandscapeProxy::Import(FGuid, MinX, MinY, MaxX, MaxY, NumSubsections, SubsectionSizeQuads, HeightData, HeightmapFileName, ImportMaterialLayerInfos, ELandscapeImportAlphamapType, Layers)` exists, is `LANDSCAPE_API`,
  but lives inside a `WITH_EDITOR` block -> must be called from an editor-only module/commandlet. The editor mode itself uses it.
- `FLandscapeImportHelper` (module LandscapeEditor, header `LandscapeImportHelper.h`) offers `ChooseBestComponentSizeForImport`, `GetHeightmapImportDescriptor/Data`, `TransformHeightmapImportData`,
  weightmap equivalents.
- Python: `unreal.Landscape` has no documented "create from heightmap" call; `LandscapeProxy.landscape_import_heightmap_from_render_target` (editor-only) and `enable_nanite` (read/write status varies by version)
  appear in the API pages - verify both in 5.8 before using.
- Editor UI import accepts 16-bit grayscale PNG, 8-bit/16-bit R8/R16, or RAW + JSON sidecar; layer weightmaps can be imported per layer as additive or weight-blended (Layered). Recommendation: write a 16-bit PNG/R16 heightmap
  plus per-layer 8-bit weightmaps from Python/C++ (numpy) and drive a C++ editor function (or the Landscape import code path) from a commandlet so the whole world is reproducible from script.
- The Open World template ships with a 2 km x 2 km sample landscape and World Partition enabled -> proof that 4 km is comfortably inside engine limits.
- Plugins present in the 5.8 install (checked on disk): PCG (+ PCGBiomeCore, PCGBiomeSample, ProceduralVegetationEditor), Experimental/Water, WaterAdvanced, Landmass, Editor/LandscapePatch, MeshTerrainMode,
  VirtualHeightfieldMesh, Mover, Mass* (MassGameplay, ZoneGraph, ZoneGraphAnnotations, StateTree), ChaosVehiclesPlugin (Experimental). Everything experimental needs an explicit risk check before use.

Terrain generation recipe [INFERENCE]:
1. Base height field = sum of region masks x shaping functions (coast ramp, valley bowl with a river channel, plateau + canyon, mountain massif) + multi-octave ridged/fBm noise, with amplitudes damped near roads.
2. Author the road graph FIRST as 2D polylines/splines (design space) with road class, width, lanes, surface, speed limit, junction nodes. The same graph feeds: terrain carving, road mesh, minimap, traffic lanes, event routes, AI.
3. Elevation profile per road: sample terrain along the centreline, smooth it (low-pass), clamp grade (highway 5%, regional 7%, mountain 9% incl. hairpins, dirt 12%), limit vertical curvature (crest / sag radius) to avoid
   launching or bottoming-out at 250+ km/h.
4. Carve: new_height = lerp(terrain, roadZ(nearest centreline sample) + cross-slope, w(d)), w = 1 inside half-width + shoulder, smoothstep to 0 over 10-30 m of cut/fill. Priority ordering for crossings;
   for stacked hairpins and bridges evaluate per-road with a Z-aware nearest-segment test (nearest in XY AND within a vertical tolerance) so one road does not drag another road's ground.
5. Banking: superelevation 2-6% on curves, crowned 2% cross-slope on straights; road mesh follows the same profile.
6. Rivers: carve channels, publish a water-level plane/spline (Water plugin is experimental; a simple water-plane mesh with a material is the safe fallback). Bridges are separate meshes over the carved channel.
7. Paint weightmaps: grass/dirt/rock/sand/snow/asphalt-shoulder/gravel from height + slope + moisture + distance-to-road masks; dirt/gravel road bed painted as its own layer with a Physical Material.
8. Export: heightmap (R16/PNG16), weightmaps (8-bit per layer), road-graph JSON, POI JSON, region mask PNG (used by the HUD region popup, weather, ambience).

### 3.7 World Partition streaming setup for speed
[OFFICIAL, Epic WP docs] Example runtime grid = 256 m cells, loading range 768 m around each streaming source; each PlayerController is a streaming source; extra `World Partition Streaming Source` components can
preload a destination (priority, shapes, target state Loaded/Activated); `Is Streaming Completed` can be polled; HLODs via Build HLODs / `wp.Runtime.HLOD 0` toggles; the Open World template includes WP + OFPA + Data Layers + HLOD.
- 256 m cells -> 16 x 16 = 256 cells in our 4032 m world. At 70 m/s the car crosses a cell every ~3.7 s; the default 768 m radius is only ~11 s of look-ahead. Recommendation [INFERENCE]: loading range ~1200-1600 m
  for the main grid, a separate lighter grid for far props, HLOD for distant dressing; attach a second streaming source ahead of the car (velocity-based) if hitching appears.
- `tp` console command: place a streaming source at the destination, wait for streaming completion, then teleport and unfreeze the car (prevents falling through unloaded landscape).
- Pitfalls from the docs: actors referenced by the Level Blueprint become always-loaded; mutually referencing actors are bundled; "Block on Slow Streaming" can stall the game; WP editor starts with world unloaded - generation
  commandlets must load regions explicitly; minimap needs virtual texture support; cook requires the cook commandlet with `-map`.
- Pitfall (inference): OFPA creates one file per actor - do NOT emit one actor per fence post / cone / tree. Use instanced static mesh components, PCG, or a few road actors with many spline-mesh components.

### 3.8 Roads, surfaces, structures
- Road actors: two valid routes in Epic docs: (a) Landscape Splines (control points + segments; deform terrain only when a "Spline" edit layer exists on the Landscape; Raise/Lower Terrain, falloff, layer painting, spline meshes
  with forward/up axis); (b) custom spline-mesh actors. Recommendation: ADAPT (b) plus heightmap carving at generation time, because the road graph is code-defined, deterministic and shared with traffic/minimap/events, and it avoids
  edit-layer dependencies. Landscape-spline pitfalls: no deformation without the Spline edit layer, Select All affects every spline actor, spline-mesh offsets are in mesh space.
- Road cross-section prefab: lane markings (centre dashes/solid), edge lines, shoulder, curb in villages, guard rails on exposed edges, reflectors, delineator posts, signs, culverts, drainage ditches, tunnel portals, bridge
  parapets - these are separate modular meshes along the same spline.
- Surface enum for grip + audio (data-driven): Asphalt, Concrete (bridges/tunnel), WetAsphalt (runtime), Dirt, Gravel, Grass, Sand, Mud, ShallowWater (ford). Landscape layer Physical Materials for terrain/dirt, mesh Physical Materials for asphalt road
  meshes and bridges; wheel traces read the Physical Material.
- FH5-style surface/prop interactions worth copying cheaply: crushable fences/hay/pins (SKIP physics, ADAPT visuals), a ford that slows the car and spawns a splash, deformable-sand look via normal blend only.
- Tunnel: 300-500 m, lit, with echo reverb zone (FH5 gives the canyon and Guanajuato strong echo -> audio reverb volumes). Bridges: coastal long bridge (400-600 m, arched or box girder), river bridge (60-120 m).

### 3.9 Landmarks, POIs and settlements (small only)
- One signature landmark per region visible from the highway (FH5 pattern): peak + radio mast, mesa arch, lighthouse + coastal bridge, ruined castle or windmill. Keep a clear line of sight from at least two roads.
- Settlements (all small): coast harbour hamlet (~10 buildings), valley village (~25 buildings + church + bridge), farm clusters (2-3), canyon gas station/diner, mountain chalet/viewpoint cafe, wind farm. Settlement kit in Blender
  (houses, barn, fences, signs) per the main prompt. FH5's only large urban area (Guanajuato) is SKIPPED.

---------------------------------------------------------------------------------------------------

## 4. Decisions (ADOPT / ADAPT / SKIP)
| # | FH5 feature | Decision | One-line reason |
|---|---|---|---|
| 1 | Biome variety driven by altitude + moisture + coast | ADOPT | Cheap to implement via weightmap rules and gives instant region contrast on a small map |
| 2 | 11 biomes | ADAPT | Collapse to 4 regions + optional marsh; each biome's key props reused as sub-biomes (sand/dune patch, forest patches) |
| 3 | Long diagonal highway spine | ADOPT | Gives the 5 km+ high-speed stretch and a navigation reference; ~7 km on our map |
| 4 | Mega events touring every biome | ADAPT | 20-24 km "grand tour" loop (FH5 scaled by sqrt(area)); doubles as time trial |
| 5 | Event = named route over an independent road network | ADOPT | Roads stay stable; events are data (road IDs + waypoints), easy to add/regenerate |
| 6 | Descent-from-high-to-low race geometry | ADOPT | Delivers speed + vistas + contrast; mountain->coast/valley sprints |
| 7 | Event length classes (circuit 2-4 km, sprint 6-10 km) | ADAPT | Scale sprints to 3-6 km; keep circuits only where a real loop exists |
| 8 | Mixed-surface routes (asphalt + dirt + sand + water) | ADOPT | Showcases the surface system; cheap if surface is by layer/mesh Physical Material |
| 9 | Cross-country shortcuts across fields/dunes/rivers | ADAPT | A few marked off-road shortcuts (canyon, ridge, farm), no full cross-country race class at first |
| 10 | Seasons (weekly rotation) | SKIP | Weather + time-of-day already cost enough; use biome weather multipliers instead |
| 11 | Seasonal geography change (dry lake, seasonal river) | SKIP (one static dry riverbed shortcut) | Not worth the dynamic-terrain cost |
| 12 | Local weather (storm in one area only) | ADAPT | Per-region weather multiplier and fog/rain zones; global state remains authoritative |
| 13 | Festival hub + 5 outposts + expeditions | ADAPT | One hub/rest area per region, free fast-travel; no campaign or gating |
| 14 | Fast travel with fees, boards and houses | SKIP economy / ADAPT travel | Free `tp` to hubs from console + map |
| 15 | PR stunts (speed trap, zone, drift zone, danger sign, Trailblazer) | ADOPT (first four) | Matches required activity list; SKIP Trailblazer |
| 16 | Collectible boards (50 + 200) | SKIP (maybe 20-30 smash boards later) | Collectibles are stretch; high content cost |
| 17 | Accolades, chapters, Hall of Fame | SKIP | No story/campaign by design |
| 18 | Big iconic landmarks per biome visible from the road | ADOPT | Cheap navigation and strong screenshots |
| 19 | Dense city with tunnels (Guanajuato) | SKIP | Prompt demands countryside; only a mountain tunnel is kept |
| 20 | Smashable props (fences, mangroves, palms) | ADAPT | Visual-only break/scatter or simple physics props for fences |
| 21 | Stadium / custom-event facility | SKIP | Not in scope; an optional dirt oval near the canyon gas station is a stretch |
| 22 | Rally Adventure style separate DLC map via fast travel | SKIP | Single 4 x 4 km map |
| 23 | Echo/reverb zones per biome (canyon, tunnel) | ADOPT | Cheap, adds big atmosphere |
| 24 | Biome-tuned ambient/player density | ADAPT | Use the same idea for traffic and ambient life density per region |
| 25 | Drive-from-driver's-seat content rule (build only what the camera sees) | ADOPT | Limits scope; no interiors, thin set dressing off-road corridor |

---------------------------------------------------------------------------------------------------

## 5. Implementation checklist for the lead (proposed order)
1. Define `WorldSpec` data (regions, mask paths, road graph, POIs) in JSON under the project; generate everything from it (Python in Tools/ue + C++ editor function).
2. Generate heightmap + weightmaps + region mask with a deterministic seed; write a quick PNG preview and look at it before importing.
3. Create the Landscape through an editor-only C++ path (`ALandscapeProxy::Import`) invoked from a commandlet / Python-exposed UFUNCTION; set scale (100,100,ZScale), assign Physical Materials to layers; verify orientation with markers.
4. Enable World Partition on the map; set runtime grid (256 m cells, loading range 1200-1600 m), generate HLODs late.
5. Build road actors from the graph (spline-mesh components for asphalt, painted layer for dirt/gravel), then guard rails/poles/signs as instanced meshes.
6. Place bridges, tunnel, hubs, settlements, landmarks as data-driven placements referencing road ID + distance.
7. Drive the loop with the scripted car at max speed to find streaming hitches, grade/crest problems and floating/embedded road segments.

---------------------------------------------------------------------------------------------------

## 6. Pitfalls and open questions
- FH5 absolute area, event distances and region positions are not official; numbers above are fan data. Use them only for ratios.
- Fan region names (8) conflict with the official 11 biomes; do not treat them as a design requirement.
- Pre-release map articles describe layout from a trailer and are speculative; position claims (Guanajuato, festival site) conflict between sources.
- Landscape World Partition options "Grid Size" vs "Region Size": docs contradict each other in direction; verify in the 5.8 editor.
- Python landscape creation is weakly documented; plan on C++ `ALandscapeProxy::Import` (editor-only). Nanite Landscape property availability/behaviour differs by version - verify in 5.8.
- Water, LandscapePatch, Landmass, ChaosVehicles, Mover are experimental in the install - budget for fallback implementations.
- 1 m heightmap spacing means road shoulders/ditches are 1-2 vertices wide; do not rely on terrain alone for fine road edge profile - the road mesh must hide the seam (mesh slightly above terrain, wide skirts).
- Crest/sag vertical curvature and stacked hairpins/bridges are the usual cause of floating roads and falling-through car bugs; test with automated drives.
- One-actor-per-prop explosion under One File Per Actor; prefer instancing/PCG.
- Time-to-cross: a 4 km map at 250 km/h is under a minute; the road design (not the footprint) has to create distance.

---------------------------------------------------------------------------------------------------

## 7. Sources actually used
Official / authoritative:
- https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
- https://forza.net/news/exploring-forza-horizon-5-biomes-and-seasons
- https://forza.net/news/forza-horizon-5-rally-adventure-map-reveal
- https://forza.net/news/forza-horizon-5-road-to-mexico-september-update
- https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-technical-guide-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-splines-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/importing-and-exporting-landscape-heightmaps-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/landscape-overview
- Local engine source: W:\Unreal Engine 5\UE_5.8\Engine\Source\Runtime\Landscape\Classes\LandscapeProxy.h; W:\Unreal Engine 5\UE_5.8\Engine\Source\Editor\LandscapeEditor\Public\LandscapeImportHelper.h;
  plugin folders under W:\Unreal Engine 5\UE_5.8\Engine\Plugins
Press / reference:
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- https://gtplanet.net/forza-horizon-5-map-revealed-20210809
- https://www.gtplanet.net/forza-horizon-5-snackable-20210907/
- https://videogameschronicle.com/news/forza-horizon-5s-full-world-map-has-been-revealed
- https://press-start.com.au/news/xbox/2021/10/11/google-maps-played-a-big-role-in-forza-horizon-5s-mexico/
- https://www.thegamer.com/interview-playground-games-forza-horizon-5/
- https://racinggames.gg/article/forza-horizon-5-mexico-map-deep-dive (layout speculation flagged by author)
- https://www.ggrecon.com/guides/forza-horizon-5-map/ (fan region list, coast-to-coast timing claim)
Fan data (numbers approximate):
- https://guides4gamers.com/forza-horizon-5/maps/mexico/ (houses, fast travel, event lists)
- https://guides4gamers.com/forza-horizon-5/pois/road-racing-events/ ; .../pois/cross-country-racing-events/ ; .../pois/dirt-racing-events/ ; .../pois/street-racing-events/
Search-result summaries only (page body not readable): windowscentral.com/forza-horizon-5-map, techradar.com (longest highway article), progameguides.com (map size), mapmaster.io (festival site / board counts),
techraptor.net (board counts), racinggames.gg (festival outposts), shacknews / gamepressure / sportskeeda (Rally Adventure).
