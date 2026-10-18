"""lane6_houselib.py - helpers for complete houses / small buildings (lane 6). Load after lane6_kitlib.py.
WallRef gives wall-local coordinates (u along the wall, d outward from the wall plane, z up) so windows/doors/trim can be
written once and used on all four walls of a footprint."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())


class WallRef:
    def __init__(self, b, axis, c, s):
        self.b, self.axis, self.c, self.s = b, axis, c, s

    def P(self, u, d, z):
        return (u, self.c + self.s * d, z) if self.axis == "y" else (self.c + self.s * d, u, z)

    def N(self, u, d, z):
        return (u, self.s * d, z) if self.axis == "y" else (self.s * d, u, z)

    def rect(self, d, u0, u1, z0, z1, mat, facing=1):
        if abs(u1 - u0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return
        self.b.pq([self.P(u0, d, z0), self.P(u1, d, z0), self.P(u1, d, z1), self.P(u0, d, z1)], self.N(0, facing, 0), mat)

    def uface(self, u, d0, d1, z0, z1, mat, facing=1):
        if abs(d1 - d0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return
        self.b.pq([self.P(u, d0, z0), self.P(u, d1, z0), self.P(u, d1, z1), self.P(u, d0, z1)], self.N(facing, 0, 0), mat)

    def zface(self, z, u0, u1, d0, d1, mat, facing=1):
        if abs(d1 - d0) < 1e-6 or abs(u1 - u0) < 1e-6:
            return
        self.b.pq([self.P(u0, d0, z), self.P(u1, d0, z), self.P(u1, d1, z), self.P(u0, d1, z)], self.N(0, 0, facing), mat)

    def box(self, u0, u1, d0, d1, z0, z1, mat, skip=""):
        sk = skip.split()
        u0, u1 = sorted((u0, u1))
        d0, d1 = sorted((d0, d1))
        z0, z1 = sorted((z0, z1))
        if "+u" not in sk: self.uface(u1, d0, d1, z0, z1, mat, 1)
        if "-u" not in sk: self.uface(u0, d0, d1, z0, z1, mat, -1)
        if "+d" not in sk: self.rect(d1, u0, u1, z0, z1, mat, 1)
        if "-d" not in sk: self.rect(d0, u0, u1, z0, z1, mat, -1)
        if "+z" not in sk: self.zface(z1, u0, u1, d0, d1, mat, 1)
        if "-z" not in sk: self.zface(z0, u0, u1, d0, d1, mat, -1)

    def wall(self, u0, u1, z0, z1, holes, mat):
        for r in rects_with_holes(u0, u1, z0, z1, holes):
            self.rect(0, r[0], r[1], r[2], r[3], mat, 1)

    def window(self, h, depth=0.15, wmat="WallA", frame=True, cross=0, sill=True, lintel=False, shutters=None,
               glass="Window", sillmat="Concrete", bar=True, reveal="lrtb"):
        u0, u1, z0, z1 = h
        if "l" in reveal: self.uface(u0, -depth, 0, z0, z1, wmat, 1)
        if "r" in reveal: self.uface(u1, -depth, 0, z0, z1, wmat, -1)
        if "b" in reveal: self.zface(z0, u0, u1, -depth, 0, wmat, 1)
        if "t" in reveal: self.zface(z1, u0, u1, -depth, 0, wmat, -1)
        self.rect(-depth, u0, u1, z0, z1, glass, 1)
        if frame:
            f, yb = 0.05, -depth
            self.box(u0, u1, yb, yb + 0.04, z1 - f, z1, "Trim", "-d -u +u +z")
            self.box(u0, u1, yb, yb + 0.04, z0, z0 + f, "Trim", "-d -u +u -z")
            self.box(u0, u0 + f, yb, yb + 0.04, z0 + f, z1 - f, "Trim", "-d -u -z +z")
            self.box(u1 - f, u1, yb, yb + 0.04, z0 + f, z1 - f, "Trim", "-d +u -z +z")
            for k in range(cross):
                um = u0 + (u1 - u0) * (k + 1) / (cross + 1)
                self.box(um - 0.025, um + 0.025, yb, yb + 0.04, z0 + f, z1 - f, "Trim", "-d -z +z")
            if bar and (z1 - z0) > 1.0:
                zm = z0 + (z1 - z0) * 0.6
                self.box(u0 + f, u1 - f, yb, yb + 0.04, zm - 0.02, zm + 0.02, "Trim", "-d -u +u")
        if sill:
            self.box(u0 - 0.08, u1 + 0.08, 0, 0.12, z0 - 0.07, z0, sillmat, "-d -z")
        if lintel:
            self.box(u0 - 0.1, u1 + 0.1, 0, 0.08, z1, z1 + 0.12, "WallD", "-d -z")
        if shutters:
            for (a, c) in ((u0 - 0.5, u0 - 0.1), (u1 + 0.1, u1 + 0.5)):
                self.box(a, c, 0, 0.04, z0 - 0.04, z1 + 0.04, shutters, "-d -z +z")
                for k in (0.3, 0.55, 0.8):
                    zz = z0 + (z1 - z0) * k
                    self.rect(0.045, a + 0.03, c - 0.03, zz, zz + 0.025, "Trim", 1)

    def door(self, h, depth=0.24, wmat="WallA", leaf="WallC", glassy=True, step=True, hmat="Metal"):
        u0, u1, z0, z1 = h
        self.uface(u0, -depth, 0, z0, z1, wmat, 1)
        self.uface(u1, -depth, 0, z0, z1, wmat, -1)
        self.zface(z1, u0, u1, -depth, 0, wmat, -1)
        self.rect(-depth, u0, u1, z0, z1, leaf, 1)
        um = (u0 + u1) / 2
        w = (u1 - u0)
        if glassy:
            self.rect(-depth + 0.01, um - w * 0.28, um + w * 0.28, z0 + 1.15, z1 - 0.3, "Window", 1)
            f = 0.04
            self.rect(-depth + 0.014, um - w * 0.28 - f, um + w * 0.28 + f, z1 - 0.3, z1 - 0.3 + f, "Trim", 1)
            self.rect(-depth + 0.014, um - w * 0.28 - f, um + w * 0.28 + f, z0 + 1.15 - f, z0 + 1.15, "Trim", 1)
        self.box(u1 - 0.18, u1 - 0.14, -depth, -depth + 0.1, z0 + 0.95, z0 + 1.1, hmat, "-d")
        self.box(u0 - 0.1, u1 + 0.1, 0, 0.08, z1, z1 + 0.12, "WallD", "-d -z")
        for (a, c) in ((u0 - 0.1, u0), (u1, u1 + 0.1)):
            self.box(a, c, 0, 0.06, z0, z1, "WallD", "-d -z +z")


def gable_x(b, x0, x1, hy, ov, z0, apex, caps_mat="WallA", roof="RoofTile", soffit="WallD", caps=(True, True)):
    """Gable roof, ridge along X, eave overhang `ov` along y, gable ends flush at x0/x1."""
    b.ex([(-hy - ov, z0), (hy + ov, z0), (0.0, apex)], x0, x1, caps_mat, mats={0: soffit, 1: roof, 2: roof}, caps=caps)


def gable_y(b, y0, y1, hx, ov, z0, apex, caps_mat="WallA", roof="RoofTile", soffit="WallD", caps=(True, True), xc=0.0):
    b.ey([(xc - hx - ov, z0), (xc + hx + ov, z0), (xc, apex)], y0, y1, caps_mat, mats={0: soffit, 1: roof, 2: roof}, caps=caps)


def hip_roof(b, cx, cy, W, D, ov, z0, z1, mat="RoofTile"):
    Wb, Db = W + 2 * ov, D + 2 * ov
    if Wb >= Db:
        top = (Wb - Db + 0.1, 0.1)
    else:
        top = (0.1, Db - Wb + 0.1)
    b.blockk((cx, cy), z0, z1, (Wb, Db), top, mat)


def chimney(b, x, y, z0, z1, w=0.7, d=0.7, mat="WallB"):
    b.blockk((x, y), z0, z1, (w, d), (w - 0.06, d - 0.06), mat)
    b.abox(x - w / 2 - 0.07, x + w / 2 + 0.07, y - d / 2 - 0.07, y + d / 2 + 0.07, z1, z1 + 0.14, "WallD", "-z")
    b.cylk((x, y, z1 + 0.36), 0.16, 0.45, 6, "MetalDark", axis="Z", r_top=0.13)


def mirror_new(b, before, matmap=None):
    """Mirror every face created since `before` (a set of faces) across x=0 (winding reversed), optionally remapping materials."""
    new = [f for f in b.bm.faces if f not in before]
    mats = b.mats
    for f in new:
        vs = [b.v((-v.co.x, v.co.y, v.co.z)) for v in f.verts]
        vs.reverse()
        mname = mats[f.material_index]
        if matmap and mname in matmap:
            mname = matmap[mname]
        b.face(vs, mname)


def make_house(hid, idx, fn, door_loc, smooth=None, extra_empties=()):
    """Create bld_xxx root + Body mesh + Door empty (+ extras), return root. fn(b) builds into the KB."""
    pre = hid + "__"
    clear_asset(pre)
    cl = coll(COLL_BUILDINGS)
    root = empty(pre + "root", loc=workshop(L6, idx, 100.0), collection=cl)
    b = KB(pre + "Body")
    fn(b)
    body = b.finish_k(cl, pre + "Body", loc=(0, 0, 0), parent=root, smooth=smooth)
    empty(pre + "Door", loc=door_loc, parent=root, collection=cl, display="ARROWS", size=0.5)
    for (n, loc) in extra_empties:
        empty(pre + n, loc=loc, parent=root, collection=cl, display="ARROWS", size=0.5)
    return root, body
