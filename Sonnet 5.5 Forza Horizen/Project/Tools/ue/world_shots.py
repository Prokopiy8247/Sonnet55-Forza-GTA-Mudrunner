"""world_shots - EXPERIMENTAL: screenshots of /Game/Forza/Maps/L_Main from the shared editor job server (SceneCapture2D; no game run).
!! KNOWN PROBLEMS (2026-10-17): the captures of L_Main come out PURE WHITE even with a fixed EV100 (cause not found; the small test maps of the
!! materials/cars agents render fine), and load_level() inside the shared job server crashed it once while another agent's asynchronous job
!! was running. Use Tools/ue/world_tour.ps1 (real game run) to look at the world.  Kept as a starting point for a standalone use.
Owner: F1.   Docs/Tech/WORLD_BUILD.md

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_shots.py -TimeoutSec 900 -Args0 "all"
    -Args0: shot names (space/comma separated) or "all";  key=value: ev=15 (fixed EV100: higher = darker)  w=1920 h=1080  map=/Game/Forza/Maps/L_Main
Output: Saved/WorldShots/<name>.png (open with the Read tool).  Log markers: ROAM_SHOT / ROAM_SHOTS_DONE.
The job returns at once; the capture is asynchronous (several frames per shot: streaming, shaders, Lumen/Nanite). While it runs the job server is held
(Saved/MatJobs/hold_world, released at the end or after 20 min) so that another job cannot replace the map under the camera.
Camera rules: road shots sit behind/above a car at roads.json (road, s) looking along the road (UE yaw = heading, X north / Y east); ground shots
use the landscape height + an offset (RoamWorldBuilder.sample_landscape).
"""
import math
import os
import sys
import time
import traceback

import unreal

_ROOT = unreal.Paths.project_dir().replace("\\", "/")
_HERE = _ROOT + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import world_lib as W  # noqa: E402

OUT = _ROOT + "Saved/WorldShots"
HOLD = _ROOT + "Saved/MatJobs/hold_world"
JOB_MODE = "JOB_ARGS" in globals()


def _tokens():
    raw = globals().get("JOB_ARGS", "") or os.environ.get("ROAM_WORLD_SHOTS", "all")
    return [t for t in raw.replace(",", " ").split() if t]


def _opt(name, default):
    for t in _tokens():
        if t.startswith(name + "="):
            return t.split("=", 1)[1]
    return default


def log(msg):
    unreal.log("ROAM_SHOT " + str(msg))


# (name, kind, params) kinds:
#   road   (road id, s, back m, up m, look-ahead m, pitch deg)       drive/chase view on a road
#   ground (x m, y m, up m, look x, look y, look z offset)           free camera above the terrain, looking at a ground point (+ offset up)
#   world  (x m, y m, z m, look x, look y, look z)                   absolute positions
SHOTS = [
    ("drive_loop_start", "road", ("HWY_EAST", 220, 9, 3.2, 60, -3)),
    ("drive_plateau_highway", "road", ("HWY_EAST", 3300, 9, 3.2, 60, -3)),
    ("drive_pass_switchbacks", "road", ("LOOP_PASS", 2600, 9, 3.2, 40, -4)),
    ("drive_summit_road", "road", ("LOOP_PASS", 4700, 9, 3.2, 60, -3)),
    ("drive_coast_road", "road", ("LOOP_COAST", 300, 9, 3.2, 60, -3)),
    ("drive_valley_road", "road", ("LOOP_VALLEY", 1000, 9, 3.2, 60, -3)),
    ("drive_dirt_wash", "road", ("DIRT_WASH", 400, 8, 2.8, 40, -3)),
    ("aerial_crossroads", "world", (-300, -250, 330, 0, 0, 100)),
    ("aerial_bay_bridge", "world", (-700, 1100, 120, -350, 1300, 0)),
    ("aerial_tidewick_coast", "world", (-1500, 1150, 140, -1150, 1500, 5)),
    ("aerial_summit", "world", (1150, -1500, 700, 1380, -1180, 500)),
    ("aerial_greenvale", "world", (-1300, -1700, 220, -900, -900, 60)),
    ("map_overview_sw", "world", (-3600, -3000, 1700, 0, 0, 80)),
    ("map_overview_east_sea", "world", (-1800, 3200, 900, -300, 1200, 20)),
]


def _road_pose(road_id, s, back, up, ahead, pitch):
    data = W.roads_json()
    road = next(r for r in data["roads"] if r["id"] == road_id)
    samples = road["samples"]
    row = samples[min(len(samples) - 1, max(0, int(round(s / 2.0))))]
    x, y, z, heading = row[1], row[2], row[3], row[4]
    h = math.radians(heading)
    fx, fy = math.cos(h), math.sin(h)
    pos = unreal.Vector((x - fx * back) * 100.0, (y - fy * back) * 100.0, (z + up) * 100.0)
    look = unreal.Vector((x + fx * ahead) * 100.0, (y + fy * ahead) * 100.0, (z + up + ahead * math.tan(math.radians(pitch))) * 100.0)
    return pos, look


def _pose(world, kind, p):
    if kind == "road":
        return _road_pose(*p)
    if kind == "world":
        return unreal.Vector(p[0] * 100.0, p[1] * 100.0, p[2] * 100.0), unreal.Vector(p[3] * 100.0, p[4] * 100.0, p[5] * 100.0)
    raise ValueError(kind)


