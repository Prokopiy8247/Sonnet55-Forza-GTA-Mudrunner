r"""
lane11_vehicles.py - per-vehicle anchors + fit formulas + part descriptions (pure Python, no bpy; load after lane11_catalog.py).

Anchors were measured with ray casts on the Wave-1 vehicle Body meshes (Blender frame: +X right, +Y forward, +Z up, origin = ground point at
the wheelbase centre):
  half_w  body half width at z=0.6           nose / tail  y of the front / rear face at z=0.5
  bump_z  z of the bumper underside          roof_z, roof_y  flat roof height and its y span
  deck    (y, z) rear spoiler anchor         hood  (y, z, pitch_deg) hood anchor + slope        wb wheelbase, wr wheel radius
"""
L11_VEHICLES = {
    "compact": dict(half_w=0.840, nose=1.840, tail=-1.876, bump_z=0.29, roof_z=1.500, roof_y=(-1.30, 0.00), deck=(-1.66, 0.953), hood=(0.90, 0.870, -7.0), wb=2.40, wr=0.300),
    "sedan":   dict(half_w=0.885, nose=2.369, tail=-2.394, bump_z=0.27, roof_z=1.450, roof_y=(-0.95, 0.25), deck=(-2.00, 0.968), hood=(1.35, 0.912, -5.1), wb=2.83, wr=0.330),
    "sports":  dict(half_w=0.940, nose=2.150, tail=-2.150, bump_z=0.21, roof_z=1.200, roof_y=(-1.00, -0.25), deck=(-1.95, 1.120), hood=(1.25, 0.830, -1.5), wb=2.60, wr=0.345),
    "muscle":  dict(half_w=0.937, nose=2.460, tail=-2.440, bump_z=0.26, roof_z=1.380, roof_y=(-1.00, -0.15), deck=(-2.05, 1.000), hood=(1.90, 0.940, -5.0), wb=2.90, wr=0.350),
    "suv":     dict(half_w=0.957, nose=2.400, tail=-2.349, bump_z=0.29, roof_z=1.765, roof_y=(-2.00, 0.40), deck=(-2.00, 1.765), hood=(1.50, 1.134, -5.1), wb=2.90, wr=0.380),
    "pickup":  dict(half_w=0.947, nose=2.580, tail=-2.708, bump_z=0.37, roof_z=1.846, roof_y=(-1.15, 0.45), deck=(-2.50, 0.900), hood=(1.70, 1.180, -3.3), wb=3.25, wr=0.380),
    "van":     dict(half_w=0.970, nose=2.520, tail=-2.652, bump_z=0.34, roof_z=2.250, roof_y=(-2.50, 0.30), deck=(-2.45, 2.220), hood=(2.10, 1.250, 0.0), wb=3.30, wr=0.340),
}
L11_VEHICLE_NOTES = {
    "compact": "short rear deck + steep hatch glass: lip / ducktail only; short hood (scoop OR vents)",
    "sedan":   "reference body: every mount was checked visually on it (rear / underside close-ups incl. exhaust_tip_quad + diffuser)",
    "sports":  "integrated tail lip at y=-1.95 (z 1.12): prefer spoiler_wing_low/high anchored on it; low flat hood",
    "muscle":  "already has a hood bulge/scoop at y=1.26..1.56 (z up to 1.07): skip hood_scoop_a, hood_vents_b goes on the front hood",
    "suv":     "no trunk deck: spoilers sit on the roof rear edge (y=-2.0); roof_rack scales to the long flat roof",
    "pickup":  "no trunk deck: only lip / ducktail on the tailgate top (z 0.90); high bumper (0.37)",
    "van":     "no real hood (windscreen starts at y=1.6): no hood parts; spoilers on the roof rear edge; high bumper",
}


