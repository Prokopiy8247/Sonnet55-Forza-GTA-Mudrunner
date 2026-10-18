# CARKIT_API - shared car kit for Blender -> Unreal (Blender 5.2 / Python 3.13)

Library: `Tools/blender/lib/carkit.py` (~3.45 k lines, ~131 functions/classes, one file, no add-ons, no external assets; `KIT_VERSION` 1.1.0 = rev 3).
Inspection helpers (read-only, never touch the scene): `Tools/blender/lib/zebra.py` (reflection-stripe surface analysis), `Tools/blender/lib/sectionplot.py` (2-D cross-section / profile plots).
Pulse QA scripts (rev 3, `Tools/blender/qa/`): `car01_profile.py` (side / plan / ring plots of the body curves, no build needed) and `car01_focus.py` (puts a wire
cube `car01_hatch_pulse_QAfocus` at a car-space point so `look(target=['car01_hatch_pulse_QAfocus'], distance=1.1..2.4)` gives close-ups).
Worked example: `Tools/blender/cars/car01_hatch_pulse.py` (the "Pulse"). Export helper it builds on: `Tools/blender/lib/fbx_export.py`.
Everything here follows `Docs/BLENDER_CONTRACT.md` (axes, part names, pivots, material names, export recipe) and
`Docs/CAR_ROSTER.md`.

---------------------------------------------------------------------------------------------------------------------------
## 1. Loading the kit and conventions

Every MCP `execute_blender_code` call gets a **fresh namespace**, so load the kit in every call (idempotent, ~0.1 s):

```python
KIT = r"<project>\Tools\blender\lib\carkit.py"
exec(compile(open(KIT, encoding="utf8").read(), KIT, "exec"), globals())
```
A car script does the same at its top (path derived from `bpy.data.filepath`) and is itself run with
`exec(compile(open(path, encoding="utf8").read(), path, "exec"), globals())`. It may read an optional global
`CAR0N_STAGE` ("geometry" | "uv1" | "uv2" | "uv3" | "all") - UV unwrapping (smart project, ~2-4 s per mesh, up to 2x slower when other agents load
Blender) is split in three calls so each Blender call stays < 20 s (Pulse geometry ~2-8 s, uv1 = Body/Glass/Interior/SteeringWheel ~8 s,
uv2 = Wheel_FL/FR ~6 s, uv3 = Wheel_RL/RR ~7 s; `validate_car` ~15-25 s: call it on its own).

* Car space: `+X` forward, `+Y` left, `+Z` up, 1 unit = 1 m, origin on the ground under the middle of the wheelbase.
  Geometry is built in car space with bmesh; objects get an identity transform and are parented (identity parent-inverse) to the
  root empty that sits at the staging position (`x = index * 12 m`). Child `location` values are therefore car-space metres.
* All bmeshes produced by the kit store **global material slot indices** (`MAT_ORDER`, see section 3.1). `finish_object()` creates
  only the used slots and remaps the faces. Use `mi('M_Paint')` for the index of a standard material.
* Left-hand builders (suffix `L` / "left, mirrored") return +Y geometry; mirror with `mirrored_copy(bm)` (flips y AND winding, no
  negative scale anywhere).
* Ray modes of the surface tools: a direction `(0,-1,0)` = parallel projection (ray starts outside, travels along the vector),
  or `('radial', C)` = point-source projection from a centre `C` *inside* the body (best for lamps that wrap round a corner).

---------------------------------------------------------------------------------------------------------------------------
## 2. Recipe for a new car (what `car01_hatch_pulse.py` does, in order)

1. **Header**: load kit, `remove_asset(car_id)`, `build_standard_materials()`, `col = ensure_collection("FORZA_UE/Cars/<id>")`,
   `root = make_empty("<id>_ROOT", col, location=(12*index,0,0))`, `set_root_props(root, wheelbase=..., track_front=..., ...)`.
2. **Profile curves** (`body_curves()`): `zf` (floor), `zt` (top centre line), `hwm`/`zw` (max half width and its height), `zb`
   (belt), `hwe` (hood/roof edge half width), optional `zc`/`cdepth` (shoulder line) ... see 3.5. **Design them, do not hand-key
   wiggles** (rev 2): the top line `zt` is a `fillet_profile([(x, z), ...], [radius, ...])` polyline (straight windscreen / hatch
   glass, tangent-continuous corners); every other curve is a few sparse keys passed through `smooth_keys(keys, sigma)`
   (Gaussian smoothing = no curvature wiggles between the keys = clean reflections). Plan-view taper at the nose/tail comes from
   `hwm`; a nose that must look round and upright is better defined as an analytic superellipse quadrant (callable curve, Pulse rev 3:
   `NOSE_N = 2.45`) than as sparse keys (sparse keys give a straight 45 degree chamfer). Round the tail AND the nose edge with
   `loft_body(..., round_x0=r, round_x1=r)` + `end_round_stations()` and a small `cap_bulge` (0.02) instead of a hard-edged or
   domed cap (a big dome shows as a pyramid with diagonal facets, rev 3). Shoulder crease = `zc` + `cdepth` + `cwidth` (rev 3).
3. **Loft**: `shell = loft_body(curves, station_list(...), ring_density=2.0, cap_rings=4, cap_bulge=0.04, round_x0=0.09)`;
   `surf0 = Surface(shell.bm)` (the UNCUT surface all projections use). Colour material zones by ring column with
   `shell_quad_cols(shell, 'belt_up', 'edge', side, frac=None)` + the `TAG_COL` face attribute (`face_tags(bm)`).
