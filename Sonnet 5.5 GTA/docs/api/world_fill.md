# World fill (World-fill agent, wave 3) - hero buildings, props, layout fixes

Owner: `gta/code/world/fill_builder.gd` + `fill_animator.gd` (new); data edits in `layout_lots.gd` / `layout_furniture.gd` / `layout_peds.gd` /
`layout_locations.gd`; hooks in `building_kit.gd` (`build_all`), `landmark_builder.gd` (`_build_one`), `city_builder.gd`. Tests: `gta/tests/fill_test.gd`
(`tools\gd.ps1 exec -Script res://gta/tests/fill_test.gd -Seconds 60 -GameArgs "--no-traffic --no-peds"`), `fill_map_dump.gd` (top-down plan PNG of lots / roads /
lane points / furniture: `-GameArgs "--multi=name=x0,z0,x1,z1,px;..."` -> `screenshots/fill/<name>.png`). Wrap-up was forced early (usage limit): see "Not done".

## What it does
* `LayoutLots` tags lots with `lot["hero"] = "<buildings/*.glb id>"`; `BuildingKit.build_all` calls `FillBuilder.place_hero_lot(batch, lot, rng)` first (uniform scale
  to fit the lot, >= 0.5; front edge 0.8 m behind the street edge; box colliders (tower_a: 5 stepped boxes); GLB `Door`/`RoofHelipad` empties become `Landmark_<hero>`
  anchors via `LandmarkBuilder._anchors`). GLB missing -> the normal kit building is built (logged, `FillBuilder.stats["missing"]`).
  Heroes: tower_a (28-floor plaza lot, 110 m; `helipad_downtown` now on the podium `RoofHelipad` anchor, y ~14.75), tower_b (north half of the (2,0) block),
  tower_c (NE quarter of block (2,1)), hotel (SW lot of block (0,2), faces south to the ring, neon), hangar_a / hangar_b (airport, scale 0.72 / 0.86, front at z 115.9),
  warehouse_a / warehouse_b / factory / silo_cluster (industrial). `building_footprints` include hero lots.
* `FillBuilder.build(batch)` (CityBuilder, after landmarks): dock crane (yaw PI = boom seaward) + 4 container stacks (3 under the crane), lighthouse on the cargo pier tip,
  life rings / dock bollards on the pier tips, animated ferris wheel on the beach (best flat sand spot; `FillAnimator` rotates `Wheel`, gondolas counter-rotate, only within 420 m),
  beach life (~16 umbrellas + towels + chairs, volleyball net, 2 surf racks, campfire + 3 tents), promenade vendors (ice cream / hotdog), 3 playgrounds
  (park W lawn, pocket park; swing set, slide, picnic tables, bins), picnic tables on the pond ring, yard clutter (barrels, pallets, crates, containers), downtown newspaper boxes / bins
  (>= 2.4 m from lanes). All static props are MultiMesh instances (`fill_<prop>` keys, LOD 150 m, no per-prop scripts).
* Landmark hook `FillBuilder.landmark_roof_pad`: a `RoofHelipad` empty on a landmark (hospital, police station) gets a marked 10 m pad (`K:Roof_Helipad_Pad`); `helipad_hospital`
  moves to it (y ~12.3 on the real roof, was 22 m in the air).
* `LayoutFurniture._validate_against_lanes()`: lamp / bin / bollard / hydrant / meter / bench / mailbox / utility box / tree / palm are removed when closer than 1.6 m
  (segment distance) to a lane (`LayoutFurniture.lane_removed`; 9 items on the real map incl. the alley wall lamps). Billboards now face their road.
* `LayoutPeds`: pier ped nodes sit on the deck (`_add_path(..., deck_abs)`), were on the sea floor. `stunt_jump_3` ramp moved to the pier end (z 198..210) so the pier path stays
  open; `stunt_jump_2` moved to z 126 (hangars occupy z < 116). Phone booth planner offset near the hospital changed (`interaction_props.gd`, one constant) so no booth stands
  at the (105,85) junction.

## Public API
`FillBuilder.stats` (`heroes props hero_fallback missing placed{}`), `FillBuilder.placed_heroes` (`[{id,pos,yaw,scale,rect}]`), `FillBuilder.prop(batch, name, pos, yaw, scale, collider)`,
`FillBuilder.place_free(batch, hero, pos, yaw, rng, scale)`, `LayoutFurniture.LANE_CLEAR / LANE_CHECKED / _lane_dist(pos)`.

## Verified (headless `fill_test.gd`, real renderer shots `screenshots/fill/after_downtown.png`, `after_docks.png`)
All 14 heroes placed, no missing GLB, CityBuilder 600-730 ms, all required locations resolve, helipads on roofs, furniture clear of lanes, no hero lot contains a lane point,
crane seaward, ferris animator registered, pier ped nodes on the deck. Shots show tower_a / tower_b / tower_c / hotel / ferris wheel / crane + containers / lighthouse / hangars in place.

## Not done / known limits
* No occluder boxes, no draw-call/CPU/GPU before-after numbers, no day/dusk/night screenshot sets, no airport-apron / beach / park close-ups viewed (props placed but only checked by counts).
* Backyards (fences, sheds, pools), extra street trees, hill-road rocks, tunnels, rooftop variety, bus-stop/planter/neon blade additions: not done.
* Hangars are scaled (0.72 / 0.86) because the airport strip is only 23.5 m deep before the apron / stunt ramp; `airport_hangar` location unchanged (apron side of lot 1).
* Dealer lot / shooting range already use their Blender GLBs through LandmarkBuilder (no stand-in); dealer_lot (60 x 40 m) is wider/deeper than its lot (55 x 12.6) and is centred on it,
  so it overlaps Anchor Alley (z 85) and the south shop lots - NOT fixed (needs a re-lot or scale 0.62).
* The elevator / roof-house planner (Systems-A) was not re-run against the new tower_a podium; hospital pad is cosmetic + location only (no new collider).
* Project `check` is green for all world-fill files; the 3 remaining VALIDATE FAILs are other agents' `debug_*.gd` (Variant inference).
