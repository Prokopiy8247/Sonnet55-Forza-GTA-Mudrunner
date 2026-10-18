"""
make_doc_cars_07_08_09_10.py - generates Docs/Kits/cars_07_08_09_10.md from the exported JSON sidecars
(Exports/Cars/<id>/<id>.json).  Plain Python (no Blender needed):

    python Tools/blender/cars/make_doc_cars_07_08_09_10.py

Combines (and supersedes) the Ridge section of Docs/Kits/cars_05_06_07.md and Docs/Kits/cars_08_09_10.md.
All numbers (dimensions, wheels, anchors, triangles, material slots) come from the sidecars, so re-running the script after a
re-export keeps the document in sync; the prose lives in the CARS table below.
"""
import json
import os
import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "Docs", "Kits", "cars_07_08_09_10.md")

CARS = [
    dict(id="car07_rally_ridge", index=7, name="Ridge", klass="B", drivetrain="AWD", mass=1260, power=235, ext="carkit_ext_05_06_07.py + carkit_ext_07_fix.py",
         script="car07_rally_ridge.py", stage="CAR07_STAGE", uv_stages=("uv1", "uv2", "uv3"), ucx="3 hulls with 30 / 24 / 23 vertices",
         tyre="205/70 R15 gravel tyre, 0.33 m (lug tops <= 0.3297 m), 0.225 m wide (0.230 incl. lugs); every lug block has seeded random jitter (height / width / slant / spacing)",
         wheel_style="6-spoke star, polished lip (`M_Rim`), brake disc + caliper",
         silhouette="rally 3-door hatch",
         brief="Rally hatchback: raised stance (0.22 m under the skid plate), sculpted flares with black arch mouldings, black bonnet panel with two louvred vents, "
               "roof scoop with a dark intake mouth, spot-light pod, tow hooks, mud flaps, a big double-plane rear wing on tall pylons and gravel tyres; "
               "cockpit with roll cage, bucket seats and harnesses.",
         features=[
             "Loft: designed profile (filleted top line, steep windscreen, hatch glass), 4 cm sculpted haunch flares over every wheel, 5 cm arch gap with rolled lip + 7.5 cm black arch mouldings, black A-pillars + bonnet panel (`M_Paint2`), black rally bumpers (`M_TrimBlack`).",
             "Fix round 2 - silhouette: the hatch glass base moved forward 6 cm (hatch ~38 degrees instead of ~32; the 14 cm tail deck now carries the wing pylons), a black roof-edge gutter bead runs along both roof edges and the wing blade is raised, which breaks up the estate / crossover reading of round 1.",
             "Fix round 2 - wing (`build_rally_wing2`): blade centre at z = 1.29 m on two flat raked pylons whose feet are seated on the measured tail deck (foot plates + bolts), a gurney lip on the flap and SMALL swept end plates (0.23 m, rounded corners, bevelled, `M_Paint2` with a raised `M_Paint` accent inset) instead of the big angular red plates; the hatch glass is clearly visible under the blade.",
             "Fix round 2 - roof scoop (`build_roof_scoop2`): rounded hump with a raised lip, a recessed black intake mouth and two chrome vanes - it reads as a duct, not a solid bump.",
             "Fix round 2 - door number panels (`number_panel`): the skin is recessed 6 mm (pocket cut in the body boolean, black walls = frame), a white plate sits 3.5 mm below the skin and a black numeral '7' (strokes on the plate) on top; the numeral reads correctly on both flanks.",
             "Fix round 2 - tyres (`build_gravel_tyre2`): no more regular comb - every lug has seeded random height, width, slant and spacing jitter, inner-row lugs are skipped at random, the two sides have different lug counts; the sidewall profile was also made monotone (round 1 folded it back by 3 cm).",
             "Details: bonnet vents (2 louvred), fender vents, bonnet pins with wire loops, door shut lines + handles, fuel flap, spot-light pod (4 lamps) on the bumper, tow hooks front and rear (`M_Caliper` red), mud flaps behind all four wheels, skid plate, recovery-mesh rear pocket, single exhaust tip, boxy rally mirrors, blade headlamps with projector eyes, segmented tail lamps (brake / indicator / reverse).",
             "Interior: bucket seats with 4-point harnesses (red webbing), roll cage (main hoop with X diagonals, A-pillar hoops, door bars, rear stays), bare rear panel, fire extinguisher, kit dash with binnacle and screen; 3-spoke wheel (rim 0.145 m).",
         ],
         weaknesses=[
             "The roof is still long and low (belt 1.03 m, glasshouse only 0.36 m deep): from a pure side view the car can still be read as a lifted crossover / estate. Round 2 steepened the hatch, added the gutter, the raised wing and the dark pillars; a deeper glasshouse would need the roof, belt line, door cutters and cage to be re-lofted together and was not attempted.",
             "The wing blade is a clean airfoil on two flat pylons; end plates are flat extrusions (rounded corners and bevel, no moulded rim); the pylon feet are bolted on the deck as overlaps, not welded into the skin.",
             "The numeral '7' is built from flat strips (white plate, black numeral): there are no other digits and no sponsor decals; liveries go on `UVLivery`.",
             "Cage tubes have no mounting plates, harness straps are flat boxes; the dash, seats and door cards are the kit's generic ones.",
             "Overall length 4.22 m (roster 4.15 m): the spot-light pod at the nose and the wing overhang at the tail add ~7 cm over the lofted shell (the 4.21 m of round 1 had the same cause); the mirrors make the car 1.955 m wide against 1.877 m over the flares.",
         ]),
    dict(id="car08_suv_ranger", index=8, name="Ranger", klass="C", drivetrain="AWD", mass=2150, power=220, ext="carkit_ext_08_09_10.py",
         script="car08_suv_ranger.py", stage="CAR08_STAGE", uv_stages=("uv1", "uv2"), ucx="3 hulls with 24 / 18 / 20 vertices",
         tyre="265/75 R16 all-terrain, 0.40 m radius, 0.265 m wide (0.276 m over the sidewall blocks): real tread blocks (`block_tyre`)",
         wheel_style="16\" six-spoke star alloy, brake disc + caliper",
         silhouette="tall boxy off-road SUV",
         brief="Tall boxy off-road SUV: lofted shell with a straight windscreen and a near-vertical tailgate, stepped shoulder crease, big flares, high clearance, "
               "chrome bull bar, roof rack with light bar and recovery boards, A-pillar snorkel, side steps, spare wheel on the tailgate.",
         features=[
             "Loft: boxy 1.93 m tall shell, stepped body side, bonnet raised towards the cowl; 6 cm arch gaps, black flares (10.5 cm), rocker cladding, black A / B / C pillars (`M_Paint2`).",
             "Fix round 2 - flanks: the shoulder crease is 3.6 cm deep and crisper (was 2.0 cm, `cwidth` 0.03), a black body-side protection strip (`M_TrimBlack`, 5 cm) runs across both doors under the crease and a body-colour bead (`M_Paint`) sits above the rocker cladding, so the side is no longer a flat slab.",
             "Fix round 2 - window seals (`window_seal`): a flat-topped black rubber bead (12.5 mm wide, 4 mm high, `M_TrimBlack`) follows every glass opening (it is swept along the boundary loops of the glass sheets and seated on the uncut skin), so the greenhouse no longer reads as a glass box with thin pillars.",
             "Fix round 2 - interior (`build_interior_utility`): flat squared dash pad, hooded two-dial cluster with warning lights, a tall centre block with five vertical vents, a radio blank and three heater knobs, round end vents, glovebox outline and a passenger grab handle, upright non-sport seats, a long gear lever + a short transfer-case lever, door grab handles - instead of the sport binnacle / screen dash of the kit.",
             "Fix round 2 - tyres (`block_tyre`): two staggered lanes of slanted tread blocks, shoulder blocks that wrap the shoulder, a ring of raised blocks on both sidewalls and seeded per-block jitter (different seed per wheel); the base revolve uses 40 segments because the blocks hide the facets - the wheel costs the same ~11.4 k triangles as before.",
             "Doors: 4 doors + side-hinged tailgate shut lines, chrome belt strip, door handles, tow mirrors, antenna, roof drip rails, hood vents / bulge strips, cowl wipers, fender repeaters.",
             "Chassis: visible axles, diffs, coil springs + shocks, driveshaft, exhaust with muffler, skid plate; chrome bull bar with spot lamps and recovery shackles, step bumper with hitch + hooks, tread-plate side steps with brackets, mud flaps.",
             "Roof: tubular rack (cross bars, rails, feet), light bar, two recovery boards, snorkel running up the A-pillar with a ram-air head; spare wheel (`spare_wheel`, block tyre + steel barrel + hub cover) on the tailgate.",
         ],
         weaknesses=[
             "The bonnet is still low and flat for a tall SUV (the front bumper line was kept for the bull bar); the crease, strip and bead help, but the flanks stay boxy by design.",
             "Glass is a thin sheet per window with a black reveal (the rear window is cut from the end cap, so its corners are rectangular); the seal bead is a plain flat-topped section, not a moulded rubber profile; wipers are ribs on the cowl.",
             "Bull bar, rack and snorkel are plain tubes / boxes; the recovery boards are flat.",
             "The seats are the kit's box seats (upright, non-sport); the dash is a generic utility dash, not model-specific; the steering-wheel hub trim is plain grey.",
             "The triangle count (see the table) sits close to the 150 k ceiling: the loft is dense and the added beads / strip / dash cost ~7 k triangles over round 1; trim `ring_density` or the tyre block counts if a lower LOD0 is needed.",
             "Doors, hood and tailgate are shut lines in one Body mesh, not separate animatable meshes.",
         ]),
    dict(id="car09_pickup_mule", index=9, name="Mule", klass="C", drivetrain="RWD (AWD optional)", mass=2350, power=250, ext="carkit_ext_08_09_10.py",
         script="car09_pickup_mule.py", stage="CAR09_STAGE", uv_stages=("uv1", "uv2"), ucx="4 hulls with 21 / 18 / 20 / 16 vertices",
         tyre="255/60 R18 all-terrain, 0.38 m radius, 0.255 m wide (0.266 m over the sidewall blocks): real tread blocks (`block_tyre`)",
         wheel_style="18\" five-double-spoke alloy, brake disc + caliper",
         silhouette="double-cab pickup with an open bed",
         brief="Double-cab pickup truck: two lofted shells in one Body - the cab (hood power dome, big grille, four doors, flares, tow mirrors, roof marker lamps, running boards) "
               "and an open bed (ribbed liner floor, wheel boxes, tie-down rings, rail caps, tailgate, stacked tail lamps, sport bar) joined by a cab-back seal panel.",
         features=[
             "Cab: lofted shell with a tall greenhouse, big upright grille with chrome roundel, blade headlamps, fog lamps, hood power dome + vents, chrome belt strip, tow mirrors, drip rails, roof marker lamps, black flares (11.5 cm), two-tone lower body (`M_Paint2`).",
             "Bed: lofted open box, pocket boolean with a rounded liner, wheel boxes, ribbed floor, rail caps, tie-down rings, tailgate shut lines + handle, stacked corner tail lamps, chrome sport bar, chrome step bumper with hitch + plate.",
             "Fix round 2 - cab / bed gap: a black rubber cab-back seal panel (`M_TrimBlack`, 8 cm, bevelled) closes the 6 cm slot between the cab and the bed, so the shell edges and the frame no longer show through it.",
             "Fix round 2 - mirrors: tow mirrors pulled in (7 cm arms, 0.105 m compact heads): the width incl. mirrors falls from 2.405 m to 2.217 m; the JSON `width` (flare width 1.98 m) and the UCX hulls (1.86 m) remain the values for placement and bounds.",
             "Fix round 2 - window seals: a black rubber seal bead (`window_seal`) frames every cab window opening.",
             "Fix round 2 - tyres (`block_tyre`): block tread lanes + shoulder blocks + sidewall blocks with seeded jitter (different per wheel); the 18\" alloys keep the kit's five twin-spoke design.",
             "Fix round 2 - interior (`build_interior_utility`): the same utilitarian dash as the Ranger (hooded 2-dial cluster, vertical vent block with heater knobs, glovebox outline, grab handle), long gear lever + transfer lever, upright seats.",
             "Chassis: frame rails, leaf springs, axles, diff, driveshaft, fuel tank, twin exhaust with muffler, skid plate; chunky chrome front bumper with skid + tow hooks, mud flaps all round, black running boards with tread strips.",
         ],
         weaknesses=[
             "The pocket boolean of the bed leaves triangle fans around the wheel boxes and the rear walls in the wireframe (shading is clean and Nanite does not care); it was not re-topologised.",
             "The seats are the kit's box seats and the dash is the generic utility dash shared with the Ranger; the bed wheel boxes are decorative (the tyre never reaches them).",
             "Doors, hood, bed gate are shut lines in one Body mesh, not separate animatable meshes.",
             "The tow mirrors are still big (2.22 m width incl. mirrors): for any vehicle-bounds use the JSON `width` and the UCX hulls, never `width_with_mirrors`.",
         ]),
    dict(id="car10_roadster_classic", index=10, name="Brisa", klass="D", drivetrain="RWD", mass=900, power=70, ext="carkit_ext_08_09_10.py",
         script="car10_roadster_classic.py", stage="CAR10_STAGE", uv_stages=("uv1", "uv2"), ucx="4 hulls with 16 vertices each",
         tyre="balloon tyre 0.30 / 0.31 m radius, 0.12 / 0.125 m wide (0.125 / 0.130 m over the sidewall rings), shallow tread ribs + two moulded sidewall rings",
         wheel_style="36 + 36 tangent-laced wire spokes, polished rim, chrome hub with knock-off spinner, brake drum",
         silhouette="vintage open roadster",
         brief="Vintage open roadster: tub + narrow bonnet loft with a boolean open cockpit and cut-down doors, four separately swept cycle wings, running boards, "
               "chrome radiator shell, round bucket headlamps on stalks, blade bumpers, tiny raked windscreen, folded soft-top boot and a fully modelled cockpit.",
         features=[
             "Body: tub + bonnet loft with a rolled leather cockpit rim, door shut lines + handles + hinge pins, bonnet louvres + hinge strip + clips, coachline.",
             "Four swept cycle wings (`fender_loft`: crowned section, rolled lip), running boards with rubber mat, chrome edge and wing stays; chrome radiator shell with slats, cap, starting-handle dog; round bucket headlamps on stalks, amber parking lamps; blade bumpers with irons and over-riders; plates front and rear; round tail lamps; twin exhaust pipes + mufflers; chassis rails, springs, axles underneath.",
             "Windscreen: chrome frame with centre post, hinge brackets, round mirrors on the posts and one glass pane (the only `Glass` object); fix round 2: the pane is gently curved (14 mm bulge, 6 mm thick, 100 triangles) instead of a flat 44-triangle plate.",
             "Fix round 2 - soft-top boot: the 0.36 x 0.22 m torpedo tube is replaced by a low, wide boot cover (rounded box 0.32 x 1.04 x 0.085 m, `M_Paint2`) with a centre seam, piping, three straps with buckles and studs - it lies on the rear deck like a canvas boot and no longer reads as a dark tube.",
             "Fix round 2 - wire wheels: spokes thinned to 1.9 mm radius and made four-sided (less shimmer); the balloon tyre profile was made monotone (round 1 folded back on itself) and the sidewalls gained two moulded rings.",
             "Open cockpit, fully modelled: pleated leather bucket seats, carpet and tunnel, wooden dash with 4 chrome-bezel gauges, switches, ignition, glovebox and grab handle, big three-spoke wooden-rim steering wheel on a raked column, pedals, gear lever, handbrake, leather door cards, rear shelf.",
         ],
         weaknesses=[
             "In the Blender preview the wood dash and the steering-wheel rim (`M_IntTrim`) show grey, the leather (`M_IntSeat`) near black and the wings / running boards (`M_Paint2`) black: these are the kit's shared default materials. The UE instances must override `M_IntTrim` (walnut), `M_IntSeat` (leather), `M_Paint2` (contrast colour / canvas for the boot).",
             "The windscreen pane is only 100 triangles (a gently curved sheet in a frame, no laminated edge); the tub / bonnet junction at the cowl is a smooth step, not a real firewall; the engine bay is closed.",
             "Wing-to-running-board joints are overlaps rather than welds; the spokes are thin 4-sided tubes (they shimmer at distance without TAA / Nanite - fade them in UE if needed).",
             "Tyre sidewall detail is limited to two rings (no lettering / whitewall: a whitewall needs a separate UE material slot).",
             "The soft top exists only as the folded boot cover, there is no raised hood; the boot cover reads like a luggage roll more than a hood bag.",
         ]),
]


