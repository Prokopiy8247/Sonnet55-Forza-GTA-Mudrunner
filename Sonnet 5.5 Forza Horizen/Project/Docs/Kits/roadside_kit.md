# Roadside kit (Blender -> Unreal)

Generated 2026-10-16 by `Tools/blender/roadside/make_doc.py` from the JSON sidecars. 61 assets, 38 materials, 59071 triangles in total (sum of LOD0).

Source of truth: `Tools/blender/roadside/*.py` (idempotent scripts, executed in the shared Blender on port 9889). Binding conventions: `Docs/BLENDER_CONTRACT.md`.

## 1. Files

| What | Path |
|---|---|
| Entry point / registry | `Tools/blender/roadside/roadside_kit.py` (execs the parts below into a private namespace) |
| Library (bmesh primitives, materials, build / validate / export harness) | `Tools/blender/roadside/rs_lib.py`, `rs_font.py` (original stroke font), `rs_ads.py` (billboard artwork generator, numpy) |
| Builders | `rs_barriers.py`, `rs_barriers2.py`, `rs_traffic.py`, `rs_signs.py`, `rs_poles.py`, `rs_misc.py` |
| Doc generator | `Tools/blender/roadside/make_doc.py` |
| FBX + sidecar per asset | `Exports/Roadside/<asset_id>.fbx` + `<asset_id>.json` |
| Billboard ad textures | `Exports/Roadside/Textures/T_RS_BillboardAd_A/B/C.png` (2048 x 1024, original generic artwork) |
| Manifest (all assets, one file) | `Exports/Roadside/_manifest.json` |
| Blender staging | world position `(x_slot, 80, 0)`; collections `FORZA_UE/Roadside/<asset_id>` (mesh + hidden `UCX_*` hulls) |

Rebuild / re-export from the Blender MCP console:

```python
_p = r"<project>/Tools/blender/roadside/roadside_kit.py"; _g = {"__name__": "rs_kit"}
exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), _g)
_g["build"](["rs_guardrail_4m"])        # or _g["build"]() for the whole kit; idempotent
_g["validate_all"](); _g["export"]("rs_guardrail_4m"); _g["write_manifest"]()
```

## 2. Conventions

* Units: 1 BU = 1 m, Z up. Blender +X = forward / sign face / run direction. FBX recipe from `Tools/blender/lib/fbx_export.py` (`center_on="self"`, `use_triangles=True` so tangent space exports); in UE: x = x*100, y = -y*100.
* **Tileable segments** (`pivot: segment_start`) start at the origin and run along **+X** by their documented length. Rails, barriers, parapet and fences have their **traffic face on +Y** (the road lies on the +Y side when walking +X; rotate 180 deg about Z to use the other verge). Jersey barrier, bridge rail and stone wall are centred on y = 0.
* **Single props** (`ground_centre` / `ground_base`) have the origin on the ground at the base centre (street lamp, gantry lamp and utility pole: origin = pole base; arms/booms reach towards +Y). Culverts and the billboard use the head-wall / post line as origin (`ground_base`). Signs: post axis on the origin, **panel faces +X**, screen-right = +Y.
* **Guard-rail run convention** (walking +X, road on +Y): `rs_guardrail_end_terminal` = START (free head x=0, flared away from the road, bolts to the next rail at x=4.0); `rs_guardrail_4m` = body (posts at x=0 and 2.0, none at x=4.0); `rs_guardrail_end_terminal_R` = END (joins at x=0, brings its own joint post + splice bolts, head at x=4.0, mirror-built); `rs_guardrail_curved_end` = turned-down END (joins at x=0); `rs_guardrail_curved_end_R` = turned-down START (anchor at x=0, joins at x=4.2). Rotating a piece 180 deg about Z moves it to the opposite verge, it does NOT turn a start piece into an end piece. Parapet: `rs_parapet_mountain_3m` x N + `rs_parapet_mountain_end` at the far end.
* `rs_utility_wire_span_30m` (+ `_taut` / `_slack`) is the only asset without a ground contact (`pivot: attach_point`): the origin is the pole centreline at insulator-top height, so spawn it at `pole_base + (0, 0, 8.654)` (sidecar `extra.place_at_pole_base_offset`), next pole `extra.next_pole_offset` = (30, 0, 0).
* Rail / fence / pole posts are embedded 0.15-0.2 m below z = 0 so they can be planted on slopes; everything else sits at z = 0.
* One mesh object per asset named exactly like the asset id, transforms applied, no parent. Collision = `UCX_<id>_NN` convex hulls (<= 32 verts) exported in the same FBX (Blender hides them in the viewport).
* UVs: `UVMap` = metric box projection (1 UV unit = 1 m) for tiling materials; cylinders/lathes use arc-length UVs. The billboard face has UV 0..1 over the whole face. Vertex colour `Col` carries per-part tint / dirt (white = neutral) - the tinted materials (Concrete, Wood, Stone, Hay, Rust, Soil) multiply it in Blender; replicate with a VertexColor node in the UE master material.
* **Decal cards** (sign lettering, pictograms, bands, culvert marks): single-sided flat polygons 1.2-2.4 mm above the plate, tagged with a face attribute `decal` (the only open geometry in the kit; every other island is closed). They are drawn on a +X facing plane and their back is hidden by the plate; the sidecar field `decal_faces` counts them.
* Shading: per-face smooth flags (FBX `mesh_smooth_type=FACE`). Curved surfaces are smooth, chamfered boxes / flat plates are flat.
* Max 8 materials per asset (all assets: <= 8, most <= 6). Materials are shared by name `M_RS_*`.