4. **Cutters** (all built on `surf0`, subtracted in ONE `bm_boolean`): `wheel_arch_cutter` (4x), shut lines via
   `surface_sweep(surf0, pts, ray, groove_profile())`, pockets via `pocket_cutter`, `plate_recess`, `build_headlight`,
   `build_taillight`, `build_diffuser`, `lamp_unit` (fog lamps), exhaust cylinders.
5. **Boolean**: `bm = bm_boolean(shell.bm, cutters)` (MANIFOLD solver, 0.1-0.3 s for ~30 cutters). Optionally chamfer the pocket
   rims with `bevel_hard_edges(..., edge_filter=...)`.
6. **Add-ons that hug the skin** (appended after the boolean with `bm_append`): lens patches / light bars from step 4, `arch_moulding`
   (black flares), side skirts (`surface_sweep` + `rib_profile`), `build_splitter`, `door_handle`, `grille_mesh` inserts seated
   with `anchor_frame`, wipers, roof `build_roof_spoiler` (hatch roof-edge spoiler with end plates) / `build_lip_spoiler` /
   `build_wing`, `build_shark_fin`, `build_mirror`, `build_exhaust_tip`. Arch flares are `surface_sweep` strips with `rib_profile` along an
   arc whose radius = hole radius + width/2 (inner edge exactly on the cut edge); build them for the LEFT wheels only and `add_pair`
   them (rev 2 mirrored the right-wheel strips onto the left side by mistake). Lamps wrapping a corner: `build_headlight_blade`.
7. **Glass**: `glass = extract_glass(bm, windows, offset=0.014)` - windows are described by the `TAG_COL` columns of the shell +
   exact bisect planes for the pillar lines (see the Pulse for the 4 windows). Pillars stay in the body; the opening gets a black
   reveal, the glass is a thin separate sheet 14 mm inside. Round the reveal edges with `bevel_hard_edges(bm, 50, 0.0045, 2,
   edge_filter=...)` (rev 3: pillars get a cross-section instead of razor-thin flat slabs). Build the interior trims from the black
   pillar / roof faces with `inner_trim_from_faces(bm, pred)` - black plastic for the pillars, light lining for the roof.
   Keep the black pack ONE graphic: pillar colour zone = the whole `belt_up -> edge` ring band down to the glass base line (x of the
   hatch glass base), not a pack that stops at an arbitrary x (rev 2 left a red horn behind the C-pillar).
8. **Finish**: `heal_nonmanifold(bm)` (optional, finish_object does it too), `body = finish_object("<id>_Body", bm, col, parent=root, smooth_angle=62)` then `apply_shell_normals(body, shell)`
   (smooth custom normals from the lofted shell -> boolean fans never show), `shell.ref.free()`;
   `finish_object("<id>_Glass", glass, ...)`.
9. **Wheels**: `build_wheel(radius, width, style='multi'|'star'|'steel'|'wire', side=+1/-1)` -> `finish_object("<id>_Wheel_FL",
   wb, col, parent=root, location=(x, y, radius))` (origin = axle centre; right wheels are mirror-built, not negative-scaled).
10. **Interior**: `build_interior(shell, spec)` (+ extra trims) -> `<id>_Interior`; `build_steering_wheel(...)` ->
    `<id>_SteeringWheel` with `location=hub` and `ob['rim_axis'] = [..]`.
11. **Collision**: `make_ucx_hulls(car_id, [hull_points_from_shell(...), ...], col, root)` (3 hulls <= 32 verts, convex).
12. **Empties** `LP_HeadL/R, LP_TailL/R, LP_Reverse, CAM_Hood, CAM_Cockpit, CAM_Bumper, EXHAUST_L/R` via `make_empty`
    (the Pulse seats the lamp empties on the lamp surface), then write measured `length/width/height` into the root props.
13. **UV**: `uv_unwrap(obj)` for every part (also `uv_unwrap_body`) in three calls; for the body also `uv_livery_layer(body)`
    (2nd channel `UVLivery`: 5 big planar islands for stripes / liveries, `UVMap` stays the first channel).
14. **QA**: `qa_studio(car_id, True)` + `look(mode='angles', target=[root], shading='solid'|'material'|'rendered')`; fix; repeat.
    Judge surface quality with `zebra_car(root, out_dir)` (see 3.13) and the shell cross sections with `plot_lines`.
    `qa_studio(car_id, False)` before finishing.
15. **Gate**: `validate_car(root_name, targets=dict(length=..., width=..., height=..., wheelbase=...))` -> must be `ok`.
16. **Export**: `export_car(root_name)` -> `Exports/Cars/<id>/` (FBX per part + sidecar JSON), then
    `bpy.ops.wm.save_mainfile()`.

Adapting to the other roster cars (hints, nothing here is Pulse-specific except the numbers):
* **sedan / GT / muscle**: same loft, trunk instead of hatch (flat `zt` run + a rear window between two `line_keys`); a 4-door
  needs two extra side windows (more `planes` pairs in `windows`); long hood -> move `x_ws_base` forward; muscle haunches via
  `hwm` bumps over the rear wheels, hood scoop = `surface_sweep` with a large `rib_profile`.
* **supercar / coupe**: low `zt`, tiny `ze` offset, cab-forward `x_ws_base`; side intakes with `pocket_cutter` + `grille_mesh`; big
  `build_wing(...)`; set `ring_density=2.5` for the nose.
* **rally / SUV / pickup**: raise `zf` and the wheel centres, `build_wheel(style='steel')`, flares via `arch_moulding(width=0.09)`;
  the pickup bed = hollow box (`prim_box` minus a smaller `prim_box` through `bm_boolean`), roof rack/bull bar = `prim_tube`.
