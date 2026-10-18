"""Imports the Blender car exports (10 player cars + 6 traffic vehicles) into /Game/Forza/Cars and /Game/Forza/Traffic.

Idempotent and re-runnable: every run re-imports the FBX parts (replacing the assets), re-applies Nanite / collision / material
slot bindings and prints a validation table (imported bounds versus the sidecar JSON).

Run (PowerShell, from the project root; the script path must use forward slashes):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/cars_import.py -LogName cars_import
Optional environment variables (set before the call) - or "key=value" tokens in JOB_ARGS when run as a job on the editor server:
    ROAM_CARS_ONLY=car01_hatch_pulse,traffic02_van   (only=...)       only these ids (substring match)
    ROAM_SKIP_IMPORT=1                               (skip_import=1)  do not import, only re-bind materials + validate
    ROAM_NO_QUIT=1                                                    keep the editor open (debugging; implied in job mode)
Log lines to grep: CARS_IMPORT (progress), CARS_VALIDATE (table rows), CARS_RESULT (summary).

Conventions (Docs/BLENDER_CONTRACT.md, Docs/Tech/UE58_automation_pipeline.md 3.7):
  * one FBX per part, pivot = vehicle origin (Body/Glass/Interior) or axle centre (SteeringWheel hub, wheels);
  * asset names  SM_<id>_<Part>  under  /Game/Forza/Cars/<id>/  or  /Game/Forza/Traffic/<id>/;
  * Nanite ON for opaque parts, OFF for glass; Body gets the UCX_ convex hulls, no other part has collision;
  * lightmap UVs off, Blender normals kept (no recompute), Blender material slot names kept (M_Paint ...) and bound to the
    material instances MI_Paint ... in /Game/Forza/Materials/Cars (created by Tools/ue/cars_materials.py).
"""
import glob
import json
import math
import os
import traceback

import unreal

PROJECT = unreal.Paths.project_dir().replace("\\", "/")
EXPORTS = PROJECT + "Exports/"
MATERIAL_DIR = "/Game/Forza/Materials/Cars"
CARS_ROOT = "/Game/Forza/Cars"
TRAFFIC_ROOT = "/Game/Forza/Traffic"
REPORT_PATH = PROJECT + "Saved/CarsImport/report.json"

# Options: environment variables (standalone run through ue_cmd.ps1) or JOB_ARGS "only=car01,traffic02 skip_import=1" when the script is
# submitted to the persistent editor job server (Tools/ue/materials_job.ps1 ... -Args0 "..."): in a job the editor must NOT quit.
JOB_MODE = "JOB_ARGS" in globals()
_JOB_OPTS = dict(tok.split("=", 1) for tok in str(globals().get("JOB_ARGS", "")).split() if "=" in tok)


def _opt(name, env):
    return _JOB_OPTS.get(name, os.environ.get(env, ""))


ONLY = [s.strip() for s in _opt("only", "ROAM_CARS_ONLY").split(",") if s.strip()]
SKIP_IMPORT = _opt("skip_import", "ROAM_SKIP_IMPORT") == "1"
NO_QUIT = JOB_MODE or os.environ.get("ROAM_NO_QUIT", "") == "1"

SMS = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
EAL = unreal.EditorAssetLibrary

TOL_REL = 0.03      # relative bounds tolerance
TOL_ABS_CM = 2.5    # absolute bounds tolerance


def log(msg):
    unreal.log("CARS_IMPORT " + msg)


def warn(msg):
    unreal.log_warning("CARS_IMPORT " + msg)


# ------------------------------------------------------------------------------------------------------------------
# import
# ------------------------------------------------------------------------------------------------------------------
def make_import_options(nanite, collision):
    """Legacy FbxImportUI options. AssetTools converts them into the Interchange pipeline (the only options object the task path
    understands: an InterchangeGenericAssetsPipeline put into task.options is ignored, verified in the 5.8.2 source and by a test run).
    Every option is set explicitly (Docs/Tech/UE58_automation_pipeline.md 3.7)."""
    ui = unreal.FbxImportUI()
    ui.set_editor_property("automated_import_should_detect_type", False)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", False)
    ui.set_editor_property("import_animations", False)
    ui.set_editor_property("import_materials", False)   # slots keep the Blender names; we bind our own MI_* instances
    ui.set_editor_property("import_textures", False)
    d = ui.static_mesh_import_data
    d.set_editor_property("combine_meshes", False)
    # Interchange maps this flag to its "import collision" switch: it must be ON for the Body or the UCX_ hulls are skipped (verified:
    # with False only an already-imported mesh kept its hulls). Parts without UCX get a fallback hull that apply_mesh_settings removes.
    d.set_editor_property("auto_generate_collision", bool(collision))
    d.set_editor_property("generate_lightmap_u_vs", False)         # Lumen/VSM project, no static lighting
    d.set_editor_property("build_nanite", bool(nanite))
    d.set_editor_property("one_convex_hull_per_ucx", True)
    d.set_editor_property("remove_degenerates", True)
    d.set_editor_property("transform_vertex_to_absolute", True)
    d.set_editor_property("normal_import_method", unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS)  # keep Blender's normals
    d.set_editor_property("import_uniform_scale", 1.0)
    d.set_editor_property("import_rotation", unreal.Rotator(0, 0, 0))
    d.set_editor_property("import_translation", unreal.Vector(0, 0, 0))
    return ui


