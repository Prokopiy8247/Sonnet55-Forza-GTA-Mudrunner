"""Applies the generated placements (Content/Forza/World/Placements/, Tools/ue/placement_gen.py) to the OPEN level (agent P1 'props').
Editor job (persistent job server, never quits the editor):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_apply.py -TimeoutSec 3600 -Args0 "cats=trees,cover,furniture,buildings"

Arguments (key=value tokens in JOB_ARGS):
    cats=trees,cover,furniture,buildings   categories to apply (default all).  Resumable: each category is cleared first (clear=1) and applied independently.
    clear=1|0|all   1 (default): remove the previously applied instances of the categories being applied (foliage types of the group / actors tagged RoamProp+<cat>);
                    all: also remove every Roam prop (all groups) and exit when cats is empty (cats=none);  0: append
    far=1|0         trees: also place the 4-triangle `_Far` billboard card of every tree (cull start 300 m, end 1100 m) and cull the Nanite tree at 320 m (default 1)
    region=x0,y0,x1,y1   only instances inside this UE-metre window (X north, Y east)       fraction=0.1   keep every n-th instance (smoke tests)
    zshift=-100     add metres to every z (test levels with a flat ground)                   batch=20000   transforms per add_instances call
    testmap=1       STANDALONE ONLY (Tools/ue_cmd.ps1, env ROAM_PROPS_TESTMAP=1): new blank throw-away world with a flat ground (nothing is saved), apply, report, quit.
                    Refuses to run inside the shared job server: replacing / loading levels there crashes it ("World Memory Leaks") and drops the open level of the other agents.
    save=1          save the current level when finished (World Partition: saves the foliage partition actors)
    allow_main=1    required to run on a level whose path contains L_Main (lead only)
Technique: foliage types /Game/Forza/Props/FoliageTypes/FT_<id> (Nanite meshes, cull distances, WPO disable distance, trunk-only collision) +
`unreal.InstancedFoliageActor.add_instances(world, type, transforms)` (partitioned automatically in a World Partition level, grid = WorldSettings foliage grid);
buildings / landmarks / pier / castle as StaticMeshActors in folder Roam/Props/Settlements/<Group> with tags RoamProp, RoamBuilding; wind turbine / windmill rotors as
StaticMeshActors tagged RoamRotor (+ RoamRotorDegPerSec=<n>, RoamRotorAxis=X, pivot = hub) for the later spin component.
Log markers: PROPS_APPLY (progress), PROPS_APPLY_DONE (timing + counts).
"""
import array
import importlib
import json
import math
import os
import sys
import time
import traceback

import unreal

PROJECT = unreal.Paths.project_dir().replace("\\", "/")
_HERE = PROJECT + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import props_catalog as C  # noqa: E402
importlib.reload(C)

_OPTS = dict(tok.split("=", 1) for tok in str(globals().get("JOB_ARGS", "")).split() if "=" in tok)


def opt(name, default=""):
    return _OPTS.get(name, os.environ.get("ROAM_PROPS_" + name.upper(), default))


CATS = [c for c in opt("cats", "trees,cover,furniture,buildings").split(",") if c and c != "none"]
CLEAR = opt("clear", "1")
FAR = opt("far", "1") != "0"
REGION = [float(v) for v in opt("region").split(",")] if opt("region") else None
FRACTION = float(opt("fraction", "1"))
ZSHIFT = float(opt("zshift", "0"))
BATCH = int(opt("batch", "20000"))
TESTMAP = opt("testmap") == "1"
SAVE = opt("save") == "1"
ALLOW_MAIN = opt("allow_main") == "1"

PLACE_DIR = PROJECT + "Content/Forza/World/Placements"
FT_DIR = "/Game/Forza/Props/FoliageTypes"
EAL = unreal.EditorAssetLibrary
EAS = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
UES = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
LES = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
CAT = C.load_catalog()
TAG_PROP, TAG_ROTOR = "RoamProp", "RoamRotor"