def load(c):
    with open(os.path.join(ROOT, "Exports", "Cars", c["id"], c["id"] + ".json"), encoding="utf8") as fh:
        return json.load(fh)


def fnum(v, n=3):
    return ("%." + str(n) + "f") % v


def vec(v):
    return "(%s)" % ", ".join(fnum(x, 3) for x in v)


def tri_table(j):
    t = j["tri_counts"]
    rows = []
    for part in ("Body", "Glass", "Interior", "SteeringWheel", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
        rows.append("| `%s_%s` | %d | %s |" % (j["id"], part, t[part], ", ".join(j["material_slots"][part])))
    rows.append("| UCX hulls (not rendered) | %d | - |" % t["UCX"])
    rows.append("| **total visual (LOD0, budget 60-150 k)** | **%d** | |" % t["total_visual"])
    return "\n".join(rows)


def car_section(c, j):
    d = j["dimensions"]
    w = j["wheels"]
    L = []
    L.append("### %d. `%s` - %s (class %s, %s)\n" % (c["index"], c["id"], c["name"], c["klass"], c["drivetrain"]))
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
    L.append("| Collision | `UCX_%s_Body_01..%02d`: %s (all convex, <= 32 vertices, no wheels) |" % (c["id"], len(j["ucx"]), c["ucx"]))
    L.append("| Reference mass / power (`Docs/CAR_ROSTER.md`) | %d kg / %d kW |" % (c["mass"], c["power"]))
    L.append("")
    L.append("Triangles and material slots per part:\n")
    L.append("| Part | Tris | Material slots |\n|---|---|---|")
    L.append(tri_table(j))
    L.append("")
    L.append("What is on the car:\n")
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
    out.append("# Player cars 07 Ridge / 08 Ranger / 09 Mule / 10 Brisa (Blender -> UE5.8 kit notes)\n")
    out.append("Generated %s by `Tools/blender/cars/make_doc_cars_07_08_09_10.py` from the JSON sidecars (all numbers are measured from the exports). "
               "This document is the single reference for the four cars; it supersedes `Docs/Kits/cars_08_09_10.md` and the Ridge section of `Docs/Kits/cars_05_06_07.md` "
               "(both stay for the history of the first build round). 4 cars, 8 FBX parts + 3-4 UCX hulls each, %d triangles of LOD0 in total.\n" % (datetime.date.today().isoformat(), total))
    out.append("All four cars are original (no manufacturer names, badges or copied models) and follow `Docs/BLENDER_CONTRACT.md` (+X forward, +Y left, origin on the ground "
               "under the middle of the wheelbase, one FBX per part, `<id>.json` sidecar, `UCX_*` hulls inside the Body FBX) and `Docs/CAR_ROSTER.md` rows 7-10. "
               "They are built with the shared car kit (`Tools/blender/lib/carkit.py`, rev 3, untouched).\n")
    out.append("| # | Id | Name | Class / drivetrain | Silhouette | Staged at |\n|---|---|---|---|---|---|")
    for c in CARS:
        out.append("| %d | `%s` | %s | %s / %s | %s | x = %d m |" % (c["index"], c["id"], c["name"], c["klass"], c["drivetrain"], c["silhouette"], 12 * c["index"]))
    out.append("")
    out.append("## 1. Files\n")
    out.append("| What | Path (relative to the project root `UnrealSonnet55Forza\\`) |\n|---|---|")
    out.append("| Build scripts (idempotent; `CAR0N_STAGE` = `geometry` / `uv1` / `uv2` (/ `uv3` for Ridge) / `all`) | `Tools/blender/cars/car07_rally_ridge.py`, `car08_suv_ranger.py`, `car09_pickup_mule.py`, `car10_roadster_classic.py` |")
    out.append("| Helpers (kit untouched) | Ridge: `Tools/blender/lib/carkit_ext_05_06_07.py` (shell sculpt, rally parts, interior builder) + `Tools/blender/lib/carkit_ext_07_fix.py` (round-2 additions: wing, scoop, number panel, jittered gravel tyre). Ranger / Mule / Brisa: `Tools/blender/lib/carkit_ext_08_09_10.py` v1.1 (block / knobbly tyres, wire wheels, cycle-wing sweep, stacked / bucket lamps, gauges, vintage seat, `window_seal`, utility dash + interior) |")
    out.append("| Doc generator | `Tools/blender/cars/make_doc_cars_07_08_09_10.py` |")
    out.append("| FBX + sidecar per car | `Exports/Cars/<id>/<id>_Body.fbx` (+ `UCX_<id>_Body_NN`), `_Glass.fbx`, `_Interior.fbx`, `_SteeringWheel.fbx`, `_Wheel_FL/FR/RL/RR.fbx`, `<id>.json` |")
    out.append("| Blender | collections `FORZA_UE/Cars/<id>`, root empty `<id>_ROOT` at x = 84 / 96 / 108 / 120 m, y = 0; master file `UnrealSonnet5.5Forza.blend` (saved after the final export) |")
    out.append("")
    out.append("Rebuild / re-export from the Blender MCP console (each call < 20 s on an idle machine: geometry 2-6 s, UV stages 5-15 s, validate 10-25 s):\n")
    out.append("```python\nCAR08_STAGE = \"geometry\"      # then \"uv1\", \"uv2\" (Ridge also \"uv3\"); CAR07_STAGE / CAR09_STAGE / CAR10_STAGE for the others\n"
               "exec(compile(open(r\"<project>/Tools/blender/cars/car08_suv_ranger.py\", encoding=\"utf8\").read(), \"car08\", \"exec\"), globals())\n"
               "# new call: load the kit, then validate and export\n"
               "exec(compile(open(r\"<project>/Tools/blender/lib/carkit.py\", encoding=\"utf8\").read(), \"kit\", \"exec\"), globals())\n"
               "validate_car(\"car08_suv_ranger_ROOT\", targets=dict(length=4.60, width=1.92, height=1.92, wheelbase=2.78))\n"
               "export_car(\"car08_suv_ranger_ROOT\", display_name=\"Ranger\")      # FBX per part + JSON\n```\n")
    out.append("## 2. Overview and measured results (from the sidecars)\n")
    out.append("| | Ridge | Ranger | Mule | Brisa |\n|---|---|---|---|---|")
    ids = [c["id"] for c in CARS]

    def row(label, fn):
        out.append("| %s | %s |" % (label, " | ".join(fn(js[i]) for i in ids)))
    row("Length x width x height (m)", lambda j: "%s x %s x %s" % (fnum(j["dimensions"]["length"]), fnum(j["dimensions"]["width"]), fnum(j["dimensions"]["height"])))
    out.append("| Roster target L x W x H | 4.15 x 1.84 x 1.48 | 4.60 x 1.92 x 1.92 | 5.30 x 1.96 x 1.88 | 3.85 x 1.62 x 1.22 |")
    row("Width incl. mirrors (m)", lambda j: fnum(j["dimensions"]["width_with_mirrors"]))
    row("Wheelbase (m)", lambda j: fnum(j["wheelbase"], 2))
    row("Track F / R (m)", lambda j: "%s / %s" % (fnum(j["track_front"], 2), fnum(j["track_rear"], 2)))
    row("Wheel radius F / R (m)", lambda j: "%s / %s" % (fnum(j["wheels"]["FL"]["radius"]), fnum(j["wheels"]["RL"]["radius"])))
    row("Wheel width F / R (m)", lambda j: "%s / %s" % (fnum(j["wheels"]["FL"]["width"]), fnum(j["wheels"]["RL"]["width"])))
    row("Ride height (m)", lambda j: fnum(j["ride_height"], 2))
    row("Wheel centre front (x, y, z)", lambda j: "%s, +-%s, %s" % (fnum(j["wheels"]["FL"]["center"][0], 3), fnum(j["wheels"]["FL"]["center"][1], 3), fnum(j["wheels"]["FL"]["center"][2], 3)))
    for part in ("Body", "Glass", "Interior", "SteeringWheel"):
        row("Tris %s" % part, lambda j, p=part: str(j["tri_counts"][p]))
    row("Tris per wheel", lambda j: str(j["tri_counts"]["Wheel_FL"]))
    row("**Total visual tris (budget 60-150 k)**", lambda j: "**%d**" % j["tri_counts"]["total_visual"])
    row("UCX hulls", lambda j: str(len(j["ucx"])))
    out.append("")
    out.append("All parts: transforms applied, no modifiers, no loose geometry, no non-manifold edges, outward normals, `UVMap` non-overlapping inside 0..1 (the Body also has the kit's "
               "`UVLivery` second channel for stripes / liveries). Body origin = car origin; wheel and steering-wheel pivots at their centres (right wheels are mirror-built, no negative scales). "
               "`validate_car` reports 0 errors for all four cars after the fix round; the only open boundary edges are window reveals, lamp lens patches and liners (by design).\n")
    out.append("Silhouette separation (the four cars and the rest of the roster): Ridge = low, wide, flared hatch with a big wing and a bonnet panel; Ranger = 1.93 m tall slab-sided box with a roof rack and a chrome bull bar; "
               "Mule = 5.3 m two-box pickup with an open bed behind a visible cab; Brisa = 1.22 m tall open roadster with separate cycle wings, a vertical radiator and 36-spoke wire wheels.\n")
    out.append("### Material slots (contract names, UE master-material instances by name)\n")
    out.append("* **Body** - Ridge `M_Paint M_Paint2 M_Chrome M_TrimBlack M_TrimGrey M_Rubber M_Headlight M_Taillight M_Reverse M_Indicator M_Caliper M_Plate M_Underbody M_Exhaust`; "
               "Ranger and Mule the same list (Ranger plus `M_Tyre M_Rim M_RimDark` for the spare wheel); Brisa `M_Paint M_Paint2 M_Chrome M_TrimBlack M_TrimGrey M_Rubber M_Headlight M_Taillight M_Indicator M_RimDark M_Plate M_Underbody M_IntSeat M_IntTrim M_IntCarpet M_Exhaust`. "
               "The lamp slots (`M_Headlight M_Taillight M_Reverse M_Indicator`) exist only in the Body (kit rev 3 rule: emissive lamp instances).")
    out.append("* **Glass** - `M_Glass` only (the only translucent part; Brisa = windscreen only). **Interior** - opaque, no lamp slots (Nanite friendly): `M_Chrome M_TrimBlack M_TrimGrey M_Caliper M_Underbody M_IntDash M_IntSeat M_IntTrim M_IntCarpet` (Brisa without `M_Underbody`). **SteeringWheel** - Ridge / Ranger / Mule `M_TrimGrey M_IntDash`, Brisa `M_Chrome M_IntTrim`. **Wheels** - `M_Tyre M_Rim M_RimDark M_Chrome M_BrakeDisc M_Caliper M_Underbody` (Brisa without `M_RimDark M_Caliper`).")
    out.append("")
    out.append("Per-car material intent for the UE material instances (the Blender preview uses the kit's shared default colours, so some of these read wrongly in Blender):\n")
    out.append("| Slot | Ridge | Ranger | Mule | Brisa |\n|---|---|---|---|---|")
    out.append("| `M_Paint` | body colour | body colour | body colour (cab + bed upper) | tub + bonnet |")
    out.append("| `M_Paint2` | satin black: bonnet panel, A-pillars, roof scoop, wing, end plates, mirrors | satin black: A/B/C pillars | accent colour: two-tone lower body | contrast colour / canvas: the four swept wings, running boards, folded soft-top boot, coachline |")
    out.append("| `M_Chrome` | few (scoop vanes, bonnet pins) | bull bar, belt strip, shackles | bumpers, sport bar, belt strip, handles | radiator, spokes, hubs, bumpers, frame, gauges |")
    out.append("| `M_IntTrim` | pillar / roof lining, cage | linings | linings | **walnut** (dash board, wheel rim, shifter knob) |")
    out.append("| `M_IntSeat` | bucket seats | seats | seats | **leather** (seats, cockpit rim, door cards) |")
    out.append("| `M_Rim` | polished star wheels | spare wheel hub cover | - | polished wire rims |")
    out.append("| `M_Caliper` | tow hooks, harness webbing, extinguisher | recovery shackles, dash warning lights | tow hooks, dash warning lights | gauge needles |")
    out.append("| `M_Plate` | number panels on the doors (+ plates) | plates | plates | plates |")
    out.append("")
    out.append("## 3. Part list and anchors\n")
    out.append("Per car: `<id>_Body`, `_Glass`, `_Interior`, `_SteeringWheel`, `_Wheel_FL/FR/RL/RR`, `UCX_<id>_Body_01..0n`; empties (not exported, positions in the JSON): "
               "`LP_HeadL/R`, `LP_TailL/R`, `LP_Reverse`, `CAM_Hood`, `CAM_Cockpit`, `CAM_Bumper`, `EXHAUST_L/R`. Steering-wheel axis in `steering_wheel.axis` and the `rim_axis` object property. "
               "Root custom properties (`wheelbase ... height`, `drivetrain`, `steering_side`) are on `<id>_ROOT`. All positions are Blender car-space metres (UE x = x*100, UE y = -y*100, UE z = z*100).\n")
    out.append("| Anchor | Ridge | Ranger | Mule | Brisa |\n|---|---|---|---|---|")
    row("Head L (R mirrored)", lambda j: vec(j["lights"]["head_l"]))
    row("Tail L", lambda j: vec(j["lights"]["tail_l"]))
    row("Reverse", lambda j: vec(j["lights"]["reverse"]))
    row("Cockpit camera", lambda j: vec(j["cameras"]["cockpit"]))
    row("Hood camera", lambda j: vec(j["cameras"]["hood"]))
    row("Bumper camera", lambda j: vec(j["cameras"]["bumper"]))
    row("Steering hub", lambda j: vec(j["steering_wheel"]["center"]))
    row("Exhaust L / R", lambda j: "%s / %s" % (vec(j["exhaust"][0]), vec(j["exhaust"][1])))
    out.append("")
    out.append("## 4. The cars\n")
    for c in CARS:
        out.append(car_section(c, js[c["id"]]))
    out.append("## 5. Recommended UE setup\n")
    out.append("| Item | Recommendation |\n|---|---|")
    out.append("| Import | One StaticMesh per FBX, **Combine Meshes off, Auto Generate Collision off, Import Materials off** (assign the shared master instances by slot name). Scale 100 uu/m is baked by the export recipe (X forward kept, Blender +Y -> UE -Y). |")
    out.append("| Nanite | on for Body, Interior, wheels, steering wheel; **off for Glass** (translucent). Glass 0.04 - 3.7 k tris: cull distance ~150 m. |")
    out.append("| Collision | Body = the `UCX_*` hulls inside `_Body.fbx` (3 for Ridge / Ranger, 4 for Mule / Brisa) as the simple collision, never per-poly. Wheels / interior / glass / steering wheel: no collision. Wheel meshes are centred on the axle: drive the wheel components from the JSON radius / width / centre (not from the meshes). Use the JSON `width` and the hulls for vehicle bounds, **not** `width_with_mirrors` (Mule tow mirrors). |")
    out.append("| Pivots | Body / Glass / Interior at the car origin (wheelbase middle, ground); wheels at the axle centre (spoke face outwards); steering wheel at the hub, rotate about `steering_wheel.axis`. |")
    out.append("| Scale | uniform 1.0 (tolerance 0.97 - 1.03); never non-uniform: arch clearances are tight (6 cm Ranger / Mule, 5 cm Ridge, ~8 cm Brisa). |")
    out.append("| Suggested masses / centre of mass | Ridge 1260 kg, Ranger 2150 kg (CoM ~0.75 m above ground), Mule 2350 kg (~0.80 m), Brisa 900 kg (~0.45 m); CoM slightly forward of the wheelbase middle, 35-40 % of the height. |")
    out.append("| Lamps | `M_Headlight`, `M_Taillight`, `M_Reverse`, `M_Indicator` only exist on the Body (emissive instances driven by lights / brake / reverse / indicator state). Brisa uses `M_Taillight` for the two round tail lamps and `M_Headlight` for the bucket lenses; Ridge has an extra `M_Headlight` / `M_Reverse` pair in the spot-light pod. |")
    out.append("| Camera | cockpit anchors are driver-eye positions; the Brisa cockpit view looks over the low windscreen frame (the cockpit is intentionally open). |")
    out.append("| LOD | LOD0 only (player cars, Nanite); traffic vehicles have their own cheaper meshes. Triangle totals %s. |" % ", ".join("%s %d k" % (c["name"], round(js[c["id"]]["tri_counts"]["total_visual"] / 1000.0)) for c in CARS))
    out.append("")
    out.append("## 6. QA record\n")
    out.append("**Round 1 (first build).** Each car went through at least three build / look / fix rounds (solid + material + rendered with temporary `qa_studio` lights, wireframe checks, close-ups of nose, tail, wheels and cockpit; QA lights removed again). "
               "Fixes made along the way: Ridge - first build read as an estate (flat roof running to a vertical tail), hatch glass + wing lowered, oversized mud flaps / tail lamps trimmed, door number panel bow-tie replaced by a dense `surface_decal`, "
               "bonnet pins, body length trimmed to 4.21 m, cockpit / bumper camera anchors; Ranger - right-hand flares were mirrored onto the left, flat end caps instead of domed ones, snorkel path, 1 mm boolean slivers (`heal_nonmanifold` + `clean_tiny`); "
               "Mule - flare sweeps that missed the shell, cab / bed length and bumper overhang; Brisa - red hood cap visible through the grille, boot straps, rear plate seat, lamp-slot rule of kit rev 3 (gauge needles on `M_Caliper`), wire-wheel width (sidecar reports the tyre width).\n")
    out.append("**Round 2 (art-director findings, this document).** The independent review scored all four cars PASS (shape 7 / 7 / 7 / 9, detail 8 / 8 / 8 / 9) but marked the group FAIL because this combined document was missing. "
               "Besides writing it, the minors were fixed in the scripts (no one-off edits: every change lives in the car scripts and the `carkit_ext_*` helpers, the assets were rebuilt through them, re-validated, re-exported and the .blend saved). "
               "Each pass of the loop was build -> `look` (material shading, close-ups with an invisible focus cube) -> fix -> rebuild; the checks of this round were close-ups of the wing, scoop, number panels, tyres, window seals, dash, cab / bed gap, boot and wheels.\n")
    out.append("| Finding (round 1) | Resolution | Status |\n|---|---|---|")
    out.append("| MAJOR - `cars_07_08_09_10.md` missing | this document (generated from the sidecars by `make_doc_cars_07_08_09_10.py`) | fixed |")
    out.append("| Ridge - reads partly as a lifted crossover / estate, flat roof, shallow glasshouse | hatch steepened (base +6 cm, ~38 deg), roof-edge gutter, raised wing; roof / belt line not re-lofted | partly fixed |")
    out.append("| Ridge - wing hides the hatch glass, large angular red end plates | blade raised to z = 1.29 m on tall flat pylons standing on the deck, small rounded black end plates with a small accent inset | fixed |")
    out.append("| Ridge - flat white number panels without numerals | recessed pocket + frame + white plate + numeral '7' (both flanks) | fixed |")
    out.append("| Ridge - roof scoop is a solid hump | recessed black intake mouth, lip and two chrome vanes | fixed |")
    out.append("| Ridge - tyre lugs very regular; mud flaps simple | seeded jitter on every lug (height / width / slant / spacing, skipped lugs, different lug counts per side); mud flaps unchanged | lugs fixed, flaps not |")
    out.append("| Ridge - length 4.21 m vs 4.15 m | now 4.22 m (pod + wing overhang), within tolerance; no change required | accepted |")
    out.append("| Ranger - flat body side, glass box with thin pillars, bonnet low | crease 3.6 cm, protection strip, character bead, black seal beads round all windows; bonnet unchanged | mostly fixed |")
    out.append("| Ranger - knobbly tyres show little tread, faceted outline; 5.7 k tris each | `block_tyre`: real tread blocks + shoulder blocks + sidewall blocks, 40-segment base; wheel triangles unchanged (11.4 k) | fixed |")
    out.append("| Ranger - generic sport dash / seats | utility dash (hooded cluster, vertical vents, knobs, grab handle), upright seats, transfer lever; seats still the kit's box seats | mostly fixed |")
    out.append("| Mule - tow mirrors make Body 2.405 m wide | mirrors pulled in (2.217 m); docs say to use JSON `width` + UCX for bounds | fixed |")
    out.append("| Mule - triangle fans at the bed wheel boxes / rear walls | not re-topologised (shading clean) | not fixed |")
    out.append("| Mule - generic interior, cab / bed gap shows shell edges, tyres smooth sidewall | utility interior, cab-back seal panel, block tyres with sidewall blocks | fixed |")
    out.append("| Brisa - M_IntTrim / M_IntSeat / M_Paint2 preview colours (grey wood, black leather) | no Blender change possible (shared kit materials); UE override table above | documented |")
    out.append("| Brisa - folded boot reads as a dark torpedo | low rounded boot cover with seam, piping, straps and buckles | fixed |")
    out.append("| Brisa - spokes shimmer, plain tyre sidewall, flat 44-tri windscreen, overlapping wing joints | 1.9 mm 4-sided spokes, two sidewall rings, curved 100-tri pane; wing joints unchanged | mostly fixed |")
    out.append("")
    out.append("Per-car list of the code changes:\n")
    out.append("* **Ridge** - `car07_rally_ridge.py` + new `carkit_ext_07_fix.py`: `build_rally_wing2`, `build_roof_scoop2`, `number_panel`, `build_gravel_tyre2` / `build_wheel_gravel2`, hatch base `x_rg_base = -1.86`, roof-edge gutter, wing seated on the measured deck.")
    out.append("* **Ranger** - `car08_suv_ranger.py` + `carkit_ext_08_09_10.py` v1.1: `window_seal`, `build_interior_utility` (`build_dash_utility`), `block_tyre`, crease / strip / bead.")
    out.append("* **Mule** - `car09_pickup_mule.py` + the same helpers: compact mirrors, cab-back seal panel, `window_seal`, `block_tyre`, `build_interior_utility`.")
    out.append("* **Brisa** - `car10_roadster_classic.py` + helpers: boot cover, curved windscreen pane, `vintage_tyre` (monotone profile + rings), thinner spokes (`wire_wheel(spoke_r, spoke_sides)`).")
    out.append("* All four: `validate_car` OK (0 errors), re-exported, `UnrealSonnet5.5Forza.blend` saved. Triangles per car: %s.\n" % ", ".join("%s %d" % (c["name"], js[c["id"]]["tri_counts"]["total_visual"]) for c in CARS))
    out.append("## 7. Remaining imperfections (honest list)\n")
    out.append("* **Shared-kit look**: the Ridge cabin (kit dash with binnacle + screen, box seats; only the cage, harnesses and bare panels are specific), the seats of the Ranger / Mule and their shared utility dash come from generic builders; only the Brisa interior is fully car-specific.")
    out.append("* **Doors, hood, tailgate, bed gate, boot are shut lines in one Body mesh**, not separate animatable meshes; there is no engine bay on any car, no suspension geometry behind the arches except the visible axles / springs of the Ranger, Mule and Brisa.")
    out.append("* **Glass** is a thin sheet per window with a black reveal (alpha 0.3 preview, so the cabin always shows in Blender); there are no defroster lines, wiper articulation or B-pillar belt anchors; the Brisa windscreen is a single gently curved pane.")
    out.append("* **UVs** are the kit's smart-project atlases (non-overlapping, uneven texel density); do not bake lighting into `UVMap`; use `UVLivery` for stripes / numbers.")
    out.append("* **Preview colours**: every shared material is the kit default (red paint, dark leather); UE instances must override them (see the intent table above, notably Brisa walnut / leather / canvas).")
    out.append("* **Triangle counts** of the Ranger and Mule sit near the 150 k ceiling (the loft is dense and the block tyres cost ~5.5 k each); a hand-made LOD1 would be needed for non-Nanite platforms.")
    out.append("")
    with open(OUT, "w", encoding="utf8") as fh:
        fh.write("\n".join(out))
    print("wrote", OUT, len("\n".join(out)))


if __name__ == "__main__":
    main()
