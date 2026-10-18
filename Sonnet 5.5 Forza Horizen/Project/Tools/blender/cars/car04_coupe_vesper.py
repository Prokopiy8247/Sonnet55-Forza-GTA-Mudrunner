"""
car04_coupe_vesper.py - parametric, idempotent build of the player car #4 "Vesper" (low sleek 2-door sports coupe, RWD).
Built with the shared car kit (Tools/blender/lib/carkit.py, Docs/CARKIT_API.md) + carkit_ext_02_03_04.py.

Run inside the verified Blender MCP session (localhost:9889):
    CAR04_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "all"
    exec(compile(open(r"<project>/Tools/blender/cars/car04_coupe_vesper.py", encoding="utf8").read(), "car04", "exec"), globals())
Staged at x = 48 m (cars row, index 4), collection FORZA_UE/Cars/car04_coupe_vesper, root car04_coupe_vesper_ROOT.
Design: long low nose with crowned fenders and hood louvres, small cabin set far back under a sweeping fastback glass, a ducktail kick-up
at the end of the deck, wide stance with coke-bottle haunches, slim wrap headlamps, wide low mouth, full-width tail light bar, centre
diffuser with twin round tips, 19" five-spoke wheels.  Original design, no badges / marques.
"""
import os
import time
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
_KIT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit.py")
_EXT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_02_03_04.py")
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())

CAR = "car04_coupe_vesper"
STAGE = globals().get("CAR04_STAGE", "all")

P = dict(
    id=CAR, display_name="Vesper", index=4,
    L=4.40, W=1.85, H=1.30, wheelbase=2.58, track_f=1.54, track_r=1.53,
    r_f=0.34, r_r=0.35, w_f=0.235, w_r=0.275, ride=0.12,            # 235/40 R19 front, 275/35 R19 rear
    x_ws_base=0.70, x_ws_top=0.0,
    x_rg_top=-0.80, x_rg_base=-1.66,
    x_end=2.16, cap_bulge=0.04, round_front=0.09, round_rear=0.08,
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1, rim_w=0.200),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1, rim_w=0.200),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1, rim_w=0.240),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1, rim_w=0.240),
}
ARCH_PAD = 0.036
GROOVE = groove_profile(0.0055, 0.007)

A0, A1 = (0.56, 0.935), (-0.04, 1.27)          # A-pillar line (front edge of the side glass)
C0, C1 = (-1.02, 0.955), (-0.84, 1.24)         # rear edge of the side glass (sail)

FOC = {"front": ((2.20 - 0.4, -0.7, 0.3), (2.20, 0.7, 1.0)), "rear": ((-2.20, -0.7, 0.3), (-2.20 + 0.4, 0.7, 1.0)),
       "cabin": ((-1.0, -0.8, 0.9), (0.9, 0.8, 1.35)), "front34": ((0.9, -0.95, 0.2), (2.20, 0.95, 1.0)),
       "side": ((-2.20, -0.95, 0.1), (2.20, -0.9, 1.35)), "hood": ((0.9, -0.6, 0.85), (2.20 - 0.3, 0.6, 1.0)),
       "quarter": ((-1.7, -1.0, 0.5), (-0.3, -0.6, 1.3)), "rearL": ((-2.20, 0.3, 0.4), (-2.20 + 0.5, 0.95, 1.1)),
       "frontL": ((2.20 - 0.5, 0.3, 0.3), (2.20, 0.95, 1.0)), "rear34": ((-2.20, -0.95, 0.2), (-0.9, 0.95, 1.2))}      # QA-only look() targets (edge meshes, removed before export)