## 3. Assets

### Barriers, rails, posts and bollards

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_guardrail_4m` | 4.06 x 0.31 x 0.96 | 524 | GalvSteel, PaintBlack, GalvDark, ReflectorWhite | box (3 UCX) | 1.00-1.00 | BODY. Tile every 4.0 m along +X (posts at x=0 and x=2.0, none at x=4.0); traffic face +Y, posts behind (-Y). W-beam top 0.75 m, posts 0.80 m, galvanised C-posts + black composite blocks. |
| `rs_guardrail_end_terminal` | 4.01 x 0.54 x 1.00 | 1252 | GalvSteel, PaintBlack, GalvDark, ReflectorWhite, PaintYellow, ReflectorAmber | box (5 UCX) | 1.00-1.00 | START of a run: flared (0.32 m) impact head at x=0, bolts onto the first post of a rail at x=4.0. For the END of the same run use _R (rotating 180 deg puts the posts on the road side). |
| `rs_guardrail_end_terminal_R` | 4.07 x 0.54 x 1.00 | 1480 | GalvSteel, PaintBlack, GalvDark, ReflectorWhite, PaintYellow, ReflectorAmber | box (6 UCX) | 1.00-1.00 | END of a run (mirror-built from the start terminal, winding fixed, no negative scale): joins the previous rail at x=0 with its own joint post + splice bolts, impact head at x=4.0. |
| `rs_guardrail_curved_end` | 4.56 x 1.57 x 0.96 | 1400 | GalvSteel, PaintBlack, GalvDark, ReflectorWhite, Concrete | box (7 UCX) | 1.00-1.00 | END of a run, turned down: joins the previous rail at x=0 (own joint post), leaves the run line after 1.2 m, curves 1.15 m away from the road (-Y) and dives into a concrete ground anchor with steel eye at x=4.2. |
| `rs_guardrail_curved_end_R` | 4.50 x 1.57 x 0.94 | 1172 | GalvSteel, PaintBlack, GalvDark, ReflectorWhite, Concrete | box (6 UCX) | 1.00-1.00 | START of a run, turned down (mirror-built): anchor at x=0, rail returns to the run line and joins the next rail at x=4.2 (the next rail brings the post and bolts at that joint). |
| `rs_parapet_mountain_3m` | 3.08 x 0.72 x 1.44 | 1488 | ConcreteDark, Stone, Wood, GalvDark | box (3 UCX) | 1.00-1.00 | Stone-faced wall (both faces coursed, pier at x=0) + two timber rails. Traffic face y=0, body to -Y. Close the run with rs_parapet_mountain_end. |
| `rs_parapet_mountain_end` | 1.69 x 0.72 x 1.44 | 1004 | ConcreteDark, Stone | box (4 UCX) | 1.00-1.00 | END of a parapet run: same stone pier as the segment (origin on the far end of the last segment) + 1.0 m stepped wall return that dives into the hillside. |
| `rs_barrier_jersey_3m` | 3.03 x 0.62 x 0.83 | 500 | Concrete, GalvDark, ReflectorAmber, ConcreteDark | box (1 UCX) | 1.00-1.00 | Symmetric New-Jersey profile 0.78 m (0.82 m with lifting loops), centreline y=0, 3.0 m, grooves every metre, amber reflectors. |
| `rs_bridge_rail_2m` | 2.11 x 0.22 x 1.11 | 666 | GalvDark, PaintGrey, GalvSteel | box (1 UCX) | 1.00-1.00 | Post on origin, round top/mid/low rails + 7 balusters + kick plate, 1.08 m high. Tile every 2.0 m. |
| `rs_delineator_post` | 0.23 x 0.22 x 1.00 | 382 | PlasticWhite, PaintBlack, ReflectorRed, Rubber | none | 1.00-1.00 | Reflector (red) faces +X. Variants: _white, _amber. |
| `rs_delineator_post_white` | 0.23 x 0.22 x 1.00 | 382 | PlasticWhite, PaintBlack, ReflectorWhite, Rubber | none | 1.00-1.00 | Left-hand verge variant. Reflector faces +X. |
| `rs_delineator_post_amber` | 0.23 x 0.22 x 1.00 | 382 | PlasticWhite, PaintBlack, ReflectorAmber, Rubber | none | 1.00-1.00 | Tunnel / hazard variant. Reflector faces +X. |
| `rs_bollard_stone` | 0.37 x 0.37 x 0.85 | 510 | Stone, PaintWhite, ReflectorRed | convex (1 UCX) | 0.90-1.15 | Granite bollard with painted band, 0.85 m. |
| `rs_bollard_plastic` | 0.26 x 0.26 x 0.96 | 468 | Rubber, PlasticWhite, PlasticOrange, ReflectorWhite | none | 0.90-1.10 | Flexible plastic bollard 0.96 m; give it no collision. |

### Traffic furniture (cone, drum, tyres, hay bales)

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_traffic_cone` | 0.38 x 0.38 x 0.70 | 416 | Rubber, PlasticOrange, ReflectorWhite | convex (1 UCX) | 0.90-1.15 | 0.70 m cone, black base, two reflective collars. |
| `rs_traffic_barrel` | 0.58 x 0.58 x 0.94 | 894 | PlasticOrange, ReflectorWhite | convex (1 UCX) | 0.90-1.10 | Channelizer drum 0.95 m, orange/white. |
| `rs_tyre_stack` | 0.63 x 0.63 x 0.80 | 5064 | TyreRubber, TyrePaint, PlasticOrange, GalvDark, GalvSteel | convex (1 UCX) | 0.90-1.10 | 4 tyres (white-painted / black alternating, different radius / yaw / tilt): ribbed tread with lug slots, chamfered shoulders, bead lip, raised lettering ring on the top tyre, 2 ratchet straps with buckles seated in the seams. |
| `rs_hay_bale_roadblock` | 0.69 x 3.04 x 1.02 | 2644 | Hay, Rope, Wood, PaintWhite, PaintRed | box (1 UCX) | 0.90-1.10 | 5 bales with streaky straw vertex colour + straw tufts, twine, red/white warning board; spans Y (2.8 m); front +X. |

