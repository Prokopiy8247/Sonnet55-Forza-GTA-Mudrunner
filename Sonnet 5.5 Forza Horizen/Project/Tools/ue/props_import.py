"""Props import (agent P1): every FBX of Exports/{Nature/Trees,Nature/Cover,Roadside,Settlements} -> static meshes
    /Game/Forza/Props/<Category>/<AssetId>/SM_<AssetId>          (Category = Trees | Cover | Roadside | Settlements; far cards are their own asset id <tree>_Far)
Idempotent: every run re-imports (replace) and re-applies Nanite / collision / material slot bindings; `skip_existing=1` only re-applies settings.

Run as an editor job (persistent job server, never quits the editor):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_import.py -TimeoutSec 3600 -Args0 "cat=Trees,Cover only=oak skip_existing=1"
Arguments (key=value tokens in JOB_ARGS, or environment ROAM_PROPS_<KEY>):
    cat=Trees,Cover,Roadside,Settlements   categories (default all)       only=a,b   substring filter on asset ids      skip_existing=1   do not re-import existing meshes
    materials=0   skip props_materials_fix.py (it creates the MI_Bld_* instances the settlement kit lacks)           voxelize=1   Nanite shape preservation VOXELIZE on trees
Rules (from the sidecar JSON, Docs/Tech/PROPS_PIPELINE.md):
  * Nanite ON for opaque meshes; OFF for the `_Far` billboard cards (masked) and the bus-stop shelter (translucent glass).  The sidecar `nanite` flag decides.
  * UCX hulls are kept where the sidecar lists `collision.hulls` (trees: trunk hull only, rocks/buildings/signs: simple); assets without hulls get no collision
    (the importer's fallback hull is removed again).  Collision complexity = USE_SIMPLE_AS_COMPLEX.
  * material slot -> MI_* instance BY NAME (Tools/ue/materials_slot_map.json, then /Game/Forza/Materials/Instances|Roads/MI_<slot without M_>).
  * vertex colours (wind masks R/G, AO B, tint A) are imported (VCIO_REPLACE) and checked afterwards.
Log markers: PROPS_IMPORT (progress), PROPS_VALIDATE (one row per asset), PROPS_RESULT (summary); report: Saved/PropsImport/report.json
"""
import importlib
import json
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

JOB_MODE = "JOB_ARGS" in globals()
_OPTS = dict(tok.split("=", 1) for tok in str(globals().get("JOB_ARGS", "")).split() if "=" in tok)


def opt(name, default=""):
    return _OPTS.get(name, os.environ.get("ROAM_PROPS_" + name.upper(), default))


CATS = [s.strip() for s in opt("cat", "Trees,Cover,Roadside,Settlements").split(",") if s.strip()]
ONLY = [s.strip() for s in opt("only").split(",") if s.strip()]
SKIP_EXISTING = opt("skip_existing") == "1"
VOXELIZE = opt("voxelize") == "1"
DO_MATERIALS = opt("materials", "1") != "0"
REPORT = PROJECT + "Saved/PropsImport/report.json"

SMS = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
EAL = unreal.EditorAssetLibrary
SLOT_MAP = {}
try:
    with open(_HERE + "/materials_slot_map.json", encoding="utf-8") as _fh:
        SLOT_MAP = json.load(_fh)
except Exception as exc:  # noqa: BLE001
    unreal.log_warning("PROPS_IMPORT slot map unreadable: %s" % exc)


def log(msg):
    unreal.log("PROPS_IMPORT " + msg)


def warn(msg):
    unreal.log_warning("PROPS_IMPORT " + msg)


# ----------------------------------------------------------------------------------------------------------------------
def make_import_options(nanite, collision):
    """Legacy FbxImportUI (the only options object the 5.8.2 task path honours, see Docs/Tech/CARS_IMPORT.md section 3)."""
    ui = unreal.FbxImportUI()
    ui.set_editor_property("automated_import_should_detect_type", False)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", False)
    ui.set_editor_property("import_animations", False)
    ui.set_editor_property("import_materials", False)   # slot names stay M_*; we bind the MI_* instances ourselves
    ui.set_editor_property("import_textures", False)
    d = ui.static_mesh_import_data
    d.set_editor_property("combine_meshes", False)
    d.set_editor_property("auto_generate_collision", bool(collision))   # must be True for the UCX_ hulls to be kept
    d.set_editor_property("generate_lightmap_u_vs", False)
    d.set_editor_property("build_nanite", bool(nanite))
    d.set_editor_property("one_convex_hull_per_ucx", True)
    d.set_editor_property("remove_degenerates", True)
    d.set_editor_property("transform_vertex_to_absolute", True)
    d.set_editor_property("normal_import_method", unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS)
    d.set_editor_property("import_uniform_scale", 1.0)
    d.set_editor_property("import_rotation", unreal.Rotator(0, 0, 0))
    d.set_editor_property("import_translation", unreal.Vector(0, 0, 0))
    try:
        d.set_editor_property("vertex_color_import_option", unreal.VertexColorImportOption.REPLACE)   # keep the wind masks
    except Exception as exc:  # noqa: BLE001
        warn("vertex_color_import_option not set: %s" % exc)
    return ui


