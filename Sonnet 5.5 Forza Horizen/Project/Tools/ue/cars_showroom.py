"""Showroom verification: builds every car from its DA_Car_<id> data asset (meshes + geometry anchors) in a lit blank map and captures
screenshots (3/4 front, side, front, rear 3/4, wheel close-up, cockpit, interior with body hidden) with a SceneCapture2D.

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/cars_showroom.py -LogName cars_showroom -TimeoutSec 3000
Options (ROAM_ARGS env var or JOB_ARGS tokens): only=car01,car05   views=front34,side,...   night=1 (lights on, dark sky)   finish=1
Output: Saved/CarsShowroom/<id>__<view>.png  (view them with the Read tool).  Log marker: CARS_SHOW.
The scene is the real asset chain: FBX parts -> static meshes -> MI_* instances -> DA_Car_* geometry (wheel centres, steering wheel).
"""
import math
import os
import time
import traceback

import unreal

JOB_MODE = "JOB_ARGS" in globals() and not globals().get("CARS_STANDALONE", False) and os.environ.get("ROAM_STANDALONE", "") != "1"
_ARGS = str(globals().get("JOB_ARGS", "")) or os.environ.get("ROAM_ARGS", "")
OPTS = dict(tok.split("=", 1) for tok in _ARGS.split() if "=" in tok)
ONLY = [s for s in OPTS.get("only", "").split(",") if s]
TRAFFIC = OPTS.get("traffic", "") == "1"      # show the civilian vehicles of DA_TrafficVehicles instead of the player cars
VIEWS = [s for s in OPTS.get("views", "front34,side,rear34,wheel" if TRAFFIC else "front34,side,front,rear34,wheel,cockpit,interior").split(",") if s]
NIGHT = OPTS.get("night", "") == "1"
RESUME = OPTS.get("resume", "") == "1"                       # skip views whose PNG already exists
WARM_SHOTS = int(OPTS.get("warm", "10"))                      # captures per car that only let Nanite/textures stream in
WAIT_SHADERS = OPTS.get("shaders", "0" if NIGHT else "1") == "1"   # probe until the paint renders coloured (not at night: the picture is dark)
FINISH = OPTS.get("finish", "")   # "1" = also render the finish variants (matte / metallic / stripes) for each car
EXPOSURE = float(OPTS.get("ev", "0.0"))
EV_SWEEP = [float(x) for x in OPTS.get("evsweep", "").split(",") if x]   # (exposure bias has no effect in scene captures: use sunsweep)
SUN_SWEEP = [float(x) for x in OPTS.get("sunsweep", "").split(",") if x]  # calibration: one front34 shot of the first car per sun illuminance
# Scene captures ignore the eye-adaptation exposure: the lights themselves must be in display range (illuminance ~ 3.14 lux = albedo-1 surface at luminance 1)
SUN = float(OPTS.get("sun", "30.0" if not NIGHT else "0.3"))
SKY = float(OPTS.get("sky", "3.0" if not NIGHT else "0.1"))
RES = (1280, 720)

ROOT = unreal.Paths.project_dir().replace("\\", "/")
OUT = ROOT + "Saved/CarsShowroom"
EAL = unreal.EditorAssetLibrary
os.makedirs(OUT, exist_ok=True)


def log(msg):
    unreal.log("CARS_SHOW " + str(msg))


log("pid=%d standalone=%s" % (os.getpid(), not JOB_MODE))


def vec(v):
    return unreal.Vector(v.x, v.y, v.z)


def look_at(frm, to):
    return unreal.MathLibrary.find_look_at_rotation(frm, to)


# ------------------------------------------------------------------------------------------------------------------
# Shared job-server protocol (Saved/MatJobs/README.txt, materials_server.py): an asynchronous multi-frame job writes Saved/MatJobs/hold_<name>
# and touches it at least every 20 minutes; while any hold exists the server neither quits nor starts queued jobs (the scene is ours).
# Standalone (ue_cmd.ps1) runs need set_keep_python_script_alive, otherwise the editor exits as soon as the script returns.
# ------------------------------------------------------------------------------------------------------------------
MATJOBS = ROOT + "Saved/MatJobs"
HOLD = MATJOBS + "/hold_cars"