def l11_fit_for(vid):
    """Recommended transform per part for vehicle `vid`. For the sedan this reproduces L11_MOUNT within ~1.5 cm."""
    V = L11_VEHICLES[vid]
    ws = V["half_w"] / 0.885
    y0, y1 = V["roof_y"]
    cy = (y0 + y1) / 2.0
    dy, dz = V["deck"]
    hy, hz, hp = V["hood"]
    bz, nose, tail = V["bump_z"], V["nose"], V["tail"]
    out = {}

    def put(pid, pos, pitch=0.0, scale=(1.0, 1.0, 1.0)):
        out[pid] = dict(pos=tuple(round(c, 3) for c in pos), pitch=round(pitch, 1), scale=tuple(round(c, 3) for c in scale))
    put("spoiler_lip", (0, dy - 0.13, dz - 0.006), 0, (ws, 1, 1))
    put("spoiler_ducktail", (0, dy, dz), 0, (ws, 1, 1))
    put("spoiler_wing_low", (0, dy + 0.02, dz), 0, (ws, 1, 1))
    put("spoiler_wing_high", (0, dy, dz), 0, (ws, 1, 1))
    put("splitter_front", (0, nose - 0.069, bz + 0.015), 0, (ws, 1, 1))
    put("bumper_front_sport", (0, nose + 0.016, bz), 0, (ws, 1, 1))
    put("bumper_rear_diffuser", (0, tail + 0.084, bz), 0, (ws, 1, 1))
    put("hood_scoop_a", (0, hy, hz), hp)
    put("hood_vents_b", (0, hy + 0.20, hz - 0.02), hp, (ws, 1, 1))
    put("roof_scoop", (0, cy + 0.05, V["roof_z"]))
    sl = max(0.6, min(2.4, (y1 - y0 - 0.15) / 1.04))
    put("roof_rack", (0, cy + 0.05, V["roof_z"]), 0, (ws, sl, 1))
    put("roof_light_bar", (0, y1 - 0.15, V["roof_z"]), 0, (ws, 1, 1))
    gap = V["wb"] - 2.42 * V["wr"]
    put("skirt_side_sport", (0, 0, bz - 0.07), 0, (ws, gap / 2.0, 1))
    put("exhaust_tip_single", (0.56 * ws, tail + 0.034, bz - 0.008), 0, (1, 1, 1))
    put("exhaust_tip_dual", (0, tail + 0.034, bz - 0.008), 0, (ws, 1, 1))
    put("exhaust_tip_quad", (0, tail + 0.034, bz - 0.008), 0, (ws, 1, 1))
    put("underglow_strip", (0, (nose + tail) / 2.0, bz - 0.095), 0, (ws, (nose - tail) / 4.763, 1))
    put("grille_mesh", (0, nose - 0.024, bz + 0.362), 0, (1, 1, 1))
    put("mirror_sport", (0, 0.62, 0.99), 0, (ws, 1, 1))     # sedan value; other vehicles: DoorL.position + (0, -0.18, +0.39), see docs
    put("antenna", (0.47 * ws, y0 + 0.30, V["roof_z"]), 0, (1, 1, 1))
    return out


def l11_wheel_scale(vid):
    """uniform radius scale for the wheel_* meshes (applied to Y and Z, keep X = 1)."""
    return round(L11_VEHICLES[vid]["wr"] / 0.34, 3)