def import_fbx(entry, nanite, collision):
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", entry["fbx"])
    task.set_editor_property("destination_path", entry["folder"])
    task.set_editor_property("destination_name", "SM_" + entry["id"])
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("replace_existing_settings", True)
    task.set_editor_property("save", False)
    task.set_editor_property("options", make_import_options(nanite, collision))
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    return [str(p) for p in task.get_editor_property("imported_object_paths")]


def mi_for_slot(slot):
    cands = []
    if slot in SLOT_MAP:
        cands.append(SLOT_MAP[slot])
    nm = slot[2:] if slot.startswith("M_") else slot
    cands += ["/Game/Forza/Materials/Instances/MI_" + nm, "/Game/Forza/Materials/Roads/MI_" + nm]
    for p in cands:
        if EAL.does_asset_exist(p):
            return EAL.load_asset(p)
    return None


def bind_materials(sm):
    bound, missing = 0, []
    for i, sm_mat in enumerate(list(sm.static_materials)):
        slot = str(sm_mat.get_editor_property("material_slot_name"))
        mi = mi_for_slot(slot)
        if mi is None:
            missing.append(slot)
            continue
        sm.set_material(i, mi)
        bound += 1
    return bound, missing


def translucent_slots(sm):
    out = []
    for i, m in enumerate(list(sm.static_materials)):
        mat = m.get_editor_property("material_interface")
        try:
            base = mat
            while base is not None and isinstance(base, unreal.MaterialInstance):
                base = base.get_editor_property("parent")
            if base is not None and base.get_editor_property("blend_mode") in (unreal.BlendMode.BLEND_TRANSLUCENT, unreal.BlendMode.BLEND_ADDITIVE,
                                                                               unreal.BlendMode.BLEND_MODULATE):
                out.append(str(m.get_editor_property("material_slot_name")))
        except Exception:  # noqa: BLE001
            pass
    return out


def simple_count(sm):
    """Number of simple collision shapes (SMS.get_simple_collision_count returns 0 for imported UCX hulls in 5.8.2: count the aggregate geometry)."""
    try:
        ag = sm.get_editor_property("body_setup").get_editor_property("agg_geom")
        return sum(len(ag.get_editor_property(k)) for k in ("convex_elems", "box_elems", "sphere_elems", "sphyl_elems"))
    except Exception:  # noqa: BLE001
        return SMS.get_simple_collision_count(sm)


def apply_settings(sm, entry, nanite, keep_hulls):
    ns = SMS.get_nanite_settings(sm)
    changed = bool(ns.enabled) != bool(nanite)
    ns.enabled = bool(nanite)
    if VOXELIZE and nanite and entry["cat"] == "Trees":
        try:
            ns.set_editor_property("shape_preservation", unreal.NaniteShapePreservation.VOXELIZE)
            changed = True
        except Exception as exc:  # noqa: BLE001
            warn("%s: voxelize not available: %s" % (entry["id"], exc))
    if changed:
        SMS.set_nanite_settings(sm, ns, True)
    try:
        bs = SMS.get_lod_build_settings(sm, 0)
        if bs.generate_lightmap_u_vs or bs.recompute_normals:
            bs.generate_lightmap_u_vs = False
            bs.recompute_normals = False
            SMS.set_lod_build_settings(sm, 0, bs)
    except Exception as exc:  # noqa: BLE001
        warn("%s: build settings: %s" % (entry["id"], exc))
    if not keep_hulls and simple_count(sm) > 0:
        SMS.remove_collisions(sm)
    try:
        sm.get_editor_property("body_setup").set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_SIMPLE_AS_COMPLEX)
    except Exception as exc:  # noqa: BLE001
        warn("%s: collision trace flag: %s" % (entry["id"], exc))


