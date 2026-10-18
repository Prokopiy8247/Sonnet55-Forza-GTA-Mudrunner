"""lane4_body.py - builds human__Body_A / Body_B / Body_C (skinned to human__Armature).
Run after gta_lib.py + lane4_lib.py + lane4_rig.py. Set C4_KINDS = ['A'] (list) before exec to build only some bodies."""

C4_HEAD_UP = [(1.725, .100, .118, .004), (1.775, .080, .100, 0.0), (1.800, .044, .064, -.004)]   # cranium identical for all bodies
C4_BODY = {
    "A": dict(
        torso=[(0.88, .158, .102, 0), (0.94, .200, .114, 0), (1.00, .186, .108, 0), (1.06, .172, .102, 0), (1.13, .166, .102, 0),
               (1.21, .186, .110, 0), (1.30, .214, .124, 0), (1.385, .230, .120, 0), (1.43, .204, .106, 0), (1.468, .096, .074, 0)],
        head=[(1.520, .042, .054, .050), (1.552, .076, .090, .028), (1.600, .096, .110, .014), (1.660, .103, .118, .008)] + C4_HEAD_UP,
        neck=.056, arm=1.15, leg=1.0, hand=1.35, shoe=1.1, nose=(.028, .030), brow=.020, eye=(.026, .015), pocket=True, earscale=1.0, mouth=.034, p=2.3),
    "B": dict(
        torso=[(0.88, .154, .100, 0), (0.94, .204, .114, 0), (1.00, .180, .106, 0), (1.06, .150, .096, 0), (1.13, .136, .092, 0),
               (1.21, .160, .106, .004), (1.30, .186, .126, .012), (1.385, .200, .112, .002), (1.43, .168, .096, 0), (1.468, .084, .068, 0)],
        head=[(1.520, .036, .048, .052), (1.552, .068, .084, .030), (1.600, .090, .106, .015), (1.660, .100, .115, .008)] + C4_HEAD_UP,
        neck=.048, arm=.98, leg=.93, hand=1.15, shoe=.98, nose=(.023, .025), brow=.012, eye=(.028, .016), pocket=False, earscale=.85, mouth=.030, p=2.3),
    "C": dict(
        torso=[(0.88, .168, .112, 0), (0.94, .202, .124, 0), (1.00, .198, .130, .006), (1.06, .200, .134, .010), (1.13, .200, .134, .012),
               (1.21, .212, .126, .006), (1.30, .228, .126, 0), (1.385, .238, .120, 0), (1.43, .206, .106, 0), (1.468, .100, .076, 0)],
        head=[(1.520, .052, .060, .048), (1.552, .086, .094, .026), (1.600, .100, .110, .012), (1.660, .104, .118, .008)] + C4_HEAD_UP,
        neck=.064, arm=1.28, leg=1.12, hand=1.5, shoe=1.2, nose=(.032, .034), brow=.024, eye=(.024, .014), pocket=True, earscale=1.1, mouth=.038, p=2.3),
}

C4_ARM_PROF = [(0.0, .056, None), (0.06, .066, "Shirt"), (0.16, .062, "Shirt"), (0.215, .058, "Shirt"),
               (0.228, .059, "Accent"), (0.229, .052, "Accent"), (0.27, .054, "Skin"), (0.30, .057, "Skin"), (0.345, .055, "Skin"),
               (0.45, .046, "Skin"), (0.535, .038, "Skin"), (0.572, .036, "Skin")]
C4_LEG_PROF = [(0.975, .090, .096, 0), (0.90, .100, .104, 0), (0.80, .096, .100, 0), (0.68, .086, .091, 0), (0.57, .076, .082, 0),
               (0.51, .076, .086, .006), (0.46, .072, .079, 0), (0.38, .072, .079, -.004), (0.28, .068, .076, -.008),
               (0.19, .060, .067, -.004), (0.12, .056, .062, 0), (0.08, .056, .062, 0)]
C4_SHOE_ST = [(-0.082, .044, .092, 0.0, .028), (-0.045, .054, .118, 0.0, .028), (0.02, .057, .112, 0.0, .028), (0.08, .059, .094, 0.0, .028),
              (0.15, .062, .072, 0.0, .028), (0.225, .058, .062, 0.0, .026), (0.282, .046, .050, .010, .022)]