L11_INFO = {
    "spoiler_lip":          dict(group="spoiler", origin="centre of the footprint on the trunk lid; z=0 = lid top (ends droop 5 cm onto the crowned lid)", use="small blade on the rear edge of the boot lid"),
    "spoiler_ducktail":     dict(group="spoiler", origin="centre of the footprint on the trunk lid; z=0 = lid top", use="kicked-up duck tail, wider at the tail than at the base, Paint2 insert"),
    "spoiler_wing_low":     dict(group="spoiler", origin="centre of the footprint on the deck; z=0 = deck top (feet sink 2 cm)", use="GT wing on two struts (blade z 0.17..0.23); Paint2 blade, Paint end plates; extra empty `Wing` at the blade centre"),
    "spoiler_wing_high":    dict(group="spoiler", origin="centre of the footprint on the deck; z=0 = deck top", use="two-element wing on swan-neck struts (blade z 0.34..0.46), tall Paint end plates; extra empty `Wing`"),
    "splitter_front":       dict(group="aero", origin="centre of the plate top at the nose bottom; plate spans y -0.20..+0.13 (rear part hides under the bumper)", use="front lip with Paint2 edge and canards"),
    "bumper_front_sport":   dict(group="aero", origin="front face centre at the shell bottom (y=0 is the FRONT face, the shell extends 0.15..0.4 behind it, z 0..0.275)", use="shell ON the nose: slatted central intake, side intakes, fog lamps (LightHead), black chin lip"),
    "bumper_rear_diffuser": dict(group="aero", origin="rear face of the valance at the bumper bottom (y=0; the valance is body coloured, the plate runs 0.20 behind it)", use="central 5-fin diffuser, Paint2 end strakes, red fog bar (LightTail); exhaust tips stay outboard"),
    "hood_scoop_a":         dict(group="hood", origin="centre of the footprint on the hood; z=0 = hood surface (base sinks 4 cm)", use="ramp scoop, black intake + 2 vanes on the front face, Paint2 stripe; pitch it to the hood slope"),
    "hood_vents_b":         dict(group="hood", origin="centre between the two louvre banks (x = +-0.10..0.50); z=0 = hood surface", use="two banks of 5 louvres over a black recess"),
    "roof_scoop":           dict(group="roof", origin="centre of the footprint on the roof; z=0 = roof top", use="Paint2 air box with twin vaned intakes on the front face"),
    "roof_rack":            dict(group="roof", origin="centre of the rack footprint on the roof; z=0 = roof top (rails z 0.05..0.075, cross bars at 0.077)", use="2 rails, 3 cross bars, 4 feet (Metal / MetalDark / Trim)"),
    "roof_light_bar":       dict(group="roof", origin="centre of the base on the roof; lamps face +Y", use="off-road bar: 6 lamps + 2 side lamps in LampGlow (emissive), Paint2 cap"),
    "skirt_side_sport":     dict(group="aero", origin="x=0 centre line, y=0 mid-sill, z=0 = bottom of the sill; BOTH skirts in one mesh (x +-0.84..0.97, y +-1.0)", use="blades with black lip and Paint2 stripe, tapered ends"),
    "exhaust_tip_single":   dict(group="exhaust", origin="centre of the OUTLET opening; the pipe runs towards +Y (into the car) for 0.29 m", use="chrome flared tip, slash cut, dark inner disc, clamp + stub"),
    "exhaust_tip_dual":     dict(group="exhaust", origin="centre line at the outlet plane; tips at x = +-0.54, pipes towards +Y", use="two single tips + hidden cross pipe"),
    "exhaust_tip_quad":     dict(group="exhaust", origin="centre line at the outlet plane; tips at x = +-0.47 and +-0.60, pipes towards +Y", use="two pairs of smaller tips with brackets"),
    "underglow_strip":      dict(group="lights", origin="centre of the ring on the centre line; z=0 = tube axis; ring 1.48 x 3.80 m", use="NeonCyan emissive hex-tube loop (+4 black clips); change the NeonCyan emission colour for other glow colours"),
    "grille_mesh":          dict(group="front", origin="centre of the grille opening, faces +Y (y=0 = back plate, the frame protrudes 0.026)", use="chrome frame + diamond lattice, drops in front of the stock grille (0.68 x 0.16)"),
    "mirror_sport":         dict(group="mirrors", origin="centre line at the mirror height; mirrors at x = +-(0.86..1.12), glass faces -Y", use="PAIR in one mesh: stalk, Paint housing, Chrome glass, Paint2 fin"),
    "antenna":              dict(group="roof", origin="centre of the base on the surface; the mast leans 11 deg backwards, 0.65 m tall", use="whip antenna: base, spring, 3 telescopic sections, tip"),
}
L11_WHEEL_INFO = {
    "wheel_stock":       "dished plain cover, 5 black slots, chrome centre cap (OEM look)",
    "wheel_five_spoke":  "classic 5-spoke alloy with chrome hub",
    "wheel_split_six":   "6 split (Y) spokes = 12 thin spokes",
    "wheel_mesh":        "chrome lip + 6-point lattice (mesh) face",
    "wheel_dish":        "deep dish with chrome lip and 5 bolts",
    "wheel_turbine":     "9 swept turbine blades",
    "wheel_steel_basic": "pressed steel wheel, 6 holes, hub cap",
    "wheel_offroad":     "chunky staggered tread, tall sidewall (rim r 0.205), 5 fat spokes, beadlock bolts",
    "wheel_lowprofile":  "10 thin spokes, chrome lip, very thin sidewall (rim r 0.285)",
    "wheel_mc_sport":    "motorcycle: r 0.31, width 0.17, round-section tyre, 5 spokes + brake disc on both faces",
}
