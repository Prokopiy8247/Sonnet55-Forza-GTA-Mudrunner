"""First-pass vehicle specification of the 10 player cars and the 6 traffic vehicles ("handling numbers").

Pure Python (no `unreal` import) so it runs both inside the editor (imported by cars_data.py) and offline for tuning:
    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools/ue/cars_spec.py          # prints derived data + the PI estimate of every car
The geometry (wheel centres, radii, anchors) is NOT here: it comes from the Blender sidecar JSON (Exports/Cars/<id>/<id>.json).
Everything here is the physics / identity layer derived from Docs/CAR_ROSTER.md (mass, power, drivetrain, class brief) with plain
engineering rules (documented in Docs/Tech/CARS_IMPORT.md, section "Tuning method"):
  * torque curve: parabola shape(x) = max(floor, 1 - k (x - xp)^2), x = rpm / redline, scaled so the peak of T*omega is PeakPowerKw
    (same family as FRoamEngineSpec::BuildSyntheticTorqueCurve, which uses xp = 0.62, k = 1.35, floor = 0.35);
  * gearing: top gear is an overdrive of 1.05..1.12 x the drag-limited top speed, first gear from a "speed at redline in 1st"
    figure, intermediate gears geometric with a slightly closer top end;
  * suspension: spring rate k = sprung_mass_per_wheel (88 % of the axle load / 2) x (2 pi f)^2 with f = 1.1 .. 2.2 Hz,
    damping c = 2 zeta sqrt(k m) with bump zeta 0.30-0.45 and rebound zeta 0.50-0.70;
  * tyres: peak mu by compound (economy 0.9 .. slick-like 1.4), load sensitivity 0.12-0.2, SurfaceBias > 1 only for rally/all-terrain.
Units: SI (kg, N, Nm, m^2), centimetres for travel, degrees, km/h. Tuned later by the vehicle-physics agent with DRIVE_TESTS.
"""
import json
import math
import os

G = 9.81
RHO = 1.2
SURFACE_BASE = {"Asphalt": 1.00, "Concrete": 0.97, "Dirt": 0.78, "Gravel": 0.70, "Grass": 0.60, "Sand": 0.55, "Snow": 0.35, "Mud": 0.45}


# ------------------------------------------------------------------------------------------------------------------
# colour helpers
# ------------------------------------------------------------------------------------------------------------------
def srgb_to_linear(hex_color):
    h = hex_color.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


# ------------------------------------------------------------------------------------------------------------------
# engine / gearing helpers
# ------------------------------------------------------------------------------------------------------------------
def torque_curve(peak_kw, idle, redline, xp=0.62, k=1.35, floor=0.35, samples=32):
    """List of (rpm, Nm) whose max(T*omega) over [idle, redline] equals peak_kw."""
    def shape(rpm):
        x = rpm / redline
        return max(floor, 1.0 - k * (x - xp) ** 2)

    best = 0.0
    rpm = idle
    while rpm <= redline:
        best = max(best, shape(rpm) * rpm * 2.0 * math.pi / 60.0)
        rpm += 25.0
    peak_torque = peak_kw * 1000.0 / max(best, 1.0)
    pts = []
    for i in range(samples):
        a = i / (samples - 1)
        r = idle + (redline - idle) * a
        pts.append((r, peak_torque * shape(r)))
    return pts


def drag_limited_vmax_kmh(peak_kw, cda, mass, crr, eff, cla=0.0):
    """Speed where eff * P = 0.5 rho CdA v^3 + Crr m g v (bisection)."""
    p = peak_kw * 1000.0 * eff
    lo, hi = 10.0, 200.0
    for _ in range(60):
        v = 0.5 * (lo + hi)
        need = 0.5 * RHO * cda * v ** 3 + crr * mass * G * v
        if need > p:
            hi = v
        else:
            lo = v
    return lo * 3.6


def gear_ratios(n, final_drive, redline, wheel_r_m, v1_kmh, vtop_kmh, skew=0.88):
    """n forward ratios (not including the final drive) from first-gear and top-gear speeds at redline."""
    k = redline * 2.0 * math.pi / 60.0 * wheel_r_m
    g1 = k / (v1_kmh / 3.6) / final_drive
    gn = k / (vtop_kmh / 3.6) / final_drive
    out = []
    for i in range(n):
        t = (i / (n - 1)) ** skew if n > 1 else 0.0
        out.append(g1 * (gn / g1) ** t)
    return out


def speed_reduction(kind):
    table = {
        "agile": [(0, 1.0), (60, 0.78), (120, 0.45), (200, 0.26), (300, 0.17)],
        "stable": [(0, 1.0), (60, 0.72), (120, 0.40), (200, 0.22), (300, 0.14)],
        "sport": [(0, 1.0), (60, 0.80), (120, 0.48), (200, 0.27), (300, 0.15)],
        "truck": [(0, 1.0), (60, 0.70), (120, 0.36), (200, 0.20), (300, 0.12)],
        "vintage": [(0, 1.0), (50, 0.80), (100, 0.50), (160, 0.30), (300, 0.20)],
    }
    return table[kind]


