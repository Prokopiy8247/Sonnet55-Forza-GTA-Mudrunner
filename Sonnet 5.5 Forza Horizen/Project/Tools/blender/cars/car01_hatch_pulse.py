"""
car01_hatch_pulse.py - parametric, idempotent build of the player car #1 "Pulse" (compact 3-door hot hatch, FWD).
This is the WORKED EXAMPLE of the car kit (Tools/blender/lib/carkit.py, documented in Docs/CARKIT_API.md).

Run inside the verified Blender MCP session (localhost:9889):
    CAR01_STAGE = "all"        # optional: "geometry" | "uv1" | "uv2" | "uv3" | "all" (default)  -> geometry = everything but the UVs
                               # (UV unwrap is split in three calls so each Blender call stays well below 20 s;
                               #  uv1 = Body/Glass/Interior/SteeringWheel, uv2 = Wheel_FL/FR, uv3 = Wheel_RL/RR)
    exec(compile(open(r"<project>/Tools/blender/cars/car01_hatch_pulse.py", encoding="utf8").read(), "car01", "exec"), globals())
It deletes the previous car01_hatch_pulse_* objects/meshes/collection and rebuilds them from the numbers below.
Car space: +X forward, +Y left (driver side, LHD), +Z up; origin on the ground under the middle of the wheelbase.
Staged at x = 12 m (cars row, index 1), collection FORZA_UE/Cars/car01_hatch_pulse, root empty car01_hatch_pulse_ROOT.

Revision 2 (art-director round 1): steep hatch tail (glass ~55 deg) with a roof-edge spoiler, designed (filleted / smoothed)
profile curves instead of hand-keyed wiggles, quarter-circle rounding of the tail edge, segmented recessed tail lamps,
twin-spoke wheels with a symmetric tread, opaque-only interior, livery UV channel, taller UCX hulls.

Revision 3 (art-director round 2): C-pillar is one continuous black sail down to the glass base (no red horn behind it), the
A-pillar is a constant-width band (no fin / diagonal fender cut), roof kicked down towards the tail + belt line that falls into
the tail lamps (no pointed pillar tip, no bullseye), hood edge runs out into the fender crest, nose = superellipse plan with a
flat upright fascia (round_x1, no pyramid cap), angular wrap-around "blade" headlights (build_headlight_blade), wide trapezoid
lower intake, arch flares over the haunches + 5 cm arch clearance (elliptical top) with the splitter ending inboard of the
tyres, sculpted shoulder crease (cdepth / cwidth), clean tangent-plane fuel flap, complete tailgate perimeter shut line, new
door mirrors (flat dark glass in a chrome rim, black lower shell, sturdy arm), rounded window-reveal edges (pillars get a
cross-section), black pillar trims + dark seat panels, Interior without lamp slots (M_Reverse / M_Indicator are Body-only).

Build order
  1. shell loft from side-profile / plan-view curves (loft_body) + material zones by ring column
  2. ONE boolean (bm_boolean): wheel arches, panel gaps (surface_sweep + groove_profile), lamp / grille / plate / vent pockets
  3. add-ons that hug the uncut surface: lenses, mouldings, skirts, splitter, handles, wipers, spoiler, mirrors ...
  4. glass cut out of the shell as separate thin sheets (extract_glass) + interior trims from the black pillar faces
  5. wheels, interior, steering wheel, UCX hulls, light / camera anchor empties, measured dimensions -> root properties
"""
import os
import time
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
_KIT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit.py")
_FIX = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_fix_01_02_03.py")      # fix round 1: cleanup_slivers, purge_qa ...
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_FIX, encoding="utf8").read(), _FIX, "exec"), globals())

CAR = "car01_hatch_pulse"
STAGE = globals().get("CAR01_STAGE", "all")

