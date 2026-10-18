"""Prop catalog (agent P1 'props'): reads every FBX sidecar JSON under Exports/{Nature/Trees,Nature/Cover,Roadside,Settlements}
and exposes one normalised dict per asset.  Pure python (no `unreal`, no numpy) so the offline placement generator, props_import.py and
props_apply.py share it.

    import props_catalog as C
    cat = C.load_catalog()            # {asset_id: entry}
    C.mesh_path("tree_oak_a")         # /Game/Forza/Props/Trees/tree_oak_a/SM_tree_oak_a

Entry keys: id, cat (Trees|Cover|Roadside|Settlements), group, fbx, json, folder, mesh, dims (Blender m: x,y,z), bmin, bmax, tris, slots,
col ('none'|'box'|'convex'|'complex_simple'), hulls, nanite, wind (vertex-colour wind masks present), tags, scale (lo, hi), footprint (w, d)|None,
extra, sockets, pivot, far (asset id of the far card or None), is_far.
"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(globals().get("__file__", "Tools/ue/props_catalog.py")))))
EXPORTS = ROOT.replace("\\", "/") + "/Exports"
GAME_ROOT = "/Game/Forza/Props"
SOURCES = [("Trees", "Nature/Trees"), ("Cover", "Nature/Cover"), ("Roadside", "Roadside"), ("Settlements", "Settlements")]


def mesh_path(asset_id, cat=None):
    cat = cat or load_catalog()[asset_id]["cat"]
    return "%s/%s/%s/SM_%s" % (GAME_ROOT, cat, asset_id, asset_id)


def _entry(cat, j, fbx, jpath):
    aid = j["id"]
    dims = j.get("dimensions", {})
    if "bounds" in j:
        bmin, bmax = j["bounds"]["min"], j["bounds"]["max"]
    else:
        bmin, bmax = j.get("bounds_min", [0, 0, 0]), j.get("bounds_max", [0, 0, 0])
    col = j.get("collision", {}) or {}
    ctype = col.get("type", "none")
    hulls = col.get("hulls") or col.get("ucx_hulls") or []
    tri = j.get("tri_counts", {}) or {}
    wind = j.get("wind")
    extra = j.get("extra", {}) or {}
    nanite = j.get("nanite", j.get("nanite_ok", True))
    return {
        "id": aid, "cat": cat, "group": j.get("group") or j.get("family") or "", "fbx": fbx, "json": jpath,
        "folder": "%s/%s/%s" % (GAME_ROOT, cat, aid), "mesh": "%s/%s/%s/SM_%s" % (GAME_ROOT, cat, aid, aid),
        "dims": (dims.get("x", 0.0), dims.get("y", 0.0), dims.get("z", 0.0)), "bmin": bmin, "bmax": bmax,
        "tris": tri.get("lod0") or tri.get("mesh") or 0, "slots": list(j.get("material_slots", [])),
        "col": ctype if hulls else "none", "hulls": list(hulls), "nanite": bool(nanite),
        "wind": isinstance(wind, dict) and "R" in wind, "tags": list(j.get("biome_tags", [])),
        "scale": tuple(j.get("scale_range", [1.0, 1.0])), "footprint": tuple(extra["footprint"]) if "footprint" in extra else None,
        "extra": extra, "sockets": j.get("sockets", {}) or {}, "pivot": j.get("pivot") or j.get("origin") or "",
        "far": (j.get("far_card") or {}).get("mesh"), "is_far": False, "family": j.get("family") or j.get("group") or "",
    }


_CACHE = {}


def load_catalog():
    if _CACHE:
        return _CACHE
    for cat, sub in SOURCES:
        for jpath in sorted(glob.glob("%s/%s/*.json" % (EXPORTS, sub))):
            base = os.path.basename(jpath)
            if base.startswith("_") or "validation" in base:
                continue
            with open(jpath, encoding="utf-8") as fh:
                j = json.load(fh)
            if "id" not in j:
                continue
            fbx = jpath[:-5] + ".fbx"
            if not os.path.exists(fbx):
                continue
            e = _entry(cat, j, fbx, jpath)
            _CACHE[e["id"]] = e
            fc = j.get("far_card")
            if fc and fc.get("mesh"):
                fid = fc["mesh"]
                ffbx = os.path.dirname(jpath) + "/" + fc.get("fbx", fid + ".fbx")
                if os.path.exists(ffbx):
                    _CACHE[fid] = {
                        "id": fid, "cat": cat, "group": "far", "fbx": ffbx, "json": None, "folder": "%s/%s/%s" % (GAME_ROOT, cat, fid),
                        "mesh": "%s/%s/%s/SM_%s" % (GAME_ROOT, cat, fid, fid), "dims": (fc.get("width_m", 1.0), fc.get("width_m", 1.0), fc.get("height_m", 1.0)),
                        "bmin": [0, 0, 0], "bmax": [0, 0, 0], "tris": fc.get("tris", 4), "slots": [fc.get("material", "M_Tree_Far_" + e["id"])],
                        "col": "none", "hulls": [], "nanite": False, "wind": False, "tags": e["tags"], "scale": e["scale"], "footprint": None,
                        "extra": {}, "sockets": {}, "pivot": "ground_centre", "far": None, "is_far": True, "family": "far", "far_of": e["id"],
                    }
    return _CACHE


def by_cat(cat):
    return [e for e in load_catalog().values() if e["cat"] == cat]


if __name__ == "__main__":
    c = load_catalog()
    print(len(c), "assets;", {k: len(by_cat(k)) for k, _ in SOURCES})
