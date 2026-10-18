r"""lane11_wheels.py - wheel styles wheel_stock, wheel_five_spoke, wheel_split_six, wheel_mesh, wheel_dish, wheel_turbine,
wheel_steel_basic, wheel_offroad, wheel_lowprofile, wheel_mc_sport. Nodes: `Tire` (Tire material) and `Rim` (Rim / Chrome / MetalDark / Metal).
Spin axis X, origin = wheel centre, radius 0.34 m (mc: 0.31), width 0.24 m (mc: 0.17). BOTH faces carry the same detail, so the same mesh
works on the left and on the right side of a vehicle without flipping. Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""


def l11_ringpts(x, r, seg, ph=0.0):
    return [(x, r * math.cos(2 * math.pi * (i + ph) / seg), r * math.sin(2 * math.pi * (i + ph) / seg)) for i in range(seg)]


def l11_annulus(b, s, x, r_out, r_in, seg, mat, ph=0.0, x_in=None):
    """ring (open) whose normal points along s*X; x_in != None makes it a cone (dish) from (x, r_out) down to (x_in, r_in)."""
    o = [b.v(p) for p in l11_ringpts(x, r_out, seg, ph)]
    n = [b.v(p) for p in l11_ringpts(x if x_in is None else x_in, r_in, seg, ph)]
    for i in range(seg):
        j = (i + 1) % seg
        q = [o[i], o[j], n[j], n[i]]
        b.face(q if s > 0 else q[::-1], mat)


def l11_disc(b, s, x, r, seg, mat, ph=0.0):
    v = [b.v(p) for p in l11_ringpts(x, r, seg, ph)]
    b.face(v if s > 0 else v[::-1], mat)


def l11_xcyl(b, s, x_in, x_out, r_in, r_out, seg, mat, ph=0.0):
    """closed frustum between x_in (towards the tyre centre) and x_out (outer face), radii r_in / r_out (outer face = s side)."""
    lo, hi = (x_in, x_out) if x_in < x_out else (x_out, x_in)
    r_lo, r_hi = (r_in, r_out) if x_in < x_out else (r_out, r_in)
    b.cyl(((lo + hi) / 2, 0, 0), r_lo, hi - lo, seg, mat, axis="X", r_top=r_hi)


def l11_spokes(b, s, n, r0, r1, w0, w1, xc, t, mat, phase=0.0, sweep=0.0, caps=True):
    """n radial bars at plate x=xc (thickness t along X), from radius r0 to r1; sweep (deg) swirls the outer end."""
    for k in range(n):
        th = math.radians(phase + 360.0 * k / n)
        th1 = th + math.radians(sweep)
        p0 = (xc, r0 * math.cos(th), r0 * math.sin(th))
        p1 = (xc, r1 * math.cos(th1), r1 * math.sin(th1))
        l11_bar(b, p0, p1, w0, t, mat, up=(1, 0, 0), w1=w1, t1=t, caps=caps)


def l11_hub(b, s, x, r, h, seg, mat):
    b.cyl((x, 0, 0), r, h, seg, mat, axis="X")


def l11_tire_mesh(P, R, W, prof, seg):
    b = P.mb()
    ph = 0.0 if seg % 4 == 0 else 0.5
    rings = []
    for (x, r, pat) in prof:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * (i + ph) / seg
            rr = r * (pat(i) if pat else 1.0)
            ring.append(b.v((x, rr * math.cos(a), rr * math.sin(a))))
        rings.append(ring)
    n = len(rings)
    for k in range(n):
        k2 = (k + 1) % n
        for i in range(seg):
            j = (i + 1) % seg
            b.face([rings[k][i], rings[k][j], rings[k2][j], rings[k2][i]], "Tire")
    return P.add(b, node="Tire", smooth=40)


def l11_std_tire(R, W, rim_r, bead=0.012, tread_w=0.07, bulge=0.52):
    hw = W / 2
    mid = rim_r + bulge * (R - rim_r)
    return [(-hw + bead, rim_r, None), (-hw, mid, None), (-hw + tread_w, R, None), (hw - tread_w, R, None), (hw, mid, None), (hw - bead, rim_r, None)]


def l11_wheel(pid, face_fn, R=0.34, W=0.24, rim_r=0.235, seg=14, prof=None, budget=500):
    P = L11Part(pid, l11_idx(pid), budget=budget)
    hw = W / 2
    ph = 0.0 if seg % 4 == 0 else 0.5
    l11_tire_mesh(P, R, W, prof or l11_std_tire(R, W, rim_r), seg)
    b = P.mb()
    ctx = dict(R=R, W=W, hw=hw, rim_r=rim_r, seg=seg, ph=ph)
    for s in (1, -1):
        face_fn(b, s, ctx)
    P.add(b, node="Rim")
    return P


# ------------------------------------------------------------------------------------------------ styles
def l11_face_stock(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.99, rr * 0.70, seg, "Rim", ph, x_in=s * (hw - 0.034))
    l11_disc(b, s, s * (hw - 0.034), rr * 0.70, seg, "Rim", ph)
    xo = s * (hw - 0.0325)
    for k in range(5):
        th = math.radians(72 * k + 18)
        d = math.radians(13)
        pts = [(xo, 0.062 * math.cos(th - d * 0.6), 0.062 * math.sin(th - d * 0.6)), (xo, 0.062 * math.cos(th + d * 0.6), 0.062 * math.sin(th + d * 0.6)),
               (xo, 0.128 * math.cos(th + d), 0.128 * math.sin(th + d)), (xo, 0.128 * math.cos(th - d), 0.128 * math.sin(th - d))]
        b.fo(pts, "Trim", (s, 0, 0))
    l11_hub(b, s, s * (hw - 0.027), 0.050, 0.014, 8, "Chrome")


def l11_face_five_spoke(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.995, rr * 0.86, seg, "Rim", ph)
    l11_disc(b, s, s * (hw - 0.040), rr * 0.88, seg, "MetalDark", ph)
    l11_spokes(b, s, 5, 0.04, rr * 0.93, 0.052, 0.082, s * (hw - 0.022), 0.024, "Rim", phase=18)
    l11_hub(b, s, s * (hw - 0.020), 0.050, 0.028, 8, "Chrome")


def l11_face_split_six(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.995, rr * 0.88, seg, "Rim", ph)
    l11_disc(b, s, s * (hw - 0.040), rr * 0.90, seg, "MetalDark", ph)
    xc = s * (hw - 0.022)
    for k in range(6):
        th = math.radians(60 * k + 10)
        for sg in (-1, 1):
            a0 = th + math.radians(5 * sg)
            a1 = th + math.radians(15 * sg)
            p0 = (xc, 0.055 * math.cos(a0), 0.055 * math.sin(a0))
            p1 = (xc, rr * 0.92 * math.cos(a1), rr * 0.92 * math.sin(a1))
            l11_bar(b, p0, p1, 0.026, 0.022, "Rim", up=(1, 0, 0), w1=0.034, t1=0.022, caps=False)
    l11_hub(b, s, s * (hw - 0.020), 0.048, 0.028, 6, "Chrome")


def l11_face_mesh(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.995, rr * 0.80, seg, "Chrome", ph)
    l11_disc(b, s, s * (hw - 0.042), rr * 0.82, seg, "MetalDark", ph)
    xc = s * (hw - 0.026)
    n = 6
    for k in range(n):
        ai = math.radians(60 * k)
        for sg in (-1, 1):
            ao = ai + math.radians(30 * sg)
            p0 = (xc, 0.06 * math.cos(ai), 0.06 * math.sin(ai))
            p1 = (xc, rr * 0.82 * math.cos(ao), rr * 0.82 * math.sin(ao))
            l11_bar(b, p0, p1, 0.020, 0.018, "Rim", up=(1, 0, 0), caps=False)
    l11_hub(b, s, s * (hw - 0.020), 0.055, 0.030, 6, "Chrome")


def l11_face_dish(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.004), rr * 1.0, rr * 0.90, seg, "Chrome", ph)
    l11_annulus(b, s, s * (hw - 0.008), rr * 0.90, rr * 0.45, seg, "Rim", ph, x_in=s * (hw - 0.078))
    l11_disc(b, s, s * (hw - 0.078), rr * 0.45, seg, "Rim", ph)
    xo = s * (hw - 0.0765)
    for k in range(5):
        th = math.radians(72 * k + 18)
        pts = [(xo, 0.092 * math.cos(th) + 0.012 * math.cos(math.radians(a)) * 1.0, 0.092 * math.sin(th) + 0.012 * math.sin(math.radians(a))) for a in range(0, 360, 60)]
        b.fo(pts, "Chrome", (s, 0, 0))
    l11_hub(b, s, s * (hw - 0.072), 0.046, 0.016, 6, "Chrome")


def l11_face_turbine(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.995, rr * 0.88, seg, "Rim", ph)
    l11_disc(b, s, s * (hw - 0.040), rr * 0.90, seg, "Trim", ph)
    l11_spokes(b, s, 9, 0.05, rr * 0.92, 0.050, 0.056, s * (hw - 0.026), 0.018, "Rim", phase=0, sweep=-s * 30.0, caps=False)
    l11_hub(b, s, s * (hw - 0.024), 0.056, 0.020, 8, "Chrome")


def l11_face_steel(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 0.99, rr * 0.80, seg, "Rim", ph, x_in=s * (hw - 0.028))
    l11_disc(b, s, s * (hw - 0.028), rr * 0.80, seg, "Rim", ph)
    xo = s * (hw - 0.0265)
    for k in range(6):
        th = math.radians(60 * k + 30)
        d = math.radians(11)
        pts = [(xo, 0.100 * math.cos(th - d), 0.100 * math.sin(th - d)), (xo, 0.100 * math.cos(th + d), 0.100 * math.sin(th + d)),
               (xo, 0.150 * math.cos(th + d * 0.8), 0.150 * math.sin(th + d * 0.8)), (xo, 0.150 * math.cos(th - d * 0.8), 0.150 * math.sin(th - d * 0.8))]
        b.fo(pts, "Trim", (s, 0, 0))
    l11_hub(b, s, s * (hw - 0.018), 0.062, 0.020, 8, "Metal")


def l11_face_offroad(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.006), rr * 1.03, rr * 0.84, seg, "MetalDark", ph)
    l11_disc(b, s, s * (hw - 0.046), rr * 0.86, seg, "Trim", ph)
    for k in range(6):
        th = math.radians(60 * k + 10)
        cx, cy = rr * 0.93 * math.cos(th), rr * 0.93 * math.sin(th)
        xo = s * (hw - 0.0045)
        b.fo([(xo, cx + 0.0125 * math.cos(math.radians(a)), cy + 0.0125 * math.sin(math.radians(a))) for a in range(0, 360, 72)], "Chrome", (s, 0, 0))
    l11_spokes(b, s, 5, 0.04, rr * 0.88, 0.060, 0.074, s * (hw - 0.028), 0.030, "Rim", phase=18, caps=False)
    l11_hub(b, s, s * (hw - 0.024), 0.054, 0.032, 8, "Chrome")


def l11_face_lowprofile(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.004), rr * 1.0, rr * 0.92, seg, "Chrome", ph)
    l11_disc(b, s, s * (hw - 0.036), rr * 0.92, seg, "MetalDark", ph)
    l11_spokes(b, s, 10, 0.045, rr * 0.93, 0.024, 0.034, s * (hw - 0.022), 0.020, "Rim", phase=0, caps=False)
    l11_hub(b, s, s * (hw - 0.018), 0.046, 0.026, 6, "Chrome")


def l11_face_mc(b, s, c):
    hw, rr, seg, ph = c["hw"], c["rim_r"], c["seg"], c["ph"]
    l11_annulus(b, s, s * (hw - 0.004), rr * 1.0, rr * 0.88, seg, "Rim", ph)
    l11_disc(b, s, s * (hw - 0.034), rr * 0.90, seg, "MetalDark", ph)
    l11_annulus(b, s, s * (hw - 0.030), 0.150, 0.088, seg, "Metal", ph)
    l11_spokes(b, s, 5, 0.04, rr * 0.92, 0.040, 0.060, s * (hw - 0.018), 0.018, "Rim", phase=18, caps=False)
    l11_hub(b, s, s * (hw - 0.014), 0.040, 0.020, 6, "Chrome")


def l11_build_wheels(only=None):
    out = []
    R, W = 0.34, 0.24
    hw = W / 2
    defs = []
    defs.append(("wheel_stock", dict(face_fn=l11_face_stock, rim_r=0.225)))
    defs.append(("wheel_five_spoke", dict(face_fn=l11_face_five_spoke, rim_r=0.235)))
    defs.append(("wheel_split_six", dict(face_fn=l11_face_split_six, rim_r=0.235)))
    defs.append(("wheel_mesh", dict(face_fn=l11_face_mesh, rim_r=0.235)))
    defs.append(("wheel_dish", dict(face_fn=l11_face_dish, rim_r=0.24)))
    defs.append(("wheel_turbine", dict(face_fn=l11_face_turbine, rim_r=0.235)))
    defs.append(("wheel_steel_basic", dict(face_fn=l11_face_steel, rim_r=0.215)))
    # offroad: chunky zig-zag tread (alternating radii on staggered rows) and a tall sidewall
    rr = 0.205

    def pa(i):
        return 1.0 if i % 2 == 0 else 0.925

    def pb(i):
        return 0.925 if i % 2 == 0 else 1.0
    off_prof = [(-hw + 0.012, rr, None), (-hw, rr + 0.5 * (R - rr), None), (-hw + 0.022, R, pa), (-0.045, R, pb), (0.045, R, pa),
                (hw - 0.022, R, pb), (hw, rr + 0.5 * (R - rr), None), (hw - 0.012, rr, None)]
    defs.append(("wheel_offroad", dict(face_fn=l11_face_offroad, rim_r=rr, prof=off_prof)))
    lr = 0.285
    low_prof = [(-hw + 0.010, lr, None), (-hw, lr + 0.028, None), (-hw + 0.045, R, None), (hw - 0.045, R, None), (hw, lr + 0.028, None), (hw - 0.010, lr, None)]
    defs.append(("wheel_lowprofile", dict(face_fn=l11_face_lowprofile, rim_r=lr, prof=low_prof)))
    for (pid, kw) in defs:
        if only and pid not in only:
            continue
        P = l11_wheel(pid, R=R, W=W, **kw)
        P.report()
        out.append(P)
    # motorcycle sport wheel: r 0.31, width 0.17, round tyre section
    if not only or "wheel_mc_sport" in only:
        Rm, Wm, rm = 0.31, 0.17, 0.215
        h2 = Wm / 2
        mid = rm + 0.45 * (Rm - rm)
        mc_prof = [(-h2 + 0.008, rm, None), (-h2, mid, None), (-h2 * 0.55, Rm * 0.985, None), (0.0, Rm, None), (h2 * 0.55, Rm * 0.985, None),
                   (h2, mid, None), (h2 - 0.008, rm, None)]
        P = l11_wheel("wheel_mc_sport", l11_face_mc, R=Rm, W=Wm, rim_r=rm, seg=14, prof=mc_prof)
        P.report()
        out.append(P)
    return out
