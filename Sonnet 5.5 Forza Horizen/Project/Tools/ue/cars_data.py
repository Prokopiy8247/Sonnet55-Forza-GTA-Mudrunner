"""Creates the vehicle data assets in /Game/Forza/Data:  DA_Car_<id> (10, URoamCarDefinition), DA_CarCatalog (URoamCarCatalog, roster
order) and DA_TrafficVehicles (URoamTrafficCatalog, 6 civilian vehicle types).

Geometry comes from the Blender sidecar JSON (Exports/<Cars|Traffic>/<id>/<id>.json, metres, Blender axes -> UE cm:
x*100, -y*100, z*100), the handling numbers from Tools/ue/cars_spec.py (first-pass physics derived from Docs/CAR_ROSTER.md).
Idempotent: existing assets are loaded and every field is overwritten.

Run as a job on the shared editor server (or standalone through ue_cmd.ps1):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/cars_data.py -Filter "CARS_DATA|MATJOB|Error:"
Log markers: CARS_DATA (progress), CARS_PI (estimator output per car), CARS_DATA_RESULT.
"""
import importlib
import json
import os
import sys
import traceback

import unreal

JOB_MODE = "JOB_ARGS" in globals()
PROJECT = unreal.Paths.project_dir().replace("\\", "/")
EXPORTS = PROJECT + "Exports/"
DATA_DIR = "/Game/Forza/Data"
CARS_ROOT = "/Game/Forza/Cars"
TRAFFIC_ROOT = "/Game/Forza/Traffic"
EAL = unreal.EditorAssetLibrary
AT = unreal.AssetToolsHelpers.get_asset_tools()

_TOOLS = PROJECT + "Tools/ue"
if _TOOLS not in sys.path:
    sys.path.insert(0, _TOOLS)
import cars_spec as S  # noqa: E402

importlib.reload(S)  # the editor server keeps modules alive between jobs


def log(msg):
    unreal.log("CARS_DATA " + str(msg))


def warn(msg):
    unreal.log_warning("CARS_DATA " + str(msg))


def vec(v):
    return unreal.Vector(v[0], v[1], v[2])


def ue_pos(p):
    """Blender car space (m) -> UE car space (cm)."""
    return unreal.Vector(p[0] * 100.0, -p[1] * 100.0, p[2] * 100.0)


def enum_value(enum_cls, name):
    """RoamDiffType + 'LimitedSlip' -> unreal.RoamDiffType.LIMITED_SLIP"""
    out = ""
    for i, ch in enumerate(name):
        if ch.isupper() and i > 0 and not name[i - 1].isupper():
            out += "_"
        out += ch.upper()
    return getattr(enum_cls, out)


def lin(c):
    return unreal.LinearColor(c[0], c[1], c[2], c[3] if len(c) > 3 else 1.0)


def get_or_create(name, cls):
    path = "%s/%s" % (DATA_DIR, name)
    if not EAL.does_directory_exist(DATA_DIR):
        EAL.make_directory(DATA_DIR)
    if EAL.does_asset_exist(path):
        return EAL.load_asset(path)
    f = unreal.DataAssetFactory()
    f.set_editor_property("data_asset_class", cls)
    asset = AT.create_asset(name, DATA_DIR, cls, f)
    if asset is None:
        raise RuntimeError("could not create " + path)
    return asset


def load_mesh(folder, vid, part):
    path = "%s/%s/SM_%s_%s" % (folder, vid, vid, part)
    m = EAL.load_asset(path)
    if m is None:
        warn("missing mesh " + path)
    return m


def surface_map(bias):
    out = {}
    for sname, val in bias.items():
        out[getattr(unreal.RoamSurface, sname.upper())] = float(val)
    return out


