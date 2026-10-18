"""
roadgeo.py - pure-numpy road geometry core for "Roamline: Open Roads" (agent R 'road-meshes').

NO bpy import here: this module only turns Tools/world/out/roads.json into triangle arrays, so it can be unit-tested with the plain
interpreter ("W:\\Blender\\5.2\\python\\bin\\python.exe" -I) and executed unchanged inside the Blender MCP session by build_roads.py.

Conventions (binding, see Docs/Tech/ROADS_PIPELINE.md)
  * roads.json is in UE metres: X north, Y east.  All geometry produced here is in BLENDER metres: (x, y, z) = (X_ue, -Y_ue, Z).
  * Road frame at arc length s: centre C(s), unit tangent T = (tx, ty) = (cos h, -sin h) (h = compass heading of roads.json),
    right vector R = (ty, -tx) (right of the direction of travel, seen from above), lateral offset d > 0 = right.
    Surface height at lateral offset d:  z(s, d) = z_c(s) - d * tan(bank) + h_profile(d)      (bank > 0: right edge lower)
    The terrain bed of the world builder is z_c - 0.05 - d*tan(bank) inside the bed half width, so every profile keeps
    h_profile >= -0.022 on top surfaces (>= 2.8 cm above the carved bed, no z-fighting) and h_profile = 0 on the centre line.
  * Triangles are counter-clockwise seen from OUTSIDE (Blender convention); top surfaces face +Z.
  * UV channels written for every chunk (names UV0..UV3 in Blender, TexCoord 0..3 in UE):
      UV0 = (u, v)  u = lateral position over the whole mesh width 0..1,  v = s / 10  (s in metres along the road)
      UV1 = (d, s)  lateral metres from the centre line (right = +) and arc length s in metres  -> markings from an atlas
      UV2 = (paved half width, lane width) in metres  (0, lane width for junction pads: draw NO lane markings)
      UV3 = (median width in metres, zone)  zone: 1.0 carriageway, 0.66 shoulder, 0.5 curb/pavement, 0.33 barrier/parapet, 0 skirt
    Structures (piers, pylons, cables ...) use metric box-projected UV0 = UV1 = (metres, metres), UV2 = (0,0), UV3 = (0, 0.33).
"""
import json
import math
import os

import numpy as np

# ----------------------------------------------------------------------------------------------------------------------
# materials (names are the UE-side match keys)
MATS = ["M_Road_Asphalt", "M_Road_Concrete", "M_Road_Dirt", "M_Road_Gravel", "M_Curb", "M_Bridge_Concrete",
        "M_Bridge_Steel", "M_Tunnel_Wall", "M_Tunnel_Light", "M_Road_Marking"]
ASPH, CONC, DIRT, GRAV, CURB, BCON, BSTL, TWAL, TLIT, MARK = range(10)

SLAB_T = 0.30          # thickness of the road slab below the surface (Lumen light-leak proofing)
BEVEL = 0.30           # outward + downward bevel of the slab edge ("skirt" that dips under the terrain)
CROWN = {"HIGHWAY": 0.016}         # total cross fall of the carriageway (m); the terrain bed is 5 cm below the centre line,
CROWN_DEFAULT = 0.012              # so the whole top surface stays >= 2 cm above it (heightmap quantum is 2.3 cm)
SHOULDER_FALL = 0.006
FLAG_BRIDGE, FLAG_TUNNEL, FLAG_CULVERT, FLAG_JUNCTION, FLAG_HAIRPIN, FLAG_PORTAL = 1, 2, 4, 8, 16, 32

CHUNK_TARGET = 360.0   # target road length of a surface chunk (metres)
CHUNK_MAX = 420.0


# ----------------------------------------------------------------------------------------------------------------------
# mesh accumulation
class MB:
    """Mesh builder: concatenates vertex/triangle blocks.  Everything in Blender world metres."""

    def __init__(self):
        self.V, self.F, self.M, self.U = [], [], [], [[], [], [], []]
        self.n = 0

    def add(self, V, F, mat, uv0=None, uv1=None, uv2=None, uv3=None):
        V = np.asarray(V, float).reshape(-1, 3)
        F = np.asarray(F, np.int64).reshape(-1, 3)
        n = len(V)
        if len(F) == 0 or n == 0:
            return self.n
        m = np.broadcast_to(np.asarray(mat, np.int16), (len(F),)).copy()
        self.V.append(V)
        self.F.append(F + self.n)
        self.M.append(m)
        for k, u in enumerate((uv0, uv1, uv2, uv3)):
            if u is None:
                u = np.zeros((n, 2))
            u = np.asarray(u, float)
            if u.ndim == 1:
                u = np.broadcast_to(u, (n, 2))
            self.U[k].append(np.array(u.reshape(-1, 2)))
        off = self.n
        self.n += n
        return off

    def finish(self):
        if not self.V:
            return None
        return dict(V=np.concatenate(self.V), F=np.concatenate(self.F), M=np.concatenate(self.M),
                    UV=[np.concatenate(u) for u in self.U])


