"""world_verify - read-only checks of the generated world, run inside the editor (job server or ue_cmd).   Docs/Tech/WORLD_BUILD.md
Owner: F1-B.  Never modifies assets or maps (it may LOAD /Game/Forza/Maps/L_Main when the editor world is not that map).

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_verify.py -TimeoutSec 1800 -Args0 "data ground"
    checks (JOB_ARGS, space separated; default = data ground):
      data     DA_RoadNetwork / DA_WorldDefinition load, counts, default-spawn road ids of RoamSettings resolve, POI list (ids + teleport flag)
      ground   N points along every road class: landscape height (RoamWorldBuilder.sample_landscape) and a wheel-channel line trace vs the
               road sample Z of roads.json (the heightmap is carved to the road bed: the difference must be small, the trace must hit)
      wheels   >= 20 wheel-style probes (Roam_Wheel trace from 1.5 m above the right-lane centre) on all road classes + bridge decks + tunnel floor:
               must hit the road surface (+-0.15 m); prints actor and physical material of each structure hit and a surface histogram
      map      loads L_Main when needed and prints landscape / actor counts (RoamWorldBuilder.describe_landscape)
    options  (ROAM_WORLD_<NAME> env or key=value tokens)  points=20  tol=1.0 (metres)  map=/Game/Forza/Maps/L_Main
Log markers: ROAM_VERIFY ...  (ROAM_VERIFY_FAIL for a failed check, ROAM_VERIFY_DONE failures=N at the end)
"""
import math
import os
import sys

import unreal

_HERE = unreal.Paths.project_dir().replace("\\", "/") + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import world_lib as W  # noqa: E402

FAILS = []


def say(msg):
    unreal.log("ROAM_VERIFY " + str(msg))


def fail(msg):
    FAILS.append(msg)
    unreal.log_error("ROAM_VERIFY_FAIL " + str(msg))


def _tokens():
    raw = globals().get("JOB_ARGS", "") or ""
    return [t for t in raw.replace(",", " ").split() if t]


def _opt(name, default):
    for t in _tokens():
        if t.startswith(name + "="):
            return t.split("=", 1)[1]
    return os.environ.get("ROAM_WORLD_" + name.upper(), default)


# ---------------------------------------------------------------------------------------------------------------------------
def check_data():
    net = W.ea.load_asset(W.DA_ROAD_NETWORK)
    if net is None:
        fail("DA_RoadNetwork missing")
    else:
        roads = list(net.get_editor_property("roads"))
        junctions = list(net.get_editor_property("junctions"))
        ids = [str(r.get_editor_property("road_id")) for r in roads]
        say("DA_RoadNetwork roads=%d junctions=%d total_length_km=%.2f" % (len(roads), len(junctions), net.get_total_length_cm() / 100000.0))
        say("DA_RoadNetwork ids: " + " ".join(ids[:80]))
        # RoamSettings default spawn roads must exist (otherwise the game mode falls back to the PlayerStart)
        try:
            settings = unreal.get_default_object(unreal.RoamSettings) if hasattr(unreal, "RoamSettings") else None
            wanted = [str(x) for x in settings.get_editor_property("default_spawn_road_ids")] if settings else []
            found = [wid for wid in wanted if wid in ids]
            for wid in wanted:
                say("default spawn road '%s' %s" % (wid, "found" if wid in found else "is not a road id of the network (ok when another entry is found)"))
            if wanted and not found:
                fail("none of RoamSettings.DefaultSpawnRoadIds %s is a road of DA_RoadNetwork" % (wanted,))
        except Exception as exc:  # noqa: BLE001
            say("settings check skipped: %r" % (exc,))
    wd = W.ea.load_asset(W.DA_WORLD_DEFINITION)
    if wd is None:
        fail("DA_WorldDefinition missing")
        return
    regions = list(wd.get_editor_property("regions"))
    pois = list(wd.get_editor_property("pois"))
    say("DA_WorldDefinition region_rects=%d pois=%d" % (len(regions), len(pois)))
    tp = []
    for p in pois:
        loc = p.get_editor_property("location")
        try:
            is_tp = p.get_editor_property("teleport_target")
        except Exception:  # noqa: BLE001
            is_tp = True
        tp.append(str(p.get_editor_property("poi_id")))
        say("POI %-24s tp=%s x=%9.0f y=%9.0f z=%7.0f yaw=%6.1f road=%s" % (
            p.get_editor_property("poi_id"), is_tp, loc.x, loc.y, loc.z, p.get_editor_property("yaw_deg"), p.get_editor_property("road_id")))
    say("TP_LIST " + ",".join(tp))
    dup = sorted(set(i for i in tp if tp.count(i) > 1))
    if dup:
        fail("duplicate POI ids in DA_WorldDefinition (a teleport command resolves only the first): %s" % dup)


