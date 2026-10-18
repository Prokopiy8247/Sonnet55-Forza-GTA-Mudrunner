"""world_holecheck - are the landscape holes (tunnel mouths) really open?  Read-only, runs inside the editor (job server).

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_holecheck.py -TimeoutSec 900 -Args0 "map=/Game/Forza/Maps/L_HoleTest"

For every rectangle of Exports/Roads/chunks.json -> landscape_holes: Roam_Wheel line trace straight down at the rectangle centre (+-1.5 m along the
road) and at 12 m to the side (outside the hole).  Expected: centre = no hit with the Landscape (the tunnel portal mesh may be hit when the road
chunks are in the map: the hit actor is printed), side = hit on the Landscape.  Marker: ROAM_HOLECHECK.
"""
import json
import math
import sys

import unreal

_HERE = unreal.Paths.project_dir().replace("\\", "/") + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import world_lib as W  # noqa: E402

ARGS = globals().get("JOB_ARGS", "") or ""
MAP = W.MAP_MAIN
for tok in ARGS.split():
    if tok.startswith("map="):
        MAP = tok.split("=", 1)[1]


def say(msg):
    unreal.log("ROAM_HOLECHECK " + str(msg))


def trace(world, x_cm, y_cm, z_top_cm):
    start = unreal.Vector(x_cm, y_cm, z_top_cm)
    end = unreal.Vector(x_cm, y_cm, z_top_cm - 200000.0)
    hit = unreal.SystemLibrary.line_trace_single(world, start, end, unreal.TraceTypeQuery.ECC_ROAM_WHEEL, False, [], unreal.DrawDebugTrace.NONE, True)
    if not hit:
        return None
    t = hit.to_tuple()
    actor = t[9]
    return (t[5].z / 100.0, actor.get_actor_label() if actor else "?")


def main():
    short = MAP.rsplit("/", 1)[1]
    world = W.get_world()
    if world is None or world.get_name() != short:
        ok = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(MAP)
        say("load_level %s ok=%s" % (MAP, ok))
        world = W.get_world()
    man = json.load(open(W.ROOT + "Exports/Roads/chunks.json", "r", encoding="utf-8"))
    bad = 0
    for h in man.get("landscape_holes", []):
        cx, cy = h["centre_ue_m"][0], h["centre_ue_m"][1]
        a = math.radians(h["heading_deg"])
        ax, ay = math.cos(a), math.sin(a)
        nx, ny = -ay, ax
        ground = unreal.RoamWorldBuilder.sample_landscape(world, cx * 100.0, cy * 100.0)
        gz = ground.get_editor_property("height_cm") if ground.get_editor_property("valid") else None
        top = (gz if gz is not None else 50000.0) + 5000.0
        res = {}
        for label, along, lat in (("centre", 0.0, 0.0), ("along-1.5", -1.5, 0.0), ("along+1.5", 1.5, 0.0), ("side12", 0.0, 12.0), ("side-12", 0.0, -12.0)):
            x = (cx + ax * along + nx * lat) * 100.0
            y = (cy + ay * along + ny * lat) * 100.0
            r = trace(world, x, y, top)
            res[label] = r
        hit_names = {k: (None if v is None else "%s@%.1f" % (v[1], v[0])) for k, v in res.items()}
        landscape = lambda v: v is not None and str(v[1]).startswith("Landscape")
        centre_open = not (landscape(res["centre"]) or landscape(res["along-1.5"]) or landscape(res["along+1.5"]))
        sides_hit = landscape(res["side12"]) and landscape(res["side-12"])
        if not (centre_open and sides_hit):
            bad += 1
        say("%s at (%.0f, %.0f) landscape_z=%s centre_open=%s sides_hit=%s %s" % (h["chunk"], cx, cy, None if gz is None else round(gz / 100.0, 2), centre_open, sides_hit, hit_names))
    say("DONE rects=%d not_as_expected=%d map=%s" % (len(man.get("landscape_holes", [])), bad, MAP))


main()