def log(msg):
    unreal.log("PROPS_APPLY " + msg)


def warn(msg):
    unreal.log_warning("PROPS_APPLY " + msg)


# ----------------------------------------------------------------------------------------------------------------------
# foliage type settings by asset family (cm)
# ----------------------------------------------------------------------------------------------------------------------
def settings_for(aid):
    """dict(cull=(start, end), wpo=bool, wpo_dist, nanite_px, shadow, dfgi, collision)"""
    e = CAT[aid]
    s = {"cull": (0, 0), "wpo": False, "wpo_dist": 0, "nanite_px": 0.0, "shadow": True, "dfgi": False, "collision": e["col"] != "none" and not e["is_far"]}
    big = max(e["dims"]) > 4.0
    if e["is_far"]:
        s.update(cull=(30000, 110000), shadow=False, collision=False)
    elif aid.startswith("tree_"):
        s.update(cull=(0, 32000 if FAR else 0), wpo=True, wpo_dist=9000, nanite_px=6000.0, dfgi=True)
    elif aid.startswith("nat_bush") or aid.startswith("nat_shrub"):
        s.update(cull=(0, 18000), wpo=True, wpo_dist=5000, nanite_px=3000.0, collision=False)
    elif aid.startswith("nat_rock") or aid.startswith("nat_cliff"):
        s.update(cull=(0, 0 if aid.startswith("nat_cliff") else (60000 if big else 30000)), dfgi=big, collision=True)
    elif aid.startswith("nat_cactus"):
        s.update(cull=(0, 30000))
    elif aid.startswith("nat_crop") or aid.startswith("nat_reeds") or aid.startswith("nat_grass") or aid.startswith("nat_flowers"):
        s.update(cull=(0, 25000), wpo=True, wpo_dist=4000, nanite_px=2500.0, shadow=False, collision=False)
    elif aid.startswith("nat_"):
        s.update(cull=(0, 25000))
    elif aid.startswith("rs_guardrail") or aid.startswith("rs_bridge_rail") or aid.startswith("rs_parapet") or aid.startswith("rs_barrier"):
        s.update(cull=(0, 60000), dfgi=False)
    elif aid.startswith("rs_delineator") or aid.startswith("rs_milemarker") or aid.startswith("rs_milestone") or aid.startswith("rs_bollard"):
        s.update(cull=(0, 20000), shadow=False, collision=False)
    elif aid.startswith("rs_sign") or aid.startswith("rs_speedtrap"):
        s.update(cull=(0, 50000))
    elif aid.startswith("rs_utility_pole") or aid.startswith("rs_streetlamp") or aid.startswith("rs_gantry"):
        s.update(cull=(0, 80000))
    elif aid.startswith("rs_utility_wire"):
        s.update(cull=(0, 60000), shadow=False, collision=False)
    elif aid.startswith("rs_fence") or aid.startswith("rs_wall"):
        s.update(cull=(0, 40000), shadow=False)
    else:
        s.update(cull=(0, 0))
    return s


