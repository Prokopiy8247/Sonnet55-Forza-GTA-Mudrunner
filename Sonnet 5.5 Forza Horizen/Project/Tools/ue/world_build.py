"""world_build - builds the Roamline open-world map  /Game/Forza/Maps/L_Main  step by step (re-runnable, one script, step flags).
Docs/Tech/WORLD_BUILD.md
(history of the duplicate-agent incident that produced this script: Tools/ue/F1_COORD.md)

ONE COMMAND for the whole world after the generator produced new data:   Tools/ue/world_rebuild.ps1
Run (headless commandlet host, quits when done; ROAM_WORLD_STEPS defaults to ALL steps):
    $env:ROAM_WORLD_STEPS = "phys,layers,material,data,map,landscape,wp,lighting,ocean,playerstart,nanite,save,verify"
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/world_build.py -LogName world_build -TimeoutSec 7200
or as a job in the shared editor server (single steps are fast there):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_build.py -TimeoutSec 7200 -Args0 "material"

Steps (in this order when several are given):
    phys        PM_Roam_* physical materials (Asphalt Concrete Dirt Gravel Grass Sand Snow Mud Rock)
    layers      landscape layer-info assets  /Game/Forza/World/Landscape/LI_<Layer>  (+ physical material per layer)
    material    M_Roam_Landscape (Tools/ue/world_material.py)
    data        DA_RoadNetwork + DA_WorldDefinition (C++ importers) under /Game/Forza/Data
    map         fresh World Partition map (deletes the old one including its external actors)
    landscape   landscape from the generated heightmap + weight maps (C++), runtime grid, GameMode override
    wp          runtime partition of the map (cell 256 m, loading range 1000 m)
    lighting    sun, sky atmosphere, sky light, height fog (tag RoamBasicLighting)
    ocean       Water plugin ocean + zone at z = 0 (fallback: a water plane)
    playerstart PlayerStart on the LOOP start road (right lane, heading along the road)
    roads       road / bridge / tunnel chunks of Exports/Roads/chunks.json (import_roads.py: Nanite meshes, complex collision, one actor each)
    nanite      build grass maps, physical-material data and the Nanite landscape meshes (slow)
    save        saves every dirty package and the map
    load        (not in the default list) loads the map first: use it with nanite/save/verify in a fresh editor
    verify      read-only checks (Tools/ue/world_verify.py: DA_* contents, landscape height vs road bed Z, wheel-channel traces)
Options (environment): ROAM_WORLD_MAP (map path, default L_Main), ROAM_WORLD_CROP "x,y,n" (build only a n-vertex window of the source starting
at x,y - the fast proving ground), ROAM_WORLD_NANITE=0 (skip Nanite).
Log markers: ROAM_WORLD_*
"""
import os
import shutil
import sys
import traceback

import unreal

import importlib  # noqa: E402

# NOT derived from __file__: in the editor job server __file__ points into Saved/MatJobs/inbox
_HERE = unreal.Paths.project_dir().replace("\\", "/") + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import world_lib as W  # noqa: E402

if "JOB_ARGS" in globals():
    importlib.reload(W)   # long-running job server: pick up edits of the helper modules
    W.set_job_args(JOB_ARGS)   # noqa: F821 - injected by the job server ("material,map crop=1,2,3 nanite=0")

# "load" is not part of the default full build (the map step leaves the new map loaded); use it with nanite/save in a fresh editor
ALL_STEPS = ["phys", "layers", "material", "data", "map", "landscape", "wp", "lighting", "ocean", "playerstart", "roads", "nanite", "save", "verify"]
ORDER = ["phys", "layers", "material", "data", "map", "load", "landscape", "wp", "lighting", "ocean", "playerstart", "roads", "nanite", "save", "verify"]
IN_JOB_SERVER = "JOB_ARGS" in globals()
MAP_PATH = W.option("MAP", W.MAP_MAIN)


# ---------------------------------------------------------------------------------------------------------------------------
def step_phys():
    t = W.Timer("phys")
    W.ensure_dir(W.PM_DIR)
    for name, index, friction, static_friction, density in W.SURFACES:
        path = "%s/PM_Roam_%s" % (W.PM_DIR, name)
        pm = W.ea.load_asset(path) if W.ea.does_asset_exist(path) else W.tools.create_asset("PM_Roam_" + name, W.PM_DIR, unreal.PhysicalMaterial, unreal.PhysicalMaterialFactoryNew())
        unreal.RoamEditorLibrary.configure_roam_physical_material(pm, index, friction, static_friction, density)
        W.ea.save_loaded_asset(pm)
        W.log("PM %s surface_index=%d friction=%.2f" % (path, index, friction))
    t.done()