* **roadster**: skip roof/screen windows (no `ws_pred`), only a short windscreen via `extract_glass`; open tub interior.
* **traffic**: `ring_density=0.8`, `build_wheel(segments=32, tread=False, caliper=False)`, drop pockets and mouldings.

---------------------------------------------------------------------------------------------------------------------------
## 3. API reference

Signatures are exactly those of `carkit.py` (defaults shown). "bm" = bmesh. Units metres, angles degrees unless stated.

### 3.1 Materials (`BLENDER_CONTRACT.md` section 4)
| function | purpose |
|---|---|
| `STANDARD_MATERIALS` / `MAT_ORDER` / `mi(name)` | table of all 22 contract materials with PBR values; global slot order; name -> slot index |
| `ensure_material(name, base_color, metallic=0.0, roughness=0.5, emissive=None, alpha=None, coat=0.0, coat_roughness=0.03, transmission=0.0, ior=1.45, emissive_strength=1.0, specular=0.5, double_sided=False)` | create-or-update a Principled material (idempotent); `alpha < 1` -> blended transparency; also sets the viewport colour |
| `build_standard_materials(paint=None, paint2=None)` | creates/updates the whole set: `M_Paint` (glossy red, clearcoat) `M_Paint2` (satin black) `M_Chrome` `M_TrimBlack` `M_TrimGrey` `M_Rubber` `M_Glass` (dark, alpha 0.3) `M_Headlight` (smoky clear lens, alpha 0.22) `M_Taillight` (deep red lens, alpha 0.78 so the LED bars behind it show) `M_Reverse` `M_Indicator` `M_Tyre` `M_Rim` `M_RimDark` `M_BrakeDisc` `M_Caliper` `M_Plate` `M_Underbody` `M_IntDash` `M_IntSeat` `M_IntTrim` `M_IntCarpet` `M_Exhaust`. Alpha is a Blender preview hint only - in UE these slots are opaque emissive masters (Nanite). Only `<id>_Glass` may use the translucent `M_Glass` slot (validator error otherwise). **Rev 3: the lamp slots `M_Headlight M_Taillight M_Reverse M_Indicator` (`LAMP_SLOTS`) are `<id>_Body` only** - UE maps them to emissive lamp instances (reverse light, indicators, brake), so a dash / seat / steering wheel using them would flash with the lamps (validator error); dial ticks / needles / screen bars use `M_Chrome` / `M_IntTrim`. |

### 3.2 Math and curves
`clamp, lerp, smoothstep(e0,e1,x)`, `T(loc=(0,0,0), rot=(0,0,0), scale=(1,1,1))` (4x4, rot in degrees),
`Curve1D(pts, mode='pchip'|'linear'|'smooth')`, `as_curve(v)` (number | key list | callable -> callable),
`line_keys(p0, p1, n=3)` (collinear interior keys = straight run), `station_list(x0, x1, dx=0.06, end_dx=0.025, end_len=0.25,
extra=(), min_gap=0.012)`, `catmull_chain(ctrl, samples, alpha=0.5, ...)` (centripetal Catmull-Rom).
Designed-curve helpers (rev 2): `smooth_keys(keys, sigma=0.12, step=0.02, mode='pchip')` -> dense key list of the Gaussian-smoothed
curve (feed to `as_curve`; sigma ~ corner radius), `fillet_profile(pts, radii, step=0.01)` -> dense key list of a polyline with a
circular fillet of radius `radii[i]` at every interior vertex (straight runs stay exactly straight),
`end_round_stations(x_end, r, n=6, at_start=False)` -> extra station positions that sample a loft end rounding (pass them to
`station_list(extra=...)` together with `min_gap=0.007`).

### 3.3 Scene helpers
| function | purpose |
|---|---|
| `project_dir()` | folder of the master .blend |
| `ensure_collection('FORZA_UE/Cars/<id>')` | nested collections under the scene collection |
| `remove_asset(asset_id)` | deletes objects/meshes/collection whose names start with the id (and `UCX_<id>`); touches nothing else |
| `make_empty(name, collection, parent=None, location=(0,0,0), display='PLAIN_AXES', size=0.1)` | anchor/root empties |
| `finish_object(name, bm, collection, parent=None, location=(0,0,0), smooth_angle=38.0, free=True, keep_tags=False, clean=True, triangulate_ngons=True)` | bm -> object: dissolves degenerates/loose edges, triangulates n-gons (beauty), heals boolean sliver sheets (`heal_nonmanifold`, rev 3), compresses material slots, smooth shading by angle, removes the kit's tag attributes, identity parent inverse |
| `heal_nonmanifold(bm, max_area=1e-4, passes=4)` | (rev 3) a pocket corner that only grazes the skin leaves coincident sliver triangles with > 2 faces per edge: keeps the two largest faces of every such edge, deletes the others when smaller than `max_area` (m^2). Returns the number of deleted faces |
| `set_root_props(root, **props)` | custom properties of the root (`wheelbase, track_front, track_rear, wheel_radius_front/rear, wheel_width_front/rear, ride_height, length, width, height` are required by the validator) |
| `bm_append(dst, src, matrix=None, mat=None, flip=False)`, `Part(name)` | merge geometry (keeps material indices unless `mat` is given) |
| `log(*a)`, `tri_count(bm_or_mesh)`, `bm_bounds(bm)`, `recalc(bm)`, `is_manifold(bm)` | small utilities |

