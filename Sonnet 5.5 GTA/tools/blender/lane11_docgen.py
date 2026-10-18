r"""lane11_docgen.py - writes docs/api/blender_vehicle_parts.md and gta/generated/models/vehicle_parts/parts_catalog.json from
lane11_catalog.py + lane11_vehicles.py + lane11_stats.json (pure Python 3, no bpy):
    python tools\blender\lane11_docgen.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ns = {}
for f in ("lane11_catalog.py", "lane11_vehicles.py"):
    exec(open(os.path.join(HERE, f), encoding="utf8").read(), ns)
ST = json.load(open(os.path.join(HERE, "lane11_stats.json"), encoding="utf8"))
ORDER, MOUNT, VEH, INFO, WINFO = ns["L11_ORDER"], ns["L11_MOUNT"], ns["L11_VEHICLES"], ns["L11_INFO"], ns["L11_WHEEL_INFO"]
fit_for, wheel_scale, NOTES = ns["l11_fit_for"], ns["l11_wheel_scale"], ns["L11_VEHICLE_NOTES"]
PARTS = [p for p in ORDER if not p.startswith("wheel_")]
WHEELS = [p for p in ORDER if p.startswith("wheel_")]


def g(p):          # Blender (x, y, z) -> Godot (x, z, -y)
    return [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]


def gs(s):         # Blender scale (sx, sy, sz) -> Godot (sx, sz, sy)
    return [round(s[0], 3), round(s[2], 3), round(s[1], 3)]


def f3(t):
    return "(" + ", ".join(("%.3f" % v).rstrip("0").rstrip(".") if abs(v) > 1e-9 else "0" for v in t) + ")"


# ------------------------------------------------------------------------------------------------ json
cat = dict(version=1, units="metres", frame_blender="+X right, +Y forward, +Z up (origin = ground at wheelbase centre)",
           frame_godot="X right, Y up, -Z forward: pos = (x, z, -y), pitch about X unchanged, scale = (sx, sz, sy)",
           glb_dir="res://gta/generated/models/vehicle_parts/", parts={}, wheels={}, vehicles={})
for pid in PARTS:
    m, st, inf = MOUNT[pid], ST[pid], INFO[pid]
    cat["parts"][pid] = dict(group=inf["group"], origin=inf["origin"], use=inf["use"], tris=st["tris"], size_blender=st["size"],
                             min_blender=st["min"], max_blender=st["max"], materials=st["materials"], nodes=st["nodes"],
                             sedan=dict(pos_blender=list(m["pos"]), pos_godot=g(m["pos"]), pitch_deg=m["pitch"], scale_blender=[1, 1, 1], scale_godot=[1, 1, 1], note=m["note"]))
for pid in WHEELS:
    st = ST[pid]
    cat["wheels"][pid] = dict(use=WINFO[pid], tris=st["tris"], size_blender=st["size"], materials=st["materials"], nodes=st["nodes"],
                              radius=0.31 if pid == "wheel_mc_sport" else 0.34, width=0.17 if pid == "wheel_mc_sport" else 0.24)
for vid, V in VEH.items():
    fit = fit_for(vid)
    cat["vehicles"][vid] = dict(anchors={k: (list(v) if isinstance(v, tuple) else v) for k, v in V.items()}, note=NOTES[vid],
                                width_scale=round(V["half_w"] / 0.885, 3), wheel_scale=wheel_scale(vid),
                                fit={pid: dict(pos_blender=list(f["pos"]), pos_godot=g(f["pos"]), pitch_deg=f["pitch"],
                                               scale_blender=list(f["scale"]), scale_godot=gs(f["scale"])) for pid, f in fit.items()})
jp = os.path.join(ROOT, "gta", "generated", "models", "vehicle_parts", "parts_catalog.json")
os.makedirs(os.path.dirname(jp), exist_ok=True)
json.dump(cat, open(jp, "w", encoding="utf8"), indent=1)
print("wrote", jp)

# ------------------------------------------------------------------------------------------------ markdown
L = []
A = L.append
A("# Blender lane 11 - vehicle customisation parts (`models/vehicle_parts/*.glb`)")
A("")
A("30 modular GLBs for the garage / `VehicleBase.apply_mods` visual layer: **20 body parts + 10 wheel styles**, authored in Blender (collection `GTA_GODOT/Vehicles/Parts`, workshop slots lane 11, "
  "rebuilt by `tools/blender/lane11_*.py`, batch = `lane11_build_all.py`). All files: `res://gta/generated/models/vehicle_parts/<id>.glb`; machine-readable twin of this document: "
  "`res://gta/generated/models/vehicle_parts/parts_catalog.json` (parts, sedan mounts, per-vehicle fit transforms in Blender AND Godot axes).")
A("Total 7 494 tris for all 30 files. Probe / contract test: `powershell -NoProfile -File tools\\gd.ps1 script -Script res://gta/tests/vehicle_parts_probe.gd` (loads every GLB, checks nodes + budgets: parts <= 400 tris, wheels <= 500).")
A("")
A("## 1. Conventions (read this first)")
A("- **One part per GLB.** Node `Body` = the part mesh (one mesh, several surfaces = materials), empty `Mount` = the mount point and **also the GLB origin (0,0,0)**. Wheels: nodes `Tire` + `Rim` + `Mount`. A few wings carry an extra empty `Wing`.")
A("- **Part frame = vehicle frame**: Blender +Y forward (becomes Godot **-Z**), +Z up, centred on X, metres, sized for the mid-size **sedan** (1.82 m wide, 4.77 m long, 1.45 m tall). The part ORIGIN is the point where the part touches the car (table in section 3: where z=0 is the panel surface, y=0 the front/rear face ...). "
  "So fitting = `part_node.transform = Transform3D(basis, position)` as a child of the vehicle root; no per-part offsets inside the mesh.")
A("- **Axis conversion** (Blender -> Godot): position `(x, y, z) -> (x, z, -y)`; rotation about X (`pitch`, + = nose up) is identical; **scale `(sx, sy, sz) -> (sx, sz, sy)`** (Blender Y = length becomes Godot Z). Transform order T * R * S (scale in the part's local axes): `Basis(Vector3.RIGHT, deg_to_rad(pitch)).scaled_local(scale_godot)`.")
A("- **Materials (runtime replace-by-name)**: `Paint` (body colour, `Util.replace_material(part, \"Paint\", mat)` or the vehicle's paint material), `Paint2` (secondary; dark default, spoiler blades / stripes / canards), `Trim`, `Chrome`, `Metal`, `MetalDark`, `Glass`, "
  "`LightHead` (fog lamps), `LightTail` (rear fog bar), `LampGlow` (light bar lamps, emissive), `NeonCyan` (underglow, emissive; **recolour by replacing / re-tinting the `NeonCyan` material**, the STD palette also has magenta `Neon`), "
  "`Tire`, `Rim` (wheel rim colour = `Rim` material; `Chrome` lip/hub stay chrome). Same material names as the vehicle GLBs, so one paint override covers car + parts.")
A("- Origin Z of every roof / hood / deck part is the **panel surface**; bases sink 2-4 cm below z=0 on purpose (no gaps on crowned panels). Hard-edged, flat shaded; tyres smooth shaded (40 deg).")
A("- Parts are **static** (no animation). Keep them in the vehicle's body node tree so they follow suspension roll / damage / hide with the car; for LOD simply hide parts beyond ~60 m.")
A("")
A("```gdscript")
A("# example: fit one part on a vehicle (sedan transform from parts_catalog.json)")
A("func fit_part(vehicle: Node3D, id: String, fit: Dictionary) -> Node3D:")
A("    var n := (load(\"res://gta/generated/models/vehicle_parts/%s.glb\" % id) as PackedScene).instantiate() as Node3D")
A("    var s: Array = fit[\"scale_godot\"]; var p: Array = fit[\"pos_godot\"]")
A("    var b := Basis(Vector3.RIGHT, deg_to_rad(float(fit[\"pitch_deg\"]))).scaled_local(Vector3(s[0], s[1], s[2]))")
A("    n.transform = Transform3D(b, Vector3(p[0], p[1], p[2]))")
A("    vehicle.add_child(n)")
A("    return n")
A("```")
A("")
A("## 2. Body parts (20)")
A("| id | tris | size X x Y x Z (m, Blender) | materials | origin / z=0 | what it is |")
A("|---|---|---|---|---|---|")
for pid in PARTS:
    st, inf = ST[pid], INFO[pid]
    A("| `%s` | %d | %.2f x %.2f x %.2f | %s | %s | %s |" % (pid, st["tris"], st["size"][0], st["size"][1], st["size"][2], ", ".join(st["materials"]), inf["origin"], inf["use"]))
A("")
A("Notes: `skirt_side_sport` and `mirror_sport` are **pairs in one mesh** (mirrored across X). `exhaust_tip_dual/quad` are mirrored pairs too (`single` is one tip: place it at x = +0.56 for the sedan's right-hand pipe, or at x = 0 / any x). "
  "`bumper_front_sport` and `bumper_rear_diffuser` can be combined with `splitter_front` / exhaust tips (tips sit outboard of the diffuser). Spoilers are mutually exclusive, so are `hood_scoop_a` / `hood_vents_b` (they overlap).")
A("")
A("## 3. Recommended mount transforms on the SEDAN (`vehicles/sedan.glb`; checked visually in Blender on a linked, read-only copy of the sedan meshes - all 20 parts incl. `exhaust_tip_quad`, which sits outboard of the diffuser)")
A("Blender frame (what `parts_catalog.json` calls `pos_blender`), scale = (1,1,1) for every part on the sedan. `pitch` = rotation about X in degrees (+ nose up, same value in Godot).")
A("| part | pos Blender (x, y, z) | pitch | pos Godot (x, y, z) | note |")
A("|---|---|---|---|---|")
for pid in PARTS:
    m = MOUNT[pid]
    A("| `%s` | %s | %s | %s | %s |" % (pid, f3(m["pos"]), ("%.1f deg" % m["pitch"]) if m["pitch"] else "0", f3(g(m["pos"])), m["note"]))
A("")
A("Wheels on the sedan: place the wheel GLB on each `Wheel_*` node (origin = wheel centre, so **identity position**), scale `(1, 0.971, 0.971)` for the sedan's 0.33 m tyres (see section 5).")
A("A ready-made contact sheet lives in the master .blend: `vpref__root` (sedan wearing the sporty set at these transforms: `spoiler_wing_low`, `bumper_front_sport`, `splitter_front`, `skirt_side_sport`, `bumper_rear_diffuser`, `hood_vents_b`, `mirror_sport`, `exhaust_tip_dual`, `underglow_strip`, `roof_light_bar` + `wheel_turbine`) and `vpsheet__root` (all non-wheel parts in a row), "
  "wheel overview rows at (-20, 1880). Fixtures are QA only and not exported.")
A("")
A("## 4. Fit hints for the other ground vehicles")
A("`parts_catalog.json -> vehicles.<id>.fit.<part>` holds ready transforms (Blender + Godot axes). They come from **ray-cast anchors on the Wave-1 vehicle bodies** (table below) and one formula set; the sedan is the only body I checked visually - for the others treat them as a good first fit and re-tune per vehicle in `VehicleDefs` if something clips. "
  "Width scale `ws = half_width / 0.885` is applied to X for every width-spanning part (spoilers, splitter, bumpers, skirts, light bar, vents, underglow, mirrors).")
A("| vehicle | half width | ws (x scale) | nose y | tail y | bumper z | roof z | roof y span | rear-spoiler anchor (y, z) | hood anchor (y, z, pitch) | wheel scale (1,s,s) |")
A("|---|---|---|---|---|---|---|---|---|---|---|")
for vid, V in VEH.items():
    A("| %s | %.3f | %.3f | %.3f | %.3f | %.2f | %.3f | %.2f .. %.2f | (%.2f, %.3f) | (%.2f, %.3f, %.1f) | %.3f |" % (
        vid, V["half_w"], V["half_w"] / 0.885, V["nose"], V["tail"], V["bump_z"], V["roof_z"], V["roof_y"][0], V["roof_y"][1], V["deck"][0], V["deck"][1],
        V["hood"][0], V["hood"][1], V["hood"][2], wheel_scale(vid)))
A("")
A("Per-vehicle remarks:")
for vid in VEH:
    A("- **%s**: %s" % (vid, NOTES[vid]))
A("")
A("Formulas (Blender frame; `nose`, `tail`, `bz` = bumper z, `(dy, dz)` = deck anchor, `(hy, hz, hp)` = hood anchor, `cy` = roof span centre, `y1` = roof front end):")
A("- spoilers `(0, dy + {-0.13 lip, 0 ducktail, +0.02 wing_low, 0 wing_high}, dz)`, scale `(ws,1,1)`; `splitter_front (0, nose-0.069, bz+0.015)`; `bumper_front_sport (0, nose+0.016, bz)`; `bumper_rear_diffuser (0, tail+0.084, bz)`;")
A("- `hood_scoop_a (0, hy, hz)` pitch `hp`; `hood_vents_b (0, hy+0.20, hz-0.02)` pitch `hp`; `roof_scoop`, `roof_rack (0, cy+0.05, roof_z)`, rack scale `(ws, clamp((roof_len-0.15)/1.04, 0.6, 2.4), 1)`; `roof_light_bar (0, y1-0.15, roof_z)`; `antenna (0.47 ws, roof_y0+0.30, roof_z)`;")
A("- `skirt_side_sport (0, 0, bz-0.07)` scale `(ws, (wheelbase - 2.42 r_wheel)/2.0, 1)` (between the arches); exhausts `(x, tail+0.034, bz-0.008)` (single x = 0.56 ws, dual/quad x = 0 scale `(ws,1,1)`); `underglow_strip (0, (nose+tail)/2, bz-0.095)` scale `(ws, length/4.763, 1)`; `grille_mesh (0, nose-0.024, bz+0.362)`;")
A("- `mirror_sport`: sedan value (0, 0.62, 0.99); on the other cars use `DoorL.position + (0, -0.18, +0.39)` for y,z (x stays 0, scale `(ws,1,1)`), i.e. the A-pillar base next to the front door hinge.")
A("- Bikes / boats / aircraft are not covered (only `wheel_mc_sport` is for motorcycles: scale X for fat rear tyres, e.g. `(1.25, 1, 1)`).")
A("")
A("## 5. Wheel styles (10)")
A("GLB = nodes `Tire` (material `Tire`, smooth shaded) + `Rim` (materials `Rim`, `Chrome`, `MetalDark`/`Trim`/`Metal`) + `Mount`. **Radius 0.34 m, width 0.24 m, spin axis X, origin = wheel centre, tyre bottom at y = -0.34** (same convention as `make_wheel` and the vehicle wheels; `wheel_mc_sport`: radius 0.31, width 0.17). "
  "**Both faces carry the same detail**, so one mesh fits the left and the right side of any car - never flip or mirror it.")
A("| id | tris | size X x Y x Z | style |")
A("|---|---|---|---|")
for pid in WHEELS:
    st = ST[pid]
    A("| `%s` | %d | %.2f x %.2f x %.2f | %s |" % (pid, st["tris"], st["size"][0], st["size"][1], st["size"][2], WINFO[pid]))
A("")
A("How to apply: the vehicle code's `Wheel_FL/FR/RL/RR` nodes are `MeshInstance3D`s that the code spins (X) and steers (Y). Two good options: (a) hide the original mesh (`mesh = null`) and **add the part GLB instance as a child** of each wheel node, with scale `(1, s, s)`, "
  "`s = vehicle_wheel_radius / 0.34` (sedan 0.971, compact 0.882, sports 1.015, muscle 1.029, suv/pickup 1.118, van 1.0 - X stays 1.0, or 0.96..1.2 for a stance/width look); (b) take `Tire`/`Rim` meshes out of the GLB and add two `MeshInstance3D` children. "
  "Rim colour = override the `Rim` material (`rim_color` mod); `Chrome` parts keep their look. The wheel set tri cost is 324..480 per wheel (x4 per car, <= 2 000 per customised car).")
A("")
A("## 6. Gotchas")
A("- Do not rely on mesh bounding boxes for placement: parts are authored around their own mount origin (e.g. `exhaust_*` extends 0.29 m to +Y from the origin, `bumper_front_sport` 0.4 m behind it).")
A("- Overlaps by design: `bumper_front_sport` hides the stock bumper bar/valance (its shell sits 1.6 cm in front of the nose at z 0.5 and ~7 cm at the chin); `grille_mesh` is an overlay in front of the stock grille; `mirror_sport` covers the stock door mirrors; the hood parts and `roof_*` parts are surface decals/solids on top of the body. Hide nothing in the vehicle mesh.")
A("- `underglow_strip` is only the glowing tube. The ground glow itself needs the vehicle code (OmniLight / decal under the car, `NeonCyan` emission energy).")
A("- `LampGlow` (light bar) and `LightHead`/`LightTail` (fog lamps / rear fog bar) are emissive materials by name: switch them with the vehicle's lights like the rest of the car.")
A("- Wheel meshes are 14-segment (as the Wave-1 wheels): `s` scaling of the radius is fine, do NOT scale X by more than ~1.3 (the faces are flat).")
A("- Tri budgets: every body part <= 400 (max 260), every wheel <= 500 (max 480). No UV unwrap / textures (colours by material only).")
A("")
A("## 7. Rebuild")
A("```python")
A("LIB = r\"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\"")
A("exec(open(LIB + r\"\\gta_lib.py\", encoding=\"utf8\").read(), globals()); assert_master()")
A("for f in (\"lane11_common.py\", \"lane11_catalog.py\", \"lane11_spoilers.py\", \"lane11_aero.py\", \"lane11_topside.py\", \"lane11_misc.py\", \"lane11_wheels.py\", \"lane11_fit.py\", \"lane11_build_all.py\"):")
A("    exec(open(LIB + \"\\\\\" + f, encoding=\"utf8\").read(), globals())")
A("l11_build_all(export=True); l11_dump_stats(); l11_showcase(); l11_sheet(); save_master()")
A("```")
A("then `python tools\\blender\\lane11_docgen.py` (regenerates this file and `parts_catalog.json`) and `powershell -NoProfile -File tools\\gd.ps1 import`. Every builder is idempotent (`clear_asset(\"<id>__\")` first); one part = one function (`l11_spoiler_lip()` ... `l11_wheel(...)`).")
A("Source files: `lane11_common.py` (helpers, part context), `lane11_catalog.py` (order, sedan mounts), `lane11_vehicles.py` (anchors, fit formulas, descriptions), `lane11_spoilers.py`, `lane11_aero.py`, `lane11_topside.py`, `lane11_misc.py`, `lane11_wheels.py`, `lane11_fit.py` (QA fixtures), `lane11_build_all.py`, `lane11_docgen.py`.")
A("")
A("## 8. Per-vehicle fit tables (generated)")
for vid in VEH:
    fit = fit_for(vid)
    A("### %s  (ws %.3f, wheel scale %.3f)" % (vid, VEH[vid]["half_w"] / 0.885, wheel_scale(vid)))
    A("| part | pos Blender | pitch | scale Blender | pos Godot | scale Godot |")
    A("|---|---|---|---|---|---|")
    for pid in PARTS:
        f = fit[pid]
        A("| `%s` | %s | %s | %s | %s | %s |" % (pid, f3(f["pos"]), ("%.1f" % f["pitch"]) if f["pitch"] else "0", f3(f["scale"]), f3(g(f["pos"])), f3(gs(f["scale"]))))
    A("")
dp = os.path.join(ROOT, "docs", "api", "blender_vehicle_parts.md")
open(dp, "w", encoding="utf8").write("\n".join(L) + "\n")
print("wrote", dp, len(L), "lines")