def step_layers():
    t = W.Timer("layers")
    W.ensure_dir(W.LAYER_INFO_DIR)
    for layer in W.LAYERS:
        pm = W.load("%s/PM_Roam_%s" % (W.PM_DIR, W.LAYER_PHYS[layer]))
        info = unreal.RoamWorldBuilder.create_or_load_layer_info(layer, W.LAYER_INFO_DIR, "LI_" + layer, pm, True)
        if info is None:
            raise RuntimeError("layer info %s failed" % layer)
        W.save_asset(info)
        W.log("LAYER_INFO %s phys=%s" % (layer, W.LAYER_PHYS[layer]))
    t.done()


def step_material():
    t = W.Timer("material")
    import importlib
    import world_material
    importlib.reload(world_material)
    errors = world_material.build()
    t.done("compile_errors=%d" % len(errors))
    if errors:
        # a material with compile errors renders as the engine checkerboard in the game. Typical cause: "CollectionParameter has invalid parameter None":
        # MPC_Roam_World was rebuilt (new parameter GUIDs) after this material was compiled - re-run this step after every MPC rebuild
        raise RuntimeError("M_Roam_Landscape has %d compile error(s): %s" % (len(errors), str(errors[0])[:300]))


def step_data():
    t = W.Timer("data")
    W.ensure_dir(W.DATA_DIR)
    net, report = unreal.RoamWorldBuilder.create_road_network_asset(W.SRC + "/roads.json", W.DA_ROAD_NETWORK)
    W.log("ROADNET " + report.replace("\n", " | "))
    if net is None:
        raise RuntimeError("road network failed")
    definition, report = unreal.RoamWorldBuilder.create_world_definition_asset(
        W.SRC + "/world_meta.json", W.SRC + "/roads.json", W.TOOLS_UE + "/world_regions.json", W.DA_WORLD_DEFINITION)
    W.log("WORLDDEF " + report.replace("\n", " | "))
    if definition is None:
        raise RuntimeError("world definition failed")
    t.done()


def step_map():
    t = W.Timer("map")
    short = MAP_PATH.rsplit("/", 1)[1]
    content = W.ROOT + "Content"
    if W.ea.does_asset_exist(MAP_PATH):
        W.ea.delete_asset(MAP_PATH)
    for folder in ("__ExternalActors__", "__ExternalObjects__"):
        shutil.rmtree("%s/%s/Forza/Maps/%s" % (content, folder, short), ignore_errors=True)
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    ok = level_subsystem.new_level(MAP_PATH, True)
    W.log("NEW_LEVEL %s partitioned ok=%s" % (MAP_PATH, ok))
    if not ok:
        raise RuntimeError("new_level failed")
    world = W.get_world()
    W.log("WORLD %s partitioned=%s" % (world.get_name(), unreal.RoamWorldBuilder.describe_landscape(world)))
    ok = unreal.RoamEditorLibrary.set_world_game_mode_override(world, unreal.RoamGameMode.static_class())
    W.log("GAMEMODE_OVERRIDE ok=%s" % ok)
    t.done()


def hole_vertices_from_manifest():
    """Heightmap vertices (i, j) to hide, from the road chunk manifest (tunnel mouths; make_hole_mask.py writes the same set as a raster)."""
    import json
    path = W.ROOT + "Exports/Roads/chunks.json"
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as fh:
        man = json.load(fh)
    return man.get("landscape_hole_vertices", {}).get("vertices", [])


def _layer_infos():
    return [W.load("%s/LI_%s" % (W.LAYER_INFO_DIR, layer)) for layer in W.LAYERS]


