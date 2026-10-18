"""
import_roads.py - UE 5.8 editor Python: import the road chunk FBX files and place one static-mesh actor per chunk.

Produced by the Blender pipeline (Tools/blender/world/build_roads.py -> Exports/Roads/*.fbx + Exports/Roads/chunks.json).
Docs/Tech/ROADS_PIPELINE.md explains the whole chain.  Run it in the editor of the WORLD map (windowed or headless), e.g.

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/import_roads.py -Map /Game/Forza/Maps/<world>

What it does (idempotent: safe to run again, re-importing replaces the assets, actors are found by tag and rebuilt):
  1. reads Exports/Roads/chunks.json (chunk centres in UE metres, material slots, tri counts, ids);
  2. imports every chunk FBX as ONE static mesh  /Game/Forza/World/Roads/Meshes/SM_<chunk id>  (Interchange engine, legacy options
     object): Nanite ON, no lightmap UVs, imported normals, collision = USE COMPLEX AS SIMPLE (the render triangles drive the wheels);
  3. maps each material slot BY NAME to /Game/Forza/Materials/Roads/MI_<name without 'M_'>  (M_Road_Asphalt -> MI_Road_Asphalt ...);
     a missing instance is created from a simple fallback parent material (flat colour, physical material PM_Roam_*) so the roads
     are visible and drivable before the real world materials exist;
  4. spawns one StaticMeshActor per chunk at the chunk centre (cm = metres * 100, rotation 0, scale 1), label 'Road_<id>', folder
     'Roads/<kind>[/<road>]', tags RoamRoad / RoamDrivable / RoamRoadChunk:<id>, collision profile RoamWorldStatic, static mobility,
     spatially loaded = False (as specified by the lead; set ROAM_ROADS_SPATIAL=1 to let World Partition stream them instead);
  5. saves everything and prints  ROADS_IMPORT ...  summary / ROADS_WARN ... lines (grep them in the log).

Environment switches (all optional):
    ROAM_ROADS_ONLY=RC_HWY_EAST_01,HWY_EAST   only these chunk ids / road ids
    ROAM_ROADS_LIMIT=5                         import at most N chunks (smoke test)
    ROAM_ROADS_SKIP_EXISTING=1                 do not re-import meshes that already exist
    ROAM_ROADS_REFRESH=1                       like SKIP_EXISTING, but re-applies the mesh settings (Nanite full-resolution fallback = collision, materials)
    ROAM_ROADS_NO_ACTORS=1                     import meshes + materials only
    ROAM_ROADS_NO_SAVE=1                       leave assets / level dirty
    ROAM_ROADS_DRY=1                           only read the manifest, check the FBX files and print a few placements (no UE changes)
    ROAM_ROADS_SPATIAL=1                       actors are spatially loaded (World Partition streaming)
"""
import json
import os
import time

import unreal

LOG = "ROADS_IMPORT"
MESH_DIR = "/Game/Forza/World/Roads/Meshes"
MAT_DIR = "/Game/Forza/Materials/Roads"
PM_DIR = "/Game/Forza/Materials/Physical"
ROOT_FOLDER = "Roads"

# slot name -> (fallback surface for the physical material, base colour (linear), roughness, emissive colour)
FALLBACK = {
    "M_Road_Asphalt":    ("Asphalt",  (0.045, 0.045, 0.05), 0.85, None),
    "M_Road_Concrete":   ("Concrete", (0.36, 0.35, 0.33), 0.80, None),
    "M_Road_Dirt":       ("Dirt",     (0.26, 0.17, 0.10), 0.95, None),
    "M_Road_Gravel":     ("Gravel",   (0.30, 0.27, 0.23), 0.95, None),
    "M_Curb":            ("Concrete", (0.52, 0.51, 0.47), 0.80, None),
    "M_Bridge_Concrete": ("Concrete", (0.42, 0.41, 0.39), 0.85, None),
    "M_Bridge_Steel":    ("Concrete", (0.50, 0.53, 0.57), 0.45, None),
    "M_Tunnel_Wall":     ("Concrete", (0.50, 0.48, 0.43), 0.90, None),
    "M_Tunnel_Light":    ("Concrete", (1.00, 0.92, 0.75), 0.50, (8.0, 7.0, 5.0)),
    "M_Road_Marking":    ("Asphalt",  (0.85, 0.85, 0.80), 0.60, None),
}


