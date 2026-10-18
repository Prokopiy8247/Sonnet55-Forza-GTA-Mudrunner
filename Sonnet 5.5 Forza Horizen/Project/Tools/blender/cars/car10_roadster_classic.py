"""
car10_roadster_classic.py - parametric, idempotent build of player car #10 "Brisa" (vintage open roadster, RWD, LHD).
Body = lofted tub + bonnet with a boolean cockpit and cut-down doors, four separately swept cycle wings (M_Paint2 accent), running
boards, chrome radiator shell, round bucket headlamps on the wing tops, blade bumpers, folded soft-top boot (M_Paint2) and a tiny
windscreen (the only glass).  Wire wheels with laced spokes.  Open cockpit with a fully modelled interior.  Built with carkit.py +
carkit_ext_08_09_10.py.

    CAR10_STAGE = "all"      # optional: "geometry" | "uv1" | "uv2" | "all" (default)
    exec(compile(open(r"<project>/Tools/blender/cars/car10_roadster_classic.py", encoding="utf8").read(), "car10", "exec"), globals())
Car space: +X forward, +Y left (driver side, LHD), +Z up; origin on the ground under the middle of the wheelbase.
Staged at x = 120 m (cars row, index 10), collection FORZA_UE/Cars/car10_roadster_classic, root car10_roadster_classic_ROOT.
Interior note: M_IntTrim is the wooden trim (dash board, steering wheel rim) on this car, M_IntSeat the leather.
"""
import os
import time
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
_KIT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit.py")
_EXT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_08_09_10.py")
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())

CAR = "car10_roadster_classic"
STAGE = globals().get("CAR10_STAGE", "all")

P = dict(
    id=CAR, display_name="Brisa", index=10,
    L=3.85, W=1.62, H=1.22, wheelbase=2.30, track_f=1.30, track_r=1.32,
    r_f=0.30, r_r=0.31, w_f=0.12, w_r=0.125, ride=0.22,
    x0=-1.78, x1=1.40,
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
GROOVE = groove_profile(0.0055, 0.007)
VL = Vector((0, 0, 1))
RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)
FLOOR_Z = 0.34                         # cockpit floor (top of the carpet)
COCKPIT = dict(x0=-0.60, x1=0.455, hw=0.485)
DOOR = dict(x0=-0.30, x1=0.34, z_top=0.735, z_bot=0.37)