def harmonics(kind):
    return {
        "inline4": [1.0, 0.55, 0.35, 0.20, 0.12, 0.07],
        "inline4_soft": [1.0, 0.45, 0.28, 0.14, 0.08, 0.04],
        "v8": [1.0, 0.72, 0.52, 0.34, 0.24, 0.14],
        "v8_flat": [1.0, 0.55, 0.62, 0.30, 0.28, 0.16],
        "v6": [1.0, 0.62, 0.42, 0.28, 0.16, 0.10],
        "flat6": [1.0, 0.65, 0.48, 0.30, 0.20, 0.12],
        "v12": [1.0, 0.45, 0.36, 0.30, 0.24, 0.18],
        "diesel": [1.0, 0.80, 0.55, 0.30, 0.15, 0.08],
    }[kind]


# ------------------------------------------------------------------------------------------------------------------
# the roster
# ------------------------------------------------------------------------------------------------------------------
STREET = {}                                                                     # all surfaces 1.0
SPORT = {"Dirt": 0.82, "Gravel": 0.78, "Grass": 0.85, "Sand": 0.85, "Snow": 0.80, "Mud": 0.80}
RALLY = {"Dirt": 1.32, "Gravel": 1.38, "Grass": 1.18, "Sand": 1.22, "Snow": 1.25, "Mud": 1.25, "Concrete": 1.0}
ALLTERRAIN = {"Dirt": 1.18, "Gravel": 1.20, "Grass": 1.15, "Sand": 1.12, "Snow": 1.15, "Mud": 1.25}
VINTAGE = {"Dirt": 0.95, "Gravel": 0.92, "Grass": 0.9, "Sand": 0.9, "Snow": 0.85, "Mud": 0.9}