### 3.4 Primitives (all return a NEW bmesh; `mat` = standard material name)
`prim_box(size, center, mat, bevel=0, segments=2, rot)` (rounded/bevelled box), `prim_cylinder(radius, depth, segments, axis,
center, mat, radius2, caps, rot, bevel)`, `prim_sphere(radius, u, v, scale, center, mat, rot)`, `prim_torus(R, r, seg_major,
seg_minor, axis, center, mat, rz, arc)`, `prim_revolve(profile, segments, axis, center, mat, closed, angle)`,
`prim_prism(outline, depth, plane='XZ'|'XY'|'YZ', center, mat, scale_back)` (extruded 2-D outline),
`prim_tube(path, radius, sides, mat, caps, up, closed)` (sweep a circle/ellipse along a polyline), `ring_loft(rings, closed,
caps, mat)`, `outline_rrect(w, h, r, n)`, `outline_ellipse(a, b, n)`, `outline_superellipse(a, b, p, n)`,
`mirror_y(bm)` (union with mirror), `mirrored_copy(bm, flip=True)`, `shade_by_angle(bm, angle_deg)`,
`bevel_hard_edges(bm, angle_deg=55, width=0.004, segments=2, edge_filter=None)`, `outline_rounded_poly(pts, r=0.01, n=3)` (rev 3: fillet every corner of a convex / mildly concave polygon, `r` may be a list per vertex), `densify_outline(pts, step=0.015)` (rev 3: subdivide the edges of a closed outline - a pocket / sweep projected on a curved skin only touches the skin at its outline points, so a long straight edge across a convex crest leaves a sliver of uncut skin inside the opening).

### 3.5 Body loft
```
loft_body(curves, xs, spans=None, caps=True, alpha=0.5, smooth_passes=2, smooth_strength=0.6, cap_rings=3, cap_bulge=0.025, ring_density=1.0, round_x0=0.0, round_x1=0.0) -> Shell
```
* Cross-section = half ring (y >= 0, mirrored) = centripetal Catmull-Rom through these control points, bottom centre -> top
  centre: `floor_c, floor_e, sill, wide, [char_lo, char_up,] belt_lo, belt_up, edge, rail, crown, top_c` (`DEFAULT_RING_SPANS`,
  `EXT_RING_SPANS` when the curve `zc` exists, samples per span x `ring_density`). Flat floor, tumblehome (`wide` -> `belt` -> `edge`),
  camber of the roof/hood (`edge`, `rail`, `crown`, `top_c` lie on a parabola), crease at the belt, optional shoulder line.
* Curves (name -> number | key list | callable of x): required `zf` floor z, `zt` top-centre z, `hwm` max half width, `zw` height of
  the max width, `zb` belt z, `hwe` half width of roof edge / hood edge. Optional: `hwb` (belt half width), `ze` (edge z),
  `hwf`, `hws`, `zs` (sill), `crease`, `belt_step`, `rail_w`, `zc` + `cdepth` (shoulder line height / how far the surface above
  steps in) + `cwidth` (rev 3, default 0.04: half height of the crease transition, smaller = crisper). `ring_controls(cv, x)` evaluates one
  station; values that would fold the ring are squashed automatically. Every curve may be a callable (e.g. `belt_step=lambda x: ...`).
* End caps are `cap_rings` shrinking domed rings (`cap_bulge` m) -> well tessellated, smooth fascia; row smoothing removes key-point
  wiggles (cowl/hood transitions get a natural radius).
* `round_x0` / `round_x1` (m, default 0 = rev-1 behaviour): quarter-circle edge rounding of radius r at the first (smallest x) /
  last station. The rings of the last r metres shrink inwards by `r - sqrt(r^2 - t^2)` (anisotropic outline-offset approximation),
  so the side/top/bottom surfaces meet the (domed) end fascia tangentially instead of in a 30-60 degree crease - this is what
  removes the "pinched tail corner". Rows inside the rounding are excluded from the Laplacian smoothing. Add
  `end_round_stations()` to the station list so the arc is resolved (Pulse: tail `round_x0=0.09`).
* Quads carry int face attributes `TAG_COL` (= ring column + 1) and `TAG_ST` (= station + 1); they survive `bisect` and the
  Boolean (cutter faces get 0). `shell_quad_cols(shell, a_name, b_name, side=+1, frac=None)` returns the tag values of a span
  (`frac=(lo, hi)` = part of it), `shell_col(shell, name, side)`, `face_tags(bm)`.
* `Shell` fields: `.bm`, `.xs`, `.rows[r][j]`, `.N`, `.H`, `.half_idx`, `.cv`, `.pos` (coordinates, survive the boolean),
  `.ref` + `.ref_bvh` (private smooth copy for `apply_shell_normals`; free with `shell.ref.free()` when done).
* `apply_shell_normals(ob, shell, tol=0.0015)` - custom corner normals from the shell for every face lying on it (Data-Transfer
  equivalent). **Do it after `finish_object` and before/after UV (UV unwrap keeps them).**
* `mark_shell_creases(shell, names, crease=1.0, bevel=1.0)` - subdivision-ready: writes `crease_edge` / `bevel_weight_edge` along
  the named ring columns (call before the boolean if you want to feed the shell to Subsurf/Bevel).
* `shell_skin(shell, name_a, name_b, x0, x1, offset=0.03, side=+1, mat, wrap=False)` - surface offset inwards from a shell region
  (door cards, quarter trims, headliner: `name_a='edge', wrap=True`).