def get_foliage_type(aid):
    path = "%s/FT_%s" % (FT_DIR, aid)
    if EAL.does_asset_exist(path):
        ft = EAL.load_asset(path)
    else:
        ft = unreal.AssetToolsHelpers.get_asset_tools().create_asset("FT_" + aid, FT_DIR, unreal.FoliageType_InstancedStaticMesh, unreal.FoliageType_InstancedStaticMeshFactory())
    st = settings_for(aid)
    mesh = EAL.load_asset(CAT[aid]["mesh"])
    if mesh is None:
        raise RuntimeError("static mesh missing (run props_import.py): " + CAT[aid]["mesh"])
    ft.set_editor_property("mesh", mesh)
    iv = unreal.Int32Interval()
    iv.set_editor_property("min", st["cull"][0])
    iv.set_editor_property("max", st["cull"][1])
    ft.set_editor_property("cull_distance", iv)
    ft.set_editor_property("cast_shadow", st["shadow"])
    ft.set_editor_property("cast_dynamic_shadow", st["shadow"])
    ft.set_editor_property("cast_contact_shadow", False)
    ft.set_editor_property("affect_distance_field_lighting", st["dfgi"])
    ft.set_editor_property("receives_decals", False)
    ft.set_editor_property("include_in_hlod", False)
    ft.set_editor_property("evaluate_world_position_offset", bool(st["wpo"]))
    try:
        ft.set_editor_property("world_position_offset_disable_distance", int(st["wpo_dist"]))
        if st["nanite_px"]:
            ft.set_editor_property("nanite_pixel_programmable_distance", float(st["nanite_px"]))
    except Exception as exc:  # noqa: BLE001
        warn("%s: wpo / nanite distance: %s" % (aid, exc))
    try:
        ft.set_editor_property("collision_with_world", False)
        bi = ft.get_editor_property("body_instance")
        bi.set_editor_property("collision_profile_name", "RoamWorldStatic" if st["collision"] else "NoCollision")
        ft.set_editor_property("body_instance", bi)
        got = str(ft.get_editor_property("body_instance").get_editor_property("collision_profile_name"))
        if got != ("RoamWorldStatic" if st["collision"] else "NoCollision"):
            warn("%s: collision profile read back as %s" % (aid, got))
    except Exception as exc:  # noqa: BLE001
        warn("%s: collision profile: %s" % (aid, exc))
    try:
        ft.set_editor_property("scaling", unreal.FoliageScaling.FREE)
        ft.set_editor_property("random_yaw", False)
        ft.set_editor_property("align_to_normal", False)
    except Exception:  # noqa: BLE001
        pass
    EAL.save_loaded_asset(ft)
    return ft


# ----------------------------------------------------------------------------------------------------------------------
def world():
    return UES.get_editor_world()


def load_group(index, name):
    g = index["groups"].get(name)
    if not g or not g["count"]:
        return [], array.array("f")
    arr = array.array("f")
    with open("%s/%s" % (PLACE_DIR, g["file"]), "rb") as f:
        arr.fromfile(f, g["count"] * g["record"])
    return g["assets"]["list"], arr


def clear_group(name, index):
    """Removes every foliage instance of the group's types."""
    n_assets = []
    g = index["groups"].get(name)
    ids = list(g["assets"]["list"]) if g else []
    if name == "trees":
        ids += [i + "_Far" for i in ids]
    w = world()
    for aid in ids:
        path = "%s/FT_%s" % (FT_DIR, aid)
        if EAL.does_asset_exist(path):
            unreal.InstancedFoliageActor.remove_all_instances(w, EAL.load_asset(path))
            n_assets.append(aid)
    log("cleared %d foliage types of group %s" % (len(n_assets), name))


def apply_foliage(name, index, tally):
    t0 = time.time()
    ids, arr = load_group(index, name)
    if not ids:
        log("group %s empty" % name)
        return
    w = world()
    rec = index["groups"][name]["record"]
    n = len(arr) // rec
    per = {}
    keep_every = max(1, int(round(1.0 / FRACTION))) if FRACTION < 1.0 else 1
    for k in range(n):
        if keep_every > 1 and k % keep_every:
            continue
        b = k * rec
        x, y = arr[b + 1] * 0.01, arr[b + 2] * 0.01
        if REGION and not (REGION[0] <= x <= REGION[2] and REGION[1] <= y <= REGION[3]):
            continue
        per.setdefault(int(arr[b]), []).append(b)
    total = 0
    for ai, offs in sorted(per.items()):
        aid = ids[ai]
        targets = [aid]
        if name == "trees" and FAR and (aid + "_Far") in CAT:
            targets.append(aid + "_Far")
        for tid in targets:
            ft = get_foliage_type(tid)
            for i0 in range(0, len(offs), BATCH):
                tfs = []
                for b in offs[i0:i0 + BATCH]:
                    tfs.append(unreal.Transform(unreal.Vector(arr[b + 1], arr[b + 2], arr[b + 3] + ZSHIFT * 100.0), unreal.Rotator(arr[b + 6], arr[b + 5], arr[b + 4]),
                                                unreal.Vector(arr[b + 7], arr[b + 8], arr[b + 9])))
                unreal.InstancedFoliageActor.add_instances(w, ft, tfs)
        total += len(offs)
        tally[aid] = tally.get(aid, 0) + len(offs)
    log("%s: %d instances (%d types) in %.1fs" % (name, total, len(per), time.time() - t0))
    tally["__" + name] = total