# Each entry documents its own reasoning in `why`.
CARS = [
    dict(
        id="car01_hatch_pulse", name="Pulse", maker="Nordvik Motors", year=2024, price=34000, body="Hot hatch",
        tags=["hatch", "fwd", "turbo", "starter"], desc="Compact three-door hot hatch. Light, eager to turn in and happy to rotate when you lift mid-corner.",
        drivetrain="FWD", mass=1250, kw=155, idle=850, redline=6800, limiter=7000, curve=dict(xp=0.55, k=1.15, floor=0.55),
        turbo=dict(bar=1.1, full_rpm=2800, spool=0.45, lag=0.70), engine_inertia=0.15, engine_brake=40, throttle=0.09,
        front_weight=0.62, com_z=50, gears=6, final=4.15, v1=55, overdrive=1.05, shift=0.26, eff=0.87, up=0.95, down=0.42,
        diff=dict(front="LimitedSlip", rear="Open", fa=0.35, fd=0.10, ra=0.0, rd=0.0, center="Open", cl=0.0, rear_share=0.0, preload=40),
        brake=dict(g=0.92, bias=0.65, abs=True), cda=0.76, cla_f=0.0, cla_r=0.03, ground=0.0,
        susp=dict(hz_f=1.45, hz_r=1.70, zb=0.32, zr=0.58, up_f=8, dn_f=9, up_r=8, dn_r=10, arb_f=0.9, arb_r=0.35, camber=-9.0, cam_f=-1.3, cam_r=-1.2, toe_f=0.05, toe_r=0.15),
        tire=dict(mu_f=0.92, mu_r=0.90, slide=0.88, load=0.16, ratio=0.12, angle=8.0, rr=0.012, wet=1.0, bias=STREET),
        steer=dict(max=35, ratio=14.5, rate=280, ack=0.75, curve="agile"), handling=1.00,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.5, tcs_str=0.5, stm_str=0.5),
        sound=dict(profile="inline4", cyl=4, pitch=1.0, harm="inline4", noise=0.28, load=0.65, whine=True, blowoff=0.5, crackle=0.2, vol=1.0),
        paints=[("#c8202a", "#1a1a1c", 0, 0, 0, "#c9ccd2"), ("#1f5fbf", "#e8e9eb", 0, 1, 0, "#2b2d31"), ("#f2b705", "#1a1a1c", 0, 2, 1, "#1a1a1c"), ("#2a2d33", "#c8202a", 2, 0, 1, "#b9bcc2"), ("#e8e9eb", "#1f5fbf", 0, 0, 0, "#c9ccd2")],
        pi_target="D/C (about 380 in the roster; the PI formula gives C/B for 155 kW)",
    ),
    dict(
        id="car02_sedan_cadence", name="Cadence", maker="Alder Motorworks", year=2023, price=22000, body="Sedan",
        tags=["sedan", "fwd", "comfort", "starter"], desc="Everyday four-door sedan. Soft, stable and forgiving: safe understeer, lots of body roll and a quiet cabin.",
        drivetrain="FWD", mass=1480, kw=120, idle=800, redline=6200, limiter=6400, curve=dict(xp=0.66, k=1.5, floor=0.45),
        turbo=None, engine_inertia=0.17, engine_brake=45, throttle=0.08,
        front_weight=0.60, com_z=55, gears=6, final=3.95, v1=46, overdrive=1.10, shift=0.36, eff=0.86, up=0.94, down=0.40,
        diff=dict(front="Open", rear="Open", fa=0.0, fd=0.0, ra=0.0, rd=0.0, center="Open", cl=0.0, rear_share=0.0, preload=0),
        brake=dict(g=0.90, bias=0.66, abs=True), cda=0.70, cla_f=0.0, cla_r=0.0, ground=0.0,
        susp=dict(hz_f=1.18, hz_r=1.32, zb=0.30, zr=0.50, up_f=10, dn_f=11, up_r=10, dn_r=12, arb_f=0.55, arb_r=0.25, camber=-6.0, cam_f=-0.8, cam_r=-0.8, toe_f=0.05, toe_r=0.10),
        tire=dict(mu_f=0.88, mu_r=0.86, slide=0.90, load=0.18, ratio=0.12, angle=8.5, rr=0.011, wet=1.0, bias=STREET),
        steer=dict(max=34, ratio=15.5, rate=240, ack=0.7, curve="stable"), handling=0.85,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.6, tcs_str=0.6, stm_str=0.6),
        sound=dict(profile="inline4", cyl=4, pitch=0.95, harm="inline4_soft", noise=0.18, load=0.5, whine=False, blowoff=0.0, crackle=0.0, vol=0.85),
        paints=[("#8d98a6", "#2b2d31", 2, 0, 0, "#c9ccd2"), ("#e8e9eb", "#2b2d31", 0, 0, 0, "#c9ccd2"), ("#1d3557", "#8d98a6", 0, 0, 0, "#c9ccd2"), ("#5a1f27", "#2b2d31", 2, 0, 0, "#c9ccd2")],
        pi_target="D (about 330)",
    ),
    dict(
        id="car03_muscle_thunderline", name="Thunderline", maker="Bannock Automotive", year=1970, price=95000, body="Muscle car",
        tags=["muscle", "rwd", "v8", "drift"], desc="Two-door V8 fastback. Huge torque, a long hood and a tail that wants to come around: wheelspin is part of the deal.",
        drivetrain="RWD", mass=1650, kw=310, idle=800, redline=6500, limiter=6700, curve=dict(xp=0.60, k=1.25, floor=0.50),
        turbo=None, engine_inertia=0.32, engine_brake=95, throttle=0.07,
        front_weight=0.54, com_z=52, gears=6, final=3.55, v1=70, overdrive=1.07, shift=0.22, eff=0.90, up=0.95, down=0.45,
        diff=dict(front="Open", rear="LimitedSlip", fa=0.0, fd=0.0, ra=0.50, rd=0.15, center="Open", cl=0.0, rear_share=0.0, preload=60),
        brake=dict(g=1.00, bias=0.60, abs=True), cda=1.05, cla_f=0.0, cla_r=0.0, ground=0.0,
        susp=dict(hz_f=1.30, hz_r=1.45, zb=0.32, zr=0.55, up_f=10, dn_f=10, up_r=10, dn_r=11, arb_f=0.65, arb_r=0.30, camber=-8.0, cam_f=-1.0, cam_r=-0.8, toe_f=0.0, toe_r=0.10),
        tire=dict(mu_f=1.08, mu_r=1.15, slide=0.82, load=0.17, ratio=0.13, angle=8.5, rr=0.013, wet=0.97, bias=STREET),
        steer=dict(max=36, ratio=15.0, rate=250, ack=0.7, curve="stable"), handling=0.90,
        assists=dict(tcs=False, stm=True, abs=True, steer=0.5, tcs_str=0.5, stm_str=0.5),
        sound=dict(profile="v8", cyl=8, pitch=0.82, harm="v8", noise=0.38, load=0.75, whine=False, blowoff=0.0, crackle=0.55, vol=1.15),
        paints=[("#14213d", "#e8e9eb", 0, 3, 0, "#c9ccd2"), ("#b3141c", "#1a1a1c", 0, 3, 0, "#c9ccd2"), ("#f2b705", "#1a1a1c", 0, 3, 1, "#1a1a1c"), ("#2d3a2e", "#e8e9eb", 1, 0, 0, "#c9ccd2")],
        pi_target="B (roster 'about 580')",
    ),
    dict(
        id="car04_coupe_vesper", name="Vesper", maker="Corvane Coachworks", year=2024, price=118000, body="Sports coupe",
        tags=["coupe", "rwd", "sports", "balanced"], desc="Low two-door sports coupe with a long nose and a small cabin. Precise, balanced and it rotates on the throttle.",
        drivetrain="RWD", mass=1380, kw=285, idle=900, redline=7400, limiter=7600, curve=dict(xp=0.68, k=1.6, floor=0.50),
        turbo=None, engine_inertia=0.20, engine_brake=60, throttle=0.06,
        front_weight=0.52, com_z=46, gears=6, final=3.75, v1=66, overdrive=1.07, shift=0.18, eff=0.92, up=0.96, down=0.50,
        diff=dict(front="Open", rear="LimitedSlip", fa=0.0, fd=0.0, ra=0.55, rd=0.28, center="Open", cl=0.0, rear_share=0.0, preload=80),
        brake=dict(g=1.18, bias=0.58, abs=True), cda=0.62, cla_f=0.03, cla_r=0.12, ground=0.05,
        susp=dict(hz_f=1.85, hz_r=2.00, zb=0.40, zr=0.65, up_f=7, dn_f=8, up_r=7, dn_r=9, arb_f=1.0, arb_r=0.65, camber=-11.0, cam_f=-2.0, cam_r=-1.6, toe_f=-0.05, toe_r=0.15),
        tire=dict(mu_f=1.16, mu_r=1.16, slide=0.90, load=0.14, ratio=0.11, angle=7.0, rr=0.011, wet=0.95, bias=SPORT),
        steer=dict(max=33, ratio=13.0, rate=300, ack=0.8, curve="sport"), handling=1.05,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.4, tcs_str=0.4, stm_str=0.4),
        sound=dict(profile="flat6", cyl=6, pitch=1.15, harm="flat6", noise=0.30, load=0.7, whine=False, blowoff=0.0, crackle=0.3, vol=1.0),
        paints=[("#7a1d2e", "#1a1a1c", 2, 0, 1, "#2b2d31"), ("#c9ccd2", "#1a1a1c", 2, 1, 1, "#2b2d31"), ("#0e6b57", "#e8e9eb", 0, 0, 0, "#c9ccd2"), ("#1a1a1c", "#c8202a", 1, 0, 1, "#2b2d31")],
        pi_target="A (about 650-700)",
    ),
    dict(
        id="car05_gt_meridian", name="Meridian GT", maker="Lorien GT", year=2024, price=215000, body="Grand tourer",
        tags=["gt", "rwd", "v12", "highspeed"], desc="Front-engined V12 grand tourer with a very long hood and a set-back cabin. Planted and unflustered at 300 km/h.",
        drivetrain="RWD", mass=1700, kw=410, idle=800, redline=7000, limiter=7200, curve=dict(xp=0.66, k=1.3, floor=0.55),
        turbo=None, engine_inertia=0.34, engine_brake=85, throttle=0.06,
        front_weight=0.51, com_z=50, gears=8, final=3.30, v1=62, overdrive=1.07, shift=0.15, eff=0.92, up=0.96, down=0.50,
        diff=dict(front="Open", rear="LimitedSlip", fa=0.0, fd=0.0, ra=0.45, rd=0.22, center="Open", cl=0.0, rear_share=0.0, preload=70),
        brake=dict(g=1.22, bias=0.60, abs=True), cda=0.68, cla_f=0.06, cla_r=0.20, ground=0.05,
        susp=dict(hz_f=1.70, hz_r=1.85, zb=0.40, zr=0.65, up_f=8, dn_f=9, up_r=8, dn_r=9, arb_f=0.95, arb_r=0.60, camber=-10.0, cam_f=-1.8, cam_r=-1.5, toe_f=0.0, toe_r=0.12),
        tire=dict(mu_f=1.18, mu_r=1.20, slide=0.90, load=0.14, ratio=0.11, angle=7.0, rr=0.011, wet=0.95, bias=SPORT),
        steer=dict(max=32, ratio=13.5, rate=280, ack=0.8, curve="stable"), handling=1.00,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.4, tcs_str=0.45, stm_str=0.5),
        sound=dict(profile="v12", cyl=12, pitch=0.9, harm="v12", noise=0.22, load=0.6, whine=False, blowoff=0.0, crackle=0.25, vol=1.05),
        paints=[("#0b2a4a", "#c9ccd2", 2, 0, 1, "#b9bcc2"), ("#1a1a1c", "#8a6a2b", 0, 0, 1, "#8a6a2b"), ("#d8d4c8", "#1a1a1c", 0, 0, 0, "#2b2d31"), ("#4a0f1c", "#1a1a1c", 2, 0, 1, "#2b2d31")],
        pi_target="A/S1 (about 720)",
    ),
    dict(
        id="car06_super_aether", name="Aether", maker="Zephyra Hypercars", year=2025, price=640000, body="Supercar",
        tags=["super", "awd", "midengine", "turbo", "hybrid"], desc="Mid-engined wedge with scissor-style roof glass, active rear wing and an enormous appetite for grip. Sharp turn-in, relentless traction.",
        drivetrain="AWD", mass=1450, kw=540, idle=1000, redline=8400, limiter=8600, curve=dict(xp=0.66, k=0.95, floor=0.55),
        turbo=dict(bar=1.5, full_rpm=3600, spool=0.30, lag=0.84), engine_inertia=0.20, engine_brake=60, throttle=0.045,
        front_weight=0.43, com_z=42, gears=7, final=3.50, v1=75, overdrive=1.06, shift=0.07, eff=0.93, up=0.97, down=0.55,
        diff=dict(front="LimitedSlip", rear="LimitedSlip", fa=0.30, fd=0.10, ra=0.55, rd=0.30, center="LimitedSlip", cl=0.35, rear_share=0.62, preload=90),
        brake=dict(g=1.40, bias=0.52, abs=True), cda=0.86, cla_f=0.55, cla_r=0.95, ground=0.18, active_wing=dict(extra=0.55, kmh=110),
        susp=dict(hz_f=2.10, hz_r=2.20, zb=0.42, zr=0.68, up_f=6, dn_f=7, up_r=6, dn_r=8, arb_f=1.1, arb_r=0.9, camber=-12.0, cam_f=-2.5, cam_r=-2.0, toe_f=-0.05, toe_r=0.15),
        tire=dict(mu_f=1.42, mu_r=1.45, slide=0.92, load=0.12, ratio=0.10, angle=6.5, rr=0.010, wet=0.88, bias=SPORT),
        steer=dict(max=30, ratio=12.0, rate=330, ack=0.85, curve="sport"), handling=1.10,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.3, tcs_str=0.4, stm_str=0.4),
        sound=dict(profile="v8_flatplane", cyl=8, pitch=1.3, harm="v8_flat", noise=0.25, load=0.8, whine=True, blowoff=0.8, crackle=0.45, vol=1.1),
        paints=[("#e8e9eb", "#1a1a1c", 0, 1, 1, "#2b2d31"), ("#ff5a1f", "#1a1a1c", 0, 2, 1, "#1a1a1c"), ("#1a1a1c", "#ff5a1f", 2, 0, 1, "#b9bcc2"), ("#0aa6c2", "#1a1a1c", 2, 0, 1, "#2b2d31")],
        pi_target="S2 (about 850-920)",
    ),
    dict(
        id="car07_rally_ridge", name="Ridge", maker="Tarn Rally Works", year=2023, price=76000, body="Rally hatch",
        tags=["rally", "awd", "turbo", "offroad", "drift"], desc="Raised turbo rally hatch with a huge wing and spotlight pod. Superb on gravel and dirt, and always ready to slide.",
        drivetrain="AWD", mass=1260, kw=235, idle=900, redline=7000, limiter=7200, curve=dict(xp=0.58, k=1.0, floor=0.55),
        turbo=dict(bar=1.4, full_rpm=3300, spool=0.40, lag=0.68), engine_inertia=0.16, engine_brake=45, throttle=0.08,
        front_weight=0.57, com_z=58, gears=6, final=4.45, v1=52, overdrive=1.04, shift=0.20, eff=0.85, up=0.95, down=0.45,
        diff=dict(front="LimitedSlip", rear="LimitedSlip", fa=0.30, fd=0.10, ra=0.40, rd=0.15, center="LimitedSlip", cl=0.45, rear_share=0.52, preload=60),
        brake=dict(g=0.88, bias=0.62, abs=True), cda=0.88, cla_f=0.0, cla_r=0.18, ground=0.0,
        susp=dict(hz_f=1.25, hz_r=1.40, zb=0.38, zr=0.62, up_f=14, dn_f=15, up_r=14, dn_r=16, arb_f=0.55, arb_r=0.30, camber=-5.0, cam_f=-0.6, cam_r=-0.6, toe_f=0.0, toe_r=0.10),
        tire=dict(mu_f=0.85, mu_r=0.85, slide=0.92, load=0.14, ratio=0.14, angle=10.0, rr=0.014, wet=1.05, bias=RALLY),
        steer=dict(max=38, ratio=12.5, rate=300, ack=0.65, curve="agile"), handling=0.92,
        assists=dict(tcs=True, stm=False, abs=True, steer=0.5, tcs_str=0.4, stm_str=0.3),
        sound=dict(profile="inline4", cyl=4, pitch=1.05, harm="inline4", noise=0.35, load=0.7, whine=True, blowoff=0.9, crackle=0.8, vol=1.1),
        paints=[("#1f4fbf", "#f2b705", 0, 2, 0, "#f2b705"), ("#e8e9eb", "#c8202a", 0, 2, 0, "#2b2d31"), ("#2a2d33", "#f2b705", 1, 0, 0, "#f2b705"), ("#ff7a00", "#1a1a1c", 0, 1, 0, "#1a1a1c")],
        pi_target="B (about 600)",
    ),
    dict(
        id="car08_suv_ranger", name="Ranger", maker="Highmoor Overland", year=2023, price=58000, body="Off-road SUV",
        tags=["suv", "awd", "offroad", "tall"], desc="Tall boxy off-roader with a roof rack, snorkel and bull bar. Long-travel suspension and knobbly tyres go where roads end.",
        drivetrain="AWD", mass=2150, kw=220, idle=750, redline=5800, limiter=6000, curve=dict(xp=0.46, k=1.7, floor=0.45),
        turbo=dict(bar=1.0, full_rpm=2200, spool=0.55, lag=0.78), engine_inertia=0.30, engine_brake=70, throttle=0.10,
        front_weight=0.52, com_z=88, gears=6, final=3.90, v1=42, overdrive=1.10, shift=0.28, eff=0.88, up=0.90, down=0.38,
        diff=dict(front="Open", rear="LimitedSlip", fa=0.0, fd=0.0, ra=0.35, rd=0.10, center="Locked", cl=0.65, rear_share=0.50, preload=50),
        brake=dict(g=0.92, bias=0.62, abs=True), cda=1.25, cla_f=0.0, cla_r=0.0, ground=0.0,
        susp=dict(hz_f=1.10, hz_r=1.20, zb=0.32, zr=0.55, up_f=16, dn_f=18, up_r=16, dn_r=18, arb_f=0.50, arb_r=0.35, camber=-4.0, cam_f=-0.3, cam_r=-0.3, toe_f=0.05, toe_r=0.05),
        tire=dict(mu_f=0.92, mu_r=0.92, slide=0.90, load=0.20, ratio=0.14, angle=10.0, rr=0.016, wet=1.05, bias=ALLTERRAIN),
        steer=dict(max=36, ratio=17.0, rate=220, ack=0.65, curve="truck"), handling=0.82,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.6, tcs_str=0.6, stm_str=0.6),
        sound=dict(profile="v6", cyl=6, pitch=0.9, harm="diesel", noise=0.30, load=0.7, whine=True, blowoff=0.2, crackle=0.0, vol=1.05),
        paints=[("#3d4a2f", "#1a1a1c", 1, 0, 2, "#1a1a1c"), ("#c9ccd2", "#1a1a1c", 0, 0, 2, "#1a1a1c"), ("#a4501b", "#1a1a1c", 0, 0, 2, "#1a1a1c"), ("#1a1a1c", "#f2b705", 1, 0, 2, "#f2b705")],
        pi_target="C (about 480)",
    ),
    dict(
        id="car09_pickup_mule", name="Mule", maker="Coldwater Truck Co.", year=2022, price=52000, body="Pickup truck",
        tags=["pickup", "rwd", "v8", "heavy", "offroad"], desc="Double-cab pickup with an open bed and a tall stance. Heavy, rolls a lot and needs a long way to stop, but it hauls.",
        drivetrain="RWD", mass=2350, kw=250, idle=700, redline=5600, limiter=5800, curve=dict(xp=0.52, k=1.7, floor=0.50),
        turbo=None, engine_inertia=0.38, engine_brake=110, throttle=0.09,
        front_weight=0.54, com_z=82, gears=6, final=3.73, v1=48, overdrive=1.10, shift=0.26, eff=0.90, up=0.90, down=0.38,
        diff=dict(front="Open", rear="LimitedSlip", fa=0.0, fd=0.0, ra=0.30, rd=0.08, center="Open", cl=0.0, rear_share=0.0, preload=40),
        brake=dict(g=0.88, bias=0.62, abs=True), cda=1.55, cla_f=0.0, cla_r=0.0, ground=0.0,
        susp=dict(hz_f=1.12, hz_r=1.45, zb=0.30, zr=0.52, up_f=14, dn_f=15, up_r=14, dn_r=16, arb_f=0.55, arb_r=0.25, camber=-4.0, cam_f=-0.3, cam_r=0.0, toe_f=0.05, toe_r=0.0),
        tire=dict(mu_f=0.95, mu_r=0.93, slide=0.90, load=0.20, ratio=0.13, angle=9.5, rr=0.015, wet=1.03, bias=ALLTERRAIN),
        steer=dict(max=36, ratio=18.0, rate=210, ack=0.6, curve="truck"), handling=0.80,
        assists=dict(tcs=True, stm=True, abs=True, steer=0.6, tcs_str=0.6, stm_str=0.6),
        sound=dict(profile="v8", cyl=8, pitch=0.75, harm="v8", noise=0.40, load=0.8, whine=False, blowoff=0.0, crackle=0.1, vol=1.15),
        paints=[("#b3141c", "#1a1a1c", 0, 0, 2, "#1a1a1c"), ("#e8e9eb", "#1a1a1c", 0, 0, 2, "#c9ccd2"), ("#2f4f6f", "#1a1a1c", 0, 0, 2, "#1a1a1c"), ("#6b705c", "#1a1a1c", 1, 0, 2, "#1a1a1c")],
        pi_target="C (about 450)",
    ),
    dict(
        id="car10_roadster_classic", name="Brisa", maker="Brisa Motor Co.", year=1957, price=18000, body="Vintage roadster",
        tags=["classic", "rwd", "roadster", "drift", "starter"], desc="Light vintage open roadster with separate wings and a folded soft-top. Slow, charming and very easy to slide.",
        drivetrain="RWD", mass=900, kw=70, idle=800, redline=5400, limiter=5600, curve=dict(xp=0.62, k=1.4, floor=0.45),
        turbo=None, engine_inertia=0.14, engine_brake=32, throttle=0.10,
        front_weight=0.50, com_z=44, gears=4, final=4.10, v1=38, overdrive=1.08, shift=0.45, eff=0.86, up=0.93, down=0.40,
        diff=dict(front="Open", rear="Open", fa=0.0, fd=0.0, ra=0.0, rd=0.0, center="Open", cl=0.0, rear_share=0.0, preload=0),
        brake=dict(g=0.78, bias=0.55, abs=False), cda=1.00, cla_f=0.0, cla_r=0.0, ground=0.0,
        susp=dict(hz_f=1.15, hz_r=1.30, zb=0.28, zr=0.45, up_f=10, dn_f=11, up_r=10, dn_r=12, arb_f=0.35, arb_r=0.10, camber=-3.0, cam_f=-0.5, cam_r=-0.5, toe_f=0.10, toe_r=0.05),
        tire=dict(mu_f=0.82, mu_r=0.80, slide=0.94, load=0.22, ratio=0.15, angle=11.0, rr=0.015, wet=0.9, bias=VINTAGE),
        steer=dict(max=38, ratio=20.0, rate=200, ack=0.55, curve="vintage"), handling=0.85,
        assists=dict(tcs=False, stm=False, abs=False, steer=0.5, tcs_str=0.3, stm_str=0.3),
        sound=dict(profile="inline4", cyl=4, pitch=0.9, harm="inline4_soft", noise=0.22, load=0.5, whine=False, blowoff=0.0, crackle=0.15, vol=0.9),
        paints=[("#0f5c3a", "#d8d4c8", 0, 0, 3, "#c9ccd2"), ("#c8202a", "#d8d4c8", 0, 0, 3, "#c9ccd2"), ("#d8d4c8", "#0f5c3a", 0, 0, 3, "#b9bcc2"), ("#1d3557", "#d8d4c8", 0, 0, 3, "#c9ccd2")],
        pi_target="D (about 300)",
    ),
]


