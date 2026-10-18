"""Settlement placement (agent P1): buildings, landmarks, harbour, farms, castle ruin, wind farm.  Called by placement_gen.py with a Ctx.
Buildings are fitted to the terrain by choosing flat spots (terrain range under the footprint <= ~1.3 m; village pads are flattened by the world
generator, see worlddef.PLATFORMS) instead of flattening anything; footprints (sidecar bounds) must not overlap each other or any road bed.
"""
import math

import numpy as np

import placement_lib as P


def deg(rad):
    return math.degrees(rad)


class Settle:
    def __init__(self, ctx):
        self.c = ctx
        self.w = ctx.w
        self.rng = ctx.rng_for(77)
        self.rects = []          # Rect of every placed building (for overlap + exclusion fields)
        self.buildings = []      # json dicts
        self.rotors = []
        self.notes = []

    # ----------------------------------------------------------------------------------------------------------- core
    def asset_rect(self, aid, x, y, yaw, scale=1.0, grow=0.0):
        e = self.c.cat[aid]
        bmin, bmax = e["bmin"], e["bmax"]
        cxl = (bmin[0] + bmax[0]) / 2 * scale
        cyl = -(bmin[1] + bmax[1]) / 2 * scale          # Blender +Y -> UE -Y
        wx, wy = P.rot(yaw, cxl, cyl)
        return P.Rect(x + wx, y + wy, (bmax[0] - bmin[0]) / 2 * scale + grow, (bmax[1] - bmin[1]) / 2 * scale + grow, yaw)

    def check(self, rect, road_margin=4.0, max_range=1.3, bld_margin=1.5, ignore=()):
        for r in self.rects:
            if rect.overlaps(r, bld_margin):
                return None
        bx, by = rect.boundary(3.0)
        if self.c.road_edge.at(bx, by).min() < road_margin:
            return None
        if self.c.river_edge.at(bx, by).min() < 4.0:
            return None
        gx, gy = rect.grid(2.5)
        z = self.w.zat(gx, gy)
        if z.max() - z.min() > max_range or z.min() < 0.9:
            return None
        return z

    def commit(self, aid, x, y, yaw, zs, scale=1.0, group="", tag=""):
        rng_z = float(zs.max() - zs.min())
        z = float(zs.max()) - 0.15 - 0.4 * rng_z
        rect = self.asset_rect(aid, x, y, yaw, scale)
        self.rects.append(rect)
        name = "%s_%s_%02d" % (group or "B", aid.replace("bld_", ""), len(self.buildings))
        self.buildings.append({"asset": aid, "x": x, "y": y, "z": z, "yaw": yaw, "scale": scale, "name": name, "group": group, "tag": tag})
        return name

    def try_place(self, aid, x, y, yaw, scale=1.0, group="", **chk):
        rect = self.asset_rect(aid, x, y, yaw, scale)
        zs = self.check(rect, **chk)
        if zs is None:
            return None
        return self.commit(aid, x, y, yaw, zs, scale, group)

    def search(self, aid, cx, cy, yaw_fn, rmax=70.0, step=6.0, scale=1.0, group="", **chk):
        """Spiral search around (cx, cy) for the first valid spot; yaw_fn(x, y) -> list of candidate yaws."""
        for r in np.arange(0.0, rmax + 0.1, step):
            angs = [0.0] if r == 0 else np.arange(0, 360, 360.0 / max(6, int(2 * math.pi * r / 14.0)))
            for a in angs:
                x, y = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
                for yaw in yaw_fn(x, y):
                    n = self.try_place(aid, x, y, yaw, scale, group, **chk)
                    if n:
                        return n
        self.notes.append("no spot for %s near (%.0f, %.0f)" % (aid, cx, cy))
        return None

    def search_best(self, aid, cx, cy, yaw_fn, rmax=60.0, step=4.0, scale=1.0, group="", **chk):
        """Like search() but evaluates every candidate and takes the one with the flattest terrain (rough hill-top landmarks)."""
        best = None
        for r in np.arange(0.0, rmax + 0.1, step):
            angs = [0.0] if r == 0 else np.arange(0, 360, 360.0 / max(6, int(2 * math.pi * r / 8.0)))
            for a in angs:
                x, y = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
                for yaw in yaw_fn(x, y):
                    zs = self.check(self.asset_rect(aid, x, y, yaw, scale), **chk)
                    if zs is not None:
                        rg = float(zs.max() - zs.min())
                        if best is None or rg < best[0]:
                            best = (rg, x, y, yaw, zs)
        if best is None:
            self.notes.append("no spot for %s near (%.0f, %.0f)" % (aid, cx, cy))
            return None
        return self.commit(aid, best[1], best[2], best[3], best[4], scale, group)

    def face_road(self, maxd=120.0):
        def f(x, y):
            px, py, d, _r = self.c.nearest_road(x, y)
            if d > maxd:
                return [self.rng.uniform(0, 360)]
            b = deg(math.atan2(py - y, px - x))
            return [b, b + 20, b - 20]
        return f

    def face_point(self, tx, ty):
        return lambda x, y: [deg(math.atan2(ty - y, tx - x)), deg(math.atan2(ty - y, tx - x)) + 25, deg(math.atan2(ty - y, tx - x)) - 25]

    # -------------------------------------------------------------------------------------------------- frontage rows
    def frontage(self, road_ids, centre, radius, weights, count, group, spacing=(14.0, 22.0), setback=(4.5, 8.5), sides=(1, -1), s_lo=14.0, max_range=1.3):
        n = 0
        names = [a for a, _ in weights]
        probs = np.array([p for _, p in weights], dtype=float)
        probs /= probs.sum()
        for rid in road_ids:
            road = self.c.roads.get(rid)
            if road is None:
                continue
            for side in sides:
                s = s_lo + self.rng.uniform(0, 8)
                while s < road.length - 10 and n < count:
                    aid = str(self.rng.choice(names, p=probs))
                    e = self.c.cat[aid]
                    scale = float(self.rng.uniform(*e["scale"]))
                    px, py, _pz, th = road.pos(s, side * road.bed)
                    fx, fy = side * math.sin(th), -side * math.cos(th)            # towards the road
                    yaw = deg(math.atan2(fy, fx)) + float(self.rng.uniform(-3, 3))
                    sb = float(self.rng.uniform(*setback))
                    ox, oy = px - fx * (sb + e["bmax"][0] * scale), py - fy * (sb + e["bmax"][0] * scale)
                    if math.hypot(ox - centre[0], oy - centre[1]) > radius:
                        s += 6.0
                        continue
                    nm = self.try_place(aid, ox, oy, yaw, scale, group, max_range=max_range)
                    if nm:
                        n += 1
                        rect = self.rects[-1]
                        s += max(spacing[0], 2 * rect.hy + float(self.rng.uniform(1.0, spacing[1] - spacing[0] + 3)))
                    else:
                        s += 5.0
        return n

    # ------------------------------------------------------------------------------------------------------- sites
    def site(self, name):
        return self.w.sites.get(name)

    def node(self, nid):
        for n in self.w.roads_json["nodes"]:
            if n["id"] == nid:
                return n
        return None

    def arm_dir_into_node(self, nid):
        """Bearing (deg) of travel INTO the node along its first arm (the way a car arrives)."""
        n = self.node(nid)
        if not n or not n["arms"]:
            return None
        return (n["arms"][0]["heading"] + 180.0) % 360.0

    def end_building(self, nid, aid, gap=4.0, group="", scale=1.0, **chk):
        """Building at the dead end of a road, front (+X) facing the arriving traffic."""
        n = self.node(nid)
        fwd = self.arm_dir_into_node(nid)
        if n is None or fwd is None:
            return None
        e = self.c.cat[aid]
        fx, fy = math.cos(math.radians(fwd)), math.sin(math.radians(fwd))
        for extra in (0.0, 4.0, 8.0, 12.0):
            for lat in (0.0, 8.0, -8.0, 16.0, -16.0):
                ox = n["x"] + fx * (gap + extra + e["bmax"][0] * scale) - fy * lat
                oy = n["y"] + fy * (gap + extra + e["bmax"][0] * scale) + fx * lat
                nm = self.try_place(aid, ox, oy, fwd + 180.0, scale, group, **chk)
                if nm:
                    return nm
        return None

    # ---------------------------------------------------------------------------------------------------- the build
    def build(self):
        c, rng = self.c, self.rng
        self.millbrook()
        self.frostholm()
        self.tidewick()
        for fn, nid in (("Farm A", "FARM_A"), ("Farm B", "FARM_B"), ("Farm C", "FARM_C"), ("Farm D", "FARM_D")):
            self.farm(fn, nid)
        self.gas_and_diners()
        self.landmarks()
        self.castle()
        self.windfarm()
        self.beach_huts()
        return self

    def millbrook(self):
        s = self.site("Millbrook")
        if not s:
            return
        ctr = (s["x"], s["y"])
        g = "Millbrook"
        # church on the first free frontage spot of the main street, then the houses
        church = None
        main = self.c.roads.get("LOCAL_MILL_MAIN")
        if main is not None:
            for side in (1, -1):
                for ss in np.arange(35.0, min(main.length - 25, 160), 8.0):
                    px, py, _z, th = main.pos(ss, side * main.bed)
                    fx, fy = side * math.sin(th), -side * math.cos(th)
                    e = self.c.cat["bld_church"]
                    ox, oy = px - fx * (7.0 + e["bmax"][0]), py - fy * (7.0 + e["bmax"][0])
                    church = self.try_place("bld_church", ox, oy, deg(math.atan2(fy, fx)), 1.0, g, max_range=1.6)
                    if church:
                        break
                if church:
                    break
        w = [("bld_house_a", 0.30), ("bld_house_b", 0.22), ("bld_house_c", 0.22), ("bld_house_l", 0.26)]
        n = self.frontage(["LOCAL_MILL_MAIN", "LOCAL_MILL_WEST", "LOCAL_MILL_RING"], ctr, 190.0, w, 16, g)
        if n < 12:   # also use the through roads that pass the village
            n += self.frontage(["LOOP_VALLEY", "LOOP_SOUTH"], ctr, 150.0, w, 12 - n, g, sides=(1, -1), setback=(6.0, 12.0))
        self.notes.append("Millbrook: church=%s houses=%d" % (bool(church), n))

    def frostholm(self):
        s = self.site("Frostholm")
        if not s:
            return
        ctr = (s["x"], s["y"])
        g = "Frostholm"
        lodge = self.end_building("LODGE", "bld_chalet", gap=6.0, group=g, scale=1.15, max_range=2.0) or self.search(
            "bld_chalet", ctr[0], ctr[1], self.face_road(), 60.0, 6.0, 1.15, g, max_range=2.0)
        n = self.frontage(["LOCAL_FROST", "PASS_SPUR"], ctr, 130.0, [("bld_chalet", 1.0)], 6, g, spacing=(18.0, 26.0), setback=(5.0, 9.0), max_range=2.2)
        self.notes.append("Frostholm: lodge=%s chalets=%d" % (bool(lodge), n))

    def tidewick(self):
        s = self.site("Tidewick")
        if not s:
            return
        ctr = (s["x"], s["y"])
        g = "Tidewick"
        w = [("bld_harbour_hut", 0.55), ("bld_house_a", 0.15), ("bld_house_b", 0.15), ("bld_house_c", 0.15)]
        n = self.frontage(["LOCAL_TIDE_QUAY", "LOCAL_TIDE_HIGH"], ctr, 170.0, w, 14, g, spacing=(12.0, 20.0), setback=(4.0, 8.0), max_range=1.8)
        # pier: from the quay node into the sea along the arrival direction, segments chained along +X
        piers = 0
        nid = self.node("PIER")
        if nid:
            fwd = (nid["arms"][0]["heading"] + 180.0) % 360.0
            best = None
            for ang in range(-180, 180, 15):
                d = math.radians(fwd + ang)
                dx, dy = math.cos(d), math.sin(d)
                dist = np.arange(0.0, 460.0, 2.0)
                zz = self.w.zat(nid["x"] + dx * dist, nid["y"] + dy * dist)
                land = np.flatnonzero(zz < 1.4)
                if len(land) == 0:
                    continue
                k0 = land[0]
                sea = np.flatnonzero(zz[k0:] < -2.0)
                if len(sea) == 0 or self.c.road_edge.at(nid["x"] + dx * dist[k0], nid["y"] + dy * dist[k0]) < 0:
                    continue
                if best is None or dist[k0] < best[1]:
                    best = (fwd + ang, dist[k0], dx, dy)
            if best is not None and best[1] > 140.0:
                self.notes.append("Tidewick: nearest sea is %.0f m from the PIER node (> 140 m) - pier skipped (heightmap has no harbour water yet)" % best[1])
                best = None
            elif best is None:
                self.notes.append("Tidewick: no sea within 460 m of the PIER node - no pier / boats")
            if best:
                yaw, d0, dx, dy = best
                x0, y0 = nid["x"] + dx * d0, nid["y"] + dy * d0
                nseg = 0
                for k in range(14):
                    px, py = x0 + dx * 4.0 * k, y0 + dy * 4.0 * k
                    self.buildings.append({"asset": "bld_pier_4m", "x": px, "y": py, "z": 0.0, "yaw": yaw, "scale": 1.0, "name": "Tidewick_pier_%02d" % k, "group": g, "tag": "pier"})
                    nseg += 1
                    if self.w.zat(px + dx * 4.0, py + dy * 4.0) < -2.2 and nseg >= 6:
                        break
                piers = nseg
                self.rects.append(P.Rect(x0 + dx * 2.0 * nseg, y0 + dy * 2.0 * nseg, 2.0 * nseg + 1.0, 2.0, yaw))
                # boats beside the pier where deep enough
                nb = 0
                for k in range(3, nseg):
                    for side in (1, -1):
                        if nb >= 5:
                            break
                        bx, by = x0 + dx * 4.0 * k - side * dy * 5.5, y0 + dy * 4.0 * k + side * dx * 5.5
                        depth = float(self.w.zat(bx, by))
                        fishing = (nb % 2 == 0)
                        need = -2.0 if fishing else -0.6
                        if depth < need and self.rng.uniform() < 0.55:
                            aid = "bld_boat_fishing_8m" if fishing else "bld_boat_row"
                            wl = 0.75 if fishing else 0.16
                            self.buildings.append({"asset": aid, "x": bx, "y": by, "z": -wl, "yaw": yaw + float(self.rng.uniform(-8, 8)), "scale": 1.0,
                                                   "name": "Tidewick_boat_%02d" % nb, "group": g, "tag": "boat"})
                            nb += 1
        self.notes.append("Tidewick: buildings=%d pier_segments=%d" % (n, piers))

    def farm(self, site_name, nid):
        s = self.site(site_name)
        node = self.node(nid)
        if not s or not node:
            return
        g = site_name.replace(" ", "")
        fwd = self.arm_dir_into_node(nid) or 0.0
        base = (node["x"], node["y"])
        placed = []
        # yard layout in the frame (fwd = continuing beyond the road end, lat = right of fwd)
        plan = [("bld_farmhouse", 24.0, -14.0), ("bld_barn", 46.0, 20.0), ("bld_silo", 56.0, 40.0), ("bld_farmhouse", 12.0, 38.0)]
        for i, (aid, f, l) in enumerate(plan):
            if i == 3:
                aid = "bld_barn" if self.rng.uniform() < 0.5 else "bld_silo"
            ok = None
            for mirror in (1, -1):
                for df in (0.0, 8.0, -6.0, 16.0):
                    fx, fy = math.cos(math.radians(fwd)), math.sin(math.radians(fwd))
                    rx, ry = -fy, fx
                    x = base[0] + fx * (f + df) + rx * l * mirror
                    y = base[1] + fy * (f + df) + ry * l * mirror
                    yaw = fwd + 180.0 if aid == "bld_farmhouse" else math.degrees(math.atan2(base[1] - y, base[0] - x)) + 90.0 * (1 if mirror > 0 else -1)
                    ok = self.try_place(aid, x, y, yaw, float(self.rng.uniform(*self.c.cat[aid]["scale"])), g, max_range=1.6)
                    if ok:
                        break
                if ok:
                    break
            placed.append(ok)
        self.notes.append("%s: %d/%d buildings" % (site_name, sum(1 for p in placed if p), len(plan)))

    def gas_and_diners(self):
        for site_name, nid, aid in (("Crossroads Gas", "GAS_X", "bld_gas_station"), ("Plateau Gas", "GAS_P", "bld_gas_station"),
                                    ("Harbour Gas", "GAS_H", "bld_gas_station"), ("Crossroads Diner", "DINER_X", "bld_diner")):
            s = self.site(site_name)
            if not s:
                continue
            g = site_name.replace(" ", "")
            nm = self.end_building(nid, aid, gap=5.0, group=g, max_range=1.5) or self.search(aid, s["x"], s["y"], self.face_road(), 50.0, 6.0, 1.0, g, max_range=1.5)
            self.notes.append("%s: %s" % (site_name, "ok" if nm else "FAILED"))
        s = self.site("Plateau Diner")
        if s:
            nm = self.search("bld_diner", s["x"], s["y"], self.face_road(160.0), 50.0, 6.0, 1.0, "PlateauDiner", max_range=1.5)
            self.notes.append("Plateau Diner: %s" % ("ok" if nm else "FAILED"))

    def landmarks(self):
        s = self.site("Lighthouse")
        if s:
            nm = self.search_best("bld_lighthouse", s["x"], s["y"], self.face_point(s["x"] + 30.0, s["y"] - 30.0), 45.0, 3.0, 1.15, "Lighthouse", max_range=9.0, road_margin=5.0)
            self.notes.append("Lighthouse: %s" % ("ok" if nm else "FAILED"))
        s = self.site("Millbrook")
        if s:   # windmill on the pad edge, blades registered as rotor
            nm = self.search("bld_windmill", s["x"] + 75.0, s["y"] - 60.0, lambda x, y: [self.rng.uniform(0, 360)], 70.0, 7.0, 1.2, "Millbrook", max_range=1.6, road_margin=8.0)
            if nm:
                b = self.buildings[-1]
                self.add_rotor("bld_windmill_blades", b, (2.8, 0.0, 8.15), 15.0, "windmill")
            self.notes.append("Windmill: %s" % ("ok" if nm else "FAILED"))

    def add_rotor(self, aid, tower, hub_bl, deg_per_s, kind):
        s = tower["scale"]
        wx, wy = P.rot(tower["yaw"], hub_bl[0] * s, -hub_bl[1] * s)
        self.rotors.append({"asset": aid, "x": tower["x"] + wx, "y": tower["y"] + wy, "z": tower["z"] + hub_bl[2] * s, "yaw": tower["yaw"], "scale": s,
                            "name": tower["name"] + "_rotor", "group": tower["group"], "deg_per_s": deg_per_s, "axis": [1.0, 0.0, 0.0], "pivot": "hub", "kind": kind})

    def castle(self):
        s = self.site("Greenvale Castle Ruin")
        if not s:
            return
        g = "Castle"
        px, py, d, _r = self.c.nearest_road(s["x"], s["y"])
        yaw0 = math.degrees(math.atan2(py - s["y"], px - s["x"]))
        a, b = 24.0, 18.0
        corners = {(1, -1): 0.0, (1, 1): 90.0, (-1, 1): 180.0, (-1, -1): 270.0}
        pts = {}
        for (sx, sy), ty in corners.items():
            cx, cy = P.rot(yaw0, sx * a, sy * b)
            x, y = s["x"] + cx, s["y"] + cy
            z = float(self.w.zat(x, y))
            pts[(sx, sy)] = (x, y, z)
            self.buildings.append({"asset": "bld_castle_tower_ruin", "x": x, "y": y, "z": z - 0.5, "yaw": yaw0 + ty, "scale": 1.0, "name": "Castle_tower_%d" % len(pts), "group": g, "tag": "ruin"})
            self.rects.append(P.Rect(x, y, 6.0, 6.0, yaw0 + ty))
        order = [(1, -1), (1, 1), (-1, 1), (-1, -1)]
        nwall = 0
        for i in range(4):
            A, B = pts[order[i]], pts[order[(i + 1) % 4]]
            L = math.hypot(B[0] - A[0], B[1] - A[1])
            ang = math.degrees(math.atan2(B[1] - A[1], B[0] - A[0]))
            ux, uy = (B[0] - A[0]) / L, (B[1] - A[1]) / L
            t0, t1 = 6.0, L - 6.0
            nseg = int((t1 - t0) // 6.0)
            gate = (nseg // 2) if i == 2 else -1
            for k in range(nseg):
                x, y = A[0] + ux * (t0 + 6.0 * k), A[1] + uy * (t0 + 6.0 * k)
                if k == gate:
                    self.buildings.append({"asset": "bld_castle_arch", "x": x + ux * 3.0, "y": y + uy * 3.0, "z": float(self.w.zat(x + ux * 3.0, y + uy * 3.0)) - 0.4, "yaw": ang,
                                           "scale": 1.0, "name": "Castle_arch", "group": g, "tag": "ruin"})
                    continue
                if self.rng.uniform() < 0.25:
                    continue
                zmin = float(min(self.w.zat(x, y), self.w.zat(x + ux * 6.0, y + uy * 6.0)))
                sz = float(self.rng.uniform(0.5, 1.0))
                self.buildings.append({"asset": "bld_castle_wall_6m", "x": x, "y": y, "z": zmin - 0.4, "yaw": ang, "scale": 1.0, "sz": sz, "name": "Castle_wall_%02d" % nwall,
                                       "group": g, "tag": "ruin"})
                nwall += 1
        self.notes.append("Castle: 4 towers, %d wall segments" % nwall)

    def windfarm(self):
        s = self.site("Windfarm")
        if not s:
            return
        cx, cy = s["x"], s["y"]
        cand = []
        for dx in np.arange(-340.0, 341.0, 25.0):
            for dy in np.arange(-340.0, 341.0, 25.0):
                x, y = cx + dx, cy + dy
                if abs(x) > 1900 or abs(y) > 1900:
                    continue
                if self.c.road_edge.at(x, y) < 30.0 or self.w.slope_deg(x, y) > 9.0 or self.w.zat(x, y) < 20.0:
                    continue
                cand.append((float(self.w.zat(x, y)) + 0.002 * math.hypot(dx, dy) * 0 - 0.01 * math.hypot(dx, dy), x, y))
        cand.sort(reverse=True)
        chosen = []
        for _s, x, y in cand:
            if all(math.hypot(x - a, y - b) > 120.0 for a, b in chosen):
                rect = self.asset_rect("bld_wind_turbine", x, y, 270.0, 1.0)
                if self.check(rect, road_margin=30.0, max_range=3.5, bld_margin=20.0) is not None:
                    chosen.append((x, y))
            if len(chosen) >= 6:
                break
        for k, (x, y) in enumerate(chosen):
            yaw = 270.0 + float(self.rng.uniform(-8, 8))
            zs = self.w.zat(*self.asset_rect("bld_wind_turbine", x, y, yaw).grid(3.0))
            nm = self.commit("bld_wind_turbine", x, y, yaw, zs, 1.0, "Windfarm", "turbine")
            self.buildings[-1]["z"] = float(zs.max()) - 0.8        # tower flange sinks into the ground
            self.add_rotor("bld_wind_turbine_rotor", self.buildings[-1], (5.6, 0.0, 61.85), 30.0, "turbine")
        self.notes.append("Windfarm: %d/6 turbines" % len(chosen))

    def beach_huts(self):
        s = self.site("Sunset Beach")
        if not s:
            return
        n = 0
        for k in range(3):
            nm = self.search("bld_harbour_hut", s["x"] + float(self.rng.uniform(-25, 25)), s["y"] + float(self.rng.uniform(-25, 25)), self.face_road(200.0), 40.0, 6.0, 1.0,
                             "SunsetBeach", max_range=1.6)
            n += 1 if nm else 0
        # beach props around the huts (umbrellas, loungers, towels) go to the ground-cover group in placement_gen
        self.notes.append("Sunset Beach: %d huts" % n)