### Road signs on posts

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_sign_speed_30` | 0.12 x 0.70 x 2.73 | 914 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge. |
| `rs_sign_speed_50` | 0.12 x 0.70 x 2.73 | 898 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge. |
| `rs_sign_speed_70` | 0.12 x 0.70 x 2.73 | 872 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge. |
| `rs_sign_speed_90` | 0.12 x 0.70 x 2.73 | 924 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge. |
| `rs_sign_speed_110` | 0.12 x 0.70 x 2.73 | 876 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge. |
| `rs_sign_curve_left` | 0.12 x 0.85 x 2.86 | 497 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Place 60-120 m before a left-hand bend; face +X. |
| `rs_sign_curve_right` | 0.12 x 0.85 x 2.86 | 497 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Place 60-120 m before a right-hand bend; face +X. |
| `rs_sign_hairpin` | 0.12 x 0.85 x 2.86 | 497 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Before hairpin switchbacks; face +X. |
| `rs_sign_steep_descent` | 0.12 x 0.85 x 2.86 | 555 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Before steep downhill sections; face +X. |
| `rs_sign_tunnel` | 0.12 x 0.85 x 2.86 | 486 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | 80-150 m before tunnel portals; face +X. |
| `rs_sign_bridge` | 0.12 x 0.85 x 2.86 | 500 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Before bridges; face +X. |
| `rs_sign_junction` | 0.12 x 0.85 x 2.86 | 479 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed, SignBlack | box (2 UCX) | 1.00-1.00 | Before side-road junctions; face +X. |
| `rs_sign_give_way` | 0.12 x 0.85 x 2.60 | 474 | GalvSteel, GalvDark, SignWhite, SignBack, SignRed | box (2 UCX) | 1.00-1.00 | At minor road junctions; face +X. |
| `rs_sign_stop` | 0.12 x 0.78 x 2.72 | 950 | GalvSteel, GalvDark, SignRed, SignBack, SignWhite | box (2 UCX) | 1.00-1.00 | At stop-controlled junctions; face +X. |
| `rs_sign_direction_s` | 0.12 x 1.20 x 2.58 | 747 | SignBlue, SignBack, SignWhite, GalvSteel, GalvDark | box (2 UCX) | 1.00-1.00 | Small direction sign on one post (rural junction). Face +X. |
| `rs_sign_direction_m` | 0.12 x 1.80 x 2.68 | 1074 | SignBlue, SignBack, SignWhite, GalvSteel, GalvDark, SignBlack | box (3 UCX) | 1.00-1.00 | Medium direction sign on two posts. Face +X. |
| `rs_sign_direction_l` | 0.12 x 2.80 x 3.13 | 1293 | SignBlue, SignBack, SignWhite, GalvSteel, GalvDark, SignBlack | box (3 UCX) | 1.00-1.00 | Large direction sign on two posts for highways / major junctions. Face +X. |
| `rs_sign_village` | 0.12 x 1.50 x 1.94 | 978 | SignWhite, SignBack, SignBlack, GalvSteel, GalvDark | box (3 UCX) | 1.00-1.00 | Village entrance sign on two posts. Face +X. |
| `rs_milemarker` | 0.24 x 0.24 x 1.00 | 318 | PlasticWhite, SignGreen, SignWhite, PaintBlack, ReflectorAmber, Rubber | box (1 UCX) | 1.00-1.00 | White plastic km post with green plate; plate faces +X. |
| `rs_sign_chevron_right` | 0.12 x 0.80 x 2.48 | 548 | GalvSteel, GalvDark, SignYellow, SignBack, SignBlack | box (2 UCX) | 1.00-1.00 | Outside of bends; chevron points right as seen by the driver (face +X). |
| `rs_sign_chevron_left` | 0.12 x 0.80 x 2.48 | 548 | GalvSteel, GalvDark, SignYellow, SignBack, SignBlack | box (2 UCX) | 1.00-1.00 | Outside of bends; chevron points left as seen by the driver (face +X). |
| `rs_sign_jump` | 0.12 x 0.88 x 2.84 | 1008 | GalvSteel, GalvDark, SignYellow, SignBack, SignBlack | box (3 UCX) | 1.00-1.00 | Before stunt ramps / road crests marked as jumps; face +X. |
| `rs_speedtrap_camera` | 1.55 x 0.50 x 3.36 | 1178 | GalvDark, PaintGrey, PaintBlack, ReflectorRed, ReflectorWhite, ReflectorAmber, SignYellow | box (3 UCX) | 1.00-1.00 | Camera housing looks along +X; sockets camera_lens / flash in sidecar. |

### Street / gantry lighting

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_streetlamp_8m` | 0.52 x 2.78 x 8.16 | 1850 | Concrete, GalvDark, GalvSteel, PaintBlack, PaintGrey, LampLens | box (2 UCX) | 1.00-1.00 | Arm reaches 2.55 m towards +Y. Light socket in sidecar. Lens = M_RS_LampLens (emissive). |
| `rs_gantry_lamp` | 0.72 x 6.08 x 10.00 | 1590 | GalvDark, GalvSteel, PaintBlack, PaintGrey, LampLens | box (3 UCX) | 1.00-1.00 | 10 m pole + 5.7 m cantilever truss towards +Y + 3 flood heads. Light sockets in sidecar. |

