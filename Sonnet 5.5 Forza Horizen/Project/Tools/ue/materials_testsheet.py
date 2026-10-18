"""Material test sheet: builds /Game/Forza/Maps/L_MaterialTest (stations of spheres / planes / test meshes lit by sun + sky) and renders
screenshots with a SceneCapture2D into Saved/MatShots/<station>_<shot>.png  (open them with the Read tool).

Run through the job server:   materials_job.ps1 Tools/ue/materials_build.py -Args0 "testsheet=road"      (station names, comma separated, or 'all')
Rendering is asynchronous (several frames per shot: sky capture, streaming, exposure); the job returns at once and logs
MAT_SHEET_SHOT <name> when a PNG is written and MAT_SHEET_DONE at the end.  Add 'save' to the station list to also save the map.
"""
import math
import os
import sys
import time
import traceback

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_testsheet.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import ROOT, MAT_ROOT, ea, at, ensure_dir, exists, load, log  # noqa: E402
import materials_testmesh as TM  # noqa: E402

TEST_DIR = MAT_ROOT + "/Test"
SHOT_DIR = ROOT + "Saved/MatShots"
MAP_PATH = "/Game/Forza/Maps/L_MaterialTest"
MPC_PATH = MAT_ROOT + "/MPC_Roam_World"
# sheet state lives on the `unreal` module so that it survives `importlib.reload(materials_testsheet)` (every job reloads this module); a second
# sheet job that arrives while a sheet is still shooting is QUEUED (added by M-B: two agents' sheets cancelled each other's tick callback)
_STATE = getattr(unreal, "_mat_sheet_state", None)
if _STATE is None:
    _STATE = {"handle": None}
    unreal._mat_sheet_state = _STATE
_STATE.setdefault("active", False)
_STATE.setdefault("pending", [])
_STATE.setdefault("last", 0.0)


def _hold(on):
    """Saved/MatJobs/hold_sheet keeps the job server alive while a sheet shoots (materials_server._held); released when the last queued sheet is done."""
    path = ROOT + "Saved/MatJobs/hold_sheet"
    try:
        if on:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                fh.write("sheet running")
        elif os.path.exists(path):
            os.remove(path)
    except OSError:
        pass


# ------------------------------------------------------------------------------------------------------------------------------
# test meshes (ASCII FBX written by materials_testmesh, imported once)
# ------------------------------------------------------------------------------------------------------------------------------
def ensure_meshes(force=False):
    ensure_dir(TEST_DIR)
    out_dir = ROOT + "Saved/MatJobs/testmesh"
    files = TM.write_all(out_dir)
    tasks, names = [], []
    for name, path in files.items():
        if exists(TEST_DIR + "/" + name) and not force:
            continue
        t = unreal.AssetImportTask()
        t.set_editor_property("filename", path)
        t.set_editor_property("destination_path", TEST_DIR)
        t.set_editor_property("destination_name", name)
        t.set_editor_property("automated", True)
        t.set_editor_property("replace_existing", True)
        t.set_editor_property("replace_existing_settings", True)
        t.set_editor_property("save", True)
        ui = unreal.FbxImportUI()
        ui.set_editor_property("import_mesh", True)
        ui.set_editor_property("import_as_skeletal", False)
        ui.set_editor_property("import_materials", False)
        ui.set_editor_property("import_textures", False)
        ui.set_editor_property("automated_import_should_detect_type", False)
        ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
        sm = ui.get_editor_property("static_mesh_import_data")
        sm.set_editor_property("vertex_color_import_option", unreal.VertexColorImportOption.REPLACE)
        sm.set_editor_property("generate_lightmap_u_vs", False)
        sm.set_editor_property("auto_generate_collision", False)
        sm.set_editor_property("build_nanite", False)
        t.set_editor_property("options", ui)
        tasks.append(t)
        names.append(name)
    if tasks:
        at.import_asset_tasks(tasks)
    for n in names:
        sm = ea.load_asset(TEST_DIR + "/" + n)
        if sm is None:
            unreal.log_error("MAT_ERR test mesh %s not imported" % n)
        else:
            b = sm.get_bounds()
            log("test mesh %s uv_channels=%d box_extent=(%.0f,%.0f,%.0f)" % (
                n, unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem).get_num_uv_channels(sm, 0),
                b.box_extent.x, b.box_extent.y, b.box_extent.z))