def step_landscape():
    t = W.Timer("landscape")
    world = W.get_world()
    material = None
    if W.ea.does_asset_exist(W.LANDSCAPE_MAT):
        material = W.load(W.LANDSCAPE_MAT)
    else:
        W.warn("M_Roam_Landscape does not exist yet - using WorldGridMaterial")
        material = unreal.EditorAssetLibrary.load_asset("/Engine/EngineMaterials/WorldGridMaterial")
    p = unreal.RoamLandscapeBuildParams()
    p.set_editor_property("heightmap_file", W.SRC + "/heightmap_4033.r16")
    p.set_editor_property("source_size", W.SRC_SIZE)
    p.set_editor_property("layer_names", [unreal.Name(n) for n in W.LAYERS])
    p.set_editor_property("layer_files", ["%s/layer_%s.r8" % (W.SRC, n) for n in W.LAYERS])
    p.set_editor_property("layer_infos", _layer_infos())
    crop = W.option("CROP")
    if crop:
        cx, cy, cn = [int(v) for v in crop.split(",")]
        p.set_editor_property("crop_x", cx)
        p.set_editor_property("crop_y", cy)
        p.set_editor_property("crop_size", cn)
        W.log("CROP window x=%d y=%d size=%d" % (cx, cy, cn))
    p.set_editor_property("scale", W.SCALE)
    p.set_editor_property("source_centre_cm", unreal.Vector(0.0, 0.0, 0.0))
    p.set_editor_property("material", material)
    p.set_editor_property("default_physical_material", W.load("%s/PM_Roam_Asphalt" % W.PM_DIR))
    p.set_editor_property("collision_profile", "RoamWorldStatic")
    p.set_editor_property("world_partition_grid_components", W.GRID_COMPONENTS)
    p.set_editor_property("proxies_always_loaded", True)
    p.set_editor_property("enable_nanite", W.option("NANITE", "1") != "0")
    # landscape holes (tunnel mouths): heightmap vertices of Exports/Roads/chunks.json -> landscape visibility layer
    holes = hole_vertices_from_manifest()
    if W.option("HOLES", "1") != "0" and holes:
        p.set_editor_property("hole_vertices", [unreal.IntPoint(int(i), int(j)) for i, j in holes])
        W.log("HOLES %d source vertices handed to the visibility layer" % len(holes))
    result = unreal.RoamWorldBuilder.create_landscape_from_heightmap(world, p)
    W.log("LANDSCAPE success=%s holes_written=%s %s" % (
        result.get_editor_property("success"), result.get_editor_property("num_hole_vertices"), result.get_editor_property("report")))
    if not result.get_editor_property("success"):
        raise RuntimeError("landscape creation failed")
    W.log("LANDSCAPE_DESC " + unreal.RoamWorldBuilder.describe_landscape(world))
    t.done()


def step_wp():
    t = W.Timer("wp")
    world = W.get_world()
    # 256 m cells, 1000 m loading range: ~14 s of look-ahead at 250 km/h; landscape and roads are always loaded, only props stream
    msg = unreal.RoamWorldBuilder.configure_world_partition(world, 25600, 100000, True)
    W.log("WP " + msg)
    t.done()


def _spawn(cls, label, location=(0.0, 0.0, 0.0), rotation=(0.0, 0.0, 0.0), folder="Roam/Lighting"):
    actor = W.actors.spawn_actor_from_class(cls, unreal.Vector(*location), unreal.Rotator(*rotation))  # Rotator(roll, pitch, yaw)
    actor.set_actor_label(label)
    actor.set_folder_path(folder)
    try:
        actor.tags = [unreal.Name("RoamBasicLighting")] if folder.endswith("Lighting") else actor.tags
    except Exception:  # noqa: BLE001
        pass
    return actor


def step_lighting():
    t = W.Timer("lighting")
    sun = _spawn(unreal.DirectionalLight, "Sun", (0.0, 0.0, 50000.0), (0.0, -48.0, 215.0))
    sun_c = sun.get_component_by_class(unreal.DirectionalLightComponent)
    sun_c.set_mobility(unreal.ComponentMobility.MOVABLE)
    sun_c.set_editor_property("atmosphere_sun_light", True)
    sun_c.set_editor_property("atmosphere_sun_light_index", 0)
    sun_c.set_editor_property("intensity", 110000.0)   # physical lux; the project uses the extended luminance range
    atmosphere = _spawn(unreal.SkyAtmosphere, "SkyAtmosphere", (0.0, 0.0, 0.0))
    sky = _spawn(unreal.SkyLight, "SkyLight", (0.0, 0.0, 30000.0))
    sky_c = sky.get_component_by_class(unreal.SkyLightComponent)
    sky_c.set_mobility(unreal.ComponentMobility.MOVABLE)
    sky_c.set_editor_property("real_time_capture", True)
    fog = _spawn(unreal.ExponentialHeightFog, "HeightFog", (0.0, 0.0, 0.0))
    fog_c = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
    fog_c.set_editor_property("fog_density", 0.004)
    fog_c.set_editor_property("fog_height_falloff", 0.15)
    fog_c.set_editor_property("start_distance", 2000.0)
    fog_c.set_editor_property("enable_volumetric_fog", True)
    for a in (sun, atmosphere, sky, fog):
        try:
            a.set_editor_property("is_spatially_loaded", False)
        except Exception:  # noqa: BLE001
            pass
    t.done()


def step_ocean():
    t = W.Timer("ocean")
    import world_water
    import importlib
    importlib.reload(world_water)
    world_water.build()
    t.done()


def step_playerstart():
    t = W.Timer("playerstart")
    x, y, z, heading = W.road_sample("HWY_EAST", 220.0)
    import math
    h = math.radians(heading)
    lane = 0.5 * 1.0 + 3.6 * 0.5   # median/2 + lane/2 of the HIGHWAY (right-hand traffic, lane +1)
    px = x + (-math.sin(h)) * lane
    py = y + math.cos(h) * lane
    start = W.actors.spawn_actor_from_class(unreal.PlayerStart, unreal.Vector(px * 100.0, py * 100.0, z * 100.0 + 150.0), unreal.Rotator(0.0, 0.0, heading))
    start.set_actor_label("PlayerStart_LoopStart")
    start.set_folder_path("Roam/Spawn")
    W.log("PLAYER_START x=%.1f y=%.1f z=%.1f heading=%.1f (HWY_EAST s=220, right lane)" % (px, py, z + 1.5, heading))
    t.done()


