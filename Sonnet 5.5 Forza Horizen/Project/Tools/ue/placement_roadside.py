"""Roadside furniture generator (agent P1): guard rails, delineators, signs, utility poles + wires, street lamps, fences / walls, bus stops, billboards,
culvert head-walls, mile markers.  Everything is derived from roads.json samples (2 m arc length spacing).

Conventions (Docs/Kits/roadside_kit.md, Blender +Y -> UE -Y):  segments run along local +X with the road on their LEFT (UE -Y);  sign panels / reflectors face +X;
road side `+1` = right of the direction of travel (increasing s, "A"), `-1` = left ("B" drivers see it as their right).  yaw = compass heading of the local +X.
"""
import math

import numpy as np

import placement_lib as P

SPEED_ASSET = {30: "rs_sign_speed_30", 50: "rs_sign_speed_50", 70: "rs_sign_speed_70", 90: "rs_sign_speed_90", 110: "rs_sign_speed_110"}
BRIDGE, TUNNEL, CULVERT, JUNCTION, HAIRPIN, PORTAL = 1, 2, 4, 8, 16, 32


def speed_asset(v):
    best = min(SPEED_ASSET, key=lambda k: (abs(k - v), k))
    return SPEED_ASSET[best]


class Furn:
    def __init__(self, ctx):
        self.c = ctx
        self.w = ctx.w
        self.rng = ctx.rng_for(21)
        self.stats = {}
        self.railmask = {}

    def add(self, aid, x, y, z, yaw, pitch=0.0, sx=1.0, sy=None, sz=None):
        self.c.store.add("furniture", aid, x, y, z, yaw, pitch, 0.0, sx, sx if sy is None else sy, sx if sz is None else sz)
        self.stats[aid] = self.stats.get(aid, 0) + 1

    def chain(self, r, side, lat, sa, sb, seg, rev=False):
        n = max(1, int(round(abs(sb - sa) / seg)))
        out = []
        for k in range(n):
            s0 = sa + k * seg if not rev else sb - k * seg
            s1 = s0 + seg if not rev else s0 - seg
            x0, y0, z0, _t = r.pos(s0, side * lat)
            x1, y1, z1, _t = r.pos(s1, side * lat)
            h = math.hypot(x1 - x0, y1 - y0)
            out.append((x0, y0, z0, math.degrees(math.atan2(y1 - y0, x1 - x0)), math.degrees(math.atan2(z1 - z0, max(h, 0.01)))))
        return out

    def free(self, r, s, bits=BRIDGE | TUNNEL | PORTAL | JUNCTION):
        return not r.flag_at(s, bits)

    # ----------------------------------------------------------------------------------------------------------------
    def guardrails(self, r):
        w = self.w
        if r.cls == "VILLAGE":
            return
        th = r.TH
        for side in (1, -1):
            lat = r.bed + 0.55
            sl = side * lat
            px, py = r.X - sl * np.sin(th), r.Y + sl * np.cos(th)
            zb = r.Zc - 0.05 - np.tan(np.radians(r.B)) * sl
            sl2 = side * (lat + 5.0)
            drop = zb - w.zat(r.X - sl2 * np.sin(th), r.Y + sl2 * np.cos(th))
            outer = (side * r.K) < 0
            tight = np.abs(r.K) > 1 / 220.0
            need = (drop > 4.5) if r.cls == "DIRT" else ((drop > 2.5) | (outer & tight & (drop > 0.6)))
            need &= (r.F & (BRIDGE | TUNNEL | PORTAL | JUNCTION)) == 0
            need &= self.c.river_edge.at(px, py) > 3.0
            mask = np.zeros(r.n, dtype=bool)
            for a, b in P.runs(need, gap=4, minlen=6):
                mask[a:b + 1] = True
                s0, s1 = float(r.S[a]), float(r.S[b])
                rev = side < 0
                use_parapet = r.cls == "MOUNTAIN" and float(drop[a:b + 1].mean()) > 6.0 and self.rng.uniform() < 0.4
                if use_parapet:
                    for (x, y, z, yaw, pit) in self.chain(r, side, r.bed + 0.9, s0, s1, 3.0, rev):
                        self.add("rs_parapet_mountain_3m", x, y, z, yaw, pit)
                    continue
                segs = self.chain(r, side, lat, s0, s1, 4.0, rev)
                for k, (x, y, z, yaw, pit) in enumerate(segs):
                    if len(segs) == 1:
                        aid = "rs_guardrail_4m"
                    elif k == 0:
                        aid = "rs_guardrail_end_terminal"
                    elif k == len(segs) - 1:
                        aid = "rs_guardrail_end_terminal_R"
                    else:
                        aid = "rs_guardrail_4m"
                    self.add(aid, x, y, z, yaw, pit)
            self.railmask[(r.id, side)] = mask
        # bridge parapets on both sides (deck follows the centre line)
        for br in r.d.get("bridges", []):
            for side in (1, -1):
                for (x, y, z, yaw, pit) in self.chain(r, side, r.bed - 0.25, br["s0"], br["s1"], 2.0, side < 0):
                    self.add("rs_bridge_rail_2m", x, y, z + 0.05, yaw, pit)

    def delineators(self, r):
        if r.cls == "VILLAGE":
            return
        for side in (1, -1):
            mask = self.railmask.get((r.id, side), np.zeros(r.n, dtype=bool))
            s = 12.0
            while s < r.length - 12:
                i = int(np.clip(round(float(r.fi(s))), 0, r.n - 1))
                hair = bool(r.F[i] & HAIRPIN)
                k = abs(float(r.K[i]))
                step = 8.0 if hair else (14.0 if k > 1 / 250.0 else (60.0 if r.cls == "HIGHWAY" else (40.0 if r.cls in ("MOUNTAIN", "REGIONAL") else 50.0)))
                if (r.F[i] & (BRIDGE | JUNCTION | PORTAL | TUNNEL)) == 0 and not mask[i]:
                    x, y, z, th = r.pos(s, side * (r.bed + 0.8))
                    aid = "rs_delineator_post_amber" if hair else ("rs_delineator_post_white" if side > 0 else "rs_delineator_post")
                    self.add(aid, x, y, z, math.degrees(th) + (180.0 if side > 0 else 0.0))
                s += step

    # ---------------------------------------------------------------------------------------------------------- signs
    def sign(self, r, s, side, aid, face, shift_ok=True):
        """face 'A' -> panel faces drivers travelling in +s, 'B' -> drivers travelling in -s."""
        if s < 4 or s > r.length - 4:
            return False
        for d in ((0, 8, -8, 16, -16) if shift_ok else (0,)):
            if self.free(r, s + d):
                x, y, z, th = r.pos(s + d, side * (r.bed + 1.3))
                self.add(aid, x, y, z, math.degrees(th) + (180.0 if face == "A" else 0.0))
                return True
        return False

    def signs(self, r):
        rng = self.rng
        L = r.length
        sp = speed_asset(r.speed)
        self.sign(r, 14.0, 1, sp, "A")
        self.sign(r, L - 14.0, -1, sp, "B")
        for s in np.arange(2200.0, L - 600.0, 2200.0):
            self.sign(r, float(s), 1, sp, "A")
            self.sign(r, float(s) + 40.0, -1, sp, "B")
        last = {}

        def spaced(key, s, gap=140.0):
            for t in last.get(key, []):
                if abs(t - s) < gap:
                    return False
            last.setdefault(key, []).append(s)
            return True

        k = np.abs(r.K)
        hair = (r.F & HAIRPIN) != 0
        for a, b in P.runs((k > 1 / 140.0) & ~hair, gap=3, minlen=8):
            mk = float(r.K[a:b + 1].mean())
            sa, sb = float(r.S[a]), float(r.S[b])
            if spaced(("cA", r.id), sa) :
                self.sign(r, sa - 75.0, 1, "rs_sign_curve_right" if mk > 0 else "rs_sign_curve_left", "A")
            if spaced(("cB", r.id), sb):
                self.sign(r, sb + 75.0, -1, "rs_sign_curve_left" if mk > 0 else "rs_sign_curve_right", "B")
            if float(k[a:b + 1].max()) > 1 / 80.0 and r.cls in ("MOUNTAIN", "REGIONAL", "DIRT"):    # chevrons on the outside of tight bends
                self.chevrons(r, sa, sb, mk)
        for a, b in P.runs(hair, gap=5, minlen=4):
            mk = float(r.K[a:b + 1].mean())
            sa, sb = float(r.S[a]), float(r.S[b])
            self.sign(r, sa - 90.0, 1, "rs_sign_hairpin", "A")
            self.sign(r, sb + 90.0, -1, "rs_sign_hairpin", "B")
            self.chevrons(r, sa, sb, mk)
        for br in r.d.get("bridges", []):
            if br["length"] >= 40:
                self.sign(r, br["s0"] - 70.0, 1, "rs_sign_bridge", "A")
                self.sign(r, br["s1"] + 70.0, -1, "rs_sign_bridge", "B")
        for tu in r.d.get("tunnels", []):
            self.sign(r, tu["s0"] - 110.0, 1, "rs_sign_tunnel", "A")
            self.sign(r, tu["s1"] + 110.0, -1, "rs_sign_tunnel", "B")
        if r.cls in ("MOUNTAIN", "REGIONAL", "DIRT"):
            for a, b in P.runs(r.grade < -0.075, gap=10, minlen=80):
                self.sign(r, float(r.S[a]) - 50.0, 1, "rs_sign_steep_descent", "A")
            for a, b in P.runs(r.grade > 0.075, gap=10, minlen=80):
                self.sign(r, float(r.S[b]) + 50.0, -1, "rs_sign_steep_descent", "B")
        if r.cls in ("HIGHWAY", "REGIONAL", "MOUNTAIN"):
            for s in np.arange(1000.0, L - 200.0, 1000.0):
                self.sign(r, float(s), 1, "rs_milemarker", "A")
        if r.cls == "MOUNTAIN":
            for s in np.arange(900.0, L - 300.0, 1400.0):
                self.sign(r, float(s), -1, "rs_milestone_stone", "B")

    def chevrons(self, r, sa, sb, mk):
        outer = -1 if mk > 0 else 1          # A turns right -> outer edge is the left one
        for s in np.arange(sa + 3.0, sb - 3.0, 12.0):
            if self.free(r, float(s), BRIDGE | TUNNEL | JUNCTION):
                x, y, z, th = r.pos(float(s), outer * (r.bed + 1.6))
                self.add("rs_sign_chevron_right" if mk > 0 else "rs_sign_chevron_left", x, y, z, math.degrees(th) + 180.0)
                x, y, z, th = r.pos(float(s) + 6.0, outer * (r.bed + 1.6))
                self.add("rs_sign_chevron_left" if mk > 0 else "rs_sign_chevron_right", x, y, z, math.degrees(th))

    def junction_signs(self):
        c = self.c
        for nd in c.w.roads_json["nodes"]:
            for conn in nd["connections"]:
                r = c.roads.get(conn["road"])
                if r is None:
                    continue
                s, role, ctl = float(conn["s"]), conn["role"], conn.get("control")
                if role == "end":
                    appr = [(s - 16.0, 1, "A")]
                elif role == "start":
                    appr = [(s + 16.0, -1, "B")]
                else:
                    appr = []
                if ctl in ("yield", "stop"):
                    for ss, side, face in appr:
                        self.sign(r, ss, side, "rs_sign_give_way" if ctl == "yield" else "rs_sign_stop", face, shift_ok=False)
                if nd["kind"] == "node" and nd["arm_count"] >= 3 and r.cls in ("HIGHWAY", "REGIONAL", "MOUNTAIN"):
                    asset = {"HIGHWAY": "rs_sign_direction_l", "REGIONAL": "rs_sign_direction_m", "MOUNTAIN": "rs_sign_direction_s"}[r.cls]
                    for ss, side, face in (appr or [(s - 60.0, 1, "A"), (s + 60.0, -1, "B")]):
                        d = 60.0 - 16.0 if appr else 0.0
                        self.sign(r, ss - d if face == "A" else ss + d, side, asset, face)
                if nd["id"] in ("MILL", "TIDE", "FROST", "LODGE") and r.cls in ("REGIONAL", "MOUNTAIN", "VILLAGE"):
                    for ss, side, face in (appr or [(s - 110.0, 1, "A"), (s + 110.0, -1, "B")]):
                        d = 110.0 - 16.0 if appr else 0.0
                        self.sign(r, ss - d if face == "A" else ss + d, side, "rs_sign_village", face)
                if nd["kind"] == "T" and role == "mid" and r.cls in ("REGIONAL", "MOUNTAIN"):
                    self.sign(r, s - 100.0, 1, "rs_sign_junction", "A")
                    self.sign(r, s + 100.0, -1, "rs_sign_junction", "B")

    # -------------------------------------------------------------------------------------------- poles and lamps
    def poles(self, r, ri):
        w = self.w
        if r.cls not in ("REGIONAL", "VILLAGE"):
            return
        side = 1 if ri % 2 == 0 else -1
        lat = r.bed + 5.0
        ox, oy = r.X - side * (r.bed + 12.0) * np.sin(r.TH), r.Y + side * (r.bed + 12.0) * np.cos(r.TH)
        farm = (w.near(w.farm, ox, oy) > 25) & np.isin(w.near(w.region, r.X, r.Y), (0, 4)) & ((r.F & (BRIDGE | TUNNEL | JUNCTION | CULVERT | PORTAL)) == 0)
        for a, b in P.runs(farm, gap=40, minlen=60):
            pts = []
            s = float(r.S[a])
            while s <= float(r.S[b]):
                x, y, _z, th = r.pos(s, side * lat)
                if self.c.bld_edge.at(x, y) > 3.0 and self.c.river_edge.at(x, y) > 3.0:
                    pts.append((x, y, float(w.zat(x, y))))
                else:
                    pts.append(None)
                s += 30.0
            for k, p in enumerate(pts):
                if p is None:
                    continue
                nxt = pts[k + 1] if k + 1 < len(pts) else None
                prv = pts[k - 1] if k > 0 else None
                ref = nxt or prv
                if ref is None:
                    continue
                yaw = math.degrees(math.atan2(ref[1] - p[1], ref[0] - p[0])) + (180.0 if nxt is None else 0.0)
                self.add("rs_utility_pole_9m", p[0], p[1], p[2], yaw, sx=1.0)
                if nxt is not None:
                    dh = math.hypot(nxt[0] - p[0], nxt[1] - p[1])
                    dz = nxt[2] - p[2]
                    self.add("rs_utility_wire_span_30m", p[0], p[1], p[2] + 8.654, math.degrees(math.atan2(nxt[1] - p[1], nxt[0] - p[0])), math.degrees(math.atan2(dz, dh)),
                             sx=math.sqrt(dh * dh + dz * dz) / 30.0, sy=1.0, sz=1.0)

    def lamps(self, r):
        if r.cls != "VILLAGE":
            return
        s = 20.0
        k = 0
        while s < r.length - 15:
            if self.free(r, s, BRIDGE | JUNCTION | TUNNEL):
                side = 1 if k % 2 == 0 else -1
                x, y, z, th = r.pos(s, side * (r.bed + 1.5))
                if self.c.bld_edge.at(x, y) > 1.5:
                    self.add("rs_streetlamp_8m", x, y, z, math.degrees(th) + (0.0 if side > 0 else 180.0))
                k += 1
            s += 36.0

    def site_lamps(self, rects_by_group):
        for g, rect in rects_by_group:
            for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                lx, ly = sx * (rect.hx + 4.5), sy * (rect.hy + 4.5)
                dx, dy = P.rot(rect.yaw, lx, ly)
                x, y = rect.cx + dx, rect.cy + dy
                if self.c.road_edge.at(x, y) < 2.0:
                    continue
                ux, uy = rect.cx - x, rect.cy - y
                self.add("rs_streetlamp_8m", x, y, float(self.w.zat(x, y)), math.degrees(math.atan2(ux / max(math.hypot(ux, uy), 1e-6), -uy / max(math.hypot(ux, uy), 1e-6))))

    # ------------------------------------------------------------------------------------------- fences and walls
    def fences(self, r):
        w, rng = self.w, self.rng
        if r.cls not in ("REGIONAL", "DIRT", "VILLAGE"):
            return
        fs = self.c.w.sites.get("Frostholm")
        reg = w.near(w.region, r.X, r.Y)
        farm_side = {sd: w.near(w.farm, r.X - sd * (r.bed + 12.0) * np.sin(r.TH), r.Y + sd * (r.bed + 12.0) * np.cos(r.TH)) > 50 for sd in (1, -1)}
        near_frost = np.zeros(r.n, dtype=bool)
        if fs:
            near_frost = np.hypot(r.X - fs["x"], r.Y - fs["y"]) < 230.0
        for side in (1, -1):
            cand = ((farm_side[side] & np.isin(reg, (0, 2, 4))) | near_frost) & ((r.F & (BRIDGE | TUNNEL | JUNCTION | CULVERT | PORTAL)) == 0)
            for a, b in P.runs(cand, gap=10, minlen=25):
                s = float(r.S[a])
                end = float(r.S[b])
                while s < end - 10.0:
                    ln = float(rng.uniform(40, 200))
                    on = rng.uniform() < 0.65
                    s1 = min(s + ln, end)
                    if on:
                        i = int(np.clip(round(float(r.fi(s))), 0, r.n - 1))
                        if near_frost[i]:
                            style = "stone"
                        elif int(reg[i]) == 0:
                            style = "wood" if rng.uniform() < 0.7 else "stone"
                        else:
                            style = "wire"
                        self.fence_run(r, side, s, s1, style)
                    s = s1 + float(rng.uniform(15, 50))

    def fence_run(self, r, side, s0, s1, style):
        w, rng = self.w, self.rng
        lat = r.bed + (3.6 if style == "stone" else 5.2)
        seg = {"wood": 2.5, "wire": 3.0, "stone": 2.0}[style]
        segs = self.chain(r, side, lat, s0, s1, seg)
        last = None
        for k, (x, y, _z, yaw, _p) in enumerate(segs):
            if self.c.bld_edge.at(x, y) < 2.0 or self.c.road_edge.at(x, y) < 2.5 or self.c.river_edge.at(x, y) < 2.0 or w.slope_deg(x, y) > 35:
                continue
            z = float(w.zat(x, y))
            if style == "wood":
                aid = ("rs_fence_wood_2_5m", "rs_fence_wood_2_5m_b", "rs_fence_wood_2_5m_c")[int(rng.integers(0, 3))]
            elif style == "wire":
                aid = "rs_fence_wire_3m"
            else:
                aid = "rs_wall_stone_2m" if k % 2 == 0 else "rs_wall_stone_2m_b"
            self.add(aid, x, y, z, yaw)
            last = (x, y, z, yaw, seg)
        if last is not None and style != "stone":
            x, y, z, yaw, sg = last
            ex, ey = P.rot(yaw, sg, 0.0)
            self.add("rs_fence_wood_endpost" if style == "wood" else "rs_fence_wire_endpost", x + ex, y + ey, float(w.zat(x + ex, y + ey)), yaw + (0.0 if style == "wood" else 180.0))

    # -------------------------------------------------------------------------------------------- misc furniture
    def nearest_s(self, r, x, y):
        d = np.hypot(r.X - x, r.Y - y)
        i = int(np.argmin(d))
        return float(r.S[i]), float(d[i])

    def bus_stops(self):
        c = self.c
        spots = [("Millbrook", ["LOCAL_MILL_MAIN", "LOCAL_MILL_RING"]), ("Tidewick", ["LOCAL_TIDE_HIGH", "LOCAL_TIDE_QUAY"]), ("Frostholm", ["LOCAL_FROST"]),
                 ("Crossroads Diner", ["LOCAL_DINER"]), ("Rest Area North", []), ("Rest Area South", [])]
        for name, rids in spots:
            site = c.w.sites.get(name)
            if not site:
                continue
            best = None
            for rid in (rids or list(c.roads)):
                r = c.roads.get(rid)
                if r is None:
                    continue
                s, d = self.nearest_s(r, site["x"], site["y"])
                if best is None or d < best[0]:
                    best = (d, r, s)
            if best is None or best[0] > 160:
                continue
            _d, r, s = best
            for off, side in ((28.0, 1), (-6.0, -1)):
                ss = float(np.clip(s + off, 12, r.length - 12))
                if not self.free(r, ss):
                    continue
                x, y, z, th = r.pos(ss, side * (r.bed + 2.8))
                if c.bld_edge.at(x, y) > 2.0 and c.river_edge.at(x, y) > 3:
                    self.add("rs_bus_stop_shelter", x, y, z, math.degrees(th) - 90.0 * side)
                    break

    def billboards(self):
        r = self.c.roads.get("HWY_EAST")
        if r is None:
            return
        for k, s in enumerate((800.0, 1900.0, 3000.0, 4200.0)):
            side = 1 if k % 2 == 0 else -1
            x, y, _z, th = r.pos(s, side * (r.bed + 26.0))
            if self.c.river_edge.at(x, y) < 3 or self.w.slope_deg(x, y) > 14:
                continue
            yaw = math.degrees(th) + (180.0 if side > 0 else 0.0)
            self.add("rs_billboard_roadside", x, y, float(self.w.zat(x, y)), yaw, sx=float(self.rng.uniform(1.0, 1.25)))
        for s in (1700.0, 3600.0):
            self.sign(r, s, 1, "rs_speedtrap_camera", "A", shift_ok=True)

    def culverts(self):
        c = self.c
        streams = [np.array(st["points"], dtype=float).reshape(-1, 4) for st in c.w.river.get("streams", []) if st.get("points")]
        for r in c.roads.values():
            for sc in r.d.get("culverts", []):
                x0, y0, _z, th = r.pos(float(sc), 0.0)
                ax, ay = -math.sin(th), math.cos(th)         # default: perpendicular to the road
                best = (40.0, None)
                for sp in streams:
                    dd = np.hypot(sp[:, 0] - x0, sp[:, 1] - y0)
                    j = int(np.argmin(dd))
                    if dd[j] < best[0] and 0 < j < len(sp) - 1:
                        best = (float(dd[j]), (sp[j + 1, 0] - sp[j - 1, 0], sp[j + 1, 1] - sp[j - 1, 1]))
                if best[1]:
                    tl = math.hypot(*best[1]) or 1.0
                    ax, ay = best[1][0] / tl, best[1][1] / tl
                for sgn in (1, -1):
                    x, y = x0 + sgn * ax * (r.bed + 2.0), y0 + sgn * ay * (r.bed + 2.0)
                    aid = "rs_culvert_headwall_a" if self.rng.uniform() < 0.6 else "rs_culvert_headwall_b"
                    self.add(aid, x, y, float(self.w.zat(x, y)) - 0.1, math.degrees(math.atan2(sgn * ay, sgn * ax)), sx=float(self.rng.uniform(0.95, 1.2)))

    def viewpoints(self):
        c = self.c
        for name in ("Summit Viewpoint", "Canyon Rim Viewpoint", "Cliff Viewpoint"):
            s = c.w.sites.get(name)
            if not s:
                continue
            for _ in range(3):
                for _try in range(12):
                    x, y = s["x"] + float(self.rng.uniform(-9, 9)), s["y"] + float(self.rng.uniform(-9, 9))
                    if c.road_edge.at(x, y) > 3.0 and c.river_edge.at(x, y) > 2.0 and self.w.zat(x, y) > 0.5:
                        self.add("rs_cairn_stack", x, y, float(self.w.zat(x, y)) - 0.05, float(self.rng.uniform(0, 360)), sx=float(self.rng.uniform(0.8, 1.3)))
                        break

    def run_all(self):
        c = self.c
        for ri, r in enumerate(c.roads.values()):
            self.guardrails(r)
        for ri, r in enumerate(c.roads.values()):
            self.delineators(r)
            self.signs(r)
            self.poles(r, ri)
            self.lamps(r)
            self.fences(r)
        self.junction_signs()
        self.bus_stops()
        self.billboards()
        self.culverts()
        self.viewpoints()
        return self.stats
