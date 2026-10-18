"""
make_doc_cars_02_03_04.py - generates Docs/Kits/cars_02_03_04.md from the exported JSON sidecars (Exports/Cars/<id>/<id>.json).
Plain Python (no Blender needed):   python Tools/blender/cars/make_doc_cars_02_03_04.py
"""
import json
import os
import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "Docs", "Kits", "cars_02_03_04.md")

CARS = [
    dict(id="car02_sedan_cadence", index=2, name="Cadence", drivetrain="FWD", mass=1480, power=120,
         ucx_verts=[32, 22, 27, 18], wheel_style="'ten' - 10 slim swept spokes, chrome centre cap, 16\"",
         tyre="195/55 R16 (rim flange radius 0.2032 m)", uv_overlap="0.02 %",
         brief="Everyday 4-door three-box sedan with a conservative roof line, chrome window trim, upright chrome-framed grille and modest 16\" wheels.",
         features=[
             "Loft: designed profile (filleted top line, straight windscreen 28 deg / rear glass 36 deg, flat deck), shoulder crease (`zc`/`cdepth`) running from the headlamp to the tail lamp, 8.5 cm tumblehome, 3.6 cm tight arch gaps with rolled lips and black arch mouldings (both sides).",
             "Four doors (two shut-line groups with a black B-pillar between them), bonnet shut line with filleted corners, boot lid cuts, fuel flap, chrome door handles, chrome belt / window-surround loops round both side windows, body-colour mirrors, wipers.",
             "Front: upright chrome-slat grille in a chrome frame, chromed slim wrap headlamps with bezel, plate recess, hex lower intake, round fog lamps, black lower bumper band that ends at the arches. Rear: large wrap-around segmented tail lamps (brake / indicator / reverse), chrome boot strip, plate recess, twin small exhaust tips, plain roundel.",
             "Interior: 2 + 3 plain seats (non-sport), parcel shelf and bulkhead, roof / pillar lining from the body faces, kit dash with twin dials + centre screen, 3-spoke round steering wheel (rim 0.19 m).",
         ],
         weaknesses=[
             "Tail lamp bezel is slightly ragged at the top corner where the lamp wraps over the deck shoulder (visible only in close-ups).",
             "Mirror caps and door handles are simple extrusions; no door seals / window frames on the inner side (glass is a single sheet 14 mm inside the skin).",
             "Interior shares the kit's generic seat / dash shapes with the other cars (box-modelled seats, flat dash vents); rear bench has no seat belts.",
             "Tri count 139.7 k is close to the 150 k budget (Body 65 k because of the dense loft + arch lips) - acceptable under Nanite, trim `ring_density` to 1.5 if a lower LOD0 is needed."]),
    dict(id="car03_muscle_thunderline", index=3, name="Thunderline", drivetrain="RWD", mass=1650, power=310,
         ucx_verts=[32, 22, 27, 15], wheel_style="'mag' - 5 wide flat spokes, chrome lip + chrome centre cap, 17\"",
         tyre="235/50 R17 front, 275/50 R17 rear (rim flange radius 0.2159 m; rear rim 0.255 m wide)", uv_overlap="0.07 %",
         brief="Classic 2-door fastback muscle car: long flat hood with a forward-facing centre scoop, short cabin set back, continuous fastback roof, short deck with a lip spoiler, wide rear haunches over fat rear tyres.",
         features=[
             "Loft: very long bonnet (cowl at x = 0.90), 22-25 deg windscreen, fastback roof falling 16 deg to a short deck, coke-bottle plan view (haunches 0.966 m half width, waist 0.908), strong shoulder crease rising to the rear haunch, wide flat nose.",
             "Twin racing stripes = separate `M_Paint2` material zone (shell bisected exactly at |y| = 0.25 / 0.39, runs over hood, roof and deck; UE can recolour or hide it by swapping the slot).",
             "Hood: filleted shut-line loop and a forward-facing wedge scoop built as a closed solid sunk into the skin (black front wall + chrome intake bars). Rear-quarter brake-cooling scoop with chrome louvres, long door with chrome pull, chrome window-trim loops round door and quarter windows, small body-colour mirrors.",
             "Front: full-width chrome-framed grid grille on a flat recess with two round chrome-ringed headlamps inside it, chrome bumper blade, plate recess, twin lower slot intakes. Rear: full-width flat tail-lamp panel (red lenses, amber / white corner windows, reflector backing, chrome frame), chrome bumper blade, plate recess, dual round chrome tips, ducktail lip.",
             "Interior: bucket seats + rear bench, parcel shelf, re-positioned rear-view mirror (the kit's is too tall for this roof), thin 3-spoke wheel (rim 0.195 m, tube 12.5 mm).",
         ],
         weaknesses=[
             "Chrome grille grid is a flat lattice of boxes (reads well from 3 m, repetitive in extreme close-ups); the bumper blades do not wrap round the corners.",
             "Stripes are a material zone, not geometry: their edges follow the exact |y| plane but the roof stripe crosses the glass pillars unbroken (fine for paint, no decal trim).",
             "`mag` wheel spokes are flat plates with a chamfer; no lug-nut centre cap detail beyond the hub ring.",
             "Interior shares the generic kit dash / seats; the dash is not period-styled (no retro gauge cluster).",
             "Tri count 138.4 k (Body 64.7 k) - near the budget ceiling."]),
    dict(id="car04_coupe_vesper", index=4, name="Vesper", drivetrain="RWD", mass=1380, power=285,
         ucx_verts=[32, 22, 25, 19], wheel_style="'five' - 5 broad concave spokes that widen into the rim, 19\"",
         tyre="235/40 R19 front, 275/35 R19 rear (rim flange radius 0.2413 m, low-profile tyre profile scaled by `_tyre_ext`)", uv_overlap="0.01 %",
         brief="Low sleek 2-door sports coupe: long crowned nose, small cabin set far back under a sweeping fastback glass, ducktail kick-up, wide stance with coke-bottle haunches, slim wrap headlamps, 19\" five-spoke wheels.",
         features=[
             "Loft: 1.29 m tall at the roof peak, 26 deg windscreen, 17 deg fastback glass, crowned fenders (narrow hood crown ratio 0.78 so the fenders peak above the bonnet), haunches 0.937 m half width, tail tucked in, 5 cm tumblehome.",
             "One long door per side with a black window-frame loop round the long sail side window, bonnet shut line loop, twin vented bonnet louvres with fins, front fender vents with louvres, door pull, fuel flap, painted black mirror caps on stalks.",
             "Front: slim projector wrap headlamps with bezel, narrow slotted upper grille, plate recess, wide low mouth with hex mesh on a flat recess, splitter lip. Rear: full-width low tail-lamp bar (flat recess, segmented lenses + centre third light), diffuser with 7 fins and twin round tips, ducktail kick-up (black `M_Paint2`), small rear splitter.",
             "Interior: two sport bucket seats only (rear shelf + bulkhead), compact flat-bottom 3-spoke wheel (rim 0.175 m), roof / pillar lining.",
         ],
         weaknesses=[
             "The ducktail is a separate black sweep (`M_Paint2`) laid on the deck; from some rear 3/4 angles it reads as a small wing rather than a moulded kick-up.",
             "Rear tail-lamp bar is thin; it has no depth cues beyond the recess (no LED sub-structure).",
             "The 5-spoke wheel has no spoke-to-spoke scallops and the caliper is the generic kit body; tyre sidewalls carry only two embossed rings.",
             "Interior shares the generic kit dash / seats (box seats); there is no rear seat or roll cage detail.",
             "Mirror stalks are thin boxes; no folding hinge or indicator lens detail apart from the amber repeater."]),
]

