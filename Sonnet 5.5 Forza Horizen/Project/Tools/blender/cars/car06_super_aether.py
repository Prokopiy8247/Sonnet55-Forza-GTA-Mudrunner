"""
car06_super_aether.py - parametric, idempotent build of the player car #6 "Aether" (mid-engine wedge supercar, AWD).
Built with the shared car kit (Tools/blender/lib/carkit.py) + Tools/blender/lib/carkit_ext_05_06_07.py (see Docs/CARKIT_API.md).

    CAR06_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "uv3" | "all"
    exec(compile(open(r"<project>/Tools/blender/cars/car06_super_aether.py", encoding="utf8").read(), "car06", "exec"), globals())

Design: cab-forward wedge, 1.14 m low, 2.02 m wide, crowned front fenders, side intakes in front of the rear wheels, glass engine
hatch over louvres + a V8, scissor-door cut lines, diffuser + swan-neck wing, 20 inch (front) / 21 inch (rear) wheels.
4.50 x 2.02 x 1.14 m, wheelbase 2.70 m.  Staged at x = 72 m.
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

CAR = "car06_super_aether"
STAGE = globals().get("CAR06_STAGE", "all")

P = dict(
    id=CAR, display_name="Aether", index=6,
    L=4.50, W=2.02, H=1.14, wheelbase=2.70, track_f=1.64, track_r=1.64,
    r_f=0.34, r_r=0.36, w_f=0.245, w_r=0.305, ride=0.10,          # 245/35 R20 front, 305/30 R21 rear
    x_ws_base=1.00, x_ws_top=0.06,                                # windscreen
    x_hatch_top=-0.80, x_hatch_base=-1.62,                        # glass engine hatch
    x_front=2.30, x_rear=-2.20, cap_bulge=0.04, round_front=0.10, round_rear=0.09,
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
X0, X1 = P['x_rear'] + P['cap_bulge'], P['x_front'] - P['cap_bulge']          # loft end stations
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
ARCH_PAD = 0.034
GROOVE = groove_profile(0.0055, 0.007)


def body_curves():
    zt = fillet_profile(
        [(X0, 0.80), (-2.10, 0.905), (-1.60, 0.965), (-0.65, 1.115), (0.05, 1.138), (1.00, 0.760), (1.40, 0.735), (1.85, 0.640),
         (2.20, 0.500), (X1, 0.43)],
        [0, 0.06, 1.0, 1.6, 0.35, 0.3, 3.0, 3.5, 0.4, 0.10, 0], step=0.01)
    zf = smooth_keys([(X0, 0.30), (-2.10, 0.26), (-1.95, 0.19), (-1.65, 0.13), (-1.2, 0.10), (-0.5, 0.09), (0.5, 0.09), (1.2, 0.09),
                      (1.9, 0.10), (2.15, 0.13), (2.22, 0.17), (X1, 0.22)], sigma=0.07)
    hwm = smooth_keys([(X0, 0.62), (-2.10, 0.78), (-2.00, 0.90), (-1.80, 0.985), (-1.55, 1.008), (-1.35, 1.012), (-1.0, 1.000),
                       (-0.5, 0.965), (0, 0.940), (0.6, 0.950), (1.0, 0.975), (1.35, 0.990), (1.7, 0.985), (2.0, 0.94), (2.15, 0.85),
                       (2.22, 0.74), (X1, 0.58)], sigma=0.07)
    zw = smooth_keys([(X0, 0.50), (-1.8, 0.55), (-1.35, 0.56), (-0.6, 0.50), (0, 0.47), (0.8, 0.47), (1.35, 0.50), (2.0, 0.45),
                      (X1, 0.36)], sigma=0.15)
    zb = smooth_keys([(X0, 0.78), (-2.0, 0.84), (-1.6, 0.88), (-1.35, 0.89), (-0.9, 0.855), (-0.5, 0.80), (0, 0.76), (0.5, 0.72),
                      (1.0, 0.65), (1.35, 0.62), (1.9, 0.53), (2.22, 0.45), (X1, 0.40)], sigma=0.10)
    zc = smooth_keys([(-1.9, 0.66), (-1.35, 0.70), (-0.8, 0.62), (0, 0.56), (0.8, 0.54), (1.35, 0.50), (2.0, 0.46)], sigma=0.15)
    cdepth = smooth_keys([(X0, 0.0), (-1.9, 0.01), (-1.35, 0.04), (-0.8, 0.06), (0, 0.055), (0.8, 0.045), (1.35, 0.025), (1.9, 0.01),
                          (X1, 0.0)], sigma=0.12)
    tuck = as_curve(smooth_keys([(X0, 0.03), (-1.9, 0.04), (-1.35, 0.04), (-0.8, 0.06), (0, 0.07), (0.6, 0.06), (1.35, 0.04),
                                 (2.0, 0.03), (X1, 0.03)], sigma=0.15))
    hw_ratio = as_curve(smooth_keys([(X0, 0.82), (-1.9, 0.82), (-1.4, 0.78), (-0.9, 0.72), (-0.65, 0.64), (-0.3, 0.60), (0.05, 0.60),
                                     (0.4, 0.70), (1.0, 0.80), (1.5, 0.84), (X1, 0.84)], sigma=0.12))
    dz = as_curve(smooth_keys([(X0, 0.03), (-1.6, 0.04), (-0.7, 0.05), (-0.3, 0.07), (0.05, 0.075), (0.5, 0.06), (1.0, 0.05),
                               (X1, 0.03)], sigma=0.12))
    rail_w = smooth_keys([(X0, 0.05), (-2.0, 0.08), (-1.8, 0.16), (-1.62, 0.21), (-1.2, 0.21), (-0.9, 0.20), (-0.7, 0.09),
                          (-0.3, 0.07), (0.5, 0.06), (1.0, 0.05), (X1, 0.05)], sigma=0.10)
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-0.7, 0.0), (-0.3, 1.0), (0.7, 1.0), (1.0, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - tuck(x)

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.06 + 0.05 * door_win(x)),
        zs=lambda x: zfc(x) + 0.095,
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
        print("[car06 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="AWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. loft + sculpt
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    rr_, rf_ = P['round_rear'], P['round_front']
    xs = station_list(X0, X1, dx=0.055, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_hatch_top'], P['x_hatch_base']] +
                            end_round_stations(X0, rr_, 6, at_start=True) + end_round_stations(X1, rf_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr_, round_x1=rf_)

    def sculpt(x, ay, z):
        dz = 0.0
        wz = smoothstep(0.40, 0.60, z)
        dz += bump(x, ay, z, 1.38, 0.80, 0.66, 0.60, 0.30, 5.0, 0.088) * wz                  # crowned front fenders
        dz += bump(x, ay, z, -1.40, 0.84, 0.90, 0.62, 0.30, 5.0, 0.035) * smoothstep(0.55, 0.80, z)   # rear haunches
        dy = bump(x, ay, z, 0.10, 1.0, 0.40, 0.80, 0.40, 0.14, -0.030)                                  # sculpted door scallop
        return (0.0, dy, dz)
    shell_deform(shell, sculpt)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, pillar_cols, roof_cols = set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        roof_cols |= shell_quad_cols(shell, 'edge', 'top_c', sd)
    for z_cut, in_zone in ((0.36, lambda x: x > 1.95), (0.46, lambda x: x < -1.95)):
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
        elif tag in pillar_cols and (-0.82 < c.x < 1.02 and c.z > 0.66):
            m = 'M_Paint2'                           # blacked A-pillar / window frames
        elif tag in roof_cols and (P['x_hatch_top'] - 0.05 < c.x < P['x_ws_top'] + 0.05) is False and \
                (P['x_hatch_base'] - 0.04 < c.x < P['x_hatch_top'] + 0.05):
            m = 'M_Paint2'                           # carbon frame around the engine hatch
        elif (c.x > 1.95 and c.z < 0.36) or (c.x < -1.95 and c.z < 0.46):
            m = 'M_TrimBlack'
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
        cutters.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.52, mat='M_Underbody'))

    RAY_L = (0, -1, 0)
    VL = Vector((0, 0, 1))
    RAY_F, RAY_R = (-1, 0, 0), (1, 0, 0)

    door = [(0.82, 0.74), (0.84, 0.60), (0.85, 0.45), (0.82, 0.30), (0.74, 0.225), (0.60, 0.205), (0.2, 0.200), (-0.3, 0.200),
            (-0.55, 0.215), (-0.64, 0.30), (-0.68, 0.50), (-0.70, 0.70), (-0.70, 0.80)]
    add_pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    # scissor-door roof cut: continues the door line over the roof edge towards the centre line
    roof_cut = [(0.04, 0.50), (-0.10, 0.47), (-0.40, 0.47), (-0.62, 0.52), (-0.74, 0.62)]
    add_pair(surface_sweep(surf0, resample_poly([Vector((x, y, 0)) for x, y in roof_cut], 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    hood_l = [(1.00, 0.52), (1.4, 0.52), (1.8, 0.47), (2.08, 0.38), (2.20, 0.25), (2.24, 0.0)]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    # engine cover clamshell
    cov_l = [(-0.72, 0.62), (-1.0, 0.72), (-1.5, 0.76), (-1.9, 0.70), (-2.08, 0.58), (-2.14, 0.40), (-2.16, 0.0)]
    cp = [Vector((x, y, 0)) for x, y in cov_l] + [Vector((x, -y, 0)) for x, y in reversed(cov_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(cp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    ff = surface_sweep(surf0, circle_pts(-1.05, 0.78, 0.065, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody')
    if ff is not None:
        cutters.append(ff)
    lap("grooves + arches ready")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps / intakes / vents / diffuser / exhaust
    # ------------------------------------------------------------------------------------------------------------------
    RH = ('radial', Vector((1.80, 0.28, 0.36)))
    UL = Vector((0.80, -0.60, 0.0)).normalized()
    c_head = Vector((2.10, 0.60, 0.50))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.27, height=0.036, rot=0.30, floor_mat='M_TrimBlack')
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)

    def nose_pocket(center, outline, depth, mat='M_TrimBlack', lift=0.09):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False, lift=lift)

    # wide front mouth with honeycomb + two side air curtains
    mouth = outline_superellipse(0.60, 0.095, 3.2, 36)
    pk = nose_pocket((2.45, 0.0, 0.235), mouth, 0.08)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in mouth], kind='bars', pitch=0.034, bar=0.009, depth=0.024, frame=0.012)
        conform_to_surface(g, surf0, (2.45, 0, 0.235), RAY_F, (0, 1, 0), VL, sink=0.045)
        keep(g)
    dC = Vector((-0.80, -0.60, 0.0)).normalized()
    UC = Vector((0.60, -0.80, 0.0)).normalized()
    cc = Vector((2.20, 0.72, 0.265))
    pk = pocket_cutter(surf0, outline_rrect(0.20, 0.085, 0.02, 3), cc, dC, depth=0.06, taper=0.9, mat='M_TrimBlack', axes=(UC, VL),
                       floor_follows=True)
    if pk is not None:
        add_pair(pk)
        for k in range(-3, 4):
            add_pair(surface_sweep(surf0, [cc + UC * (k * 0.026) + VL * v for v in (-0.034, 0.0, 0.034)], dC,
                                   [(-0.0028, -0.045), (0.0028, -0.045), (0.0028, -0.012), (-0.0028, -0.012)], mat='M_TrimBlack'),
                     into=inserts)
    # hood heat extractors (louvred) and fender-crown vents
    for hy in (0.27, -0.27):
        cut, sl = slat_vent(surf0, Vector((1.60, hy, 0.0)), (0, 0, -1), (1, 0, 0), (0, 1, 0), 0.40, 0.19, 7, depth=0.035)
        if cut is not None:
            cutters.append(cut)
            for b in sl:
                keep(b)
    for s in (1, -1):
        cut, sl = slat_vent(surf0, Vector((1.40, s * 0.82, 0.0)), (0, 0, -1), (1, 0, 0), (0, 1, 0), 0.26, 0.085, 4, depth=0.03)
        if cut is not None:
            cutters.append(cut)
            for b in sl:
                keep(b)
    # big side intake in front of the rear wheel (hex mesh) + scoop lip
    sc = Vector((-0.80, 1.2, 0.51))
    sk = pocket_cutter(surf0, outline_rrect(0.34, 0.27, 0.04, 4), sc, RAY_L, depth=0.14, lift=0.08, taper=0.92, mat='M_TrimBlack',
                       floor_follows=True, axes=(Vector((1, 0, 0)), VL))
    if sk is not None:
        add_pair(sk)
        g = grille_mesh(outline_rrect(0.32, 0.25, 0.04, 4), kind='hex', pitch=0.034, bar=0.006, depth=0.02, frame=0.010)
        conform_to_surface(g, surf0, (-0.80, 1.2, 0.51), RAY_L, (-1, 0, 0), VL, sink=0.06)
        keep(g)
        keep(mirrored_copy(g))
    else:
        lap("side intake FAILED")

    # --- tail ------------------------------------------------------------------------------------------------------------
    RT = ('radial', Vector((-1.85, 0.30, 0.70)))
    UT = Vector((0.40, 0.92, 0.0)).normalized()
    c_tail = Vector((-2.17, 0.68, 0.80))
    cut, ins = build_taillight(surf0, c_tail, RT, (UT, VL), length=0.200, height=0.052, rot=-0.10, depth=0.034)
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)
    keep(surface_sweep(surf0, [Vector((-2.5, y, 0.745)) for y in [0.50 - 0.1 * i for i in range(11)]], RAY_R,
                       rib_profile(0.012, 0.004, 0.006, 0.0016), mat='M_Taillight'))
    # engine heat extractor between the lamps (hex mesh)
    hx = outline_rrect(0.76, 0.12, 0.03, 4)
    pk = pocket_cutter(surf0, hx, Vector((-2.5, 0, 0.625)), RAY_R, depth=0.08, lift=0.09, taper=0.97, mat='M_TrimBlack', floor_follows=False)
    if pk is not None:
        cutters.append(pk)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in hx], kind='hex', pitch=0.034, bar=0.0062, depth=0.02, frame=0.010)
        conform_to_surface(g, surf0, (-2.5, 0, 0.625), RAY_R, (0, -1, 0), VL, sink=0.05)
        keep(g)
    cut, plate = plate_recess(surf0, (-2.5, 0.0, 0.485), RAY_R, width=0.40, height=0.10, plate_w=0.38, plate_h=0.088)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    cut, fins = build_diffuser(surf0, (-2.5, 0.0, 0.34), RAY_R, width=1.30, height=0.10, fins=8, fin_h=0.085)
    if cut is not None:
        cutters.append(cut)
        for fb in fins:
            keep(fb)
    ex_pts = []
    for yy in (0.20, -0.20):
        h = surf0.hit(Vector((0, yy, 0.40)), RAY_R)
        xh = h[0].x if h else -2.20
        cutters.append(prim_cylinder(radius=0.056, depth=0.20, segments=24, axis='X', center=(xh + 0.05, yy, 0.40), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.046, length=0.14, lip=0.005)
        bmesh.ops.transform(tip, matrix=T((xh + 0.004, yy, 0.40)), verts=tip.verts)
        keep(tip)
        ex_pts.append((xh, yy))
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
    n_lip = bevel_arch_lips(bm, WHEELS, ARCH_PAD, tc, width=0.010, segments=2, y_min=0.40)
    lap("rims %d, arch lips %d" % (n_rim, n_lip))

    # side blades, splitter, wing, handles, mirrors, wipers
    add_pair(surface_sweep(surf0, poly_pts([(-0.60, 0.215), (-0.3, 0.208), (0.0, 0.205), (0.3, 0.208), (0.62, 0.215)], subdiv=2), RAY_L,
                           rib_profile(0.06, 0.016, 0.014, 0.006), mat='M_TrimBlack'), into=inserts)
    add_pair(build_splitter(surf0, RAY_F, z=0.125, z_top=0.133, z_bot=0.105, out=0.060, inn=0.08, y_max=0.85), into=inserts)
    add_pair(door_handle(surf0, -0.18, 0.66, RAY_L, length=0.14), into=inserts)
    keep(surface_sweep(surf0, [Vector((1.045, y, 0)) for y in [0.66 - 0.08 * i for i in range(17)]], (0, 0, -1),
                       rib_profile(0.07, 0.009, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((1.00, 0.10), (0.95, 0.62)), ((1.00, -0.62), (0.95, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.012, 0.012, 0.0095, 0.003), mat='M_TrimBlack'))
    # rear wing on swan-neck pylons (deck height from the surface)
    wx, wz = -1.98, 1.02
    hz = surf0.hit(Vector((wx - 0.085, 0.40, 0)), (0, 0, -1))
    z_base = (hz[0].z if hz else 0.90) - 0.045
    wing = build_swan_wing(span=1.56, chord=0.28, thick=0.034, stand_y=0.40, drop=wz - z_base, endplate_h=0.105)
    bmesh.ops.transform(wing, matrix=T((wx, 0, wz)), verts=wing.verts)
    keep(wing)
    keep(surface_patch(surf0, outline_ellipse(0.028, 0.028, 20), Vector((-2.5, 0, 0.865)), RAY_R, offset=-0.0015, rings=2, mat='M_Chrome'))
    # mirrors: slim carbon caps on stalks
    mh = surf0.hit(Vector((0.78, 0.0, 0.70)), RAY_L)
    my = (mh[0].y - 0.012) if mh else 0.90
    zm = 0.80
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint2', length=0.17, width=0.085, height=0.075, arm_len=0.075)
        bmesh.ops.transform(m, matrix=T((0.80, s * my, zm)), verts=m.verts)
        keep(m)

    # engine bay under the glass hatch + louvres
    keep(build_engine_bay(x0=-2.00, x1=-0.62, z_floor=0.30, half_w=0.56))

    def skin_z(x):
        h = surf0.hit(Vector((x, 0.0, 0.0)), (0, 0, -1))
        return h[0].z if h else 1.0
    lx = [-1.57 + 0.075 * i for i in range(11)]
    keep(build_louvre_slats(lx, lambda x: 0.50, lambda x: skin_z(x) - 0.060, tilt=32.0, height=0.040, thick=0.010, mat='M_Paint2'))

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
    A0, A1 = (0.88, 0.735), (-0.02, 1.075)
    C0, C1 = (-0.70, 0.80), (-0.38, 1.085)

    def behind(c, p0, p1):
        xl = p0[0] + (p1[0] - p0[0]) * (c.z - p0[1]) / (p1[1] - p0[1])
        return c.x < xl

    def plane(p0, p1):
        return (Vector((p0[0], 0, p0[1])), Vector((-(p1[1] - p0[1]), 0, p1[0] - p0[0])).normalized())

    def side_zone(f):
        return f[tc] in side_cols

    def side_pred(f):
        if f[tc] not in side_cols:
            return False
        c = f.calc_center_median()
        return behind(c, A0, A1) and not behind(c, C0, C1)

    def ws_pred(f):
        return f[tc] in top_cols and P['x_ws_top'] < f.calc_center_median().x < P['x_ws_base']

    def hatch_pred(f):
        return f[tc] in top_cols and P['x_hatch_base'] < f.calc_center_median().x < P['x_hatch_top']

    wins = [dict(name='side', pred=side_pred, zone=side_zone, planes=[plane(A0, A1), plane(C0, C1)]),
            dict(name='windscreen', pred=ws_pred), dict(name='hatch', pred=hatch_pred)]
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass: %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    pillar_trim = inner_trim_from_faces(
        bm, lambda f: f[tc] != 0 and (f[tc] in pillar_cols or f[tc] in roof_cols) and (P['x_hatch_base'] - 0.1 < f.calc_center_median().x < P['x_ws_base'] + 0.1)
        and f.calc_center_median().z > 0.70 and f.calc_center_median().x > -0.80, offset=0.03, mat='M_IntTrim')

    heal_slivers(bm)
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    lap("healed %d sliver faces on the finished mesh" % heal_mesh(body))
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels (front 20", rear 21", dark star wheels with chrome centre nut)
    # ------------------------------------------------------------------------------------------------------------------
    for name, w in WHEELS.items():
        front = name[0] == 'F'
        wb = build_wheel(radius=w['radius'], width=w['width'], rim_radius=0.2667 if front else 0.2794, rim_width=w['width'] - 0.045,
                         spokes=10, style='star', side=w['side'], hub_radius=0.062, brake_disc_radius=0.172 if front else 0.180,
                         caliper_angle=35.0 if front else 20.0, segments=48, tyre_segments=64, rim_mat='M_RimDark',
                         center_cap_mat='M_Chrome', dish=0.05)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior_ext(shell, dict(
        floor_z=0.20, front_x=-0.04, driver_y=0.36, dash_x_back=0.60, dash_x_front=0.90, dash_z_top=0.79, dash_z_low=0.44,
        hw=0.74, x_front_floor=0.88, x_rear_floor=-0.62, seats_rear=False, door_x=(-0.66, 0.80), quarter_x=(-0.661, -0.65),
        roof_x=(P['x_hatch_top'] + 0.02, P['x_ws_top']), console=(-0.55, 0.62), console_h=0.26, shifter_x=0.10,
        mirror=(0.16, 0.0, 1.07), back_h=0.52, front_z=0.215, front_recline=26.0, seat_w=0.52, armrest_x=0.20, rear_x=-1.5))
    _add(ib, pillar_trim)
    # bulkhead between cabin and engine bay + rear parcel under the hatch
    _add(ib, prim_box((0.04, 1.34, 0.66), (-0.64, 0, 0.53), mat='M_IntTrim', bevel=0.01, segments=1))
    _add(ib, prim_box((0.02, 0.50, 0.20), (-0.615, 0.0, 0.58), mat='M_TrimBlack', bevel=0.005, segments=1))
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.45, 0.36, 0.755)
    swb, axis = build_steering_wheel(rim_radius=0.172, tilt=22.0, flat_bottom=True)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision hulls + empties
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.14, -1.5, -0.6, 0.3], low, z_clip=(0.17, 0.88), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 0.74) - 0.012)) for p in
         hull_points_from_shell(shell, [0.3, 1.2, 2.2], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.20, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.9, 0.2, -0.5, -1.2, -1.9], ['belt_up', 'edge', 'top_c'], z_clip=(0.76, None), shrink=0.05)],
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
    rv = lamp_point(c_tail - UT * 0.09 - VL * 0.02, RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', rv)
    E('CAM_Hood', (0.85, 0.0, 0.84), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.14, 0.36, 1.00), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.36, 0.0, 0.32), 'ARROWS', 0.15)
    xr = min(p[0] for p in ex_pts)
    E('EXHAUST_L', (xr, 0.20, 0.40))
    E('EXHAUST_R', (xr, -0.20, 0.40))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.75 and abs(v.co.x) < 2.0]
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
            print("[car06] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
