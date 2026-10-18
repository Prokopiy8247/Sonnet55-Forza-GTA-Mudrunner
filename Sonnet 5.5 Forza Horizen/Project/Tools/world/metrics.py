"""Acceptance metrics (self-check) computed on the FINAL quantised data (heightmap read back from the r16 encoding)."""
import numpy as np

import roads_def as RD
import profile as PR
import align as AL
import worlddef as W
from common import HALF, sample_bilinear, log
import export as EX


def _runs_len(mask, ds):
    return [(b - a + 1) * ds for a, b in PR.runs(mask)]


def compute(H, roads, nodes, region_land_frac, loop_chain=EX.LOOP_CHAIN, near_road_mask=None):
    m = {}
    byid = {r["id"]: r for r in roads}
    total = sum(r["s"][-1] for r in roads)
    m["total_length_km"] = round(total / 1000, 3)
    bycls = {}
    for r in roads:
        bycls[r["cls"]] = bycls.get(r["cls"], 0.0) + r["s"][-1] / 1000
    m["length_km_by_class"] = {k: round(v, 3) for k, v in sorted(bycls.items())}
    # loop
    loop_len = sum(byid[i]["s"][-1] for i in loop_chain)
    closed = all(byid[loop_chain[i]]["defn"]["end"] == byid[loop_chain[(i + 1) % len(loop_chain)]]["defn"]["start"] for i in range(len(loop_chain)))
    # also verify geometric closure: end point of each road == start point of the next
    geo_ok = True
    for i in range(len(loop_chain)):
        a = byid[loop_chain[i]]["xy"][-1]
        b = byid[loop_chain[(i + 1) % len(loop_chain)]]["xy"][0]
        if np.linalg.norm(a - b) > 1.0:
            geo_ok = False
    m["loop_length_km"] = round(loop_len / 1000, 3)
    m["loop_closed"] = bool(closed and geo_ok)
    m["loop_ge_22km"] = bool(loop_len >= 22000)
    # uninterrupted stretch: a single road without an interior junction node and without tunnel / bridge-free requirement not needed
    interior = {}
    for name, nd in nodes.items():
        for c in nd["conns"]:
            L = byid[c["road"]]["s"][-1]
            if 5.0 < c["s"] < L - 5.0:
                interior.setdefault(c["road"], []).append(c["s"])
    best = 0.0
    best_id = None
    for r in roads:
        L = r["s"][-1]
        cuts = sorted([0.0] + [s for s in interior.get(r["id"], [])] + [L])
        tun = (r["flags"] & PR.FLAG_TUNNEL) > 0
        tcuts = [r["s"][a] for a, b in PR.runs(tun)] + [r["s"][b] for a, b in PR.runs(tun)]
        cuts = sorted(cuts + tcuts)
        for a, b in zip(cuts[:-1], cuts[1:]):
            if r["cls"] in ("HIGHWAY", "REGIONAL") and b - a > best:
                best = b - a
                best_id = r["id"]
    m["longest_uninterrupted_km"] = round(best / 1000, 3)
    m["longest_uninterrupted_road"] = best_id
    m["longest_uninterrupted_ge_5km"] = bool(best >= 5000)
    m["hwy_east_length_km"] = round(byid["HWY_EAST"]["s"][-1] / 1000, 3)
    # grade / radius per class
    gmax = {}
    gp99 = {}
    glim = {}
    rmin = {}
    rmin_hp = {}
    rmin_nonhp = {}
    for cls in sorted(set(r["cls"] for r in roads)):
        gs = []
        rs = []
        rs_hp = []
        rs_nh = []
        for r in roads:
            if r["cls"] != cls:
                continue
            ok = (r["flags"] & (PR.FLAG_TUNNEL)) == 0
            g = np.abs(r["grade"])
            # grade statistics use every sample (also the node pins); radius excludes only the first / last 3 samples
            # (curvature estimate at the polyline ends)
            sl = np.ones(len(g), dtype=bool)
            sl[:3] = False
            sl[-3:] = False
            gs.append(g)
            k = np.abs(AL.curvature(r["xy"], r["s"], 6.0))
            rad = 1.0 / np.maximum(k, 1e-9)
            rs.append(rad[sl])
            hp = (r["flags"] & PR.FLAG_HAIRPIN) > 0
            rs_hp.append(rad[sl & hp])
            rs_nh.append(rad[sl & ~hp])
        gs = np.concatenate(gs)
        rs = np.concatenate(rs)
        gmax[cls] = round(float(gs.max()), 4)
        gp99[cls] = round(float(np.percentile(gs, 99)), 4)
        glim[cls] = RD.CLASSES[cls]["g_max"]
        rmin[cls] = round(float(rs.min()), 1)
        rh = np.concatenate(rs_hp) if rs_hp else np.zeros(0)
        rn = np.concatenate(rs_nh) if rs_nh else np.zeros(0)
        rmin_hp[cls] = round(float(rh.min()), 1) if len(rh) else None
        rmin_nonhp[cls] = round(float(rn.min()), 1) if len(rn) else None
    m["grade_max_by_class"] = gmax
    m["grade_p99_by_class"] = gp99
    m["grade_limit_by_class"] = glim
    m["grade_ok"] = bool(all(gmax[c] <= glim[c] * 1.005 for c in gmax))
    m["min_radius_by_class"] = rmin
    m["min_radius_hairpin_by_class"] = rmin_hp
    m["min_radius_nonhairpin_by_class"] = rmin_nonhp
    ok_r = True
    for cls in rmin:
        lim_nh = RD.CLASSES[cls]["r_min"]
        lim_hp = RD.CLASSES[cls]["r_hair"]
        if rmin_nonhp[cls] is not None and rmin_nonhp[cls] < lim_nh * 0.985:
            ok_r = False
        if rmin_hp[cls] is not None and rmin_hp[cls] < lim_hp * 0.985:
            ok_r = False
    m["min_radius_ok"] = bool(ok_r)
    # connectivity
    parent = {r["id"]: r["id"] for r in roads}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for name, nd in nodes.items():
        ids = [c["road"] for c in nd["conns"]]
        for a in ids[1:]:
            parent[find(a)] = find(ids[0])
    comps = len(set(find(r["id"]) for r in roads))
    m["network_components"] = comps
    m["network_connected"] = bool(comps == 1)
    m["junction_nodes"] = len(nodes)
    # bounds / terrain
    out_b = 0
    below = 0
    nsamp = 0
    for r in roads:
        xy = r["xy"]
        nsamp += len(xy)
        out_b += int((np.abs(xy[:, 0]) > 1990).sum() + (np.abs(xy[:, 1]) > 1990).sum())
        t = sample_bilinear(H, xy[:, 0], xy[:, 1])
        nb = (r["flags"] & PR.FLAG_BRIDGE) == 0
        below += int(((t < 0.5) & nb).sum())
    m["road_samples"] = nsamp
    m["samples_outside_1990"] = out_b
    m["samples_terrain_below_0p5m_nonbridge"] = below
    # bridges / tunnels
    bl = []
    tl = []
    for r in roads:
        ds = r["s"][1] - r["s"][0]
        for a, b in PR.runs((r["flags"] & PR.FLAG_BRIDGE) > 0):
            bl.append((round(float(r["s"][b] - r["s"][a]), 1), r["id"]))
        for a, b in PR.runs((r["flags"] & PR.FLAG_TUNNEL) > 0):
            tl.append((round(float(r["s"][b] - r["s"][a]), 1), r["id"]))
    m["bridge_count"] = len(bl)
    m["bridges"] = sorted(bl, reverse=True)
    m["bridges_ge_3"] = bool(len(bl) >= 3)
    big = [x for x in bl if 300 <= x[0] <= 520]
    m["great_bay_bridge_length_m"] = big[0][0] if big else None
    m["tunnel_count"] = len(tl)
    m["tunnels"] = tl
    m["tunnel_120_400"] = bool(any(120 <= x[0] <= 400 for x in tl))
    # hairpins
    hp_by_road = {}
    for r in roads:
        hp_by_road[r["id"]] = len(PR.runs((r["flags"] & PR.FLAG_HAIRPIN) > 0))
    m["hairpins_by_road"] = {k: v for k, v in hp_by_road.items() if v}
    m["hairpins_pass"] = hp_by_road.get("LOOP_PASS", 0)
    m["hairpins_pass_ge_8"] = bool(hp_by_road.get("LOOP_PASS", 0) >= 8)
    # carving consistency across the road width
    devs = []
    devj = []
    dev_by_road = {}
    drop_bad = 0
    drop_n = 0
    for r in roads:
        d0 = RD.bed_half_width(r["cls"])
        ok = ((r["flags"] & (PR.FLAG_BRIDGE | PR.FLAG_TUNNEL)) == 0)
        xy, z = r["xy"], r["z"]
        bank = np.tan(r["bank"])
        hd = np.empty_like(xy)
        hd[1:-1] = xy[2:] - xy[:-2]
        hd[0] = xy[1] - xy[0]
        hd[-1] = xy[-1] - xy[-2]
        hd /= np.maximum(np.linalg.norm(hd, axis=1, keepdims=True), 1e-9)
        rx, ry = -hd[:, 1], hd[:, 0]
        mx = np.zeros(len(z))
        for off in (-d0 * 0.9, -d0 * 0.5, 0.0, d0 * 0.5, d0 * 0.9):
            h = sample_bilinear(H, xy[:, 0] + rx * off, xy[:, 1] + ry * off)
            bed = z - 0.05 - bank * off
            mx = np.maximum(mx, np.abs(h - bed))
        junc = (r["flags"] & PR.FLAG_JUNCTION) > 0
        devs.append(mx[ok & ~junc])
        devj.append(mx[ok & junc])
        okk = ok & ~junc
        if okk.any():
            idxw = np.nonzero(okk & (mx > 0.2))[0]
            worst = []
            last = -1e9
            for q in idxw[np.argsort(-mx[idxw])][:40]:
                if all(abs(r["s"][q] - w[0]) > 30 for w in worst) and len(worst) < 3:
                    worst.append([round(float(r["s"][q]), 0), round(float(xy[q, 0]), 0), round(float(xy[q, 1]), 0), round(float(mx[q]), 2)])
            dev_by_road[r["id"]] = [round(float(mx[okk].max()), 2), round(float(np.percentile(mx[okk], 99)), 2), int((mx[okk] > 0.2).sum()), worst]
        # floating embankment check: terrain 2.5 m beyond the bed edge must not drop more than 1:1.2 below the edge
        for side in (1.0, -1.0):
            off = side * (d0 + 2.5)
            h = sample_bilinear(H, xy[:, 0] + rx * off, xy[:, 1] + ry * off)
            edge = z - 0.05 - bank * side * d0
            drop = edge - h
            drop_n += int(ok.sum())
            drop_bad += int(((drop > 2.5 / 1.2) & ok).sum())
    dv = np.concatenate(devs)
    dj = np.concatenate(devj) if devj else np.zeros(1)
    m["carve_dev_junction_zones_max_m"] = round(float(dj.max()), 3)
    m["carve_dev_junction_zones_p99_m"] = round(float(np.percentile(dj, 99)), 3)
    m["carve_dev_by_road_max_p99_n"] = dev_by_road
    m["carve_dev_max_m"] = round(float(dv.max()), 3)
    m["carve_dev_p99_m"] = round(float(np.percentile(dv, 99)), 3)
    m["carve_dev_p999_m"] = round(float(np.percentile(dv, 99.9)), 3)
    m["carve_samples_over_0p2m"] = int((dv > 0.2).sum())
    m["carve_fraction_within_0p2m"] = round(float((dv <= 0.2).mean()), 5)
    m["carve_consistent"] = bool((dv > 0.2).sum() <= 0.002 * len(dv))
    m["embankment_samples_steeper_than_1_to_1p2"] = drop_bad
    # heightmap
    m["heightmap_min_m"] = round(float(H.min()), 2)
    m["heightmap_max_m"] = round(float(H.max()), 2)
    m["heightmap_range_ok"] = bool(H.min() >= -60 and H.max() <= 760)
    # spikes: gradient over the whole map
    gy, gx = np.gradient(H)
    g = np.sqrt(gx * gx + gy * gy)
    if near_road_mask is not None:
        gm = g[near_road_mask]
        m["gradient_near_roads_max"] = round(float(gm.max()), 2)
        m["gradient_near_roads_p999"] = round(float(np.percentile(gm[::3], 99.9)), 3)
        m["gradient_near_roads_p99"] = round(float(np.percentile(gm[::3], 99.0)), 3)
    m["gradient_max"] = round(float(g.max()), 2)
    m["gradient_p9999"] = round(float(np.percentile(g[::2, ::2], 99.99)), 3)
    m["region_land_fraction"] = region_land_frac
    m["regions_visible"] = bool(all(v > 0.05 for v in region_land_frac.values()))
    return m