def validate(entry, sm, nanite, keep_hulls, missing):
    """One PROPS_VALIDATE row; returns list of problems."""
    probs = []
    b = sm.get_bounds()
    size = (b.box_extent.x * 2, b.box_extent.y * 2, b.box_extent.z * 2)
    want = (entry["bmax"][0] - entry["bmin"][0], entry["bmax"][1] - entry["bmin"][1], entry["bmax"][2] - entry["bmin"][2])
    if not entry["is_far"]:
        for a, (g, w) in zip("xyz", zip(size, want)):
            if abs(g - w * 100.0) > max(3.0, 0.03 * w * 100.0):
                probs.append("size_%s got %.1f want %.1f cm" % (a, g, w * 100.0))
    hulls = simple_count(sm)
    if keep_hulls and hulls != len(entry["hulls"]) and not (entry["cat"] == "Trees" and hulls > 0):
        probs.append("hulls got %d want %d" % (hulls, len(entry["hulls"])))
    if not keep_hulls and hulls:
        probs.append("unexpected hulls %d" % hulls)
    if bool(SMS.get_nanite_settings(sm).enabled) != bool(nanite):
        probs.append("nanite flag")
    vc = False
    try:
        vc = bool(SMS.has_vertex_colors(sm))
    except Exception:  # noqa: BLE001
        pass
    if entry["wind"] and not vc:
        probs.append("vertex colours (wind) missing")
    if missing:
        probs.append("unbound slots %s" % missing)
    unreal.log("PROPS_VALIDATE %-34s %s tris=%s size_cm=(%.0f,%.0f,%.0f) hulls=%d nanite=%s vcol=%s %s" % (
        entry["id"], entry["cat"], SMS.get_number_triangles(sm, 0) if hasattr(SMS, "get_number_triangles") else "?", size[0], size[1], size[2], hulls,
        bool(SMS.get_nanite_settings(sm).enabled), vc, ("PROBLEMS: " + "; ".join(probs)) if probs else "ok"))
    return probs


def decide(entry):
    """(nanite, keep_hulls) from the sidecar."""
    nanite = bool(entry["nanite"]) and not entry["is_far"]
    keep = bool(entry["hulls"]) and entry["col"] in ("box", "convex", "complex_simple")
    return nanite, keep


def main():
    t0 = time.time()
    if DO_MATERIALS:
        try:
            if not EAL.does_asset_exist("/Game/Forza/Materials/Instances/MI_Bld_Window"):
                with open(_HERE + "/props_materials_fix.py", encoding="utf-8") as _fh:
                    exec(compile(_fh.read(), "props_materials_fix.py", "exec"), {"__name__": "props_materials_fix"})
        except Exception as exc:  # noqa: BLE001
            warn("props_materials_fix failed: %s" % exc)
    cat = C.load_catalog()
    todo = [e for e in cat.values() if e["cat"] in CATS and (not ONLY or any(o in e["id"] for o in ONLY))]
    todo.sort(key=lambda e: (CATS.index(e["cat"]), e["id"]))
    log("%d assets to process (cats=%s only=%s skip_existing=%s)" % (len(todo), CATS, ONLY, SKIP_EXISTING))
    rows, fails = [], 0
    for n, e in enumerate(todo):
        ts = time.time()
        nanite, keep = decide(e)
        try:
            exists = EAL.does_asset_exist(e["mesh"])
            if not (SKIP_EXISTING and exists):
                paths = import_fbx(e, nanite, keep)
                if not paths:
                    raise RuntimeError("import returned no objects")
            sm = EAL.load_asset(e["mesh"])
            if sm is None:
                raise RuntimeError("mesh not found after import: " + e["mesh"])
            apply_settings(sm, e, nanite, keep)
            bound, missing = bind_materials(sm)
            tr = translucent_slots(sm)
            if tr and nanite:
                warn("%s: Nanite mesh has translucent slot(s) %s (renders through the Nanite fallback mesh)" % (e["id"], tr))
            probs = validate(e, sm, nanite, keep, missing)
            EAL.save_loaded_asset(sm)
            rows.append({"id": e["id"], "cat": e["cat"], "mesh": e["mesh"], "nanite": nanite, "hulls": keep, "bound": bound, "missing": missing,
                         "translucent": tr, "problems": probs, "seconds": round(time.time() - ts, 1)})
            fails += 1 if probs else 0
            log("[%d/%d] %s %.1fs" % (n + 1, len(todo), e["id"], time.time() - ts))
        except Exception as exc:  # noqa: BLE001
            fails += 1
            rows.append({"id": e["id"], "cat": e["cat"], "error": str(exc)})
            unreal.log_error("PROPS_IMPORT %s FAILED: %s\n%s" % (e["id"], exc, traceback.format_exc()))
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as _fh:
        json.dump(rows, _fh, indent=1)
    unreal.log("PROPS_RESULT assets=%d with_problems=%d seconds=%.0f report=%s" % (len(todo), fails, time.time() - t0, REPORT))


main()