# ------------------------------------------------------------------------------------------------------------------------------
# stations: each returns a list of shots
# ------------------------------------------------------------------------------------------------------------------------------
class Ctx(object):
    def __init__(self, world):
        self.world = world
        self.eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
        self.actors = []

    def spawn(self, cls, loc=(0, 0, 0), rot=(0, 0, 0)):
        a = self.eas.spawn_actor_from_class(cls, unreal.Vector(*loc), unreal.Rotator(rot[0], rot[1], rot[2]))
        a.tags = [unreal.Name("matsheet")]  # marker: the next run destroys these actors instead of creating a new map (new_blank_map crashed python)
        self.actors.append(a)
        return a

    def mesh(self, mesh_path, loc, mats, rot=(0, 0, 0), scale=(1, 1, 1), label=None):
        a = self.spawn(unreal.StaticMeshActor, loc, rot)
        c = a.static_mesh_component
        c.set_mobility(unreal.ComponentMobility.MOVABLE)
        sm = ea.load_asset(mesh_path)
        if sm is None:
            raise RuntimeError("mesh not found " + mesh_path)
        c.set_static_mesh(sm)
        a.set_actor_scale3d(unreal.Vector(*scale))
        for i, mp in enumerate(mats if isinstance(mats, (list, tuple)) else [mats]):
            mat = ea.load_asset(mp) if isinstance(mp, str) else mp
            if mat is None:
                raise RuntimeError("material not found %s" % (mp,))
            c.set_material(i, mat)
        if label:
            a.set_actor_label(label)
        return a

    def text(self, txt, loc, rot=(0, 0, 0), size=40.0):
        a = self.spawn(unreal.TextRenderActor, loc, rot)
        c = a.text_render
        c.set_text(unreal.Text(txt)) if hasattr(unreal, "Text") else None
        c.set_editor_property("world_size", size)
        c.set_editor_property("horizontal_alignment", unreal.HorizontalTextAligment.EHTA_CENTER)
        return a


def station_road(ctx, which=None):
    """Road variants side by side (strips run along +X, 10.5 m wide, spaced 12 m on Y)."""
    names = [("MI_Road_AsphaltNew", "asphalt new"), ("MI_Road_AsphaltWorn", "asphalt worn"), ("MI_Road_Concrete", "concrete"),
             ("MI_Road_Dirt", "dirt"), ("MI_Road_Gravel", "gravel")]
    ox, oy = 0.0, 0.0
    sel = [n for n in names if (not which or n[0] in which or n[1] in which)]
    for i, (mi, label) in enumerate(sel):
        path = MAT_ROOT + "/Instances/" + mi
        if not exists(path):
            path = MAT_ROOT + "/M_Roam_Road"
        ctx.mesh(TEST_DIR + "/SM_Test_Road", (ox, oy + i * 1200.0, 2.0), path, label=label)
    cy = oy + (len(sel) - 1) * 600.0
    return [
        {"name": "road_dry_far", "cam": (-1500, cy, 650), "look": (1400, cy, 0), "fov": 55},
        {"name": "road_dry_close", "cam": (-120, cy - 250, 170), "look": (900, cy - 250, 0), "fov": 60},
        {"name": "road_wet_rain", "cam": (-120, cy - 250, 170), "look": (900, cy - 250, 0), "fov": 60,
         "mpc": {"Wetness": 1.0, "PuddleAmount": 0.7, "RainIntensity": 0.8}},
        {"name": "road_snow", "cam": (-1500, cy, 650), "look": (1400, cy, 0), "fov": 55, "mpc": {"SnowAmount": 0.8}},
        {"name": "road_dust", "cam": (-1500, cy, 650), "look": (1400, cy, 0), "fov": 55, "mpc": {"DustAmount": 0.9}},
    ]


STATIONS = {"road": station_road}
_STATIONS_LOADED = []


def register(name, fn):
    STATIONS[name] = fn


# ------------------------------------------------------------------------------------------------------------------------------
# map + capture
# ------------------------------------------------------------------------------------------------------------------------------
def _reset_mpc(world, mpc):
    defaults = {"Wetness": 0.0, "PuddleAmount": 0.0, "RainIntensity": 0.0, "SnowAmount": 0.0, "DustAmount": 0.0, "TimeOfDay": 12.0,
                "NightFactor": -1.0, "WindStrength": 0.35, "WindSpeed": 5.0, "FoliageSeason": 0.0}
    for k, v in defaults.items():
        unreal.MaterialLibrary.set_scalar_parameter_value(world, mpc, k, v)
    unreal.MaterialLibrary.set_vector_parameter_value(world, mpc, "WindDirection", unreal.LinearColor(1, 0, 0, 0))
    unreal.MaterialLibrary.set_vector_parameter_value(world, mpc, "SeasonTint", unreal.LinearColor(1, 1, 1, 1))


