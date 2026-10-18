"""
make_doc_cars_01_02_03.py - generates Docs/Kits/cars_01_02_03.md from the exported JSON sidecars (Exports/Cars/<id>/<id>.json).
Plain Python (no Blender needed):   python Tools/blender/cars/make_doc_cars_01_02_03.py
All numbers in the tables come from the sidecars (= read from the live Blender scene by export_car), so the doc cannot go stale
against the exports; re-run it after every re-export.
"""
import json
import os
import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "Docs", "Kits", "cars_01_02_03.md")

CARS = [
    dict(id="car01_hatch_pulse", index=1, name="Pulse", drivetrain="FWD", mass=1250, power=155, ucx=3,
         ucx_desc="1 lower body (tail to nose), 2 nose / bonnet, 3 cabin",
         wheel_style="'multi' - 5 twin-spoke pairs (10 slim chamfered concave spokes), chrome lip, red calipers, slotted discs, 17\"",
         tyre="205/55 R17 (kit tyre: bead, 2 embossed sidewall rings, 4 circumferential grooves)",
         brief="Compact 3-door hot hatch: short overhangs, floating black roof pack, steep hatch tail with a roof-edge spoiler, angular wrap-around blade headlamps, 17\" alloys, twin exhaust tips.",
         features=[
             "Loft: designed profile (filleted top line; windscreen ~30 deg, hatch glass ~52 deg; roof peak 1.412 m at x = -0.25, kicked down to 1.27 m at the glass), belt line 1.004 m over the rear quarter that falls into the tail lamps, nose = superellipse plan with a flat upright fascia, shoulder crease 5.6 cm deep, 5.2 cm tyre-to-arch clearance with 5 cm black flare strips and haunch flares.",
             "Colour graphic: black roof + A / B / C pillars as ONE floating-roof graphic (`M_Paint2`, C-pillar down to the glass base line), black lower valances (`M_TrimBlack`), wedge-shaped roof-edge spoiler with end plates and an inset third brake light, shark fin, rear wiper lying on the glass.",
             "Panels: one long door per side (3-door), bonnet shut line wrapped round the nose, complete tailgate perimeter (roof, glass frame, deck corner, tail face, lower edge), tangent-plane fuel flap, fender side vents with louvres, chrome belt strip, door handles, body-colour mirrors with chrome-rimmed flat glass.",
             "Front: blade headlamps (projector eyes, DRL bar, indicator), upper bar grille, plate recess, wide trapezoid honeycomb intake, corner intakes with fins, fog lamps, splitter. Rear: clean wrap-around tail lamps (fix round 1), plate recess, diffuser with 5 fins, twin round exhaust tips, plain roundel.",
             "Interior: kit sport seats + 2-seat bench with cargo floor, tailgate lining, flat-bottom 3-spoke wheel (rim 0.18 m), kit dash + binnacle + centre screen, black pillar trims / light roof lining generated from the body faces, red accent band across the dash + red ring round the gear boot (fix round 1).",
         ],
         weaknesses=[
             "The class reads as 'hot hatch' mostly through the black roof pack, spoiler, alloys and wrap lamps; the tall greenhouse and short bonnet still read a little like a compact crossover from some side angles (roof lowered 2.2 cm and tail radius tightened in fix round 1; a lower belt or a longer bonnet would need a new loft).",
             "Interior shares the kit's box-modelled seats and flat dash vents with the other cars; only the accent trim and the flat-bottom wheel are Pulse specific.",
             "Tri count 135.6 k of 150 k: the four wheels are 41 % of it (14.0 k each) - drop `tyre_segments` to 48 if a lighter LOD0 is wanted.",
             "Body UV sheet is ~50 % used (about 1 400 small islands from the smart project); fine for livery (UVLivery) but not a trim-sheet layout.",
             "Mirror stalks are thin boxes, no door seals / window frames on the inner side (glass = single sheet 14 mm inside the skin)."]),
    dict(id="car02_sedan_cadence", index=2, name="Cadence", drivetrain="FWD", mass=1480, power=120, ucx=4,
         ucx_desc="1 rear lower body, 2 mid lower body, 3 nose, 4 cabin",
         wheel_style="'ten' - 10 slim swept spokes, chrome centre cap, 16\"",
         tyre="195/55 R16 (rim flange radius 0.2032 m)",
         brief="Everyday 4-door three-box sedan with a conservative roof line, chrome window trim, upright chrome-framed grille and modest 16\" wheels.",
         features=[
             "Loft: designed profile (filleted top line, straight windscreen / rear glass, flat deck), shoulder crease (`zc` / `cdepth` 7 cm, `cwidth` 3.2 cm) running from the headlamp to the tail lamp, 8.5 cm tumblehome, 3.6 cm arch gaps with rolled lips and black arch mouldings; fix round 1: squarer plan-view corners (fascia half width 0.72 / 0.78 m, end rounding 0.078 m) so the nose and tail are no longer egg shaped.",
             "Four doors (two shut-line groups with a black B-pillar), bonnet shut line with filleted corners, boot lid cuts, fuel flap, chrome door handles, chrome window-surround loops round both side windows, body-colour mirrors, wipers; fix round 1: black body-side rub moulding with a chrome insert along both doors.",
             "Front: upright chrome-slat grille in a chrome frame, wrap headlamps with chrome bezel, plate recess, hex lower intake, round fog lamps, black lower bumper band that ends at the arches. Rear: large wrap-around tail lamps (fix round 1: shallow black pocket, one smooth red lens over amber | white, chrome separator and chrome bezel, no LED sub-structure behind the translucent preview lens), chrome boot strip, plate recess, twin small exhaust tips, plain roundel.",
             "Interior: 2 + 3 plain (non-sport) seats, parcel shelf and bulkhead, roof / pillar lining from the body faces, kit dash with twin dials + centre screen, 3-spoke round wheel (rim 0.19 m), cream trim band framed by two chrome lines across the dash (fix round 1).",
         ],
         weaknesses=[
             "Still a soft, rounded nose / tail with a small 'pillbox' greenhouse: the plan corners are tighter than in round 1 but the loft remains a smooth superellipse-like shell (conservative by design, a little dated).",
             "Front lower bumper valance: the black band boundary follows the exact z = 0.43 m bisect plane, so it is a clean curve but meets the arch lip with a small step (visible only in close-ups).",
             "Mirror caps and door handles are simple extrusions; no door seals / window frames on the inner side.",
             "Interior shares the kit's generic seat / dash shapes (box-modelled seats, flat dash vents); rear bench has no seat belts.",
             "Tri count 139.5 k (Body 64.9 k because of the dense loft + arch lips + lamp patches) is close to the 150 k budget - acceptable under Nanite, trim `ring_density` to 1.5 for a lighter LOD0."]),
    dict(id="car03_muscle_thunderline", index=3, name="Thunderline", drivetrain="RWD", mass=1650, power=310, ucx=4,
         ucx_desc="1 rear lower body, 2 mid lower body, 3 nose, 4 cabin",
         wheel_style="'mag' - 5 wide flat spokes, chrome lip + chrome centre cap, 17\"",
         tyre="235/50 R17 front, 275/50 R17 rear (rim flange radius 0.2159 m; rear rim 0.255 m wide)",
         brief="Classic 2-door fastback muscle car: long flat hood with a forward-facing centre scoop, short cabin set back, continuous fastback roof, short deck with a lip spoiler, wide rear haunches over fat rear tyres.",
         features=[
             "Loft: very long bonnet (cowl at x = 0.90), 22-25 deg windscreen, fastback roof falling to a short deck, coke-bottle plan view (haunches 0.966 m half width, waist 0.908), strong shoulder crease rising to the rear haunch, wide flat nose; fix round 1: the tail panel is raked 5.5 cm over its height (`shear_end`) instead of a vertical slab.",
             "Twin racing stripes = separate `M_Paint2` material zone (shell bisected exactly at |y| = 0.25 / 0.39, runs over hood, roof and deck; UE can recolour or hide it by swapping the slot).",
             "Hood: filleted shut-line loop and a forward-facing wedge scoop built as a closed solid sunk into the skin (black front wall + chrome intake bars). Rear-quarter brake-cooling scoop with chrome louvres, long door with chrome pull, chrome window-trim loops, small body-colour mirrors, black sill skirt with a chrome rocker moulding (fix round 1).",
             "Front: full-width chrome-framed grid grille with two round chrome-ringed headlamps inside it and a chrome centre cross (fix round 1), chrome bumper blade that now wraps round both corners (radial sweep, fix round 1), plate recess, twin lower slot intakes. Rear: full-width flat tail-lamp panel (red lenses, amber / white corner windows, reflector backing, chrome frame), wrap-around chrome bumper blade, plate recess, dual round chrome tips, ducktail lip.",
             "Interior: bucket seats + rear bench, parcel shelf, re-positioned rear-view mirror, thin 3-spoke wheel (rim 0.195 m, tube 12.5 mm), chrome band + passenger grab bar across the dash and a triple auxiliary gauge pod ahead of the gear lever (fix round 1).",
         ],
         weaknesses=[
             "Profile is still a slab-sided long-hood coupe: very long flat bonnet, long front overhang and a small set-back cabin; the wheels look slightly small under the tall flanks (they match the roster: 0.33 / 0.35 m radius).",
             "Chrome grille grid is a flat lattice of boxes; the new centre cross breaks it up but it stays repetitive in extreme close-ups.",
             "Stripes are a material zone, not geometry: their edges follow the exact |y| plane but the roof stripe crosses the glass pillars unbroken (fine for paint).",
             "`mag` wheel spokes are flat plates with a chamfer; no lug-nut detail beyond the hub ring.",
             "Interior still shares the generic kit seats / dash vents; the new pod, chrome band and grab bar are the only period styling.",
             "Tri count 137.5 k (Body 62.6 k) - near the budget ceiling."]),
]


