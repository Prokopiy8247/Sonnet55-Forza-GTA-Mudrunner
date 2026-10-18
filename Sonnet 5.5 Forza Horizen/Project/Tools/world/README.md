# Tools/world - terrain + road-network generator

Builds the whole 4.03 x 4.03 km world of "Roamline: Open Roads" (WORLD_SPEC.md) from code: heightmap, road network, terrain carving, landscape weight maps, vegetation density masks, JSON data products and review previews. Pure **Python 3.13 + numpy 2.3**, no other package, **no Blender, no Unreal, no network**. Deterministic (fixed seed `20260516`, byte-identical outputs on every run).

## Run

```
"W:\Blender\5.2\python\bin\python.exe" -I Tools\world\build_world.py            # full build, ~115 s, ~3.3 GB peak
"W:\Blender\5.2\python\bin\python.exe" -I Tools\world\build_world.py --no-previews   # skip the PNG previews
"W:\Blender\5.2\python\bin\python.exe" -I Tools\world\build_world.py --no-write      # do everything except the big raw files (metrics only)
"W:\Blender\5.2\python\bin\python.exe" -I Tools\world\build_world.py --fast          # design iteration: macro grid 4 m, no 1 m detail noise (not for export)
```

(`-I` = isolated mode; the Blender-bundled Python is used only as a plain interpreter that has numpy.) Run from the project root; paths are resolved relative to the script. Measured on the dev machine: 114 s wall clock for the full build with previews, peak working set 3.3 GiB (limits: 15 min, 6 GB).

The build prints a stage log (with memory probes), a road table (class, length, max grade, bridges / tunnels / culverts / hairpins per road) and a **PASS / FAIL acceptance table** (section "Acceptance metrics"). Exit code is 0 even when a metric fails; read the table (or `out/road_metrics.json`).

## Outputs

| Where | What |
|---|---|
| `Content/Forza/World/Source/` | Unreal-bound: `heightmap_4033.r16`, `layer_<Name>.r8` x 8, `density_*.r8` x 3, `slope.r8`, `region_id.r8` (git-ignored, ~234 MB) and copies of the four small JSON files |
| `Tools/world/out/` | `roads.json`, `river.json`, `world_meta.json`, `road_metrics.json` (small, tracked), `heightmap_4033_16bit.png` (inspection only) |
| `Tools/world/out/previews/` | `overview_1008.png` (hillshade + regions + roads + POIs), `route_highcrest_switchbacks.png`, `route_hwy_plateau.png`, `route_coast_bridge.png`, `route_greenvale.png`, `profile_LOOP.png`, `profile_PASS_SPUR.png` (elevation strips with bridge / tunnel / hairpin marks, grade colours), `slope_map.png`, `grade_histogram.png`, `layers_preview.png` |

Formats, units, coordinate conventions, flag bits and consumer notes: **`Docs/WORLD_DATA_FORMATS.md`**.

## Module map

| Module | Role |
|---|---|
| `build_world.py` | orchestrator: terrain -> roads -> carve -> layers -> metrics -> export -> previews |
| `worlddef.py` | world definition: regions + parameters, sites (POIs), river / brooks / Great Bay, platforms, sea stacks, Highcrest face model |
| `roads_def.py` | road classes, junction nodes, the road list (waypoints, ladders, forced bridge / tunnel spans, terrain-shaping guides) |
| `noise.py`, `geom.py`, `common.py`, `pngio.py` | lattice noise (B-spline gather, fbm, ridged), polyline helpers, constants / grid helpers / logging, own PNG writer |
| `terrain.py` | macro terrain (2 m grid) with regions, mountains + pass saddle, mesas / canyons, coast / beaches / bay, river valley, corridor shaping, 1 m detail; region-id map |
| `ladder.py` | switchback (ladder) generator for the Highcrest pass roads |
| `roadplan.py` | slope-limited least-cost planner (6 m cells, 16 neighbours, hard grade cap 1.4x class max, turn / corridor penalties) |
| `align.py` | horizontal alignment: simplify -> tangent arcs (min radii per class, hairpins) -> 2 m resampling, curvature, heading |
| `profile.py` | vertical profile (grade-limited banded least squares), node pins, bridge / tunnel / culvert detection (the uncovered ends of the forced tunnel become bridge / road), banking |
| `network.py` | junction graph (named nodes, T-junctions, auto crossings), profile solving in road order, per-sample attributes, junction / merge-zone flags |
| `carve.py` | road-bed (flat bed = paved + shoulders + 1.3 m) / cut (1:2) / fill (1:3) carving, no carving under bridges / tunnels, terrain ceiling 0.3 m below the deck over the first / last 15 m of every bridge, tunnel portal cuttings |
| `layers.py` | weight maps (sum 255), vegetation density masks, slope |
| `export.py` | r16 / r8 / JSON writers, road, node, edge and route tables |
| `metrics.py` | acceptance metrics + PASS / FAIL report |
| `preview.py`, `previews.py` | hillshade / contour / polyline drawing, the review images |

## Changing the world

* Roads: edit `roads_def.py` (`ROADS`, `NODES`). A road is `start`, `end` (node name or `("ON", road_id, (x, y))` T-junction hint), a waypoint list (corridor guide for the planner; `("bridge"|"tunnel", a, b)` entries are forced straight spans) and optional `ladder` / `shape` / `corridor` settings. New roads must be listed after the roads they join.
* Terrain / regions / POIs: edit `worlddef.py` (and `terrain.py` for the algorithms).
* After any change run the full build and check the PASS / FAIL table, then look at `previews/overview_1008.png` and the route zooms.
* The rebuild is deterministic, so a changed JSON / raw file means a changed definition.

