"""
car05_gt_meridian.py - parametric, idempotent build of the player car #5 "Meridian GT" (front-engine grand tourer, RWD).
Built with the shared car kit (Tools/blender/lib/carkit.py) + Tools/blender/lib/carkit_ext_05_06_07.py, following the worked example
Tools/blender/cars/car01_hatch_pulse.py and Docs/BLENDER_CONTRACT.md.

Run inside the verified Blender MCP session (localhost:9889):
    CAR05_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "uv3" | "all"  (UV unwrap is split so each call stays < 20 s)
    exec(compile(open(r"<project>/Tools/blender/cars/car05_gt_meridian.py", encoding="utf8").read(), "car05", "exec"), globals())

Design: very long hood, set-back cabin, fastback roof, wide rear haunches, slim swept headlights, light-bar tail, quad exhaust,
20 inch twin-spoke wheels.  4.80 x 1.95 x 1.34 m, wheelbase 2.88 m.  Staged at x = 60 m.
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
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())

CAR = "car05_gt_meridian"
STAGE = globals().get("CAR05_STAGE", "all")

P = dict(
    id=CAR, display_name="Meridian GT", index=5,
    L=4.80, W=1.95, H=1.34, wheelbase=2.88, track_f=1.62, track_r=1.60,
    r_f=0.35, r_r=0.36, w_f=0.245, w_r=0.285, ride=0.12,         # 20" wheels: 245/40 R20 front, 285/35 R20 rear
    x_ws_base=0.20, x_ws_top=-0.52,                              # windscreen glass (lower / upper edge)
    x_rg_top=-1.15, x_rg_base=-1.86,                             # fastback rear glass
    x_end=2.375, cap_bulge=0.04, round_front=0.10, round_rear=0.09,
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
ARCH_PAD = 0.036
GROOVE = groove_profile(0.0055, 0.007)


def body_curves():
    zt = fillet_profile(
        [(-2.36, 0.895), (-2.31, 0.965), (-1.86, 1.075), (-1.15, 1.305), (-0.52, 1.340), (0.20, 0.955), (0.45, 0.935),
         (1.44, 0.868), (2.12, 0.785), (2.30, 0.725), (2.36, 0.62)],
        [0, 0.07, 0.55, 2.4, 0.45, 0.30, 4.0, 3.5, 0.35, 0.10, 0], step=0.01)
    zf = smooth_keys([(-2.36, 0.30), (-2.30, 0.27), (-2.15, 0.22), (-1.90, 0.18), (-1.5, 0.145), (-0.8, 0.12), (0.0, 0.12),
                      (0.8, 0.125), (1.5, 0.14), (2.0, 0.16), (2.25, 0.19), (2.33, 0.23), (2.36, 0.30)], sigma=0.07)
    hwm = smooth_keys([(-2.36, 0.60), (-2.30, 0.78), (-2.2, 0.88), (-2.0, 0.945), (-1.7, 0.972), (-1.44, 0.977), (-0.9, 0.965),
                       (-0.2, 0.945), (0.5, 0.935), (1.0, 0.940), (1.44, 0.948), (1.85, 0.935), (2.05, 0.90), (2.2, 0.82),
                       (2.3, 0.72), (2.36, 0.56)], sigma=0.07)
    zw = smooth_keys([(-2.36, 0.55), (-2.0, 0.60), (-1.44, 0.625), (-0.8, 0.60), (0, 0.58), (0.8, 0.57), (1.44, 0.575),
                      (2.0, 0.56), (2.36, 0.50)], sigma=0.15)
    zb = smooth_keys([(-2.36, 0.86), (-2.28, 0.92), (-2.0, 0.965), (-1.6, 0.985), (-1.44, 0.985), (-0.9, 0.950), (-0.4, 0.935),
                      (0.15, 0.915), (0.6, 0.88), (1.0, 0.84), (1.44, 0.805), (2.0, 0.745), (2.3, 0.68), (2.36, 0.60)], sigma=0.10)
    zc = smooth_keys([(-2.2, 0.74), (-1.44, 0.77), (-0.8, 0.74), (0, 0.72), (0.8, 0.70), (1.44, 0.66), (2.0, 0.62)], sigma=0.15)
    cdepth = smooth_keys([(-2.36, 0.0), (-2.1, 0.008), (-1.6, 0.028), (-0.8, 0.03), (0.2, 0.026), (1.0, 0.022), (1.7, 0.012),
                          (2.1, 0.0), (2.36, 0.0)], sigma=0.12)
    tuck = as_curve(smooth_keys([(-2.36, 0.03), (-1.9, 0.035), (-1.44, 0.04), (-0.8, 0.055), (0, 0.05), (1, 0.045), (1.44, 0.04),
                                 (2.0, 0.03), (2.36, 0.03)], sigma=0.15))
    hw_ratio = as_curve(smooth_keys([(-2.36, 0.80), (-2.0, 0.82), (-1.8, 0.78), (-1.5, 0.72), (-1.1, 0.70), (-0.52, 0.70),
                                     (0.0, 0.72), (0.4, 0.80), (0.8, 0.86), (2.36, 0.86)], sigma=0.12))
    dz = as_curve(smooth_keys([(-2.36, 0.03), (-2.0, 0.04), (-1.5, 0.06), (-1.1, 0.075), (-0.52, 0.075), (0.0, 0.07), (0.4, 0.05),
                               (1.0, 0.045), (2.36, 0.03)], sigma=0.12))
    rail_w = smooth_keys([(-2.36, 0.05), (-2.0, 0.10), (-1.8, 0.19), (-1.5, 0.21), (-1.2, 0.17), (-0.9, 0.08), (-0.52, 0.07), (0.2, 0.07),
                          (0.6, 0.05), (2.36, 0.05)], sigma=0.12)
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-0.9, 0.0), (-0.55, 1.0), (0.1, 1.0), (0.45, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - tuck(x)

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.05 + 0.04 * door_win(x)),
        zs=lambda x: zfc(x) + 0.10,
        rail_w=rail_w,
        belt_step=0.016, crease=0.016,
    )


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car05 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="RWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. body shell loft
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    xe = P['x_end']
    rr_, rf_ = P['round_rear'], P['round_front']
    xs = station_list(-xe, xe, dx=0.055, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_rg_top'], P['x_rg_base']] +
                            end_round_stations(-xe, rr_, 6, at_start=True) + end_round_stations(xe, rf_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr_, round_x1=rf_)
    # sculpt: a gentle power dome along the hood centre line (crowned, not flat)
    def sculpt(x, ay, z):
        a = smoothstep(0.30, 0.85, x) * (1.0 - smoothstep(1.85, 2.25, x)) * math.exp(-(ay / 0.36) ** 2) * clamp((z - 0.74) / 0.08, 0.0, 1.0)
        dy = bump(x, ay, z, -0.15, 0.95, 0.42, 0.90, 0.35, 0.15, -0.026)             # flowing scallop below the door line
        dy += bump(x, ay, z, 1.44, 0.93, 0.66, 0.55, 0.30, 0.22, 0.012)              # front fender muscle
        dy += bump(x, ay, z, -1.44, 0.95, 0.74, 0.65, 0.30, 0.26, 0.012)             # rear haunch
        return (0.0, dy, 0.017 * a)
    shell_deform(shell, sculpt)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, pillar_cols, roof_cols, bumper_cols = set(), set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        roof_cols |= shell_quad_cols(shell, 'edge', 'top_c', sd)
        bumper_cols |= shell_quad_cols(shell, 'sill', 'wide', sd, frac=(0.0, 0.55))
    for z_cut, in_zone in ((0.42, lambda x: x > 1.90), (0.50, lambda x: x < -1.90)):
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
        elif tag in roof_cols and (P['x_rg_base'] - 0.05 < c.x < P['x_ws_base'] + 0.03):
            m = 'M_Paint2'                           # contrast roof incl. window frames
        elif tag in pillar_cols and (-1.72 < c.x < 0.12 and c.z > 0.9):
            m = 'M_Paint2'                           # blacked-out pillars (glasshouse unit)
        elif (c.x > 1.90 and c.z < 0.42) or (c.x < -1.90 and c.z < 0.50):
            m = 'M_TrimBlack'                        # lower bumper valances (horizontal split line)
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
    z_belt_door = 0.935
    door = [(0.34, z_belt_door), (0.335, 0.85), (0.325, 0.70), (0.315, 0.50), (0.31, 0.36), (0.295, 0.29), (0.25, 0.268),
            (-0.2, 0.262), (-0.6, 0.268), (-0.78, 0.29), (-0.80, 0.36), (-0.80, 0.50), (-0.80, 0.70), (-0.80, 0.85),
            (-0.80, z_belt_door)]
    add_pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    hood_l = [(0.26, 0.66), (0.6, 0.70), (1.0, 0.74), (1.6, 0.755), (2.0, 0.73), (2.2, 0.66), (2.29, 0.52), (2.33, 0.30), (2.345, 0.0)]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    # boot lid
    x_boot = -1.84
    tg = [Vector((x_boot, y, 0)) for y in (0.64, -0.64)]
    cutters.append(surface_sweep(surf0, resample_poly(tg, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))

    def edge_y(x):
        return dict(ring_controls(shell.cv, x))['edge'][0]
    tgs = [Vector((x, edge_y(x) - 0.01, 0)) for x in (x_boot, -1.95, -2.1, -2.22, -2.3)]
    add_pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    tail_low = [Vector((0, 0.66, 0.62)), Vector((0, -0.66, 0.62))]
    cutters.append(surface_sweep(surf0, resample_poly(tail_low, 0.04), (1, 0, 0), GROOVE, mat='M_Underbody'))
    ff = surface_sweep(surf0, circle_pts(-1.55, 0.86, 0.075, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody')
    if ff is not None:
        cutters.append(ff)
    lap("grooves + arches ready")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps / grille / vents / diffuser / exhaust
    # ------------------------------------------------------------------------------------------------------------------
    VL = Vector((0, 0, 1))
    RAY_F, RAY_R = (-1, 0, 0), (1, 0, 0)

    RH = ('radial', Vector((1.90, 0.28, 0.58)))
    UL = Vector((0.80, -0.60, 0.0)).normalized()
    c_head = Vector((2.20, 0.64, 0.640))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.300, height=0.050, rot=0.20, floor_mat='M_TrimGrey')
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)

    def nose_pocket(center, outline, depth, mat='M_TrimBlack', lift=0.09):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False, lift=lift)

    # big oval grille with chrome frame + horizontal bars
    gr_out = outline_superellipse(0.46, 0.100, 2.8, 36)
    pk = nose_pocket((2.45, 0.0, 0.455), gr_out, 0.07)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.93) for p in gr_out], kind='bars', pitch=0.026, bar=0.0055, depth=0.02, frame=0.012,
                        frame_mat='M_Chrome')
        conform_to_surface(g, surf0, (2.45, 0, 0.455), RAY_F, (0, 1, 0), VL, sink=0.04)
        keep(g)
    # lower intake slot (splitter mouth) + corner brake ducts
    low_out = outline_rrect(0.92, 0.075, 0.03, 5)
    pk = nose_pocket((2.45, 0.0, 0.275), low_out, 0.07)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in low_out], kind='hex', pitch=0.034, bar=0.0062, depth=0.022, frame=0.01)
        conform_to_surface(g, surf0, (2.45, 0, 0.275), RAY_F, (0, 1, 0), VL, sink=0.04)
        keep(g)
    dC = Vector((-0.80, -0.60, 0.0)).normalized()
    UC = Vector((0.60, -0.80, 0.0)).normalized()
    cc = Vector((2.25, 0.70, 0.30))
    pk = pocket_cutter(surf0, outline_rrect(0.15, 0.075, 0.02, 3), cc, dC, depth=0.05, taper=0.9, mat='M_TrimBlack', axes=(UC, VL),
                       floor_follows=True)
    if pk is not None:
        add_pair(pk)
        for k in range(-3, 4):
            add_pair(surface_sweep(surf0, [cc + UC * (k * 0.02) + VL * v for v in (-0.028, 0.0, 0.028)], dC,
                                   [(-0.0025, -0.040), (0.0025, -0.040), (0.0025, -0.012), (-0.0025, -0.012)], mat='M_TrimBlack'),
                     into=inserts)

    # --- front fender gills (behind the front wheel): chrome slats ---------------------------------------------------
    vc = Vector((0.86, 0.9, 0.60))
    pk = pocket_cutter(surf0, outline_rrect(0.30, 0.085, 0.02, 3), vc, RAY_L, depth=0.03, taper=1.0, mat='M_TrimBlack', floor_follows=True)
    if pk is not None:
        add_pair(pk)
        for k in range(-3, 4):
            add_pair(surface_sweep(surf0, [Vector((0.86 + u, 0.9, 0.60 + k * 0.0105)) for u in (-0.13, 0.0, 0.13)], RAY_L,
                                   [(-0.0028, -0.02), (0.0028, -0.02), (0.0028, -0.002), (-0.0028, -0.002)], mat='M_Chrome'),
                     into=inserts)
    # --- two long hood vents -------------------------------------------------------------------------------------------
    for hy in (0.30, -0.30):
        pk = pocket_cutter(surf0, outline_rrect(0.44, 0.095, 0.02, 3), Vector((1.12, hy, 0.0)), (0, 0, -1), depth=0.03, taper=1.0,
                           mat='M_TrimBlack', floor_follows=True, axes=(Vector((1, 0, 0)), Vector((0, 1, 0))))
        if pk is not None:
            cutters.append(pk)
            for k in range(-4, 5):
                keep(surface_sweep(surf0, [Vector((1.12 + k * 0.045, hy + v, 0)) for v in (-0.038, 0.0, 0.038)], (0, 0, -1),
                                   [(-0.0035, -0.02), (0.0035, -0.02), (0.0035, -0.003), (-0.0035, -0.003)], mat='M_TrimBlack'))

    # --- taillights (wrap-around, left mirrored) + light bar ----------------------------------------------------------
    RT = ('radial', Vector((-2.00, 0.30, 0.78)))
    UT = Vector((0.45, 0.89, 0.0)).normalized()
    c_tail = Vector((-2.30, 0.66, 0.845))
    cut, ins = build_taillight(surf0, c_tail, RT, (UT, VL), length=0.230, height=0.055, rot=0.05, depth=0.034)
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)
    keep(surface_sweep(surf0, [Vector((-2.5, y, 0.857)) for y in [0.50 - 0.1 * i for i in range(11)]], RAY_R,
                       rib_profile(0.020, 0.0055, 0.006, 0.0022), mat='M_Taillight'))

    # --- tail: plate, diffuser, quad exhaust ---------------------------------------------------------------------------
    cut, plate = plate_recess(surf0, (-2.5, 0.0, 0.70), RAY_R)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    cut, fins = build_diffuser(surf0, (-2.5, 0.0, 0.405), RAY_R, width=0.70, height=0.105, fins=5, fin_h=0.075)
    if cut is not None:
        cutters.append(cut)
        for fb in fins:
            keep(fb)
    ex_pts = []
    for yy in (0.50, 0.70):
        for s in (1, -1):
            h = surf0.hit(Vector((0, s * yy, 0.40)), RAY_R)
            xh = h[0].x if h else -2.40
            cutters.append(prim_cylinder(radius=0.046, depth=0.20, segments=24, axis='X', center=(xh + 0.05, s * yy, 0.40), mat='M_Underbody'))
            tip = build_exhaust_tip(radius=0.038, length=0.12, lip=0.004)
            bmesh.ops.transform(tip, matrix=T((xh + 0.004, s * yy, 0.40)), verts=tip.verts)
            keep(tip)
            ex_pts.append((xh, s * yy))
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
    lap("pocket rims chamfered: %d edges" % n_rim)
    n_lip = bevel_arch_lips(bm, WHEELS, ARCH_PAD, tc, width=0.011, segments=2)
    lap("arch lips rounded: %d edges" % n_lip)

    # side skirts, splitter, belt strip, handles, wipers, mirrors, ducktail, badge
    add_pair(surface_sweep(surf0, poly_pts([(-0.95, 0.252), (-0.5, 0.248), (0.0, 0.246), (0.5, 0.248), (0.95, 0.252)], subdiv=2), RAY_L,
                           rib_profile(0.07, 0.018, 0.014, 0.006), mat='M_TrimBlack'), into=inserts)
    add_pair(build_splitter(surf0, RAY_F, z=0.17, z_top=0.178, z_bot=0.148, out=0.050, inn=0.07, y_max=0.76), into=inserts)
    add_pair(build_splitter(surf0, RAY_R, z=0.22, z_top=0.228, z_bot=0.205, out=0.020, inn=0.05, y_max=0.76), into=inserts)
    belt = []
    for x in [0.30 - 0.05 * i for i in range(0, 44)]:
        pts_x = dict(ring_controls(shell.cv, x))
        belt.append((x, pts_x['belt_up'][1] - 0.004))
    add_pair(surface_sweep(surf0, poly_pts(belt), RAY_L, rib_profile(0.012, 0.004, 0.004, 0.002), mat='M_Chrome'), into=inserts)
    add_pair(door_handle(surf0, -0.55, 0.865, RAY_L), into=inserts)
    keep(surface_sweep(surf0, [Vector((0.235, y, 0)) for y in [0.62 - 0.08 * i for i in range(16)]], (0, 0, -1),
                       rib_profile(0.075, 0.010, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.18, 0.10), (0.12, 0.62)), ((0.18, -0.62), (0.12, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    # ducktail lip on the boot lid
    lip_pts = [Vector((-2.285 + 0.004 * (y / 0.6) ** 2, y, 0)) for y in [0.62 - 0.062 * i for i in range(21)]]
    keep(surface_sweep(surf0, lip_pts, (0, 0, -1), rib_profile(0.050, 0.020, 0.012, 0.007), mat='M_Paint2'))
    keep(surface_patch(surf0, outline_ellipse(0.03, 0.03, 20), Vector((-2.5, 0, 0.805)), RAY_R, offset=-0.0015, rings=2, mat='M_Chrome'))
    keep(surface_patch(surf0, outline_ellipse(0.028, 0.028, 20), Vector((2.5, 0, 0.60)), RAY_F, offset=-0.0015, rings=2, mat='M_Chrome'))
    # mirrors
    zm = 0.955
    mh = surf0.hit(Vector((0.18, 0.0, 0.90)), RAY_L)
    my = (mh[0].y - 0.012) if mh else 0.90
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint', length=0.19, width=0.105, height=0.105, arm_len=0.085)
        bmesh.ops.transform(m, matrix=T((0.20, s * my, zm)), verts=m.verts)
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
    A0, A1 = (0.02, 0.925), (-0.64, 1.27)
    B0, B1 = (-0.80, 0.90), (-0.80, 1.40)
    Q0, Q1 = (-0.93, 0.90), (-0.93, 1.40)
    C0, C1 = (-1.62, 0.98), (-1.20, 1.285)

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
    pillar_cols_all = pillar_cols | roof_cols
    pillar_trim = inner_trim_from_faces(
        bm, lambda f: f[tc] != 0 and f[tc] in pillar_cols_all and (P['x_rg_base'] - 0.1 < f.calc_center_median().x < P['x_ws_base'] + 0.1
                                                                     and f.calc_center_median().z > 0.88),
        offset=0.03, mat='M_IntTrim')

    heal_slivers(bm)
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    lap("healed %d sliver faces on the finished mesh" % heal_mesh(body))
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels
    # ------------------------------------------------------------------------------------------------------------------
    for name, w in WHEELS.items():
        rim_r = 0.2667                         # 20" bead + flange
        wb = build_wheel(radius=w['radius'], width=w['width'], rim_radius=rim_r, rim_width=w['width'] - 0.045, spokes=5,
                         style='multi', side=w['side'], hub_radius=0.062, brake_disc_radius=0.178,
                         caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=60, tyre_segments=72)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior_ext(shell, dict(
        floor_z=0.21, front_x=-0.82, driver_y=0.36, rear_x=-1.36, rear_width=1.12, dash_x_back=-0.22, dash_x_front=0.08,
        dash_z_top=0.90, dash_z_low=0.50, hw=0.76, x_front_floor=0.02, x_rear_floor=-1.98, door_x=(-0.80, 0.30),
        quarter_x=(-1.04, -0.80), roof_x=(P['x_rg_top'], P['x_ws_top']), console=(-1.05, -0.02), console_h=0.32, shifter_x=-0.46,
        mirror=(-0.32, 0.0, 1.16), rear_cushion=0.42, rear_back_h=0.50, front_z=0.255, rear_z=0.30, back_h=0.60, armrest_x=-0.42))
    _add(ib, pillar_trim)
    for sd in (1, -1):
        _add(ib, shell_skin(shell, 'sill', 'belt_up', -2.28, -1.90, offset=0.045, side=sd, mat='M_IntTrim'))
    _add(ib, prim_box((0.52, 1.10, 0.03), (-2.06, 0, 0.40), mat='M_IntCarpet', bevel=0.008, segments=1))
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (-0.37, 0.36, 0.865)
    swb, axis = build_steering_wheel(rim_radius=0.18, tilt=24.0)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision hulls + empties
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.32, -1.4, -0.4, 0.4], low, z_clip=(0.19, 0.93), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 0.99) - 0.012)) for p in
         hull_points_from_shell(shell, [0.4, 1.4, 2.32], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.22, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.14, -0.4, -1.1, -1.8, -2.1], ['belt_up', 'edge', 'top_c'], z_clip=(0.90, None), shrink=0.05)],
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
    rv = lamp_point(c_tail - UT * 0.10 - VL * 0.022, RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', rv)
    E('CAM_Hood', (0.95, 0.0, 0.95), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.94, 0.36, 1.17), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.42, 0.0, 0.40), 'ARROWS', 0.15)
    xr = min(p[0] for p in ex_pts)
    E('EXHAUST_L', (xr, 0.60, 0.40))
    E('EXHAUST_R', (xr, -0.60, 0.40))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 2.0]
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
            print("[car05] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