def load(c):
    with open(os.path.join(ROOT, "Exports", "Cars", c["id"], c["id"] + ".json"), encoding="utf8") as fh:
        return json.load(fh)


def fnum(v, n=3):
    return ("%." + str(n) + "f") % v


def vec(v):
    return "(%s)" % ", ".join(fnum(x, 3) for x in v)


def tri_table(j, c):
    t = j["tri_counts"]
    rows = []
    for part in ("Body", "Glass", "Interior", "SteeringWheel", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
        rows.append("| `%s_%s` | %d | %s |" % (j["id"], part, t[part], ", ".join(j["material_slots"][part])))
    rows.append("| UCX hulls (%d, not rendered) | %d | - |" % (len(j["ucx"]), t["UCX"]))
    rows.append("| **total visual (LOD0)** | **%d** | |" % t["total_visual"])
    return "\n".join(rows)


def car_section(c, j):
    d = j["dimensions"]
    w = j["wheels"]
    L = []
    L.append("### %d. `%s` - %s (%s, player car)\n" % (c["index"], c["id"], c["name"], c["drivetrain"]))
    L.append(c["brief"] + "\n")
    L.append("| Property | Value |\n|---|---|")
    L.append("| Dimensions L x W x H (m) | %s x %s x %s (width incl. mirrors %s) |" % (fnum(d["length"]), fnum(d["width"]), fnum(d["height"]), fnum(d["width_with_mirrors"])))
    L.append("| Wheelbase / track F / R / ride height (m) | %s / %s / %s / %s |" % (fnum(j["wheelbase"], 2), fnum(j["track_front"], 2), fnum(j["track_rear"], 2), fnum(j["ride_height"], 2)))
    L.append("| Wheels (radius x width, m) | front %s x %s, rear %s x %s |" % (fnum(w["FL"]["radius"]), fnum(w["FL"]["width"]), fnum(w["RL"]["radius"]), fnum(w["RL"]["width"])))
    L.append("| Tyre / wheel | %s; %s |" % (c["tyre"], c["wheel_style"]))
    L.append("| Wheel centres (car space, m) | FL %s, FR %s, RL %s, RR %s |" % (vec(w["FL"]["center"]), vec(w["FR"]["center"]), vec(w["RL"]["center"]), vec(w["RR"]["center"])))
    L.append("| Steering wheel | hub %s, rim axis %s |" % (vec(j["steering_wheel"]["center"]), vec(j["steering_wheel"]["axis"])))
    L.append("| Cameras | hood %s, cockpit %s, bumper %s |" % (vec(j["cameras"]["hood"]), vec(j["cameras"]["cockpit"]), vec(j["cameras"]["bumper"])))
    L.append("| Lights | head L/R %s / %s, tail L/R %s / %s, reverse %s |" % (vec(j["lights"]["head_l"]), vec(j["lights"]["head_r"]), vec(j["lights"]["tail_l"]), vec(j["lights"]["tail_r"]), vec(j["lights"]["reverse"])))
    L.append("| Exhaust anchors | L %s, R %s |" % (vec(j["exhaust"][0]), vec(j["exhaust"][1])))
    L.append("| Collision | `UCX_%s_Body_01..%02d` (convex, no wheels): %s |" % (c["id"], len(j["ucx"]), c["ucx_desc"]))
    L.append("| UV | `UVMap` (smart project, non-overlapping, overlap <= 0.02 %%) on every part, Body island margin 0.0015 (~50 %% of the sheet used); `UVLivery` (5 planar islands for stripes / liveries) on the Body only |")
    L.append("| Reference mass / power (Docs/CAR_ROSTER.md) | %d kg / %d kW |" % (c["mass"], c["power"]))
    L.append("")
    L.append("Triangles and material slots per part:\n")
    L.append("| Part | Tris | Material slots |\n|---|---|---|")
    L.append(tri_table(j, c))
    L.append("")
    L.append("Design / detail summary:\n")
    for f in c["features"]:
        L.append("* " + f)
    L.append("")
    L.append("Known weaknesses (honest list):\n")
    for f in c["weaknesses"]:
        L.append("* " + f)
    L.append("")
    return "\n".join(L)


def main():
    js = {c["id"]: load(c) for c in CARS}
    total = sum(j["tri_counts"]["total_visual"] for j in js.values())
    out = []
    out.append("# Player cars 01 Pulse / 02 Cadence / 03 Thunderline (Blender -> Unreal)\n")
    out.append("Generated %s by `Tools/blender/cars/make_doc_cars_01_02_03.py` from the JSON sidecars (which `export_car` reads from the live scene). 3 cars, 8 FBX parts each + 3 / 4 / 4 UCX hulls, %d triangles in total (sum of LOD0, visual parts). This file supersedes the Cadence and Thunderline sections of `Docs/Kits/cars_02_03_04.md` (their numbers were stale after the Cadence rebuild).\n" % (datetime.date.today().isoformat(), total))
    out.append("Source of truth: `Tools/blender/cars/car0N_*.py` (idempotent, executed in the shared Blender on port 9889) built on `Tools/blender/lib/carkit.py` (untouched) + `carkit_ext_02_03_04.py` (cars 02 / 03) + `carkit_ext_fix_01_02_03.py` (fix round 1, all three). Binding conventions: `Docs/BLENDER_CONTRACT.md`, recipe `Docs/CARKIT_API.md`, roster `Docs/CAR_ROSTER.md` rows 1-3.\n")
    out.append("## 1. Files\n")
    out.append("| What | Path |\n|---|---|")
    out.append("| Car scripts | `Tools/blender/cars/car01_hatch_pulse.py`, `car02_sedan_cadence.py`, `car03_muscle_thunderline.py` |")
    out.append("| Helpers (own files, `carkit.py` not edited) | `Tools/blender/lib/carkit_ext_02_03_04.py` (cars 02 / 03), `Tools/blender/lib/carkit_ext_fix_01_02_03.py` (fix round 1, see section 6) |")
    out.append("| Doc generator | `Tools/blender/cars/make_doc_cars_01_02_03.py` |")
    out.append("| FBX + sidecar per car | `Exports/Cars/<id>/<id>_Body.fbx` (Body + `UCX_*`), `_Glass`, `_Interior`, `_SteeringWheel`, `_Wheel_FL/FR/RL/RR` + `<id>.json` |")
    out.append("| Blender staging | roots at `x = 12 m` (Pulse), `24 m` (Cadence), `36 m` (Thunderline), `y = 0`; collections `FORZA_UE/Cars/<id>` (Pulse 22 objects: root, 4 meshes, 4 wheels, 3 hidden `UCX_*`, 10 anchor empties; Cadence / Thunderline 23 objects with 4 hulls; no QA clutter) |")
    out.append("| Master file | `UnrealSonnet5.5Forza.blend` (saved after the final export) |")
    out.append("")
    out.append("Rebuild / re-export from the Blender MCP console (each call < 20 s: geometry 3-6 s, each UV stage 6-12 s, validate 15-20 s, export ~1 s):\n")
    out.append("```python\nCAR02_STAGE = \"geometry\"      # \"geometry\" | \"uv1\" (Body, Glass, Interior, SteeringWheel) | \"uv2\" (front wheels) | \"uv3\" (rear wheels) | \"all\"   (CAR01_STAGE / CAR03_STAGE alike)\nexec(compile(open(r\"<project>/Tools/blender/cars/car02_sedan_cadence.py\", encoding=\"utf8\").read(), \"car02\", \"exec\"), globals())\nCAR02_STAGE = \"uv1\"; exec(...); CAR02_STAGE = \"uv2\"; exec(...); CAR02_STAGE = \"uv3\"; exec(...)\nfor f in (\"carkit.py\", \"carkit_ext_fix_01_02_03.py\"): exec(compile(open(r\"<project>/Tools/blender/lib/\" + f, encoding=\"utf8\").read(), f, \"exec\"), globals())\nvalidate_car(\"car02_sedan_cadence_ROOT\", targets=dict(length=4.70, width=1.82, height=1.46, wheelbase=2.76))\nexport_car_checked(\"car02_sedan_cadence_ROOT\", display_name=\"Cadence\")      # FBX per part + JSON, then re-reads every FBX (tangent / binormal layers present)\n```\n")
    out.append("Set `CAR02_QA = True` / `CAR03_QA = True` before the geometry stage to get edge-only `<id>_FOC_*` look targets for close-up `look` calls; the default build removes them (`purge_qa`).\n")
    out.append("## 2. Conventions (all three cars)\n")
    out.append("* 1 BU = 1 m, Z up, **+X forward, +Y left (LHD)**; car-space origin on the ground under the middle of the wheelbase. All meshes have applied transforms, identity parent inverse, no modifiers; `<id>_ROOT` carries the contract custom properties (`wheelbase`, `track_*`, `wheel_radius_*`, `wheel_width_*` (measured tyre width), `ride_height`, `length`, `width`, `height`, `drivetrain`, `steering_side`).")
    out.append("* One FBX per part, each exported centred on its own pivot (Body/Glass/Interior on the car origin; SteeringWheel on the hub; wheels on the axle). FBX recipe from `fbx_export.py` (4 m body -> 400 uu, left side -> -Y in UE). Import with **Combine Meshes off, Import Materials off, Auto Generate Collision off**; the `UCX_*` hulls in `_Body.fbx` become the simple collision of the body. The Body FBX carries tangents + binormals for both UV channels (every mesh is tris / quads only, no n-gons).")
    out.append("* Material slots are the contract names; map them to the master-material instances **by name**. `M_Glass` appears only in `_Glass`; the lamp slots (`M_Headlight`, `M_Taillight`, `M_Reverse`, `M_Indicator`) only in `_Body`. `M_Paint2` is the accent slot: Pulse roof pack + pillars + spoiler, Thunderline stripes; the Cadence body uses `M_Paint` only. Nanite: all parts except `_Glass` are opaque.")
    out.append("* Right-hand parts are mirror-built (no negative scales); wheels FR / RR are mirror-built so the spokes face outward. Normals: smooth custom normals from the lofted shell (`apply_shell_normals`), hard edges above 62 deg.")
    out.append("")
    out.append("## 3. Recommended UE usage\n")
    out.append("| Item | Recommendation |\n|---|---|")
    out.append("| Collision | Body: the imported `UCX_*` hulls as simple collision, *Use Complex As Simple* off. Glass / Interior / SteeringWheel / wheels: collision **none**. Chaos wheel collider radius / width from the JSON (`wheels.*.radius`, `.width`, in m x 100 = cm). Use the root custom properties for suspension setup (ride height, track, wheelbase). |")
    out.append("| Pivots in UE | Body, Glass, Interior at the vehicle origin (middle of the wheelbase, on the ground); wheel meshes at the axle centre (attach to the wheel bones / sockets at the JSON centres: UE x = x*100, UE y = -y*100, UE z = z*100); SteeringWheel at the hub, rotate about `steering_wheel.axis`. |")
    out.append("| Scale | 1.00 only: the vehicle-dynamics values (wheel radius, track) are baked into the meshes. |")
    out.append("| LOD / Nanite | Nanite on Body, Interior, wheels, steering wheel; glass is a separate translucent material (3 k tris, no Nanite). LOD0 totals 135 k - 140 k triangles per car. |")
    out.append("| Paint | `M_Paint` = body colour / finish (swap in the instance), `M_Paint2` = accent. UV `UVLivery` is for stripes / liveries (box-projected, 5 planar islands). |")
    out.append("| Lights | Anchor empties are *not* exported; read the positions from the JSON (`lights`, `exhaust`, `cameras`) and spawn light components / niagara exhaust / cameras there. The lamp slots are the emissive lens slots (brake lights brighten `M_Taillight`). |")
    out.append("")
    out.append("## 4. Car overview\n")
    out.append("| Car | L x W x H (m) | Wheelbase | Wheels F / R (radius, m) | Tris (LOD0) | Body tris | Drivetrain |\n|---|---|---|---|---|---|---|")
    for c in CARS:
        j = js[c["id"]]
        d = j["dimensions"]
        out.append("| `%s` %s | %s x %s x %s | %s | %s / %s | %d | %d | %s |" % (c["id"], c["name"], fnum(d["length"], 2), fnum(d["width"], 2), fnum(d["height"], 2), fnum(j["wheelbase"], 2),
                                                                                fnum(j["wheels"]["FL"]["radius"], 2), fnum(j["wheels"]["RL"]["radius"], 2), j["tri_counts"]["total_visual"], j["tri_counts"]["Body"], c["drivetrain"]))
    out.append("")
    out.append("Silhouette separation: Pulse = short, tall compact with a floating black roof and a roof-edge spoiler; Cadence = conservative three-box with a chrome-trimmed greenhouse and upright grille; Thunderline = long hood / short raked deck fastback with wide rear haunches, stripes and wrap-around chrome bumpers. Wheels differ per car (10 twin-spoke / 10 slim swept / 5 wide flat), and so do tyre sizes, track, lamp signatures (angular blade lamps + wrap tail lamps / chrome wrap lamps + clean wrap tail lamps / round lamps in a chrome grille + full-width tail panel) and exhaust layouts (twin small round / twin small round / dual large chrome rings).\n")
    out.append("## 5. Assets\n")
    for c in CARS:
        out.append(car_section(c, js[c["id"]]))
    out.append("## 6. Fix round 1 (art-director findings) - what changed\n")
    out.append("* **Cadence export was stale (blocker)**: the Body had been rebuilt after the 23:26 export (FBX 65.3 k Body tris / 18-vertex UCX_04 / old anchor positions against 62.7 k / 16 / new positions in the scene). The car was rebuilt from the script, validated and re-exported; the JSON now carries the live anchors (tail lamp, reverse, head lamp) and tri counts. `export_car_checked` (in `carkit_ext_fix_01_02_03.py`) re-reads every written FBX and fails if the tangent / binormal layers are missing or the file is older than the call; all three cars were exported with it. Independent proof: `Tools/blender/qa/fbx_geometry_info.py` reads the binary FBX back - Body vertices / corners (Pulse 29 834 / 126 022, Cadence 33 680 / 141 668, Thunderline 31 813 / 133 786), the wheel meshes and every UCX hull vertex count equal the live scene exactly.")
    out.append("* **Near-zero-area faces**: `cleanup_slivers` welds the vertices of every face below 1e-7 m2 to their neighbours within 0.25 mm, dissolves the degenerate geometry, repairs the non-manifold edges a weld can create and re-triangulates n-gons. Body faces below 1e-7 m2: Pulse 926 -> 21, Cadence 838 -> 4, Thunderline 771 -> 7; below 1e-9 m2: 59 / 158 / 276 -> 2 / 0 / 0; validator degenerate faces (< 1e-10 m2): none. It runs twice: on the bmesh before `finish_object` and on the finished mesh after it (`fix_object_micro_islands`), because `finish_object`'s own triangulation re-creates a few slivers. Lesson: a post-weld n-gon makes Blender's FBX exporter silently drop the tangent layers (Body FBX shrinks to ~40 %), so the clean-up ends with a beauty triangulation.")
    out.append("* **QA clutter**: the `<id>_FOC_*` edge meshes and `<id>_QA_*` area lights of Cadence and Thunderline were deleted (collections back to the documented 23 objects); the scripts only create them when `CAR0N_QA = True` and call `purge_qa(CAR)` otherwise. `remove_asset` already removes everything with the car prefix on every rebuild.")
    out.append("* **Cadence tail lamp / nose / tail / flank**: new `build_taillight_clean` (also used by Pulse) - shallow black pocket, one smooth red lens over amber | white, densified lens seams (a straight seam across the curved corner used to sag below the skin and show as a black wedge), chrome / black bezel; the lamp moved 1 cm down so the bezel no longer crosses the deck-shoulder crease. Plan-view corners squarer, crisper shoulder crease, rub moulding with chrome insert.")
    out.append("* **Thunderline**: raked tail (`shear_end`: vertices within 0.55 m of the tail move towards the car centre by up to 5.5 cm, growing with height; shell, reference shell and BVH are moved together so projections, custom normals and hulls stay consistent), chrome bumper blades wrap round the corners (radial rays from the centre of the nose / tail, 140 degrees), chrome rocker moulding on the sill, grille centre cross.")
    out.append("* **Pulse**: roof peak -2.2 cm, tail rounding 0.09 -> 0.065 m and cap bulge 0.020 -> 0.014 (crisper hatch face), wheels 64 / 72 -> 56 / 64 segments (15.3 k -> 14.0 k tris each, total 143.0 k -> 135.6 k), 2.8 mm speck at the nose removed, clean tail lamps.")
    out.append("* **UV**: new `uv_unwrap_packed` (Body island margin 0.004 -> 0.0015, concave packing): Body sheet usage 27 % -> 47 - 50 % at the same <= 0.02 % overlap, all UVs inside 0..1; `UVLivery` unchanged.")
    out.append("* **Per-car cockpit character**: Pulse red dash band + gear-boot ring, Cadence cream trim band with chrome lines, Thunderline chrome band + grab bar + triple gauge pod (the kit dash, seats and door cards are still shared).")
    out.append("* Dial ticks / knobs (22 micro boxes of 5-8 mm per Interior) are closed solids with outward normals (verified: no inverted closed islands in any part); `fix_micro_islands` recalculates normals of closed micro islands and drops open specks < 4 mm / 2-face junk sheets.")
    out.append("")
    out.append("## 7. Library additions (`Tools/blender/lib/carkit_ext_fix_01_02_03.py`)\n")
    out.append("`purge_qa`, `cleanup_slivers`, `fix_micro_islands`, `fix_object_micro_islands`, `build_taillight_clean`, `shear_end`, `uv_unwrap_packed`, `unwrap_parts_fix`, `uv_utilisation`, `export_car_checked`, `mesh_quality`. Nothing in `carkit.py` was edited. QA tool (plain Python, no Blender): `Tools/blender/qa/fbx_geometry_info.py`.\n")
    out.append("## 8. Cross-car known weaknesses\n")
    out.append("* Interiors, door cards and seats come from the shared kit and look alike; per-car differences are the wheel, seat sport-ness, rear seating, dash height and the small trim additions listed above.")
    out.append("* Preview paint is the shared red `M_Paint`; the paint finishes are intended to be swapped in UE.")
    out.append("* The loft is a dense quad grid (~16 k quads): Body 57 - 65 k triangles, 135 - 140 k per car (limit 150 k).")
    out.append("* ~2 300 open boundary edges in the Pulse / Cadence Body (window reveals, lens patches, liners) are by design (validator warning only).")
    out.append("* Glass is a single shell with a black reveal; no frame thickness, no wiper pivot on the windscreen.")
    out.append("* No damage / deformation mesh, no LOD meshes (Nanite assumed).")
    out.append("")
    with open(OUT, "w", encoding="utf8") as fh:
        fh.write("\n".join(out))
    print("wrote", OUT, len("\n".join(out)))


if __name__ == "__main__":
    main()