# ------------------------------------------------------------------------------------------------------------------
# derivation
# ------------------------------------------------------------------------------------------------------------------
def load_json(exports_dir, vid, kind="Cars"):
    with open(os.path.join(exports_dir, kind, vid, vid + ".json"), encoding="utf8") as fh:
        return json.load(fh)


def ue_vec(v):
    return (v[0] * 100.0, -v[1] * 100.0, v[2] * 100.0)


def derive(c, js):
    """Returns the full numeric parameter dict for one car (UE units) from the spec `c` and the sidecar JSON `js`."""
    out = {}
    w = js["wheels"]
    r_f = 0.5 * (w["FL"]["radius"] + w["FR"]["radius"])
    r_r = 0.5 * (w["RL"]["radius"] + w["RR"]["radius"])
    m = float(c["mass"])
    wf = c["front_weight"]
    wheelbase_cm = js["wheelbase"] * 100.0

    # ---- engine --------------------------------------------------------------------------------------------------
    cv = c["curve"]
    pts = torque_curve(c["kw"], c["idle"], c["redline"], cv["xp"], cv["k"], cv["floor"])
    out["torque_curve"] = pts
    out["idle"], out["redline"], out["limiter"] = c["idle"], c["redline"], c["limiter"]

    # ---- gearbox -------------------------------------------------------------------------------------------------
    crr = c["tire"]["rr"]
    vmax = drag_limited_vmax_kmh(c["kw"], c["cda"], m, crr, c["eff"])
    r_drive = 0.5 * (r_f + r_r)
    vtop = vmax * c["overdrive"]
    ratios = gear_ratios(c["gears"], c["final"], c["redline"], r_drive, c["v1"], vtop)
    out["gears"] = ratios
    out["final"] = c["final"]
    out["reverse"] = ratios[0] * 0.95
    out["drag_vmax"] = vmax
    out["gear_top_kmh"] = vtop

    # ---- suspension ----------------------------------------------------------------------------------------------
    s = c["susp"]
    for axle, frac, hz in (("f", wf, s["hz_f"]), ("r", 1.0 - wf, s["hz_r"])):
        sprung = 0.88 * m * frac * 0.5
        k = sprung * (2.0 * math.pi * hz) ** 2
        crit = 2.0 * math.sqrt(k * sprung)
        out["k_" + axle] = k
        out["bump_" + axle] = crit * s["zb"]
        out["reb_" + axle] = crit * s["zr"]
        out["arb_" + axle] = k * s["arb_" + axle]
        out["stop_" + axle] = max(150000.0, 8.0 * k)
    # ---- tyres / brakes -------------------------------------------------------------------------------------------
    out["nominal_f"] = m * G * wf * 0.5
    out["nominal_r"] = m * G * (1.0 - wf) * 0.5
    out["handbrake"] = 1.35 * 1.0 * out["nominal_r"] * r_r
    # ---- centre of mass -------------------------------------------------------------------------------------------
    out["com"] = ((wf - 0.5) * wheelbase_cm, 0.0, c["com_z"])
    return out