### Utility poles and wire

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_utility_pole_9m` | 0.37 x 2.40 x 9.28 | 1780 | Wood, PaintBlack, GalvDark, Insulator, GalvSteel | box (2 UCX) | 0.95-1.10 | Crossarm along Y; wire attach sockets (wire_L / wire_R / wire_top) in sidecar. |
| `rs_utility_wire_span_30m` | 30.00 x 1.82 x 1.35 | 918 | Wire | none | 1.00-1.00 | Origin = pole centreline at insulator-top height: spawn at pole_base + (0, 0, 8.654); 3 conductors start on the insulator tops, 0.70 m sag, end 30 m along +X (next pole). Id requested as utility_wire_span_30m (rs_ prefix added). |
| `rs_utility_wire_span_30m_taut` | 30.00 x 1.82 x 1.05 | 918 | Wire | none | 1.00-1.00 | Same placement as rs_utility_wire_span_30m, 0.40 m sag. |
| `rs_utility_wire_span_30m_slack` | 30.00 x 1.82 x 1.70 | 918 | Wire | none | 1.00-1.00 | Same placement as rs_utility_wire_span_30m, 1.05 m sag. |

### Fences and walls

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_fence_wood_2_5m` | 2.68 x 0.36 x 1.45 | 470 | Wood, Soil, GalvDark | box (2 UCX) | 1.00-1.00 | Post (with soil mound) on origin, 3 rails (two overlapping split timbers each) run to the next post; close a run with rs_fence_wood_endpost. _b (rails 8 cm lower) and _c (two rails) share post and envelope. |
| `rs_fence_wood_2_5m_b` | 2.68 x 0.36 x 1.45 | 470 | Wood, Soil, GalvDark | box (2 UCX) | 1.00-1.00 | Variant: three rails at 0.30 / 0.66 / 1.02 m. |
| `rs_fence_wood_2_5m_c` | 2.68 x 0.36 x 1.45 | 358 | Wood, Soil, GalvDark | box (2 UCX) | 1.00-1.00 | Variant: two rails at 0.55 / 1.05 m. |
| `rs_fence_wood_endpost` | 0.44 x 0.36 x 1.45 | 266 | Wood, Soil | box (1 UCX) | 1.00-1.00 | Closes the last panel of a post-and-rail run (rail stubs point to -X). |
| `rs_fence_wire_3m` | 3.17 x 0.32 x 1.44 | 854 | Wood, Soil, GalvDark, Wire | none | 1.00-1.00 | Round wooden post on origin + steel T-post at mid span, 5 strands + vertical stays. |
| `rs_fence_wire_endpost` | 1.92 x 0.46 x 1.61 | 420 | Wood, Soil, Wire | none | 1.00-1.00 | Corner / end strainer for the wire fence: strainer post on the origin, brace runs 1.5 m to +X. Rotate 180 deg to close the far end. |
| `rs_wall_stone_2m` | 2.05 x 0.63 x 0.98 | 976 | Mortar, Stone | box (1 UCX) | 1.00-1.00 | Dry-stone wall, both faces coursed with pillow-faced stones, 0.55 m thick, centreline y=0. |
| `rs_wall_stone_2m_b` | 2.06 x 0.64 x 0.97 | 1036 | Mortar, Stone | box (1 UCX) | 1.00-1.00 | Variant B: same envelope / end faces, 5 courses of different heights and stone lengths (alternate with the base segment). |