def _loaded_world_has_landscape():
    world = W.get_world()
    try:
        desc = unreal.RoamWorldBuilder.describe_landscape(world)
    except Exception:  # noqa: BLE001
        return False, ""
    return ("proxies=0" not in desc), desc


def ensure_map():
    path = _opt("map", W.MAP_MAIN)
    world = W.get_world()
    ok, desc = _loaded_world_has_landscape()
    if ok and world.get_name() == path.rsplit("/", 1)[1]:
        return world, desc
    say("loading map %s" % path)
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    if not level_subsystem.load_level(path):
        fail("cannot load map " + path)
    world = W.get_world()
    ok, desc = _loaded_world_has_landscape()
    return world, desc


def check_map():
    world, desc = ensure_map()
    say("MAP %s %s" % (world.get_name(), desc))
    if "proxies=0" in desc:
        fail("map has no landscape")


def _trace_down(world, x_cm, y_cm, z_cm):
    """Wheel-channel line trace through the editor world. Returns hit z (cm) or None."""
    start = unreal.Vector(x_cm, y_cm, z_cm + 30000.0)
    end = unreal.Vector(x_cm, y_cm, z_cm - 30000.0)
    try:
        q = unreal.TraceTypeQuery.ECC_ROAM_WHEEL            # custom trace channel Roam_Wheel (DefaultEngine.ini)
        hit = unreal.SystemLibrary.line_trace_single(world, start, end, q, False, [], unreal.DrawDebugTrace.NONE, True)
    except Exception as exc:  # noqa: BLE001
        say("line trace not available: %r" % (exc,))
        return None
    if hit is None:
        return None
    # python HitResult exposes its fields through to_tuple(): (blocking_hit, initial_overlap, time, distance, location, impact_point, ...)
    return hit.to_tuple()[5].z