class Shooter(object):
    def __init__(self):
        self.ticks = 0
        self.wait_until = 0.0
        self.queue = []
        self.phase = "load"
        self.last_sig = None
        self.tries = 0
        self.handle = None
        self.cur = None
        self.world = None
        self.t_start = time.time()
        self.ev = float(_opt("ev", "15"))
        self.res = (int(_opt("w", "1920")), int(_opt("h", "1080")))
        want = [t for t in _tokens() if "=" not in t] or ["all"]
        self.names = [s[0] for s in SHOTS] if "all" in want else [n for n in want if n in [s[0] for s in SHOTS]]
        os.makedirs(OUT, exist_ok=True)

    def hold(self):
        try:
            with open(HOLD, "w") as fh:
                fh.write(str(time.time()))
        except OSError:
            pass

    def release(self):
        try:
            os.remove(HOLD)
        except OSError:
            pass

    def start(self):
        map_path = _opt("map", W.MAP_MAIN)
        world = W.get_world()
        if world.get_name() != map_path.rsplit("/", 1)[1]:
            log("loading %s" % map_path)
            ok = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(map_path)
            log("load_level ok=%s" % ok)
        self.world = W.get_world()
        log("world %s %s" % (self.world.get_name(), unreal.RoamWorldBuilder.describe_landscape(self.world)))
        self.rt = unreal.RenderingLibrary.create_render_target2d(self.world, self.res[0], self.res[1], unreal.TextureRenderTargetFormat.RTF_RGBA8)
        cap = W.actors.spawn_actor_from_class(unreal.SceneCapture2D, unreal.Vector(0, 0, 100000), unreal.Rotator(0, 0, 0))
        cap.set_actor_label("ZZ_ShotCamera")
        comp = cap.capture_component2d
        comp.set_editor_property("texture_target", self.rt)
        comp.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
        comp.set_editor_property("capture_every_frame", False)
        comp.set_editor_property("capture_on_movement", False)
        comp.set_editor_property("fov_angle", 70.0)
        sfs = unreal.EngineShowFlagsSetting()
        sfs.set_editor_property("show_flag_name", "EyeAdaptation")
        sfs.set_editor_property("enabled", True)
        comp.set_editor_property("show_flag_settings", [sfs])
        pp = comp.get_editor_property("post_process_settings")
        pp.set_editor_property("override_auto_exposure_method", True)
        pp.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_BASIC)
        pp.set_editor_property("override_auto_exposure_min_brightness", True)
        pp.set_editor_property("override_auto_exposure_max_brightness", True)
        pp.set_editor_property("auto_exposure_min_brightness", self.ev)
        pp.set_editor_property("auto_exposure_max_brightness", self.ev)
        pp.set_editor_property("override_auto_exposure_bias", True)
        pp.set_editor_property("auto_exposure_bias", 0.0)
        comp.set_editor_property("post_process_settings", pp)
        comp.set_editor_property("post_process_blend_weight", 1.0)
        self.cap, self.comp = cap, comp
        self.queue = [s for s in SHOTS if s[0] in self.names]
        self.wait_until = time.time() + 20.0       # streaming / shaders / Nanite
        self.phase = "shoot"
        log("armed %d shots, EV %.1f, %dx%d" % (len(self.queue), self.ev, self.res[0], self.res[1]))

    def export(self, name):
        unreal.RenderingLibrary.export_render_target(self.world, self.rt, OUT, name + ".png")
        path = "%s/%s.png" % (OUT, name)
        try:
            with open(path, "rb") as fh:
                data = fh.read()
            return hash(data), len(data)
        except OSError:
            return None, 0

    def finish(self, why):
        log("ROAM_SHOTS_DONE %s in %.0f s" % (why, time.time() - self.t_start))
        unreal.log("ROAM_SHOTS_DONE %s" % why)
        try:
            self.cap.destroy_actor()
        except Exception:  # noqa: BLE001
            pass
        self.release()
        unreal.unregister_slate_post_tick_callback(self.handle)
        if not JOB_MODE:
            unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")

    def tick(self, dt):
        self.ticks += 1
        now = time.time()
        try:
            if now - self.t_start > 1100:
                self.finish("timeout")
                return
            if self.ticks % 100 == 0:
                self.hold()
            if now < self.wait_until:
                return
            if self.phase == "load":
                self.start()
                return
            if self.cur is None:
                if not self.queue:
                    self.finish("ok")
                    return
                self.cur = self.queue.pop(0)
                name, kind, params = self.cur
                pos, look = _pose(self.world, kind, params)
                rot = unreal.MathLibrary.find_look_at_rotation(pos, look)
                self.cap.set_actor_location_and_rotation(pos, rot, False, False)
                self.last_sig = None
                self.tries = 0
                self.wait_until = now + 6.0          # let the streaming pick up the new view before the first capture
                return
            name = self.cur[0]
            self.comp.capture_scene()
            sig = self.export(name)
            self.tries += 1
            if (sig != self.last_sig or sig[1] == 0) and self.tries < 6:
                self.last_sig = sig
                self.wait_until = now + 4.0          # two identical consecutive captures = converged
                return
            log("shot %s bytes=%d tries=%d -> %s/%s.png" % (name, sig[1], self.tries, OUT, name))
            self.cur = None
            self.wait_until = now + 1.0
        except Exception:  # noqa: BLE001
            log("EXC " + traceback.format_exc())
            self.finish("exception")


try:
    shooter = Shooter()
    shooter.hold()
    shooter.handle = unreal.register_slate_post_tick_callback(shooter.tick)
    log("job armed (async)")
except Exception:  # noqa: BLE001
    traceback.print_exc()
    log("FAILED to start")