# ------------------------------------------------------------------------------------------------------------------
# upgrade slots
# ------------------------------------------------------------------------------------------------------------------
def upgrade_slots(c):
    cat = unreal.RoamUpgradeCategory
    price = c["price"]
    tiers = [1.0, 2.2, 4.6]

    def slot(sid, category, frac, max_tier=3):
        s = unreal.RoamUpgradeSlot()
        s.set_editor_property("slot_id", sid)
        s.set_editor_property("category", category)
        s.set_editor_property("max_tier", max_tier)
        s.set_editor_property("tier_price_credits", [int(round(price * frac * t / 50.0) * 50) for t in tiers[:max_tier]])
        return s

    out = [
        slot("Engine.Intake", cat.ENGINE, 0.015), slot("Engine.Exhaust", cat.ENGINE, 0.02), slot("Engine.Tune", cat.ENGINE, 0.04),
        slot("Platform.Brakes", cat.PLATFORM_HANDLING, 0.025), slot("Platform.Springs", cat.PLATFORM_HANDLING, 0.03),
        slot("Platform.AntiRoll", cat.PLATFORM_HANDLING, 0.015), slot("Platform.Weight", cat.PLATFORM_HANDLING, 0.035),
        slot("Tires.Compound", cat.TIRES_RIMS, 0.02), slot("Tires.Width", cat.TIRES_RIMS, 0.015),
        slot("Drivetrain.Clutch", cat.DRIVETRAIN, 0.015), slot("Drivetrain.Transmission", cat.DRIVETRAIN, 0.03),
        slot("Drivetrain.Differential", cat.DRIVETRAIN, 0.025),
    ]
    if not c["turbo"]:
        out.append(slot("Conversion.Turbo", cat.CONVERSION, 0.08, 1))
    if c["drivetrain"] != "AWD" and c["id"] != "car10_roadster_classic":
        out.append(slot("Conversion.AWD", cat.CONVERSION, 0.10, 1))
    out.append(slot("Conversion.EngineSwap", cat.CONVERSION, 0.14, 1))
    if c["id"] != "car10_roadster_classic":
        out.append(slot("Aero.Front", cat.AERO_APPEARANCE, 0.02))
        out.append(slot("Aero.Rear", cat.AERO_APPEARANCE, 0.025))
    out.append(slot("Aero.Weight", cat.AERO_APPEARANCE, 0.02, 2))
    return out


