"""
traffic_kit.py - tiny driver for the six traffic vehicle scripts (Tools/blender/traffic/<id>.py).

    _p = r"<project>/Tools/blender/traffic/traffic_kit.py"
    exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), globals())
    run(["traffic01_compact"], ["geometry", "uv_a", "uv_b"])     # every stage < 20 s per MCP call
    run(["traffic01_compact"], ["uv_wheels", "validate", "export"])
    save()                                                       # bpy.ops.wm.save_mainfile()

Stages: geometry (build, idempotent: removes the previous <id>_* objects first) | uv_a (Body + Glass) | uv_b (Interior) |
uv_wheels | validate | export (FBX per part + JSON sidecar in Exports/Traffic/<id>/).  Ids: traffic01_compact, traffic02_van,
traffic03_lorry, traffic04_bus, traffic05_tractor, traffic06_pickup.
"""
import os
import time
import bpy

IDS = ["traffic01_compact", "traffic02_van", "traffic03_lorry", "traffic04_bus", "traffic05_tractor", "traffic06_pickup"]


def _dir():
    return os.path.join(os.path.dirname(bpy.data.filepath), "Tools", "blender", "traffic")


def run(ids, stages):
    for vid in ids:
        path = os.path.join(_dir(), vid + ".py")
        for st in stages:
            t = time.time()
            ns = {"TRAFFIC_STAGE": st, "__name__": "traffic_run"}
            exec(compile(open(path, encoding="utf8").read(), path, "exec"), ns)
            print("[traffic_kit] %-20s %-10s %.1fs" % (vid, st, time.time() - t))


def qa_off(ids=IDS):
    """remove the temporary QA studio lights of the given vehicles"""
    for vid in ids:
        for o in [o for o in bpy.data.objects if o.name.startswith(vid + "_QA_")]:
            d = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if d is not None and d.users == 0:
                bpy.data.lights.remove(d)


def save():
    r = bpy.ops.wm.save_mainfile()
    print("[traffic_kit] save_mainfile ->", r, bpy.data.filepath)


def write_manifest():
    """Exports/Traffic/_manifest.json: one entry per vehicle (read back from the JSON sidecars)."""
    import json
    root = os.path.join(os.path.dirname(bpy.data.filepath), "Exports", "Traffic")
    items = []
    for vid in IDS:
        jp = os.path.join(root, vid, vid + ".json")
        if not os.path.exists(jp):
            continue
        d = json.load(open(jp, encoding="utf8"))
        items.append({"id": vid, "display_name": d["display_name"], "dimensions": d["dimensions"], "wheelbase": d["wheelbase"],
                      "wheel_count": d["wheel_count"], "tri_total": d["tri_counts"]["total_visual"], "json": "%s/%s.json" % (vid, vid),
                      "parts": sorted(d["files"].values())})
    with open(os.path.join(root, "_manifest.json"), "w", encoding="utf8") as fh:
        json.dump({"kit": "traffic", "count": len(items), "vehicles": items}, fh, indent=2)
    print("[traffic_kit] manifest with %d vehicles" % len(items))
