"""
car03_muscle_thunderline.py - parametric, idempotent build of the player car #3 "Thunderline" (classic 2-door fastback muscle car, RWD V8).
Built with the shared car kit (Tools/blender/lib/carkit.py, Docs/CARKIT_API.md) + carkit_ext_02_03_04.py.

Run inside the verified Blender MCP session (localhost:9889):
    CAR03_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "all"
    exec(compile(open(r"<project>/Tools/blender/cars/car03_muscle_thunderline.py", encoding="utf8").read(), "car03", "exec"), globals())
Staged at x = 36 m (cars row, index 3), collection FORZA_UE/Cars/car03_muscle_thunderline, root car03_muscle_thunderline_ROOT.
Design: long flat hood with a centre power-bulge scoop, short cabin set back, continuous fastback roof to a short deck with a lip
spoiler, wide rear haunches over fat rear tyres, twin racing stripes (separate M_Paint2 material zone), chrome-framed full-width grille
with two round headlamps, chrome bumper blades, full-width tail-lamp panel, dual round exhaust tips.  Original design, no badges.
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
_FIX = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_fix_01_02_03.py")      # fix round 1: cleanup_slivers, purge_qa ...
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())
exec(compile(open(_FIX, encoding="utf8").read(), _FIX, "exec"), globals())

CAR = "car03_muscle_thunderline"
STAGE = globals().get("CAR03_STAGE", "all")

P = dict(
    id=CAR, display_name="Thunderline", index=3,
    L=4.85, W=1.92, H=1.32, wheelbase=2.75, track_f=1.60, track_r=1.58,
    r_f=0.33, r_r=0.35, w_f=0.245, w_r=0.285, ride=0.13,            # 235/50 R17 front, 275/50 R17 rear
    x_ws_base=0.90, x_ws_top=0.16,
    x_rg_top=-0.66, x_rg_base=-1.64,
    x_end=2.385, cap_bulge=0.04, round_front=0.06, round_rear=0.08,
    tail_lean=0.055,                                                 # fix round 1: rake of the tail panel (m over z = 0.42 .. 0.97)
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1, rim_w=0.215),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1, rim_w=0.215),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1, rim_w=0.255),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1, rim_w=0.255),
}
ARCH_PAD = 0.040
GROOVE = groove_profile(0.0055, 0.007)
CHROME = rib_profile(0.012, 0.0045, 0.004, 0.002)

A0, A1 = (0.86, 0.985), (0.10, 1.30)           # A-pillar line (front edge of the door glass)
B0, B1 = (-0.62, 0.985), (-0.56, 1.32)         # rear edge of the door glass
Q0, Q1 = (-0.675, 0.985), (-0.615, 1.32)       # front edge of the quarter glass
C0, C1 = (-1.14, 0.985), (-0.93, 1.20)         # rear edge of the quarter glass


FOC = {"front": ((2.40 - 0.4, -0.7, 0.3), (2.40, 0.7, 1.0)), "rear": ((-2.40, -0.7, 0.3), (-2.40 + 0.4, 0.7, 1.0)),
       "cabin": ((-1.0, -0.8, 0.9), (0.9, 0.8, 1.35)), "front34": ((0.9, -0.95, 0.2), (2.40, 0.95, 1.0)),
       "side": ((-2.40, -0.95, 0.1), (2.40, -0.9, 1.35)), "hood": ((0.9, -0.6, 0.85), (2.40 - 0.3, 0.6, 1.0)),
       "quarter": ((-1.7, -1.0, 0.5), (-0.3, -0.6, 1.3)), "rearL": ((-2.40, 0.3, 0.4), (-2.40 + 0.5, 0.95, 1.1)),
       "frontL": ((2.40 - 0.5, 0.3, 0.3), (2.40, 0.95, 1.0)), "rear34": ((-2.40, -0.95, 0.2), (-0.9, 0.95, 1.2))}      # QA-only look() targets (edge meshes, removed before export)


def body_curves():
    zt = fillet_profile(
        [(-2.50, 0.935), (-2.28, 0.985), (-1.70, 1.000), (-0.62, 1.298), (-0.12, 1.322), (0.14, 1.300), (0.90, 0.985),
         (1.55, 0.950), (2.10, 0.925), (2.34, 0.905), (2.43, 0.84), (2.48, 0.72)],
        [0, 0.35, 0.40, 1.6, 6.0, 1.0, 0.40, 3.0, 1.5, 0.12, 0], step=0.01)
    zf = smooth_keys([(-2.385, 0.33), (-2.34, 0.30), (-2.2, 0.26), (-1.9, 0.21), (-1.5, 0.165), (-0.8, 0.14), (0.0, 0.13),
                      (0.8, 0.14), (1.5, 0.165), (2.0, 0.20), (2.25, 0.23), (2.34, 0.27), (2.385, 0.33)], sigma=0.07)
    hwm = smooth_keys([(-2.385, 0.80), (-2.34, 0.85), (-2.25, 0.895), (-2.0, 0.945), (-1.75, 0.962), (-1.38, 0.966),
                       (-1.0, 0.940), (-0.5, 0.915), (0.0, 0.908), (0.6, 0.918), (1.0, 0.934), (1.38, 0.946), (1.8, 0.940),
                       (2.05, 0.925), (2.2, 0.912), (2.30, 0.885), (2.36, 0.845), (2.385, 0.80)], sigma=0.05)
    zw = smooth_keys([(-2.385, 0.55), (-1.4, 0.66), (0, 0.60), (1.4, 0.66), (2.385, 0.56)], sigma=0.15)
    zb = smooth_keys([(-2.385, 0.78), (-2.33, 0.90), (-2.2, 0.955), (-1.8, 0.97), (-1.4, 0.98), (-0.8, 0.985), (0.0, 0.985),
                      (0.7, 0.97), (1.0, 0.925), (1.4, 0.885), (2.0, 0.86), (2.3, 0.83), (2.385, 0.74)], sigma=0.11)
    zc = smooth_keys([(-2.2, 0.84), (-1.4, 0.86), (-0.8, 0.82), (0.0, 0.79), (0.8, 0.775), (1.6, 0.76), (2.2, 0.74)], sigma=0.15)
    cdepth = smooth_keys([(-2.385, 0.0), (-2.2, 0.014), (-1.8, 0.040), (-1.4, 0.052), (-0.8, 0.046), (0.0, 0.040), (0.8, 0.040),
                          (1.5, 0.034), (2.0, 0.014), (2.385, 0.0)], sigma=0.12)
    hw_ratio = as_curve(smooth_keys([(-2.385, 0.72), (-2.1, 0.78), (-1.6, 0.76), (-1.0, 0.70), (-0.5, 0.68), (0.2, 0.70),
                                     (0.8, 0.78), (1.2, 0.84), (2.0, 0.84), (2.385, 0.80)], sigma=0.15))
    dz = as_curve(smooth_keys([(-2.385, 0.03), (-2.0, 0.025), (-1.6, 0.04), (-1.0, 0.05), (-0.2, 0.055), (0.3, 0.05), (0.9, 0.04),
                               (1.3, 0.03), (2.385, 0.03)], sigma=0.15))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-0.9, 0.0), (-0.5, 1.0), (0.6, 1.0), (0.95, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - (0.060 + 0.012 * smoothstep(0.9, 0.5, x))

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
    B = Build("car03")
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
    shear_end(shell, 'rear', zone=0.55, lean=P['tail_lean'], z_lo=0.42, z_hi=0.97)       # fix round 1: raked tail panel (was a vertical slab)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, side_cols_all = set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        side_cols_all |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
    Z_FRONT_VAL, Z_REAR_VAL = 0.455, 0.47
    for z_cut, in_zone in ((Z_FRONT_VAL, lambda x: x > 1.80), (Z_REAR_VAL, lambda x: x < -1.80)):
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
        elif abs(c.x) > 1.80 and c.z < (Z_FRONT_VAL if c.x > 0 else Z_REAR_VAL):
            m = 'M_TrimBlack'
        elif tag in side_cols_all and (Q1[0] < c.x < B0[0]) and c.z > 0.9:
            m = 'M_TrimBlack'                                   # B / quarter pillar gap
        f.material_index = mi(m)
    n_str = paint_bands(bm, tc, [(0.25, 0.39)], 'M_Paint2', zmin=0.85)          # twin racing stripes
    lap("stripes: %d faces" % n_str)
    bm.normal_update()
    surf0 = Surface(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters
    # ------------------------------------------------------------------------------------------------------------------
    RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)
    VL = Vector((0, 0, 1))
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        B.cut(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))
    zd = 0.98
    door = [(0.74, zd), (0.76, 0.85), (0.775, 0.62), (0.785, 0.42), (0.775, 0.31), (0.735, 0.272), (0.3, 0.264), (0.0, 0.262),
            (-0.4, 0.266), (-0.55, 0.272), (-0.60, 0.31), (-0.615, 0.45), (-0.625, 0.70), (-0.635, zd)]
    B.pair(surface_sweep(surf0, poly_pts(door, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    B.cut(sweep_xy(surf0, hood_loop_xy(shell, 0.95, 2.36, r=0.17), (0, 0, -1), GROOVE, mat='M_Underbody', step=0.03, closed=True))
    x_trunk = -1.70
    B.cut(surface_sweep(surf0, resample_poly([Vector((x_trunk, y, 0)) for y in (0.62, -0.62)], 0.04), (0, 0, -1), GROOVE,
                        mat='M_Underbody'))
    tgs = [Vector((x, edge_y(shell, x) - 0.012, 0)) for x in (x_trunk, -1.85, -2.0, -2.12, -2.22, -2.3)]
    B.pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    lap("grooves + arches")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. grille + round headlamps, bumper blade, plate, tail panel, exhaust
    # ------------------------------------------------------------------------------------------------------------------
    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)

    gz, gw, gh = 0.675, 1.44, 0.215
    g_out = outline_rrect(gw, gh, 0.05, 5)
    cutg, ginfo = pocket_cutter_flat(surf0, g_out, Vector((2.6, 0.0, gz)), RAY_F, depth=0.085, extra=0.03)
    B.cut(cutg)
    xg = ginfo['s_floor']                                       # x of the flat grille floor
    g = grille_mesh([(p[0] * 0.97, p[1] * 0.88) for p in g_out], kind='grid', pitch=0.030, bar=0.0065, depth=0.022, frame=0.008,
                    mat='M_Chrome', frame_mat='M_Chrome')
    bmesh.ops.transform(g, matrix=T((xg + 0.040, 0, gz)), verts=g.verts)
    B.keep(g)
    B.keep(sweep_yz(surf0, [(p[0] * 1.012, gz + p[1] * 1.03) for p in g_out], 2.6, RAY_F, rib_profile(0.018, 0.007, 0.007, 0.003),
                    mat='M_Chrome', closed=True))
    # round headlamps sit inside the grille opening, left and right (flat-referenced assemblies)
    for s_ in (1, -1):
        yy = s_ * 0.560
        B.keep(prim_cylinder(radius=0.084, depth=0.030, segments=32, axis='X', center=(xg + 0.050, yy, gz), mat='M_TrimBlack', bevel=0.004, bevel_segments=1))
        B.keep(prim_torus(R=0.080, r=0.0085, seg_major=32, seg_minor=8, axis='X', center=(xg + 0.072, yy, gz), mat='M_Chrome'))
        B.keep(prim_cylinder(radius=0.068, depth=0.012, segments=28, axis='X', center=(xg + 0.062, yy, gz), mat='M_Chrome'))
        B.keep(prim_sphere(radius=0.068, u=28, v=10, scale=(0.30, 1.0, 1.0), center=(xg + 0.066, yy, gz), mat='M_Headlight'))
        B.keep(prim_sphere(radius=0.020, u=16, v=8, scale=(0.5, 1.0, 1.0), center=(xg + 0.080, yy, gz), mat='M_Chrome'))
    # fix round 1: chrome bumper blade across the nose that WRAPS round both corners (radial rays from the centre of the nose, so the
    # strip follows the plan outline of the fascia down the flanks instead of stopping at the corner)
    C_nose = ('radial', Vector((1.55, 0.0, 0.505)))
    th_ = [math.radians(-70.0 + 140.0 * i / 56.0) for i in range(57)]
    B.keep(surface_sweep(surf0, [Vector((1.55 + 3.0 * math.cos(t), 3.0 * math.sin(t), 0.505)) for t in th_], C_nose,
                         rib_profile(0.050, 0.014, 0.012, 0.007), mat='M_Chrome'))
    # split-grille centre bars (horizontal + vertical divider between the round lamps): the lattice no longer reads as one repeated pattern
    B.keep(prim_box((0.030, 0.82, 0.014), (xg + 0.042, 0.0, gz), mat='M_Chrome', bevel=0.004, segments=1))
    B.keep(prim_box((0.030, 0.014, gh * 0.80), (xg + 0.042, 0.0, gz), mat='M_Chrome', bevel=0.004, segments=1))
    cut, plate = plate_recess(surf0, (2.6, 0.0, 0.395), RAY_F)
    B.cut(cut)
    B.keep(plate)
    for s in (1, -1):                                                    # lower slot intakes either side of the plate
        slot = outline_rrect(0.34, 0.075, 0.03, 4)
        B.cut(nose_pocket((2.6, s * 0.52, 0.385), slot, 0.06))
        fm = anchor_frame(surf0, (2.6, s * 0.52, 0.385), RAY_F, sink=0.035)
        gg = grille_mesh([(p[0] * 0.97, p[1] * 0.85) for p in slot], kind='bars', pitch=0.018, bar=0.0055, depth=0.02, frame=0.008)
        bmesh.ops.transform(gg, matrix=fm, verts=gg.verts)
        B.keep(gg)

    # full-width tail lamp panel: flat recessed housing, red lenses (bevelled boxes), amber outer / white inner windows
    tz = 0.805
    t_out = outline_rrect(1.50, 0.125, 0.04, 5)
    cutt, tinfo = pocket_cutter_flat(surf0, t_out, Vector((-2.6, 0.0, tz)), RAY_R, depth=0.05, extra=0.03)
    B.cut(cutt)
    xt = -tinfo['s_floor']                                      # x of the flat floor of the tail panel (inboard of the skin)
    B.keep(sweep_yz(surf0, [(p[0] * 1.012, tz + p[1] * 1.04) for p in t_out], -2.6, RAY_R, rib_profile(0.011, 0.0035, 0.005, 0.0015),
                    mat='M_Chrome', closed=True))
    B.keep(prim_box((0.006, 1.40, 0.108), (xt - 0.004, 0.0, tz), mat='M_TrimGrey', bevel=0.003, segments=1))          # reflector backing
    for s_ in (1, -1):
        def seg(y0, y1, z0, z1, mat, r=0.010):
            B.keep(prim_box((0.020, abs(y1 - y0), abs(z1 - z0)), (xt - 0.012, s_ * (y0 + y1) / 2, (z0 + z1) / 2), mat=mat, bevel=r, segments=2))
        seg(0.20, 0.52, tz - 0.046, tz + 0.046, 'M_Taillight')
        seg(0.535, 0.665, tz - 0.046, tz + 0.046, 'M_Taillight')
        seg(0.680, 0.745, tz - 0.046, tz + 0.004, 'M_Indicator', 0.008)
        seg(0.680, 0.745, tz + 0.014, tz + 0.046, 'M_Reverse', 0.008)
    cut, plate = plate_recess(surf0, (-2.6, 0.0, 0.620), RAY_R)
    B.cut(cut)
    B.keep(plate)
    C_tail_b = ('radial', Vector((-1.55, 0.0, 0.515)))             # fix round 1: the rear blade wraps round the corners as well
    th_r = [math.radians(-70.0 + 140.0 * i / 56.0) for i in range(57)]
    B.keep(surface_sweep(surf0, [Vector((-1.55 - 3.0 * math.cos(t), 3.0 * math.sin(t), 0.515)) for t in th_r], C_tail_b,
                         rib_profile(0.050, 0.014, 0.012, 0.007), mat='M_Chrome'))
    for s in (1, -1):
        B.cut(prim_cylinder(radius=0.052, depth=0.22, segments=24, axis='X', center=(-2.30, s * 0.46, 0.37), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.043, length=0.14, lip=0.005)
        bmesh.ops.transform(tip, matrix=T((-2.385, s * 0.46, 0.37)), verts=tip.verts)
        B.keep(tip)
    # rear-quarter brake-cooling scoop (left, mirrored): black pocket with horizontal louvres between the door and the rear arch
    qc = Vector((-0.815, 0.95, 0.60))
    pk = pocket_cutter(surf0, outline_rrect(0.22, 0.085, 0.02, 3), qc, RAY_L, depth=0.03, taper=1.0, mat='M_TrimBlack', floor_follows=True)
    if pk is not None:
        B.pair(pk)
        for k in range(-2, 3):
            B.pair_in(surface_sweep(surf0, [Vector((-0.815 + u, 0.95, 0.60 + k * 0.0145)) for u in (-0.085, 0.0, 0.085)], RAY_L,
                                    [(-0.0028, -0.02), (0.0028, -0.02), (0.0028, -0.002), (-0.0028, -0.002)], mat='M_Chrome'))
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

    B.pair_in(surface_sweep(surf0, poly_pts([(-0.60, 0.256), (-0.3, 0.252), (0.0, 0.250), (0.3, 0.252), (0.70, 0.256)], subdiv=2),
                            RAY_L, rib_profile(0.07, 0.016, 0.012, 0.006), mat='M_TrimBlack'))
    B.pair_in(build_splitter(surf0, RAY_F, out=0.030, inn=0.05, z=0.235, z_top=0.242, z_bot=0.214))
    # fix round 1: chrome rocker moulding on top of the black sill skirt (sill / rocker break in the flank)
    B.pair_in(surface_sweep(surf0, poly_pts([(-0.60, 0.318), (-0.3, 0.314), (0.0, 0.312), (0.3, 0.314), (0.70, 0.318)], subdiv=2),
                            RAY_L, rib_profile(0.012, 0.007, 0.008, 0.003), mat='M_Chrome'))
    # window trim loops (chrome)
    def zbu_(x):
        return ring_pt(shell, x, 'belt_up')[1]

    def zed_(x):
        return ring_pt(shell, x, 'edge')[1]

    def line_x(p0, p1, z):
        return p0[0] + (p1[0] - p0[0]) * (z - p0[1]) / (p1[1] - p0[1])

    fa = lambda z: line_x(A0, A1, z)
    fb = lambda z: line_x(B0, B1, z)
    fq = lambda z: line_x(Q0, Q1, z)
    fc = lambda z: line_x(C0, C1, z)
    for (xa, xb) in ((fa, fb), (fq, fc)):
        poly = window_loop_pts(xa, xb, zbu_, zed_, z_bot=0.985, inset=0.012)
        B.pair_in(sweep_loop(surf0, rounded_poly(poly, 0.03, 4), RAY_L, CHROME, mat='M_Chrome', step=0.03))
    B.pair_in(door_handle(surf0, -0.30, 0.875, RAY_L, mat='M_Chrome', length=0.13))
    B.keep(surface_sweep(surf0, [Vector((0.925, y, 0)) for y in [0.62 - 0.08 * i for i in range(16)]], (0, 0, -1),
                         rib_profile(0.07, 0.009, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.88, 0.10), (0.83, 0.62)), ((0.88, -0.62), (0.83, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        B.keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    # hood power-bulge / scoop
    def scoop_h(u, v):            # u = 0 at the FRONT (x = 2.00, tall opening), u = 1 at the rear (x = 1.24, ramps into the hood)
        f = 1.0 - 0.90 * (u ** 1.25)
        g = min(max((1.0 - abs(v)) / 0.16, 0.0), 1.0) ** 0.6
        return 0.078 * f * g
    scoop = height_field_solid(surf0, 2.00, 1.24, 0.20, 20, 18, scoop_h, sink=0.015, mat='M_Paint', front_mat='M_TrimBlack',
                               y_fun=lambda u: 0.20 * (1.0 - 0.28 * u))
    zs0 = surf0.hit(Vector((2.0, 0.0, 0.0)), (0, 0, -1))[0].z
    sg = grille_mesh(outline_rrect(0.31, 0.050, 0.012, 3), kind='bars', pitch=0.014, bar=0.0045, depth=0.016, frame=0.006,
                     mat='M_Chrome', frame_mat='M_Chrome')
    bmesh.ops.transform(sg, matrix=T((2.0, 0.0, zs0 + 0.036)), verts=sg.verts)
    B.keep(sg)
    B.keep(scoop)
    # lip spoiler on the deck (ducktail)
    lip = [(-2.225, y) for y in [-0.70 + 0.1 * i for i in range(15)]]
    B.keep(sweep_xy(surf0, lip, (0, 0, -1), rib_profile(0.085, 0.032, 0.010, 0.014), mat='M_Paint', step=0.04))
    # mirrors (small, chrome cap)
    zm = zbu_(0.78) + 0.045
    mh = surf0.hit(Vector((0.78, 0.0, zm - 0.03)), RAY_L)
    my = (mh[0].y - 0.02) if mh else 0.86
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint', length=0.15, width=0.085, height=0.09, arm_len=0.075)
        bmesh.ops.transform(m, matrix=T((0.80, s * my, zm)), verts=m.verts)
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
    lap("glass %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    lining = inner_trim_from_faces(bm, lambda f: f[tc] != 0 and (f[tc] in side_cols or f[tc] in top_cols) and
                                   f.calc_center_median().z > 1.0 and -1.62 < f.calc_center_median().x < 0.92,
                                   offset=0.03, mat='M_IntTrim')
    cleanup_slivers(bm)            # fix round 1: ~800 near-zero-area boolean fans (< 1e-7 m2) -> welded / dissolved, non-manifold healed
    fix_micro_islands(bm, max_dim=0.015, drop_open_below=0.004)      # fix round 1: welded 2-face junk sheets / specks, outward normals on micro solids
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    fix_object_micro_islands(body)          # fix round 1: finish_object() can weld a 2-face junk sheet again
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 6. wheels
    # ------------------------------------------------------------------------------------------------------------------
    for name, w in WHEELS.items():
        wb = build_wheel_ext(radius=w['radius'], width=w['width'], rim_radius=0.2159, rim_width=w['rim_w'], style='mag', side=w['side'],
                             brake_disc_radius=0.15, caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=56,
                             tyre_segments=64, hub_radius=0.055, dish=0.03, cap_chrome=True, bulge=1.03)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels")
    wf, wr = bounds_obj(bpy.data.objects[CAR + "_Wheel_FL"]), bounds_obj(bpy.data.objects[CAR + "_Wheel_RL"])      # measured tyre sizes -> root props
    set_root_props(root, wheel_width_front=round(wf[1].y - wf[0].y, 4), wheel_width_rear=round(wr[1].y - wr[0].y, 4),
                   wheel_radius_front=round((wf[1].z - wf[0].z) / 2, 4), wheel_radius_rear=round((wr[1].z - wr[0].z) / 2, 4))

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior(shell, dict(dash_x_back=0.50, dash_z_top=0.95, hw=0.78, front_x=-0.28, driver_y=0.38, rear_x=-1.00,
                                    rear_width=1.28, x_front_floor=0.86, x_rear_floor=-1.55, door_x=(-0.60, 0.74),
                                    quarter_x=(-1.55, -0.60), roof_x=(-1.30, 0.20), headliner=False, sport=True,
                                    floor_z=0.21, back_h=0.58, rear_z=0.26))
    delete_verts_where(ib, lambda co: co.z > 1.15 and abs(co.y) < 0.2 and 0.2 < co.x < 0.45)         # kit mirror is too tall for this roof
    _add(ib, build_rv_mirror(0.30, 1.13))
    _add(ib, lining)
    _add(ib, prim_box((0.62, 1.34, 0.03), (-1.40, 0, 0.80), mat='M_IntTrim', bevel=0.008, segments=1))       # parcel shelf under the glass
    _add(ib, prim_box((0.04, 1.30, 0.50), (-1.22, 0, 0.56), mat='M_IntTrim', bevel=0.01, segments=1))        # bulkhead
    # fix round 1: Thunderline cockpit character: chrome band across the dash face, chrome passenger grab bar and a triple auxiliary
    # gauge pod ahead of the gear lever (classic muscle-car console)
    _add(ib, prim_box((0.010, 1.20, 0.012), (0.498, 0.0, 0.815), mat='M_Chrome', bevel=0.003, segments=1))
    _add(ib, prim_box((0.018, 0.40, 0.020), (0.488, -0.36, 0.88), mat='M_Chrome', bevel=0.006, segments=2))
    _add(ib, prim_box((0.085, 0.27, 0.105), (0.30, 0.0, 0.560), mat='M_IntDash', bevel=0.02, segments=2))
    for yy in (-0.085, 0.0, 0.085):
        _add(ib, prim_cylinder(radius=0.029, depth=0.008, segments=20, axis='X', center=(0.2565, yy, 0.570), mat='M_TrimBlack'))
        _add(ib, prim_torus(R=0.031, r=0.0035, seg_major=20, seg_minor=6, axis='X', center=(0.2585, yy, 0.570), mat='M_Chrome'))
        _add(ib, prim_box((0.0010, 0.0035, 0.024), (0.2515, yy, 0.573), mat='M_Chrome'))                      # needle
    fix_micro_islands(ib)          # fix round 1: dial ticks / knobs get outward normals
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.33, 0.38, 0.915)
    swb, axis = build_steering_wheel(rim_radius=0.195, tube=0.0125, tilt=18.0, flat_bottom=False)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision + anchors
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.30, -1.8, -1.2, -0.6], low, z_clip=(0.19, 0.95), shrink=0.05),
        hull_points_from_shell(shell, [-0.6, 0.1, 0.8, 1.4], low, z_clip=(0.19, 0.93), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 0.96) - 0.012)) for p in
         hull_points_from_shell(shell, [1.4, 1.9, 2.3], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.22, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.85, 0.1, -0.5, -1.0, -1.6], ['belt_up', 'edge', 'top_c'], z_clip=(0.93, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)
    hl = (2.46, 0.575, 0.70)
    tl = (-2.43, 0.55, 0.805)
    add_anchors(CAR, col, root, {
        'LP_HeadL': (hl, 'PLAIN_AXES', 0.08), 'LP_HeadR': ((hl[0], -hl[1], hl[2]), 'PLAIN_AXES', 0.08),
        'LP_TailL': (tl, 'PLAIN_AXES', 0.08), 'LP_TailR': ((tl[0], -tl[1], tl[2]), 'PLAIN_AXES', 0.08),
        'LP_Reverse': ((-2.43, 0.70, 0.82), 'PLAIN_AXES', 0.08),
        'CAM_Hood': ((0.95, 0.0, 1.05), 'ARROWS', 0.15), 'CAM_Cockpit': ((-0.24, 0.38, 1.13), 'ARROWS', 0.15),
        'CAM_Bumper': ((2.46, 0.0, 0.45), 'ARROWS', 0.15),
        'EXHAUST_L': ((-2.385, 0.46, 0.37), 'PLAIN_AXES', 0.08), 'EXHAUST_R': ((-2.385, -0.46, 0.37), 'PLAIN_AXES', 0.08)})
    lo, hi = bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.9]
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    if globals().get("CAR03_QA", False):          # optional QA-only look() targets (set CAR03_QA = True; remove with purge_qa(CAR))
        focus_meshes(CAR, root.location.x, FOC)
    else:
        purge_qa(CAR)                             # fix round 1: no FOC_* / QA_* clutter in the shipped collection
    lap("done. L x W x H = %.3f x %.3f x %.3f (with mirrors %.3f wide)" % (root['length'], root['width'], root['height'], hi.y - lo.y))
    return root


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts_fix(CAR, ['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):          # front wheels (uv2) / rear wheels (uv3): keeps every Blender call well below 20 s
    unwrap_parts_fix(CAR, ['Wheel_FL', 'Wheel_FR'])
if STAGE in ("all", "uv", "uv3"):
    unwrap_parts_fix(CAR, ['Wheel_RL', 'Wheel_RR'])