def step_roads():
    """Imports every chunk of Exports/Roads/chunks.json (Tools/ue/import_roads.py): Nanite static meshes, complex-as-simple collision,
    one StaticMeshActor per chunk; deletes road meshes / actors that are no longer in the manifest. Options: roads_only=<ids>."""
    import runpy
    t = W.Timer("roads")
    ensure_map_loaded()
    only = W.option("ROADS_ONLY", "")
    if only:
        os.environ["ROAM_ROADS_ONLY"] = only
    else:
        os.environ.pop("ROAM_ROADS_ONLY", None)
    for flag in ("SKIP_EXISTING", "REFRESH", "NO_ACTORS", "LIMIT"):      # options  roads_refresh=1  roads_no_actors=1 ...
        value = W.option("ROADS_" + flag, "")
        if value:
            os.environ["ROAM_ROADS_" + flag] = value
        else:
            os.environ.pop("ROAM_ROADS_" + flag, None)
    ns = runpy.run_path(W.TOOLS_UE + "/import_roads.py")
    ok = ns.get("OK")
    t.done("ok=%s" % ok)
    if not ok:
        raise RuntimeError("road import reported problems (ROADS_WARN lines in the log)")


def ensure_map_loaded():
    """Loads MAP_PATH into the editor unless it already is the current world (a fresh editor starts on the default map)."""
    short = MAP_PATH.rsplit("/", 1)[1]
    world = W.get_world()
    if world is None or world.get_name() != short:
        t0 = W.time.time()
        ok = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(MAP_PATH)
        W.log("LOAD_LEVEL %s ok=%s %.1fs" % (MAP_PATH, ok, W.time.time() - t0))
        if not ok:
            raise RuntimeError("load_level failed: " + MAP_PATH)
        world = W.get_world()
    return world


def step_load():
    t = W.Timer("load")
    world = ensure_map_loaded()
    W.log("LANDSCAPE_DESC " + unreal.RoamWorldBuilder.describe_landscape(world))
    t.done()


def step_nanite():
    t = W.Timer("nanite")
    world = ensure_map_loaded()
    nanite = W.option("NANITE", "1") != "0"
    msg = unreal.RoamWorldBuilder.build_landscape_data(world, True, True, nanite)
    W.log("BUILD " + msg)
    W.log("LANDSCAPE_DESC " + unreal.RoamWorldBuilder.describe_landscape(world))
    t.done()


def step_save():
    t = W.Timer("save")
    ok = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
    W.log("SAVE_DIRTY ok=%s" % ok)
    world = W.get_world()
    try:
        saved = unreal.EditorLoadingAndSavingUtils.save_map(world, MAP_PATH)
        W.log("SAVE_MAP %s ok=%s" % (MAP_PATH, saved))
    except Exception as exc:  # noqa: BLE001
        W.warn("save_map: %r" % (exc,))
    t.done()


def step_verify():
    """Read-only checks of the freshly built world (Tools/ue/world_verify.py): assets, landscape-vs-road alignment, wheel traces. A failed check
    is logged as ROAM_VERIFY_FAIL / an Error line but does not stop the build (the numbers are what the report needs)."""
    t = W.Timer("verify")
    import world_verify
    importlib.reload(world_verify)
    failures = world_verify.run(["data", "ground", "wheels"])
    t.done("failures=%d" % failures)


STEP_FUNCS = {
    "phys": step_phys, "layers": step_layers, "material": step_material, "data": step_data, "map": step_map, "landscape": step_landscape,
    "wp": step_wp, "lighting": step_lighting, "ocean": step_ocean, "playerstart": step_playerstart, "roads": step_roads, "load": step_load, "nanite": step_nanite, "save": step_save, "verify": step_verify,
}


def main():
    wanted = W.steps_from_environment(ALL_STEPS)
    unknown = [s for s in wanted if s not in STEP_FUNCS]
    if unknown:
        W.err("unknown steps: %s (known: %s)" % (unknown, ORDER))
        return False
    ordered = [s for s in ORDER if s in wanted]
    W.log("RUN steps=%s map=%s" % (",".join(ordered), MAP_PATH))
    for name in ordered:
        try:
            STEP_FUNCS[name]()
        except Exception:  # noqa: BLE001 - report with a traceback, stop at the first failure
            W.err("STEP_FAILED %s\n%s" % (name, traceback.format_exc()))
            return False
    W.log("RUN_DONE")
    return True


_ok = main()
if not IN_JOB_SERVER:
    unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