class Soup:
    """Quad/tri soup for structures (flat shaded, metric UVs). Collects into an MB at the end."""

    def __init__(self):
        self.V, self.F, self.M, self.U1 = [], [], [], []
        self.n = 0

    def tri(self, p0, p1, p2, mat, hint=None):
        p0, p1, p2 = np.asarray(p0, float), np.asarray(p1, float), np.asarray(p2, float)
        nrm = np.cross(p1 - p0, p2 - p0)
        if hint is not None and np.dot(nrm, hint) < 0:
            p1, p2 = p2, p1
            nrm = -nrm
        ln = np.linalg.norm(nrm)
        if ln < 1e-12:
            return
        # metric box projection: pick the dominant axis of the normal
        nn = nrm / ln
        a = np.argmax(np.abs(nn))
        ax = [1, 2] if a == 0 else ([0, 2] if a == 1 else [0, 1])
        i = self.n
        self.V.extend([p0, p1, p2])
        self.U1.extend([(p[ax[0]], p[ax[1]]) for p in (p0, p1, p2)])
        self.F.append((i, i + 1, i + 2))
        self.M.append(mat)
        self.n += 3

    def quad(self, p0, p1, p2, p3, mat, hint=None):
        """Quad p0 p1 p2 p3 (as a loop); outward direction `hint` (3,) flips the winding if needed."""
        p0, p1, p2, p3 = (np.asarray(p, float) for p in (p0, p1, p2, p3))
        nrm = np.cross(p2 - p0, p3 - p1)
        if hint is not None and np.dot(nrm, hint) < 0:
            p0, p1, p2, p3 = p3, p2, p1, p0
        # split along the shorter diagonal
        if np.linalg.norm(p2 - p0) <= np.linalg.norm(p3 - p1):
            self.tri(p0, p1, p2, mat)
            self.tri(p0, p2, p3, mat)
        else:
            self.tri(p0, p1, p3, mat)
            self.tri(p1, p2, p3, mat)

    def fan(self, pts, mat, hint=None):
        """Convex polygon fan."""
        pts = [np.asarray(p, float) for p in pts]
        for k in range(1, len(pts) - 1):
            self.tri(pts[0], pts[k], pts[k + 1], mat, hint)

    def poly(self, pts3, mat, hint=None, basis=None):
        """Possibly concave planar polygon via ear clipping in the plane given by two basis vectors (u,v)."""
        pts3 = [np.asarray(p, float) for p in pts3]
        if basis is None:
            nrm = np.zeros(3)
            for i in range(len(pts3)):
                nrm += np.cross(pts3[i], pts3[(i + 1) % len(pts3)])
            nrm /= (np.linalg.norm(nrm) + 1e-12)
            bu = np.cross(nrm, [0.3, 0.5, 0.8])
            bu /= np.linalg.norm(bu)
            bv = np.cross(nrm, bu)
        else:
            bu, bv = basis
        P2 = [(float(np.dot(p, bu)), float(np.dot(p, bv))) for p in pts3]
        for (a, b, c) in ear_clip(P2):
            self.tri(pts3[a], pts3[b], pts3[c], mat, hint)

    def into(self, mb, uv_scale=1.0):
        if not self.F:
            return
        V = np.array(self.V)
        U1 = np.array(self.U1)
        n = len(V)
        mb.add(V, np.array(self.F), np.array(self.M, np.int16), uv0=U1 / 4.0, uv1=U1, uv2=np.zeros((n, 2)),
               uv3=np.tile([0.0, 0.33], (n, 1)))