def _prepare_world():
    """Current editor world, emptied of the actors of previous sheet runs; a blank map is only created when the editor world is not a sheet world
    (repeated new_blank_map calls corrupted Python references and crashed the editor: EXCEPTION_ACCESS_VIOLATION in python311.dll)."""
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    world = ues.get_editor_world()
    mine = []
    if world is not None:
        for a in eas.get_all_level_actors():
            if any(str(t) == "matsheet" for t in a.tags):
                mine.append(a)
    if world is not None and mine:
        for a in mine:
            eas.destroy_actor(a)
        log("test sheet: reusing the sheet world (%d old actors removed)" % len(mine))
        return world
    unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
    return ues.get_editor_world()


def run(opts=""):
    """opts: comma separated station names (default: all registered) + optional flags: save, remesh."""
    if _STATE.get("active") and time.time() - _STATE.get("last", 0.0) < 120.0:
        _STATE["pending"].append(opts)
        log("test sheet busy: queued run '%s' (%d pending)" % (opts, len(_STATE["pending"])))
        return
    toks = [t for t in (opts or "").split(",") if t]
    save_map = "save" in toks
    remesh = "remesh" in toks
    toks = [t for t in toks if t not in ("save", "remesh")]
    ensure_meshes(force=remesh)
    # additional stations from other modules register themselves into STATIONS when imported (materials_testsheet_*.py)
    stations = toks or list(STATIONS.keys())
    os.makedirs(SHOT_DIR, exist_ok=True)

    world = _prepare_world()
    ctx = Ctx(world)
    ea_ = ea
    sun = ctx.spawn(unreal.DirectionalLight, (0, 0, 1000), (0, -35, 40))
    sc = sun.get_component_by_class(unreal.DirectionalLightComponent)
    sc.set_editor_property("intensity", float(globals().get("SUN_LUX", 8.0)))  # a scene capture has exposure 1.0: sun in "display units" (see apply_shot)
    sc.set_editor_property("atmosphere_sun_light", True)
    sc.set_mobility(unreal.ComponentMobility.MOVABLE)
    ctx.spawn(unreal.SkyAtmosphere)
    sky = ctx.spawn(unreal.SkyLight, (0, 0, 600))
    skc = sky.get_component_by_class(unreal.SkyLightComponent)
    skc.set_mobility(unreal.ComponentMobility.MOVABLE)
    skc.set_editor_property("real_time_capture", True)
    # fill light: a scene capture gets no sky-light / Lumen indirect light (shadowed sides rendered pitch black), so a weak shadowless blue-ish
    # directional light from the opposite side stands in for the sky dome (rotation + intensity follow the sun in apply_shot)
    fill = ctx.spawn(unreal.DirectionalLight, (0, 0, 1100), (0, -20, 220))
    fc = fill.get_component_by_class(unreal.DirectionalLightComponent)
    fc.set_mobility(unreal.ComponentMobility.MOVABLE)
    fc.set_editor_property("cast_shadows", False)
    fc.set_editor_property("atmosphere_sun_light", False)
    fc.set_editor_property("light_color", unreal.Color(190, 210, 255, 255))
    fc.set_editor_property("intensity", 2.0)
    ground = ctx.spawn(unreal.StaticMeshActor, (0, 0, -5))
    ground.static_mesh_component.set_static_mesh(ea_.load_asset("/Engine/BasicShapes/Plane.Plane"))
    ground.set_actor_scale3d(unreal.Vector(400, 400, 1))
    ground.static_mesh_component.set_material(0, ea_.load_asset("/Engine/EngineMaterials/WorldGridMaterial"))
    ground.set_actor_label("Ground")

    shots = []
    sx = 0.0
    for st in stations:
        fn = STATIONS.get(st)
        if fn is None:
            L.warn("unknown station %s" % st)
            continue
        base = len(ctx.actors)
        sh = fn(ctx)
        for s in sh:
            s["name"] = s["name"]
        shots.extend(sh)

    cap = ctx.spawn(unreal.SceneCapture2D, (0, 0, 300), (0, 0, 0))
    comp = cap.capture_component2d
    W, H = 1280, 720
    rt = unreal.RenderingLibrary.create_render_target2d(world, W, H, unreal.TextureRenderTargetFormat.RTF_RGBA8)
    comp.set_editor_property("texture_target", rt)
    comp.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
    comp.set_editor_property("capture_every_frame", False)
    comp.set_editor_property("capture_on_movement", False)
    # exposure (fixed EV100, see apply_shot) only works in a scene capture when the EyeAdaptation show flag is on
    sfs = unreal.EngineShowFlagsSetting()
    sfs.set_editor_property("show_flag_name", "EyeAdaptation")
    sfs.set_editor_property("enabled", True)
    comp.set_editor_property("show_flag_settings", [sfs])
    # eye adaptation needs a persistent view state (history buffer); without it a capture has exposure 1.0
    try:
        comp.set_editor_property("always_persist_rendering_state", True)
    except Exception as ex:  # noqa: BLE001
        unreal.log_warning("MAT_BUILD always_persist_rendering_state not settable: %s" % ex)
    mpc = ea_.load_asset(MPC_PATH)
    EV = float(globals().get("SHEET_EV", 15.0))

    if save_map:
        unreal.EditorLoadingAndSavingUtils.save_map(world, MAP_PATH)
        log("saved map %s" % MAP_PATH)

    st = {"i": -1, "wait": 90, "phase": "start"}

    def apply_shot(s):
        _reset_mpc(world, mpc)
        for k, v in s.get("mpc", {}).items():
            if isinstance(v, (tuple, list)):
                unreal.MaterialLibrary.set_vector_parameter_value(world, mpc, k, unreal.LinearColor(*v))
            else:
                unreal.MaterialLibrary.set_scalar_parameter_value(world, mpc, k, float(v))
        cam = unreal.Vector(*s["cam"])
        look = unreal.Vector(*s["look"])
        rot = unreal.MathLibrary.find_look_at_rotation(cam, look)
        cap.set_actor_location_and_rotation(cam, rot, False, False)
        comp.set_editor_property("fov_angle", float(s.get("fov", 60)))
        sp = s.get("sun", (-35.0, 40.0))
        sun.set_actor_rotation(unreal.Rotator(0.0, sp[0], sp[1]), False)
        fill.set_actor_rotation(unreal.Rotator(0.0, -22.0, sp[1] + 180.0), False)
        pp = comp.get_editor_property("post_process_settings")
        # Exposure: a scene capture renders with exposure 1.0 (eye adaptation was ignored in every variant tried: manual bias, basic min/max
        # EV100, EyeAdaptation show flag, persistent view state), so the sheet scales the LIGHT instead: sun illuminance 8 lux (sky atmosphere and
        # sky light follow the sun) puts a sunlit mid-grey around 0.2.  Per shot: "sun_lux": value (night shots: 0.05 + emissive stays visible).
        lux = float(s.get("sun_lux", globals().get("SUN_LUX", 8.0)))
        sc.set_editor_property("intensity", lux)
        fc.set_editor_property("intensity", float(s.get("fill_lux", 0.28 * lux)))
        if "ev" in s:  # optional exposure override (EV100 min/max, only effective when eye adaptation works for the capture)
            ev = float(s["ev"])
            pp.set_editor_property("override_auto_exposure_method", True)
            pp.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_BASIC)
            pp.set_editor_property("override_auto_exposure_min_brightness", True)
            pp.set_editor_property("override_auto_exposure_max_brightness", True)
            pp.set_editor_property("auto_exposure_min_brightness", ev)
            pp.set_editor_property("auto_exposure_max_brightness", ev + 0.01)
        comp.set_editor_property("post_process_settings", pp)
        comp.set_editor_property("post_process_blend_weight", 1.0)

    def tick(dt):
        _STATE["last"] = time.time()
        try:
            if st["wait"] > 0:
                st["wait"] -= 1
                return
            if st["phase"] == "start" or st["phase"] == "next":
                st["i"] += 1
                if st["i"] >= len(shots):
                    unreal.unregister_slate_post_tick_callback(_STATE["handle"])
                    unreal.log("MAT_SHEET_DONE shots=%d dir=%s" % (len(shots), SHOT_DIR))
                    _STATE["active"] = False
                    if _STATE["pending"]:
                        nxt = _STATE["pending"].pop(0)
                        log("test sheet: starting queued run '%s'" % nxt)
                        run(nxt)
                    else:
                        _hold(False)
                    return
                apply_shot(shots[st["i"]])
                st["phase"] = "shoot"
                st["wait"] = int(shots[st["i"]].get("wait", 40))
                return
            if st["phase"] == "shoot":
                s = shots[st["i"]]
                comp.capture_scene()
                unreal.RenderingLibrary.export_render_target(world, rt, SHOT_DIR, s["name"] + ".png")
                unreal.log("MAT_SHEET_SHOT %s" % s["name"])
                st["phase"] = "next"
                st["wait"] = 2
        except Exception:  # noqa: BLE001
            unreal.log_error("MAT_ERR sheet tick\n" + traceback.format_exc())
            _STATE["active"] = False
            _hold(False)
            try:
                unreal.unregister_slate_post_tick_callback(_STATE["handle"])
            except Exception:  # noqa: BLE001
                pass

    if _STATE["handle"] is not None:
        try:
            unreal.unregister_slate_post_tick_callback(_STATE["handle"])
        except Exception:  # noqa: BLE001
            pass
    _STATE["handle"] = unreal.register_slate_post_tick_callback(tick)
    _STATE["active"] = True
    _STATE["last"] = time.time()
    _hold(True)
    log("test sheet armed: stations=%s shots=%d" % (stations, len(shots)))
