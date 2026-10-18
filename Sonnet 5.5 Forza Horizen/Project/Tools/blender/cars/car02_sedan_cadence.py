"""
car02_sedan_cadence.py - parametric, idempotent build of the player car #2 "Cadence" (conservative 4-door three-box sedan, FWD).
Built with the shared car kit (Tools/blender/lib/carkit.py, Docs/CARKIT_API.md) + carkit_ext_02_03_04.py.

Run inside the verified Blender MCP session (localhost:9889):
    CAR02_STAGE = "all"      # "geometry" | "uv1" | "uv2" | "uv3" | "all"
    exec(compile(open(r"<project>/Tools/blender/cars/car02_sedan_cadence.py", encoding="utf8").read(), "car02", "exec"), globals())
Staged at x = 24 m (cars row, index 2), collection FORZA_UE/Cars/car02_sedan_cadence, root car02_sedan_cadence_ROOT.
Car space: +X forward, +Y left (LHD driver), +Z up, origin on the ground under the middle of the wheelbase.
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

CAR = "car02_sedan_cadence"
STAGE = globals().get("CAR02_STAGE", "all")

P = dict(
    id=CAR, display_name="Cadence", index=2,
    L=4.70, W=1.82, H=1.46, wheelbase=2.76, track_f=1.55, track_r=1.54,
    r_f=0.31, r_r=0.31, w_f=0.195, w_r=0.195, ride=0.14,           # 195/55 R16
    x_ws_base=1.06, x_ws_top=0.22,                                  # windscreen glass (x of its lower / upper edge)
    x_rg_top=-0.88, x_rg_base=-1.52,                                # rear glass
    x_end=2.31, cap_bulge=0.034, round_x=0.078,                     # fix round 1: tighter end rounding (was 0.04 / 0.10)
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
CHROME = rib_profile(0.012, 0.0045, 0.004, 0.002)

# greenhouse lines (x, z) -----------------------------------------------------------------------------------------------
A0, A1 = (0.97, 0.985), (0.18, 1.39)           # A-pillar line (front edge of the front door glass)
B0, B1 = (-0.145, 0.985), (-0.145, 1.47)       # rear edge of the front door glass
Q0, Q1 = (-0.215, 0.985), (-0.215, 1.47)       # front edge of the rear door glass
C0, C1 = (-1.17, 0.985), (-0.97, 1.39)         # rear edge of the rear door glass (C-pillar side)


FOC = {"front": ((2.35 - 0.4, -0.7, 0.3), (2.35, 0.7, 1.0)), "rear": ((-2.35, -0.7, 0.3), (-2.35 + 0.4, 0.7, 1.0)),
       "cabin": ((-1.0, -0.8, 0.9), (0.9, 0.8, 1.35)), "front34": ((0.9, -0.95, 0.2), (2.35, 0.95, 1.0)),
       "side": ((-2.35, -0.95, 0.1), (2.35, -0.9, 1.35)), "hood": ((0.9, -0.6, 0.85), (2.35 - 0.3, 0.6, 1.0)),
       "quarter": ((-1.7, -1.0, 0.5), (-0.3, -0.6, 1.3)), "rearL": ((-2.35, 0.3, 0.4), (-2.35 + 0.5, 0.95, 1.1)),
       "frontL": ((2.35 - 0.5, 0.3, 0.3), (2.35, 0.95, 1.0)), "rear34": ((-2.35, -0.95, 0.2), (-0.9, 0.95, 1.2))}      # QA-only look() targets (edge meshes, removed before export)


def body_curves():
    zt = fillet_profile(
        [(-2.36, 0.925), (-2.15, 0.975), (-1.55, 0.992), (-0.86, 1.43), (-0.30, 1.462), (0.22, 1.43), (1.06, 0.99),
         (2.05, 0.895), (2.24, 0.864), (2.33, 0.80), (2.36, 0.70)],
        [0, 0.35, 0.30, 0.9, 6.0, 0.9, 0.55, 2.0, 0.35, 0.10, 0], step=0.01)
    zf = smooth_keys([(-2.31, 0.31), (-2.27, 0.275), (-2.15, 0.245), (-1.9, 0.205), (-1.5, 0.17), (-0.8, 0.15), (0.0, 0.14),
                      (0.8, 0.15), (1.5, 0.17), (1.95, 0.205), (2.15, 0.225), (2.27, 0.255), (2.31, 0.31)], sigma=0.07)
    # fix round 1: squarer plan-view corners (fascia half width 0.78 / 0.72 instead of 0.74 / 0.67) -> less egg-shaped nose / tail
    hwm = smooth_keys([(-2.31, 0.785), (-2.27, 0.820), (-2.18, 0.858), (-2.0, 0.884), (-1.75, 0.898), (-1.38, 0.910),
                       (-0.9, 0.896), (0.0, 0.894), (0.9, 0.898), (1.38, 0.908), (1.75, 0.896), (1.98, 0.880), (2.12, 0.846),
                       (2.22, 0.806), (2.28, 0.762), (2.31, 0.716)], sigma=0.045)
    zw = smooth_keys([(-2.31, 0.52), (-1.9, 0.58), (-1.0, 0.60), (0, 0.60), (1.0, 0.60), (1.9, 0.57), (2.31, 0.50)], sigma=0.12)
    zb = smooth_keys([(-2.31, 0.80), (-2.25, 0.90), (-2.1, 0.935), (-1.7, 0.955), (-1.2, 0.975), (-0.4, 0.985), (0.3, 0.985),
                      (0.8, 0.972), (1.1, 0.935), (1.5, 0.895), (1.9, 0.85), (2.2, 0.805), (2.31, 0.72)], sigma=0.11)
    zc = smooth_keys([(-2.2, 0.81), (-1.5, 0.815), (0.0, 0.80), (1.0, 0.79), (1.7, 0.765), (2.2, 0.73)], sigma=0.12)
    # fix round 1: crisper / deeper shoulder crease (slab-sided flank): depth x1.35, transition 3 cm (cwidth)
    cdepth = smooth_keys([(-2.31, 0.0), (-2.05, 0.019), (-1.7, 0.049), (-1.2, 0.068), (0.0, 0.070), (1.0, 0.065),
                          (1.6, 0.046), (2.0, 0.014), (2.31, 0.0)], sigma=0.12)
    hw_ratio = as_curve(smooth_keys([(-2.31, 0.74), (-2.0, 0.80), (-1.6, 0.80), (-1.2, 0.775), (-0.9, 0.76), (-0.3, 0.76),
                                     (0.2, 0.77), (0.8, 0.80), (1.1, 0.82), (1.8, 0.82), (2.31, 0.78)], sigma=0.15))
    dz = as_curve(smooth_keys([(-2.31, 0.04), (-2.0, 0.035), (-1.5, 0.04), (-1.1, 0.06), (-0.5, 0.07), (0.2, 0.065), (0.8, 0.045),
                               (1.1, 0.04), (1.8, 0.036), (2.31, 0.03)], sigma=0.15))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    door_win = as_curve([(-1.1, 0.0), (-0.7, 1.0), (0.7, 1.0), (1.05, 0.0)], mode='smooth')

    def hwb(x):
        return hwmc(x) - (0.085 + 0.010 * smoothstep(0.9, 0.5, x))

    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth, cwidth=0.032,
        hwe=lambda x: hwb(x) * hw_ratio(x),
        ze=lambda x: ztc(x) - dz(x),
        hwb=hwb,
        hws=lambda x: hwmc(x) - (0.060 + 0.050 * door_win(x)),
        zs=lambda x: zfc(x) + 0.095,
        belt_step=0.018, crease=0.016,
    )


def build():
    B = Build("car02")
    lap = B.lap
    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="FWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. shell
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    xe, rr_ = P['x_end'], P['round_x']
    xs = station_list(-xe, xe, dx=0.05, end_dx=0.018, end_len=0.28, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], P['x_rg_top'], P['x_rg_base']] +
                      end_round_stations(-xe, rr_, 6, at_start=True) + end_round_stations(xe, rr_, 6, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr_, round_x1=rr_)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, bumper_cols, side_cols_all = set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        bumper_cols |= shell_quad_cols(shell, 'sill', 'wide', sd, frac=(0.0, 0.75))
        side_cols_all |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
    Z_FRONT_VAL, Z_REAR_VAL = 0.43, 0.46
    for z_cut, in_zone in ((Z_FRONT_VAL, lambda x: x > 1.74), (Z_REAR_VAL, lambda x: x < -1.74)):
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
        elif abs(c.x) > 1.74 and c.z < (Z_FRONT_VAL if c.x > 0 else Z_REAR_VAL):
            m = 'M_TrimBlack'                                   # wrapped black lower bumper band (ends at the wheel arches)
        elif tag in side_cols_all and (Q1[0] - 0.0 < c.x < B0[0] + 0.0) and c.z > 0.9:
            m = 'M_TrimBlack'                                   # B-pillar
        f.material_index = mi(m)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters
    # ------------------------------------------------------------------------------------------------------------------
    RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)
    VL = Vector((0, 0, 1))
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        B.cut(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))
    zd = 0.975
    door_f = [(0.915, zd), (0.935, 0.85), (0.945, 0.65), (0.955, 0.45), (0.957, 0.31), (0.925, 0.272), (0.5, 0.262), (0.0, 0.262),
              (-0.14, 0.262), (-0.148, 0.31), (-0.146, 0.50), (-0.145, 0.75), (-0.145, zd)]
    door_r = [(-0.215, zd), (-0.217, 0.75), (-0.220, 0.50), (-0.222, 0.31), (-0.23, 0.265), (-0.55, 0.262), (-0.95, 0.266),
              (-1.04, 0.30), (-1.075, 0.45), (-1.11, 0.62), (-1.15, 0.80), (-1.18, zd)]
    B.pair(surface_sweep(surf0, poly_pts(door_f, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    B.pair(surface_sweep(surf0, poly_pts(door_r, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    # hood: shut lines around the bonnet
    B.cut(sweep_xy(surf0, hood_loop_xy(shell, 1.10, 2.25, r=0.15), (0, 0, -1), GROOVE, mat='M_Underbody', step=0.03, closed=True))
    # trunk lid: front cut under the rear glass, side cuts along the deck edge, lower cut across the tail
    x_trunk = -1.585
    B.cut(surface_sweep(surf0, resample_poly([Vector((x_trunk, y, 0)) for y in (0.70, -0.70)], 0.04), (0, 0, -1), GROOVE,
                        mat='M_Underbody'))
    tgs = [Vector((x, edge_y(shell, x) - 0.012, 0)) for x in (x_trunk, -1.70, -1.85, -2.0, -2.12, -2.2)]
    B.pair(surface_sweep(surf0, resample_poly(tgs, 0.04), (0, 0, -1), GROOVE, mat='M_Underbody'))
    B.cut(surface_sweep(surf0, resample_poly([Vector((0, 0.60, 0.745)), Vector((0, -0.60, 0.745))], 0.04), RAY_R, GROOVE,
                        mat='M_Underbody'))
    B.cut(surface_sweep(surf0, circle_pts(-1.80, 0.80, 0.07, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody'))
    lap("grooves + arches")

    # ------------------------------------------------------------------------------------------------------------------
    # 3. lamps, grilles, plates
    # ------------------------------------------------------------------------------------------------------------------
    RH = ('radial', Vector((1.85, 0.30, 0.74)))
    UL = Vector((0.55, -0.835, 0.0)).normalized()
    c_head = Vector((2.14, 0.64, 0.745))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.25, height=0.050, rot=0.20, floor_mat='M_TrimGrey')
    if cut is None:
        lap("headlight FAILED")
    B.pair(cut)
    for b in ins:
        B.pair_in(b)
    B.pair_in(lamp_bezel(surf0, c_head, RH, (UL, VL), 0.25, 0.050, rot=0.20, mat='M_Chrome', width=0.010))

    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)

    # upright chrome-framed grille
    gz = 0.640
    g_out = outline_rrect(0.66, 0.15, 0.03, 4)
    B.cut(nose_pocket((2.4, 0.0, gz), g_out, 0.07))
    fm = anchor_frame(surf0, (2.4, 0, gz), RAY_F, sink=0.04)
    g = grille_mesh([(p[0] * 0.97, p[1] * 0.90) for p in g_out], kind='bars', pitch=0.026, bar=0.008, depth=0.022, frame=0.006,
                    mat='M_Chrome', frame_mat='M_Chrome')
    bmesh.ops.transform(g, matrix=fm, verts=g.verts)
    B.keep(g)
    B.keep(sweep_yz(surf0, [(p[0] * 1.02, gz + p[1] * 1.04) for p in outline_rrect(0.66, 0.15, 0.03, 4)], 2.4, RAY_F,
                    rib_profile(0.016, 0.006, 0.006, 0.003), mat='M_Chrome', closed=True))
    cut, plate = plate_recess(surf0, (2.4, 0.0, 0.50), RAY_F)
    B.cut(cut)
    B.keep(plate)
    low_out = outline_rrect(0.90, 0.11, 0.03, 5)
    B.cut(nose_pocket((2.4, 0.0, 0.345), low_out, 0.07))
    fm = anchor_frame(surf0, (2.4, 0, 0.345), RAY_F, sink=0.04)
    g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in low_out], kind='hex', pitch=0.034, bar=0.006, depth=0.022, frame=0.01)
    bmesh.ops.transform(g, matrix=fm, verts=g.verts)
    B.keep(g)
    fogd = Vector((-0.97, -0.24, 0.0)).normalized()
    fogU = Vector((0.24, -0.97, 0.0)).normalized()
    cut, lens = lamp_unit(surf0, Vector((2.26, 0.66, 0.35)), fogd, outline_ellipse(0.04, 0.03, 18), depth=0.04, lens_inset=0.004,
                          axes=(fogU, VL), lens_mat='M_Headlight', taper=0.8)
    if cut is not None:
        B.pair(cut)
        B.pair_in(lens)

    # tail lamps + plate + exhaust
    # fix round 1: clean wrap-around lamp (shallow black pocket, one smooth red lens over amber | white, chrome bezel), moved 1 cm
    # down so the bezel no longer runs over the deck-shoulder crease (that made the wavy notch)
    RT = ('radial', Vector((-2.00, 0.30, 0.835)))
    UT = Vector((0.62, 0.785, 0.0)).normalized()
    c_tail = Vector((-2.235, 0.68, 0.835))
    cut, ins = build_taillight_clean(surf0, c_tail, RT, (UT, VL), length=0.30, height=0.066, rot=0.10)
    if cut is None:
        lap("taillight FAILED")
    B.pair(cut)
    for b in ins:
        B.pair_in(b)
    cut, plate = plate_recess(surf0, (-2.4, 0.0, 0.64), RAY_R)
    B.cut(cut)
    B.keep(plate)
    for s in (1, -1):
        B.cut(prim_cylinder(radius=0.045, depth=0.20, segments=24, axis='X', center=(-2.26, s * 0.58, 0.40), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.034, length=0.12, lip=0.004)
        bmesh.ops.transform(tip, matrix=T((-2.31, s * 0.58, 0.40)), verts=tip.verts)
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

    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        sw = arch_moulding(surf0, cx, cz, w['radius'] + ARCH_PAD + 0.020, (0, -1, 0) if cy > 0 else (0, 1, 0), width=0.032,
                           height=0.010)
        if sw is not None:
            B.keep(sw)             # (right wheels are swept from the right with the ray (0, 1, 0): no mirroring needed)
    B.pair_in(surface_sweep(surf0, poly_pts([(-0.95, 0.256), (-0.4, 0.252), (0.0, 0.250), (0.4, 0.252), (0.90, 0.256)], subdiv=2),
                            RAY_L, rib_profile(0.06, 0.014, 0.012, 0.005), mat='M_TrimBlack'))
    B.pair_in(build_splitter(surf0, RAY_F, out=0.030, inn=0.05))
    # fix round 1: black body-side rub moulding with a chrome insert along both doors (breaks up the slab-sided flank)
    rub = [(-1.10, 0.545), (-0.55, 0.545), (0.0, 0.545), (0.55, 0.545), (0.90, 0.548)]
    B.pair_in(surface_sweep(surf0, poly_pts(rub, subdiv=2), RAY_L, rib_profile(0.050, 0.010, 0.010, 0.004), mat='M_TrimBlack'))
    B.pair_in(surface_sweep(surf0, poly_pts([(x, z + 0.0) for (x, z) in rub], subdiv=2), RAY_L, rib_profile(0.008, 0.0125, 0.010, 0.002),
                            mat='M_Chrome'))
    # chrome window trim: closed loops round the two side windows (rounded corners), lower belt strip
    def zbu_(x):
        return ring_pt(shell, x, 'belt_up')[1]

    def zed_(x):
        return ring_pt(shell, x, 'edge')[1]

    def line_x(p0, p1, z):
        return p0[0] + (p1[0] - p0[0]) * (z - p0[1]) / (p1[1] - p0[1])

    def window_loop(xa_fn, xb_fn, n=14):
        zb0 = lambda x: zbu_(x) + 0.001
        xa0, xb0 = xa_fn(0.985), xb_fn(0.985)
        top_pts = [(xa_fn(1.39) + (xb_fn(1.39) - xa_fn(1.39)) * i / n, 0) for i in range(n + 1)]
        pts = [(xa0, zb0(xa0)), (xb0, zb0(xb0))]
        # up the rear edge to the roof edge, along the roof edge back to the front, down the front edge
        xt_b = xb_fn(1.39)
        pts += [(xt_b, zed_(xt_b) - 0.012)]
        xt_a = xa_fn(1.39)
        for i in range(1, 6):
            x = xt_b + (xt_a - xt_b) * i / 6.0
            pts.append((x, zed_(x) - 0.012))
        pts.append((xt_a, zed_(xt_a) - 0.012))
        return pts
    fa = lambda z: line_x(A0, A1, z)
    fb = lambda z: B0[0]
    fq = lambda z: Q0[0]
    fc = lambda z: line_x(C0, C1, z)
    for (xa, xb) in ((fa, fb), (fq, fc)):
        poly = window_loop(xa, xb)
        B.pair_in(sweep_loop(surf0, rounded_poly(poly, 0.035, 4), RAY_L, CHROME, mat='M_Chrome', step=0.03))
    # door handles (chrome), cowl strip, wipers
    for x in (0.02, -0.93):
        B.pair_in(door_handle(surf0, x, 0.86, RAY_L, mat='M_Chrome'))
    B.keep(surface_sweep(surf0, [Vector((1.085, y, 0)) for y in [0.62 - 0.08 * i for i in range(16)]], (0, 0, -1),
                         rib_profile(0.07, 0.009, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((1.04, 0.10), (0.99, 0.62)), ((1.04, -0.62), (0.99, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        B.keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    B.keep(sweep_yz(surf0, [(-0.44, 0.795), (0.44, 0.795)], -2.4, RAY_R, rib_profile(0.014, 0.005, 0.005, 0.0025), mat='M_Chrome', step=0.04))
    # badge, mirrors
    zm = zbu_(0.84) + 0.045
    mh = surf0.hit(Vector((0.84, 0.0, zm - 0.03)), RAY_L)
    my = (mh[0].y - 0.02) if mh else 0.82
    for s in (1, -1):
        m = build_mirror(side=s, mat_shell='M_Paint', length=0.17, width=0.092, height=0.10, arm_len=0.085)
        bmesh.ops.transform(m, matrix=T((0.86, s * my, zm)), verts=m.verts)
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

    def door_f_pred(f):
        if f[tc] not in side_cols:
            return False
        c = f.calc_center_median()
        return behind(c, A0, A1) and not behind(c, B0, B1)

    def door_r_pred(f):
        if f[tc] not in side_cols:
            return False
        c = f.calc_center_median()
        return behind(c, Q0, Q1) and not behind(c, C0, C1)

    def ws_pred(f):
        return f[tc] in top_cols and P['x_ws_top'] < f.calc_center_median().x < P['x_ws_base']

    def rear_pred(f):
        return f[tc] in top_cols and P['x_rg_base'] < f.calc_center_median().x < P['x_rg_top']

    wins = [dict(name='door_f', pred=door_f_pred, zone=side_zone, planes=[plane(A0, A1), plane(B0, B1)]),
            dict(name='door_r', pred=door_r_pred, zone=side_zone, planes=[plane(Q0, Q1), plane(C0, C1)]),
            dict(name='windscreen', pred=ws_pred), dict(name='rear', pred=rear_pred)]
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    # roof lining + pillar linings: inward copies of every remaining greenhouse face
    lining = inner_trim_from_faces(bm, lambda f: f[tc] != 0 and (f[tc] in side_cols or f[tc] in top_cols) and
                                   f.calc_center_median().z > 1.03 and -1.62 < f.calc_center_median().x < 1.10,
                                   offset=0.03, mat='M_IntTrim')
    cleanup_slivers(bm)            # fix round 1: ~850 near-zero-area boolean fans (< 1e-7 m2) -> welded / dissolved, non-manifold healed
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
        wb = build_wheel_ext(radius=w['radius'], width=w['width'], rim_radius=0.2032, rim_width=0.165, style='ten', side=w['side'],
                             brake_disc_radius=0.13, caliper_angle=35.0 if name[0] == 'F' else 20.0, segments=56,
                             tyre_segments=64, hub_radius=0.05, cap_chrome=True)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels")
    wf, wr = bounds_obj(bpy.data.objects[CAR + "_Wheel_FL"]), bounds_obj(bpy.data.objects[CAR + "_Wheel_RL"])      # measured tyre sizes -> root props
    set_root_props(root, wheel_width_front=round(wf[1].y - wf[0].y, 4), wheel_width_rear=round(wr[1].y - wr[0].y, 4),
                   wheel_radius_front=round((wf[1].z - wf[0].z) / 2, 4), wheel_radius_rear=round((wr[1].z - wr[0].z) / 2, 4))

    # ------------------------------------------------------------------------------------------------------------------
    # 7. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior(shell, dict(dash_x_back=0.72, dash_z_top=0.95, hw=0.76, front_x=-0.05, driver_y=0.36, rear_x=-0.93,
                                    rear_width=1.30, x_front_floor=1.02, x_rear_floor=-1.52, door_x=(-1.04, 0.96),
                                    quarter_x=(-1.52, -1.04), roof_x=(-1.35, 0.22), headliner=False, sport=False,
                                    floor_z=0.22, back_h=0.60))
    _add(ib, lining)
    _add(ib, prim_box((0.46, 1.34, 0.03), (-1.30, 0, 0.925), mat='M_IntTrim', bevel=0.008, segments=1))       # parcel shelf
    _add(ib, prim_box((0.04, 1.30, 0.60), (-1.14, 0, 0.62), mat='M_IntTrim', bevel=0.01, segments=1))         # bulkhead
    # fix round 1: Cadence cockpit character: cream trim band framed by two chrome lines across the dash face (conservative, upscale)
    _add(ib, prim_box((0.008, 1.16, 0.050), (0.718, 0.0, 0.815), mat='M_IntTrim', bevel=0.004, segments=1))
    for zz in (0.843, 0.787):
        _add(ib, prim_box((0.010, 1.16, 0.004), (0.717, 0.0, zz), mat='M_Chrome', bevel=0.001, segments=1))
    fix_micro_islands(ib)          # fix round 1: dial ticks / knobs get outward normals
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.57, 0.36, 0.93)
    swb, axis = build_steering_wheel(rim_radius=0.19, tube=0.0185, tilt=22.0, flat_bottom=False)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior")

    # ------------------------------------------------------------------------------------------------------------------
    # 8. collision + anchors
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'sill', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-2.22, -1.7, -1.0, -0.4], low, z_clip=(0.19, 0.92), shrink=0.05),
        hull_points_from_shell(shell, [-0.4, 0.4, 1.0, 1.55], low, z_clip=(0.19, 0.92), shrink=0.05),
        [Vector((p.x, p.y, min(p.z, 0.99) - 0.012)) for p in
         hull_points_from_shell(shell, [1.55, 1.95, 2.25], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'], z_clip=(0.22, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [1.0, 0.1, -0.8, -1.55], ['belt_up', 'edge', 'top_c'], z_clip=(0.90, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)

    def lamp_point(center, ray, lift=0.03):
        h = surf0.hit(Vector(center), ray)
        return tuple(round(c, 4) for c in (h[0] + h[1] * lift)) if h else tuple(center)
    hl = lamp_point(c_head, RH)
    tl = lamp_point(c_tail, RT)
    rv = lamp_point(c_tail - UT * 0.14 - VL * 0.025, RT)
    add_anchors(CAR, col, root, {
        'LP_HeadL': (hl, 'PLAIN_AXES', 0.08), 'LP_HeadR': ((hl[0], -hl[1], hl[2]), 'PLAIN_AXES', 0.08),
        'LP_TailL': (tl, 'PLAIN_AXES', 0.08), 'LP_TailR': ((tl[0], -tl[1], tl[2]), 'PLAIN_AXES', 0.08),
        'LP_Reverse': (rv, 'PLAIN_AXES', 0.08),
        'CAM_Hood': ((1.12, 0.0, 1.05), 'ARROWS', 0.15), 'CAM_Cockpit': ((-0.04, 0.36, 1.21), 'ARROWS', 0.15),
        'CAM_Bumper': ((2.40, 0.0, 0.45), 'ARROWS', 0.15),
        'EXHAUST_L': ((-2.31, 0.58, 0.40), 'PLAIN_AXES', 0.08), 'EXHAUST_R': ((-2.31, -0.58, 0.40), 'PLAIN_AXES', 0.08)})
    lo, hi = bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.9]
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    if globals().get("CAR02_QA", False):          # optional QA-only look() targets (set CAR02_QA = True; remove with purge_qa(CAR))
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