# ----------------------------------------------------------------------------------------------------------------------
def ear_clip(P):
    """Ear clipping of a simple polygon P (list of (x, y)); returns index triples with the SAME orientation as the input."""
    n = len(P)
    if n < 3:
        return []
    area = 0.0
    for i in range(n):
        x0, y0 = P[i]
        x1, y1 = P[(i + 1) % n]
        area += x0 * y1 - x1 * y0
    sgn = 1.0 if area >= 0 else -1.0
    idx = list(range(n))
    tris = []

    def cross(a, b, c):
        return ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) * sgn

    def inside(p, a, b, c):
        c1, c2, c3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
        return c1 >= -1e-12 and c2 >= -1e-12 and c3 >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 20000:
        guard += 1
        m = len(idx)
        found = False
        best = None
        for k in range(m):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, b, c = P[i0], P[i1], P[i2]
            cr = cross(a, b, c)
            if best is None or abs(cr) < best[0]:
                best = (abs(cr), k)
            if cr <= 1e-10:
                continue
            ok = True
            for q in idx:
                if q == i0 or q == i1 or q == i2:
                    continue
                pq = P[q]
                if (abs(pq[0] - a[0]) < 1e-12 and abs(pq[1] - a[1]) < 1e-12) or \
                        (abs(pq[0] - b[0]) < 1e-12 and abs(pq[1] - b[1]) < 1e-12) or \
                        (abs(pq[0] - c[0]) < 1e-12 and abs(pq[1] - c[1]) < 1e-12):
                    continue
                if inside(pq, a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(k)
                found = True
                break
        if not found:
            idx.pop(best[1])   # degenerate sliver: drop the flattest vertex
    if len(idx) == 3:
        a, b, c = P[idx[0]], P[idx[1]], P[idx[2]]
        if abs(cross(a, b, c)) > 1e-12:
            tris.append((idx[0], idx[1], idx[2]))
    return tris


# ----------------------------------------------------------------------------------------------------------------------
class Heightmap:
    """Final carved terrain (Content/Forza/World/Source/heightmap_4033.r16), sampled in UE metres."""

    def __init__(self, path):
        self.H = np.memmap(path, dtype="<u2", mode="r", shape=(4033, 4033))

    def z_ue(self, xu, yu):
        xu = np.asarray(xu, float)
        yu = np.asarray(yu, float)
        i = np.clip(xu + 2016.0, 0, 4031.999)
        j = np.clip(yu + 2016.0, 0, 4031.999)
        i0 = np.floor(i).astype(int)
        j0 = np.floor(j).astype(int)
        fi, fj = i - i0, j - j0
        H = self.H

        def g(a, b):
            return (np.asarray(H[b, a], float) - 32768.0) * 300.0 / 128.0 / 100.0
        return (g(i0, j0) * (1 - fi) * (1 - fj) + g(i0 + 1, j0) * fi * (1 - fj) +
                g(i0, j0 + 1) * (1 - fi) * fj + g(i0 + 1, j0 + 1) * fi * fj)

    def z_bl(self, x, y):
        """Blender coordinates (x, y) -> terrain height."""
        return self.z_ue(x, -np.asarray(y, float))


# ----------------------------------------------------------------------------------------------------------------------
def _crown(road, ad):
    """Vertical offset (<= 0) of the top surface w.r.t. the banked plane at |lateral| = ad (carriageway cross fall + shoulder fall)."""
    P = road.P
    m2 = road.med / 2.0
    amp = CROWN.get(road.cls, CROWN_DEFAULT)
    t = np.clip((ad - m2) / max(P - m2, 1e-6), 0.0, 1.0)
    lane = -amp * (t if road.med > 0 else t * t)
    sh = -SHOULDER_FALL * np.clip((ad - P) / max(road.sh, 1e-6), 0.0, 1.0)
    return lane + sh


class Road:
    def __init__(self, rd):
        self.rd = rd
        self.id = rd["id"]
        self.cls = rd["class"]
        self.lw = float(rd["lane_width"])
        self.sh = float(rd["shoulder_width"])
        self.med = float(rd["median_width"])
        self.P = float(rd["paved_width"]) / 2.0
        self.B = self.P + self.sh
        self.surface = rd["surface"]
        S = np.asarray(rd["samples"], float)
        self.s = S[:, 0]
        self.x = S[:, 1].copy()
        self.y = -S[:, 2]
        self.z = S[:, 3].copy()
        h = np.radians(S[:, 4])
        self.tx = np.cos(h)
        self.ty = -np.sin(h)
        self.k = S[:, 5]
        self.bank = np.radians(S[:, 6])
        self.flags = S[:, 8].astype(int)
        self.L = float(self.s[-1])
        self.trims = []          # [(a, b, junction id)] removed intervals (junction pads)
        self._prof = None
        self._base = None

    # ---- frames --------------------------------------------------------------------------------------------------
    def at(self, s):
        s = np.atleast_1d(np.asarray(s, float))
        s = np.clip(s, 0.0, self.L)
        o = dict(s=s)
        o["x"] = np.interp(s, self.s, self.x)
        o["y"] = np.interp(s, self.s, self.y)
        o["z"] = np.interp(s, self.s, self.z)
        o["bank"] = np.interp(s, self.s, self.bank)
        tx = np.interp(s, self.s, self.tx)
        ty = np.interp(s, self.s, self.ty)
        ln = np.hypot(tx, ty)
        o["tx"], o["ty"] = tx / ln, ty / ln
        o["k"] = np.interp(s, self.s, self.k)
        return o

    def base_stations(self):
        """Curvature-adaptive station list (2 m in curves / hairpins / junction zones, 4 m on straights)."""
        n = len(self.s)
        fine = (np.abs(self.k) > 0.0040) | ((self.flags & (FLAG_HAIRPIN | FLAG_JUNCTION | FLAG_PORTAL)) != 0)
        fine = fine | np.roll(fine, 1) | np.roll(fine, -1)
        # never skip a sample whose height / bank is not reproduced (< 4 mm / 0.02 deg) by the chord of its neighbours
        zdev = np.zeros(n)
        zdev[1:-1] = np.abs(self.z[1:-1] - 0.5 * (self.z[:-2] + self.z[2:]))
        bdev = np.zeros(n)
        bdev[1:-1] = np.abs(self.bank[1:-1] - 0.5 * (self.bank[:-2] + self.bank[2:]))
        fine = fine | (zdev > 0.004) | (bdev > math.radians(0.02))
        self._fine = fine
        out = [0]
        i = 0
        while i < n - 1:
            if i + 2 <= n - 1 and not fine[i:i + 3].any():
                i += 2
            else:
                i += 1
            out.append(i)
        return self.s[np.array(out)]

    def stations(self, a, b, extra=(), step=None):
        """Station s values covering [a, b] (a and b always included).  step=None: the curvature-adaptive list of the road (2 / 4 m);
        step=x: a uniform grid of at most x metres PLUS every 2 m sample where the road bends or its height / bank is not
        reproduced by a longer chord (so the mesh passes through the data and stays within ~4 mm of it); `extra` are forced stations."""
        if self._base is None:
            self._base = self.base_stations()
        forced = [e for e in extra if a + 0.3 < e < b - 0.3]
        if step is None:
            base = self._base
            st = base[(base > a + 0.4) & (base < b - 0.4)]
        else:
            nseg = max(1, int(math.ceil((b - a) / step)))
            uni = np.linspace(a, b, nseg + 1)[1:-1]
            fs = self.s[self._fine & (self.s > a + 0.3) & (self.s < b - 0.3)]
            forced = list(forced) + fs.tolist()
            if forced:
                fa = np.array(forced)
                uni = uni[np.min(np.abs(uni[:, None] - fa[None, :]), axis=1) > 0.9] if len(uni) else uni
            st = uni
        allst = np.unique(np.round(np.concatenate([[a], st, np.array(forced, float), [b]]), 6))
        keep = [allst[0]]
        for v in allst[1:-1]:
            if v - keep[-1] > 0.3 and b - v > 0.3:
                keep.append(v)
        keep.append(allst[-1])
        return np.array(keep)

    # ---- top-surface profile -------------------------------------------------------------------------------------
    def profile(self):
        if self._prof is None:
            self._prof = surface_profile(self)
        return self._prof

    def carriage_points(self):
        """(d, h) of the drivable top-surface points (carriageway + shoulders / pavements, no barrier, no bevel), ascending d.
        These are the vertices a junction pad shares with the end cross-section of an arm."""
        pr = self.profile()
        d, h, z = pr["d"], pr["h"], pr["zone"]
        m = (z >= 0.5) & (np.abs(d) <= self.B + 1e-6)
        idx = np.where(m)[0]
        order = idx[np.argsort(d[idx], kind="stable")]
        return d[order], h[order]

    def surface_z(self, s, d):
        """Analytic surface height at (s, lateral d) for the top profile of this road (validation helper)."""
        fr = self.at(s)
        ad = np.abs(d)
        hh = _crown(self, ad)
        return fr["z"] - d * np.tan(fr["bank"]) + hh


def surface_profile(road):
    """Closed cross-section loop (CW in (d,h)): top surface left->right, bevel, bottom.  Returns dict of arrays."""
    cls, P, B, S, med, lw = road.cls, road.P, road.B, road.sh, road.med, road.lw
    e = BEVEL
    f = lambda ad: float(_crown(road, ad))
    carr = {"asphalt": ASPH, "gravel": GRAV, "dirt": DIRT}[road.surface]
    if cls == "HIGHWAY":
        m2 = med / 2.0
        E = [(B + e, f(B) - e, 0.0, True), (B, f(B), 0.66, True), (P, f(P), 1.0, False),
             (m2 + lw, f(m2 + lw), 1.0, False), (m2, 0.0, 1.0, True), (0.30, 0.0, 0.33, True),
             (0.27, 0.10, 0.33, False), (0.14, 0.50, 0.33, False), (0.085, 0.80, 0.33, True)]
        seg = [ASPH, ASPH, ASPH, ASPH, CONC, CONC, CONC, CONC]
        center_mat, bottom_mat = CONC, ASPH
    elif cls == "REGIONAL":
        E = [(B + e, f(B) - e, 0.0, True), (B, f(B), 0.66, True), (P + 0.30, f(P + 0.30), 0.5, False),
             (P, f(P), 1.0, False), (P / 2, f(P / 2), 1.0, False), (0.0, 0.0, 1.0, False)]
        seg = [DIRT, GRAV, CURB, carr, carr]
        center_mat, bottom_mat = None, DIRT
    elif cls == "MOUNTAIN":
        E = [(B + e, f(B) - e, 0.0, True), (B, f(B), 0.66, True), (P, f(P), 1.0, False),
             (P / 2, f(P / 2), 1.0, False), (0.0, 0.0, 1.0, False)]
        seg = [DIRT, GRAV, carr, carr]
        center_mat, bottom_mat = None, DIRT
    elif cls == "VILLAGE":
        H = 0.12
        E = [(B + 0.45, H - 0.45 - 0.0, 0.0, True), (B, H, 0.5, True), (P + 0.15, H, 0.5, True), (P, H, 0.5, True),
             (P, f(P), 1.0, True), (P / 2, f(P / 2), 1.0, False), (0.0, 0.0, 1.0, False)]
        E[0] = (B + 0.45, -0.33, 0.0, True)
        seg = [CONC, CONC, CURB, CURB, carr, carr]
        center_mat, bottom_mat = None, CONC
    else:  # DIRT, SHORTCUT
        sh_mat = DIRT
        E = [(B + e, f(B) - e, 0.0, True), (B, f(B), 0.66, True), (P, f(P), 1.0, False),
             (P / 2, f(P / 2), 1.0, False), (0.0, 0.0, 1.0, False)]
        seg = [DIRT, sh_mat, carr, carr]
        center_mat, bottom_mat = None, DIRT
    E, seg = _subdivide(road, E, seg)
    return mirror_profile(E, seg, center_mat, bottom_mat)


def _subdivide(road, E, seg, maxlen=1.9):
    """Insert intermediate cross-section points into wide flat top segments (<= maxlen across): smoother crown, even quads."""
    f = lambda ad: float(_crown(road, ad))
    E2, seg2 = [E[0]], []
    for k in range(len(E) - 1):
        (a0, h0, z0, hd0), (a1, h1, z1, hd1) = E[k], E[k + 1]
        flat = z0 >= 0.5 and z1 >= 0.5 and abs(a0 - a1) > maxlen and abs(h0 - f(a0)) < 1e-6 and abs(h1 - f(a1)) < 1e-6             and h0 < 0.2 and h1 < 0.2
        if flat:
            n = int(math.ceil(abs(a0 - a1) / maxlen))
            for q in range(1, n):
                a = a0 + (a1 - a0) * q / n
                E2.append((a, f(a), min(z0, z1), False))
                seg2.append(seg[k])
        seg2.append(seg[k])
        E2.append(E[k + 1])
    return E2, seg2


def mirror_profile(E, seg, center_mat, bottom_mat):
    """E: entries (ad, h, zone, hard) from the outside to the inside; seg[k]: material of the edge E[k]-E[k+1]."""
    m = len(E)
    gap = E[-1][0] > 1e-9
    d, h, zone, hard, mat = [], [], [], [], []
    for k in range(m):                       # left half, outside -> inside
        ad, hh, zn, hd = E[k]
        d.append(-ad); h.append(hh); zone.append(zn); hard.append(hd)
        if k < m - 1:
            mat.append(seg[k])
    start = m - 1 if gap else m - 2
    for k in range(start, -1, -1):           # right half, inside -> outside
        ad, hh, zn, hd = E[k]
        d.append(ad); h.append(hh); zone.append(zn); hard.append(hd)
        if k == start:
            mat.append(center_mat if gap else seg[k])
        else:
            mat.append(seg[k])
    # mats were appended per arriving edge, i.e. mat[j] is the edge leaving point j; the closing edge (last point -> first) is the bottom
    mat.append(bottom_mat)
    n = len(d)
    assert len(mat) == n, (len(mat), n)
    return dict(d=np.array(d), h=np.array(h), zone=np.array(zone), hard=np.array(hard, bool), mat=np.array(mat, np.int16),
                closed=True)


# ----------------------------------------------------------------------------------------------------------------------
def ribbon(mb, fr, prof, par, cap0=False, cap1=False, mat_override=None):
    """Extrude the cross-section `prof` along the stations `fr`.  Returns dict(vid=(n_st, n_ids) vertex index grid, off=offset)."""
    s = fr["s"]
    n = len(s)
    dd = np.asarray(prof["d"], float)
    n_pt = dd.shape[-1]
    hard = np.asarray(prof["hard"], bool)
    closed = prof.get("closed", True)
    in_id = np.zeros(n_pt, np.int64)
    out_id = np.zeros(n_pt, np.int64)
    src = []
    for i in range(n_pt):
        if hard[i]:
            in_id[i] = len(src); src.append(i)
            out_id[i] = len(src); src.append(i)
        else:
            in_id[i] = out_id[i] = len(src); src.append(i)
    src = np.array(src)
    nv = len(src)
    D = np.broadcast_to(dd, (n, n_pt))[:, src]
    Hh = np.broadcast_to(np.asarray(prof["h"], float), (n, n_pt))[:, src]
    rx = fr["ty"][:, None]
    ry = -fr["tx"][:, None]
    X = fr["x"][:, None] + rx * D
    Y = fr["y"][:, None] + ry * D
    Z = fr["z"][:, None] - D * np.tan(fr["bank"])[:, None] + Hh
    V = np.stack([X, Y, Z], -1).reshape(-1, 3)
    n_edge = n_pt if closed else n_pt - 1
    ea = out_id[:n_edge]
    eb = in_id[(np.arange(n_edge) + 1) % n_pt]
    j = np.arange(n - 1) * nv
    A = j[:, None] + ea[None, :]
    Bq = j[:, None] + eb[None, :]
    C = j[:, None] + nv + eb[None, :]
    Dq = j[:, None] + nv + ea[None, :]
    # diagonal along the shorter one
    dac = np.sum((V[A] - V[C]) ** 2, -1)
    dbd = np.sum((V[Bq] - V[Dq]) ** 2, -1)
    use_ac = (dac <= dbd)[..., None]
    t1 = np.where(use_ac, np.stack([A, Bq, C], -1), np.stack([A, Bq, Dq], -1))
    t2 = np.where(use_ac, np.stack([A, C, Dq], -1), np.stack([Bq, C, Dq], -1))
    F = np.stack([t1, t2], 2).reshape(-1, 3)
    mat_e = np.asarray(prof["mat"], np.int16)[:n_edge]
    if mat_override is not None:
        mat_e = np.full(n_edge, mat_override, np.int16)
    M = np.broadcast_to(mat_e[None, :, None], (n - 1, n_edge, 2)).reshape(-1)
    # UVs
    Wt = par.get("Wt", 2.0 * (np.abs(dd).max() + 1e-6))
    u = (D + Wt / 2.0) / Wt
    sv = np.broadcast_to(s[:, None], D.shape)
    uv0 = np.stack([u, sv / 10.0], -1).reshape(-1, 2)
    uv1 = np.stack([D, sv], -1).reshape(-1, 2)
    uv2 = np.tile([par.get("P", 0.0), par.get("lw", 0.0)], (n * nv, 1))
    zone = np.asarray(prof["zone"], float)[src]
    uv3 = np.stack([np.full(D.shape, par.get("med", 0.0)), np.broadcast_to(zone[None, :], D.shape)], -1).reshape(-1, 2)
    off = mb.add(V, F, M, uv0, uv1, uv2, uv3)
    info = dict(off=off, nv=nv, n=n, out_id=out_id, in_id=in_id)
    # end caps (flat)
    if (cap0 or cap1) and closed:
        for flag, jj in ((cap0, 0), (cap1, n - 1)):
            if not flag:
                continue
            dcap = D[jj, out_id]
            hcap = Hh[jj, out_id]
            P2 = list(zip(dcap.tolist(), hcap.tolist()))
            tris = ear_clip(P2)
            if not tris:
                continue
            pos = np.stack([X[jj, out_id], Y[jj, out_id], Z[jj, out_id]], -1)
            T = np.array([[a, b, c] for (a, b, c) in tris])
            if jj == 0:
                T = T[:, [0, 2, 1]]
            capM = int(np.bincount(np.asarray(prof["mat"], np.int16)[:n_edge]).argmax()) if mat_override is None else mat_override
            cuv = np.stack([dcap, hcap], -1)
            mb.add(pos, T, capM, uv0=cuv / 4.0, uv1=cuv, uv2=np.zeros((n_pt, 2)),
                   uv3=np.tile([par.get("med", 0.0), 0.0], (n_pt, 1)))
    return info


# ----------------------------------------------------------------------------------------------------------------------
# network / planning
def load_network(path):
    d = json.load(open(path, "r", encoding="utf8"))
    roads = {r["id"]: Road(r) for r in d["roads"]}
    return d, roads


def _wrap180(a):
    return (a + 180.0) % 360.0 - 180.0


def fillet_radius(cls):
    return {"HIGHWAY": 14.0, "REGIONAL": 8.0, "MOUNTAIN": 7.0, "DIRT": 6.0, "SHORTCUT": 6.0, "VILLAGE": 5.0}.get(cls, 6.0)


def plan_junctions(net, roads):
    """Cluster nodes, derive arms and trim distances.  Fills road.trims.  Returns list of junction dicts (Blender coords)."""
    nodes = net["nodes"]
    clusters = []
    for n in nodes:
        for c in clusters:
            if math.hypot(c["x"] - n["x"], c["y"] - n["y"]) < 6.0:
                c["nodes"].append(n)
                break
        else:
            clusters.append(dict(x=n["x"], y=n["y"], nodes=[n]))
    out = []
    for c in clusters:
        arms = {}
        for n in c["nodes"]:
            for cn in n["connections"]:
                r = roads[cn["road"]]
                s = cn["s"]
                if s < 1.0:
                    dirs = [1]
                elif s > r.L - 1.0:
                    dirs = [-1]
                else:
                    dirs = [1, -1]
                for dd in dirs:
                    key = (cn["road"], dd)
                    if key not in arms:
                        arms[key] = dict(road=cn["road"], dir=dd, s_node=float(min(max(s, 0.0), r.L)), control=cn["control"])
        if len(arms) < 3:
            continue
        named = [n for n in c["nodes"] if n["kind"] == "node"]
        nid = (named[0] if named else c["nodes"][0])["id"]
        zc = float(np.mean([n["z"] for n in c["nodes"]]))
        cx, cy = c["x"], -c["y"]
        A = []
        for a in arms.values():
            r = roads[a["road"]]
            fr = r.at(a["s_node"])
            ax, ay = a["dir"] * fr["tx"][0], a["dir"] * fr["ty"][0]
            a["ax"], a["ay"] = float(ax), float(ay)
            a["phi"] = math.atan2(ay, ax)
            a["P"] = r.P
            a["B"] = r.B
            a["cls"] = r.cls
            A.append(a)
        A.sort(key=lambda q: -q["phi"])        # clockwise seen from above (Blender axes)
        m = len(A)
        trim = [6.0] * m
        for i in range(m):
            j = (i + 1) % m
            th = (A[i]["phi"] - A[j]["phi"]) % (2 * math.pi)       # clockwise angle from arm i to arm j
            if th >= math.radians(172.0) or th < 1e-3:
                continue
            Pi, Pj = A[i]["B"], A[j]["B"]
            Rf = 0.5 * (fillet_radius(A[i]["cls"]) + fillet_radius(A[j]["cls"]))
            xi = Pi / math.tan(th) + Pj / math.sin(th)
            xj = Pj / math.tan(th) + Pi / math.sin(th)
            fil = Rf / math.tan(th / 2.0)
            trim[i] = max(trim[i], xi + fil)
            trim[j] = max(trim[j], xj + fil)
        for i in range(m):
            A[i]["t"] = float(min(max(trim[i], 7.0), 40.0))
        jn = dict(id=nid, nodes=[n["id"] for n in c["nodes"]], x=cx, y=cy, z=zc, arms=A)
        out.append(jn)
        # register trims (merge mid-pass arms)
        for a in A:
            r = roads[a["road"]]
            if a["dir"] == 1:
                r.trims.append([a["s_node"], min(a["s_node"] + a["t"], r.L), nid])
            else:
                r.trims.append([max(a["s_node"] - a["t"], 0.0), a["s_node"], nid])
    for r in roads.values():
        r.trims = merge_intervals(r.trims)
    return out


def merge_intervals(iv):
    iv = sorted([list(x) for x in iv], key=lambda x: x[0])
    out = []
    for a, b, n in iv:
        if out and a <= out[-1][1] + 0.01:
            out[-1][1] = max(out[-1][1], b)
            if n not in out[-1][2]:
                out[-1][2] = out[-1][2] + "+" + n
        else:
            out.append([a, b, n])
    return out


def subtract_intervals(lo, hi, cuts):
    out = []
    a = lo
    for (c0, c1, _) in cuts:
        if c1 <= a:
            continue
        if c0 >= hi:
            break
        if c0 > a:
            out.append((a, min(c0, hi)))
        a = max(a, c1)
    if a < hi:
        out.append((a, hi))
    return out


def effective_tunnel(road, t, hm, thr=0.6):
    """The tunnel run of roads.json starts inside the portal cutting (an open trench).  The head-walls belong at the FOOT of the
    cut face where the hillside starts to rise over the road: first / last station where the terrain stands >= thr m above the
    road on the centre line (heightmap sampled).  The road stays an ordinary road chunk in the trench before that."""
    a, b = float(t["s0"]), float(t["s1"])
    if hm is None:
        return a, b
    ss = np.arange(a, b + 0.01, 1.0)
    fr = road.at(ss)
    z0 = hm.z_bl(fr["x"], fr["y"]) - fr["z"]
    ok = z0 >= thr
    if not ok.any():
        return a, b
    i0 = int(np.argmax(ok))
    i1 = len(ok) - 1 - int(np.argmax(ok[::-1]))
    return float(ss[i0]), float(ss[i1])


def plan_chunks(road, hm=None):
    """Split one road into chunk descriptors: roads between junction trims, bridges, tunnels."""
    rd = road.rd
    kept = subtract_intervals(0.0, road.L, road.trims)
    structs = []
    for b in rd.get("bridges", []):
        structs.append(("bridge", float(b["s0"]), float(b["s1"]), b))
    for t in rd.get("tunnels", []):
        pa, pb = effective_tunnel(road, t, hm)
        t = dict(t, run_s0=t["s0"], run_s1=t["s1"], portal_s0=pa, portal_s1=pb)
        structs.append(("tunnel", pa, pb, t))
    structs.sort(key=lambda x: x[1])
    pieces = []
    for (a, b) in kept:
        if b - a < 3.0:
            continue
        cur = a
        for kind, s0, s1, meta in structs:
            if s1 <= cur or s0 >= b:
                continue
            s0c, s1c = max(s0, a), min(s1, b)
            if s0c > cur + 0.5:
                pieces.append(dict(kind="road", s0=cur, s1=s0c, cap0=(cur == a), cap1=False))
            nparts = max(1, int(math.ceil((s1c - s0c) / 230.0))) if kind == "bridge" else 1
            edges_ = np.linspace(s0c, s1c, nparts + 1)
            for q in range(nparts):
                pieces.append(dict(kind=kind, s0=float(edges_[q]), s1=float(edges_[q + 1]), cap0=False, cap1=False, meta=meta,
                                   part=q, nparts=nparts))
            cur = s1c
        if b > cur + 0.5:
            pieces.append(dict(kind="road", s0=cur, s1=b, cap0=(cur == a), cap1=True))
        elif pieces and pieces[-1]["kind"] != "road":
            pass
        # road piece after a structure which touches the kept end: nothing
    # split long road pieces
    out = []
    for p in pieces:
        if p["kind"] != "road":
            out.append(p)
            continue
        L = p["s1"] - p["s0"]
        n = max(1, int(round(L / CHUNK_TARGET)))
        if L / n > CHUNK_MAX:
            n += 1
        edges = np.linspace(p["s0"], p["s1"], n + 1)
        for i in range(n):
            out.append(dict(kind="road", s0=float(edges[i]), s1=float(edges[i + 1]),
                            cap0=(p["cap0"] if i == 0 else False), cap1=(p["cap1"] if i == n - 1 else False)))
    return out


# ----------------------------------------------------------------------------------------------------------------------
def build_road_chunk(road, s0, s1, cap0, cap1):
    """Plain surface chunk (slab, shoulders, curbs, median barrier, bevel skirt)."""
    st = road.stations(s0, s1)
    fr = road.at(st)
    prof = road.profile()
    par = dict(P=road.P, lw=road.lw, med=road.med, Wt=2.0 * (road.B + BEVEL))
    mb = MB()
    ribbon(mb, fr, prof, par, cap0, cap1)
    return mb


# ----------------------------------------------------------------------------------------------------------------------
# junction pads
PAD_BEVEL = 0.6


def _arm_geometry(jn, roads):
    """Arm end cross-sections (left -> right, looking away from the node) + the arm's actual away direction."""
    for a in jn["arms"]:
        r = roads[a["road"]]
        s_end = min(max(a["s_node"] + a["dir"] * a["t"], 0.0), r.L)
        a["s_end"] = s_end
        fr = r.at(s_end)
        d, h = r.carriage_points()
        if a["dir"] == -1:
            d, h = d[::-1], h[::-1]
        rx, ry = fr["ty"][0], -fr["tx"][0]
        x = fr["x"][0] + rx * d
        y = fr["y"][0] + ry * d
        z = fr["z"][0] - d * np.tan(fr["bank"][0]) + h
        a["pts"] = np.stack([x, y, z], -1)
        a["dx"], a["dy"] = a["dir"] * float(fr["tx"][0]), a["dir"] * float(fr["ty"][0])


PAD_LIFT = 0.07          # pad surface stays at least 7 cm above the carved terrain wherever the terrain would bury it


def _smax(a, b, k=0.08):
    """Smooth maximum (no crease where the terrain crosses the fan)."""
    return 0.5 * (a + b + np.sqrt((a - b) ** 2 + k * k)) - 0.5 * k


def build_junction(jn, roads, mat_pad=ASPH, hm=None):
    """Pad polygon (arm end edges + smooth Bezier corners) tessellated as a polar grid from the node centre, draped over the
    terrain in the corners; slab bottom, skirt, stop lines."""
    _arm_geometry(jn, roads)
    A = jn["arms"]
    m = len(A)
    C = np.array([jn["x"], jn["y"], jn["z"]])
    pts, kinds = [], []                 # kinds[k]: kind of the edge pts[k] -> pts[k+1]  ('arm' | 'curve')
    for i in range(m):
        ai, aj = A[i], A[(i + 1) % m]
        P_arm = ai["pts"]
        for k in range(len(P_arm)):
            pts.append(P_arm[k])
            kinds.append("arm" if k < len(P_arm) - 1 else "curve")
        # corner from the right end of arm i to the left end of arm j (cubic Bezier tangent to both arm edges)
        p0, p3 = ai["pts"][-1], aj["pts"][0]
        ch = math.hypot(p3[0] - p0[0], p3[1] - p0[1])
        ui = np.array([ai["dx"], ai["dy"]])
        uj = np.array([aj["dx"], aj["dy"]])
        cosphi = float(np.clip(np.dot(-ui, uj), -1, 1))
        phi = math.acos(cosphi)
        if phi < 0.05:
            kk = ch / 3.0
        else:
            reff = ch / (2.0 * math.sin(phi / 2.0))
            kk = min(4.0 / 3.0 * math.tan(phi / 4.0) * reff, 0.7 * ch)
        p1 = np.array([p0[0] - ui[0] * kk, p0[1] - ui[1] * kk])
        p2 = np.array([p3[0] - uj[0] * kk, p3[1] - uj[1] * kk])
        nseg = max(5, int(ch / 2.0) + 3)
        for q in range(1, nseg):
            t = q / nseg
            b = ((1 - t) ** 3) * p0[:2] + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + (t ** 3) * p3[:2]
            z = p0[2] + (p3[2] - p0[2]) * (t * t * (3 - 2 * t))
            pts.append(np.array([b[0], b[1], z]))
            kinds.append("curve")
    pts = np.array(pts)
    N = len(pts)
    assert len(kinds) == N, (len(kinds), N)
    # orientation of the boundary in plan (clockwise expected)
    area = 0.0
    for k in range(N):
        x0, y0 = pts[k][:2]
        x1, y1 = pts[(k + 1) % N][:2]
        area += x0 * y1 - x1 * y0
    cw = area < 0
    # outward directions on curve vertices (bevel fades to a vertical drop where the pad meets an arm)
    out = np.zeros((N, 2))
    for k in range(N):
        kp, kn = (k - 1) % N, (k + 1) % N
        if kinds[kp] == "curve" and kinds[k] == "curve":
            e = pts[kn][:2] - pts[kp][:2]
            nrm = np.array([-e[1], e[0]]) if cw else np.array([e[1], -e[0]])
            ln = np.linalg.norm(nrm)
            if ln > 1e-9:
                out[k] = nrm / ln
    # --- drape the corner fillets over the carved terrain: the pad must never be buried (the world builder blends the carved
    #     beds of the arms with the natural terrain, up to ~1.5 m of deviation in the corners between the arms)
    if hm is not None:
        curve_v = np.array([kinds[(k - 1) % N] == "curve" and kinds[k] == "curve" for k in range(N)])
        zt = hm.z_bl(pts[:, 0], pts[:, 1]) + PAD_LIFT
        pts[curve_v, 2] = _smax(pts[curve_v, 2], zt[curve_v])
    top = pts.copy()
    bot = pts.copy()
    bot[:, 0] += out[:, 0] * PAD_BEVEL
    bot[:, 1] += out[:, 1] * PAD_BEVEL
    bot[:, 2] -= PAD_BEVEL
    mb = MB()
    # --- top surface: polar grid (centre + K rings towards the boundary), z = fan height soft-maxed with the terrain
    rad = np.hypot(pts[:, 0] - C[0], pts[:, 1] - C[1])
    K = max(3, int(math.ceil(float(rad.max()) / 2.5)))
    ks = np.arange(1, K + 1) / float(K)
    X = C[0] + (pts[None, :, 0] - C[0]) * ks[:, None]
    Y = C[1] + (pts[None, :, 1] - C[1]) * ks[:, None]
    Zf = C[2] + (pts[None, :, 2] - C[2]) * ks[:, None]
    Z = Zf.copy()
    if hm is not None:
        Zt = hm.z_bl(X, Y) + PAD_LIFT
        Z[:-1] = _smax(Zf[:-1], Zt[:-1])             # the boundary ring keeps the arm / fillet heights
    Vt = np.vstack([C[None, :], np.stack([X.ravel(), Y.ravel(), Z.ravel()], -1)])
    nverts = len(Vt)
    tri = []
    for j in range(N):
        tri.append((0, 1 + (j + 1) % N, 1 + j))
    jj = np.arange(N)
    for k in range(K - 1):
        a = 1 + k * N + jj
        b = 1 + k * N + (jj + 1) % N
        c = 1 + (k + 1) * N + (jj + 1) % N
        d = 1 + (k + 1) * N + jj
        tri.extend(zip(a, c, b))
        tri.extend(zip(a, d, c))
    tri = np.array(tri)
    nz = np.cross(Vt[tri[:, 1]] - Vt[tri[:, 0]], Vt[tri[:, 2]] - Vt[tri[:, 0]])[:, 2]
    tri[nz < 0] = tri[nz < 0][:, [0, 2, 1]]
    uvp = Vt[:, :2]
    mb.add(Vt, tri, mat_pad, uv0=uvp / 10.0, uv1=uvp, uv2=np.tile([0.0, 3.0], (nverts, 1)),
           uv3=np.stack([np.zeros(nverts), np.ones(nverts)], -1))
    # --- skirt along the curved edges
    sk_v, sk_f = [], []
    for k in range(N):
        if kinds[k] != "curve":
            continue
        kn = (k + 1) % N
        q = len(sk_v)
        sk_v.extend([top[k], top[kn], bot[kn], bot[k]])
        sk_f.append((q, q + 1, q + 2))
        sk_f.append((q, q + 2, q + 3))
    if sk_v:
        sk_v = np.array(sk_v)
        sk_f = np.array(sk_f)
        cen = (sk_v[sk_f[:, 0]] + sk_v[sk_f[:, 1]] + sk_v[sk_f[:, 2]]) / 3.0
        nrm = np.cross(sk_v[sk_f[:, 1]] - sk_v[sk_f[:, 0]], sk_v[sk_f[:, 2]] - sk_v[sk_f[:, 0]])
        flip = np.sum(nrm[:, :2] * (cen[:, :2] - C[None, :2]), -1) < 0
        sk_f[flip] = sk_f[flip][:, [0, 2, 1]]
        up = sk_v[:, :2]
        mb.add(sk_v, sk_f, mat_pad, uv0=up / 10.0, uv1=up, uv2=np.tile([0.0, 3.0], (len(sk_v), 1)),
               uv3=np.zeros((len(sk_v), 2)))
    # --- bottom fan (faces down)
    Cb = C.copy()
    Cb[2] -= PAD_BEVEL
    Vb = np.vstack([Cb[None, :], bot])
    tb = []
    for k in range(N):
        a, b = 1 + k, 1 + (k + 1) % N
        tb.append((0, a, b) if cw else (0, b, a))
    ub = Vb[:, :2]
    mb.add(Vb, np.array(tb), DIRT, uv0=ub / 10.0, uv1=ub, uv2=np.zeros((len(Vb), 2)), uv3=np.zeros((len(Vb), 2)))
    stop_lines(jn, roads, mb)
    return mb, dict(boundary=pts, centre=C, n=N)


def stop_lines(jn, roads, mb):
    """Stop (solid) / give-way (dashed) lines across the approaching half of each controlled arm."""
    LIFT = 0.012
    for a in jn["arms"]:
        ctrl = a.get("control")
        if ctrl not in ("stop", "yield"):
            continue
        r = roads[a["road"]]
        sa = a["s_end"] + a["dir"] * 1.2
        sb = a["s_end"] + a["dir"] * 1.75
        if sa < 0 or sb < 0 or sa > r.L or sb > r.L:
            continue
        fa, fb = r.at(sa), r.at(sb)
        P, m2 = r.P, r.med / 2.0
        # approaching lane = LEFT of the away direction: away-looking lateral q is negative there
        q0, q1 = -(P - 0.25), -(m2 + 0.12)
        spans = []
        if ctrl == "stop":
            spans = [(q0, q1)]
        else:
            x = q0
            while x + 0.5 <= q1 + 1e-6:
                spans.append((x, x + 0.5))
                x += 0.9
        V, F = [], []
        for (qa, qb) in spans:
            quad = []
            for (fr, qq) in ((fa, qa), (fa, qb), (fb, qb), (fb, qa)):
                d = qq if a["dir"] == 1 else -qq
                x = fr["x"][0] + fr["ty"][0] * d
                y = fr["y"][0] - fr["tx"][0] * d
                z = fr["z"][0] - d * math.tan(fr["bank"][0]) + float(_crown(r, abs(d))) + LIFT
                quad.append((x, y, z))
            i = len(V)
            V.extend(quad)
            F.extend([(i, i + 1, i + 2), (i, i + 2, i + 3)])
        if not V:
            continue
        V = np.array(V)
        F = np.array(F)
        nrm = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        flip = nrm[:, 2] < 0
        F[flip] = F[flip][:, [0, 2, 1]]
        n = len(V)
        mb.add(V, F, MARK, uv0=np.zeros((n, 2)), uv1=V[:, :2], uv2=np.zeros((n, 2)), uv3=np.tile([0.0, 1.0], (n, 1)))