MAT_COUNT = None


def load(c):
    with open(os.path.join(ROOT, "Exports", "Cars", c["id"], c["id"] + ".json"), encoding="utf8") as fh:
        return json.load(fh)


def fnum(v, n=3):
    return ("%." + str(n) + "f") % v


def tri_table(j):
    t = j["tri_counts"]
    rows = []
    for part in ("Body", "Glass", "Interior", "SteeringWheel", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
        rows.append("| `%s_%s` | %d | %s |" % (j["id"], part, t[part], ", ".join(j["material_slots"][part])))
    rows.append("| UCX hulls (4, not rendered) | %d | - |" % t["UCX"])
    rows.append("| **total visual (LOD0)** | **%d** | |" % t["total_visual"])
    return "\n".join(rows)


def vec(v):
    return "(%s)" % ", ".join(fnum(x, 3) for x in v)


def car_section(c, j):
    d = j["dimensions"]
    w = j["wheels"]
    L = []
    L.append("### %d. `%s` - %s (%s, %s)\n" % (c["index"], c["id"], c["name"], c["drivetrain"], "player car"))
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
    L.append("| Collision | `UCX_%s_Body_01..04` (verts %s, convex, no wheels): 1 rear lower body, 2 mid lower body, 3 nose, 4 cabin |" % (c["id"], "/".join(str(v) for v in c["ucx_verts"])))
    L.append("| UV | `UVMap` (smart project, non-overlapping; overlap %s) on every part; `UVLivery` (5 planar islands for stripes / liveries) on the Body only |" % c["uv_overlap"])
    L.append("| Reference mass / power (Docs/CAR_ROSTER.md) | %d kg / %d kW |" % (c["mass"], c["power"]))
    L.append("")
    L.append("Triangles and material slots per part:\n")
    L.append("| Part | Tris | Material slots |\n|---|---|---|")
    L.append(tri_table(j))
    L.append("")
    L.append("Design / detail summary:\n")
    for f in c["features"]:
        L.append("* " + f)
    L.append("")
    L.append("Known weaknesses:\n")
    for f in c["weaknesses"]:
        L.append("* " + f)
    L.append("")
    return "\n".join(L)


def main():
    js = {c["id"]: load(c) for c in CARS}
    total = sum(j["tri_counts"]["total_visual"] for j in js.values())
    out = []
    out.append("# Player cars 02 Cadence / 03 Thunderline / 04 Vesper (Blender -> Unreal)\n")
    out.append('> **Superseded for Cadence (car02) and Thunderline (car03):** both cars were rebuilt, re-validated and re-exported in the art-director fix round; the current numbers, anchors and known weaknesses are in `Docs/Kits/cars_01_02_03.md`. The Cadence / Thunderline tables below (Body tris, UCX_04 vertex count, anchor positions, weakness lists) predate that round. Vesper (car04) is unchanged.\n')
    out.append("Generated %s by `Tools/blender/cars/make_doc_cars_02_03_04.py` from the JSON sidecars. 3 cars, 8 FBX parts each + 4 UCX hulls each, %d triangles in total (sum of LOD0, visual parts).\n" % (datetime.date.today().isoformat(), total))
    out.append("Source of truth: `Tools/blender/cars/car0N_*.py` (idempotent, executed in the shared Blender on port 9889) built on `Tools/blender/lib/carkit.py` (untouched) + `Tools/blender/lib/carkit_ext_02_03_04.py`. Binding conventions: `Docs/BLENDER_CONTRACT.md`, recipe `Docs/CARKIT_API.md`, roster `Docs/CAR_ROSTER.md` rows 2-4.\n")
    out.append("## 1. Files\n")
    out.append("| What | Path |\n|---|---|")
    out.append("| Car scripts | `Tools/blender/cars/car02_sedan_cadence.py`, `car03_muscle_thunderline.py`, `car04_coupe_vesper.py` |")
    out.append("| Extra helpers (own file, `carkit.py` not edited) | `Tools/blender/lib/carkit_ext_02_03_04.py` |")
    out.append("| Doc generator | `Tools/blender/cars/make_doc_cars_02_03_04.py` |")
    out.append("| FBX + sidecar per car | `Exports/Cars/<id>/<id>_Body.fbx` (Body + `UCX_*`), `_Glass`, `_Interior`, `_SteeringWheel`, `_Wheel_FL/FR/RL/RR` + `<id>.json` |")
    out.append("| Blender staging | roots at `x = 24 m` (Cadence), `36 m` (Thunderline), `48 m` (Vesper), `y = 0`; collections `FORZA_UE/Cars/<id>` (23 objects each: root, 4 meshes, 4 wheels, 4 hidden `UCX_*`, 10 anchor empties) |")
    out.append("| Master file | `UnrealSonnet5.5Forza.blend` (saved after the final export) |")
    out.append("")
    out.append("Rebuild / re-export from the Blender MCP console (each call < 20 s: geometry ~2-4 s, UV stages 5-10 s each, validate 10-25 s, export 1-4 s):\n")
    out.append("```python\nCAR03_STAGE = \"geometry\"      # \"geometry\" | \"uv1\" (Body, Glass, Interior, SteeringWheel) | \"uv2\" (front wheels) | \"uv3\" (rear wheels) | \"all\"\nexec(compile(open(r\"<project>/Tools/blender/cars/car03_muscle_thunderline.py\", encoding=\"utf8\").read(), \"car03\", \"exec\"), globals())\nCAR03_STAGE = \"uv1\"; exec(...); CAR03_STAGE = \"uv2\"; exec(...); CAR03_STAGE = \"uv3\"; exec(...)\nexec(compile(open(r\"<project>/Tools/blender/lib/carkit.py\", encoding=\"utf8\").read(), \"kit\", \"exec\"), globals())\nvalidate_car(\"car03_muscle_thunderline_ROOT\", targets=dict(length=4.85, width=1.92, height=1.32, wheelbase=2.75))\nexport_car(\"car03_muscle_thunderline_ROOT\", display_name=\"Thunderline\")      # FBX per part + JSON\n```\n")
    out.append("## 2. Conventions (all three cars)\n")
    out.append("* 1 BU = 1 m, Z up, **+X forward, +Y left (LHD)**; car-space origin on the ground under the middle of the wheelbase. All meshes have applied transforms, identity parent inverse, no modifiers; `<id>_ROOT` carries the contract custom properties (`wheelbase`, `track_*`, `wheel_radius_*`, `wheel_width_*` (measured tyre width), `ride_height`, `length`, `width`, `height`, `drivetrain`, `steering_side`).")
    out.append("* One FBX per part, each exported centred on its own pivot (Body/Glass/Interior on the car origin; SteeringWheel on the hub; wheels on the axle). FBX recipe from `fbx_export.py` (4 m body -> 400 uu, left side -> -Y in UE). Import with **Combine Meshes off, Import Materials off, Auto Generate Collision off**; the `UCX_*` hulls in `_Body.fbx` become the simple collision of the body.")
    out.append("* Material slots are the contract names (`M_Paint`, `M_Paint2`, `M_Chrome`, `M_TrimBlack`, ... `M_Exhaust`); map them to the master-material instances **by name**. `M_Glass` appears only in `_Glass`. `M_Paint2` is the accent slot: Thunderline stripes, Vesper ducktail + mirror caps; the Cadence body uses `M_Paint` only. Nanite: all parts except `_Glass` are opaque.")
    out.append("* Right-hand parts are mirror-built (no negative scales); wheels FR / RR are mirror-built so the spokes face outward. Normals: smooth custom normals from the lofted shell (`apply_shell_normals`), hard edges above 62 deg.")
    out.append("")
    out.append("## 3. Recommended UE usage\n")
    out.append("| Item | Recommendation |\n|---|---|")
    out.append("| Collision | Body: the 4 imported `UCX_*` hulls as simple collision, *Use Complex As Simple* off. Glass / Interior / SteeringWheel / wheels: collision **none**. Chaos wheel collider radius / width from the JSON (`wheels.*.radius`, `.width`, in m x 100 = cm). Use the root custom properties for suspension setup (ride height, track, wheelbase). |")
    out.append("| Pivots in UE | Body, Glass, Interior at the vehicle origin (middle of the wheelbase, on the ground); wheel meshes at the axle centre (attach to the wheel bones / sockets at the JSON centres: UE x = x*100, UE y = -y*100, UE z = z*100); SteeringWheel at the hub, rotate about `steering_wheel.axis`. |")
    out.append("| Scale | 1.00 only (range 1.00 - 1.00): the vehicle-dynamics values (wheel radius, track) are baked into the meshes. |")
    out.append("| LOD / Nanite | Nanite on Body, Interior, wheels, steering wheel; glass is a separate translucent material (3 k tris, no Nanite). LOD0 totals 128 k - 140 k triangles per car; far LODs/impostors are the engine's job (Nanite). |")
    out.append("| Paint | `M_Paint` = body colour / finish (swap in the instance), `M_Paint2` = accent. UV `UVLivery` is for stripes / liveries (box-projected, 5 planar islands). |")
    out.append("| Lights | Anchor empties are *not* exported; read the positions from the JSON (`lights`, `exhaust`, `cameras`) and spawn light components / niagara exhaust / cameras there. `M_Headlight`, `M_Taillight`, `M_Reverse`, `M_Indicator` are the emissive lens slots (brake lights brighten `M_Taillight`). |")
    out.append("")
    out.append("## 4. Car overview\n")
    out.append("| Car | L x W x H (m) | Wheelbase | Wheels F / R (radius, m) | Tris (LOD0) | Body tris | Drivetrain |\n|---|---|---|---|---|---|---|")
    for c in CARS:
        j = js[c["id"]]
        d = j["dimensions"]
        out.append("| `%s` %s | %s x %s x %s | %s | %s / %s | %d | %d | %s |" % (c["id"], c["name"], fnum(d["length"], 2), fnum(d["width"], 2), fnum(d["height"], 2), fnum(j["wheelbase"], 2),
                                                                                fnum(j["wheels"]["FL"]["radius"], 2), fnum(j["wheels"]["RL"]["radius"], 2), j["tri_counts"]["total_visual"], j["tri_counts"]["Body"], c["drivetrain"]))
    out.append("")
    out.append("Silhouette separation: Cadence = tall three-box greenhouse and upright grille; Thunderline = long hood / short deck fastback with wide rear haunches and stripes; Vesper = low, short, cab-rearward coupe with crowned fenders and ducktail. Wheel designs differ per car (10 slim spokes / 5 wide flat spokes / 5 broad concave spokes) and so do tyre sizes, track, lamp signatures (wrap-around chrome-trimmed / round lamps in a chrome grille + full-width tail panel / slim projectors + tail bar) and exhaust layouts.\n")
    out.append("## 5. Assets\n")
    for c in CARS:
        out.append(car_section(c, js[c["id"]]))
    out.append("## 6. QA record (honest iteration log)\n")
    out.append("Every car went through the same loop: build -> `look` (4 angles, rendered / material, close-ups of lamps, grille, hood, wheels, cockpit) -> `zebra_car` reflection-stripe checks (side, front 3/4, rear 3/4) -> validate -> fix -> repeat.\n")
    out.append("* **Cadence** - it0 first loft (blobby tail corners, thick A-pillar, headlamp pocket ragged, bumper valance patch with vertical edges); it1 wrapped black bumper band that ends at the arches, shoulder crease + tumblehome, wider plan corners, A-pillar moved forward, headlamp bezel; it2 enlarged wrap tail lamps, hood loop with filleted front corner, found + fixed the kit-pattern bug that put the right arch mouldings on the left side (clearance left/right now symmetric 22 mm), rolled arch lips; it3 UV / validate / export.")
    out.append("* **Thunderline** - it0 first build (uncut grille: the skin-following pocket cap left the dome of the nose uncut -> new `pocket_cutter_flat`), it1 flat grille / lamp / tail recesses with flat-referenced assemblies, wider nose corners and stripes; it2 hood shut-line loop, scoop rebuilt (first version faced backwards, then too blocky -> forward wedge with chrome intake bars), quarter scoop + trim loops, interior mirror re-positioned (poked through the screen); it3 wheel-arch clearance QA (tracks 1.60 / 1.58, `zw` 0.66 -> tyres 7-11 mm inside the fender lip), arch lips, final validate / export.")
    out.append("* **Vesper** - it0 first build, it1 bumper valance raised so every pocket sits inside the black band (no ragged boundary), interior mirror fixed, ducktail resized; it2 wheel-arch clearance (front tyres stuck out 19 mm -> track 1.54 / 1.53, tyres 235 / 275, hwm 0.935, tumblehome 5 cm, `zw` 0.64 -> +8 / +13 mm), black window frame loop, removed the ragged corner intakes, arch lips; it3 UV / validate / export.")
    out.append("* Note for the kit owner: `car01_hatch_pulse.py` (and the recipe in `Docs/CARKIT_API.md`) mirrors the right-hand arch mouldings with `mirrored_copy(sw) if cy < 0`, but `arch_moulding` is already swept on the right side with the ray (0, 1, 0), so the mirror moves the strip to the LEFT (left arches get two mouldings, right arches none). The Cadence script uses the right-side sweep directly. car01 was not touched.")
    out.append("* Validation (`validate_car`): all three OK - no loose geometry, no non-manifold edges, no inverted closed islands, contract material names, `UVMap` overlap <= 0.07 %, wheel pivots on the axle with tyres touching z = 0, UCX 4 hulls <= 32 verts and convex, triangle budget 128 k - 140 k. Open boundary edges in the Body are the glass reveals, lens patches and liners (by design).\n")
    out.append("## 7. Library additions (`Tools/blender/lib/carkit_ext_02_03_04.py`)\n")
    out.append("`Build` (cutter / insert bookkeeping + `pair`), `ring_pt` / `edge_y`, `rounded_poly` (filleted closed polygons), `sweep_loop` / `sweep_xy` / `sweep_yz` (surface sweeps along 2-D polylines), `window_loop_pts` (outline of a side window for trim sweeps), `hood_loop_xy` (shut-line loop with a filleted corner), `paint_bands` (exact stripe zones by bisecting the shell), `height_field_solid` (scoops / power domes sunk into the skin), `pocket_cutter_flat` (flat-top / flat-floor pockets for wide openings on a domed fascia), `lamp_bezel`, `build_wheel_ext` (+ `_tyre_ext`, spoke styles `ten`, `mag`, `five`, tyre profile scaling for low-profile tyres), `build_rv_mirror`, `delete_verts_where`, `add_anchors`, `unwrap_parts`, QA helpers `wheel_clearance` (tyre vs fender lip) and `focus_meshes` (edge-only look targets).\n")
    out.append("## 8. Cross-car known weaknesses\n")
    out.append("* Interiors, door cards and seats come from the shared kit and look alike; only seat sport-ness, rear seats, steering wheel, parcel shelf and dash height differ.")
    out.append("* Preview paint is the shared red `M_Paint`; the paint finishes are intended to be swapped in UE.")
    out.append("* The loft is a dense quad grid (~16 k quads) so the Body is 56 - 65 k triangles; the three cars together are ~406 k triangles of LOD0 (Nanite assumed).")
    out.append("* Glass is a single shell with a black reveal; there is no frame thickness, no sun-visor / mirror stalk geometry on the windscreen and no wiper pivot.")
    out.append("* No damage / deformation mesh, no brake-light emissive variants (UE material handles it), no LOD meshes.")
    out.append("")
    with open(OUT, "w", encoding="utf8") as fh:
        fh.write("\n".join(out))
    print("wrote", OUT, len("\n".join(out)))


if __name__ == "__main__":
    main()