def log(msg):
    unreal.log("%s %s" % (LOG, msg))


def warn(msg):
    unreal.log_warning("ROADS_WARN %s" % msg)


def env_flag(name):
    return os.environ.get(name, "") not in ("", "0", "false", "False")


# ----------------------------------------------------------------------------------------------------------------------
# materials
def _asset(path):
    return unreal.EditorAssetLibrary.load_asset(path) if unreal.EditorAssetLibrary.does_asset_exist(path) else None


def ensure_fallback_parent(surface):
    """One simple fallback parent Material per physical surface: parameters BaseColor / Roughness / EmissiveColor."""
    name = "M_RoadFallback_%s" % surface
    path = "%s/%s" % (MAT_DIR, name)
    mat = _asset(path)
    if mat is not None:
        return mat
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    mat = tools.create_asset(name, MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
    mel = unreal.MaterialEditingLibrary
    col = mel.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -420, -120)
    col.set_editor_property("parameter_name", "BaseColor")
    col.set_editor_property("default_value", unreal.LinearColor(0.2, 0.2, 0.2, 1.0))
    rough = mel.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -420, 100)
    rough.set_editor_property("parameter_name", "Roughness")
    rough.set_editor_property("default_value", 0.85)
    emis = mel.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -420, 260)
    emis.set_editor_property("parameter_name", "EmissiveColor")
    emis.set_editor_property("default_value", unreal.LinearColor(0.0, 0.0, 0.0, 1.0))
    mel.connect_material_property(col, "", unreal.MaterialProperty.MP_BASE_COLOR)
    mel.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    mel.connect_material_property(emis, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    pm = _asset("%s/PM_Roam_%s" % (PM_DIR, surface))
    if pm is not None:
        try:
            mat.set_editor_property("phys_material", pm)
        except Exception as exc:                  # property name differences must not stop the import
            warn("cannot set phys_material on %s: %s" % (name, exc))
    else:
        warn("physical material PM_Roam_%s not found" % surface)
    mel.recompile_material(mat)
    unreal.EditorAssetLibrary.save_loaded_asset(mat)
    log("created fallback parent material %s" % path)
    return mat


def mi_path(slot_name):
    base = slot_name[2:] if slot_name.startswith("M_") else slot_name
    return "%s/MI_%s" % (MAT_DIR, base)


def ensure_instance_physmat(mi, slot_name):
    """The wheel traces read the physical material of the hit material (complex collision): the road MI_* (made by the materials agent) must carry
    the matching PM_Roam_* (asphalt / concrete / dirt / gravel, FALLBACK table). Sets bOverridePhysMaterial + PhysMaterial when they differ."""
    surface = FALLBACK.get(slot_name, ("Asphalt",))[0]
    pm = _asset("%s/PM_Roam_%s" % (PM_DIR, surface))
    if pm is None:
        warn("physical material PM_Roam_%s not found for %s" % (surface, slot_name))
        return
    try:
        cur = mi.get_editor_property("phys_material")
        if bool(mi.get_editor_property("override_phys_material")) and cur is not None and cur.get_path_name() == pm.get_path_name():
            return
        mi.set_editor_property("override_phys_material", True)
        mi.set_editor_property("phys_material", pm)
        unreal.EditorAssetLibrary.save_loaded_asset(mi, only_if_is_dirty=False)
        log("physical material %s set on %s" % (pm.get_name(), mi.get_name()))
    except Exception as exc:
        warn("cannot set the physical material on %s: %s" % (mi.get_name(), exc))


def ensure_material_instance(slot_name):
    """MI_<name> from /Game/Forza/Materials/Roads (the real one when it exists), else a fallback instance."""
    path = mi_path(slot_name)
    mi = _asset(path)
    if mi is not None:
        ensure_instance_physmat(mi, slot_name)
        return mi
    surface, colour, rough, emis = FALLBACK.get(slot_name, ("Asphalt", (0.2, 0.2, 0.2), 0.8, None))
    parent = ensure_fallback_parent(surface)
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    name = path.rsplit("/", 1)[1]
    mi = tools.create_asset(name, MAT_DIR, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel = unreal.MaterialEditingLibrary
    mel.set_material_instance_parent(mi, parent)
    mel.set_material_instance_vector_parameter_value(mi, "BaseColor", unreal.LinearColor(colour[0], colour[1], colour[2], 1.0))
    mel.set_material_instance_scalar_parameter_value(mi, "Roughness", rough)
    if emis:
        mel.set_material_instance_vector_parameter_value(mi, "EmissiveColor", unreal.LinearColor(emis[0], emis[1], emis[2], 1.0))
    pm = _asset("%s/PM_Roam_%s" % (PM_DIR, surface))
    if pm is not None:
        try:
            mi.set_editor_property("override_phys_material", True)
            mi.set_editor_property("phys_material", pm)
        except Exception:
            pass
    mel.update_material_instance(mi)
    unreal.EditorAssetLibrary.save_loaded_asset(mi)
    log("created fallback material instance %s (replace it with the real world material)" % path)
    return mi


# ----------------------------------------------------------------------------------------------------------------------
# meshes
def import_static_fbx(fbx_path, dest_path, dest_name):
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    ui = unreal.FbxImportUI()
    ui.set_editor_property("automated_import_should_detect_type", False)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", False)
    ui.set_editor_property("import_animations", False)
    ui.set_editor_property("import_materials", False)        # slots are bound to our own MI_* afterwards
    ui.set_editor_property("import_textures", False)
    d = ui.static_mesh_import_data
    d.set_editor_property("combine_meshes", False)
    d.set_editor_property("auto_generate_collision", False)   # collision = complex as simple (set below)
    d.set_editor_property("generate_lightmap_u_vs", False)   # Lumen / VSM project
    d.set_editor_property("build_nanite", True)
    d.set_editor_property("remove_degenerates", True)
    d.set_editor_property("transform_vertex_to_absolute", True)
    d.set_editor_property("normal_import_method", unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS)
    d.set_editor_property("import_uniform_scale", 1.0)
    d.set_editor_property("import_rotation", unreal.Rotator(0, 0, 0))
    t = unreal.AssetImportTask()
    t.set_editor_property("filename", fbx_path)
    t.set_editor_property("destination_path", dest_path)
    t.set_editor_property("destination_name", dest_name)
    t.set_editor_property("automated", True)
    t.set_editor_property("save", False)
    t.set_editor_property("replace_existing", True)
    t.set_editor_property("replace_existing_settings", True)
    t.set_editor_property("options", ui)
    tools.import_asset_tasks([t])
    for obj in list(t.get_objects()):
        if isinstance(obj, unreal.StaticMesh):
            return obj
    return None


def configure_mesh(sm, rec, mis):
    """Nanite on, collision complex-as-simple, material slots by name."""
    sms = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    ns = sms.get_nanite_settings(sm)
    # The physics triangle mesh of "complex as simple" is cooked from the Nanite FALLBACK mesh. The default (fallback target AUTO) reduces a
    # 4 000-triangle road ribbon to ~300 vertices: bridge decks vanish for the wheel traces and the surface sits up to 2.9 m off. A full
    # resolution fallback (100 % of the triangles; the whole network is 0.5 M triangles) makes the collision equal to the render mesh.
    want = (True, unreal.NaniteFallbackTarget.PERCENT_TRIANGLES, 1.0, unreal.NaniteGenerateFallback.ENABLED)
    have = (bool(ns.enabled), ns.fallback_target, float(ns.fallback_percent_triangles), ns.generate_fallback)
    if have != want:
        ns.enabled = True
        ns.fallback_target = unreal.NaniteFallbackTarget.PERCENT_TRIANGLES
        ns.fallback_percent_triangles = 1.0
        ns.generate_fallback = unreal.NaniteGenerateFallback.ENABLED
        sms.set_nanite_settings(sm, ns, True)
    body = sm.get_editor_property("body_setup")
    body.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    try:
        body.invalidate_physics_data()
    except Exception:
        pass
    sm.set_editor_property("body_setup", body)
    sm.set_editor_property("has_navigation_data", False)
    slots = list(sm.get_editor_property("static_materials"))
    for i, slot in enumerate(slots):
        name = str(slot.get_editor_property("material_slot_name"))
        mi = mis.get(name)
        if mi is None:
            mi = mis[name] = ensure_material_instance(name)
            warn("slot '%s' of %s was not in the manifest slot list" % (name, rec["id"]))
        sm.set_material(i, mi)
    sm.modify()
    unreal.EditorAssetLibrary.save_loaded_asset(sm, only_if_is_dirty=False)
    return sms


def verify_mesh(sm, rec):
    """Bounds must equal the manifest size (cm) within 2 %; Nanite must be on."""
    box = sm.get_bounding_box()
    ext = box.max - box.min
    want = [v * 100.0 for v in rec["size_m"]]          # manifest is in Blender axes: size in (x, y, z) is axis-aligned either way
    got = [ext.x, ext.y, ext.z]
    ok = all(abs(g - w) <= max(0.02 * w, 5.0) for g, w in zip(got, want))
    if not ok:
        warn("%s bounds %s cm differ from manifest %s cm" % (rec["id"], [round(g, 1) for g in got], [round(w, 1) for w in want]))
    sms = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    if not sms.get_nanite_settings(sm).enabled:
        warn("%s: Nanite is not enabled" % rec["id"])
        ok = False
    return ok


# ----------------------------------------------------------------------------------------------------------------------
# actors
def existing_chunk_actors():
    sub = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    out = {}
    for a in sub.get_all_level_actors():
        for tag in a.tags:
            t = str(tag)
            if t.startswith("RoamRoadChunk:"):
                out[t.split(":", 1)[1]] = a
    return sub, out


def spawn_chunk_actor(sub, existing, sm, rec, spatial):
    old = existing.get(rec["id"])
    if old is not None:
        sub.destroy_actor(old)
    c = rec["centre_ue_m"]
    loc = unreal.Vector(c[0] * 100.0, c[1] * 100.0, c[2] * 100.0)
    actor = sub.spawn_actor_from_object(sm, loc, unreal.Rotator(0, 0, 0))
    if actor is None:
        warn("could not spawn actor for %s" % rec["id"])
        return None
    actor.set_actor_label("Road_%s" % rec["id"])
    folder = "%s/%s" % (ROOT_FOLDER, rec["kind"].capitalize())
    if rec.get("road"):
        folder += "/%s" % rec["road"]
    actor.set_folder_path(folder)
    tags = [unreal.Name("RoamRoad"), unreal.Name("RoamRoadChunk:%s" % rec["id"]), unreal.Name("RoamRoad_%s" % rec["kind"])]
    if rec["kind"] in ("road", "junction", "bridge", "tunnel"):
        tags.append(unreal.Name("RoamDrivable"))
    actor.tags = tags
    comp = actor.get_editor_property("static_mesh_component")
    comp.set_mobility(unreal.ComponentMobility.STATIC)
    comp.set_collision_profile_name("RoamWorldStatic")
    try:
        actor.set_editor_property("is_spatially_loaded", bool(spatial))
    except Exception as exc:
        warn("is_spatially_loaded not settable on %s: %s" % (rec["id"], exc))
    return actor


def purge_stale(man, sub, existing):
    """The manifest is the source of truth: destroy road actors and delete SM_* meshes of chunks that are no longer in it."""
    ids = {c["id"] for c in man["chunks"]}
    n_act = n_mesh = 0
    for cid, actor in list(existing.items()):
        if cid not in ids:
            sub.destroy_actor(actor)
            existing.pop(cid, None)
            n_act += 1
    keep = {"SM_%s" % i for i in ids}
    for path in unreal.EditorAssetLibrary.list_assets(MESH_DIR, recursive=False, include_folder=False):
        name = path.split(".")[0].rsplit("/", 1)[1]
        if name not in keep:
            if unreal.EditorAssetLibrary.delete_asset(path):
                n_mesh += 1
    log("purged %d stale chunk actors and %d stale road meshes (not in the manifest)" % (n_act, n_mesh))


# ----------------------------------------------------------------------------------------------------------------------
def main():
    t0 = time.time()
    project = unreal.Paths.project_dir()
    manifest_path = os.path.join(project, "Exports", "Roads", "chunks.json")
    if not os.path.exists(manifest_path):
        unreal.log_error("%s no manifest at %s (run Tools/blender/world/build_roads.py first)" % (LOG, manifest_path))
        return False
    man = json.load(open(manifest_path, "r", encoding="utf8"))
    chunks = man["chunks"]
    only = [s.strip() for s in os.environ.get("ROAM_ROADS_ONLY", "").split(",") if s.strip()]
    if only:
        low = [o.lower() for o in only]
        chunks = [c for c in chunks if c["id"].lower() in low or (c.get("road") or "").lower() in low]
    limit = int(os.environ.get("ROAM_ROADS_LIMIT", "0") or 0)
    if limit:
        chunks = chunks[:limit]
    skip_existing = env_flag("ROAM_ROADS_SKIP_EXISTING") or env_flag("ROAM_ROADS_REFRESH")
    refresh = env_flag("ROAM_ROADS_REFRESH")
    no_actors = env_flag("ROAM_ROADS_NO_ACTORS")
    no_save = env_flag("ROAM_ROADS_NO_SAVE")
    spatial = env_flag("ROAM_ROADS_SPATIAL")
    log("manifest: %d chunks selected of %d, %d tris" % (len(chunks), len(man["chunks"]), sum(c["tris"] for c in chunks)))
    if env_flag("ROAM_ROADS_DRY"):
        # no asset or level changes: manifest + FBX presence + where the actors would go
        missing = [c["id"] for c in chunks if not os.path.exists(os.path.join(project, c["fbx"].replace("/", os.sep)))]
        for c in chunks[:5]:
            log("dry: %s -> /Game/Forza/World/Roads/Meshes/SM_%s at cm (%.0f, %.0f, %.0f) slots %s" % (
                c["id"], c["id"], c["centre_ue_m"][0] * 100, c["centre_ue_m"][1] * 100, c["centre_ue_m"][2] * 100, c["material_slots"]))
        log("dry run: %d FBX missing %s" % (len(missing), missing[:5]))
        return not missing
    unreal.EditorAssetLibrary.make_directory(MESH_DIR)
    unreal.EditorAssetLibrary.make_directory(MAT_DIR)
    mis = {}
    for name in man.get("materials", list(FALLBACK.keys())):
        mis[name] = ensure_material_instance(name)
    sub, existing = existing_chunk_actors()
    if not only and not limit and not no_actors:
        purge_stale(man, sub, existing)
    n_imp = n_spawn = n_bad = 0
    for k, rec in enumerate(chunks):
        name = "SM_%s" % rec["id"]
        apath = "%s/%s" % (MESH_DIR, name)
        try:
            sm = None
            if skip_existing and unreal.EditorAssetLibrary.does_asset_exist(apath):
                sm = unreal.EditorAssetLibrary.load_asset(apath)
                if refresh:                               # re-apply Nanite / collision / material settings without re-importing the FBX
                    configure_mesh(sm, rec, mis)
                    n_imp += 1
            else:
                fbx = os.path.join(project, rec["fbx"].replace("/", os.sep))
                if not os.path.exists(fbx):
                    warn("missing FBX %s" % fbx)
                    n_bad += 1
                    continue
                sm = import_static_fbx(fbx, MESH_DIR, name)
                if sm is None:
                    warn("import produced no static mesh for %s" % rec["id"])
                    n_bad += 1
                    continue
                configure_mesh(sm, rec, mis)
                n_imp += 1
            try:
                if not verify_mesh(sm, rec):
                    n_bad += 1
            except Exception as exc:                  # verification must never stop the import
                warn("verify_mesh failed for %s: %s" % (rec["id"], exc))
            if not no_actors:
                if spawn_chunk_actor(sub, existing, sm, rec, spatial) is not None:
                    n_spawn += 1
        except Exception as exc:
            import traceback
            warn("chunk %s failed: %s\n%s" % (rec["id"], exc, traceback.format_exc()))
            n_bad += 1
        if (k + 1) % 20 == 0:
            log("progress %d / %d  (%.0fs)" % (k + 1, len(chunks), time.time() - t0))
    if not no_save:
        unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
    hv = man.get("landscape_hole_vertices", {})
    if hv.get("count"):
        log("NOTE: the Landscape needs %d hidden vertices at %d tunnel mouths and the bridge ends (chunks.json -> landscape_hole_vertices; "
            "Tools/blender/world/make_hole_mask.py writes the raster), see Docs/Tech/ROADS_PIPELINE.md section 7" % (
                hv["count"], len(man.get("landscape_holes", []))))
    log("done: imported=%d spawned=%d problems=%d in %.0fs" % (n_imp, n_spawn, n_bad, time.time() - t0))
    return n_bad == 0


try:
    OK = main()
except Exception as exc:                    # keep the failure visible in the log and in the exit status of ue_cmd.ps1
    import traceback
    unreal.log_error("%s FAILED: %s\n%s" % (LOG, exc, traceback.format_exc()))
    OK = False