# ------------------------------------------------------------------------------------------------------------------
# PI estimator (port of URoamCarDefinition::ComputePerformance, same constants)
# ------------------------------------------------------------------------------------------------------------------
def _torque_at(pts, limiter, rpm):
    if not pts or rpm <= 0.0 or rpm >= limiter:
        return 0.0
    if rpm <= pts[0][0]:
        return pts[0][1] * (rpm / pts[0][0])
    for i in range(1, len(pts)):
        if rpm <= pts[i][0]:
            x0, y0 = pts[i - 1]
            x1, y1 = pts[i]
            a = (rpm - x0) / (x1 - x0) if x1 > x0 else 1.0
            return y0 + (y1 - y0) * a
    return pts[-1][1]


def _norm(v, a, b):
    if abs(a - b) < 1e-9:
        return 0.0
    return min(1.0, max(0.0, (v - a) / (b - a)))


def estimate_pi(c, d, js):
    """(t60, t100, vmax, latG, brake100, offroad, PI, class) exactly like the C++ estimator."""
    w = js["wheels"]
    mass = max(float(c["mass"]), 100.0)
    tf, tr = c["tire"], c["tire"]
    mu = 0.5 * (tf["mu_f"] + tf["mu_r"])
    wheel_r = max(0.2, 0.5 * (w["FL"]["radius"] + w["RL"]["radius"]))
    crr = tf["rr"]
    cda = c["cda"]
    cla = c["cla_f"] + c["cla_r"]
    drive_frac = {"AWD": 0.95, "FWD": 0.55, "RWD": 0.58}[c["drivetrain"]]
    ratios = d["gears"]
    final = d["final"]
    pts = d["torque_curve"]
    peak_t_rpm = max(pts, key=lambda p: p[1])[0]
    launch = max(c["idle"], 0.65 * peak_t_rpm)
    wing = c.get("active_wing")

    dt = 0.005
    v = 0.0
    t = 0.0
    gear = 1
    shift_timer = 0.0
    t60 = t100 = -1.0
    v60, v100 = 60 / 3.6, 100 / 3.6
    n = len(ratios)
    for _ in range(18000):
        ratio = ratios[gear - 1] * final
        rpm = (v / wheel_r) * ratio * 60.0 / (2.0 * math.pi)
        if gear < n and rpm > c["up"] * c["redline"] and shift_timer <= 0.0:
            gear += 1
            shift_timer = c["shift"]
        thrust = 0.0
        if shift_timer > 0.0:
            shift_timer -= dt
        else:
            rpm_t = max(rpm, launch) if gear == 1 else rpm
            wf_ = _torque_at(pts, c["limiter"], rpm_t) * ratios[gear - 1] * final * c["eff"] / wheel_r
            active = cla + (wing["extra"] if wing and v * 3.6 > wing["kmh"] else 0.0)
            traction = mu * (mass * G * drive_frac + 0.5 * RHO * active * v * v)
            thrust = min(wf_, traction)
        res = 0.5 * RHO * cda * v * v + (crr * mass * G if v > 0.01 else 0.0)
        a = (thrust - res) / mass
        pv = v
        v = max(0.0, v + a * dt)
        t += dt
        if t60 < 0 and v >= v60:
            t60 = t - dt + dt * (v60 - pv) / max(v - pv, 1e-6)
        if t100 < 0 and v >= v100:
            t100 = t - dt + dt * (v100 - pv) / max(v - pv, 1e-6)
    t60 = t60 if t60 >= 0 else 90.0
    t100 = t100 if t100 >= 0 else 90.0
    vmax = v * 3.6
    df27 = 0.5 * RHO * cla * 27.8 ** 2
    lat = mu * c["handling"] * (mass * G + df27) / (mass * G)
    mu_brake = min(mu * 1.02, c["brake"]["g"]) * (1.0 + 0.5 * df27 / (mass * G))
    brake = (100 / 3.6) ** 2 / (2.0 * G * max(mu_brake, 0.1))
    travel = 0.25 * (c["susp"]["up_f"] + c["susp"]["dn_f"] + c["susp"]["up_r"] + c["susp"]["dn_r"])
    travel01 = min(1.0, max(0.0, travel * 2.0 / 25.0))
    bias = c["tire"]["bias"]
    loose = sum(SURFACE_BASE[s] * bias.get(s, 1.0) for s in ("Dirt", "Gravel", "Sand")) / 3.0
    loose_rating = min(1.0, max(0.0, (loose - 0.5) / 0.4))
    off = min(1.0, max(0.0, loose_rating * (0.6 + 0.4 * travel01) * (1.1 if c["drivetrain"] == "AWD" else 1.0)))
    score = (0.22 * _norm(vmax, 110, 360) + 0.26 * _norm(lat, 0.55, 1.70) + 0.22 * _norm(t100, 12.0, 2.3)
             + 0.07 * _norm(t60, 5.0, 1.4) + 0.13 * _norm(brake, 62.0, 26.0) + 0.10 * off)
    pi = int(round(100 + 899 * (min(1.0, max(0.0, score)) ** 0.72)))
    pi = min(999, max(100, pi))
    cls = "D" if pi <= 500 else "C" if pi <= 600 else "B" if pi <= 700 else "A" if pi <= 800 else "S1" if pi <= 900 else "S2" if pi <= 998 else "X"
    return dict(t60=t60, t100=t100, vmax=vmax, lat=lat, brake=brake, off=off, pi=pi, cls=cls)