# ------------------------------------------------------------------------------------------------------------------
# player cars
# ------------------------------------------------------------------------------------------------------------------
def build_car(c):
    vid = c["id"]
    js = S.load_json(EXPORTS, vid)
    d = S.derive(c, js)
    da = get_or_create("DA_Car_" + vid, unreal.RoamCarDefinition)

    # ---- identity ----
    da.set_editor_property("car_id", vid)
    da.set_editor_property("display_name", c["name"])
    da.set_editor_property("maker", c["maker"])
    da.set_editor_property("year", int(c["year"]))
    da.set_editor_property("description", c["desc"])
    da.set_editor_property("price_credits", int(c["price"]))
    da.set_editor_property("body_type", c["body"])
    da.set_editor_property("tags", c["tags"])

    # ---- meshes ----
    folder = CARS_ROOT
    da.set_editor_property("body_mesh", load_mesh(folder, vid, "Body"))
    da.set_editor_property("glass_mesh", load_mesh(folder, vid, "Glass"))
    da.set_editor_property("interior_mesh", load_mesh(folder, vid, "Interior"))
    da.set_editor_property("steering_wheel_mesh", load_mesh(folder, vid, "SteeringWheel"))
    for key, part in (("wheel_mesh_fl", "Wheel_FL"), ("wheel_mesh_fr", "Wheel_FR"), ("wheel_mesh_rl", "Wheel_RL"), ("wheel_mesh_rr", "Wheel_RR")):
        da.set_editor_property(key, load_mesh(folder, vid, part))

    # ---- geometry (JSON -> UE cm) ----
    geo = unreal.RoamCarGeometry()
    dims = js["dimensions"]
    geo.set_editor_property("length_cm", dims["length"] * 100.0)
    geo.set_editor_property("width_cm", dims["width"] * 100.0)
    geo.set_editor_property("height_cm", dims["height"] * 100.0)
    geo.set_editor_property("wheelbase_cm", js["wheelbase"] * 100.0)
    geo.set_editor_property("track_front_cm", js["track_front"] * 100.0)
    geo.set_editor_property("track_rear_cm", js["track_rear"] * 100.0)
    geo.set_editor_property("ride_height_cm", js.get("ride_height", 0.12) * 100.0)
    for key, wname in (("wheel_fl", "FL"), ("wheel_fr", "FR"), ("wheel_rl", "RL"), ("wheel_rr", "RR")):
        w = unreal.RoamWheelGeometry()
        w.set_editor_property("center_cm", ue_pos(js["wheels"][wname]["center"]))
        w.set_editor_property("radius_cm", js["wheels"][wname]["radius"] * 100.0)
        w.set_editor_property("width_cm", js["wheels"][wname]["width"] * 100.0)
        geo.set_editor_property(key, w)
    sw = js["steering_wheel"]
    geo.set_editor_property("steering_wheel_center_cm", ue_pos(sw["center"]))
    ax = sw["axis"]
    geo.set_editor_property("steering_wheel_axis", unreal.Vector(ax[0], -ax[1], ax[2]))   # points at the driver: +angle = clockwise seen by the driver
    cams = js["cameras"]
    geo.set_editor_property("camera_hood_cm", ue_pos(cams["hood"]))
    geo.set_editor_property("camera_cockpit_cm", ue_pos(cams["cockpit"]))
    geo.set_editor_property("camera_bumper_cm", ue_pos(cams["bumper"]))
    lights = js["lights"]
    geo.set_editor_property("head_light_l_cm", ue_pos(lights["head_l"]))
    geo.set_editor_property("head_light_r_cm", ue_pos(lights["head_r"]))
    geo.set_editor_property("tail_light_l_cm", ue_pos(lights["tail_l"]))
    geo.set_editor_property("tail_light_r_cm", ue_pos(lights["tail_r"]))
    geo.set_editor_property("reverse_light_cm", ue_pos(lights["reverse"]))
    geo.set_editor_property("exhaust_l_cm", ue_pos(js["exhaust_l"]))
    geo.set_editor_property("exhaust_r_cm", ue_pos(js["exhaust_r"]))
    da.set_editor_property("geometry", geo)

    # ---- mass ----
    da.set_editor_property("mass_kg", float(c["mass"]))
    da.set_editor_property("center_of_mass_cm", vec(d["com"]))
    da.set_editor_property("inertia_kg_m2", unreal.Vector(0, 0, 0))   # estimated by GetEstimatedInertia()
    da.set_editor_property("handling_factor", float(c["handling"]))

    # ---- engine ----
    eng = unreal.RoamEngineSpec()
    eng.set_editor_property("torque_curve", [unreal.RoamTorquePoint(rpm=r, torque_nm=t) for r, t in d["torque_curve"]])
    eng.set_editor_property("idle_rpm", float(c["idle"]))
    eng.set_editor_property("redline_rpm", float(c["redline"]))
    eng.set_editor_property("rev_limiter_rpm", float(c["limiter"]))
    eng.set_editor_property("inertia_kg_m2", float(c["engine_inertia"]))
    eng.set_editor_property("engine_brake_nm", float(c["engine_brake"]))
    eng.set_editor_property("throttle_response_sec", float(c["throttle"]))
    t = c["turbo"]
    eng.set_editor_property("turbo", t is not None)
    if t:
        eng.set_editor_property("max_boost_bar", t["bar"])
        eng.set_editor_property("turbo_full_boost_rpm", t["full_rpm"])
        eng.set_editor_property("turbo_spool_time_sec", t["spool"])
        eng.set_editor_property("turbo_lag_torque_fraction", t["lag"])
    da.set_editor_property("engine", eng)

    # ---- gearbox ----
    gb = unreal.RoamGearboxSpec()
    gb.set_editor_property("forward_ratios", [float(round(g, 3)) for g in d["gears"]])
    gb.set_editor_property("reverse_ratio", float(round(d["reverse"], 3)))
    gb.set_editor_property("final_drive", float(d["final"]))
    gb.set_editor_property("upshift_rpm_fraction", float(c["up"]))
    gb.set_editor_property("downshift_rpm_fraction", float(c["down"]))
    gb.set_editor_property("shift_time_sec", float(c["shift"]))
    gb.set_editor_property("efficiency", float(c["eff"]))
    da.set_editor_property("gearbox", gb)

    # ---- drivetrain ----
    dt = unreal.RoamDrivetrainSpec()
    df = c["diff"]
    dt.set_editor_property("layout", getattr(unreal.RoamDrivetrain, c["drivetrain"]))
    dt.set_editor_property("rear_torque_share", float(df["rear_share"]) if c["drivetrain"] == "AWD" else (1.0 if c["drivetrain"] == "RWD" else 0.0))
    dt.set_editor_property("front_diff", enum_value(unreal.RoamDiffType, df["front"]))
    dt.set_editor_property("rear_diff", enum_value(unreal.RoamDiffType, df["rear"]))
    dt.set_editor_property("center_diff", enum_value(unreal.RoamDiffType, df["center"]))
    dt.set_editor_property("front_lock_accel", float(df["fa"]))
    dt.set_editor_property("front_lock_decel", float(df["fd"]))
    dt.set_editor_property("rear_lock_accel", float(df["ra"]))
    dt.set_editor_property("rear_lock_decel", float(df["rd"]))
    dt.set_editor_property("center_lock", float(df["cl"]))
    dt.set_editor_property("preload_nm", float(df["preload"]))
    da.set_editor_property("drivetrain", dt)

    # ---- brakes ----
    br = unreal.RoamBrakeSpec()
    br.set_editor_property("peak_deceleration_g", float(c["brake"]["g"]))
    br.set_editor_property("bias_front", float(c["brake"]["bias"]))
    br.set_editor_property("handbrake_torque_nm", float(round(d["handbrake"], -1)))
    br.set_editor_property("has_abs", bool(c["brake"]["abs"]))
    br.set_editor_property("abs_slip_ratio", 0.14)
    da.set_editor_property("brakes", br)

    # ---- suspension ----
    s = c["susp"]
    for axle, prop in (("f", "suspension_front"), ("r", "suspension_rear")):
        sp = unreal.RoamSuspensionAxleSpec()
        sp.set_editor_property("spring_rate_n_per_m", float(round(d["k_" + axle], -1)))
        sp.set_editor_property("bump_damping_ns_per_m", float(round(d["bump_" + axle], -1)))
        sp.set_editor_property("rebound_damping_ns_per_m", float(round(d["reb_" + axle], -1)))
        sp.set_editor_property("travel_up_cm", float(s["up_" + axle]))
        sp.set_editor_property("travel_down_cm", float(s["dn_" + axle]))
        sp.set_editor_property("anti_roll_n_per_m", float(round(d["arb_" + axle], -1)))
        sp.set_editor_property("bump_stop_n_per_m", float(round(d["stop_" + axle], -3)))
        sp.set_editor_property("camber_gain_deg_per_m", float(s["camber"]))
        sp.set_editor_property("static_camber_deg", float(s["cam_" + axle]))
        sp.set_editor_property("static_toe_deg", float(s["toe_" + axle]))
        da.set_editor_property(prop, sp)

    # ---- tyres ----
    tr = c["tire"]
    for axle, prop, wname in (("f", "tire_front", "FL"), ("r", "tire_rear", "RL")):
        ts = unreal.RoamTireSpec()
        ts.set_editor_property("width_mm", float(round(js["wheels"][wname]["width"] * 1000.0)))
        ts.set_editor_property("peak_friction", float(tr["mu_" + axle]))
        ts.set_editor_property("slide_friction_ratio", float(tr["slide"]))
        ts.set_editor_property("load_sensitivity", float(tr["load"]))
        ts.set_editor_property("nominal_load_n", float(round(d["nominal_" + axle])))
        ts.set_editor_property("peak_slip_ratio", float(tr["ratio"]))
        ts.set_editor_property("peak_slip_angle_deg", float(tr["angle"]))
        ts.set_editor_property("rolling_resistance", float(tr["rr"]))
        ts.set_editor_property("surface_bias", surface_map(tr["bias"]))
        ts.set_editor_property("wet_grip_bias", float(tr["wet"]))
        da.set_editor_property(prop, ts)

    # ---- aero ----
    ae = unreal.RoamAeroSpec()
    ae.set_editor_property("cd_a", float(c["cda"]))
    ae.set_editor_property("cl_a_front", float(c["cla_f"]))
    ae.set_editor_property("cl_a_rear", float(c["cla_r"]))
    ae.set_editor_property("ground_effect", float(c["ground"]))
    aw = c.get("active_wing")
    ae.set_editor_property("active_wing", aw is not None)
    if aw:
        ae.set_editor_property("active_wing_extra_cl_a", float(aw["extra"]))
        ae.set_editor_property("active_wing_deploy_kmh", float(aw["kmh"]))
    da.set_editor_property("aero", ae)

    # ---- steering ----
    st = c["steer"]
    sp = unreal.RoamSteeringSpec()
    sp.set_editor_property("max_steer_angle_deg", float(st["max"]))
    sp.set_editor_property("speed_reduction", [unreal.Vector2D(x, y) for x, y in S.speed_reduction(st["curve"])])
    sp.set_editor_property("steer_rate_deg_per_sec", float(st["rate"]))
    sp.set_editor_property("steering_ratio", float(st["ratio"]))
    sp.set_editor_property("ackermann", float(st["ack"]))
    da.set_editor_property("steering", sp)

    # ---- assists ----
    a = c["assists"]
    ad = unreal.RoamAssistDefaults()
    ad.set_editor_property("traction_control", bool(a["tcs"]))
    ad.set_editor_property("stability_control", bool(a["stm"]))
    ad.set_editor_property("abs", bool(a["abs"]))
    ad.set_editor_property("steering_assist", float(a["steer"]))
    ad.set_editor_property("tcs_strength", float(a["tcs_str"]))
    ad.set_editor_property("stm_strength", float(a["stm_str"]))
    da.set_editor_property("assist_defaults", ad)

    # ---- sound ----
    so = c["sound"]
    ss = unreal.RoamSoundSpec()
    ss.set_editor_property("profile", so["profile"])
    ss.set_editor_property("cylinders", int(so["cyl"]))
    ss.set_editor_property("pitch_scale", float(so["pitch"]))
    ss.set_editor_property("harmonic_mix", [float(x) for x in S.harmonics(so["harm"])])
    ss.set_editor_property("noise_amount", float(so["noise"]))
    ss.set_editor_property("load_dependence", float(so["load"]))
    ss.set_editor_property("turbo_whine", bool(so["whine"]))
    ss.set_editor_property("turbo_whine_hz", unreal.Vector2D(1800.0, 6500.0))
    ss.set_editor_property("blow_off_volume", float(so["blowoff"]))
    ss.set_editor_property("exhaust_crackle", float(so["crackle"]))
    ss.set_editor_property("volume", float(so["vol"]))
    da.set_editor_property("sound", ss)

    # ---- garage ----
    da.set_editor_property("upgrade_slots", upgrade_slots(c))
    paints = []
    for pr, se, fin, stripe, wstyle, wcol in c["paints"]:
        p = unreal.RoamPaint()
        p.set_editor_property("primary", lin(S.srgb_to_linear(pr)))
        p.set_editor_property("secondary", lin(S.srgb_to_linear(se)))
        p.set_editor_property("finish", [unreal.RoamPaintFinish.GLOSS, unreal.RoamPaintFinish.MATTE, unreal.RoamPaintFinish.METALLIC][fin])
        p.set_editor_property("stripe_style", int(stripe))
        p.set_editor_property("wheel_style", int(wstyle))
        p.set_editor_property("wheel_color", lin(S.srgb_to_linear(wcol)))
        paints.append(p)
    da.set_editor_property("suggested_paints", paints)

    EAL.save_loaded_asset(da)
    try:
        # ---- report the engine's own estimator ----
        perf = da.compute_performance(unreal.RoamPerformanceRules())
        mine = S.estimate_pi(c, d, js)
        peak_kw = max(t * r * 2.0 * 3.14159265 / 60.0 / 1000.0 for r, t in d["torque_curve"])
        peak_nm = max(t for r, t in d["torque_curve"])
        unreal.log("CARS_PI %-26s UE: PI=%d %s t60=%.2f t100=%.2f vmax=%.0f latG=%.2f brake=%.1fm off=%.2f | py: PI=%d %s | target %s | peak %.0f kW %.0f Nm" % (
            vid, perf.performance_index, str(perf.car_class).split(".")[-1], perf.time0_to60_kmh, perf.time0_to100_kmh, perf.top_speed_kmh,
            perf.lateral_g, perf.brake_distance100m, perf.offroad01, mine["pi"], mine["cls"], c["pi_target"], peak_kw, peak_nm))
    except Exception:  # noqa: BLE001 - the report must never drop a car
        traceback.print_exc()
    return da