# ----------------------------------------------------------------------------------------------------------------------
def destroy_tagged(extra_tag=None):
    n = 0
    for a in list(EAS.get_all_level_actors()):
        try:
            tags = [str(t) for t in a.get_editor_property("tags")]
        except Exception:  # noqa: BLE001
            continue
        if TAG_PROP in tags and (extra_tag is None or extra_tag in tags):
            EAS.destroy_actor(a)
            n += 1
    log("destroyed %d tagged actors (%s)" % (n, extra_tag or "all RoamProp"))


def spawn(b, rotor=False):
    mesh = EAL.load_asset(CAT[b["asset"]]["mesh"])
    if mesh is None:
        raise RuntimeError("mesh missing: " + CAT[b["asset"]]["mesh"])
    loc = unreal.Vector(b["x"], b["y"], b["z"] + ZSHIFT * 100.0)
    a = EAS.spawn_actor_from_class(unreal.StaticMeshActor, loc, unreal.Rotator(0.0, 0.0, b["yaw"]))
    a.set_actor_label(b["name"])
    a.set_folder_path("Roam/Props/%s/%s" % ("Rotors" if rotor else "Settlements", b.get("group") or "Misc"))
    s = float(b.get("scale", 1.0))
    a.set_actor_scale3d(unreal.Vector(s, s, s * float(b.get("sz", 1.0))))
    comp = a.static_mesh_component
    comp.set_static_mesh(mesh)
    comp.set_mobility(unreal.ComponentMobility.STATIC)
    comp.set_collision_profile_name("NoCollision" if rotor else "RoamWorldStatic")
    tags = [TAG_PROP, "RoamBuilding" if not rotor else TAG_ROTOR, "RoamBuildings"]
    if rotor:
        tags += ["RoamRotorDegPerSec=%g" % b.get("deg_per_s", 20.0), "RoamRotorAxis=X", "RoamRotorKind=%s" % b.get("kind", "")]
    a.set_editor_property("tags", [unreal.Name(t) for t in tags])
    try:
        a.set_is_spatially_loaded(True)
    except Exception:  # noqa: BLE001
        pass
    return a


def apply_buildings(index, tally):
    t0 = time.time()
    n = 0
    for b in index.get("buildings", []):
        if REGION and not (REGION[0] <= b["x"] * 0.01 <= REGION[2] and REGION[1] <= b["y"] * 0.01 <= REGION[3]):
            continue
        try:
            spawn(b)
            n += 1
        except Exception as exc:  # noqa: BLE001
            unreal.log_error("PROPS_APPLY building %s failed: %s" % (b.get("name"), exc))
    r = 0
    for b in index.get("rotors", []):
        if REGION and not (REGION[0] <= b["x"] * 0.01 <= REGION[2] and REGION[1] <= b["y"] * 0.01 <= REGION[3]):
            continue
        try:
            spawn(b, rotor=True)
            r += 1
        except Exception as exc:  # noqa: BLE001
            unreal.log_error("PROPS_APPLY rotor %s failed: %s" % (b.get("name"), exc))
    log("buildings: %d actors + %d rotor actors in %.1fs" % (n, r, time.time() - t0))
    tally["__buildings"] = n
    tally["__rotors"] = r