def import_fbx(fbx_path, dest_folder, asset_name, nanite, collision):
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", fbx_path)
    task.set_editor_property("destination_path", dest_folder)
    task.set_editor_property("destination_name", asset_name)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("replace_existing_settings", True)
    task.set_editor_property("save", True)
    task.set_editor_property("options", make_import_options(nanite, collision))
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    paths = [str(p) for p in task.get_editor_property("imported_object_paths")]
    return paths


# ------------------------------------------------------------------------------------------------------------------
# post-processing
# ------------------------------------------------------------------------------------------------------------------
def material_instance_for_slot(slot_name):
    """Blender slot 'M_Paint' -> /Game/Forza/Materials/Cars/MI_Paint (None when it does not exist yet)."""
    name = str(slot_name)
    if name.startswith("M_"):
        name = name[2:]
    asset = "%s/MI_%s" % (MATERIAL_DIR, name)
    if EAL.does_asset_exist(asset):
        return EAL.load_asset(asset)
    return None


def bind_materials(sm):
    """Assigns the MI_* instance of every slot by slot NAME. Returns (bound, missing)."""
    bound, missing = 0, []
    mats = list(sm.static_materials)
    for i, sm_mat in enumerate(mats):
        slot = str(sm_mat.get_editor_property("material_slot_name"))
        mi = material_instance_for_slot(slot)
        if mi is None:
            missing.append(slot)
            continue
        sm.set_material(i, mi)
        bound += 1
    return bound, missing


def apply_mesh_settings(sm, part, nanite, collision):
    """Re-applies Nanite / lightmap / collision flags after the import (the pipeline mapping is verified, not trusted)."""
    ns = SMS.get_nanite_settings(sm)
    if bool(ns.enabled) != bool(nanite):
        ns.enabled = bool(nanite)
        SMS.set_nanite_settings(sm, ns, True)
    try:
        bs = SMS.get_lod_build_settings(sm, 0)
        changed = False
        if bs.generate_lightmap_u_vs:
            bs.generate_lightmap_u_vs = False
            changed = True
        if bs.recompute_normals:
            bs.recompute_normals = False
            changed = True
        if changed:
            SMS.set_lod_build_settings(sm, 0, bs)
    except Exception as exc:  # noqa: BLE001
        warn("%s: build settings check failed: %s" % (sm.get_name(), exc))
    if part == "Body":
        try:
            body_setup = sm.get_editor_property("body_setup")
            body_setup.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_SIMPLE_AS_COMPLEX)
        except Exception as exc:  # noqa: BLE001
            warn("%s: could not set simple-as-complex: %s" % (sm.get_name(), exc))
    elif not collision and SMS.get_simple_collision_count(sm) > 0:
        SMS.remove_collisions(sm)


def mesh_bounds(sm):
    b = sm.get_bounds()
    o, e = b.origin, b.box_extent
    return (o.x - e.x, o.y - e.y, o.z - e.z), (o.x + e.x, o.y + e.y, o.z + e.z)


# ------------------------------------------------------------------------------------------------------------------
# expectations from the sidecar JSON (Blender car space, metres -> UE cm)
# ------------------------------------------------------------------------------------------------------------------
def ue(v):
    return (v[0] * 100.0, -v[1] * 100.0, v[2] * 100.0)


def check(rows, asset, what, got, want, tol_abs=TOL_ABS_CM, tol_rel=TOL_REL):
    ok = abs(got - want) <= max(tol_abs, abs(want) * tol_rel)
    rows.append((asset, what, got, want, ok))
    return ok