### Village furniture

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_bus_stop_shelter` | 2.25 x 4.13 x 3.20 | 2018 | Concrete, PaintGrey, SignBlue, LampLens, Glass, WoodPale, SignWhite | box (4 UCX) | 1.00-1.00 | Open/bench side faces +X. Glass = separate M_RS_Glass slot (translucent in UE). Not Nanite (translucent). |

### Billboard

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_billboard_roadside` | 1.83 x 6.34 x 8.09 | 2016 | GalvDark, GalvSteel, BillboardFace, Grating, PaintGrey, LampLens | box (3 UCX) | 0.90-1.40 | Face (M_RS_BillboardFace, UV 0..1 over whole face) faces +X, preview shows original ad A; ads B / C ship as textures + preview materials; 4 lamp sockets in sidecar. |

### Culvert head-walls

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_culvert_headwall_a` | 2.14 x 5.09 x 1.90 | 2196 | Concrete, PaintBlack, ConcreteDark, GalvSteel, Rust | box (6 UCX) | 0.90-1.30 | Round 1.24 m pipe with collar + mortar fillet, 35 deg wing walls, apron, coping with drip step, belt course, weep holes, form ties, ID plate. Opening faces +X. Collision: 4 hulls frame the open mouth + 1 closed wedge per wing. |
| `rs_culvert_headwall_b` | 2.52 x 5.13 x 2.64 | 1344 | Concrete, PaintBlack, ConcreteDark, GalvSteel, Rust | box (17 UCX) | 0.90-1.30 | Box opening 1.8 x 1.24 m with trash rack, stepped wing walls, guard posts + rail, weep holes. Opening faces +X. Collision: frame hulls + one closed hull per wing step / post + thin rack hull. |

### Mountain markers

| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |
|---|---|---|---|---|---|---|
| `rs_cairn_stack` | 1.15 x 1.15 x 1.24 | 660 | Stone | convex (1 UCX) | 0.70-1.50 | Eight balanced stones (angular slabs alternating with rounded river stones, per-stone colour) + 9 angular / rounded chips. |
| `rs_milestone_stone` | 0.48 x 0.30 x 0.82 | 274 | Stone, PaintWhite, PaintBlack, PaintRed | box (1 UCX) | 0.90-1.20 | Granite slab with painted number plate (12 km) facing +X. |

### Sign family (flat panels with modelled rims, raised borders and geometric pictograms)

Speed limits 30 / 50 / 70 / 90 / 110, curve left / right, hairpin, steep descent (12 %), tunnel, bridge, junction, stop, give way, three blue direction signs (small 1.2 x 0.45 on one post, medium 1.8 x 0.65 and large 2.8 x 1.15 on two posts), village name sign, kilometre marker, chevron boards (left / right), danger-jump diamond + JUMP plate, speed-trap camera post. All symbols and place names (OAKRIDGE, HARBOR, SUMMIT) are original and built from geometry (stroke font in `rs_font.py`, 11-22 segments on round glyphs), nothing is copied from real sign sets. Plates, folded rims and posts are closed solids; borders, lettering and pictograms are single-sided decal cards (see Conventions), which keeps every sign at 0.3-1.3 k triangles. Panel faces +X; all signs share the 7 sign materials (`SignWhite/Red/Black/Blue/Yellow/Green`, `SignBack`) + `GalvSteel`/`GalvDark` for hardware.

## 4. Materials (UE master-material instances are created BY NAME)

| Material | Use |
|---|---|
| `M_RS_BillboardFace` | billboard face (UV 0..1), preview = ad texture A; swap the texture per material instance |
| `M_RS_Concrete` | cast concrete (tinted by vertex colour, dirt gradient near the ground) |
| `M_RS_ConcreteDark` | stained / wet concrete, kerbs, aprons |
| `M_RS_GalvDark` | dark galvanised hardware: bolts, brackets, bases |
| `M_RS_GalvSteel` | zinc-coated steel: rails, posts, rails, tubes (metallic 0.9, rough 0.4) |
| `M_RS_Glass` | shelter glass - TRANSLUCENT |
| `M_RS_Grating` | catwalk grating |
| `M_RS_Hay` | straw (tinted) |
| `M_RS_Insulator` | ceramic pin insulators |
| `M_RS_LampLens` | LED lens - EMISSIVE (drive from a time-of-day parameter) |
| `M_RS_Mortar` | core between stones |
| `M_RS_PaintBlack` | black rubber-like plastic, bands, cabinet doors |
| `M_RS_PaintGrey` | powder-coated steel (shelter, bridge rail, cabinets) |
| `M_RS_PaintRed` | red paint |
| `M_RS_PaintWhite` | white paint / posts / tyres |
| `M_RS_PaintYellow` | impact head |
| `M_RS_PlasticOrange` | cone / drum / bollard |
| `M_RS_PlasticWhite` | delineator posts |
| `M_RS_ReflectorAmber` | retro-reflective amber |
| `M_RS_ReflectorRed` | retro-reflective red (emissive hint) |
| `M_RS_ReflectorWhite` | retro-reflective white |
| `M_RS_Rope` | bale twine |
| `M_RS_Rubber` | tyres, feet |
| `M_RS_Rust` | trash rack, rebar eyes |
| `M_RS_SignBack` | folded sign rim and back |
| `M_RS_SignBlack` | sign black |
| `M_RS_SignBlue` | direction signs |
| `M_RS_SignGreen` | km marker plate |
| `M_RS_SignRed` | sign red |
| `M_RS_SignWhite` | sign faces / lettering (retro-reflective) |
| `M_RS_SignYellow` | warning boards |
| `M_RS_Soil` | soil mound at post feet (tinted) |
| `M_RS_Stone` | granite / dry stone (tinted) |
| `M_RS_TyrePaint` | white tyre paint (tinted, scuffs) |
| `M_RS_TyreRubber` | tyre rubber (tinted, dirt gradient near the ground) |
| `M_RS_Wire` | fence / power wire |
| `M_RS_Wood` | timber (tinted) |
| `M_RS_WoodPale` | bench slats |

## 5. Recommended Unreal setup

* **Static meshes**: enable Nanite for everything except `rs_bus_stop_shelter` (translucent glass slot). Mobility Static. Import with *Auto Generate Collision = off* - the `UCX_*` hulls come with the FBX. `collision: none` assets (delineator posts, flexible bollard, wire fence panel + strainer assembly, wire span) ship without UCX hulls and should have no collision; use *Simple* collision only for the rest.
* **Instancing**: tile rails / barriers / fences / walls as splines or HISM runs at the documented segment length. Recommended placement spacing: guard rail 4.0 m, jersey 3.0 m, parapet 3.0 m, bridge rail 2.0 m, wood fence 2.5 m, wire fence 3.0 m, stone wall 2.0 m, delineators 25-50 m, street lamps 30-45 m (alternate sides on dual carriageways), utility poles 30 m (wire span 30 m, scale X by 0.9-1.1 and re-aim to bridge the gap), speed-limit / warning signs 2-4 m from the road edge, km markers every 1 km, chevron boards every 8-15 m in bends.
* **Scale range** per asset is in the table (rails / signs 1.0 only; props 0.9-1.15; culverts / billboard 0.9-1.4).
* **Emissive**: `M_RS_LampLens` (street lamp, gantry, shelter light strip / light box, billboard lamps) and the `M_RS_Reflector*` slots should be driven by headlight / time-of-day parameters. Light sockets (spot light origin) are listed per asset in the sidecar `sockets`.
* **Wind**: none (no vegetation); the wire span can optionally get a tiny WPO sway on the vertical axis.
* **Colour grading**: vertex colour `Col` is neutral white on non-tinted parts; keep it enabled in the master material.

## 6. Validation (run in Blender, `validate_all()`)

Every asset passes: object / collision names, transforms applied, no parent, ground / pivot rule, <= 8 material slots with `M_RS_*` names and none unused, `UVMap` present with no degenerate (zero-area) UV face, no loose vertices, no zero-area faces, all solid islands closed (open boundaries are allowed only on tagged decal cards), no inverted islands (signed-volume test), triangle budget per asset, and every `UCX_*` hull is a closed, convex, positive-volume mesh with <= 32 vertices (flat quads / open shells are rejected by the validator). Largest meshes: `rs_tyre_stack` 5064, `rs_hay_bale_roadblock` 2644, `rs_culvert_headwall_a` 2196, `rs_bus_stop_shelter` 2018, `rs_billboard_roadside` 2016, `rs_streetlamp_8m` 1850 tris.

## 7. Known weaknesses

* Sign graphics are single-sided decal cards 1.2-2.4 mm above the plate (no relief sides): crisp and original, but at grazing angles / very close the card edge shows a hairline gap, and the retro-reflective response must come from the UE material (`SignWhite/Red/...` need a clear-coat / emissive-at-night term).
* Stonework (parapet, wall, cairn, bollard, milestone) is pillow-faced frustum blocks / pebbles with vertex-colour tint; the fine surface detail must come from a tiling UE stone material (UV is metric).
* Tyre stack: black rubber barely shows its tread in a flat preview (needs normal / AO in UE); painted tyres expose rubber in the grooves and lug slots; there are 10-12 lug slots per tyre (30 / 36 radial segments) and the lower three tyres have a simplified hidden sidewall. 5.1 k triangles (budget 5.2 k) makes it the heaviest asset of the kit.
* Hay bales: lumpy low-poly shells with streaky vertex colour and ~30 straw tufts each, no real straw cards / fuzz; M_RS_Hay still wants a UE straw texture.
* Fence wire, stays and the power wires are 3-8 mm geometry: they alias without Nanite + TSR. A masked-card far version for non-Nanite platforms is NOT provided (it needs an alpha-masked UE material).
* Guard-rail pieces butt-joint (4 splice bolts, no real lap overlap). The handed pieces are mirror-built copies: for a run on the opposite verge rotate the whole run 180 deg about Z, never mirror.
* Utility wire spans have a fixed sag (0.40 / 0.70 / 1.05 m variants); non-uniform scaling changes the sag proportionally.
* Billboard: three original ad textures ship, the Blender mesh carries ad A only (ads B / C are separate preview materials: swap per UE material instance). The shelter poster / light box is still a flat emissive panel.
* No hand-made LODs (Nanite assumed). `rs_bus_stop_shelter` (translucent glass slot, 7 material slots) needs classic LODs if it must be placed in great numbers; a lighter proxy for the stone wall / parapet is not provided.
* Culvert aprons and pipe interiors carry no collision (drive-over / pass-through by design); the pipe mouth is framed by hulls, so the 1.24 m square opening is slightly larger than the round bore.
* Triangle budgets: every asset is within its registered budget; the sign set (0.3-1.3 k) is inside the 0.2-2 k sign budget and the guard-rail pieces are <= 1.5 k. Only the tyre stack (5.1 k) and hay roadblock (2.6 k) sit above the generic 2 k prop figure on purpose.
* Asset ids use the `rs_` prefix; the brief name `utility_wire_span_30m` is `rs_utility_wire_span_30m`.