### 3.6 Booleans and surface projection tools
| function | purpose |
|---|---|
| `bm_boolean(target, cutters, operation='DIFFERENCE', solver='MANIFOLD', free_inputs=True)` | boolean through the modifier evaluated via the depsgraph (no operators, no selection). Gives temp meshes all material slots (else the solver clamps indices to 0) and keeps face attributes. Inputs must be closed |
| `Surface(bm)` | ray-cast wrapper: `.hit(p, ray)` -> `(location, outward normal)`, `.dir_at(p, ray)`, `.closest(p)` |
| `groove_profile(width=0.006, depth=0.008, lift=0.03)`, `rib_profile(width=0.03, height=0.012, sink=0.012, round_=0.004)` | profiles `(lateral, along_normal)` for cutter grooves / raised strips |
| `surface_sweep(surf, pts, ray, profile, closed=False, caps=True, mat=None)` | sweep a profile along a polyline projected on the skin: shut lines (cutters), mouldings, skirts, light bars, wiper blades |
| `pocket_cutter(surf, outline, center, ray, depth=0.05, lift=0.03, taper=1.0, mat, axes=None, floor_follows=True)` | closed solid whose top follows the skin and whose floor is `depth` below (lamp / grille / plate / vent pockets) |
| `surface_patch(surf, outline, center, ray, offset=0.004, rings=3, mat=None, axes=None, scale=1.0, bulge=0.0)` | open patch of the skin inside an outline (lens, badge, indicator segment); `bulge` domes it outwards by up to that many metres in the middle |
| `anchor_frame(surf, p, ray, sink=0.0, up)` | 4x4 at the hit point, +X = surface normal: seat inserts that were modelled facing +X (plates, grilles, fins) |
| `poly_pts(xz_pts, y=0, subdiv=0)`, `arc_pts(cx, cz, r, a0, a1, n, y)`, `circle_pts(cx, cz, r, n, y, axis)`, `resample_poly(pts, step)` | path helpers |
| `wheel_arch_cutter(x, z, radius, side, inner_y=0.30, outer_y=1.3, segments=56, mat, stretch_up=1.0)`, `carve_wheel_arches(bm, wheels, pad=0.045, ...)`, `bevel_circle_edges(...)` | arches |

### 3.7 Glass / greenhouse
`extract_glass(bm, windows, offset=0.012, glass_mat='M_Glass', reveal_mat='M_TrimBlack') -> glass bm`.
`windows` = list of `dict(name, pred=callable(face)->bool, zone=callable (optional), planes=[(point, normal), ...])`. The shell is
bisected exactly along `planes` (inside `zone`) so pillar edges are straight; faces accepted by `pred` become a separate sheet pushed
`offset` along the vertex normals, the body gets a black reveal strip between the window edge and the glass, no gaps.
`inner_trim_from_faces(bm, pred, offset=0.03, mat='M_IntTrim')` - inward copies (flipped) of body faces: roof lining, pillar trims.

### 3.8 Details (left side; mirror with `mirrored_copy`)
| function | returns |
|---|---|
| `build_headlight(surf, center, ray, axes, length=0.225, height=0.048, rot=0.17, depth=0.06, scale=0.97, n=48, rings=7, floor_mat, projector=True, drl=True, indicator=True)` | `(cutter, [inserts])` - slim lens following the skin, black housing, projector rings, DRL bar, indicator |
| `build_taillight(surf, center, ray, axes, length=0.195, height=0.075, rot=-0.12, depth=0.034, n=48, rings=7, ..., segmented=True, rib=0.0065, bulge=0.003, lens_inset=0.0045, bezel=True)` | `(cutter, [inserts])` (rev 2): recessed housing (`depth` m, black walls, `M_TrimGrey` reflector floor) with a clean rotated superellipse outline, a raised black bezel strip on the cut edge, a lens split by thin ribs into a big red brake/tail segment (`M_Taillight`, ~65 %) and two lower windows - amber indicator (outer, +U) and white reverse (inner, -U) - every segment domed by `bulge` and `lens_inset` below the skin; behind the lens 3 emissive LED bars + a chrome separator. `segmented=False` = the old single flat lens |
| `build_headlight_blade(surf, center, ray, axes, length=0.27, height=0.078, depth=0.06, scale=0.97, rings=7, corner=0.011, floor_mat, lens_mat, drl=True, indicator=True, lift=0.16, taper=1.0)` | (rev 3) angular "blade" headlight, same `(cutter, [inserts])` contract as `build_headlight`: convex outline `headlight_blade_outline()` (tall squared inner end, top edge sweeping up to a pointed outer tip, +U = inner end), densified, black bezel strip, lens with two projector eyes (`M_Rim` ring - mirror `M_Chrome` turned lime green in the preview HDRI), black eyelid band along the top edge with a white DRL bar (`M_Reverse`) just below it, amber indicator strip. Use a radial ray from a point inside the nose corner; `lift` 0.16 + `taper` 1.0 give straight walls whose opening equals the outline even across a convex corner |
| `build_roof_spoiler(surf, x_lead, chord=0.17, half_span=0.60, thick=0.038, lip_h=0.026, mat='M_Paint2', plates=True, brake_strip=True, plan_taper=0.34, brake_w=0.50)` | hatchback roof-edge spoiler: wedge/aerofoil section whose leading edge is seated on the roof (follows the camber across the span by ray casts on the uncut skin), kicks up by `thick` and ends in a `lip_h` lip over the rear glass, rounded plan ends, end plates running down to the glass/roof skin (no gap, no floating), inset `M_Taillight` third brake light on the lip. Returns bmesh |
| `clip_poly(poly, a, b, c)`, `poly_centroid(poly)` | convex polygon clipping with the half plane `a*x+b*y+c >= 0`, area centroid (lens segmentation) |
| `lamp_unit(surf, center, ray, outline, depth, lens_inset, lens_scale, axes, lens_mat, housing_mat, floor_mat, taper, lift, rings)` | generic `(cutter, lens)` (fog lamps, anything) |
| `plate_recess(surf, center, ray, width=0.54, height=0.125, depth=0.02, sink=0.011)` | `(cutter, plate)` |
| `build_diffuser(surf, center, ray, width=0.92, height=0.088, fins=5, ...)` | `(cutter, [fins])` |
| `build_splitter(surf, ray_front, z=0.215, y_max=0.66, ...)` | flat lip, left half, ends fade out flush with the bumper |
| `arch_moulding(surf, cx, cz, radius, ray, a0=12, a1=168, ...)`, `door_handle(surf, x, z, ray, ...)` | strips that hug the skin |
| `grille_mesh(outline, kind='hex'|'bars'|'grid', pitch, bar, depth, frame, ...)` | insert in the YZ plane facing +X (place with `anchor_frame`) |
| `build_mirror(side, length, width, height, mat_shell, mat_glass='M_TrimBlack', mat_arm, arm_len, repeater, mat_rim='M_Chrome')` | door mirror in its own frame (origin = attachment point), rev 3: lofted rounded-rectangle cap with a flat rear face, body-colour upper shell + black lower shell, flat dark glass in a thin chrome rim, sturdy arm + base block, amber repeater |
| `build_exhaust_tip(radius, length, lip, ...)`, `build_wing(span, chord, thick, ..., endplate, stands)`, `build_lip_spoiler(outline_xz, span, droop, fins)`, `build_wiper(pivot, tip)`, `build_shark_fin(...)`, `build_plate(w, h)` | misc parts |