def body_curves():
    zt = fillet_profile(
        [(-2.30, 0.930), (-2.12, 0.975), (-1.70, 0.985), (-0.75, 1.268), (-0.30, 1.300), (0.0, 1.272), (0.70, 0.935),
         (1.45, 0.895), (2.05, 0.815), (2.17, 0.760), (2.22, 0.660)],
        [0, 0.30, 0.35, 1.5, 5.0, 1.2, 0.40, 3.0, 1.0, 0.12, 0], step=0.01)
    zf = smooth_keys([(-2.16, 0.31), (-2.12, 0.28), (-2.0, 0.245), (-1.75, 0.20), (-1.5, 0.155), (-0.8, 0.125), (0.0, 0.12),
                      (0.8, 0.125), (1.5, 0.155), (1.85, 0.185), (2.05, 0.215), (2.12, 0.25), (2.16, 0.30)], sigma=0.07)
    hwm = smooth_keys([(-2.16, 0.70), (-2.11, 0.79), (-2.0, 0.862), (-1.8, 0.916), (-1.55, 0.934), (-1.29, 0.937),
                       (-1.0, 0.920), (-0.5, 0.898), (0.0, 0.893), (0.5, 0.903), (0.9, 0.922), (1.29, 0.935), (1.65, 0.915),
                       (1.9, 0.885), (2.02, 0.845), (2.10, 0.790), (2.14, 0.735), (2.16, 0.68)], sigma=0.05)
    zw = smooth_keys([(-2.16, 0.52), (-1.3, 0.65), (0, 0.58), (1.3, 0.64), (2.16, 0.52)], sigma=0.15)
    zb = smooth_keys([(-2.16, 0.78), (-2.10, 0.90), (-1.95, 0.955), (-1.5, 0.97), (-0.8, 0.955), (0.0, 0.93), (0.6, 0.90),
                      (1.0, 0.845), (1.5, 0.80), (2.0, 0.76), (2.16, 0.70)], sigma=0.11)
    zc = smooth_keys([(-2.0, 0.80), (-1.3, 0.80), (-0.5, 0.77), (0.3, 0.75), (1.2, 0.73), (2.0, 0.70)], sigma=0.15)
    cdepth = smooth_keys([(-2.16, 0.0), (-2.0, 0.016), (-1.6, 0.046), (-1.2, 0.052), (-0.4, 0.044), (0.4, 0.040), (1.2, 0.036),
                          (1.8, 0.016), (2.16, 0.0)], sigma=0.12)
    hw_ratio = as_curve(smooth_keys([(-2.16, 0.70), (-1.9, 0.76), (-1.5, 0.74), (-0.9, 0.68), (-0.3, 0.66), (0.2, 0.68),
                                     (0.7, 0.76), (1.2, 0.78), (2.0, 0.78), (2.16, 0.74)], sigma=0.15))
    dz = as_curve(smooth_keys([(-2.16, 0.035), (-1.9, 0.03), (-1.5, 0.045), (-0.9, 0.06), (-0.2, 0.065), (0.3, 0.06), (0.8, 0.06),
                               (1.3, 0.055), (2.16, 0.05)], sigma=0.15))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-0.85, 0.0), (-0.45, 1.0), (0.3, 1.0), (0.6, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - (0.050 + 0.014 * smoothstep(0.8, 0.4, x))

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.045 + 0.040 * door_win(x)),
        zs=lambda x: zfc(x) + 0.095,
        belt_step=0.018, crease=0.016,
    )


