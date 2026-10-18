"""Roamline procedural texture library - generator CLI.

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools\\textures\\generate_all.py
    ... generate_all.py --only grass_lush,asphalt_new --size 1024
    ... generate_all.py --list
    ... generate_all.py --verify
    ... generate_all.py --sheets-only

Pure Python 3.13 + numpy.  Fully deterministic: every recipe is seeded from its own name.
"""
from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
if TOOLS not in sys.path:          # needed under "python -I" (no script dir on sys.path)
    sys.path.insert(0, TOOLS)

from textures import core, qa, recipes   # noqa: E402  (registers all recipes)

DEFAULT_OUT = os.path.join(ROOT, "Content", "Forza", "Textures", "Source")
CATEGORIES = ["terrain", "road", "building", "nature", "fx"]
GENERATOR_VERSION = "1.0.0"


def _work(args):
    name, size, out = args
    try:
        return core.run_recipe(name, size, out)
    except Exception:
        import traceback
        return dict(name=name, error=traceback.format_exc())


def load_manifest(path):
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def write_manifest(out, entries, size):
    path = os.path.join(out, "manifest.json")
    old = load_manifest(path)
    merged = {e["name"]: e for e in (old["sets"] if old else [])}
    for e in entries:
        merged[e["name"]] = e
    order = {c: i for i, c in enumerate(CATEGORIES)}
    sets = sorted(merged.values(), key=lambda e: (order.get(e["category"], 99), e["name"]))
    man = {
        "project": "Roamline: Open Roads",
        "generator": "Tools/textures/generate_all.py",
        "generator_version": GENERATOR_VERSION,
        "base_size": size,
        "conventions": {
            "normal_maps": "tangent space, DirectX/Unreal convention (+X right, green = down / +V)",
            "orm": "R = ambient occlusion, G = roughness, B = metallic (linear, import with sRGB off)",
            "bc": "base colour, sRGB (import with sRGB on); atlases/decals carry alpha in A",
            "height": "16-bit greyscale, 0..1, linear (white = high)",
            "data": "linear data textures (sRGB off); see per-file 'srgb' flag",
            "tile_metres": "real-world edge length in metres of one tile ([w, h] when non-uniform)",
            "albedo_values": "albedo_mean_linear is the mean linear reflectance luminance (physically plausible ranges)",
        },
        "sets": sets,
    }
    for s in man["sets"]:
        meta = core.REGISTRY.get(s["name"])
        if meta and meta["albedo"]:
            s["albedo_range"] = list(meta["albedo"])
        tm = s["tile_metres"]
        tm = tm if isinstance(tm, list) else [tm, tm]
        s["uv_repeats_per_metre"] = [round(1.0 / tm[0], 5), round(1.0 / tm[1], 5)]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)
    return man


def build_sheets(out, man, thumb=256):
    sd = os.path.join(out, "_contact_sheets")
    os.makedirs(sd, exist_ok=True)
    made = []
    for cat in CATEGORIES:
        ents = [e for e in man["sets"] if e["category"] == cat]
        if not ents:
            continue
        for mode in ("albedo", "lit"):
            # chunk big categories so sheets stay legible
            per = 15
            for ci in range(0, len(ents), per):
                chunk = ents[ci:ci + per]
                suffix = "" if len(ents) <= per else "_%d" % (ci // per + 1)
                p = os.path.join(sd, "%s_%s%s.png" % (mode, cat, suffix))
                made.append(qa.build_sheet(out, chunk, 5, thumb, mode, p))
    return made


def build_tiling(out, man):
    """2x2 tiling previews: full-size for hero (2048) tileable textures + 2x2 contact sheets of every tileable set."""
    sd = os.path.join(out, "_contact_sheets")
    os.makedirs(sd, exist_ok=True)
    for e in man["sets"]:
        if e["size"][0] >= 2048 and e.get("tileable", True) and "BC" in e["files"]:
            p = qa.tiling_preview(out, e, os.path.join(sd, "tiling2x2_%s.png" % e["name"]))
            print("tiling", p)
    for cat in CATEGORIES:
        ents = [e for e in man["sets"] if e["category"] == cat and e.get("tileable", True)
                and ("BC" in e["files"] or "N" in e["files"])]
        per = 12
        for ci in range(0, len(ents), per):
            suffix = "" if len(ents) <= per else "_%d" % (ci // per + 1)
            p = qa.tiling_sheet(out, ents[ci:ci + per], 4, 384, os.path.join(sd, "tiling2x2_sheet_%s%s.png" % (cat, suffix)))
            print("tiling sheet", p)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", action="append", help="recipe name(s), comma separated; repeatable")
    ap.add_argument("--size", type=int, default=1024, help="base tile size (hero textures use 2x)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--jobs", type=int, default=0, help="parallel processes (0 = auto)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--verify", action="store_true", help="verify the files on disk (seams, ranges)")
    ap.add_argument("--sheets-only", action="store_true")
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--tiling", action="store_true", help="also write 2x2 tiling previews for hero sets")
    args = ap.parse_args()

    if args.list:
        for n, m in sorted(core.REGISTRY.items(), key=lambda kv: (CATEGORIES.index(kv[1]["category"]), kv[0])):
            print("%-10s %-26s x%d  tile=%s m" % (m["category"], n, m["size_mult"], m["tile_m"]))
        print(len(core.REGISTRY), "recipes")
        return 0

    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, "manifest.json")

    if args.verify or args.sheets_only:
        man = load_manifest(mpath)
        if man is None:
            print("no manifest at", mpath)
            return 2
        if args.verify:
            issues = qa.verify(out, man)
            print("\n%d issue(s)" % len(issues))
            for i in issues:
                print("  -", i)
        if args.sheets_only:
            for p in build_sheets(out, man):
                print("sheet", p)
        if args.tiling:
            build_tiling(out, man)
        return 0

    names = sorted(core.REGISTRY)
    if args.only:
        want = [x for chunk in args.only for x in chunk.split(",") if x]
        bad = [w for w in want if w not in core.REGISTRY]
        if bad:
            print("unknown recipes:", bad)
            return 2
        names = want
    # slowest first for better load balance
    names.sort(key=lambda n: -core.REGISTRY[n]["size_mult"])
    jobs = args.jobs or max(1, min(8, (os.cpu_count() or 4) - 1))
    jobs = min(jobs, len(names))
    t0 = time.time()
    entries, errors = [], []
    work = [(n, args.size, out) for n in names]
    if jobs <= 1:
        results = map(_work, work)
    else:
        ctx = mp.get_context("spawn")
        pool = ctx.Pool(jobs)
        results = pool.imap_unordered(_work, work, chunksize=1)
    for r in results:
        if "error" in r:
            errors.append(r)
            print("FAILED %s\n%s" % (r["name"], r["error"]))
        else:
            entries.append(r)
            print("  %-26s %5d px  %6.1fs" % (r["name"], r["size"][0], r["gen_seconds"]), flush=True)
    if jobs > 1:
        pool.close()
        pool.join()
    man = write_manifest(out, entries, args.size)
    print("generated %d sets in %.1fs (%d failed)" % (len(entries), time.time() - t0, len(errors)))
    if not args.no_sheets:
        for p in build_sheets(out, man):
            pass
        print("contact sheets written")
    if args.tiling:
        build_tiling(out, man)
    return 1 if errors else 0


if __name__ == "__main__":
    mp.freeze_support()
    sys.exit(main())