def wheel_entries(js):
    """[(part_name, center_blender_m, radius_m, width_m)] for both the dict (cars) and the list (traffic) schema."""
    out = []
    w = js["wheels"]
    if isinstance(w, dict):
        for key in ("FL", "FR", "RL", "RR"):
            out.append(("Wheel_" + key, w[key]["center"], w[key]["radius"], w[key]["width"]))
    else:
        for item in w:
            part = item["name"].replace(js["id"] + "_", "")
            out.append((part, item["center"], item["radius"], item["width"]))
    return out


def validate_vehicle(js, folder, asset_ids):
    """Compares imported bounds with the JSON. Returns the list of (asset, what, got, want, ok)."""
    rows = []
    vid = js["id"]
    dims = js["dimensions"]
    for part in js["files"].keys():
        path = "%s/SM_%s_%s" % (folder, vid, part)
        sm = EAL.load_asset(path)
        if sm is None:
            rows.append((path, "exists", 0, 1, False))
            continue
        (mn, mx) = mesh_bounds(sm)
        size = (mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2])
        name = "SM_%s_%s" % (vid, part)
        if part == "Body":
            wm = dims.get("width_with_mirrors", dims["width"])
            check(rows, name, "length_cm", size[0], dims["length"] * 100.0, tol_abs=6.0, tol_rel=0.05)
            check(rows, name, "width_cm", size[1], wm * 100.0, tol_abs=6.0, tol_rel=0.05)
            check(rows, name, "max_z_cm", mx[2], dims["height"] * 100.0, tol_abs=8.0, tol_rel=0.06)
            # origin conventions: ground under the middle of the wheelbase -> min z about 0 (underbody/tyre-clear), x centred
            check(rows, name, "center_x_cm", 0.5 * (mn[0] + mx[0]), 0.0, tol_abs=60.0, tol_rel=0.0)
            check(rows, name, "center_y_cm", 0.5 * (mn[1] + mx[1]), 0.0, tol_abs=8.0, tol_rel=0.0)
            ride = js.get("ride_height", 0.12) * 100.0   # underbody anywhere between the ground and a little above the ride height
            rows.append((name, "min_z_cm", mn[2], ride, -2.0 <= mn[2] <= ride + 15.0))
            check(rows, name, "ucx_hulls", float(SMS.get_convex_collision_count(sm)), float(len(js.get("ucx", []))), tol_abs=0.5, tol_rel=0.0)
        elif part == "Glass":
            check(rows, name, "center_y_cm", 0.5 * (mn[1] + mx[1]), 0.0, tol_abs=8.0, tol_rel=0.0)
            top = dims["height"] * 100.0   # glass tops out below the body roof (racks, scoops, box bodies): accept 50 % .. 100 %
            rows.append((name, "max_z_cm", mx[2], top, 0.50 * top <= mx[2] <= top + 2.0))
            check(rows, name, "collision", float(SMS.get_simple_collision_count(sm)), 0.0, tol_abs=0.5, tol_rel=0.0)
        elif part == "Interior":
            check(rows, name, "center_y_cm", 0.5 * (mn[1] + mx[1]), 0.0, tol_abs=10.0, tol_rel=0.0)
            check(rows, name, "collision", float(SMS.get_simple_collision_count(sm)), 0.0, tol_abs=0.5, tol_rel=0.0)
        elif part == "SteeringWheel":
            check(rows, name, "center_xyz_cm", math.sqrt(sum(((mn[i] + mx[i]) * 0.5) ** 2 for i in range(3))), 0.0, tol_abs=4.0, tol_rel=0.0)
        else:
            entries = {w[0]: w for w in wheel_entries(js)}
            w = entries.get(part)
            if w is None:
                rows.append((name, "wheel in json", 0, 1, False))
                continue
            radius = w[2] * 100.0
            width = w[3] * 100.0
            # wheel pivot at the axle centre: bounds centred on the origin; extent z/x = radius, y = width
            check(rows, name, "radius_x_cm", size[0] * 0.5, radius, tol_abs=2.0, tol_rel=0.04)
            check(rows, name, "radius_z_cm", size[2] * 0.5, radius, tol_abs=2.0, tol_rel=0.04)
            check(rows, name, "width_y_cm", size[1], width, tol_abs=4.0, tol_rel=0.20)
            centre = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, (mn[2] + mx[2]) * 0.5)
            check(rows, name, "pivot_offset_cm", math.sqrt(sum(c * c for c in centre)), 0.0, tol_abs=3.0, tol_rel=0.0)
            check(rows, name, "collision", float(SMS.get_simple_collision_count(sm)), 0.0, tol_abs=0.5, tol_rel=0.0)
        # shared checks
        want_nanite = part != "Glass"
        got_nanite = bool(SMS.get_nanite_settings(sm).enabled)
        rows.append((name, "nanite", 1.0 if got_nanite else 0.0, 1.0 if want_nanite else 0.0, got_nanite == want_nanite))
        slots = [str(m.get_editor_property("material_slot_name")) for m in sm.static_materials]
        expect_slots = js["material_slots"].get(part, [])
        missing = [s for s in expect_slots if s not in slots]
        rows.append((name, "slots_present", float(len(expect_slots) - len(missing)), float(len(expect_slots)), not missing))
        unbound = [str(m.get_editor_property("material_slot_name")) for m in sm.static_materials if m.get_editor_property("material_interface") is None]
        rows.append((name, "unbound_slots", float(len(unbound)), 0.0, not unbound))
    return rows