### 3.9 Wheel
`build_wheel(name='wheel', radius=0.32, width=0.215, rim_radius=0.2286, rim_width=0.185, spokes=5, style='multi', brake_disc_radius=0.155,
caliper=True, side=+1, segments=80, bulge=1.0, hub_radius=0.058, lugs=5, caliper_angle=35.0, dish=0.04, tread=True, ...,
tyre_segments=None, tread_sipes=False)`
- one bmesh (`M_Tyre M_Rim M_RimDark M_BrakeDisc M_Caliper M_Chrome M_Underbody`), axle = local Y through the origin, outer face
+Y for `side=+1`, mirror-built copy for `side=-1`. Rev 2: `'multi'` = 5 twin-spoke pairs (10 slender chamfered concave spokes
that melt into a rim face ring) + polished chrome lip torus + hub plate with 5 steel hex lug nuts + centre cap; slotted brake
disc; body-shaped caliper (outboard/inboard body, bridge, piston rings, bolts, bleed nipple; its outer face never touches the
spokes). Tyre: bead, 2 embossed sidewall rings, rounded shoulder, 4 symmetric circumferential grooves (`tread_sipes=True` adds
slanted lateral notches - only sensible with `tyre_segments >= 120`, off by default because at 72 segments they look lumpy);
`tyre_segments` overrides `segments` for the tyre only. Pulse: `segments=64, tyre_segments=72` -> ~15.4 k tris per wheel
(`segments=80/96` ~19 k). Other styles: `'star'` (single bevelled spokes), `'steel'`, `'wire'`.


### 3.10 Interior
`build_interior(shell=None, spec=None)` - carpet floor, tunnel/console, 2 sport seats + rear bench, dash with binnacle/screen/vents,
pedals, shifter, column, rear-view mirror, door cards / quarter trims (from the shell), optional headliner. `spec` keys:
`floor_z, front_x, driver_y, rear_x, rear_width, dash_x_back, dash_z_top, hw, x_front_floor, x_rear_floor, door_x, quarter_x, roof_x,
seats_rear, rear_z, front_z, back_h, sport, headliner`.
Parts: `build_seat(width, sport, headrest, ..., bench)`, `build_dash(...)`, `build_console(...)`, `build_pedals(...)`,
`build_shifter(...)`, `build_steering_wheel(rim_radius=0.185, tube, tilt=24, flat_bottom, spokes, ...) -> (bm, axis)` (hub at the
origin, tilt baked into the vertices, `axis` = rim normal -> store it in `ob['rim_axis']`, the exporter writes it to the JSON).
The interior is **opaque only** (rev 2) and **free of lamp slots** (rev 3): dial faces / screens are `M_TrimBlack` with `M_Chrome` ticks and
needles and `M_IntTrim` UI bars (no `M_Glass`, so the Interior mesh stays Nanite-eligible; no `M_Reverse` / `M_Indicator`, so the dash does not
flash with the lamps in UE). Rev 3 defaults: seat centre panels `M_TrimGrey` (was light beige `M_IntTrim` = flat "paper" rectangles), dash vents
`M_TrimGrey`, steering-wheel cap / 12 o'clock mark `M_TrimGrey` (mirror chrome reflects the green ground of the preview HDRI).

### 3.11 Collision and UV
* `hull_points_from_shell(shell, x_list, names, z_clip=(None,None), shrink=0.0)` - points from ring control points at the given
  stations; `hull_bmesh(points)` convex hull (triangulated, exactly convex); `make_ucx_hulls(car_id, hulls, collection, parent,
  max_verts=32)` -> `UCX_<id>_Body_NN`. Keep each hull <= 32 verts (4 stations x 4 ring names x 2 sides).
  The Pulse hides them with `hide_set(True)` (they are wire-displayed and would poke through the body in QA renders);
  `export_car` un-hides them while exporting and restores the state.
* `uv_unwrap(ob, angle=66, margin=0.004, layer_name='UVMap')` (alias `uv_unwrap_body`) smart project + pack (restores selection),
  `uv_overlap_ratio(mesh, res=512)` pixel-coverage overlap estimate (validator limit 2 %).