# ------------------------------------------------------------------------------------------------------------------
# traffic vehicles (IDM numbers and masses; geometry from the JSON)
# ------------------------------------------------------------------------------------------------------------------
TRAFFIC = {
    "traffic01_compact": dict(mass=1050, vmax=120, accel=2.2, decel=3.2, headway=1.4, mingap=2.2, weight=3.0, roads=None),
    "traffic02_van": dict(mass=2200, vmax=110, accel=1.5, decel=2.8, headway=1.6, mingap=2.8, weight=1.4, roads=None),
    "traffic03_lorry": dict(mass=9500, vmax=90, accel=0.9, decel=2.5, headway=2.0, mingap=4.0, weight=0.7, roads=["Highway", "Regional", "Mountain"]),
    "traffic04_bus": dict(mass=14500, vmax=100, accel=0.9, decel=2.4, headway=2.0, mingap=4.0, weight=0.4, roads=["Highway", "Regional"]),
    "traffic05_tractor": dict(mass=4200, vmax=40, accel=0.7, decel=2.0, headway=2.2, mingap=3.5, weight=0.5, roads=["Dirt", "Village", "Regional"]),
    "traffic06_pickup": dict(mass=2000, vmax=115, accel=1.8, decel=3.0, headway=1.5, mingap=2.5, weight=1.6, roads=None),
}


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    exports = os.path.normpath(os.path.join(here, "..", "..", "Exports"))
    print("%-26s %5s %6s %6s %6s %5s %5s | %-6s %-6s %-5s %-5s %-6s %-5s | %s" % ("car", "kg", "kW", "dragV", "gearV", "g1", "gN", "t60", "t100", "vmax", "latG", "brake", "PI", "target"))
    for c in CARS:
        js = load_json(exports, c["id"])
        d = derive(c, js)
        e = estimate_pi(c, d, js)
        print("%-26s %5d %6d %6.0f %6.0f %5.2f %5.2f | %-6.2f %-6.2f %-5.0f %-5.2f %-6.1f %-3d %-2s | %s | k=%.0f/%.0f N/m ratios=%s" % (
            c["id"], c["mass"], c["kw"], d["drag_vmax"], d["gear_top_kmh"], d["gears"][0], d["gears"][-1],
            e["t60"], e["t100"], e["vmax"], e["lat"], e["brake"], e["pi"], e["cls"], c["pi_target"], d["k_f"], d["k_r"], ",".join("%.2f" % g for g in d["gears"])))