# ------------------------------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------------------------------
def collect_vehicles():
    items = []
    for kind, root, base in (("car", "Cars", CARS_ROOT), ("traffic", "Traffic", TRAFFIC_ROOT)):
        for jpath in sorted(glob.glob(EXPORTS + root + "/*/*.json")):
            with open(jpath, encoding="utf8") as fh:
                js = json.load(fh)
            if ONLY and not any(token in js["id"] for token in ONLY):
                continue
            items.append((kind, js, os.path.dirname(jpath).replace("\\", "/"), "%s/%s" % (base, js["id"])))
    return items


def process_vehicle(kind, js, src_dir, folder):
    vid = js["id"]
    result = {"id": vid, "kind": kind, "parts": {}, "failed": []}
    for part, fname in js["files"].items():
        fbx = "%s/%s" % (src_dir, fname)
        name = "SM_%s_%s" % (vid, part)
        nanite = part != "Glass"
        collision = part == "Body"
        if not os.path.exists(fbx):
            result["failed"].append(part + ": FBX missing")
            continue
        if not SKIP_IMPORT:
            EAL.make_directory(folder)
            paths = import_fbx(fbx, folder, name, nanite, collision)
            log("%s -> %s" % (fname, paths))
            if not paths:
                result["failed"].append(part + ": import produced nothing")
                continue
        for junk in EAL.list_assets(folder, recursive=False, include_folder=False):
            if os.path.basename(junk).startswith(("M_", "MI_", "T_")):
                EAL.delete_asset(junk.split(".")[0])      # stray materials from an earlier import with materials enabled
        sm = EAL.load_asset("%s/%s" % (folder, name))
        if sm is None or not isinstance(sm, unreal.StaticMesh):
            result["failed"].append(part + ": asset not found after import")
            continue
        apply_mesh_settings(sm, part, nanite, collision)
        bound, missing = bind_materials(sm)
        EAL.save_loaded_asset(sm)
        result["parts"][part] = {"bound": bound, "missing_mi": missing}
    return result


def main():
    items = collect_vehicles()
    log("vehicles to process: %s" % [i[1]["id"] for i in items])
    report = {"vehicles": [], "rows": []}
    total_rows, bad_rows = 0, 0
    for kind, js, src_dir, folder in items:
        try:
            res = process_vehicle(kind, js, src_dir, folder)
            rows = validate_vehicle(js, folder, None)
            res["rows_failed"] = []
            for asset, what, got, want, ok in rows:
                total_rows += 1
                tag = "OK  " if ok else "FAIL"
                unreal.log("CARS_VALIDATE %s %-40s %-16s got=%10.2f want=%10.2f" % (tag, asset, what, got, want))
                if not ok:
                    bad_rows += 1
                    res["rows_failed"].append("%s %s got=%.2f want=%.2f" % (asset, what, got, want))
            report["vehicles"].append(res)
        except Exception as exc:  # noqa: BLE001
            traceback.print_exc()
            warn("%s failed: %s" % (js["id"], exc))
            report["vehicles"].append({"id": js["id"], "kind": kind, "exception": str(exc)})
            bad_rows += 1
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf8") as fh:
        json.dump(report, fh, indent=1)
    unreal.log("CARS_RESULT vehicles=%d rows=%d failed_rows=%d" % (len(items), total_rows, bad_rows))


try:
    main()
except Exception:  # noqa: BLE001
    traceback.print_exc()
    unreal.log_error("CARS_RESULT exception")
finally:
    if not NO_QUIT:
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