def hold_start():
    if JOB_MODE and os.path.isdir(MATJOBS):
        with open(HOLD, "w") as fh:
            fh.write(str(time.time()))
    elif not JOB_MODE:
        unreal.EditorPythonScripting.set_keep_python_script_alive(True)


def keepalive_beat():
    if JOB_MODE:
        try:
            os.utime(HOLD, None)
        except OSError:
            with open(HOLD, "w") as fh:
                fh.write(str(time.time()))


def hold_stop():
    if JOB_MODE:
        try:
            os.remove(HOLD)
        except OSError:
            pass
    else:
        unreal.EditorPythonScripting.set_keep_python_script_alive(False)


def png_colorfulness(path):
    """Mean (max(R,G,B) - min(R,G,B)) of an 8-bit RGB/RGBA PNG (pure python): grey default materials give ~0-6, a painted car > 15."""
    import struct
    import zlib
    with open(path, "rb") as fh:
        data = fh.read()
    pos, idat, width, height, ctype = 8, b"", 0, 0, 6
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or interlace != 0 or ctype not in (2, 6):
                return -1.0
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * bpp
    prev = bytearray(stride)
    total, count = 0, 0
    for y in range(height):
        base = y * (stride + 1)
        ft = raw[base]
        row = bytearray(raw[base + 1:base + 1 + stride])
        if ft == 1:
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = row[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 255
        prev = row
        if y % 2 == 0:
            for x in range(0, width, 2):
                o = x * bpp
                r, g, b = row[o], row[o + 1], row[o + 2]
                total += max(r, g, b) - min(r, g, b)
                count += 1
    return total / max(count, 1)


class TrafficAdapter(object):
    """Makes an FRoamTrafficVehicleDef look enough like a car definition for the showroom."""

    def __init__(self, d):
        self.d = d
        self.spec = d.get_editor_property("spec")

    def get_editor_property(self, name):
        if name == "car_id":
            return self.d.get_editor_property("type_id")
        raise KeyError(name)

    def dims(self):
        s = self.spec
        return s.get_editor_property("length_cm"), s.get_editor_property("width_cm"), s.get_editor_property("height_cm")


class Show(object):
    def __init__(self):
        self.eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
        self.car_actors = []
        self.queue = []
        self.wait_until = 0.0
        self.ticks = 0
        self.last_sig = None
        self.warm_tries = 0
        self.cur_da = None
        self.new_scene()
        self.cars = []
        if TRAFFIC:
            cat = EAL.load_asset("/Game/Forza/Data/DA_TrafficVehicles")
            for d in cat.get_editor_property("vehicles"):
                a = TrafficAdapter(d)
                if ONLY and not any(o in str(a.get_editor_property("car_id")) for o in ONLY):
                    continue
                self.cars.append(a)
        for i, path in enumerate([] if TRAFFIC else sorted(EAL.list_assets("/Game/Forza/Data", recursive=False, include_folder=False))):
            if "/DA_Car_" not in path:
                continue
            da = EAL.load_asset(path.split(".")[0])
            vid = str(da.get_editor_property("car_id"))
            if ONLY and not any(o in vid for o in ONLY):
                continue
            self.cars.append(da)
        log("cars: %s" % [str(c.get_editor_property("car_id")) for c in self.cars])
        self.plan()

    # -------------------------------------------------------------------------------------------------------------
    def spawn(self, cls, loc=(0, 0, 0), rot=(0, 0, 0)):
        return self.eas.spawn_actor_from_class(cls, unreal.Vector(*loc), unreal.Rotator(rot[0], rot[1], rot[2]))

    def new_scene(self):
        self.world = unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
        self.rt = unreal.RenderingLibrary.create_render_target2d(self.world, RES[0], RES[1], unreal.TextureRenderTargetFormat.RTF_RGBA8)
        self.car_actors = []
        self.build_scene()

    def scene_alive(self):
        """Another job of the shared editor may have replaced the map under us."""
        try:
            return bool(unreal.SystemLibrary.is_valid(self.cap)) and self.cap.get_world() == unreal.EditorLevelLibrary.get_editor_world()
        except Exception:  # noqa: BLE001
            return False

    def build_scene(self):
        sun = self.spawn(unreal.DirectionalLight, (0, 0, 800), (0, -38, 40))
        sc = sun.get_component_by_class(unreal.DirectionalLightComponent)
        sc.set_editor_property("intensity", SUN)
        self.sun_comp = sc
        sc.set_editor_property("atmosphere_sun_light", False)
        sc.set_mobility(unreal.ComponentMobility.MOVABLE)
        fill = self.spawn(unreal.DirectionalLight, (0, 0, 900), (0, -30, 215))     # opposite side, no shadows: keeps the shaded flanks readable
        fc = fill.get_component_by_class(unreal.DirectionalLightComponent)
        fc.set_editor_property("intensity", SUN * 0.45)
        fc.set_editor_property("cast_shadows", False)
        fc.set_mobility(unreal.ComponentMobility.MOVABLE)
        # environment: engine daylight HDR cubemap (the real-time sky capture needs many frames; sky luminance is not linear in the sun intensity)
        sky = self.spawn(unreal.SkyLight, (0, 0, 400))
        skc = sky.get_component_by_class(unreal.SkyLightComponent)
        skc.set_mobility(unreal.ComponentMobility.MOVABLE)
        skc.set_editor_property("source_type", unreal.SkyLightSourceType.SLS_SPECIFIED_CUBEMAP)
        skc.set_editor_property("cubemap", EAL.load_asset("/Engine/MapTemplates/Sky/DaylightAmbientCubemap"))
        skc.set_editor_property("intensity", SKY)
        skc.set_editor_property("real_time_capture", False)
        try:
            skc.recapture_sky()
        except Exception:  # noqa: BLE001
            pass
        floor = self.spawn(unreal.StaticMeshActor, (0, 0, 0))
        floor.static_mesh_component.set_static_mesh(EAL.load_asset("/Engine/BasicShapes/Plane.Plane"))
        floor.set_actor_scale3d(unreal.Vector(300, 300, 1))
        fm = floor.static_mesh_component.create_dynamic_material_instance(0, EAL.load_asset("/Engine/BasicShapes/BasicShapeMaterial"))
        fm.set_vector_parameter_value("Color", unreal.LinearColor(0.16, 0.16, 0.17, 1.0))
        cap = self.spawn(unreal.SceneCapture2D, (-600, 0, 160))
        comp = cap.capture_component2d
        comp.set_editor_property("texture_target", self.rt)
        comp.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
        comp.set_editor_property("capture_every_frame", False)
        comp.set_editor_property("capture_on_movement", False)
        pp = comp.get_editor_property("post_process_settings")
        pp.set_editor_property("override_auto_exposure_method", True)
        pp.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_MANUAL)
        pp.set_editor_property("override_auto_exposure_bias", True)
        pp.set_editor_property("auto_exposure_bias", EXPOSURE)
        comp.set_editor_property("post_process_settings", pp)
        comp.set_editor_property("post_process_blend_weight", 1.0)
        self.cap, self.comp = cap, comp

    # -------------------------------------------------------------------------------------------------------------
    def mesh_actor(self, mesh, loc, rot=(0, 0, 0), label=""):
        if mesh is None:
            return None
        a = self.spawn(unreal.StaticMeshActor, (loc.x, loc.y, loc.z), rot)
        a.static_mesh_component.set_static_mesh(mesh)
        a.static_mesh_component.set_mobility(unreal.ComponentMobility.MOVABLE)
        a.set_actor_label(label)
        self.car_actors.append(a)
        return a

    def build_traffic(self, da):
        d, spec = da.d, da.spec
        o = unreal.Vector(0, 0, 0)
        parts = {"Body": self.mesh_actor(spec.get_editor_property("body_mesh"), o, label="Body"),
                 "Glass": self.mesh_actor(d.get_editor_property("glass_mesh"), o, label="Glass"),
                 "Interior": self.mesh_actor(d.get_editor_property("interior_mesh"), o, label="Interior")}
        for i, w in enumerate(d.get_editor_property("wheels")):
            parts["W%d" % i] = self.mesh_actor(w.get_editor_property("mesh"), w.get_editor_property("center_cm"), label="Wheel%d" % i)
        paints = d.get_editor_property("paint_variants")
        self.apply_paint(parts["Body"], paints[0] if paints else None, 0)
        if NIGHT:
            self.set_lights(parts["Body"], 1.0)
        self.parts = parts
        return parts

    def build_car(self, da):
        if isinstance(da, TrafficAdapter):
            return self.build_traffic(da)
        g = da.get_editor_property("geometry")
        parts = {}
        o = unreal.Vector(0, 0, 0)
        parts["Body"] = self.mesh_actor(da.get_editor_property("body_mesh"), o, label="Body")
        parts["Glass"] = self.mesh_actor(da.get_editor_property("glass_mesh"), o, label="Glass")
        parts["Interior"] = self.mesh_actor(da.get_editor_property("interior_mesh"), o, label="Interior")
        parts["Steer"] = self.mesh_actor(da.get_editor_property("steering_wheel_mesh"), g.get_editor_property("steering_wheel_center_cm"), label="Steer")
        for key, prop, wprop in (("FL", "wheel_mesh_fl", "wheel_fl"), ("FR", "wheel_mesh_fr", "wheel_fr"), ("RL", "wheel_mesh_rl", "wheel_rl"), ("RR", "wheel_mesh_rr", "wheel_rr")):
            parts["W" + key] = self.mesh_actor(da.get_editor_property(prop), g.get_editor_property(wprop).get_editor_property("center_cm"), label="Wheel" + key)
        # paint: first suggested paint via dynamic instances of the body's paint slots
        paints = da.get_editor_property("suggested_paints")
        self.apply_paint(parts["Body"], paints[0] if paints else None, 0)
        if NIGHT:
            self.set_lights(parts["Body"], 1.0)
        self.parts = parts
        return parts

    def slot_mids(self, actor):
        comp = actor.static_mesh_component
        out = {}
        for i, name in enumerate(comp.get_material_slot_names()):
            mid = comp.create_dynamic_material_instance(i)
            out[str(name)] = mid
        return out

    def apply_paint(self, body, paint, variant):
        if body is None:
            return
        mids = self.slot_mids(body)
        self.mids = mids
        if paint is None:
            return
        p1 = mids.get("M_Paint")
        p2 = mids.get("M_Paint2")
        if p1:
            p1.set_vector_parameter_value("PrimaryColor", paint.get_editor_property("primary"))
            p1.set_vector_parameter_value("StripeColor", paint.get_editor_property("secondary"))
            p1.set_scalar_parameter_value("StripeStyle", float(paint.get_editor_property("stripe_style")))
        if p2:
            p2.set_vector_parameter_value("PrimaryColor", paint.get_editor_property("secondary"))
        finish = str(paint.get_editor_property("finish")).split(".")[-1].upper()
        self.finish(finish if variant == 0 else ["GLOSS", "MATTE", "METALLIC"][variant % 3])

    def finish(self, finish):
        for slot in ("M_Paint", "M_Paint2"):
            m = self.mids.get(slot)
            if not m:
                continue
            if finish == "MATTE":
                vals = dict(Metallic=0.0, BaseRoughness=0.8, ClearCoat=0.0, FlakeIntensity=0.0, MatteFlatness=1.0)
            elif finish == "METALLIC":
                vals = dict(Metallic=0.85, BaseRoughness=0.33, ClearCoat=1.0, FlakeIntensity=0.65, MatteFlatness=0.0)
            else:
                vals = dict(Metallic=0.0, BaseRoughness=0.38, ClearCoat=1.0, FlakeIntensity=0.0, MatteFlatness=0.0)
            for k, v in vals.items():
                m.set_scalar_parameter_value(k, v)

    def set_lights(self, body, value):
        for slot in ("M_Headlight", "M_Taillight", "M_Reverse", "M_Indicator"):
            m = self.mids.get(slot)
            if m:
                m.set_scalar_parameter_value("Intensity", value if slot != "M_Reverse" and slot != "M_Indicator" else 0.0)

    def clear_car(self):
        for a in self.car_actors:
            if a:
                self.eas.destroy_actor(a)
        self.car_actors = []

    # -------------------------------------------------------------------------------------------------------------
    def camera_for(self, da, view):
        if isinstance(da, TrafficAdapter):
            length, width, height = da.dims()
            g = None
        else:
            g = da.get_editor_property("geometry")
            length, width, height = g.get_editor_property("length_cm"), g.get_editor_property("width_cm"), g.get_editor_property("height_cm")
        target = unreal.Vector(0, 0, height * 0.42)
        fov = 38.0
        dist = max(length, width * 1.8) * 1.75

        def orbit(az, el, d, tgt):
            a, e = math.radians(az), math.radians(el)
            return unreal.Vector(tgt.x + d * math.cos(e) * math.cos(a), tgt.y - d * math.cos(e) * math.sin(a), tgt.z + d * math.sin(e))

        if view == "front34":
            return orbit(36, 12, dist, target), target, fov
        if view == "rear34":
            return orbit(146, 12, dist, target), target, fov
        if view == "side":
            return orbit(90, 2, dist * 1.12, target), target, 34.0
        if view == "front":
            return orbit(0, 4, dist * 1.1, target), target, fov
        if view == "rear":
            return orbit(180, 4, dist * 1.1, target), target, fov
        if view == "top":
            return orbit(90, 80, dist * 1.2, target), target, fov
        if view == "wheel":
            wc = da.d.get_editor_property("wheels")[0].get_editor_property("center_cm") if g is None else g.get_editor_property("wheel_fl").get_editor_property("center_cm")
            tgt = unreal.Vector(wc.x, wc.y, wc.z)
            return orbit(90, 4, 120.0, tgt), tgt, 40.0
        if view == "cockpit":
            c = g.get_editor_property("camera_cockpit_cm")
            pos = unreal.Vector(c.x, c.y, c.z)
            return pos, unreal.Vector(c.x + 300.0, c.y * 0.6, c.z - 18.0), 82.0
        if view == "interior":
            tgt = unreal.Vector(g.get_editor_property("camera_cockpit_cm").x - 10.0, 0, height * 0.42)
            return orbit(120, 38, max(length * 0.55, 220.0), tgt), tgt, 55.0
        return orbit(36, 12, dist, target), target, fov

    def set_sun(self, lux):
        self.sun_comp.set_editor_property("intensity", lux)

    def set_ev(self, ev):
        pp = self.comp.get_editor_property("post_process_settings")
        pp.set_editor_property("auto_exposure_bias", ev)
        self.comp.set_editor_property("post_process_settings", pp)

    def plan(self):
        if SUN_SWEEP and self.cars:
            self.queue.append(("build", self.cars[0]))
            for lux in SUN_SWEEP:
                self.queue.append(("sun", lux))
                self.queue.append(("shot", self.cars[0], "front34", "sun%g" % lux))
            self.queue.append(("clear",))
            return
        if EV_SWEEP and self.cars:
            self.queue.append(("build", self.cars[0]))
            for ev in EV_SWEEP:
                self.queue.append(("ev", ev))
                self.queue.append(("shot", self.cars[0], "front34", "ev%g" % ev))
            self.queue.append(("clear",))
            return
        for da in self.cars:
            vid = str(da.get_editor_property("car_id"))
            views = [v for v in VIEWS if not (RESUME and os.path.exists("%s/%s__%s%s.png" % (OUT, vid, v, "_night" if NIGHT else "")))]
            if not views and not FINISH:
                continue
            self.queue.append(("build", da))
            if da is self.cars[0] and WAIT_SHADERS:
                self.queue.append(("shaders", da))
            for _ in range(WARM_SHOTS):
                self.queue.append(("warm", da))     # captures that only make the renderer request the Nanite pages / textures of the new car
            for v in views:
                self.queue.append(("shot", da, v))
            if FINISH:
                for variant, label in ((1, "matte"), (2, "metallic")):
                    self.queue.append(("variant", da, variant))
                    self.queue.append(("shot", da, "front34", label))
            self.queue.append(("clear",))

    def export(self, name):
        unreal.RenderingLibrary.export_render_target(self.world, self.rt, OUT, name + ".png")
        path = OUT + "/" + name + ".png"
        try:
            with open(path, "rb") as fh:
                data = fh.read()
            return hash(data), len(data)
        except OSError:
            return None, 0

    def tick(self, dt):
        self.ticks += 1
        now = time.time()
        if now - getattr(self, "last_beat", 0.0) > 1.0:
            self.last_beat = now
            keepalive_beat()
        if now < self.wait_until:
            return
        if self.ticks % 200 == 0:
            log("alive ticks=%d queue=%d" % (self.ticks, len(self.queue)))
        if not self.queue:
            log("ALL DONE")
            hold_stop()
            unreal.unregister_slate_post_tick_callback(self.handle)
            if not JOB_MODE:
                unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
            return
        if self.cur_da is not None and not self.scene_alive():
            log("scene was replaced by another job: rebuilding it")
            self.new_scene()
            self.queue.insert(0, ("build", self.cur_da))
            self.last_sig = None
            self.warm_tries = 0
            self.wait_until = now + 1.0
            return
        task = self.queue.pop(0)
        try:
            kind = task[0]
            if kind == "build":
                self.clear_car()
                self.cur_da = task[1]
                self.build_car(task[1])
                self.last_sig = None
                self.warm_tries = 0          # Nanite data / textures of a freshly spawned car stream in asynchronously: warm up per car
                self.hidden = []
                self.wait_until = now + 2.0
                log("built %s" % task[1].get_editor_property("car_id"))
            elif kind == "clear":
                self.clear_car()
                self.cur_da = None
            elif kind == "sun":
                self.set_sun(task[1])
                self.wait_until = now + 3.0
                self.last_sig = None
                self.warm_tries = 99
            elif kind == "warm":
                pos, tgt, fov = self.camera_for(task[1], "front34")
                self.cap.set_actor_location_and_rotation(pos, look_at(pos, tgt), False, False)
                self.comp.set_editor_property("fov_angle", fov)
                self.comp.capture_scene()
                self.wait_until = now + 1.5
            elif kind == "shaders":
                # after a material rebuild the shaders compile asynchronously (minutes on a loaded machine) and the car renders with the grey
                # default material meanwhile: probe a small capture every 15 s until the picture is coloured (paint) or 120 tries (30 min)
                pos, tgt, fov = self.camera_for(task[1], "front34")
                self.cap.set_actor_location_and_rotation(pos, look_at(pos, tgt), False, False)
                self.comp.set_editor_property("fov_angle", fov)
                self.comp.capture_scene()
                self.export("_shader_probe")
                try:
                    cf = png_colorfulness(OUT + "/_shader_probe.png")
                except Exception as exc:  # noqa: BLE001
                    cf = -1.0
                    log("probe decode failed: %s" % exc)
                self.shader_tries = getattr(self, "shader_tries", 0) + 1
                log("shader probe %d colourfulness=%.1f" % (self.shader_tries, cf))
                if (cf < 12.0 or cf > 250.0) and self.shader_tries < 120:
                    self.queue.insert(0, task)
                    self.wait_until = now + 15.0
                else:
                    log("shaders ready after %d probes (colourfulness %.1f)" % (self.shader_tries, cf))
                    self.wait_until = now + 2.0
            elif kind == "ev":
                self.set_ev(task[1])
                self.wait_until = now + 2.5
                self.last_sig = None
                self.warm_tries = 99
            elif kind == "variant":
                self.finish(["GLOSS", "MATTE", "METALLIC"][task[2] % 3])
                self.wait_until = now + 1.0
            elif kind == "shot":
                da, view = task[1], task[2]
                label = task[3] if len(task) > 3 else view
                for a in self.hidden:
                    a.set_actor_hidden_in_game(False)
                self.hidden = []
                if view == "interior":
                    for key in ("Body", "Glass"):
                        a = self.parts.get(key)
                        if a:
                            a.set_actor_hidden_in_game(True)
                            self.hidden.append(a)
                pos, tgt, fov = self.camera_for(da, view)
                self.cap.set_actor_location_and_rotation(pos, look_at(pos, tgt), False, False)
                self.comp.set_editor_property("fov_angle", fov)
                vid = str(da.get_editor_property("car_id"))
                name = "%s__%s%s" % (vid, label, "_night" if NIGHT else "")
                self.comp.capture_scene()
                sig = self.export(name)
                log("shot %s bytes=%d" % (name, sig[1]))
                # warm-up: the first captures render while shaders compile / Lumen converges: repeat the very first view until two
                # consecutive captures are identical (or 14 tries)
                if self.warm_tries < 0 and (sig != self.last_sig or sig[1] == 0):
                    self.warm_tries += 1
                    self.last_sig = sig
                    self.queue.insert(0, ("shot",) + task[1:])
                    self.wait_until = now + 3.0
                else:
                    self.warm_tries = 99
                    self.wait_until = now + 1.2
        except Exception:  # noqa: BLE001
            log("EXC " + traceback.format_exc())
            self.wait_until = now + 2.0


try:
    show = Show()
    hold_start()
    show.handle = unreal.register_slate_post_tick_callback(show.tick)
    log("armed: %d tasks" % len(show.queue))
except Exception:  # noqa: BLE001
    traceback.print_exc()
    log("FAILED to start")
    if not JOB_MODE:
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