# ----------------------------------------------------------------------------------------------------------------------
# parameters (metres)
# ----------------------------------------------------------------------------------------------------------------------
P = dict(
    id=CAR, display_name="Pulse", index=1,
    L=3.95, W=1.78, H=1.44, wheelbase=2.52, track_f=1.52, track_r=1.50,
    r_f=0.33, r_r=0.33, w_f=0.215, w_r=0.215, ride=0.14,          # 205/55 R17 (rim bead 17", tyre radius 0.33 m)
    x_ws_base=0.92, x_ws_top=0.16,                                # windscreen glass (x of its lower / upper edge)
    x_rg_top=-1.60, x_rg_base=-1.79,                              # rear glass (steep hatch glass, ~52 deg)
    x_end=1.955, cap_bulge=0.014,          # loft end stations; the (flatter, rev 3) caps add cap_bulge -> length 3.95
    round_rear=0.065,                     # quarter-circle edge rounding of the tail (m); fix round 1: 0.09 -> 0.065 = crisper hatch face
    round_front=0.07,                     # rev 3: quarter-circle edge rounding of the nose -> flat upright fascia, no pyramid facets
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
ARCH_PAD = 0.052          # rev 3: tyre -> arch clearance (rev 2: 0.034 = too tight for suspension travel / steering lock)
ARCH_STRETCH = 1.04       # the top of the arch is a little taller than the front / rear lip (elliptical upper half)
ARCH_FLARE = 0.050        # width of the black arch moulding strip (flare), sits exactly on the cut edge
GROOVE = groove_profile(0.0055, 0.007)


def body_curves():
    """Side profile + plan view of the shell (x -> value), all in car space.  Every curve is DESIGNED: the top line is a
    polyline with fillets (straight windscreen / hatch glass, tangent-continuous corners); the other curves are sparse keys
    that are Gaussian-smoothed (no curvature wiggles between the keys -> clean reflections)."""
    # rev 3: roof kicked down towards the tail (peak 1.434 at x = -0.25 -> 1.27 at the hatch glass), hatch glass ~52 deg, hood
    # leading edge higher / flatter / more upright with a crisper fascia corner
    zt = fillet_profile(
        [(-1.99, 1.03), (-1.79, 1.03), (-1.60, 1.270), (-0.25, 1.412), (0.17, 1.380), (0.935, 0.972), (1.72, 0.838),
         (1.90, 0.812), (1.955, 0.776), (1.975, 0.690)],
        [0, 0.14, 0.32, 6.0, 0.6, 0.9, 0.6, 0.10, 0.04, 0], step=0.01)
    zf = smooth_keys([(-1.975, 0.30), (-1.95, 0.27), (-1.88, 0.23), (-1.70, 0.20), (-1.30, 0.165), (-0.8, 0.15), (0.0, 0.14),
                      (0.8, 0.15), (1.3, 0.17), (1.70, 0.20), (1.85, 0.205), (1.93, 0.225), (1.96, 0.255), (1.975, 0.30)],
                     sigma=0.07)
    # plan view: gentle haunch flares over both wheels (+2.5 cm vs the doors); the nose corner is a true superellipse quadrant
    # (rev 2 / first rev 3 keys gave a straight 45 degree chamfer, which read as a bulbous "pug" nose)
    hwm_k = Curve1D(smooth_keys([(-1.975, 0.690), (-1.935, 0.770), (-1.85, 0.822), (-1.70, 0.855), (-1.50, 0.874), (-1.26, 0.882),
                                 (-1.00, 0.876), (-0.60, 0.862), (-0.20, 0.858), (0.40, 0.860), (0.80, 0.870), (1.10, 0.879),
                                 (1.26, 0.881), (1.50, 0.870), (1.60, 0.866)], sigma=0.14))
    NOSE_X0, NOSE_X1, NOSE_Y1, NOSE_N = 1.52, 1.975, 0.50, 2.45

    def hwm(x):
        if x <= NOSE_X0:
            return hwm_k(x)
        y0 = hwm_k(NOSE_X0)
        t = min((x - NOSE_X0) / (NOSE_X1 - NOSE_X0), 1.0)
        return NOSE_Y1 + (y0 - NOSE_Y1) * (1.0 - t ** NOSE_N) ** (1.0 / NOSE_N)
    zw = smooth_keys([(-1.975, 0.50), (-1.8, 0.57), (-1.0, 0.60), (0, 0.60), (1.0, 0.595), (1.7, 0.57), (1.93, 0.52),
                      (1.975, 0.46)], sigma=0.12)
    # belt line: raised at the rear (wedge), flows into the tail lamp shoulder
    zb = smooth_keys([(-1.975, 0.82), (-1.93, 0.870), (-1.84, 0.918), (-1.68, 0.968), (-1.30, 1.004), (-0.9, 0.990), (-0.4, 0.965),
                      (0.2, 0.942), (0.6, 0.918), (0.92, 0.875), (1.2, 0.826), (1.5, 0.778), (1.80, 0.748), (1.94, 0.705),
                      (1.975, 0.58)], sigma=0.13)
    zc = smooth_keys([(-1.95, 0.72), (-1.7, 0.755), (-1.0, 0.760), (0.0, 0.738), (1.0, 0.724), (1.4, 0.702), (1.75, 0.656),
                      (1.95, 0.60)], sigma=0.14)
    # shoulder crease: deeper and crisper than rev 2 (5 cm step over a 6.4 cm transition) so the flank reads as sculpted, not slab-sided
    cdepth = smooth_keys([(-1.975, 0.0), (-1.85, 0.010), (-1.55, 0.032), (-1.2, 0.048), (-0.8, 0.054), (0.0, 0.056), (0.8, 0.052),
                          (1.2, 0.042), (1.55, 0.024), (1.78, 0.0), (1.975, 0.0)], sigma=0.14)
    # top flat (hood / roof) half width as a ratio of the belt half width -> wider greenhouse, much less tumblehome than rev 2
    # towards the nose the hood edge runs out to meet the fender crest (shoulder 10 cm wide at the wheel -> 3 cm at the fascia):
    # no shelf / knuckle at the nose corner, the hood flows into the fender, the corner stays tight and upright
    hw_ratio = as_curve(smooth_keys([(-1.975, 0.78), (-1.80, 0.80), (-1.5, 0.835), (-0.6, 0.85), (0.16, 0.85), (0.92, 0.87),
                                     (1.40, 0.865), (1.70, 0.90), (1.85, 0.935), (1.935, 0.945), (1.975, 0.945)], sigma=0.12))
    dz = as_curve(smooth_keys([(-1.975, 0.04), (-1.80, 0.05), (-1.3, 0.066), (-0.5, 0.068), (0.16, 0.066), (0.92, 0.040),
                               (1.5, 0.030), (1.975, 0.026)], sigma=0.15))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-1.2, 0.0), (-0.75, 1.0), (0.75, 1.0), (1.1, 0.0)], mode='smooth')
    # belt ledge (belt_lo -> belt_up) and crease fade out over the front fender / hood, so the fender crest flows into the hood
    ledge = as_curve([(0.55, 1.0), (1.15, 0.12)], mode='smooth')

    def hwb(x):
        return hwmc(x) - (0.047 + 0.012 * smoothstep(0.9, 0.5, x))

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth, cwidth=0.032,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.045 + 0.035 * door_win(x)),
        zs=lambda x: zfc(x) + 0.095,
        belt_step=lambda x: 0.004 + 0.012 * ledge(x), crease=lambda x: 0.004 + 0.012 * ledge(x),
    )


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car01 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="FWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. body shell loft
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    xe = P['x_end']
    rr_ = P['round_rear']
    rf_ = P['round_front']
    xs = station_list(-xe, xe, dx=0.05, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_rg_top'], P['x_rg_base']] + end_round_stations(-xe, rr_, 6, at_start=True)
                      + end_round_stations(xe, rf_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr_, round_x1=rf_)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, pillar_cols, roof_cols, bumper_cols, rail_cols = set(), set(), set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        roof_cols |= shell_quad_cols(shell, 'edge', 'top_c', sd)
        rail_cols |= shell_quad_cols(shell, 'edge', 'rail', sd)                         # roof-edge strip beside the glass
        bumper_cols |= shell_quad_cols(shell, 'sill', 'wide', sd, frac=(0.0, 0.75))    # black lower bumper valance
    # crisp horizontal split lines for the black nose / tail valances (the domed caps are rings: centroid tests alone would
    # give a stair-stepped paint edge)
    for z_cut, in_zone in ((0.43, lambda x: x > 1.8), (0.47, lambda x: x < -1.8)):
        geom = set()
        for f in bm.faces:
            if in_zone(f.calc_center_median().x):
                geom.add(f)
                geom.update(f.edges)
                geom.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, 0, z_cut), plane_no=(0, 0, 1))
    bm.normal_update()
    surf0 = Surface(bm)   # uncut surface for all projections

    # rev 3: the black pack is ONE continuous floating-roof graphic: roof, A/B pillars and the C-pillar, which now runs all the
    # way down beside the hatch glass to the tail corner (rev 2 stopped it at x = -1.64 and left a red horn behind it)
    X_ROOF_REAR = -1.62                          # black roof panel ends at the hatch glass
    X_PILLAR_REAR = -1.80                        # black C-pillar ends at the glass base line (no spike along the deck)
    X_COWL = 0.93                                # front end of the black A-pillar foot (the cowl strip)
    for f in bm.faces:    # material zones on the raw shell (faces keep them through the boolean)
        c = f.calc_center_median()
        tag = f[tc]
        m = 'M_Paint'
        if tag in under_cols:
            m = 'M_Underbody'
        elif tag in roof_cols and ((X_ROOF_REAR < c.x < 0.97) or (tag in rail_cols and X_PILLAR_REAR < c.x <= X_ROOF_REAR)):
            m = 'M_Paint2'                          # black roof pack (+ the roof-edge strip beside the hatch glass)
        elif tag in pillar_cols and (X_PILLAR_REAR < c.x < X_COWL):
            m = 'M_Paint2'                          # blacked-out pillars A / B / C
        elif tag in bumper_cols and abs(c.x) > 1.56:
            m = 'M_TrimBlack'                       # lower bumper valances
        elif tag == 0 and c.z < (0.43 if c.x > 0 else 0.47):   # dome caps: black valance below the intake / diffuser line
            m = 'M_TrimBlack'
        f.material_index = mi(m)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters (wheel arches, panel gaps, lamp / grille / plate / vent pockets, exhaust holes) -> ONE boolean
    # ------------------------------------------------------------------------------------------------------------------
    cutters = []
    inserts = []      # bmeshes added to the body after the boolean

    def keep(b):
        if b is not None:
            inserts.append(b)
        return b

    def add_pair(bm_left, into=None):
        """append a left-hand bmesh and its mirror image (right) to the cutters, or to `into`."""
        tgt = cutters if into is None else into
        if bm_left is None:
            return
        tgt.append(mirrored_copy(bm_left))
        tgt.append(bm_left)

    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        cutters.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody',
                                         stretch_up=ARCH_STRETCH))

    def edge_y(x):
        return dict(ring_controls(shell.cv, x))['edge'][0]

    RAY_L = (0, -1, 0)
    RAY_F, RAY_R = (-1, 0, 0), (1, 0, 0)
    z_belt_door = 0.944                                      # top edge of the door cut = just under the glass
    # rev 3: the door front edge leans forward at the top (it ends right behind the glass front corner / mirror foot)
    door = [(0.745, z_belt_door), (0.722, 0.85), (0.690, 0.70), (0.648, 0.50), (0.616, 0.36), (0.598, 0.29), (0.55, 0.268),
            (0.0, 0.262), (-0.55, 0.268), (-0.585, 0.29), (-0.596, 0.36), (-0.588, 0.50), (-0.574, 0.70), (-0.562, 0.85),
            (-0.554, z_belt_door)]
    add_pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    # hood shut line: follows the hood edge of the loft (the `edge` ring point) and wraps round the leading edge
    hx1 = 1.79
    hy1 = edge_y(hx1) - 0.012
    hxc = 1.905                                              # hood leading edge at the centre line
    hood_l = [(x, edge_y(x) - 0.006) for x in (0.94, 1.1, 1.3, 1.5, 1.7)] + [(hx1, hy1)] +              [(hx1 + (hxc - hx1) * math.sin(th), hy1 * math.cos(th)) for th in [i * (math.pi / 2.0) / 14.0 for i in range(1, 15)]]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    # tailgate (rev 3: complete perimeter - roof cut ahead of the spoiler, side cuts along the glass frame over the deck corner and
    # down the tail face through the lamp, lower edge across the tail under the plate)
    x_hatch = -1.475
    y_tg = 0.56                                              # y of the tailgate side cut on the tail face
    ye0 = edge_y(x_hatch) - 0.012
    cutters.append(surface_sweep(surf0, resample_poly([Vector((x_hatch, ye0, 0)), Vector((x_hatch, -ye0, 0))], 0.04), (0, 0, -1),
                                 GROOVE, mat='M_Underbody'))
    tgx = [x_hatch - 0.0545 * i for i in range(0, 9)]        # -1.475 ... -1.911 : along the roof edge, then curving in over the deck
    tgs = []
    for x in tgx:
        y = edge_y(x) - 0.012
        if x < -1.82:
            y = y + (y_tg - y) * smoothstep(-1.82, -1.93, x)
        tgs.append(Vector((x, y, 0)))
    add_pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    for z0_, z1_ in ((0.985, 0.905), (0.742, 0.605)):         # side cuts on the tail face: above and below the lamp
        add_pair(surface_sweep(surf0, [Vector((-2.2, y_tg, z)) for z in [z0_ + (z1_ - z0_) * i / 5.0 for i in range(6)]], RAY_R, GROOVE,
                               mat='M_Underbody'))
    tail_low = [Vector((-2.2, y_tg, 0.605)), Vector((-2.2, -y_tg, 0.605))]
    cutters.append(surface_sweep(surf0, resample_poly(tail_low, 0.04), RAY_R, GROOVE, mat='M_Underbody'))
    # fuel flap: a clean rounded rectangle drawn in the tangent plane of the flank and projected back along the surface normal
    # (rev 2 projected a circle along the Y axis onto the curved quarter panel -> lopsided egg)
    fh = surf0.hit(Vector((-1.03, 0.9, 0.875)), RAY_L)
    if fh is not None:
        fn = fh[1].normalized()
        t1 = (Vector((1, 0, 0)) - fn * fn.x).normalized()
        t2 = t1.cross(fn).normalized()
        flap = [fh[0] + t1 * u + t2 * v for (u, v) in outline_rounded_poly([(-0.072, -0.056), (0.072, -0.056), (0.072, 0.056),
                                                                           (-0.072, 0.056)], 0.030, 5)]
        fuel_flap = surface_sweep(surf0, flap, -fn, GROOVE, closed=True, mat='M_Underbody')
        if fuel_flap is not None:
            cutters.append(fuel_flap)
    lap("grooves + arches ready")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps, grilles, vents, plates (pocket cutters + inserts); built on the UNCUT surface
    # ------------------------------------------------------------------------------------------------------------------
    VL = Vector((0, 0, 1))

    # --- headlights (left, mirrored): rev 3 angular "blade" units that wrap the corner and sweep up onto the fender;
    #     point-source projection from the centre of the nose corner -------------------------------------------------------
    RH = ('radial', Vector((1.50, 0.26, 0.70)))
    UL = Vector((0.55, -0.835, 0.0)).normalized()             # +U = towards the inner end of the lamp (nose centre)
    c_head = Vector((1.745, 0.655, 0.700))
    cut, ins = build_headlight_blade(surf0, c_head, RH, (UL, VL), length=0.285, height=0.082)
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)

    # --- nose: upper grille, plate, lower intake, corner intakes, fog lamps --------------------------------------------
    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)

    z_up, z_plate, z_low = 0.628, 0.508, 0.343
    up_out = outline_rrect(0.60, 0.066, 0.022, 4)
    pk = nose_pocket((1.99, 0.0, z_up), up_out, 0.06)
    if pk is not None:
        cutters.append(pk)
        fm = anchor_frame(surf0, (1.99, 0, z_up), RAY_F, sink=0.035)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.85) for p in up_out], kind='bars', pitch=0.017, bar=0.0045, depth=0.02, frame=0.009)
        bmesh.ops.transform(g, matrix=fm, verts=g.verts)
        keep(g)
    cut, plate = plate_recess(surf0, (1.99, 0.0, z_plate), RAY_F)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    # wide, low trapezoid intake (rev 3: wider at the top, spans the bumper) with honeycomb mesh
    low_out = outline_rounded_poly([(-0.40, -0.066), (0.40, -0.066), (0.50, 0.072), (-0.50, 0.072)], 0.030, 4)
    pk = nose_pocket((1.99, 0.0, z_low), low_out, 0.07)
    if pk is not None:
        cutters.append(pk)
        fm = anchor_frame(surf0, (1.99, 0, z_low), RAY_F, sink=0.04)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in low_out], kind='hex', pitch=0.036, bar=0.0065, depth=0.022, frame=0.01)
        bmesh.ops.transform(g, matrix=fm, verts=g.verts)
        keep(g)
    # corner air intakes (left, mirrored): diagonal rays, small black pockets with vertical fins
    dC = Vector((-0.80, -0.60, 0.0)).normalized()
    UC = Vector((0.60, -0.80, 0.0)).normalized()
    cc = Vector((1.80, 0.68, 0.385))
    pk = pocket_cutter(surf0, outline_rrect(0.15, 0.095, 0.022, 3), cc, dC, depth=0.05, taper=0.9, mat='M_TrimBlack', axes=(UC, VL),
                       floor_follows=True)
    if pk is not None:
        add_pair(pk)
        for k in range(-2, 3):
            add_pair(surface_sweep(surf0, [cc + UC * (k * 0.027) + VL * v for v in (-0.036, 0.0, 0.036)], dC,
                                   [(-0.0025, -0.040), (0.0025, -0.040), (0.0025, -0.012), (-0.0025, -0.012)], mat='M_TrimBlack'),
                     into=inserts)
    # fog lamps (left, mirrored)
    fogd = Vector((-0.97, -0.24, 0.0)).normalized()
    fogU = Vector((0.24, -0.97, 0.0)).normalized()
    cut, lens = lamp_unit(surf0, Vector((1.88, 0.67, 0.285)), fogd, outline_ellipse(0.038, 0.028, 18), depth=0.04, lens_inset=0.004,
                          axes=(fogU, VL), lens_mat='M_Headlight', taper=0.8)
    if cut is not None:
        add_pair(cut)
        add_pair(lens, into=inserts)

    # --- fender side vents (behind the front arch), left, mirrored ----------------------------------------------------
    vc = Vector((0.80, 0.9, 0.50))
    pk = pocket_cutter(surf0, outline_rrect(0.11, 0.045, 0.012, 3), vc, RAY_L, depth=0.03, taper=1.0, mat='M_TrimBlack', floor_follows=True)
    if pk is not None:
        add_pair(pk)
        for k in range(-2, 3):
            add_pair(surface_sweep(surf0, [Vector((0.80 + u, 0.9, 0.50 + k * 0.0095)) for u in (-0.045, 0.0, 0.045)], RAY_L,
                                   [(-0.0028, -0.02), (0.0028, -0.02), (0.0028, -0.002), (-0.0028, -0.002)], mat='M_TrimGrey'),
                     into=inserts)

    # --- taillights (left, mirrored): recessed, segmented wrap-around cluster (brake / indicator / reverse windows) -----
    RT = ('radial', Vector((-1.66, 0.25, 0.815)))
    UT = Vector((0.55, 0.80, 0.0)).normalized()
    c_tail = Vector((-1.905, 0.58, 0.808))
    # fix round 1: clean lamp (shallow black pocket, one smooth red lens over amber | white, thin chrome separator, black bezel)
    cut, ins = build_taillight_clean(surf0, c_tail, RT, (UT, VL), length=0.205, height=0.066, rot=0.09, bezel_mat='M_TrimBlack',
                                     bezel_w=0.0105, bezel_h=0.0028, margin=(0.011, 0.010))
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)

    # --- tail: plate recess, diffuser pocket with fins, exhaust cut-outs --------------------------------------------
    cut, plate = plate_recess(surf0, (-1.99, 0.0, 0.70), RAY_R)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    cut, fins = build_diffuser(surf0, (-1.99, 0.0, 0.505), RAY_R, width=0.84, height=0.082, fins=5, fin_h=0.065)
    if cut is not None:
        cutters.append(cut)
        for fb in fins:
            keep(fb)
    for s in (1, -1):
        cutters.append(prim_cylinder(radius=0.05, depth=0.20, segments=24, axis='X', center=(-1.93, s * 0.52, 0.432), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.036, length=0.12, lip=0.004)
        bmesh.ops.transform(tip, matrix=T((-1.974, s * 0.52, 0.432)), verts=tip.verts)
        keep(tip)
    lap("pockets ready: %d cutters" % len([c for c in cutters if c is not None]))

    # ------------------------------------------------------------------------------------------------------------------
    # 4. the boolean (manifold solver, one go) + everything that is added to the body
    # ------------------------------------------------------------------------------------------------------------------
    cutters = [c for c in cutters if c is not None]
    bm = bm_boolean(bm, cutters)
    lap("boolean done: %d faces, manifold=%s" % (len(bm.faces), is_manifold(bm)))
    # chamfer the rims of the lamp / grille / plate / vent pockets (shell face <-> cutter wall, > 60 deg) so they catch light
    tc, ts = face_tags(bm)
    wall_mats = (mi('M_TrimBlack'), mi('M_Chrome'), mi('M_Taillight'))

    def pocket_rim(e):
        if len(e.link_faces) != 2:
            return False
        a, b = e.link_faces
        if (a[tc] != 0) == (b[tc] != 0):
            return False
        wall = b if a[tc] != 0 else a
        return wall.material_index in wall_mats
    n_rim = bevel_hard_edges(bm, angle_deg=60.0, width=0.0035, segments=1, edge_filter=pocket_rim)
    lap("pocket rims chamfered: %d edges" % n_rim)

    # arch mouldings (black fender flares) following the arch lip: the upper half of the arch is an ellipse (ARCH_STRETCH), the
    # strip sits exactly on the cut edge (inner edge = hole edge), left wheels only, mirrored for the right side
    for name in ('FL', 'RL'):
        cx, cy, cz = WHEELS[name]['center']
        rh = WHEELS[name]['radius'] + ARCH_PAD
        rm = rh + ARCH_FLARE / 2.0 - 0.002
        arc = [Vector((cx + rm * math.cos(math.radians(a_)), 0.0, cz + rm * ARCH_STRETCH * math.sin(math.radians(a_))))
               for a_ in [10.0 + 160.0 * i / 34.0 for i in range(35)]]
        add_pair(surface_sweep(surf0, arc, RAY_L, rib_profile(ARCH_FLARE, 0.017, 0.012, 0.007), mat='M_TrimBlack'), into=inserts)
    add_pair(surface_sweep(surf0, poly_pts([(-0.80, 0.252), (-0.4, 0.248), (0.0, 0.246), (0.4, 0.248), (0.80, 0.252)], subdiv=2), RAY_L,
                           rib_profile(0.07, 0.018, 0.014, 0.006), mat='M_TrimBlack'), into=inserts)
    add_pair(build_splitter(surf0, RAY_F, y_max=0.56, out=0.040, inn=0.055), into=inserts)     # rev 3: ends well inboard of the tyre (rev 2: 0.66 m = 0.01 cm gap to the steered tyre)
    # thin chrome beltline strip under the side glass (z follows the belt_up ring point of the shell)
    belt = []
    for x in [0.76 - 0.05 * i for i in range(0, 46)]:
        pts_x = dict(ring_controls(shell.cv, x))
        belt.append((x, pts_x['belt_up'][1] - 0.004))
    add_pair(surface_sweep(surf0, poly_pts(belt), RAY_L, rib_profile(0.012, 0.004, 0.004, 0.002), mat='M_Chrome'), into=inserts)
    # door handle, cowl strip, wipers (hood ribs removed in rev 2: they read as bolted-on strips)
    add_pair(door_handle(surf0, -0.30, 0.875, RAY_L), into=inserts)
    keep(surface_sweep(surf0, [Vector((0.905, y, 0)) for y in [0.64 - 0.08 * i for i in range(17)]], (0, 0, -1),
                       rib_profile(0.075, 0.010, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.86, 0.10), (0.80, 0.64)), ((0.86, -0.64), (0.80, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    # rear badge (plain roundel, no brand), roof-edge spoiler with the third brake light, shark fin, rear wiper
    keep(surface_patch(surf0, outline_ellipse(0.035, 0.035, 20), Vector((-1.99, 0, 0.855)), RAY_R, offset=-0.0015, rings=2, mat='M_Chrome'))
    sp = build_roof_spoiler(surf0, -1.50, chord=0.22, half_span=0.63, thick=0.056, lip_h=0.038)
    if sp is None:
        lap("roof spoiler FAILED")
    keep(sp)
    fin = build_shark_fin(0.15, 0.034, 0.024, mat='M_Paint2')
    rz = surf0.hit(Vector((-0.98, 0, 0)), (0, 0, -1))[0].z
    bmesh.ops.transform(fin, matrix=T((-0.98, 0, rz - 0.004)), verts=fin.verts)
    keep(fin)
    # rear wiper at its rest position along the glass bottom edge: pivot cap + short arm + blade, collinear, lying ON the glass
    # sheet (the glass is 14 mm below the paint skin); everything is built in the glass plane frame (X up the glass, Z = normal)
    gz = lambda x: 1.02 + (x + 1.80) * (1.300 - 1.02) / (-1.60 + 1.80)      # glass line (x -> z), see the zt polyline
    phi = math.atan2(1.300 - 1.02, -1.60 + 1.80)                            # glass pitch (rad from horizontal)
    nrm = Vector((-math.sin(phi), 0.0, math.cos(phi)))                      # outward glass normal
    xw = -1.745                                                             # wiper line (slightly above the glass base)
    base = Vector((xw, 0.0, gz(xw))) - nrm * 0.0105
    wm = T(base, (0, -math.degrees(phi), 0))
    for (size, c, kind) in (((0.0105, 0.130, 0.006), (0.0, 0.070, 0.0), 'box'),         # arm
                            ((0.0140, 0.300, 0.0075), (0.0, 0.280, 0.0), 'box'),         # blade
                            ((0.0095, 0.0, 0.0), (0.0, 0.0, 0.0), 'cyl')):              # pivot cap
        if kind == 'box':
            pm = prim_box(size, c, mat='M_TrimBlack', bevel=0.0018, segments=1)
        else:
            pm = prim_cylinder(radius=0.0115, depth=0.010, segments=14, axis='Z', center=(0, 0, 0.003), mat='M_TrimBlack')
        bmesh.ops.transform(pm, matrix=wm, verts=pm.verts)
        keep(pm)
    # door mirrors: slim body-colour caps on short stalks, mounted on the door skin at the A-pillar foot
    zm = dict(ring_controls(shell.cv, 0.68))['belt_up'][1] + 0.045
    mh = surf0.hit(Vector((0.68, 0.0, zm - 0.03)), RAY_L)
    my = (mh[0].y - 0.02) if mh else 0.80
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint', length=0.185, width=0.108, height=0.100, arm_len=0.085)
        bmesh.ops.transform(m, matrix=T((0.70, s * my, zm)), verts=m.verts)
        keep(m)

    for ib in inserts:
        if ib is None:
            continue
        bm_append(bm, ib)
        ib.free()
    lap("add-ons appended: %d faces" % len(bm.faces))
    tc, ts = face_tags(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 5. greenhouse: windows as thin separate shells
    # ------------------------------------------------------------------------------------------------------------------
    side_cols = shell_quad_cols(shell, 'belt_up', 'edge', 1) | shell_quad_cols(shell, 'belt_up', 'edge', -1)
    top_cols = shell_quad_cols(shell, 'rail', 'top_c', 1) | shell_quad_cols(shell, 'rail', 'top_c', -1)
    A0, A1 = (0.78, 0.945), (-0.02, 1.375)         # A-pillar line (glass lies behind it); ~parallel to the windscreen edge, so
                                                    # the pillar is a constant-width band (rev 2: a wedge 0.2 m wide at the foot)
    B0, B1 = (-0.52, 0.89), (-0.52, 1.50)          # door glass rear edge
    Q0, Q1 = (-0.70, 0.89), (-0.70, 1.50)          # quarter glass front edge
    C0, C1 = (-1.52, 0.995), (-1.30, 1.345)        # quarter glass rear edge (broad C-pillar, leaning forward at the top)

    def behind(c, p0, p1):
        xl = p0[0] + (p1[0] - p0[0]) * (c.z - p0[1]) / (p1[1] - p0[1])
        return c.x < xl

    def plane(p0, p1):
        return (Vector((p0[0], 0, p0[1])), Vector((-(p1[1] - p0[1]), 0, p1[0] - p0[0])).normalized())

    def side_zone(f):
        return f[tc] in side_cols

    def door_pred(f):
        if f[tc] not in side_cols:
            return False
        c = f.calc_center_median()
        return behind(c, A0, A1) and not behind(c, B0, B1)

    def quarter_pred(f):
        if f[tc] not in side_cols:
            return False
        c = f.calc_center_median()
        return behind(c, Q0, Q1) and not behind(c, C0, C1)

    def ws_pred(f):
        return f[tc] in top_cols and P['x_ws_top'] < f.calc_center_median().x < P['x_ws_base']

    def rear_pred(f):
        return f[tc] in top_cols and P['x_rg_base'] < f.calc_center_median().x < P['x_rg_top']

    wins = [dict(name='door', pred=door_pred, zone=side_zone, planes=[plane(A0, A1), plane(B0, B1)]),
            dict(name='quarter', pred=quarter_pred, zone=side_zone, planes=[plane(Q0, Q1), plane(C0, C1)]),
            dict(name='windscreen', pred=ws_pred), dict(name='rear', pred=rear_pred)]
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass: %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    # rev 3: round over the skin edge of every window reveal, so the pillars and the roof edge are no longer razor-thin flat slabs
    # (they catch a highlight along both sides, which reads as a pillar with a cross-section)
    tc, ts = face_tags(bm)
    m_tb = mi('M_TrimBlack')

    def glass_rim(e):
        if len(e.link_faces) != 2:
            return False
        fa, fb = e.link_faces
        if (fa[tc] != 0) == (fb[tc] != 0):
            return False
        wall = fb if fa[tc] != 0 else fa
        return wall.material_index == m_tb and all(v.co.z > 0.90 and abs(v.co.x) < 1.95 for v in e.verts)
    n_gr = bevel_hard_edges(bm, angle_deg=50.0, width=0.0045, segments=2, edge_filter=glass_rim)
    lap("glass reveal edges rounded: %d" % n_gr)
    tc, ts = face_tags(bm)
    # roof lining (light headliner) and pillar trims (black plastic) = inward copies of the black (M_Paint2) shell faces; they
    # follow the window cut-outs exactly (rev 2 made both beige M_IntTrim: the pillars looked olive through the glass)
    m_p2 = mi('M_Paint2')
    roof_lining = inner_trim_from_faces(bm, lambda f: f[tc] in roof_cols and f.material_index == m_p2, offset=0.03, mat='M_IntTrim')
    pillar_trim = inner_trim_from_faces(bm, lambda f: f[tc] in pillar_cols and f.material_index == m_p2, offset=0.03, mat='M_TrimBlack')

    n_heal = heal_nonmanifold(bm)
    lap("non-manifold sliver faces removed: %d" % n_heal)
    cleanup_slivers(bm)            # fix round 1: ~930 near-zero-area boolean fans (< 1e-7 m2) -> welded / dissolved, non-manifold healed
    fix_micro_islands(bm, max_dim=0.015, drop_open_below=0.004)      # fix round 1: a 2.8 mm 4-face speck at the nose
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    fix_object_micro_islands(body)          # fix round 1: finish_object() can weld a 2-face junk sheet again
    n_sm = apply_shell_normals(body, shell)          # smooth shading from the lofted shell (boolean cuts keep clean normals)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels (axle centre = object origin, axle along Y, right wheels mirror-built)
    # ------------------------------------------------------------------------------------------------------------------
    for name, w in WHEELS.items():
        wb = build_wheel(radius=w['radius'], width=w['width'], spokes=5, style='multi', side=w['side'],
                         caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=56, tyre_segments=64)      # fix round 1: 15.3k -> ~12.5k tris per wheel
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior(shell, dict(dash_x_back=0.52, dash_z_top=0.93, front_x=-0.10, roof_x=(-1.30, 0.16),
                                    quarter_x=(-0.895, -0.58), driver_y=0.36, headliner=False))
    _add(ib, roof_lining)
    _add(ib, pillar_trim)
    for sd in (1, -1):                                   # trim behind the rear arches
        _add(ib, shell_skin(shell, 'sill', 'belt_up', -1.93, -1.66, offset=0.045, side=sd, mat='M_IntTrim'))
    _add(ib, prim_box((0.62, 1.16, 0.03), (-1.50, 0, 0.40), mat='M_IntCarpet', bevel=0.008, segments=1))       # cargo floor
    _add(ib, prim_box((0.03, 1.10, 0.54), (-1.86, 0, 0.67), mat='M_IntDash', bevel=0.01, segments=1))       # tailgate lining (kept 5 cm inside the skin: its top corners used to poke through the deck)
    # fix round 1: Pulse cockpit character (the kit dash / seats are shared by all cars): red accent band across the dash face + red
    # trim ring round the gear lever boot
    _add(ib, prim_box((0.008, 1.12, 0.012), (0.518, 0.0, 0.795), mat='M_Caliper', bevel=0.003, segments=1))
    _add(ib, prim_torus(R=0.040, r=0.0035, seg_major=24, seg_minor=6, axis='Z', center=(0.10, 0.0, 0.525), mat='M_Caliper'))
    fix_micro_islands(ib)          # fix round 1: dial ticks / knobs get outward normals
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.37, 0.36, 0.90)
    swb, axis = build_steering_wheel(rim_radius=0.18, tilt=24.0)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision hulls + empties
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-1.92, -0.9, 0.3, 0.92], low, z_clip=(0.17, 0.90), shrink=0.05),
        # nose hull: up to the hood line (shrunk 2 cm below the skin), not just to the belt
        [Vector((p.x, p.y, min(p.z, 0.99) - 0.012)) for p in
         hull_points_from_shell(shell, [0.92, 1.45, 1.92], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.22, None), shrink=0.05)],
        # cabin hull: from the tail glass base to the windscreen base, up to the roof (-2 cm)
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.88, 0.1, -0.8, -1.70, -1.85], ['belt_up', 'edge', 'top_c'], z_clip=(0.90, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:          # hidden in the viewport (QA renders); export_car() un-hides them while exporting
        h.hide_set(True)

    def E(suffix, loc, disp='PLAIN_AXES', size=0.08):
        return make_empty("%s_%s" % (CAR, suffix), col, parent=root, location=loc, display=disp, size=size)

    def lamp_point(center, ray, lift=0.03):
        h = surf0.hit(Vector(center), ray)
        return tuple(round(c, 4) for c in (h[0] + h[1] * lift)) if h else tuple(center)

    hl = lamp_point(c_head, RH)
    tl = lamp_point(c_tail, RT)
    rv = lamp_point(c_tail - UT * 0.12 - VL * 0.025, RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', rv)
    E('CAM_Hood', (1.02, 0.0, 1.03), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.22, 0.36, 1.19), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.00, 0.0, 0.45), 'ARROWS', 0.15)
    E('EXHAUST_L', (-1.974, 0.52, 0.432))
    E('EXHAUST_R', (-1.974, -0.52, 0.432))

    # measured dimensions -> root custom properties (sidecar JSON reads them from the scene)
    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.7]     # fenders only (no mirrors)
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    purge_qa(CAR)                                       # fix round 1: no <car>_FOC_* / <car>_QA_* clutter in the shipped collection
    lap("done. body bounds %s %s | L x W x H = %.3f x %.3f x %.3f (mirrors: %.3f wide)" % (
        tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), root['length'], root['width'], root['height'], hi.y - lo.y))
    return root


def unwrap_parts(parts):
    unwrap_parts_fix(CAR, parts)          # fix round 1: Body = tight island margin (46 % sheet usage instead of 27 %) + UVLivery channel


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):       # smart-project UVs are slow (~2-4 s per mesh, more when Blender is busy) -> three stages keep each call < 20 s
    unwrap_parts(['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts(['Wheel_RL', 'Wheel_RR'])