def c4_torso(b, P, margin=0.0, mats=None, n=12, tag=T_TORSO):
    b.cur = tag
    rings = [c4_ring((0, cy, z), C4_X, C4_Y, rx + margin, ry + margin, n, 0.0, P["p"]) for (z, rx, ry, cy) in P["torso"]]
    m = mats or ["Pants", "Pants", "Accent", "Shirt", "Shirt", "Shirt", "Shirt", "Shirt", "Shirt"]
    b.loft2(rings, m, cap0=m[0], cap1=m[-1])
    if margin == 0.0 and mats is None:
        rx, ry, cy = c4_interp_rings(P["torso"], 1.03)
        b.box((0, cy + ry + .004, 1.03), (.042, .012, .042), "Chrome")          # belt buckle
        if P.get("pocket"):
            rx, ry, cy = c4_interp_rings(P["torso"], 1.26)
            ys = cy + ry * (1 - (.095 / rx) ** P["p"]) ** (1.0 / P["p"])
            b.box((-.095, ys + .002, 1.255), (.07, .014, .075), "Shirt")   # chest pocket
            b.box((-.095, ys + .004, 1.287), (.074, .016, .014), "Accent") # pocket flap


def c4_neck(b, P):
    b.cur = T_NECK
    r = P["neck"]
    rings = [c4_ring((0, 0.004, z), C4_X, C4_Y, r, r * .92, 8) for z in (1.40, 1.46, 1.54, 1.58)]
    b.loft2(rings, "Skin", cap0="Skin", cap1="Skin")
    # ribbed collar band (closed torus-like ring), moves with the torso/neck blend
    b.cur = T_TORSO
    c = []
    for z, dr in ((1.452, .022), (1.488, .012), (1.488, -.004), (1.452, 0.002)):
        c.append(c4_ring((0, 0.004, z), C4_X, C4_Y, r + dr, (r + dr) * .94, 10))
    b.loft2(c, "Accent", wrap=True)


def c4_head(b, P):
    b.cur = T_HEAD
    H = P["head"]
    rings = [c4_ring((0, cy, z), C4_X, C4_Y, rx, ry, 12, 0.0, 2.2) for (z, rx, ry, cy) in H]
    b.loft2(rings, "Skin", cap0="Skin", cap1="Skin")
    fy = lambda x, z: c4_front_y(H, x, z)
    # nose wedge
    nl, nw = P["nose"]
    yt = fy(0, 1.700); yb = fy(0, 1.606)
    tl = (-.011, fy(-.011, 1.694) + .002, 1.694); tr = (.011, fy(.011, 1.694) + .002, 1.694)
    bl = (-nw, fy(-nw, 1.604) - .003, 1.604); br = (nw, fy(nw, 1.604) - .003, 1.604)
    tip = (0, yb + nl, 1.610)
    for tri in ((tl, tr, tip), (tl, tip, bl), (tr, br, tip), (bl, br, tip)):
        b.tri(*tri, mat="Skin")
    b.quad(tl, bl, br, tr, mat="Skin")
    # brow ridge (two wedges following the facets)
    bh = P["brow"]
    for s in (1, -1):
        rr = []
        for x in (0.004, 0.042, 0.084):
            yf_b = fy(x, 1.694); yf_t = fy(x, 1.716)
            rr.append([(s * x, yf_b + bh * .55, 1.694), (s * x, yf_t + bh * .35, 1.716), (s * x, yf_t - .02, 1.716), (s * x, yf_b - .02, 1.694)])
        b.loft2(rr, "Skin", cap0="Skin", cap1="Skin")
    # eyes: small dark insets
    ew, eh = P["eye"]
    for s in (1, -1):
        x = s * .034
        b.box((x, fy(x, 1.670) - .001, 1.670), (ew, .008, eh), mat="Trim")
    ym = fy(0, 1.578)
    b.box((0, ym, 1.578), (P['mouth'], .006, .006), mat="Trim")
    # ears
    es = P["earscale"]
    rxe = c4_interp_rings(H, 1.665)[0]
    pts = [(-0.012, 1.692), (0.012, 1.690), (0.022, 1.668), (0.010, 1.640), (-0.012, 1.646), (-0.020, 1.668)]
    for s in (1, -1):
        r_in = [Vector((s * (rxe - .006), p[0] * es, 1.666 + (p[1] - 1.666) * es)) for p in pts]
        r_out = [Vector((s * (rxe + .014), p[0] * es * .8, 1.666 + (p[1] - 1.666) * es * .8)) for p in pts]
        b.loft2([r_in, r_out], "Skin", cap0="Skin", cap1="Skin")