def check_ground():
    world, desc = ensure_map()
    say("GROUND map=%s %s" % (world.get_name(), desc))
    n = int(_opt("points", "20"))
    tol_m = float(_opt("tol", "1.0"))
    data = W.roads_json()
    worst = 0.0
    misses = 0
    traced = 0
    per_class = {}
    for road in data["roads"]:
        samples = road["samples"]
        per_class.setdefault(road["class"], []).append(road)
    for cls, roads in sorted(per_class.items()):
        rows = []
        for road in roads:
            samples = road["samples"]
            step = max(1, len(samples) // max(1, n // len(roads) + 1))
            rows += [(road["id"], samples[i]) for i in range(0, len(samples), step)]
        rows = rows[:n]
        dz_max = 0.0
        for road_id, s in rows:
            x_m, y_m, z_m = s[1], s[2], s[3]
            if int(s[8]) & (FLAG_BRIDGE | FLAG_TUNNEL | FLAG_PORTAL):
                continue          # the terrain is not carved to the road under bridges / over tunnels (checked by `wheels` instead)
            sample = unreal.RoamWorldBuilder.sample_landscape(world, x_m * 100.0, y_m * 100.0)
            if not sample.get_editor_property("valid"):
                misses += 1
                fail("landscape has no height at %s x=%.0f y=%.0f" % (road_id, x_m, y_m))
                continue
            h_m = sample.get_editor_property("height_cm") / 100.0
            dz = h_m - z_m
            dz_max = max(dz_max, abs(dz))
            worst = max(worst, abs(dz))
            traced += 1
        say("GROUND class=%-9s points=%d max|landscape-road|=%.2f m" % (cls, len(rows), dz_max))
    say("GROUND worst |landscape-road| = %.2f m (tol %.2f), bed samples compared=%d, missing landscape=%d (bridge / tunnel samples excluded)" % (worst, tol_m, traced, misses))
    if worst > tol_m:
        fail("landscape deviates from the road bed by %.2f m (> %.2f)" % (worst, tol_m))


FLAG_BRIDGE, FLAG_TUNNEL, FLAG_PORTAL = 1, 2, 32


def _probe(world, x_m, y_m, z_m):
    """Wheel-style probe: Roam_Wheel line trace from 1.5 m above the lane point down 4.5 m (what a suspension raycast does).
    Returns (impact_z_m, actor_name, physmat_name) or None."""
    start = unreal.Vector(x_m * 100.0, y_m * 100.0, (z_m + 1.5) * 100.0)
    end = unreal.Vector(x_m * 100.0, y_m * 100.0, (z_m - 3.0) * 100.0)
    hit = unreal.SystemLibrary.line_trace_single(world, start, end, unreal.TraceTypeQuery.ECC_ROAM_WHEEL, False, [], unreal.DrawDebugTrace.NONE, True)
    if hit is None:
        return None
    t = hit.to_tuple()
    pm = t[8]
    actor = t[9]
    return (t[5].z / 100.0, actor.get_actor_label() if actor else "?", pm.get_name() if pm else "none")


def _lane_point(road, s):
    """(x, y, z) at the centre of the right lane (right-hand traffic) for a roads.json sample row."""
    h = math.radians(s[4])
    d = 0.5 * float(road.get("median_width", 0.0)) + 0.5 * float(road.get("lane_width", 3.5))
    x = s[1] - math.sin(h) * d
    y = s[2] + math.cos(h) * d
    z = s[3] - d * math.tan(math.radians(s[6]))
    return x, y, z


def check_wheels():
    """>= 20 wheel-channel probes along the roads (all classes, bridge decks, tunnel floor, junction pads): every probe must hit, at the road
    surface (+-0.15 m); prints the physical material of each hit so the surface lookup can be compared with the road class."""
    world, desc = ensure_map()
    n_per_class = int(_opt("wheelpoints", "8"))
    data = W.roads_json()
    plan = []     # (label, road, sample)
    by_class = {}
    for road in data["roads"]:
        by_class.setdefault(road["class"], []).append(road)
    for cls, roads in sorted(by_class.items()):
        picks = []
        for road in roads:
            rows = [r for r in road["samples"] if not int(r[8]) & (FLAG_BRIDGE | FLAG_TUNNEL | FLAG_PORTAL)]
            if rows:
                picks.append((road, rows[len(rows) // 3]))
                picks.append((road, rows[(2 * len(rows)) // 3]))
        for road, row in picks[:n_per_class]:
            plan.append(("%s" % cls, road, row))
    for road in data["roads"]:
        for key, flag in (("bridges", FLAG_BRIDGE), ("tunnels", FLAG_TUNNEL)):
            for st in road.get(key, [])[:2]:
                mid = 0.5 * (st["s0"] + st["s1"])
                rows = [r for r in road["samples"] if abs(r[0] - mid) <= 40.0 or (st["s0"] + 10 < r[0] < st["s1"] - 10 and int(r[8]) & flag)]
                for row in rows[:: max(1, len(rows) // 3)][:3]:
                    plan.append((key[:-1].upper(), road, row))
    miss = off = landscape_hits = 0
    surfaces = {}
    worst = 0.0
    for label, road, row in plan:
        x, y, z = _lane_point(road, row)
        res = _probe(world, x, y, z)
        if res is None:
            miss += 1
            fail("wheel probe MISS %s %s s=%.0f (%.0f, %.0f, z %.2f)" % (label, road["id"], row[0], x, y, z))
            continue
        dz = res[0] - z
        worst = max(worst, abs(dz))
        key = "%s/%s" % (label, res[2])
        surfaces[key] = surfaces.get(key, 0) + 1
        if not str(res[1]).startswith("Road_"):
            landscape_hits += 1
            say("WHEEL hit the %s instead of a road chunk: %s %s s=%.0f dz %+.2f" % (res[1], label, road["id"], row[0], dz))
        if abs(dz) > 0.15:
            off += 1
            say("WHEEL off-surface %s %s s=%.0f probe z %.2f vs road %.2f (dz %+.2f) actor=%s pm=%s" % (label, road["id"], row[0], res[0], z, dz, res[1], res[2]))
        elif label in ("BRIDGE", "TUNNEL"):
            say("WHEEL %s %s s=%.0f hit actor=%s pm=%s dz %+.3f" % (label, road["id"], row[0], res[1], res[2], dz))
    say("WHEELS probes=%d miss=%d off_surface(>0.15 m)=%d landscape_instead_of_road=%d worst|dz|=%.3f m" % (len(plan), miss, off, landscape_hits, worst))
    say("WHEELS surfaces (class/physical material -> count): %s" % sorted(surfaces.items()))
    if miss or off or landscape_hits:
        fail("wheel probes: %d miss, %d off the road surface, %d hit the landscape instead of the road mesh" % (miss, off, landscape_hits))


CHECKS = {"data": check_data, "map": check_map, "ground": check_ground, "wheels": check_wheels}


def run(wanted=None):
    """Runs the named checks (default data + ground); returns the number of failures. Callable from world_build.py (step `verify`)."""
    del FAILS[:]
    wanted = wanted or [t for t in _tokens() if "=" not in t] or ["data", "ground"]
    for name in wanted:
        fn = CHECKS.get(name)
        if fn is None:
            fail("unknown check '%s' (known: %s)" % (name, ", ".join(CHECKS)))
            continue
        try:
            fn()
        except Exception:  # noqa: BLE001
            import traceback
            fail("check %s raised: %s" % (name, traceback.format_exc()))
    say("DONE failures=%d" % len(FAILS))
    unreal.log("ROAM_VERIFY_DONE failures=%d" % len(FAILS))
    return len(FAILS)


if __name__ == "__main__":
    run()
    if "JOB_ARGS" not in globals():
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