def report(m):
    ok = lambda b: "PASS" if b else "FAIL"
    lines = []
    lines.append(("Total drivable road length 40-60 km", "%.1f km" % m["total_length_km"], 40 <= m["total_length_km"] <= 60))
    lines.append(("LOOP closed, >= 22 km", "%.1f km, closed=%s" % (m["loop_length_km"], m["loop_closed"]), m["loop_closed"] and m["loop_ge_22km"]))
    lines.append(("Uninterrupted >= 5 km (HWY_EAST)", "%.2f km (%s), HWY_EAST %.2f km" % (m["longest_uninterrupted_km"], m["longest_uninterrupted_road"], m["hwy_east_length_km"]), m["longest_uninterrupted_ge_5km"]))
    lines.append(("Max grade per class", ", ".join("%s %.1f%%/%.0f%%" % (c, 100 * m["grade_max_by_class"][c], 100 * m["grade_limit_by_class"][c]) for c in m["grade_max_by_class"]), m["grade_ok"]))
    lines.append(("Min radius per class", ", ".join("%s %.0f" % (c, v) for c, v in m["min_radius_by_class"].items()), m["min_radius_ok"]))
    lines.append(("One connected network", "%d component(s), %d nodes" % (m["network_components"], m["junction_nodes"]), m["network_connected"]))
    lines.append(("Samples outside +-1990 m / terrain < 0.5 m", "%d / %d" % (m["samples_outside_1990"], m["samples_terrain_below_0p5m_nonbridge"]),
                  m["samples_outside_1990"] == 0 and m["samples_terrain_below_0p5m_nonbridge"] == 0))
    lines.append(("Bridges >= 3 (incl. Great Bay ~300-450 m)", "%d, longest %s" % (m["bridge_count"], m["bridges"][0] if m["bridges"] else None), m["bridges_ge_3"] and m["great_bay_bridge_length_m"] is not None))
    lines.append(("Tunnels >= 1 (120-400 m)", "%d %s" % (m["tunnel_count"], m["tunnels"][:3]), m["tunnel_count"] >= 1 and m["tunnel_120_400"]))
    lines.append(("Hairpins on the pass >= 8", "%d (LOOP_PASS)" % m["hairpins_pass"], m["hairpins_pass_ge_8"]))
    lines.append(("Carving |terrain-bed| < 0.2 m", "max %.2f p99 %.3f, %.3f%% within" % (m["carve_dev_max_m"], m["carve_dev_p99_m"], 100 * m["carve_fraction_within_0p2m"]), m["carve_consistent"]))
    lines.append(("Heightmap range -60..760 m", "%.1f .. %.1f" % (m["heightmap_min_m"], m["heightmap_max_m"]), m["heightmap_range_ok"]))
    lines.append(("Region coverage (4 biomes + hub)", ", ".join("%s %.0f%%" % (k, 100 * v) for k, v in m["region_land_fraction"].items()), m["regions_visible"]))
    for name, val, good in lines:
        log("  [%s] %-46s %s" % (ok(good), name, val))
    return lines
