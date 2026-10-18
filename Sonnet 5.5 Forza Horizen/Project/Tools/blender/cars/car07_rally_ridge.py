"""
car07_rally_ridge.py - parametric, idempotent build of the player car #7 "Ridge" (rally hatchback, AWD).
Built with the shared car kit (Tools/blender/lib/carkit.py) + Tools/blender/lib/carkit_ext_05_06_07.py (see Docs/CARKIT_API.md).

    CAR07_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "uv3" | "all"
    exec(compile(open(r"<project>/Tools/blender/cars/car07_rally_ridge.py", encoding="utf8").read(), "car07", "exec"), globals())

Design: 3-door rally hatch with a raised stance (0.22 m ground clearance), sculpted wide fender flares + black arch mouldings, black
bonnet panel with two vents, roof scoop, auxiliary lamp pod, tow hooks, mud flaps, big double-plane rear wing, 15 inch wheels on
chunky gravel tyres; cockpit with roll cage, bucket seats and harnesses.  4.15 x 1.84 x 1.48 m, wheelbase 2.60 m.
Staged at x = 84 m.
"""
import os
import time
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
_KIT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit.py")
_EXT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_05_06_07.py")
_FIX = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_07_fix.py")          # round-2 additions (wing, scoop, number panel, tyre)
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())
exec(compile(open(_FIX, encoding="utf8").read(), _FIX, "exec"), globals())

CAR = "car07_rally_ridge"
STAGE = globals().get("CAR07_STAGE", "all")