* `uv_livery_layer(ob, layer_name='UVLivery', margin=0.006)` - second UV channel for stripes / liveries / decals: the whole mesh is
  box-projected on 5 large planar islands (top, left, right, front, rear; seen from outside, ~0.17 uv/m, all inside 0..1), so a
  stripe over the roof or hood is one straight band in the texture. Call it AFTER `uv_unwrap` (which rebuilds the UV layers);
  `UVMap` stays the first channel. Overlap inside one plane is by design (never bake lighting into it).

### 3.12 Validate and export
* `validate_car(root_name, targets=None, verbose=True) -> dict(ok, errors, warnings, stats)` checks: required parts/empties/root
  properties, parent + identity transforms, no modifiers, loose geometry, non-manifold (> 2 faces) edges, inverted closed islands,
  degenerate faces, material slot names vs the contract (+ `M_Glass` only allowed in `<id>_Glass`), `UVMap` present + overlap + inside 0..1, wheel pivots at the axle centre
  and tyres touching z = 0, origins of Body/Glass/Interior, UCX count 2-6 / <= 32 verts / convex, triangle budget 60-150 k,
  dimensions vs `targets`, rev 3: lamp slots (`LAMP_SLOTS`) outside `<id>_Body` are an error. Open boundary edges of the body (window reveals, lens patches, liners) are reported as a warning only.
* `export_car(root_name, out_dir=None, display_name=None)` -> `{part: (path, bytes)}`: per-part FBX through `fbx_export.export_fbx`
  (Body + UCX centred on the root; steering wheel and wheels centred on their own origin) and the sidecar
  `Exports/Cars/<id>/<id>.json`:
  `id, display_name, units, dimensions{length,width,height,width_with_mirrors}, wheelbase, track_front, track_rear, ride_height,
  wheels{FL,FR,RL,RR:{center,radius,width}}, steering_wheel{center,axis}, cameras{hood,cockpit,bumper},
  lights{head_l,head_r,tail_l,tail_r,reverse}, exhaust[[l],[r]] (+ exhaust_l / exhaust_r), material_slots{part:[names]},
  tri_counts{part, UCX, total_visual}, ucx[names], files{part: filename}` - everything is read from the scene (wheel centres and
  radii from the meshes, empties from their locations, triangle counts from the meshes). All positions are Blender car-space metres.

### 3.13 QA helper
`qa_studio(car_id, on=True, center=None, power=1.0)` (rev 3: only removes LIGHT objects named `<car_id>_QA_*`; name any other QA helper object differently, e.g. `<car_id>_QAfocus`) - five temporary area lights named `<car_id>_QA_*` so that
`look(shading='rendered')` is lit (the shared scene world is black; metals still look grey in `rendered`, judge them with
`shading='material'`). Always remove with `on=False`; `remove_asset` also removes them.

`zebra.py` (`exec` it like the kit): `zebra(obj_names, eye_dir, target, dist, fov, size, out, pattern='h'|'v'|'d'|'c', freq)` casts
camera rays with a BVH against the object's current mesh incl. custom split normals, reflects them and writes a PNG of reflection
stripes (nothing in the scene is touched, ~1 s per image); `zebra_car(root_name, out_dir, views=('rear34','rearclose','side',
'front34','top', ...), freq=6..11)` renders a standard set. Smooth, continuous stripes = good surface; swirls / bullseyes / kinks =
fix the curves. `sectionplot.py`: `plot_lines([(pts, rgb), ...], bounds, size, out)` plots side profiles (`as_curve` samples) or
ring cross sections (`shell.rows[r][j].co`) to a PNG.

---------------------------------------------------------------------------------------------------------------------------
## 4. Lessons learned (read before debugging)
* `bmesh.ops.bevel` defaults to **material index 0** for the new faces (= `M_Paint`, red!) -> always `material=-1` (the kit does).
* The Boolean modifier **clamps material indices to the slot count of the temp meshes** -> `bm_boolean` gives its temp meshes all
  22 slots. Cutter faces keep their own material (use `M_TrimBlack` / `M_Underbody` for pocket walls and grooves).
* `bisect_plane` keeps custom face attributes; the Boolean propagates them but gives cutter faces 0 (use tag 0 to recognise them).
* Boolean results contain fans of thin triangles around cuts -> never trust their vertex normals: `apply_shell_normals`.
* Face-centroid tests make stair-stepped material borders; use ring columns (`shell_quad_cols`) for clean edge loops.
* Wire-displayed UCX objects show up as thin black lines in solid renders - hide them for QA.
* `look` with a tiny target (an empty) and a small `distance` (0.8-1.3) is the way to close-ups; the cockpit view is
  `target=[<id>_SteeringWheel]`, `views=[[-1,0,0.18]]`, `distance=0.75`.
* A single-sided body face is invisible from inside in the engine: roof lining, pillars, door cards and the tailgate lining are part of
  `<id>_Interior` (generated from the body faces / shell).
* Parallel projection of lamps across a tight corner stretches/shards the lens -> use `('radial', C)` rays.
* Keep each Blender call < 20 s: UV unwrap in two calls; booleans/loft/projections are all < 1 s.
* The MCP namespace is not persistent: re-`exec` the kit in every call; never rely on selection/active object (the kit restores them).
* (rev 2) Hand-keyed pchip curves with many keys are the source of wavy reflections: design the profile (fillet polyline +
  `smooth_keys`) and check it with `zebra_car` / `plot_lines`; a hard-edged end cap (30-60 degree crease between the side and the
  dome) shades as a pinched corner -> use `round_x0`.