def body_curves():
    zt = fillet_profile([(-1.78, 0.585), (-1.62, 0.715), (-1.25, 0.800), (-0.70, 0.838), (0.48, 0.852), (0.56, 0.870), (1.40, 0.860)],
                        [0, 0.6, 0.7, 0.25, 0.08, 0.05, 0], step=0.01)
    zf = smooth_keys([(-1.78, 0.46), (-1.5, 0.36), (-1.1, 0.30), (0.45, 0.30), (0.6, 0.34), (1.40, 0.42)], sigma=0.06)
    hwm = smooth_keys([(-1.78, 0.17), (-1.62, 0.28), (-1.30, 0.46), (-0.80, 0.560), (0.40, 0.565), (0.50, 0.52), (0.56, 0.30), (0.66, 0.272),
                       (1.40, 0.225)], sigma=0.03)
    zw = smooth_keys([(-1.8, 0.56), (1.4, 0.56)], sigma=0.2)
    zb = smooth_keys([(-1.78, 0.50), (-1.60, 0.63), (-1.25, 0.745), (-0.8, 0.795), (0.40, 0.805), (0.56, 0.79), (1.40, 0.775)], sigma=0.05)
    hwe = smooth_keys([(-1.78, 0.10), (-1.62, 0.20), (-1.30, 0.40), (-0.80, 0.50), (0.40, 0.505), (0.49, 0.46), (0.56, 0.19), (0.66, 0.17),
                       (1.40, 0.14)], sigma=0.03)
    dz = as_curve(smooth_keys([(-1.78, 0.04), (-1.2, 0.035), (0.4, 0.03), (0.56, 0.075), (1.4, 0.08)], sigma=0.05))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    return dict(zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, hwe=hwe, ze=lambda x: ztc(x) - dz(x), hwb=lambda x: hwmc(x) - 0.01,
                zs=lambda x: zfc(x) + 0.07, belt_step=0.03, crease=0.02, rail_w=0.05)


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car10 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="RWD", steering_side="LHD")
    inserts, cutters = [], []

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

    # ==================================================================================================================
    # 1. tub + bonnet shell
    # ==================================================================================================================
    cv = body_curves()
    x0, x1 = P['x0'], P['x1']
    rr0, rr1 = 0.16, 0.05
    xs = station_list(x0, x1, dx=0.055, end_dx=0.02, end_len=0.25, min_gap=0.007,
                      extra=[0.42, 0.46, 0.50, 0.53, 0.56, 0.60, -0.62, -0.60] + end_round_stations(x0, rr0, 6, at_start=True)
                      + end_round_stations(x1, rr1, 4, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=0.07, ring_density=1.5, cap_rings=4, round_x0=rr0, round_x1=rr1)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))
    under_cols = set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
    bm.normal_update()
    surf0 = Surface(bm)
    for f in bm.faces:
        f.material_index = mi('M_Underbody' if f[tc] in under_cols else 'M_Paint')

    # ---- cockpit pocket (boolean) + cut-down door scoops ------------------------------------------------------------
    cx0, cx1, chw = COCKPIT['x0'], COCKPIT['x1'], COCKPIT['hw']
    pocket = prim_prism(outline_rrect4(cx0, cx1, -chw, chw, (0.05, 0.17, 0.17, 0.05), 6), 1.0, plane='XY',
                        center=(0.0, 0.0, FLOOR_Z + 0.5), mat='M_Paint')
    for f in pocket.faces:
        if f.normal.z < -0.9:
            f.material_index = mi('M_IntCarpet')
    cutters.append(pocket)
    dxc = 0.5 * (DOOR['x0'] + DOOR['x1'])
    dlen = (DOOR['x1'] - DOOR['x0']) - 0.07
    for s in (1, -1):
        sc = prim_prism(outline_rrect(dlen, 0.34, 0.12, 6), 1.0, plane='XY', center=(dxc, s * 0.585, DOOR['z_top'] + 0.5), mat='M_Paint')
        cutters.append(sc)
    # door shut lines (left, mirrored)
    door = [(DOOR['x1'], DOOR['z_top'] - 0.02), (DOOR['x1'], 0.43), (DOOR['x1'] - 0.04, DOOR['z_bot']), (DOOR['x1'] - 0.10, DOOR['z_bot'] - 0.012),
            (DOOR['x0'] + 0.10, DOOR['z_bot'] - 0.012), (DOOR['x0'] + 0.04, DOOR['z_bot']), (DOOR['x0'], 0.43), (DOOR['x0'], DOOR['z_top'] - 0.02)]
    add_pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    # bonnet: louvres (rows of grooves on the side panels), centre seam, rear seam
    for k in range(7):
        zl = 0.515 + 0.046 * k
        add_pair(surface_sweep(surf0, [Vector((0.74 + 0.05 * i, 0.0, zl)) for i in range(12)], RAY_L, groove_profile(0.0075, 0.012),
                               mat='M_Underbody'))
    cutters.append(surface_sweep(surf0, [Vector((0.575, y, 0)) for y in [-0.20 + 0.04 * i for i in range(11)]], (0, 0, -1), GROOVE,
                                 mat='M_Underbody'))
    # fuel filler pocket + rear deck seam
    cutters.append(surface_sweep(surf0, [Vector((-1.33 + 0.0, y, 0)) for y in [-0.20 + 0.04 * i for i in range(11)]], (0, 0, -1), GROOVE,
                                 mat='M_Underbody'))
    lap("cutters ready (%d)" % len([c for c in cutters if c is not None]))

    cutters = [c for c in cutters if c is not None]
    bm = bm_boolean(bm, cutters)
    lap("boolean: %d faces, manifold=%s" % (len(bm.faces), is_manifold(bm)))
    bevel_hard_edges(bm, angle_deg=70.0, width=0.004, segments=1,
                     edge_filter=lambda e: len(e.link_faces) == 2 and any(f.material_index == mi('M_Paint') for f in e.link_faces)
                     and min(v.co.z for v in e.verts) > 0.6)

    # ==================================================================================================================
    # 2. rolled cockpit rim, wings, running boards, radiator, lamps, bumpers, windscreen, boot, details
    # ==================================================================================================================
    def smooth_step_f(a, b, x):
        t = clamp((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3 - 2 * t)

    rim_pts = outline_rrect4(cx0, cx1, -chw, chw, (0.05, 0.17, 0.17, 0.05), 8)
    rim_path = []
    for (u, v) in rim_pts:
        h = surf0.hit(Vector((u, v * 0.985, 0.0)), (0, 0, -1))
        zr = (h[0].z if h else 0.84) + 0.002
        if abs(v) > 0.3:
            f = smooth_step_f(0.40, 0.31, u) * smooth_step_f(-0.34, -0.26, u)
            zr = zr * (1 - f) + (DOOR['z_top'] + 0.004) * f
        rim_path.append(Vector((u, v, zr)))
    keep(tube(rim_path, 0.0165, 12, 'M_IntSeat', closed=True))

    for s_ in (1, -1):
        pass
    add_pair(door_handle(surf0, -0.17, 0.62, RAY_L, length=0.10, width=0.022, height=0.014, mat='M_Chrome'), into=inserts)
    for hz in (0.47, 0.64):
        add_pair(prim_cylinder(radius=0.011, depth=0.05, segments=10, axis='Z', center=(DOOR['x1'] + 0.012, 0.572, hz), mat='M_Chrome'), into=inserts)

    # coachline (accent stripe along the tub) + chrome bonnet hinge strip
    cl = [Vector((x, 0.0, 0.595)) for x in [0.36 - 0.08 * i for i in range(0, 25)]]
    add_pair(surface_sweep(surf0, cl, RAY_L, rib_profile(0.014, 0.004, 0.005, 0.002), mat='M_Paint2'), into=inserts)
    keep(surface_sweep(surf0, [Vector((0.60 + 0.07 * i, 0.0, 0.0)) for i in range(12)], (0, 0, -1), rib_profile(0.016, 0.006, 0.004, 0.002),
                       mat='M_Chrome'))
    for s_ in (1, -1):               # bonnet side clips
        for hx in (0.82, 1.14):
            keep(prim_box((0.030, 0.010, 0.050), (hx, s_ * 0.280, 0.50), mat='M_Chrome', bevel=0.004, segments=1))

    # ---- cycle wings (left built, right mirrored) ----------------------------------------------------------------------
    pathF, a0F, a1F = fender_path(XF, 0.30, 0.395, -62.0, 80.0, (0.45, 0.312), True, n_arc=28, n_tail=12, l1=0.20, l2=0.14)
    wF = fender_loft(pathF, 0.29, 0.805, [(0, 1.0), (0.86, 1.0), (1.0, 0.46)], [(0, 0.0), (0.12, 0.25), (0.30, 1.0), (0.82, 0.9), (1.0, 0.18)],
                     [(0, 0.35), (0.15, 0.7), (0.30, 1.0), (0.92, 0.95), (1.0, 0.55)])
    add_pair(wF, into=inserts)
    pathR, a0R, a1R = fender_path(XR, 0.31, 0.405, -84.0, 62.0, (-0.40, 0.312), False, n_arc=28, n_tail=12, l1=0.20, l2=0.14)
    wR = fender_loft(pathR, 0.30, 0.805, [(0, 0.6), (0.12, 1.0), (1.0, 1.0)], [(0, 0.45), (0.14, 1.0), (0.70, 1.0), (0.88, 0.25), (1.0, 0.0)],
                     [(0, 0.8), (0.05, 1.0), (0.70, 1.0), (0.85, 0.6), (1.0, 0.35)])
    add_pair(wR, into=inserts)
    # running boards: rubber mat with ribs, chrome outer edge, black apron
    for s in (1, -1):
        keep(prim_box((0.92, 0.30, 0.030), (0.025, s * 0.655, 0.288), mat='M_Paint2', bevel=0.010, segments=1))
        keep(prim_box((0.84, 0.23, 0.008), (0.025, s * 0.655, 0.306), mat='M_Rubber', bevel=0.002, segments=1))
        for k in range(14):
            keep(prim_box((0.012, 0.22, 0.004), (-0.36 + k * 0.0625, s * 0.655, 0.312), mat='M_TrimBlack', bevel=0.001, segments=1))
        keep(prim_box((0.90, 0.014, 0.032), (0.025, s * 0.812, 0.296), mat='M_Chrome', bevel=0.005, segments=1))
        # wing stays (chrome) from the wing lip to the tub
        for sx in (XF + 0.28, XF - 0.30):
            keep(tube([(sx, s * 0.74, 0.52 + (0.02 if sx > XF else 0.0)), (sx, s * 0.58, 0.40)], 0.0065, 6, 'M_Chrome'))
        for sx in (XR + 0.30, XR - 0.30):
            keep(tube([(sx, s * 0.76, 0.52), (sx, s * 0.56, 0.42)], 0.0065, 6, 'M_Chrome'))

    # ---- radiator shell, cap, grille ------------------------------------------------------------------------------------
    rad_out = outline_rrect(0.47, 0.54, 0.09, 6)
    rad_in = outline_rrect(0.405, 0.475, 0.06, 6)
    rad_o = prim_prism(rad_out, 0.14, plane='YZ', center=(1.455, 0.0, 0.70), mat='M_Chrome')
    rad_i = prim_prism(rad_in, 0.20, plane='YZ', center=(1.455, 0.0, 0.70), mat='M_TrimBlack')
    rad = bm_boolean(rad_o, [rad_i])
    keep(rad)
    keep(prim_prism(rad_in, 0.014, plane='YZ', center=(1.497, 0.0, 0.70), mat='M_TrimBlack'))
    for k in range(-6, 7):
        keep(prim_box((0.014, 0.0075, 0.46), (1.512, k * 0.0285, 0.70), mat='M_Chrome', bevel=0.002, segments=1))
    keep(prim_box((0.014, 0.40, 0.012), (1.512, 0.0, 0.70), mat='M_Chrome', bevel=0.002, segments=1))
    keep(prim_cylinder(radius=0.026, depth=0.030, segments=16, axis='Z', center=(1.455, 0.0, 0.987), mat='M_Chrome', bevel=0.005))
    keep(prim_sphere(0.022, 14, 9, scale=(1, 1, 1.15), center=(1.455, 0.0, 1.022), mat='M_Chrome'))
    keep(prim_torus(R=0.045, r=0.007, seg_major=20, seg_minor=6, axis='X', center=(1.524, 0.0, 0.565), mat='M_Chrome'))
    keep(prim_cylinder(radius=0.034, depth=0.012, segments=18, axis='X', center=(1.526, 0.0, 0.565), mat='M_Paint2'))
    # starting-handle dog
    keep(tube([(1.52, 0.0, 0.46), (1.58, 0.0, 0.46)], 0.012, 8, 'M_Chrome'))
    keep(prim_cylinder(radius=0.020, depth=0.020, segments=10, axis='X', center=(1.52, 0.0, 0.46), mat='M_Chrome'))

    # ---- bucket headlamps on stalks (wing tops) + parking lamps ------------------------------------------------------------
    for s in (1, -1):
        stalk = tube([(1.27, s * 0.50, 0.715), (1.27, s * 0.50, 0.80)], 0.011, 10, 'M_Chrome')
        keep(stalk)
        keep(prim_box((0.09, 0.05, 0.016), (1.27, s * 0.50, 0.712), mat='M_Chrome', bevel=0.005, segments=1))
        lamp = round_lamp(0.098, 0.088, mat_shell='M_Chrome', mat_lens='M_Headlight', style='bucket')
        bmesh.ops.transform(lamp, matrix=T((1.215, s * 0.50, 0.872)), verts=lamp.verts)
        keep(lamp)
        pl = round_lamp(0.026, 0.04, mat_shell='M_Chrome', mat_lens='M_Indicator', style='tail')
        bmesh.ops.transform(pl, matrix=T((1.50, s * 0.62, 0.50), (0, -18, 0)), verts=pl.verts)
        keep(pl)

    # ---- bumpers (blade, chrome) with irons + over-riders + plate ---------------------------------------------------------
    fb = [(1.62, 0.76, 0.0), (1.74, 0.64, 0.0), (1.82, 0.42, 0.0), (1.845, 0.0, 0.0), (1.82, -0.42, 0.0), (1.74, -0.64, 0.0), (1.62, -0.76, 0.0)]
    fb = fillet_path3([Vector((x, y, 0.385)) for (x, y, z) in fb], [0, 0.18, 0.25, 0.35, 0.25, 0.18, 0], 5)
    keep(tube(fb, (0.013, 0.050), 14, 'M_Chrome'))
    for s in (1, -1):
        keep(tube(fillet_path3([(1.43, s * 0.20, 0.36), (1.62, s * 0.26, 0.37), (1.80, s * 0.30, 0.385)], [0, 0.1, 0], 4), 0.011, 8, 'M_Chrome'))
        keep(prim_box((0.030, 0.045, 0.20), (1.864, s * 0.19, 0.40), mat='M_Chrome', bevel=0.010, segments=2))
    plf = build_plate(0.30, 0.10)
    bmesh.ops.transform(plf, matrix=T((1.872, 0.0, 0.385)), verts=plf.verts)
    keep(plf)
    rb = [(-1.58, 0.70, 0.0), (-1.72, 0.58, 0.0), (-1.89, 0.36, 0.0), (-1.93, 0.0, 0.0), (-1.89, -0.36, 0.0), (-1.72, -0.58, 0.0), (-1.58, -0.70, 0.0)]
    rb = fillet_path3([Vector((x, y, 0.435)) for (x, y, z) in rb], [0, 0.18, 0.25, 0.35, 0.25, 0.18, 0], 5)
    keep(tube(rb, (0.013, 0.050), 14, 'M_Chrome'))
    for s in (1, -1):
        keep(tube(fillet_path3([(-1.62, s * 0.22, 0.40), (-1.78, s * 0.26, 0.42), (-1.90, s * 0.30, 0.435)], [0, 0.1, 0], 4), 0.011, 8, 'M_Chrome'))
        keep(prim_box((0.030, 0.045, 0.20), (-1.96, s * 0.20, 0.45), mat='M_Chrome', bevel=0.010, segments=2))

    # ---- windscreen frame (chrome), mirror stems, hinge brackets -----------------------------------------------------------
    rake = math.radians(12.0)
    zb_w, zt_w = 0.862, 1.205
    xb_w = 0.505
    xt_w = xb_w - (zt_w - zb_w) * math.tan(rake)
    hwf = 0.505
    frame = fillet_path3([Vector((xb_w, hwf, zb_w)), Vector((xt_w, hwf - 0.005, zt_w)), Vector((xt_w, -hwf + 0.005, zt_w)),
                          Vector((xb_w, -hwf, zb_w)), Vector((xb_w, hwf, zb_w))], [0, 0.035, 0.035, 0.035, 0], 6)
    keep(tube(frame, 0.0105, 10, 'M_Chrome'))
    keep(tube([(xb_w, 0.0, zb_w), (xt_w, 0.0, zt_w)], 0.008, 8, 'M_Chrome'))
    for s in (1, -1):
        keep(prim_cylinder(radius=0.020, depth=0.030, segments=14, axis='Z', center=(xb_w, s * hwf, zb_w - 0.005), mat='M_Chrome', bevel=0.004))
        keep(prim_box((0.05, 0.026, 0.014), (xb_w + 0.01, s * hwf, zb_w - 0.002), mat='M_Chrome', bevel=0.003, segments=1))
    for s in (1, -1):               # round mirrors on the windscreen posts
        keep(tube([(xt_w + 0.012, s * hwf, zt_w - 0.05), (xt_w + 0.05, s * (hwf + 0.09), zt_w - 0.03)], 0.006, 6, 'M_Chrome'))
        keep(prim_cylinder(radius=0.045, depth=0.016, segments=22, axis='X', center=(xt_w + 0.07, s * (hwf + 0.10), zt_w - 0.03), mat='M_Chrome',
                           bevel=0.004))
    # windscreen glass (own object): fix round 2 - a gently curved 6 mm pane (cylindrical bulge towards the front, 14 mm at the centre) instead of a
    # flat 44-triangle plate; it follows the raked frame and the edges stay 11 mm inside the chrome rim
    up_d = Vector((xt_w - xb_w, 0.0, zt_w - zb_w)).normalized()
    nrm_d = Vector((up_d.z, 0.0, -up_d.x))                       # forward / outward normal of the raked plane
    if nrm_d.x < 0:
        nrm_d = -nrm_d
    c_w = Vector(((xb_w + xt_w) / 2 - 0.002, 0.0, (zb_w + zt_w) / 2))
    h_w = math.hypot(xt_w - xb_w, zt_w - zb_w) - 0.024
    wh = hwf - 0.011
    rings_g = []
    for i in range(13):
        u = -1.0 + 2.0 * i / 12.0
        cb = c_w + nrm_d * (0.014 * (1.0 - u * u) - 0.010) + Vector((0.0, u * wh, 0.0))
        rings_g.append([cb + up_d * (h_w / 2) + nrm_d * 0.003, cb + up_d * (h_w / 2) - nrm_d * 0.003,
                        cb - up_d * (h_w / 2) - nrm_d * 0.003, cb - up_d * (h_w / 2) + nrm_d * 0.003])
    gl = ring_loft(rings_g, closed=True, caps=True, mat='M_Glass')
    glass = gl

    # ---- folded soft-top boot behind the seats (M_Paint2), straps + studs ------------------------------------------------
    # fix round 2: a LOW, WIDE canvas boot cover (rounded box 0.32 x 1.04 x 0.085 m with a centre seam, piping, three straps and buckles) lying
    # on the rear deck instead of the 0.36 x 0.22 m torpedo tube of round 1
    boot_x, boot_z = -0.85, 0.872
    bw, bl, bh = 0.32, 1.04, 0.085
    keep(prim_box((bw, bl, bh), (boot_x, 0.0, boot_z), mat='M_Paint2', bevel=0.032, segments=3))
    keep(prim_box((0.004, bl * 0.90, 0.004), (boot_x, 0.0, boot_z + bh / 2 + 0.0005), mat='M_TrimBlack', bevel=0.001, segments=1))      # centre seam
    for sx in (-1, 1):                                                                                                                # piping along the long edges
        keep(tube([(boot_x + sx * (bw / 2 - 0.020), -bl / 2 + 0.03, boot_z + bh / 2 - 0.004), (boot_x + sx * (bw / 2 - 0.020), bl / 2 - 0.03, boot_z + bh / 2 - 0.004)],
                  0.0042, 6, 'M_IntTrim'))
    loop = [Vector((boot_x + u, 0.0, boot_z + v)) for (u, v) in outline_rrect(bw + 0.010, bh + 0.010, 0.034, 5)]
    for yy in (-0.32, 0.0, 0.32):
        keep(tube([Vector((p.x, yy, p.z)) for p in loop], 0.0072, 6, 'M_IntTrim', closed=True))
        keep(prim_box((0.022, 0.032, 0.008), (boot_x, yy, boot_z + bh / 2 + 0.0085), mat='M_Chrome', bevel=0.002, segments=1))          # buckle
        keep(prim_cylinder(radius=0.011, depth=0.008, segments=10, axis='Z', center=(boot_x - 0.075, yy, boot_z + bh / 2 + 0.005), mat='M_Chrome', bevel=0.002))
    for s in (1, -1):               # hood-iron stubs at the sides
        keep(tube([(-0.80, s * 0.50, boot_z + 0.01), (-0.80, s * 0.56, boot_z - 0.03)], 0.009, 6, 'M_Chrome'))
    # ---- rear deck: fuel cap, tail lamps, plate, exhaust tips -----------------------------------------------------------------
    keep(prim_cylinder(radius=0.040, depth=0.016, segments=18, axis='Z', center=(-1.42, 0.0, 0.797), mat='M_Chrome', bevel=0.004))
    keep(prim_cylinder(radius=0.022, depth=0.012, segments=14, axis='Z', center=(-1.42, 0.0, 0.806), mat='M_RimDark', bevel=0.003))
    for s in (1, -1):
        h = surf0.hit(Vector((-1.9, s * 0.20, 0.57)), RAY_R)
        if h is not None:
            fm = anchor_frame(surf0, (-1.9, s * 0.20, 0.57), RAY_R, sink=0.012)
            tl = round_lamp(0.040, 0.034, mat_shell='M_Chrome', mat_lens='M_Taillight', style='tail')
            bmesh.ops.transform(tl, matrix=fm, verts=tl.verts)
            keep(tl)
    plr = build_plate(0.30, 0.105)
    bmesh.ops.transform(plr, matrix=T((-1.950, 0.0, 0.540), (0, 0, 180)), verts=plr.verts)
    keep(plr)
    keep(prim_box((0.012, 0.34, 0.012), (-1.943, 0.0, 0.486), mat='M_Chrome', bevel=0.003, segments=1))
    keep(prim_box((0.012, 0.34, 0.010), (-1.943, 0.0, 0.600), mat='M_Chrome', bevel=0.003, segments=1))
    for s in (1, -1):
        tip = build_exhaust_tip(radius=0.030, length=0.12, lip=0.004)
        bmesh.ops.transform(tip, matrix=T((-1.86, s * 0.26, 0.40)), verts=tip.verts)
        keep(tip)

    # ---- undercarriage: chassis rails, axles, leaf springs, exhaust pipes + mufflers ---------------------------------------
    for s in (1, -1):
        keep(prim_box((3.20, 0.07, 0.10), (-0.10, s * 0.40, 0.255), mat='M_Underbody', bevel=0.012, segments=1))
        for ax_x, rz in ((XF, 0.30), (XR, 0.31)):
            keep(tube([(ax_x - 0.42, s * 0.44, 0.335), (ax_x - 0.14, s * 0.44, 0.38), (ax_x + 0.14, s * 0.44, 0.38), (ax_x + 0.42, s * 0.44, 0.335)],
                      0.011, 6, 'M_TrimBlack'))
        keep(tube(fillet_path3([(0.55, s * 0.50, 0.255), (-0.8, s * 0.52, 0.24), (-1.5, s * 0.50, 0.25), (-1.80, s * 0.26, 0.38)],
                               [0, 0.4, 0.3, 0], 5), 0.025, 10, 'M_Chrome'))
        keep(prim_cylinder(radius=0.066, depth=0.55, segments=18, axis='X', center=(-0.95, s * 0.52, 0.245), mat='M_Chrome', bevel=0.012))
    keep(tube([(XF, -0.58, 0.30), (XF, 0.58, 0.30)], 0.030, 10, 'M_TrimBlack'))
    keep(tube([(XR, -0.58, 0.31), (XR, 0.58, 0.31)], 0.030, 10, 'M_TrimBlack'))
    keep(prim_sphere(0.085, 14, 9, scale=(1.0, 1.0, 0.9), center=(XR + 0.04, 0.0, 0.31), mat='M_TrimGrey'))
    keep(tube([(XF - 0.1, 0.0, 0.28), (XR + 0.1, 0.0, 0.28)], 0.022, 8, 'M_TrimBlack'))
    keep(prim_box((0.30, 0.22, 0.12), (0.45, 0.0, 0.27), mat='M_TrimGrey', bevel=0.02, segments=1))
    lap("body add-ons")

    for ib in inserts:
        if ib is not None:
            bm_append(bm, ib)
            ib.free()
    n_healed = heal_nonmanifold(bm) if 'heal_nonmanifold' in globals() else 0
    n_tiny = clean_tiny(bm)
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("body finished, custom normals %d, tiny %d" % (n_sm, n_tiny))
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ==================================================================================================================
    # 3. wheels
    # ==================================================================================================================
    for name, w in WHEELS.items():
        wb = wire_wheel(R=w['radius'], w=w['width'], rim_r=0.2075, rim_w=0.075, n_spokes=36, side=w['side'], segs=56)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ==================================================================================================================
    # 4. interior (open cockpit): floor, tunnel, seats, dash with gauges, pedals, shifter, brake lever, door cards, shelf
    # ==================================================================================================================
    ib = bmesh.new()
    fz = FLOOR_Z
    _add(ib, prim_box((1.00, 0.94, 0.012), (-0.07, 0.0, fz + 0.006), mat='M_IntCarpet', bevel=0.004, segments=1))       # carpet
    _add(ib, prim_box((0.62, 0.15, 0.075), (-0.03, 0.0, fz + 0.045), mat='M_IntCarpet', bevel=0.03, segments=2))        # tunnel
    # firewall pad + shelf behind the seats
    _add(ib, prim_box((0.10, 0.94, 0.30), (0.405, 0.0, fz + 0.16), mat='M_IntDash', bevel=0.02, segments=1))
    _add(ib, prim_box((0.16, 0.94, 0.020), (-0.52, 0.0, 0.52), mat='M_IntCarpet', bevel=0.006, segments=1))
    _add(ib, prim_box((0.02, 0.94, 0.30), (-0.595, 0.0, 0.64), mat='M_IntSeat', bevel=0.008, segments=1))
    # seats
    for sy in (0.27, -0.27):
        _add(ib, vintage_seat(width=0.40, depth=0.46, back_h=0.50, recline=14.0), matrix=T((-0.20, sy, fz)))
    # door cards (leather) + pulls
    for s in (1, -1):
        _add(ib, prim_box((0.96, 0.016, 0.30), (-0.07, s * 0.470, 0.545), mat='M_IntSeat', bevel=0.007, segments=1))
        for k in range(4):
            _add(ib, prim_box((0.94, 0.004, 0.008), (-0.07, s * 0.461, 0.44 + k * 0.07), mat='M_IntTrim', bevel=0.001, segments=1))
        _add(ib, tube([(0.02, s * 0.462, 0.60), (-0.12, s * 0.462, 0.60)], 0.009, 8, 'M_Chrome'))
        _add(ib, prim_cylinder(radius=0.016, depth=0.018, segments=12, axis='Y', center=(0.01, s * 0.462, 0.64), mat='M_Chrome', bevel=0.003))
    # dash: wooden board, gauges, switches, glovebox, grab handle
    _add(ib, prim_box((0.032, 0.94, 0.25), (0.428, 0.0, 0.715), mat='M_IntTrim', bevel=0.012, segments=2))
    xg = 0.411
    for (gy, gr, deg) in ((0.215, 0.052, -30.0), (0.093, 0.052, 20.0), (-0.030, 0.036, -60.0), (-0.115, 0.036, 10.0)):
        g = gauge(gr, 0.035, deg)
        bmesh.ops.transform(g, matrix=T((xg, gy, 0.745)), verts=g.verts)
        _add(ib, g)
    for k in range(3):
        _add(ib, prim_cylinder(radius=0.011, depth=0.018, segments=10, axis='X', center=(xg - 0.008, -0.03 + k * 0.045, 0.655), mat='M_Chrome'))
    _add(ib, prim_cylinder(radius=0.016, depth=0.014, segments=12, axis='X', center=(xg - 0.005, 0.34, 0.655), mat='M_Chrome'))          # ignition
    _add(ib, prim_box((0.004, 0.30, 0.15), (xg - 0.002, -0.31, 0.73), mat='M_TrimBlack', bevel=0.004, segments=1))                      # glovebox
    _add(ib, prim_box((0.012, 0.012, 0.030), (xg - 0.010, -0.31, 0.74), mat='M_Chrome', bevel=0.003, segments=1))
    _add(ib, tube(fillet_path3([(0.40, -0.18, 0.835), (0.37, -0.18, 0.88), (0.37, -0.42, 0.88), (0.40, -0.42, 0.835)], [0, 0.03, 0.03, 0], 4),
                  0.010, 8, 'M_Chrome'))
    # pedals + gear lever + handbrake + column boss
    _add(ib, build_pedals(x=0.33, y=0.27, z=fz + 0.01, manual=True))
    _add(ib, build_shifter(x=0.00, y=0.0, z=fz + 0.07, mat_trim='M_Chrome', mat_knob='M_IntTrim', stick_h=0.25))
    _add(ib, tube([(-0.10, -0.03, fz + 0.07), (-0.22, -0.03, fz + 0.30)], 0.009, 8, 'M_Chrome'))
    _add(ib, prim_box((0.05, 0.016, 0.05), (-0.226, -0.03, fz + 0.31), mat='M_IntSeat', bevel=0.007, segments=1))
    hub = (0.17, 0.27, 0.79)
    tilt = 34.0
    ax = Vector((math.cos(math.radians(tilt)), 0.0, -math.sin(math.radians(tilt))))
    _add(ib, tube([Vector(hub) + ax * 0.03, Vector(hub) + ax * 0.26], 0.016, 10, 'M_IntDash'))
    _add(ib, prim_cylinder(radius=0.036, depth=0.03, segments=16, axis='X', center=(0.415, 0.27, 0.58), mat='M_Chrome', bevel=0.006))
    finish_object(CAR + "_Interior", ib, col, parent=root)
    swb, axis = build_steering_wheel(rim_radius=0.205, tube=0.0155, tilt=tilt, flat_bottom=False, mat_rim='M_IntTrim', mat_trim='M_Chrome',
                                     mat_hub='M_Chrome', spokes=3, segments=48)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ==================================================================================================================
    # 5. collision + anchors
    # ==================================================================================================================
    hulls = [
        hull_box_pts(-1.74, 0.54, 0.0, 0.57, 0.30, 0.86, cx=0.10, cy=0.12, cz=0.04),                       # tub (to the cowl)
        hull_box_pts(0.54, 1.52, 0.0, 0.29, 0.36, 1.02, cx=0.06, cy=0.04, cz=0.16),                        # bonnet + radiator
        hull_box_pts(0.40, 1.60, 0.0, 0.81, 0.28, 0.72, cx=0.10, cy=0.14, cz=0.20),                        # front wings + board
        hull_box_pts(-1.68, -0.30, 0.0, 0.81, 0.28, 0.74, cx=0.12, cy=0.16, cz=0.20),                      # rear wings
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)

    def E(suffix, loc, disp='PLAIN_AXES', size=0.08):
        return make_empty("%s_%s" % (CAR, suffix), col, parent=root, location=loc, display=disp, size=size)
    E('LP_HeadL', (1.30, 0.50, 0.872))
    E('LP_HeadR', (1.30, -0.50, 0.872))
    E('LP_TailL', (-1.90, 0.20, 0.57))
    E('LP_TailR', (-1.90, -0.20, 0.57))
    E('LP_Reverse', (-1.90, 0.0, 0.52))
    E('CAM_Hood', (0.95, 0.0, 1.05), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.30, 0.27, 1.20), 'ARROWS', 0.15)
    E('CAM_Bumper', (1.95, 0.0, 0.46), 'ARROWS', 0.15)
    E('EXHAUST_L', (-1.86, 0.26, 0.40))
    E('EXHAUST_R', (-1.86, -0.26, 0.40))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.6 and v.co.y > 0]
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    lap("done. body bounds %s %s | L x W x H = %.3f x %.3f x %.3f" % (
        tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), root['length'], root['width'], root['height']))
    return root


def unwrap_parts(parts):
    t0 = time.time()
    for suf in parts:
        o = bpy.data.objects.get("%s_%s" % (CAR, suf))
        if o is not None:
            uv_unwrap(o)
            if suf == 'Body':
                uv_livery_layer(o)
            print("[car10] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