P = dict(
    id=CAR, display_name="Ridge", index=7,
    L=4.15, W=1.84, H=1.48, wheelbase=2.60, track_f=1.54, track_r=1.54,
    r_f=0.33, r_r=0.33, w_f=0.225, w_r=0.225, ride=0.22,          # 205/70 R15 gravel tyres
    x_ws_base=0.70, x_ws_top=0.12,
    x_rg_top=-1.52, x_rg_base=-1.86,                              # hatch glass (round 2: base moved forward 6 cm = steeper, ~38 deg)
    x_end=2.035, cap_bulge=0.04, round_front=0.08, round_rear=0.07,
    x_scale=0.9825,                                               # final x trim of the lofted shell (-> 4.15 m with the caps)
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
ARCH_PAD = 0.050                       # big wheel-arch gap (suspension travel)
GROOVE = groove_profile(0.0055, 0.007)


def body_curves():
    xe = P['x_end']
    zt = fillet_profile(
        [(-xe, 0.93), (-2.00, 1.02), (P['x_rg_base'] - 0.01, 1.04), (-1.50, 1.315), (-0.90, 1.388), (-0.30, 1.412), (0.12, 1.395), (0.70, 1.040),
         (0.95, 1.025), (1.50, 0.995), (1.85, 0.955), (2.00, 0.905), (xe, 0.80)],
        [0, 0.03, 0.12, 0.55, 1.8, 1.6, 0.35, 0.3, 3.0, 3.0, 0.2, 0.10, 0], step=0.01)
    zf = smooth_keys([(-xe, 0.42), (-1.95, 0.36), (-1.8, 0.29), (-1.55, 0.245), (-1.2, 0.22), (0, 0.22), (1.0, 0.22), (1.6, 0.24),
                      (1.85, 0.28), (1.98, 0.33), (xe, 0.40)], sigma=0.07)
    hwm = smooth_keys([(-xe, 0.60), (-1.98, 0.73), (-1.9, 0.80), (-1.75, 0.845), (-1.5, 0.868), (-1.3, 0.873), (-0.5, 0.873),
                       (0.5, 0.873), (1.1, 0.873), (1.4, 0.868), (1.62, 0.85), (1.78, 0.81), (1.92, 0.74), (2.0, 0.65), (xe, 0.54)],
                      sigma=0.07)
    zw = smooth_keys([(-xe, 0.62), (-1.8, 0.68), (-1.0, 0.69), (0, 0.69), (1.0, 0.69), (1.7, 0.66), (xe, 0.60)], sigma=0.15)
    zb = smooth_keys([(-xe, 0.98), (-1.95, 1.0), (-1.7, 1.04), (-1.3, 1.05), (-0.6, 1.04), (0.2, 1.03), (0.7, 1.02), (1.2, 0.985),
                      (1.7, 0.93), (1.95, 0.88), (xe, 0.80)], sigma=0.11)
    hw_ratio = as_curve(smooth_keys([(-xe, 0.78), (-1.9, 0.80), (-1.6, 0.82), (-1.0, 0.85), (0, 0.85), (0.7, 0.87), (1.2, 0.88),
                                     (xe, 0.82)], sigma=0.15))
    dz = as_curve(smooth_keys([(-xe, 0.04), (-1.5, 0.065), (-0.5, 0.07), (0.2, 0.065), (0.7, 0.045), (1.2, 0.035), (xe, 0.03)], sigma=0.12))
    tuck = as_curve(smooth_keys([(-xe, 0.04), (-1.5, 0.045), (0, 0.055), (1.2, 0.045), (xe, 0.035)], sigma=0.15))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-0.8, 0.0), (-0.4, 1.0), (0.5, 1.0), (0.85, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - tuck(x)

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.045 + 0.035 * door_win(x)),
        zs=lambda x: zfc(x) + 0.095,
        belt_step=0.016, crease=0.016,
    )


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car07 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="AWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. loft + fender flare sculpt
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    xe = P['x_end']
    rr_, rf_ = P['round_rear'], P['round_front']
    xs = station_list(-xe, xe, dx=0.05, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_rg_top'], P['x_rg_base'], 0.86, 1.94] +
                            end_round_stations(-xe, rr_, 6, at_start=True) + end_round_stations(xe, rf_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr_, round_x1=rf_)

    def sculpt(x, ay, z):
        dy = 0.0
        if ay > 0.45:
            for (cx, cz) in ((XF, P['r_f']), (XR, P['r_r'])):
                d = math.hypot(x - cx, z - cz)
                dy += 0.040 * smoothstep(0.66, 0.43, d) * smoothstep(0.22, 0.40, z)
        return (0.0, dy, 0.0)
    shell_deform(shell, sculpt)
    kx = P['x_scale']                                   # the curves were designed for a 2.035 half length: trim to the target length
    shell_deform(shell, lambda x, ay, z: ((kx - 1.0) * x, 0.0, 0.0))
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, pillar_cols, hood_cols = set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        hood_cols |= shell_quad_cols(shell, 'crown', 'top_c', sd)
    for z_cut, in_zone in ((0.56, lambda x: x > 1.80), (0.62, lambda x: x < -1.80)):
        geom = set()
        for f in bm.faces:
            if in_zone(f.calc_center_median().x):
                geom.add(f)
                geom.update(f.edges)
                geom.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, 0, z_cut), plane_no=(0, 0, 1))
    bm.normal_update()
    surf0 = Surface(bm)

    for f in bm.faces:
        c = f.calc_center_median()
        tag = f[tc]
        m = 'M_Paint'
        if tag in under_cols:
            m = 'M_Underbody'
        elif tag in hood_cols and 0.86 < c.x < 1.94:
            m = 'M_Paint2'                           # black bonnet panel
        elif tag in pillar_cols and (-0.2 < c.x < 0.80 and c.z > 1.02):
            m = 'M_Paint2'                           # black A-pillars
        elif (c.x > 1.80 and c.z < 0.56) or (c.x < -1.80 and c.z < 0.62):
            m = 'M_TrimBlack'                        # rally bumpers
        f.material_index = mi(m)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters
    # ------------------------------------------------------------------------------------------------------------------
    cutters = []
    inserts = []

    def keep(b):
        if b is not None:
            inserts.append(b)
        return b

    def add_pair(bm_left, into=None):
        tgt = cutters if into is None else into
        if bm_left is None:
            return
        tgt.append(mirrored_copy(bm_left))
        tgt.append(bm_left)

    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        cutters.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))

    RAY_L = (0, -1, 0)
    VL = Vector((0, 0, 1))
    RAY_F, RAY_R = (-1, 0, 0), (1, 0, 0)
    zbd = 1.03
    door = [(0.62, zbd), (0.60, 0.90), (0.585, 0.70), (0.575, 0.50), (0.57, 0.40), (0.55, 0.34), (0.50, 0.325), (0.0, 0.32),
            (-0.5, 0.325), (-0.54, 0.34), (-0.555, 0.40), (-0.56, 0.50), (-0.55, 0.70), (-0.54, 0.90), (-0.535, zbd)]
    add_pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    hood_l = [(0.74, 0.68), (1.0, 0.72), (1.5, 0.72), (1.85, 0.66), (1.97, 0.55), (2.01, 0.40), (2.025, 0.15), (2.03, 0.0)]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    x_hatch = -1.97
    tg = [Vector((x_hatch, y, 0)) for y in (0.62, -0.62)]
    cutters.append(surface_sweep(surf0, resample_poly(tg, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))

    def edge_y(x):
        return dict(ring_controls(shell.cv, x))['edge'][0]
    tgs = [Vector((x, edge_y(x) - 0.012, 0)) for x in (x_hatch, -1.92, -1.85, -1.76, -1.66, -1.58)]
    add_pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    tail_low = [Vector((0, 0.62, 0.70)), Vector((0, -0.62, 0.70))]
    cutters.append(surface_sweep(surf0, resample_poly(tail_low, 0.04), (1, 0, 0), GROOVE, mat='M_Underbody'))
    ff = surface_sweep(surf0, circle_pts(-1.02, 0.84, 0.07, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody')
    if ff is not None:
        cutters.append(ff)
    lap("grooves + arches ready")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps / grilles / vents / tail
    # ------------------------------------------------------------------------------------------------------------------
    RH = ('radial', Vector((1.55, 0.29, 0.80)))
    UL = Vector((0.60, -0.80, 0.0)).normalized()
    c_head = Vector((1.84, 0.62, 0.78))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.24, height=0.072, rot=0.18, floor_mat='M_TrimBlack')
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)

    def nose_pocket(center, outline, depth, mat='M_TrimBlack', lift=0.07):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False, lift=lift)

    up_out = outline_rrect(0.76, 0.085, 0.022, 4)
    pk = nose_pocket((2.2, 0.0, 0.775), up_out, 0.06)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.85) for p in up_out], kind='bars', pitch=0.017, bar=0.0045, depth=0.02, frame=0.009)
        conform_to_surface(g, surf0, (2.2, 0, 0.775), RAY_F, (0, 1, 0), VL, sink=0.035)
        keep(g)
    low_out = outline_rrect(1.00, 0.19, 0.04, 5)
    pk = nose_pocket((2.2, 0.0, 0.445), low_out, 0.08)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.92) for p in low_out], kind='grid', pitch=0.042, bar=0.0058, depth=0.02, frame=0.012)
        conform_to_surface(g, surf0, (2.2, 0, 0.445), RAY_F, (0, 1, 0), VL, sink=0.045)
        keep(g)
    # fender vents (louvred) between the door and the front arch
    cut, sl = slat_vent(surf0, Vector((0.78, 1.2, 0.80)), RAY_L, (1, 0, 0), (0, 0, 1), 0.20, 0.09, 4, depth=0.03)
    if cut is not None:
        add_pair(cut)
        for b in sl:
            add_pair(b, into=inserts)
    # round 2: recessed rally number panels on the doors (pocket + white plate + black numeral '7'); the reading direction differs per side
    for s_ in (1, -1):
        cutn, insn = number_panel(surf0, Vector((0.02, s_ * 1.2, 0.70)), (0, -s_, 0), Vector((-s_, 0, 0)), VL, w=0.36, h=0.27, digit='7')
        if cutn is not None:
            cutters.append(cutn)
            for b in insn:
                keep(b)
        else:
            lap("number panel %d FAILED" % s_)
    # two big bonnet vents with louvres
    for hy in (0.30, -0.30):
        cut, sl = slat_vent(surf0, Vector((1.42, hy, 0.0)), (0, 0, -1), (1, 0, 0), (0, 1, 0), 0.46, 0.20, 7, depth=0.035)
        if cut is not None:
            cutters.append(cut)
            for b in sl:
                keep(b)

    # --- tail ------------------------------------------------------------------------------------------------------------
    RT = ('radial', Vector((-1.72, 0.25, 0.84)))
    UT = Vector((0.55, 0.80, 0.0)).normalized()
    c_tail = Vector((-2.00, 0.62, 0.84))
    cut, ins = build_taillight(surf0, c_tail, RT, (UT, VL), length=0.17, height=0.085, rot=0.50, depth=0.034)
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)
    cut, plate = plate_recess(surf0, (-2.2, 0.0, 0.72), RAY_R)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    # recovery mesh pocket in the rear bumper
    rp = outline_rrect(0.62, 0.12, 0.03, 4)
    pk = pocket_cutter(surf0, rp, Vector((-2.2, 0, 0.50)), RAY_R, depth=0.07, lift=0.08, taper=0.97, mat='M_TrimBlack', floor_follows=False)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in rp], kind='grid', pitch=0.04, bar=0.006, depth=0.02, frame=0.010)
        conform_to_surface(g, surf0, (-2.2, 0, 0.50), RAY_R, (0, -1, 0), VL, sink=0.04)
        keep(g)
    h = surf0.hit(Vector((0, 0.44, 0.52)), RAY_R)
    xh = h[0].x if h else -2.06
    cutters.append(prim_cylinder(radius=0.052, depth=0.20, segments=24, axis='X', center=(xh + 0.05, 0.44, 0.52), mat='M_Underbody'))
    tip = build_exhaust_tip(radius=0.043, length=0.13, lip=0.005)
    bmesh.ops.transform(tip, matrix=T((xh + 0.004, 0.44, 0.52)), verts=tip.verts)
    keep(tip)
    lap("pockets ready: %d cutters" % len([c for c in cutters if c is not None]))

    # ------------------------------------------------------------------------------------------------------------------
    # 4. boolean + add-ons
    # ------------------------------------------------------------------------------------------------------------------
    cutters = [c for c in cutters if c is not None]
    bm = bm_boolean(bm, cutters)
    n_heal = heal_slivers(bm)
    lap("boolean done: %d faces, manifold=%s (%d sliver faces healed)" % (len(bm.faces), is_manifold(bm), n_heal))
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
    n_lip = bevel_arch_lips(bm, WHEELS, ARCH_PAD, tc, width=0.012, segments=2, y_min=0.45)
    lap("rims %d, arch lips %d" % (n_rim, n_lip))

    # arch mouldings (black fender flare strips), sills, splitter, handles, wipers
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        sw = arch_moulding(surf0, cx, cz, w['radius'] + ARCH_PAD + 0.028, (0, -1, 0) if cy > 0 else (0, 1, 0), a0=4.0, a1=176.0, n=40,
                           width=0.075, height=0.022)
        if sw is not None:
            keep(mirrored_copy(sw) if cy < 0 else sw)
    add_pair(surface_sweep(surf0, poly_pts([(-0.80, 0.302), (-0.4, 0.298), (0.0, 0.296), (0.4, 0.298), (0.80, 0.302)], subdiv=2), RAY_L,
                           rib_profile(0.07, 0.020, 0.014, 0.006), mat='M_TrimBlack'), into=inserts)
    add_pair(door_handle(surf0, -0.30, 0.95, RAY_L), into=inserts)
    keep(surface_sweep(surf0, [Vector((0.725, y, 0)) for y in [0.62 - 0.08 * i for i in range(16)]], (0, 0, -1),
                       rib_profile(0.075, 0.010, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.69, 0.10), (0.63, 0.62)), ((0.69, -0.62), (0.63, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    # underbody skid plate
    keep(prim_box((0.80, 0.92, 0.016), (1.32, 0, 0.212), mat='M_TrimGrey', bevel=0.006, segments=1))
    # roof scoop (round 2: rounded hump with a recessed black intake mouth + vanes) and a black roof-edge gutter on both sides
    keep(build_roof_scoop2(surf0, -0.64, -0.14, 0.19, 0.095))
    for s_ in (1, -1):
        pts_r = []
        for x in [0.04 - 0.12 * i for i in range(0, 14)]:
            pts_r.append(Vector((x, s_ * (edge_y(x) - 0.012), 0.0)))
        keep(surface_sweep(surf0, pts_r, (0, 0, -1), rib_profile(0.022, 0.0085, 0.006, 0.003), mat='M_TrimBlack'))
    # spot-light pod on the bumper
    hp_ = surf0.hit(Vector((0, 0.0, 0.605)), RAY_F)
    x_pod = (hp_[0].x if hp_ else 2.02) + 0.035
    pod = build_spot_pod(width=0.90, lamps=4, r=0.070, depth=0.085)
    bmesh.ops.transform(pod, matrix=T((x_pod, 0, 0.608)), verts=pod.verts)
    keep(pod)
    # tow hooks (front corners, rear corners)
    for s in (1, -1):
        hf = surf0.hit(Vector((0, s * 0.50, 0.33)), RAY_F)
        if hf:
            th = build_tow_hook(front=True)
            bmesh.ops.transform(th, matrix=T((hf[0].x - 0.01, s * 0.50, 0.33)), verts=th.verts)
            keep(th)
        hr = surf0.hit(Vector((0, s * 0.52, 0.40)), RAY_R)
        if hr:
            th = build_tow_hook(front=False)
            bmesh.ops.transform(th, matrix=T((hr[0].x + 0.01, s * 0.52, 0.40)), verts=th.verts)
            keep(th)
    # mud flaps behind all four wheels
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        mf = build_mud_flap(w=0.20, h=0.21)
        bmesh.ops.transform(mf, matrix=T((cx - w['radius'] - 0.075, (1 if cy > 0 else -1) * (abs(cy) + 0.045), 0.40)), verts=mf.verts)
        keep(mf)
    # rear wing on raked pylons
    # round 2: raised blade (z = 1.29 m) on two flat raked pylons that stand on the tail deck (feet seated on the measured skin), small rounded end plates
    wx, wz, w_foot, w_py = -1.90, 1.29, 0.0, 0.46
    drops = []
    for s_ in (1, -1):
        hh_ = surf0.hit(Vector((wx + w_foot, s_ * w_py, 2.0)), (0, 0, -1))
        drops.append((wz - hh_[0].z + 0.012) if hh_ else 0.28)
    wing = build_rally_wing2(span=1.40, chord=0.29, flap_chord=0.165, gap=0.082, plate_h=0.23, pylon_y=w_py, drop_l=drops[0], drop_r=drops[1],
                             foot_x=w_foot)
    bmesh.ops.transform(wing, matrix=T((wx, 0, wz)), verts=wing.verts)
    keep(wing)
    lap("wing drops %.3f / %.3f" % (drops[0], drops[1]))
    keep(surface_patch(surf0, outline_ellipse(0.028, 0.028, 20), Vector((-2.2, 0, 0.935)), RAY_R, offset=-0.0015, rings=2, mat='M_Chrome'))
    # bonnet pins (4) with wire loops on the black bonnet panel
    for (px, py) in ((0.97, 0.50), (0.97, -0.50), (1.88, 0.34), (1.88, -0.34)):
        hz_ = surf0.hit(Vector((px, py, 0)), (0, 0, -1))
        if hz_ is None:
            continue
        pz = hz_[0].z
        keep(prim_cylinder(radius=0.0115, depth=0.020, segments=12, axis='Z', center=(px, py, pz + 0.004), mat='M_Chrome', bevel=0.002, bevel_segments=1))
        keep(prim_torus(R=0.020, r=0.0030, seg_major=16, seg_minor=5, axis='Y', center=(px, py, pz + 0.020), mat='M_Chrome'))
    # (the door number panels are recessed pockets now: see number_panel above)
    # mirrors (boxy rally mirrors)
    mh = surf0.hit(Vector((0.64, 0.0, 1.0)), RAY_L)
    my = (mh[0].y - 0.012) if mh else 0.88
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint2', length=0.17, width=0.095, height=0.115, arm_len=0.07)
        bmesh.ops.transform(m, matrix=T((0.66, s * my, 1.065)), verts=m.verts)
        keep(m)

    for ib in inserts:
        if ib is None:
            continue
        bm_append(bm, ib)
        ib.free()
    lap("add-ons appended: %d faces" % len(bm.faces))
    tc, ts = face_tags(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 5. greenhouse
    # ------------------------------------------------------------------------------------------------------------------
    side_cols = shell_quad_cols(shell, 'belt_up', 'edge', 1) | shell_quad_cols(shell, 'belt_up', 'edge', -1)
    top_cols = shell_quad_cols(shell, 'rail', 'top_c', 1) | shell_quad_cols(shell, 'rail', 'top_c', -1)
    A0, A1 = (0.66, 1.045), (0.06, 1.38)
    B0, B1 = (-0.52, 1.02), (-0.52, 1.52)
    Q0, Q1 = (-0.66, 1.02), (-0.66, 1.52)
    C0, C1 = (-1.82, 1.05), (-1.60, 1.31)

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
    m_p2 = mi('M_Paint2')
    pillar_cols_all = pillar_cols
    pillar_trim = inner_trim_from_faces(
        bm, lambda f: f[tc] != 0 and f[tc] in pillar_cols_all and f.calc_center_median().z > 1.0 and
        (P['x_rg_base'] - 0.1 < f.calc_center_median().x < P['x_ws_base'] + 0.1), offset=0.03, mat='M_IntTrim')

    heal_slivers(bm)
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    lap("healed %d sliver faces on the finished mesh" % heal_mesh(body))
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels: 15" star wheels on chunky gravel tyres
    # ------------------------------------------------------------------------------------------------------------------
    for wi, (name, w) in enumerate(WHEELS.items()):
        wb = build_wheel_gravel2(radius=w['radius'], width=w['width'], rim_radius=0.2032, rim_width=w['width'] - 0.040, spokes=6,
                                 style='star', side=w['side'], hub_radius=0.056, brake_disc_radius=0.150,
                                 caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=48, rim_mat='M_Rim', dish=0.035,
                                 seed=11 + 5 * wi, vary=1.0)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior: bucket seats, roll cage, harnesses
    # ------------------------------------------------------------------------------------------------------------------
    seat_x, seat_z, dy = -0.36, 0.36, 0.36
    ib = build_interior_ext(shell, dict(
        floor_z=0.31, front_x=seat_x, driver_y=dy, dash_x_back=0.28, dash_x_front=0.58, dash_z_top=1.00, dash_z_low=0.60,
        hw=0.77, x_front_floor=0.56, x_rear_floor=-1.88, seats_rear=False, door_x=(-0.56, 0.60), quarter_x=(-0.90, -0.60),
        roof_x=(P['x_rg_top'] + 0.02, P['x_ws_top']), console=(-0.80, 0.30), console_h=0.26, shifter_x=-0.20,
        mirror=(0.10, 0.0, 1.30), back_h=0.62, front_z=seat_z, front_recline=18.0, seat_w=0.50, armrest_x=0.02, headliner=True))
    _add(ib, pillar_trim)
    for sd in (1, -1):
        _add(ib, shell_skin(shell, 'sill', 'belt_up', -1.98, -1.72, offset=0.045, side=sd, mat='M_IntTrim'))
    _add(ib, prim_box((0.03, 1.08, 0.50), (-1.885, 0, 0.66), mat='M_IntTrim', bevel=0.008, segments=1))       # bare rear panel
    _add(ib, build_roll_cage(x_hoop=-0.80, x_a_base=0.50, x_a_top=0.16, y_half=0.62, z_floor=0.33, z_roof=1.30, z_dash=0.86,
                             x_rear=-1.55))
    for yy in (dy, -dy):
        _add(ib, build_harness((seat_x, yy, seat_z), back_h=0.62, recline=18.0))
    _add(ib, prim_cylinder(radius=0.05, depth=0.30, segments=14, axis='Y', center=(-0.62, 0.0, 0.50), mat='M_Caliper'))   # fire extinguisher
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.13, dy, 0.975)
    swb, axis = build_steering_wheel(rim_radius=0.145, tilt=22.0, flat_bottom=False, tube=0.016)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision hulls + empties
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.0, -1.2, -0.4, 0.4], low, z_clip=(0.26, 1.02), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 1.0) - 0.012)) for p in
         hull_points_from_shell(shell, [0.7, 1.4, 2.0], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.28, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.62, 0.0, -0.8, -1.5, -1.9], ['belt_up', 'edge', 'top_c'], z_clip=(1.02, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)

    def E(suffix, loc, disp='PLAIN_AXES', size=0.08):
        return make_empty("%s_%s" % (CAR, suffix), col, parent=root, location=loc, display=disp, size=size)

    def lamp_point(center, ray, lift=0.03):
        h = surf0.hit(Vector(center), ray)
        return tuple(round(c, 4) for c in (h[0] + h[1] * lift)) if h else tuple(center)

    hl = lamp_point(c_head, RH)
    tl = lamp_point(c_tail, RT)
    rv = lamp_point(c_tail - UT * 0.08 - VL * 0.03, RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', rv)
    E('CAM_Hood', (0.95, 0.0, 1.10), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.48, dy, 1.27), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.13, 0.0, 0.46), 'ARROWS', 0.15)
    E('EXHAUST_L', (xh, 0.44, 0.52))
    E('EXHAUST_R', (xh, -0.44, 0.52))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 1.0 and abs(v.co.x) < 1.9 and v.co.z > 0.25]     # fenders (flares) only
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    lap("done. body bounds %s %s | L x W x H = %.3f x %.3f x %.3f (mirrors: %.3f wide)" % (
        tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), root['length'], root['width'], root['height'], hi.y - lo.y))
    return root


def unwrap_parts(parts):
    t0 = time.time()
    for suf in parts:
        o = bpy.data.objects.get("%s_%s" % (CAR, suf))
        if o is not None:
            uv_unwrap(o)
            if suf == 'Body':
                uv_livery_layer(o)
            print("[car07] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
