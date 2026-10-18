"""Generates Source/Sonnet55Forza/Vehicle/RoamTestCarData.inl: the 10 roster cars as plain C++ assignments, derived by the SAME code that
builds the DA_Car_* data assets (Tools/ue/cars_spec.py: derive() + the Blender sidecar JSON geometry), so the automated drive tests and
the `testcar` console command measure exactly the numbers the data assets will carry.

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools/ue/drive_test_cars_gen.py

Re-run it whenever cars_spec.py or the Exports/Cars JSON change; commit the .inl.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cars_spec as S  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
EXPORTS = os.path.join(ROOT, "Exports")
OUT = os.path.join(ROOT, "Source", "Sonnet55Forza", "Vehicle", "RoamTestCarData.inl")


def f(x):
    s = "%.6g" % float(x)
    if "." not in s and "e" not in s and "n" not in s:
        s += ".0"
    return s + "f"


def ue_pos(v):
    return "FVector(%s, %s, %s)" % (f(v[0] * 100.0), f(-v[1] * 100.0), f(v[2] * 100.0))


def diff_enum(name):
    return {"Open": "ERoamDiffType::Open", "LimitedSlip": "ERoamDiffType::LimitedSlip", "Locked": "ERoamDiffType::Locked"}[name]


def emit_car(c, idx):
    js = S.load_json(EXPORTS, c["id"])
    d = S.derive(c, js)
    L = []
    a = L.append
    a("\tcase %d:" % idx)
    a("\t{")
    a("\t\tD->CarId = TEXT(\"%s\");" % c["id"])
    a("\t\tD->DisplayName = FText::FromString(TEXT(\"%s\"));" % c["name"])
    dims = js["dimensions"]
    a("\t\tD->Geometry.LengthCm = %s; D->Geometry.WidthCm = %s; D->Geometry.HeightCm = %s;" % (f(dims["length"] * 100), f(dims["width"] * 100), f(dims["height"] * 100)))
    a("\t\tD->Geometry.WheelbaseCm = %s; D->Geometry.TrackFrontCm = %s; D->Geometry.TrackRearCm = %s; D->Geometry.RideHeightCm = %s;" % (
        f(js["wheelbase"] * 100), f(js["track_front"] * 100), f(js["track_rear"] * 100), f(js.get("ride_height", 0.12) * 100)))
    for key, wname in (("WheelFL", "FL"), ("WheelFR", "FR"), ("WheelRL", "RL"), ("WheelRR", "RR")):
        w = js["wheels"][wname]
        a("\t\tD->Geometry.%s.CenterCm = %s; D->Geometry.%s.RadiusCm = %s; D->Geometry.%s.WidthCm = %s;" % (key, ue_pos(w["center"]), key, f(w["radius"] * 100), key, f(w["width"] * 100)))
    a("\t\tD->MassKg = %s; D->CenterOfMassCm = FVector(%s, %s, %s); D->HandlingFactor = %s;" % (f(c["mass"]), f(d["com"][0]), f(d["com"][1]), f(d["com"][2]), f(c["handling"])))
    # engine
    a("\t\tD->Engine.TorqueCurve = {")
    for r, t in d["torque_curve"]:
        a("\t\t\t{%s, %s}," % (f(r), f(t)))
    a("\t\t};")
    a("\t\tD->Engine.IdleRPM = %s; D->Engine.RedlineRPM = %s; D->Engine.RevLimiterRPM = %s;" % (f(c["idle"]), f(c["redline"]), f(c["limiter"])))
    a("\t\tD->Engine.InertiaKgM2 = %s; D->Engine.EngineBrakeNm = %s; D->Engine.ThrottleResponseSec = %s;" % (f(c["engine_inertia"]), f(c["engine_brake"]), f(c["throttle"])))
    t = c["turbo"]
    a("\t\tD->Engine.bTurbo = %s;" % ("true" if t else "false"))
    if t:
        a("\t\tD->Engine.MaxBoostBar = %s; D->Engine.TurboFullBoostRPM = %s; D->Engine.TurboSpoolTimeSec = %s; D->Engine.TurboLagTorqueFraction = %s;" % (f(t["bar"]), f(t["full_rpm"]), f(t["spool"]), f(t["lag"])))
    # gearbox
    a("\t\tD->Gearbox.ForwardRatios = { %s };" % ", ".join(f(round(g, 3)) for g in d["gears"]))
    a("\t\tD->Gearbox.ReverseRatio = %s; D->Gearbox.FinalDrive = %s; D->Gearbox.UpshiftRpmFraction = %s; D->Gearbox.DownshiftRpmFraction = %s;" % (f(round(d["reverse"], 3)), f(d["final"]), f(c["up"]), f(c["down"])))
    a("\t\tD->Gearbox.ShiftTimeSec = %s; D->Gearbox.Efficiency = %s;" % (f(c["shift"]), f(c["eff"])))
    # drivetrain
    df = c["diff"]
    rear_share = df["rear_share"] if c["drivetrain"] == "AWD" else (1.0 if c["drivetrain"] == "RWD" else 0.0)
    a("\t\tD->Drivetrain.Layout = ERoamDrivetrain::%s; D->Drivetrain.RearTorqueShare = %s;" % (c["drivetrain"], f(rear_share)))
    a("\t\tD->Drivetrain.FrontDiff = %s; D->Drivetrain.RearDiff = %s; D->Drivetrain.CenterDiff = %s;" % (diff_enum(df["front"]), diff_enum(df["rear"]), diff_enum(df["center"])))
    a("\t\tD->Drivetrain.FrontLockAccel = %s; D->Drivetrain.FrontLockDecel = %s; D->Drivetrain.RearLockAccel = %s; D->Drivetrain.RearLockDecel = %s; D->Drivetrain.CenterLock = %s; D->Drivetrain.PreloadNm = %s;" % (
        f(df["fa"]), f(df["fd"]), f(df["ra"]), f(df["rd"]), f(df["cl"]), f(df["preload"])))
    # brakes
    br = c["brake"]
    a("\t\tD->Brakes.PeakDecelerationG = %s; D->Brakes.BiasFront = %s; D->Brakes.HandbrakeTorqueNm = %s; D->Brakes.bHasABS = %s; D->Brakes.ABSSlipRatio = 0.14f;" % (
        f(br["g"]), f(br["bias"]), f(round(d["handbrake"], -1)), "true" if br["abs"] else "false"))
    # suspension
    s = c["susp"]
    for axle, prop in (("f", "SuspensionFront"), ("r", "SuspensionRear")):
        a("\t\tD->%s.SpringRateNPerM = %s; D->%s.BumpDampingNsPerM = %s; D->%s.ReboundDampingNsPerM = %s;" % (prop, f(round(d["k_" + axle], -1)), prop, f(round(d["bump_" + axle], -1)), prop, f(round(d["reb_" + axle], -1))))
        a("\t\tD->%s.TravelUpCm = %s; D->%s.TravelDownCm = %s; D->%s.AntiRollNPerM = %s; D->%s.BumpStopNPerM = %s;" % (prop, f(s["up_" + axle]), prop, f(s["dn_" + axle]), prop, f(round(d["arb_" + axle], -1)), prop, f(round(d["stop_" + axle], -3))))
        a("\t\tD->%s.CamberGainDegPerM = %s; D->%s.StaticCamberDeg = %s; D->%s.StaticToeDeg = %s;" % (prop, f(s["camber"]), prop, f(s["cam_" + axle]), prop, f(s["toe_" + axle])))
    # tyres
    tr = c["tire"]
    for axle, prop, wname in (("f", "TireFront", "FL"), ("r", "TireRear", "RL")):
        a("\t\tD->%s.WidthMm = %s; D->%s.PeakFriction = %s; D->%s.SlideFrictionRatio = %s; D->%s.LoadSensitivity = %s; D->%s.NominalLoadN = %s;" % (
            prop, f(round(js["wheels"][wname]["width"] * 1000)), prop, f(tr["mu_" + axle]), prop, f(tr["slide"]), prop, f(tr["load"]), prop, f(round(d["nominal_" + axle]))))
        a("\t\tD->%s.PeakSlipRatio = %s; D->%s.PeakSlipAngleDeg = %s; D->%s.RollingResistance = %s; D->%s.WetGripBias = %s;" % (prop, f(tr["ratio"]), prop, f(tr["angle"]), prop, f(tr["rr"]), prop, f(tr["wet"])))
        for sname, val in tr["bias"].items():
            a("\t\tD->%s.SurfaceBias.Add(ERoamSurface::%s, %s);" % (prop, sname, f(val)))
    # aero, steering, assists
    a("\t\tD->Aero.CdA = %s; D->Aero.ClAFront = %s; D->Aero.ClARear = %s; D->Aero.GroundEffect = %s;" % (f(c["cda"]), f(c["cla_f"]), f(c["cla_r"]), f(c["ground"])))
    aw = c.get("active_wing")
    if aw:
        a("\t\tD->Aero.bActiveWing = true; D->Aero.ActiveWingExtraClA = %s; D->Aero.ActiveWingDeployKmh = %s;" % (f(aw["extra"]), f(aw["kmh"])))
    st = c["steer"]
    a("\t\tD->Steering.MaxSteerAngleDeg = %s; D->Steering.SteerRateDegPerSec = %s; D->Steering.SteeringRatio = %s; D->Steering.Ackermann = %s;" % (f(st["max"]), f(st["rate"]), f(st["ratio"]), f(st["ack"])))
    a("\t\tD->Steering.SpeedReduction = { %s };" % ", ".join("FVector2D(%s, %s)" % (f(x), f(y)) for x, y in S.speed_reduction(st["curve"])))
    asx = c["assists"]
    a("\t\tD->AssistDefaults.bTractionControl = %s; D->AssistDefaults.bStabilityControl = %s; D->AssistDefaults.bABS = %s; D->AssistDefaults.SteeringAssist = %s; D->AssistDefaults.TCSStrength = %s; D->AssistDefaults.STMStrength = %s;" % (
        "true" if asx["tcs"] else "false", "true" if asx["stm"] else "false", "true" if asx["abs"] else "false", f(asx["steer"]), f(asx["tcs_str"]), f(asx["stm_str"])))
    a("\t\tbreak;")
    a("\t}")
    return "\n".join(L)


def main():
    parts = ["// GENERATED by Tools/ue/drive_test_cars_gen.py from Tools/ue/cars_spec.py + Exports/Cars/*.json. Do not edit by hand.", ""]
    parts.append("static const TCHAR* const GRoamTestCarIds[] = {")
    for c in S.CARS:
        parts.append("\tTEXT(\"%s\")," % c["id"])
    parts.append("};")
    parts.append("")
    parts.append("static void RoamFillTestCar(int32 Index, URoamCarDefinition* D)")
    parts.append("{")
    parts.append("\tswitch (Index)")
    parts.append("\t{")
    for i, c in enumerate(S.CARS):
        parts.append(emit_car(c, i))
    parts.append("\tdefault: break;")
    parts.append("\t}")
    parts.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(parts) + "\n")
    print("wrote", OUT, "(%d cars)" % len(S.CARS))


if __name__ == "__main__":
    main()