def build():
    B = Build("car04")
    lap = B.lap
    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="RWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. shell
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    xe = P['x_end']
    r_f_, r_r_ = P['round_front'], P['round_rear']
    xs = station_list(-xe, xe, dx=0.05, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_rg_top'], P['x_rg_base']] +
                      end_round_stations(-xe, r_r_, 6, at_start=True) + end_round_stations(xe, r_f_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=r_r_, round_x1=r_f_)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, side_cols_all = set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        side_cols_all |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
    Z_FRONT_VAL, Z_REAR_VAL = 0.455, 0.465
    for z_cut, in_zone in ((Z_FRONT_VAL, lambda x: x > 1.68), (Z_REAR_VAL, lambda x: x < -1.68)):
        geom = set()
        for f in bm.faces:
            if in_zone(f.calc_center_median().x):
                geom.add(f)
                geom.update(f.edges)
                geom.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, 0, z_cut), plane_no=(0, 0, 1))
    bm.normal_update()
    for f in bm.faces:
        c = f.calc_center_median()
        tag = f[tc]
        m = 'M_Paint'
        if tag in under_cols:
            m = 'M_Underbody'
        elif abs(c.x) > 1.68 and c.z < (Z_FRONT_VAL if c.x > 0 else Z_REAR_VAL):
            m = 'M_TrimBlack'
        f.material_index = mi(m)
    surf0 = Surface(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters
    # ------------------------------------------------------------------------------------------------------------------
    RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)
    VL = Vector((0, 0, 1))
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        B.cut(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))
    zd = 0.925
    door = [(0.46, zd), (0.475, 0.80), (0.495, 0.60), (0.51, 0.42), (0.50, 0.31), (0.46, 0.272), (0.0, 0.262), (-0.45, 0.266),
            (-0.72, 0.275), (-0.78, 0.31), (-0.80, 0.45), (-0.805, 0.65), (-0.80, 0.86), (-0.79, zd + 0.01)]
    B.pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    B.cut(sweep_xy(surf0, hood_loop_xy(shell, 0.78, 2.14, r=0.16), (0, 0, -1), GROOVE, mat='M_Underbody', step=0.03, closed=True))
    x_deck = -1.76
    B.cut(surface_sweep(surf0, resample_poly([Vector((x_deck, y, 0)) for y in (0.62, -0.62)], 0.04), (0, 0, -1), GROOVE,
                        mat='M_Underbody'))
    tgs = [Vector((x, edge_y(shell, x) - 0.012, 0)) for x in (x_deck, -1.88, -2.0, -2.08, -2.13)]
    B.pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    B.cut(surface_sweep(surf0, circle_pts(-1.35, 0.78, 0.065, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody'))
    lap("grooves + arches")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps, mouth, vents, tail
    # ------------------------------------------------------------------------------------------------------------------
    RH = ('radial', Vector((1.80, 0.28, 0.67)))
    UL = Vector((0.60, -0.80, 0.0)).normalized()
    c_head = Vector((2.08, 0.585, 0.665))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.26, height=0.040, rot=0.16, floor_mat='M_TrimGrey')
    if cut is None:
        lap("headlight FAILED")
    B.pair(cut)
    for b in ins:
        B.pair_in(b)
    B.pair_in(lamp_bezel(surf0, c_head, RH, (UL, VL), 0.26, 0.040, rot=0.16, mat='M_TrimBlack', width=0.010))

    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)

    mouth = outline_rrect(1.06, 0.125, 0.05, 6)
    cutm, minfo = pocket_cutter_flat(surf0, mouth, Vector((2.5, 0.0, 0.375)), RAY_F, depth=0.08, extra=0.03)
    B.cut(cutm)
    xm = minfo['s_floor']
    g = grille_mesh([(p[0] * 0.97, p[1] * 0.88) for p in mouth], kind='hex', pitch=0.034, bar=0.006, depth=0.022, frame=0.01)
    bmesh.ops.transform(g, matrix=T((xm + 0.035, 0, 0.375)), verts=g.verts)
    B.keep(g)
    slot = outline_rrect(0.46, 0.036, 0.016, 4)
    B.cut(nose_pocket((2.5, 0.0, 0.625), slot, 0.05))
    fm = anchor_frame(surf0, (2.5, 0, 0.625), RAY_F, sink=0.028)
    g = grille_mesh([(p[0] * 0.97, p[1] * 0.8) for p in slot], kind='bars', pitch=0.014, bar=0.0045, depth=0.016, frame=0.006)
    bmesh.ops.transform(g, matrix=fm, verts=g.verts)
    B.keep(g)
    cut, plate = plate_recess(surf0, (2.5, 0.0, 0.505), RAY_F)
    B.cut(cut)
    B.keep(plate)
    # hood louvres: two vented pockets with fins
    for s_ in (1, -1):
        vc = Vector((1.62, s_ * 0.33, 0))
        pk = pocket_cutter(surf0, outline_rrect(0.40, 0.14, 0.025, 3), vc, (0, 0, -1), depth=0.03, taper=0.96, mat='M_TrimBlack',
                           axes=(Vector((1, 0, 0)), Vector((0, 1, 0))), floor_follows=True)
        if pk is not None:
            B.cut(pk)
            for k in range(-4, 5):
                B.keep(surface_sweep(surf0, [Vector((1.62 + k * 0.040, s_ * 0.33 + dy, 0)) for dy in (-0.052, 0.0, 0.052)], (0, 0, -1),
                                     [(-0.0028, -0.02), (0.0028, -0.02), (0.0028, 0.006), (-0.0028, 0.006)], mat='M_TrimBlack'))
    # front fender vents behind the arch
    vc = Vector((0.68, 0.9, 0.57))
    pk = pocket_cutter(surf0, outline_rrect(0.26, 0.085, 0.02, 3), vc, RAY_L, depth=0.03, taper=1.0, mat='M_TrimBlack', floor_follows=True)
    if pk is not None:
        B.pair(pk)
        for k in range(-3, 4):
            B.pair_in(surface_sweep(surf0, [Vector((0.68 + u, 0.9, 0.57 + k * 0.0105)) for u in (-0.10, 0.0, 0.10)], RAY_L,
                                    [(-0.0028, -0.02), (0.0028, -0.02), (0.0028, -0.002), (-0.0028, -0.002)], mat='M_TrimGrey'))

    # full-width tail light bar (flat recess) + plate + diffuser with twin round tips
    tz = 0.745
    t_out = outline_rrect(1.38, 0.085, 0.035, 5)
    cutt, tinfo = pocket_cutter_flat(surf0, t_out, Vector((-2.5, 0.0, tz)), RAY_R, depth=0.05, extra=0.03)
    B.cut(cutt)
    xt = -tinfo['s_floor']
    B.keep(sweep_yz(surf0, [(p[0] * 1.012, tz + p[1] * 1.05) for p in t_out], -2.5, RAY_R, rib_profile(0.010, 0.0035, 0.005, 0.0015),
                    mat='M_TrimBlack', closed=True))
    B.keep(prim_box((0.006, 1.30, 0.070), (xt - 0.004, 0.0, tz), mat='M_TrimGrey', bevel=0.003, segments=1))
    for s_ in (1, -1):
        def seg(y0, y1, z0, z1, mat, r=0.008):
            B.keep(prim_box((0.018, abs(y1 - y0), abs(z1 - z0)), (xt - 0.011, s_ * (y0 + y1) / 2, (z0 + z1) / 2), mat=mat, bevel=r, segments=2))
        seg(0.10, 0.50, tz - 0.030, tz + 0.030, 'M_Taillight')
        seg(0.515, 0.640, tz - 0.030, tz + 0.030, 'M_Taillight')
        seg(0.655, 0.690, tz - 0.030, tz - 0.001, 'M_Indicator', 0.006)
        seg(0.655, 0.690, tz + 0.007, tz + 0.030, 'M_Reverse', 0.006)
    seg_c = prim_box((0.018, 0.20, 0.060), (xt - 0.011, 0.0, tz), mat='M_Taillight', bevel=0.008, segments=2)
    B.keep(seg_c)
    cut, plate = plate_recess(surf0, (-2.5, 0.0, 0.600), RAY_R)
    B.cut(cut)
    B.keep(plate)
    cut, fins = build_diffuser(surf0, (-2.5, 0.0, 0.385), RAY_R, width=1.12, height=0.11, fins=7, fin_h=0.10)
    B.cut(cut)
    for fb in fins:
        B.keep(fb)
    for s_ in (1, -1):
        B.cut(prim_cylinder(radius=0.046, depth=0.22, segments=24, axis='X', center=(-2.10, s_ * 0.24, 0.380), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.040, length=0.13, lip=0.005)
        bmesh.ops.transform(tip, matrix=T((-2.20, s_ * 0.24, 0.380)), verts=tip.verts)
        B.keep(tip)
    lap("pockets: %d cutters" % len(B.cutters))

    # ------------------------------------------------------------------------------------------------------------------
    # 4. boolean + add-ons
    # ------------------------------------------------------------------------------------------------------------------
    bm = bm_boolean(bm, B.cutters)
    lap("boolean: %d faces manifold=%s" % (len(bm.faces), is_manifold(bm)))
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
    bevel_hard_edges(bm, angle_deg=60.0, width=0.0035, segments=1, edge_filter=pocket_rim)
    n_lip = 0
    for name, w in WHEELS.items():              # rolled lip round the wheel-arch openings (catches the light, hides the cut edge)
        n_lip += bevel_circle_edges(bm, (w['center'][0], 0, w['center'][2]), w['radius'] + ARCH_PAD, axis='Y', width=0.011, segments=2,
                                    y_min=0.45)
    lap("arch lips: %d edges" % n_lip)

    B.pair_in(surface_sweep(surf0, poly_pts([(-0.70, 0.256), (-0.3, 0.252), (0.0, 0.250), (0.3, 0.252), (0.50, 0.256)], subdiv=2),
                            RAY_L, rib_profile(0.07, 0.016, 0.012, 0.006), mat='M_TrimBlack'))
    B.pair_in(build_splitter(surf0, RAY_F, out=0.045, inn=0.06, z=0.205, z_top=0.212, z_bot=0.184))
    B.pair_in(build_splitter(surf0, RAY_R, out=0.020, inn=0.05, z=0.24, z_top=0.247, z_bot=0.219))

    def zbu_(x):
        return ring_pt(shell, x, 'belt_up')[1]

    def zed_(x):
        return ring_pt(shell, x, 'edge')[1]

    def line_x(p0, p1, z):
        return p0[0] + (p1[0] - p0[0]) * (z - p0[1]) / (p1[1] - p0[1])
    fa_ = lambda z: line_x(A0, A1, z)
    fc_ = lambda z: line_x(C0, C1, z)
    wpoly = window_loop_pts(fa_, fc_, zbu_, zed_, z_bot=0.94, inset=0.010)
    B.pair_in(sweep_loop(surf0, rounded_poly(wpoly, 0.03, 4), RAY_L, rib_profile(0.016, 0.004, 0.005, 0.002), mat='M_TrimBlack', step=0.03))
    B.pair_in(door_handle(surf0, -0.52, 0.82, RAY_L, mat='M_TrimBlack', length=0.11, width=0.022, height=0.010))
    B.keep(surface_sweep(surf0, [Vector((0.72, y, 0)) for y in [0.58 - 0.08 * i for i in range(15)]], (0, 0, -1),
                         rib_profile(0.06, 0.008, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.69, 0.10), (0.64, 0.58)), ((0.69, -0.58), (0.64, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        B.keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.012, 0.012, 0.0095, 0.003), mat='M_TrimBlack'))
    # ducktail kick-up
    lip = [(-2.12, y) for y in [-0.64 + 0.08 * i for i in range(17)]]
    B.keep(sweep_xy(surf0, lip, (0, 0, -1), rib_profile(0.100, 0.030, 0.010, 0.014), mat='M_Paint2', step=0.04))
    # mirrors
    zm = zbu_(0.50) + 0.040
    mh = surf0.hit(Vector((0.50, 0.0, zm - 0.03)), RAY_L)
    my = (mh[0].y - 0.02) if mh else 0.86
    for s_ in (1, -1):
        m = build_mirror(side=s_, mat_shell='M_Paint2', length=0.155, width=0.080, height=0.075, arm_len=0.085)
        bmesh.ops.transform(m, matrix=T((0.52, s_ * my, zm)), verts=m.verts)
        B.keep(m)
    for ib in B.inserts:
        if ib is None:
            continue
        bm_append(bm, ib)
        ib.free()
    lap("add-ons: %d faces" % len(bm.faces))
    tc, ts = face_tags(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 5. glass
    # ------------------------------------------------------------------------------------------------------------------
    side_cols = shell_quad_cols(shell, 'belt_up', 'edge', 1) | shell_quad_cols(shell, 'belt_up', 'edge', -1)
    top_cols = shell_quad_cols(shell, 'rail', 'top_c', 1) | shell_quad_cols(shell, 'rail', 'top_c', -1)

    def behind(c, p0, p1):
        return c.x < p0[0] + (p1[0] - p0[0]) * (c.z - p0[1]) / (p1[1] - p0[1])

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

    def rear_pred(f):
        return f[tc] in top_cols and P['x_rg_base'] < f.calc_center_median().x < P['x_rg_top']

    wins = [dict(name='side', pred=side_pred, zone=side_zone, planes=[plane(A0, A1), plane(C0, C1)]),
            dict(name='windscreen', pred=ws_pred), dict(name='rear', pred=rear_pred)]
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    lining = inner_trim_from_faces(bm, lambda f: f[tc] != 0 and (f[tc] in side_cols or f[tc] in top_cols) and
                                   f.calc_center_median().z > 1.0 and -1.66 < f.calc_center_median().x < 0.72,
                                   offset=0.03, mat='M_IntTrim')
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels
    # ------------------------------------------------------------------------------------------------------------------
    for name, w in WHEELS.items():
        wb = build_wheel_ext(radius=w['radius'], width=w['width'], rim_radius=0.2413, rim_width=w['rim_w'], style='five', side=w['side'],
                             brake_disc_radius=0.165, caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=56,
                             tyre_segments=64, hub_radius=0.055, dish=0.05, cap_chrome=False, bulge=1.02, spokes=5)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels")
    wf, wr = bounds_obj(bpy.data.objects[CAR + "_Wheel_FL"]), bounds_obj(bpy.data.objects[CAR + "_Wheel_RL"])      # measured tyre sizes -> root props
    set_root_props(root, wheel_width_front=round(wf[1].y - wf[0].y, 4), wheel_width_rear=round(wr[1].y - wr[0].y, 4),
                   wheel_radius_front=round((wf[1].z - wf[0].z) / 2, 4), wheel_radius_rear=round((wr[1].z - wr[0].z) / 2, 4))

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior(shell, dict(dash_x_back=0.30, dash_z_top=0.92, hw=0.78, front_x=-0.50, driver_y=0.38, x_front_floor=0.62,
                                    x_rear_floor=-1.45, door_x=(-0.80, 0.46), quarter_x=(-1.55, -0.80), roof_x=(-1.30, 0.0),
                                    headliner=False, sport=True, seats_rear=False, floor_z=0.19, back_h=0.56, front_z=0.25))
    delete_verts_where(ib, lambda co: co.z > 1.12 and abs(co.y) < 0.2 and 0.2 < co.x < 0.45)         # kit mirror is too tall for this roof
    _add(ib, build_rv_mirror(0.28, 1.03))
    _add(ib, lining)
    _add(ib, prim_box((0.56, 1.36, 0.03), (-1.35, 0, 0.60), mat='M_IntCarpet', bevel=0.008, segments=1))      # luggage floor
    _add(ib, prim_box((0.04, 1.30, 0.40), (-1.08, 0, 0.50), mat='M_IntTrim', bevel=0.01, segments=1))         # bulkhead behind the seats
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.15, 0.38, 0.89)
    swb, axis = build_steering_wheel(rim_radius=0.175, tube=0.0165, tilt=18.0, flat_bottom=True)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision + anchors
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.10, -1.6, -1.1, -0.6], low, z_clip=(0.17, 0.95), shrink=0.05),
        hull_points_from_shell(shell, [-0.6, 0.0, 0.6, 1.2], low, z_clip=(0.17, 0.92), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 0.90) - 0.012)) for p in
         hull_points_from_shell(shell, [1.2, 1.7, 2.1], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.20, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.65, 0.0, -0.5, -1.0, -1.7], ['belt_up', 'edge', 'top_c'], z_clip=(0.90, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)
    hl = (2.12, 0.52, 0.675)
    tl = (-2.20, 0.50, 0.745)
    add_anchors(CAR, col, root, {
        'LP_HeadL': (hl, 'PLAIN_AXES', 0.08), 'LP_HeadR': ((hl[0], -hl[1], hl[2]), 'PLAIN_AXES', 0.08),
        'LP_TailL': (tl, 'PLAIN_AXES', 0.08), 'LP_TailR': ((tl[0], -tl[1], tl[2]), 'PLAIN_AXES', 0.08),
        'LP_Reverse': ((-2.20, 0.67, 0.745), 'PLAIN_AXES', 0.08),
        'CAM_Hood': ((0.75, 0.0, 1.02), 'ARROWS', 0.15), 'CAM_Cockpit': ((-0.30, 0.38, 1.08), 'ARROWS', 0.15),
        'CAM_Bumper': ((2.22, 0.0, 0.42), 'ARROWS', 0.15),
        'EXHAUST_L': ((-2.20, 0.24, 0.380), 'PLAIN_AXES', 0.08), 'EXHAUST_R': ((-2.20, -0.24, 0.380), 'PLAIN_AXES', 0.08)})
    lo, hi = bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.9]
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    if globals().get("CAR04_QA", False):          # optional QA-only look() targets (set CAR04_QA = True; remove with focus_meshes(CAR, 0, on=False))
        focus_meshes(CAR, root.location.x, FOC)
    lap("done. L x W x H = %.3f x %.3f x %.3f (with mirrors %.3f wide)" % (root['length'], root['width'], root['height'], hi.y - lo.y))
    return root


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(CAR, ['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):          # front wheels (uv2) / rear wheels (uv3): keeps every Blender call well below 20 s
    unwrap_parts(CAR, ['Wheel_FL', 'Wheel_FR'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts(CAR, ['Wheel_RL', 'Wheel_RR'])