# ----------------------------------------------------------------------------------------------------------------------
def prepare_testmap():
    """Standalone only: blank world + flat ground (top surface z = 0, like L_Test)."""
    if "JOB_ARGS" in globals():
        raise RuntimeError("testmap=1 must run standalone (Tools/ue_cmd.ps1), not in the shared job server")
    unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
    g = EAS.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0, 0, -100), unreal.Rotator(0, 0, 0))
    g.set_actor_label("PropsTestGround")
    g.set_actor_scale3d(unreal.Vector(4000.0, 4000.0, 2.0))
    g.static_mesh_component.set_static_mesh(EAL.load_asset("/Engine/BasicShapes/Cube.Cube"))
    log("blank test world ready: %s" % world().get_path_name())


def report_foliage():
    """Instance totals found in the level's foliage actors (proves the API calls landed)."""
    n_actors = n_comp = n_inst = 0
    for a in EAS.get_all_level_actors():
        if isinstance(a, unreal.InstancedFoliageActor):
            n_actors += 1
            for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
                n_comp += 1
                n_inst += int(c.get_instance_count())
    n_tag = sum(1 for a in EAS.get_all_level_actors() if TAG_PROP in [str(t) for t in a.get_editor_property("tags")])
    log("foliage actors=%d components=%d instances=%d, tagged building / rotor actors=%d" % (n_actors, n_comp, n_inst, n_tag))
    return n_inst, n_tag


def run_categories(index, tally, timing):
    for cat in CATS:
        tc = time.time()
        try:
            if cat in ("trees", "cover", "furniture"):
                if CLEAR == "1":
                    clear_group(cat, index)
                apply_foliage(cat, index, tally)
            elif cat == "buildings":
                if CLEAR == "1":
                    destroy_tagged("RoamBuildings")
                apply_buildings(index, tally)
        except Exception as exc:  # noqa: BLE001
            unreal.log_error("PROPS_APPLY category %s failed: %s\n%s" % (cat, exc, traceback.format_exc()))
        timing[cat] = round(time.time() - tc, 1)


def main():
    t0 = time.time()
    with open(PLACE_DIR + "/placements_index.json", encoding="utf-8") as fh:
        index = json.load(fh)
    if TESTMAP:
        prepare_testmap()
    wp = world().get_path_name()
    if "L_Main" in wp and not ALLOW_MAIN:
        raise RuntimeError("refusing to apply to %s (pass allow_main=1 - lead only)" % wp)
    log("world=%s cats=%s clear=%s far=%s region=%s fraction=%s zshift=%s" % (wp, CATS, CLEAR, FAR, REGION, FRACTION, ZSHIFT))
    tally, timing = {}, {}
    if CLEAR == "all":
        for gname in ("trees", "cover", "furniture"):
            clear_group(gname, index)
        destroy_tagged()
    run_categories(index, tally, timing)
    if TESTMAP:   # self test: second pass must be idempotent (clear first), then a full clear must leave nothing behind
        n1 = report_foliage()
        run_categories(index, {}, {})
        n2 = report_foliage()
        log("SELFTEST idempotent re-apply: %s (%s vs %s)" % ("OK" if n1 == n2 else "MISMATCH", n1, n2))
        for gname in ("trees", "cover", "furniture"):
            clear_group(gname, index)
        destroy_tagged()
        n3 = report_foliage()
        log("SELFTEST clear all: %s (%s)" % ("OK" if n3 == (0, 0) else "LEFTOVERS", n3))
        run_categories(index, {}, {})      # leave the throw-away world filled (nothing is saved)
    if SAVE and not TESTMAP:
        LES.save_current_level()
    report_foliage()
    total = sum(v for k, v in tally.items() if k in ("__trees", "__cover", "__furniture"))
    unreal.log("PROPS_APPLY_DONE seconds=%.1f instances=%d categories=%s tally=%s" % (time.time() - t0, total, timing, {k: v for k, v in tally.items() if k.startswith("__")}))


main()
if TESTMAP:
    unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