# ------------------------------------------------------------------------------------------------------------------
# traffic
# ------------------------------------------------------------------------------------------------------------------
def traffic_def(js):
    vid = js["id"]
    tp = S.TRAFFIC[vid]
    folder = TRAFFIC_ROOT
    d = unreal.RoamTrafficVehicleDef()
    d.set_editor_property("type_id", vid)
    d.set_editor_property("display_name", js.get("display_name", vid))
    body = load_mesh(folder, vid, "Body")
    wheels = []
    for w in js["wheels"] if isinstance(js["wheels"], list) else []:
        part = w["name"].replace(vid + "_", "")
        wd = unreal.RoamTrafficWheelDef()
        wd.set_editor_property("part_name", w["name"])
        wd.set_editor_property("mesh", load_mesh(folder, vid, part))
        wd.set_editor_property("center_cm", ue_pos(w["center"]))
        wd.set_editor_property("radius_cm", w["radius"] * 100.0)
        wd.set_editor_property("width_cm", w["width"] * 100.0)
        wd.set_editor_property("axle_index", int(w.get("axle", 0)))
        wd.set_editor_property("steering", bool(w.get("steering", False)))
        wd.set_editor_property("driven", bool(w.get("driven", False)))
        wd.set_editor_property("left_side", w["center"][1] > 0)    # Blender +Y = vehicle left
        wheels.append(wd)
    d.set_editor_property("wheels", wheels)
    d.set_editor_property("glass_mesh", load_mesh(folder, vid, "Glass"))
    d.set_editor_property("interior_mesh", load_mesh(folder, vid, "Interior"))
    spec = unreal.RoamTrafficVehicleSpec()
    dims = js["dimensions"]
    first = js["wheels"][0]
    spec.set_editor_property("type_id", vid)
    spec.set_editor_property("body_mesh", body)
    spec.set_editor_property("wheel_mesh", wheels[0].get_editor_property("mesh") if wheels else None)
    spec.set_editor_property("length_cm", dims["length"] * 100.0)
    spec.set_editor_property("width_cm", dims["width"] * 100.0)
    spec.set_editor_property("height_cm", dims["height"] * 100.0)
    spec.set_editor_property("wheelbase_cm", js["wheelbase"] * 100.0)
    spec.set_editor_property("wheel_radius_cm", first["radius"] * 100.0)
    spec.set_editor_property("track_cm", js["track_front"] * 100.0)
    spec.set_editor_property("mass_kg", float(tp["mass"]))
    spec.set_editor_property("max_speed_kmh", float(tp["vmax"]))
    spec.set_editor_property("acceleration_ms2", float(tp["accel"]))
    spec.set_editor_property("comfort_decel_ms2", float(tp["decel"]))
    spec.set_editor_property("time_headway_sec", float(tp["headway"]))
    spec.set_editor_property("min_gap_m", float(tp["mingap"]))
    spec.set_editor_property("spawn_weight", float(tp["weight"]))
    if tp["roads"]:
        spec.set_editor_property("allowed_road_classes", [getattr(unreal.RoamRoadClass, r.upper()) for r in tp["roads"]])
    d.set_editor_property("spec", spec)
    cams = js.get("cameras", {})
    if "bumper" in cams:
        d.set_editor_property("camera_bumper_cm", ue_pos(cams["bumper"]))
    if "cockpit" in cams:
        d.set_editor_property("camera_cockpit_cm", ue_pos(cams["cockpit"]))
    lights = js.get("lights", {})
    for key, prop in (("head_l", "head_light_l_cm"), ("head_r", "head_light_r_cm"), ("tail_l", "tail_light_l_cm"), ("tail_r", "tail_light_r_cm"), ("reverse", "reverse_light_cm")):
        if key in lights:
            d.set_editor_property(prop, ue_pos(lights[key]))
    d.set_editor_property("exhaust_cm", [ue_pos(p) for p in js.get("exhaust", []) if isinstance(p, list) and len(p) == 3 and not isinstance(p[0], list)])
    paints = []
    for pv in js.get("paint_variants", []):
        p = unreal.RoamPaint()
        p.set_editor_property("primary", lin(pv["M_Paint"]["linear"]))
        p.set_editor_property("secondary", lin(pv["M_Paint2"]["linear"]))
        p.set_editor_property("finish", unreal.RoamPaintFinish.METALLIC if pv["M_Paint"]["metallic"] > 0.1 else unreal.RoamPaintFinish.GLOSS)
        paints.append(p)
    d.set_editor_property("paint_variants", paints)
    cs = js.get("traffic", {}).get("cruise_speed_kmh", [50, 110])
    d.set_editor_property("cruise_speed_kmh", unreal.Vector2D(cs[0], cs[1]))
    d.set_editor_property("num_axles", len(js["axles"]) if "axles" in js else 2)
    return d