## Acceptance metrics (printed at the end of every build)

total drivable length 40-60 km; LOOP closed and >= 22 km; >= 5 km uninterrupted highway; max grade and minimum radius per class; one connected network; no sample outside +-1990 m or on terrain below 0.5 m; >= 3 bridges (Great Bay 300-450 m); >= 1 tunnel (120-400 m); >= 8 pass hairpins; carved terrain within 0.2 m of the road bed on >= 99.8 % of the bed / shoulder samples (bridges, tunnels and junction / merge zones excluded and reported separately); heightmap range -60 .. +760 m; all four biomes + hub present. Current values are in `out/road_metrics.json` and in the final report of the build task.

## Current build (final run of this rework, all 13 acceptance checks PASS)

45.6 km of road (HIGHWAY 5.5, MOUNTAIN 15.4, REGIONAL 14.9, DIRT 8.1, VILLAGE 1.6), LOOP 23.1 km closed, 22 bridges (longest HWY_EAST 500 m), 1 tunnel (LOOP_DESC, 298 m, 3 m to 75 m of cover), 9 hairpins on LOOP_PASS (9 on LOOP_DESC and PASS_SPUR each), max grade at the class limit on every class, carve deviation max 1.08 m / p99 0.03 m, 99.92 % of the bed samples within 0.2 m, heightmap -51.8 .. 757.0 m.

## What changed in the last rework pass (and why)

* `carve.py`: the flat bed is 1.3 m wider than `bed_half_width` (`BED_BAND`). Where a neighbouring leg of a hairpin stack stood only 20-30 m away at a very different height, its embankment / wall started right at the shoulder edge and the bilinear samples across the bed saw it (330 bad samples on LOOP_DESC alone). The first / last 15 m of every bridge run get a terrain ceiling 0.3 m below the deck (no hump of natural terrain through the deck ends; `Tools/blender/world/make_hole_mask.py` still derives the tunnel-mouth holes from `roads.json` + heightmap, the bridge-end holes are no longer needed but stay harmless).
* `network.py`: `FLAG_JUNCTION` also marks the bed overlap (< 3 m height difference, up to 150 m from the shared node) between roads that meet at a node (branches leaving their parent at a shallow angle). Overlaps with a bigger height difference stay ordinary samples and count as defects.
* `profile.py`: the uncovered ends of the forced tunnel (natural terrain less than 2.5 m above the deck) are no longer tunnel; the tunnel starts where the hillside covers the bore, the stretch before it is bridge / embankment.
* `roadplan.py` / `roads_def.py`: the seed choice of a traced road can weight crossings (`cross_w`), overlapping legs (`hard_w`) and a missing tunnel (`tunnel_miss`); LOOP_DESC requires the tunnel and rejects designs that run beside another road (seed 7 of 16). `LOCAL_MILL_RING` now starts lower on the village street (it used to cross CASTLE_ROAD between two pins that no 10 % grade could connect: 199 % grade) and `LOCAL_FARM_B` leaves LOOP_SOUTH at a right angle instead of running along it.

## Known limitations

* **Hairpin embankments on the Highcrest roads.** Hairpin arcs are exempt from the fill-to-bridge rule and the profile weights them lightly, so some sit on very high fills: LOOP_PASS s 4780-4870 (up to 50 m), LOOP_DESC s 250-310 (42 m); in total 0.4 km (LOOP_PASS) and 0.9 km (LOOP_DESC) of road more than 8 m above the natural ground, and LOOP_SOUTH / LOOP_DESC / PASS_SPUR have cuttings up to 18 / 33 / 33 m. They carve consistently (the metric passes) but look like earth dams in 3D.
* **LOOP_DESC design.** The traced design is chaotic: any terrain change reshuffles the 16 seeds. The chosen seed has 335 overlapping-leg samples by the design measure (legs 20-30 m apart at 20-35 m height difference); the wider carve bed hides this in the metric, in the heightmap there are steep walls next to the shoulder in those stretches. The tunnel (298 m) is preceded by a 282 m viaduct (bridge, deck up to 73 m above the ravine) on its high side.
* **Carve deviation outside junction zones:** 15 samples above 0.2 m remain (LOCAL_DINER hairpin next to DIRT_WASH, max 1.08 m; DIRT_WASH 0.46 m). Junction / merge zones (flag 8) are reported separately (`carve_dev_junction_zones_*`, max 1.8 m).
* `LOCAL_MILL_MAIN` and `CASTLE_ROAD` run side by side (5-10 m apart) for ~100 m south of the Millbrook green; the two beds overlap there (counted as merge zone).
* The pin solver of `profile.py` does not detect node pins that the grade limit cannot connect (it produced the 199 % grade on `LOCAL_MILL_RING`); a new short road between two already solved roads can hit this again. The build table prints `<-- GRADE` and the acceptance check fails when it happens.
* Plateau elevations, the Highcrest massif shape and the beach / bay coast were not re-measured after the terrain rework (earlier notes about a planar south face, a median plateau height of 155 m and a short `COAST_SPUR` are obsolete / unverified; `COAST_SPUR` is 2.2 km now).
