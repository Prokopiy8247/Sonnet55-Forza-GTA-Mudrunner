"""Entry point: builds the whole world (terrain, road network, carving, layers, exports, previews, metrics).

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools\\world\\build_world.py            # full build (~5-8 min)
    ... build_world.py --fast                                                          # quick design build (macro 4 m, no 1 m detail)
Python 3.13 + numpy only. Deterministic (fixed seeds).
"""
import argparse
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np

import worlddef as W
import roads_def as RD
import terrain as T
import roadplan as RP
import network as NW
import carve as CV
import layers as LY
import export as EX
import metrics as MT
import previews as PV
import profile as PR
from common import (N, HALF, ensure_dirs, OUT_DIR, SOURCE_DIR, PREVIEW_DIR, CACHE_DIR, log, log_mem, sample_bilinear, M_PER_UNIT)
from pngio import write_png


def nearest_up(A, step):
    """nearest-neighbour resample of a macro grid (step m) to the 1 m grid"""
    idx = np.clip(np.rint(np.arange(N) / step).astype(int), 0, A.shape[0] - 1)
    return A[np.ix_(idx, idx)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast", action="store_true", help="macro step 4 m, no 1 m detail noise (design iterations)")
    ap.add_argument("--no-previews", action="store_true")
    ap.add_argument("--no-write", action="store_true", help="skip the large raw files")
    args = ap.parse_args()
    t_start = time.time()
    ensure_dirs()
    step = 4.0 if args.fast else 2.0
    log("== terrain (macro step %.0f m)" % step)
    corr = RD.corridors()
    M = T.build_macro(step=step, corridors=corr, trace_corridors=RD.trace_corridors())
    log_mem("after build_macro")
    H1 = T.finalize_1m(M) if not args.fast else T.resize_to(M["H"], step, 1.0)
    water1 = nearest_up(M["water_river"], step)
    log("natural terrain: %.1f .. %.1f m" % (H1.min(), H1.max()))
    log_mem("after finalize_1m")

    log("== road network")
    grid = RP.PlanGrid.from_h1(H1, water1)
    roads = NW.build_alignments(grid, dict(RD.NODES))
    nodes, created = NW.build_nodes(roads)
    # mountain / dirt roads: gullies are filled and spurs shaved along the road (smooth the terrain near the alignment)
    smooth_lines = [rr_["al"]["xy"] for rid_, rr_ in roads.items() if rr_["defn"]["cls"] in ("MOUNTAIN", "DIRT")]
    T.bench_slopes(H1, smooth_lines)
    T.smooth_road_corridors(H1, smooth_lines, sigma_m=14.0, full=30.0, fade=110.0)
    # designed tunnels: a rocky shoulder (ridge bump) is raised over each straight tunnel chord so the bore has real cover
    for rid_, rr_ in roads.items():
        for rg in rr_["plan"].get("ridges", []):
            T.add_tunnel_ridge(H1, rg["A"], rg["B"], rg["h"])
            log("  tunnel ridge on %s: chord (%.0f,%.0f)-(%.0f,%.0f), +%.0f m" % (rid_, rg["A"][0], rg["A"][1], rg["B"][0], rg["B"][1], rg["h"]))
    for (a, b, p) in created:
        log("  auto crossing node %s x %s at (%.0f, %.0f)" % (a, b, p[0], p[1]))
    NW.solve_profiles(roads, nodes, H1, water1, M["streams"])
    out = NW.finalize_roads(roads, nodes, created)
    del grid
    log_mem("after road planning")

    log("== road table")
    for rd in out:
        c_ = RD.CLASSES[rd["cls"]]
        g_ = np.abs(rd["grade"])
        nb = len(PR.runs((rd["flags"] & PR.FLAG_BRIDGE) > 0))
        nt = len(PR.runs((rd["flags"] & PR.FLAG_TUNNEL) > 0))
        nc = len(PR.runs((rd["flags"] & PR.FLAG_CULVERT) > 0))
        nh = len(PR.runs((rd["flags"] & PR.FLAG_HAIRPIN) > 0))
        flag = "  <-- GRADE" if g_.max() > c_["g_max"] * 1.003 else ""
        rs_ = roads[rd["id"]]["prof"]["reasons"]
        dsr = roads[rd["id"]]["al"]["s"][1] - roads[rd["id"]]["al"]["s"][0]
        why = " ".join("%s=%d" % (k_, int(v_.sum() * dsr)) for k_, v_ in rs_.items() if v_.sum() * dsr >= 1)
        if why:
            flag += "  [bridge m: %s]" % why
        log("  %-16s %-9s %7.0f m  max grade %.3f (lim %.2f)  bridges %d tunnels %d culverts %d hairpins %d%s" % (
            rd["id"], rd["cls"], rd["s"][-1], g_.max(), c_["g_max"], nb, nt, nc, nh, flag))
    log("== carving")
    res = CV.carve(H1, out, verbose=False)
    H2 = res["H"]
    h16 = EX.height_to_h16(H2)
    Hq = EX.h16_to_height(h16)
    log("carved terrain: %.1f .. %.1f m" % (Hq.min(), Hq.max()))
    if os.environ.get("DEV_DUMP"):
        import pickle
        np.save(os.path.join(PREVIEW_DIR, "dev_build_H.npy"), Hq[::4, ::4].copy())
        np.save(os.path.join(PREVIEW_DIR, "dev_build_H1m.npy"), Hq)
        np.save(os.path.join(PREVIEW_DIR, "dev_build_Hnat.npy"), H1[::4, ::4].copy())
        with open(os.path.join(PREVIEW_DIR, "dev_build_roads.pkl"), "wb") as f_:
            pickle.dump([dict(id=r["id"], cls=r["cls"], xy=r["xy"], z=r["z"], flags=r["flags"], s=r["s"], terrain=r["terrain"]) for r in out], f_)
    log_mem("after carving")

    log("== layers")
    layers, dens, slope = LY.build_layers(M, Hq, res)
    region1 = nearest_up(M["region"], step)
    log_mem("after layers")

    # site elevations + computed positions
    # the "Highcrest Tunnel" site is the midpoint of the longest generated tunnel (bed height of the road there)
    best_t = None
    for rd in out:
        for a, b in PR.runs((rd["flags"] & PR.FLAG_TUNNEL) > 0):
            if best_t is None or rd["s"][b] - rd["s"][a] > best_t[0]:
                m = (a + b) // 2
                best_t = (float(rd["s"][b] - rd["s"][a]), float(rd["xy"][m][0]), float(rd["xy"][m][1]), float(rd["z"][m]))
    sites = []
    site_z = []
    for (nm, kind, X, Y) in W.SITES:
        if nm == "Highcrest Tunnel" and best_t is not None:
            X, Y = best_t[1], best_t[2]
            site_z.append(best_t[3])
        else:
            site_z.append(float(sample_bilinear(Hq, X, Y)))
        sites.append((nm, kind, X, Y))

    log("== metrics")
    land = Hq > 0.3
    rf = {}
    tot_land = float(land.sum())
    for k, name in zip(range(5), ("Greenvale", "Highcrest", "Plateau", "Coast", "Basin")):
        rf[name] = round(float(((region1 == k) & land).sum()) / tot_land, 4)
    # region around roads (cut/fill zone) excluding tunnel portal headwalls
    near = res["touched"] & (res["emin"] > 0.4)
    for rd in out:
        for a, b in PR.runs((rd["flags"] & PR.FLAG_TUNNEL) > 0):
            for k in (a, b):
                px_, py_ = rd["xy"][k]
                i0_, i1_ = int(px_ + HALF - 60), int(px_ + HALF + 60)
                j0_, j1_ = int(py_ + HALF - 60), int(py_ + HALF + 60)
                near[max(j0_, 0):j1_, max(i0_, 0):i1_] = False
    metrics = MT.compute(Hq, out, nodes, rf, near_road_mask=near)
    metrics["build_seconds_so_far"] = round(time.time() - t_start, 1)
    EX.write_json(os.path.join(OUT_DIR, "road_metrics.json"), metrics, indent=1)
    MT.report(metrics)

    log_mem("after metrics")
    log("== export")
    files = {}
    if not args.no_write:
        EX.write_raw(os.path.join(SOURCE_DIR, "heightmap_4033.r16"), h16)
        files["heightmap_4033.r16"] = os.path.getsize(os.path.join(SOURCE_DIR, "heightmap_4033.r16"))
        for L in W.LAYERS:
            p = os.path.join(SOURCE_DIR, "layer_%s.r8" % L)
            EX.write_raw(p, layers[L])
            files["layer_%s.r8" % L] = os.path.getsize(p)
        for k, v in dens.items():
            p = os.path.join(SOURCE_DIR, "density_%s.r8" % k)
            EX.write_raw(p, v)
            files["density_%s.r8" % k] = os.path.getsize(p)
        slope_deg = np.degrees(np.arctan(slope))
        EX.write_raw(os.path.join(SOURCE_DIR, "slope.r8"), np.clip(np.rint(slope_deg * 255.0 / 90.0), 0, 255).astype(np.uint8))
        EX.write_raw(os.path.join(SOURCE_DIR, "region_id.r8"), region1.astype(np.uint8))
        files["slope.r8"] = N * N
        files["region_id.r8"] = N * N
    roads_obj = EX.write_roads_json(os.path.join(OUT_DIR, "roads.json"), out, nodes)
    files["roads.json"] = os.path.getsize(os.path.join(OUT_DIR, "roads.json"))
    EX.write_river_json(os.path.join(OUT_DIR, "river.json"), M)
    EX.write_world_meta(os.path.join(OUT_DIR, "world_meta.json"), files, dict(site_z=site_z, sites=sites, build=dict(
        macro_step_m=step, detail_noise=(not args.fast), seed=T.SEED, numpy=np.__version__, python=sys.version.split()[0])))
    for f in ("world_meta.json", "roads.json", "river.json", "road_metrics.json"):
        shutil.copyfile(os.path.join(OUT_DIR, f), os.path.join(SOURCE_DIR, f))
    # grayscale 16-bit PNG of the heightmap for quick inspection / alternative import
    if not args.no_write and not args.fast:
        write_png(os.path.join(OUT_DIR, "heightmap_4033_16bit.png"), h16, level=3)

    if not args.no_previews:
        log("== previews")
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        byid = {r["id"]: r for r in out}
        PV.overview(Hq, M, out, nodes, sites, os.path.join(PREVIEW_DIR, "overview_1008.png"))
        # per-route zooms
        PV.route_zoom(Hq, out, nodes, (100, 1500, -1950, -420), os.path.join(PREVIEW_DIR, "route_highcrest_switchbacks.png"), step=2,
                      rid_filter=["LOOP_PASS", "LOOP_DESC", "PASS_SPUR", "LOCAL_FROST", "LOOP_VALLEY"], label="HIGHCREST SWITCHBACKS")
        PV.route_zoom(Hq, out, nodes, (-300, 1950, -300, 1300), os.path.join(PREVIEW_DIR, "route_hwy_plateau.png"), step=2,
                      rid_filter=["HWY_EAST", "DIRT_WASH", "LOCAL_PGAS", "LOOP_DESC"], label="HWY EAST AND PLATEAU")
        PV.route_zoom(Hq, out, nodes, (-1500, 100, 700, 2000), os.path.join(PREVIEW_DIR, "route_coast_bridge.png"), step=2,
                      rid_filter=None, label="COAST AND GREAT BAY BRIDGE")
        PV.route_zoom(Hq, out, nodes, (-1700, -300, -1800, -400), os.path.join(PREVIEW_DIR, "route_greenvale.png"), step=2,
                      rid_filter=None, label="GREENVALE", hairpins=False)
        PV.profile_strip([byid[i] for i in EX.LOOP_CHAIN], os.path.join(PREVIEW_DIR, "profile_LOOP.png"), "LOOP ELEVATION PROFILE")
        PV.profile_strip([byid["PASS_SPUR"]], os.path.join(PREVIEW_DIR, "profile_PASS_SPUR.png"), "PASS_SPUR ELEVATION PROFILE")
        PV.slope_preview(Hq, slope, os.path.join(PREVIEW_DIR, "slope_map.png"))
        PV.grade_histogram(out, os.path.join(PREVIEW_DIR, "grade_histogram.png"))
        PV.layers_preview(layers, dens, Hq, os.path.join(PREVIEW_DIR, "layers_preview.png"))
    log_mem("end")
    log("== done in %.1f s" % (time.time() - t_start))
    return metrics


if __name__ == "__main__":
    main()