def main():
    cars = []
    for c in S.CARS:
        try:
            cars.append(build_car(c))
            log("DA_Car_%s OK" % c["id"])
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            warn("DA_Car_%s FAILED" % c["id"])
    cat = get_or_create("DA_CarCatalog", unreal.RoamCarCatalog)
    cat.set_editor_property("cars", cars)
    EAL.save_loaded_asset(cat)
    log("DA_CarCatalog: %d cars in roster order" % len(cars))

    tc = get_or_create("DA_TrafficVehicles", unreal.RoamTrafficCatalog)
    defs = []
    for vid in sorted(S.TRAFFIC.keys()):
        try:
            js = S.load_json(EXPORTS, vid, "Traffic")
            defs.append(traffic_def(js))
            log("traffic def %s OK" % vid)
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            warn("traffic def %s FAILED" % vid)
    tc.set_editor_property("vehicles", defs)
    EAL.save_loaded_asset(tc)
    log("DA_TrafficVehicles: %d vehicle types" % len(defs))
    unreal.log("CARS_DATA_RESULT cars=%d traffic=%d" % (len(cars), len(defs)))


try:
    main()
except Exception:  # noqa: BLE001
    traceback.print_exc()
    unreal.log_error("CARS_DATA FAILED")
finally:
    if not JOB_MODE:
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
