"""
verify_roads.py - plain-Python (numpy only) acceptance report of the road geometry, no Blender needed.

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools\\blender\\world\\verify_roads.py [--no-manifest]

Regenerates every chunk with roadbuild.py (same code the Blender session runs) and checks:
  * Exports/Roads/chunks.json exists, lists every chunk, every FBX file exists and the triangle counts agree with a fresh build;
  * no NaN / Inf in positions or UVs, no zero-area triangles above a small tolerance, UV4 channels present;
  * budgets: whole network < 4 M triangles, per-chunk <= 40 k;
  * fit to the carved terrain (Content/Forza/World/Source/heightmap_4033.r16): road surfaces stay above the bed, junction pads are
    never buried;
  * structure facts: bridge / tunnel / junction counts, Great Bay Bridge length, landscape holes.
The surface-Z-equals-profile check on the real Blender meshes (ray casts) is build_roads.validate() inside Blender.
Exit status 0 = all checks passed.
"""
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import roadbuild as rb
import roadgeo as rg


def main(check_manifest=True):
    t0 = time.time()
    fails = []
    plan = rb.make_plan()
    hm = plan["hm"]
    chunks = plan["chunks"]
    print("chunks planned: %d  (%s)" % (len(chunks), {k: sum(1 for c in chunks if c["kind"] == k) for k in ("road", "junction", "bridge", "tunnel")}))
    man = None
    mpath = os.path.join(rb.ROOT, "Exports", "Roads", "chunks.json")
    if check_manifest:
        if not os.path.exists(mpath):
            fails.append("manifest missing: " + mpath)
        else:
            man = json.load(open(mpath, "r", encoding="utf8"))
    by_id = {r["id"]: r for r in man["chunks"]} if man else {}
    tot = 0
    worst_degen = 0
    maxtri = 0
    recs = {}
    for c in chunks:
        data, extra = rb.chunk_data(plan, c)
        rec = rb.chunk_record(c, data, extra)
        recs[c["id"]] = (data, rec)
        V, F = data["V"], data["F"]
        if not (np.isfinite(V).all() and all(np.isfinite(u).all() for u in data["UV"])):
            fails.append("non-finite data in " + c["id"])
        if len(data["UV"]) != 4:
            fails.append("UV channel count != 4 in " + c["id"])
        nrm = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        degen = int((np.linalg.norm(nrm, axis=1) < 2e-9).sum())
        worst_degen = max(worst_degen, degen)
        if degen > 0.002 * len(F) + 4:
            fails.append("%s: %d degenerate triangles" % (c["id"], degen))
        tot += rec["tris"]
        maxtri = max(maxtri, rec["tris"])
        if rec["tris"] > 40000:
            fails.append("%s: %d tris > 40k" % (c["id"], rec["tris"]))
        if man:
            m = by_id.get(c["id"])
            if m is None:
                fails.append("not in manifest: " + c["id"])
            else:
                if m["tris"] != rec["tris"]:
                    fails.append("%s: manifest tris %d != rebuilt %d (re-run build_roads.write_manifest)" % (c["id"], m["tris"], rec["tris"]))
                fbx = os.path.join(rb.ROOT, m["fbx"].replace("/", os.sep))
                if not os.path.exists(fbx) or os.path.getsize(fbx) < 1000:
                    fails.append("FBX missing / empty: " + m["fbx"])
    if man and len(man["chunks"]) != len(chunks):
        fails.append("manifest has %d chunks, plan has %d" % (len(man["chunks"]), len(chunks)))
    tris = [recs[c["id"]][1]["tris"] for c in chunks]
    print("triangles: total %d (budget 4 000 000), per chunk min %d / mean %d / max %d; below 8k: %d chunks" % (
        tot, min(tris), np.mean(tris), maxtri, sum(1 for t in tris if t < 8000)))
    if tot >= 4000000:
        fails.append("triangle budget exceeded")
    # ---- fit of the road surfaces to the carved terrain
    if hm is not None:
        diffs = []
        for rid, r in plan["roads"].items():
            s = np.arange(0.0, r.L, 3.0)
            fr = r.at(s)
            excl = (np.round(np.interp(s, r.s, r.flags)).astype(int) & 3) != 0
            for (a, b, _) in r.trims:
                excl |= (s >= a - 1) & (s <= b + 1)
            for d in (-0.95 * r.B, -0.5 * r.P, 0.0, 0.5 * r.P, 0.95 * r.B):
                zs = fr["z"] - d * np.tan(fr["bank"]) + rg._crown(r, abs(d))
                zt = hm.z_bl(fr["x"] + fr["ty"] * d, fr["y"] - fr["tx"] * d)
                diffs.append((zs - zt)[~excl])
        v = np.concatenate(diffs)
        print("road surface minus terrain (m): p1 %.3f p5 %.3f p50 %.3f p95 %.3f; buried > 5 cm: %.2f %%, > 30 cm: %.3f %% (hairpin apexes / "
              "junction shoulders of the carve)" % (np.percentile(v, 1), np.percentile(v, 5), np.percentile(v, 50), np.percentile(v, 95),
                                                    100 * (v < -0.05).mean(), 100 * (v < -0.30).mean()))
        if (v < -0.30).mean() > 0.002:
            fails.append("too many road samples buried by more than 30 cm")
        pv = []
        for c in chunks:
            if c["kind"] != "junction":
                continue
            data, rec = recs[c["id"]]
            V, F, M = data["V"], data["F"], data["M"]
            tri = V[F]
            n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            nn = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)
            T = tri[(nn[:, 2] > 0.9) & (M == rg.ASPH)]
            rng = np.random.default_rng(1)
            r1, r2 = rng.random(len(T)), rng.random(len(T))
            a, b, cc = 1 - np.sqrt(r1), np.sqrt(r1) * (1 - r2), np.sqrt(r1) * r2
            P = T[:, 0] * a[:, None] + T[:, 1] * b[:, None] + T[:, 2] * cc[:, None]
            pv.append(P[:, 2] - hm.z_bl(P[:, 0], P[:, 1]))
        pv = np.concatenate(pv)
        print("junction pads minus terrain (m): min %.3f p5 %.3f p50 %.3f p95 %.3f max %.3f; buried > 10 cm: %.3f %%" % (
            pv.min(), np.percentile(pv, 5), np.percentile(pv, 50), np.percentile(pv, 95), pv.max(), 100 * (pv < -0.10).mean()))
        if (pv < -0.10).mean() > 0.001:
            fails.append("junction pads are buried by the terrain")
    # ---- structures
    br = [recs[c["id"]][1] for c in chunks if c["kind"] == "bridge"]
    gb = [b for b in br if b.get("style") == "cable"]
    print("bridges: %d chunks, styles %s; Great Bay Bridge length %.1f m, %d pylons" % (
        len(br), sorted(set(b["style"] for b in br)), gb[0]["length"] if gb else 0.0, sum(len(b["pylons"]) for b in gb)))
    if not gb:
        fails.append("no cable-stayed hero bridge")
    tn = [recs[c["id"]][1] for c in chunks if c["kind"] == "tunnel"]
    holes = sum(len(t.get("landscape_holes", [])) for t in tn)
    print("tunnels: %d, portals %d, landscape holes %d" % (len(tn), sum(len(t["portals"]) for t in tn), holes))
    db = [(b["id"], r) for b in br for r in b.get("deck_buried", {}).get("ranges", [])]
    print("bridge ends where the natural terrain stands above the deck: %d ranges, worst %.2f m (needs Landscape holes or a carve fix)" % (
        len(db), max([r["max_m"] for _, r in db] or [0.0])))
    ta = [(r["id"], x) for r in (recs[c["id"]][1] for c in chunks if c["kind"] == "road") for x in r.get("terrain_above_road", [])]
    print("road ranges with terrain > 10 cm above the surface (carve deviations): %d, %.0f m in total, worst %.2f m" % (
        len(ta), sum(x["s1"] - x["s0"] + 1 for _, x in ta), max([x["max_m"] for _, x in ta] or [0.0])))
    if man:
        hv = man.get("landscape_hole_vertices", {})
        print("manifest hole vertices: %d" % hv.get("count", 0))
    print("done in %.1f s" % (time.time() - t0))
    if fails:
        print("FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main("--no-manifest" not in sys.argv))