def c4_arm(b, P, sx):
    b.cur = T_ARM_R if sx > 0 else T_ARM_L
    S = Vector((0.19 * sx, 0, 1.40)); E = Vector((0.30 * sx, 0, 1.12)); W = Vector((0.40 * sx, 0, 0.87))
    L0 = (E - S).length; L1 = (W - E).length
    d0 = (E - S) / L0; d1 = (W - E) / L1
    sc = P["arm"]
    rings, mats = [], []
    for (u, r, m) in C4_ARM_PROF:
        if u <= L0:
            c = S + d0 * u; d = d0
        else:
            c = E + d1 * (u - L0); d = d1
        uv = C4_Y.cross(d).normalized()
        rings.append(c4_ring(c, uv, C4_Y, r * sc * .97, r * sc, 10, 18.0 * math.pi / 180))
        mats.append(m)
    b.loft2(rings, mats[1:], cap0="Shirt", cap1="Skin")


def c4_hand(b, P, sx):
    b.cur = T_HAND_R if sx > 0 else T_HAND_L
    W = Vector((0.40 * sx, 0, 0.87)); T = Vector((0.44 * sx, 0, 0.76))
    d = (T - W).normalized()
    uv = C4_Y.cross(d).normalized()
    k = P["hand"]
    prof = [(-0.025, .031, .033), (0.012, .030, .037), (0.050, .022, .046), (0.088, .020, .043), (0.118, .013, .029)]
    rings = [c4_ring(W + d * s, uv, C4_Y, th * k, wd * k, 8) for s, th, wd in prof]
    b.loft2(rings, "Skin", cap0="Skin", cap1="Skin")
    p0 = W + d * 0.030 + C4_Y * (0.030 * k)
    tdir = (C4_Y * 0.75 + d * 0.55).normalized()
    b.beam(p0, p0 + tdir * (0.055 * k), 0.017 * k, 0.011 * k, 5, "Skin")


def c4_leg(b, P, sx):
    b.cur = T_LEG_R if sx > 0 else T_LEG_L
    sc = P["leg"]
    rings = []
    for (z, rx, ry, cy) in C4_LEG_PROF:
        xc = 0.09 + (0.92 - z) / 0.42 * 0.01 if z > 0.5 else 0.10
        rings.append(c4_ring((sx * xc, cy, z), C4_X, C4_Y, rx * sc, ry * sc, 10, 18.0 * math.pi / 180))
    b.loft2(rings, "Pants", cap0="Pants", cap1="Pants")


def c4_shoe(b, P, sx):
    b.cur = T_SHOE_R if sx > 0 else T_SHOE_L
    k = P["shoe"]
    rings = []
    for (y, w, zt, zs, th) in C4_SHOE_ST:
        w = w * k
        zm = zs + th + (zt - zs - th) * .55
        pts = [(w, zs + th), (.92 * w, zm), (.55 * w, zt), (-.55 * w, zt), (-.92 * w, zm), (-w, zs + th), (-.88 * w, zs), (.88 * w, zs)]
        rings.append([Vector((sx * .10 + px, y, pz)) for (px, pz) in pts])
    up = ["Shoes"] * 5 + ["Trim"] * 3
    toe = ["Shoes", "Accent", "Accent", "Accent", "Shoes", "Trim", "Trim", "Trim"]
    b.loft2(rings, [up] * 5 + [toe], cap0="Shoes", cap1="Accent")


def c4_build_body(kind):
    P = C4_BODY[kind]
    b = CB("body_" + kind)
    c4_torso(b, P)
    c4_neck(b, P)
    c4_head(b, P)
    for sx in (1, -1):
        c4_arm(b, P, sx)
        c4_hand(b, P, sx)
        c4_leg(b, P, sx)
        c4_shoe(b, P, sx)
    obj = c4_finish(b, "Body_" + kind)
    return obj


for _k in globals().get("C4_KINDS", ["A"]):
    _o = c4_build_body(_k)
    print(_k, "tris", c4_tris(_o), "verts", len(_o.data.vertices), "inverted_islands", sum(1 for (_f, _v, _oe) in c4_islands(_o) if _v < 0), "open_islands", sum(1 for (_f, _v, _oe) in c4_islands(_o) if _oe > 0),
          "groups", len(_o.vertex_groups), "mats", [m.name for m in _o.data.materials])