* (rev 2) Collapsed ring points at the tail deck (belt / edge / rail / crown within 4 cm in z) create a bullseye on the C-pillar:
  let the belt `zb` fall towards the tail so the shoulder becomes a rounded rectangle.
* (rev 2) A boolean cut edge across a coarse loft is ragged in close-ups: cover it with a raised `surface_sweep` bezel (see
  `build_taillight(bezel=True)`).
* (rev 2) Freshly created objects have stale `matrix_world` until `bpy.context.view_layer.update()` (the zebra tool calls it).
* (rev 2) Material boundaries on the domed caps: bisect the shell at the plane first (`bmesh.ops.bisect_plane` keeps the TAG
  attributes), then colour by centroid - otherwise the paint / valance edge is stair-stepped.
* (rev 3) `look` with a tiny target (an empty, a 2 cm cube) clips the car away (the viewport near clip scales with the target size): use a 0.3-0.8 m
  QA cube (`Tools/blender/qa/car01_focus.py`) and `distance` 1.0-2.4 for close-ups.
* (rev 3) Pocket cutter across a convex corner (headlight wrapping the nose): the top ring only touches the skin at the outline points, so a long
  straight outline edge leaves a red sliver of skin inside the opening. Fix = `densify_outline` (16 mm), `lift` 0.16 (cap far outside the crest) and
  `taper=1.0` (a tapered floor shrinks the opening at the skin: the bezel then sits outside the hole).
* (rev 3) Boolean cutters that only graze the skin leave coincident sliver triangles (> 2 faces per edge, validator error): `heal_nonmanifold` (called
  by `finish_object`).
* (rev 3) Belt line: do NOT raise it into the tail deck - a flank band that tapers to zero height at the glass base ends in a pointed black / red
  spike and a bullseye in the zebra; let the belt fall 5-8 cm over the last 0.3 m so the pillar ends on a blunt base on a falling shoulder line.
* (rev 3) Colour zones of a floating-roof car: pillar zone = whole `belt_up -> edge` band, A-pillar glass line parallel to the windscreen edge
  (constant width), C-pillar down to the glass base line; colour stops at the glass base, not at a magic x.
* (rev 3) Mirror: a bevelled-box cap is a pill without a flat face, a rectangular glass plate then pokes out of the outline - loft rounded-rect rings
  (`build_mirror`) so the rear face is flat and the plate fits inside it.
* (rev 3) Tyre clearance check: rotate the tyre vertices about the vertical axis through the wheel centre (+-30 degrees) and `BVHTree.find_nearest`
  against the body (Pulse: >= 4.9 cm everywhere with `ARCH_PAD = 0.052`, splitter ends at y = 0.56 m).
* Shared live session: only create/delete objects that start with the car id; `M_*` materials are created through
  `ensure_material` (idempotent). QA lights/objects must be named `<car_id>_QA_*` and removed.

---------------------------------------------------------------------------------------------------------------------------
## 5. The worked example: `car01_hatch_pulse`
* 3.95 x 1.78 x 1.44 target; built (rev 3) 3.949 x 1.801 x 1.423 (spoiler included; fenders + 18 mm flare strips; mirrors 1.93 m wide), wheelbase
  2.52, track 1.52 / 1.50, wheels 0.33 m radius (205/55 R17), 0.216 m wide, ride height 0.14. Windscreen ~30 deg, hatch glass ~52 deg, roof kicked
  down towards the tail (1.434 m peak at x = -0.25 -> 1.27 m at the glass), belt line 1.004 m at the quarter that then FALLS to 0.918 m at the tail
  lamps, roof-edge spoiler, tail rounded r = 0.09 m, nose rounded r = 0.07 m (flat upright fascia, cap bulge 0.02), 5.2 cm arch clearance (top
  elliptical x 1.04) + 5 cm black flare strips, haunch flares (+2.5 cm over both wheels), shoulder crease 5.4 cm deep (cwidth 0.032).
* Rev 3 colour / panel layout: black roof + A / B / C pillars as one graphic (C-pillar down to the glass base line x = -1.80), A-pillar a constant-width
  band parallel to the windscreen edge (glass front corner at x = 0.78), hood shut line from the `edge` ring column wrapped round a quarter ellipse
  at the nose, door front edge x = 0.745 at the belt, complete tailgate perimeter (roof cut ahead of the spoiler, side cuts along the glass frame,
  over the deck corner, down the tail face above and below the lamp, lower edge under the plate), clean tangent-plane rounded-rectangle fuel flap.
* Loft: 105 stations x 132 ring columns (~15.0 k quads), 33 cutters in one boolean, 4 windows (reveal edges rounded), 8 FBX parts + 3 UCX hulls.
* Triangles (LOD0): Body 59 084, Glass 2 894, Interior 17 792, SteeringWheel 1 784, 4 wheels 15 352 each, total 142 962 (budget 60-150 k),
  UCX 142.
* Materials per part: Body 13 slots (lamp slots allowed here only), Glass 1, Interior 8 (opaque, no lamp slots), SteeringWheel 2, wheel 7 (all names
  from the contract).
* UV: `UVMap` (smart project, non-overlapping) + `UVLivery` (body only).
* Re-run time: geometry 2-8 s, uv1 ~8 s, uv2 ~6 s, uv3 ~7 s, validate ~15-25 s (call it separately), export ~2 s.
* Checks used for rev 3: tyre clearance >= 4.9 cm at +-30 deg steer (`BVHTree.find_nearest`), `zebra_car` (front34, rearclose, side, flank close-ups),
  `look` close-ups with `Tools/blender/qa/car01_focus.py`, `validate_car` OK.
