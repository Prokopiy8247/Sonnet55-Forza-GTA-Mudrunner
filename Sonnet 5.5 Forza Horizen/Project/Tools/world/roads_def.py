"""Road classes, junction nodes and the route list (waypoints) of the world.

Waypoint entries are (X, Y) tuples in UE metres, or forced straight spans:
    ("bridge", (X1, Y1), (X2, Y2))    straight bridge between the two points
    ("tunnel", (X1, Y1), (X2, Y2))    straight tunnel between the two portals
start / end are node names (NODES) or ("ON", road_id, (hintX, hintY)) for a T-junction onto an existing road.
`shape` = (arc fraction, z) control points: the terrain is shaped around the waypoint line to carry a road that
profile (only used for roads where natural terrain would not give a drivable gradient).
`trace` = grade-line tracer settings (tracer.py): the mountain roads are walked uphill on the real terrain along a guide
line (valley axis / flank) with hairpins where the corridor edge is reached; `want` picks the best of several seeds.
"""
import numpy as np

CLASSES = {
    "HIGHWAY": dict(lanes=2, lane_w=3.6, shoulder=2.5, median=1.0, speed=120, surface="asphalt",
                    g_max=0.06, r_min=250.0, r_hair=250.0, r_pref=520.0, bank_max=0.06, bank_ref=900.0,
                    rdp_tol=14.0, smooth=22.0, vc_len=200.0, cw=260.0, turn=2.2, lc=1.0),
    "REGIONAL": dict(lanes=1, lane_w=3.4, shoulder=1.5, median=0.0, speed=80, surface="asphalt",
                     g_max=0.09, r_min=70.0, r_hair=70.0, r_pref=260.0, bank_max=0.05, bank_ref=420.0,
                     rdp_tol=12.0, smooth=8.0, vc_len=85.0, cw=210.0, turn=1.5, lc=1.0),
    "MOUNTAIN": dict(lanes=1, lane_w=3.2, shoulder=1.0, median=0.0, speed=60, surface="asphalt",
                     g_max=0.12, g_tunnel=0.105, r_min=40.0, r_hair=18.0, r_pref=120.0, bank_max=0.05, bank_ref=200.0,
                     rdp_tol=10.0, smooth=3.0, vc_len=60.0, cw=200.0, turn=8.0, lc=1.0),
    "DIRT": dict(lanes=1, lane_w=2.8, shoulder=0.6, median=0.0, speed=50, surface="gravel",
                 g_max=0.14, r_min=25.0, r_hair=25.0, r_pref=90.0, bank_max=0.03, bank_ref=120.0,
                 rdp_tol=6.0, smooth=3.0, vc_len=38.0, cw=170.0, turn=0.9, lc=1.0),
    "SHORTCUT": dict(lanes=1, lane_w=2.4, shoulder=0.4, median=0.0, speed=40, surface="dirt",
                     g_max=0.16, r_min=25.0, r_hair=25.0, r_pref=80.0, bank_max=0.03, bank_ref=100.0,
                     rdp_tol=6.0, smooth=3.0, vc_len=36.0, cw=150.0, turn=0.8, lc=1.0),
    "VILLAGE": dict(lanes=1, lane_w=2.9, shoulder=1.0, median=0.0, speed=30, surface="asphalt",
                    g_max=0.10, r_min=20.0, r_hair=20.0, r_pref=45.0, bank_max=0.0, bank_ref=100.0,
                    rdp_tol=4.0, smooth=2.0, vc_len=28.0, cw=90.0, turn=0.6, lc=1.0),
}


def paved_width(cls):
    c = CLASSES[cls]
    return 2 * c["lanes"] * c["lane_w"] + c["median"]


def bed_half_width(cls):
    """half width of the carved road bed (paved + shoulders)."""
    c = CLASSES[cls]
    return paved_width(cls) / 2.0 + c["shoulder"]


def wiggle(wp, spacing, amp, first_sign=1.0, keep_ends=True, limit=1840.0):
    """densify a waypoint polyline every `spacing` m and push the new points alternately left / right by `amp` m
    (gentle S-bends that lengthen a road without changing its corridor)."""
    pts = np.array(wp, dtype=float)
    seg = np.sqrt((np.diff(pts, axis=0) ** 2).sum(1))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(2, int(cum[-1] / spacing))
    t = np.linspace(0, cum[-1], n + 1)
    x = np.interp(t, cum, pts[:, 0])
    y = np.interp(t, cum, pts[:, 1])
    d = np.gradient(np.stack([x, y], 1), t, axis=0)
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    out = []
    sg = first_sign
    for i in range(len(t)):
        p = np.array([x[i], y[i]])
        if 0 < i < len(t) - 1:
            p = np.clip(p + sg * amp * nrm[i], -limit, limit)
            sg = -sg
        out.append((float(p[0]), float(p[1])))
    return out


def river_gate(y0, half=44.0, northbound=True):
    """straight bridge span across the Silverrun at Y = y0, perpendicular to the (straightened) river reach.
    Returns ("bridge", a, b) with a on the bank the road comes from."""
    import worlddef as W
    P = W.make_river()["pts"]
    k = int(np.argmin(np.abs(P[:, 1] - y0)))
    t = P[min(k + 3, len(P) - 1)] - P[max(k - 3, 0)]
    t = t / np.hypot(*t)
    n = np.array([-t[1], t[0]])
    if n[0] > 0:
        n = -n                         # n points south (towards -X)
    c = P[k]
    south = c + half * n
    north = c - half * n
    if northbound:
        return ("bridge", (float(south[0]), float(south[1])), (float(north[0]), float(north[1])))
    return ("bridge", (float(north[0]), float(north[1])), (float(south[0]), float(south[1])))


def coast_wiggle(ys, offsets, side=1.0):
    """waypoints that follow the south coast (worlddef.coast_Xs) at alternating inland offsets (m): gentle S-bends of a coast road"""
    import worlddef as W
    out = []
    for k, y in enumerate(ys):
        out.append((float(W.coast_Xs(float(y))) + side * offsets[k % len(offsets)], float(y)))
    return out


NODES = {
    "CROSS": (0.0, 0.0),
    "J_BAY_S": (-650.0, 1300.0),
    "TIDE": (-1150.0, 1385.0),
    "MILL": (-900.0, -900.0),
    "PFOOT": (-80.0, -1580.0),
    "SUMMIT": (1230.0, -1175.0),
    "LH": (-1700.0, 1830.0),
    "FROST": (900.0, -1015.0),
    "MILL_E": (-880.0, -690.0),
    "MILL_W": (-780.0, -1120.0),
    "FARM_A": (-1090.0, -1400.0),
    "FARM_B": (-1340.0, 190.0),
    "FARM_C": (-1470.0, -1290.0),
    "FARM_D": (-700.0, -480.0),
    "GAS_X": (-70.0, 230.0),
    "DINER_X": (30.0, 330.0),
    "GAS_P": (790.0, 1085.0),
    "GAS_H": (-710.0, 1420.0),
    "WASH_END": (1010.0, 1330.0),
    "WIND_END": (1450.0, 1250.0),
    "BEACH_END": (-1530.0, 860.0),
    "PIER": (-1200.0, 1520.0),
    "TIDE_N": (-1260.0, 1270.0),
    "LODGE": (900.0, -900.0),
    "ORCHARD": (-300.0, -600.0),
    "BASIN_FARM": (-1230.0, 430.0),
    "DUST_END": (380.0, 1420.0),
}

_hwy_shape = [(0.0, 112.0), (0.12, 138.0), (0.25, 170.0), (0.37, 204.0), (0.47, 214.0), (0.55, 208.0), (0.64, 188.0),
              (0.74, 150.0), (0.85, 100.0), (0.93, 64.0), (1.0, 50.0)]

ROADS = [
    dict(id="HWY_EAST", name="Spine Highway", cls="HIGHWAY", start="CROSS", end="J_BAY_S",
         wp=[(0, 0), (210, 70), (520, 170), (880, 230), (1230, 290), (1560, 420), (1830, 680), (1925, 1020), (1890, 1360), (1770, 1660),
             (1480, 1820), (1100, 1860), (700, 1850), (360, 1770), (110, 1630), (-20, 1440), (-80, 1330),
             ("bridge", (-170, 1300), (-530, 1300)), (-650, 1300)],
         shape=_hwy_shape, auto_z=(0.055, 380.0, 112.0, 50.0), corridor=75.0,
         shape_params=dict(flat=95.0, blend=190.0, strength=1.0, cross=0.0, terrace=3, noise=3.0)),
    dict(id="LOOP_COAST", name="Harbour Road", cls="REGIONAL", start="J_BAY_S", end="TIDE",
         wp=[(-650, 1300), (-760, 1060), (-960, 1000), (-1150, 1120), (-1130, 1260), (-1090, 1340), (-1150, 1385)],
         shape=[(0.0, 50.0), (0.30, 44.0), (0.65, 25.0), (1.0, 4.0)], auto_z=(0.08, 140.0, 50.0, 4.0),
         shape_params=dict(flat=40.0, blend=180.0, strength=0.9, cross=0.03)),
    dict(id="LOOP_SOUTH", name="Southern Coast Road", cls="REGIONAL", start="TIDE", end="MILL",
         wp=[(-1150, 1385), (-1250, 1235)]
            + coast_wiggle([1070, 900, 730, 560, 390, 220, 50, -120, -290, -430], [260.0, 440.0, 260.0, 430.0, 270.0, 450.0, 270.0, 430.0, 280.0, 440.0])
            + [(-1380, -560), (-1250, -660), (-1090, -780), (-960, -860), (-900, -900)]),
    dict(id="LOOP_VALLEY", name="Silverrun Valley Road", cls="REGIONAL", start="MILL", end="PFOOT",
         wp=[(-900, -900), (-1100, -1050), (-1350, -1350), (-1250, -1650), (-1000, -1800), (-800, -1700), river_gate(-1700, 44.0, True),
             (-330, -1640), (-200, -1600), (-80, -1580)]),
    dict(id="CASTLE_ROAD", name="Castle Road", cls="REGIONAL", start="MILL_E", end=("ON", "LOOP_VALLEY", (-250, -1350)),
         wp=[(-880, -690), (-700, -760), (-560, -800), river_gate(-830, 44.0, True), (-330, -880), (-260, -1000), (-200, -1130), (-230, -1250), (-250, -1350)]),
    dict(id="LOOP_PASS", name="Highcrest Pass (ascent)", cls="MOUNTAIN", start="PFOOT", end="SUMMIT",
         wp=[(-80, -1580), (1230, -1175)],
         trace=dict(guide=[(-80.0, -1580.0), (150.0, -1600.0), (400.0, -1620.0), (650.0, -1590.0), (900.0, -1500.0), (1080.0, -1360.0), (1230.0, -1175.0)],
                    half_width=[(0.0, 230.0), (0.8, 230.0), (1.0, 90.0)], g_lo=0.045, g_hi=0.07, min_leg=200.0, min_advance=30.0, seeds=list(range(1, 17)),
                    want=dict(hairpins=(9, 12), length=(5800, 6900)))),
    dict(id="LOOP_DESC", name="Highcrest Pass (descent)", cls="MOUNTAIN", start="SUMMIT", end="CROSS",
         wp=[(1230, -1175), (0, 0)],
         trace=dict(reverse=True, valley=dict(src=(1296.0, -1104.0), z_stop=122.0, sigma=140.0),
                    half_width=[(0.0, 150.0), (0.35, 230.0), (0.75, 270.0), (1.0, 150.0)], g_lo=0.05, g_hi=0.088, min_leg=240.0, min_advance=12.0,
                    seeds=list(range(1, 17)), want=dict(hairpins=(4, 9), length=(5000, 7000)),
                    tunnel=dict(zone=(0.1, 0.95), len=(160.0, 380.0), cover=1.0, cover_peak=3.0, grade=0.095, save_min=1.06, angle=34.0, ridge_h=30.0),
                    # design choice among the seeds: the tunnel is required (the Highcrest pass needs one), a design that runs beside another road
                    # (crossings) is rejected, overlapping legs matter less (the carve keeps a wider flat bed)
                    tunnel_miss=2000.0, cross_w=500.0, hard_w=8.0)),
    dict(id="PASS_SPUR", name="Frostholm Road", cls="MOUNTAIN", start=("ON", "CASTLE_ROAD", (-190.0, -1130.0)), end="FROST",
         wp=[(-190, -1130), (900, -1015)],
         trace=dict(guide=[(-190.0, -1130.0), (50.0, -1100.0), (300.0, -1060.0), (520.0, -1050.0), (700.0, -1030.0), (820.0, -1020.0), (905.0, -1015.0)],
                    half_width=[(0.0, 90.0), (0.3, 150.0), (0.6, 270.0), (1.0, 280.0)], g_lo=0.04, g_hi=0.06, min_leg=240.0, min_advance=30.0,
                    pref_leg=(380.0, 760.0), seeds=list(range(1, 17)), want=dict(hairpins=(5, 9), length=(4800, 7000)))),
    dict(id="COAST_SPUR", name="Cliff Road", cls="REGIONAL", start="TIDE", end="LH",
         wp=[(-1150, 1385), (-1040, 1450), (-960, 1580), (-870, 1620), (-790, 1740), (-860, 1860), (-1010, 1900), (-1140, 1860), (-1210, 1760),
             (-1330, 1840), (-1450, 1760), (-1560, 1860), (-1700, 1830)], coast_margin=60.0),
    # ---------------------------------------------------------------- regional links
    dict(id="BASIN_ROAD", name="Basin Road", cls="REGIONAL", start="CROSS", end=("ON", "LOOP_COAST", (-960, 1005)),
         wp=[(0, 0), (-200, 150), (-360, 320), river_gate(460, 44.0, False), (-700, 560), (-840, 760), (-900, 900), (-960, 1005)]),
    dict(id="RIVER_ROAD", name="Silverrun River Road", cls="REGIONAL", start=("ON", "BASIN_ROAD", (-840, 760)), end=("ON", "LOOP_COAST", (-770, 1100)),
         wp=[(-840, 760), (-800, 900), (-780, 1000), (-770, 1100)]),
    # ---------------------------------------------------------------- dirt / shortcut
    dict(id="DIRT_WASH", name="Redrock Wash", cls="DIRT", start="CROSS", end="WASH_END",
         wp=[(0, 0), (30, 300), (150, 600), (300, 820), (450, 940), (560, 1000), (700, 1060), (800, 950), (960, 1020), (1090, 1170), (1010, 1330)], corridor=150.0),
    dict(id="DIRT_LOG", name="Old Logging Track", cls="DIRT", start=("ON", "LOOP_VALLEY", (-860, -1060)), end=("ON", "LOOP_SOUTH", (-1575, -270)),
         wp=[(-860, -1060), (-1100, -1250), (-1400, -1250), (-1620, -1000), (-1700, -700), (-1650, -450), (-1575, -270)], corridor=170.0),
    dict(id="DIRT_FARM", name="Hollow Farm Track", cls="DIRT", start="MILL", end=("ON", "LOOP_SOUTH", (-1340, -520)),
         wp=[(-900, -900), (-1000, -820), (-1000, -640), (-1100, -520), (-1250, -500), (-1340, -520)], corridor=150.0),
    dict(id="DIRT_CLIFF", name="Cliff-top Track", cls="DIRT", start=("ON", "COAST_SPUR", (-960, 1580)), end=("ON", "LOOP_COAST", (-1130, 1230)),
         wp=[(-960, 1580), (-1010, 1480), (-1080, 1380), (-1120, 1300), (-1130, 1230)], corridor=120.0),
    dict(id="DIRT_WIND", name="Windfarm Track", cls="DIRT", start="WASH_END", end="WIND_END",
         wp=[(1010, 1330), (1180, 1340), (1330, 1300), (1450, 1250)], corridor=140.0),
    dict(id="DIRT_BEACH", name="Sunset Beach Track", cls="DIRT", start=("ON", "LOOP_SOUTH", (-1440, 790)), end="BEACH_END",
         wp=[(-1440, 790), (-1500, 830), (-1530, 860)], corridor=120.0),
    dict(id="DIRT_DUST", name="Dustbowl Loop", cls="DIRT", start=("ON", "DIRT_WASH", (450, 940)), end="DUST_END",
         wp=[(450, 940), (440, 1100), (420, 1260), (380, 1420)], corridor=170.0),
    dict(id="BASIN_LANE", name="Basin Lane", cls="REGIONAL", start=("ON", "BASIN_ROAD", (-700, 560)), end="BASIN_FARM",
         wp=[(-700, 560), (-900, 520), (-1080, 440), (-1230, 430)], corridor=120.0),
    dict(id="ORCHARD_ROAD", name="Orchard Road", cls="REGIONAL", start=("ON", "BASIN_ROAD", (-216, 66)), end="FARM_D",
         wp=[(-216, 66), (-270, -150), (-330, -400), river_gate(-560, 44.0, False), (-690, -520), (-700, -480)], corridor=110.0),
    # ---------------------------------------------------------------- local: villages, farms, stations
    dict(id="LOCAL_MILL_MAIN", name="Millbrook Main Street", cls="VILLAGE", start="MILL", end="MILL_E",
         wp=[(-900, -900), (-890, -790), (-880, -690)]),
    dict(id="LOCAL_MILL_WEST", name="Millbrook Church Lane", cls="VILLAGE", start="MILL", end="MILL_W",
         wp=[(-900, -900), (-840, -1010), (-780, -1120)], corridor=90.0),
    dict(id="LOCAL_MILL_RING", name="Millbrook Green Road", cls="VILLAGE", start=("ON", "LOCAL_MILL_MAIN", (-900, -845)), end=("ON", "LOCAL_MILL_WEST", (-830, -1030)),
         wp=[(-900, -845), (-815, -865), (-745, -905), (-770, -1000), (-830, -1030)], corridor=80.0),
    dict(id="LOCAL_FARM_A", name="Hawthorn Farm Road", cls="REGIONAL", start=("ON", "DIRT_LOG", (-1150, -1300)), end="FARM_A",
         wp=wiggle([(-1150, -1300), (-1120, -1350), (-1090, -1400)], 80.0, 20.0), corridor=90.0),
    dict(id="LOCAL_FARM_B", name="Ashby Farm Road", cls="REGIONAL", start=("ON", "LOOP_SOUTH", (-1500, 90)), end="FARM_B",
         wp=[(-1500, 90), (-1440, 105), (-1390, 160), (-1340, 190)], corridor=90.0),
    dict(id="LOCAL_FARM_C", name="Greywell Farm Road", cls="REGIONAL", start=("ON", "DIRT_LOG", (-1590, -1230)), end="FARM_C",
         wp=[(-1590, -1230), (-1530, -1260), (-1470, -1290)], corridor=90.0),
    dict(id="LOCAL_GAS_X", name="Crossroads Gas Link", cls="REGIONAL", start=("ON", "BASIN_ROAD", (-110, 60)), end="GAS_X",
         wp=[(-110, 60), (-95, 140), (-70, 230)], corridor=80.0),
    dict(id="LOCAL_DINER", name="Diner Lane", cls="VILLAGE", start=("ON", "LOCAL_GAS_X", (-85, 185)), end="DINER_X",
         wp=[(-85, 185), (-30, 270), (30, 330)], corridor=60.0),
    dict(id="LOCAL_PGAS", name="Plateau Gas Road", cls="REGIONAL", start=("ON", "DIRT_WASH", (700, 1060)), end="GAS_P",
         wp=[(705, 1060), (750, 1070), (790, 1085)], corridor=60.0),
    dict(id="LOCAL_HGAS", name="Harbour Gas Road", cls="REGIONAL", start="J_BAY_S", end="GAS_H",
         wp=[(-650, 1300), (-690, 1360), (-710, 1420)], corridor=60.0),
    dict(id="LOCAL_TIDE_QUAY", name="Tidewick Quay", cls="VILLAGE", start="TIDE", end="PIER",
         wp=[(-1150, 1385), (-1140, 1450), (-1200, 1520)], corridor=70.0),
    dict(id="LOCAL_TIDE_HIGH", name="Tidewick High Street", cls="VILLAGE", start="TIDE", end="TIDE_N",
         wp=[(-1150, 1385), (-1220, 1340), (-1260, 1270)], corridor=70.0),
    dict(id="LOCAL_FROST", name="Frostholm Lodge Road", cls="VILLAGE", start="FROST", end="LODGE",
         wp=[(900, -1015), (900, -960), (900, -900)], corridor=70.0),
]

def _shape_fracs(r):
    """convert shape entries [(frac, z) | ("wp", idx, z)] to [(frac, z)] (fractions along the waypoint polyline)."""
    out = []
    pts = [np.array(w[1] if isinstance(w[0], str) else w, float) for w in r["wp0"]]
    seg = np.sqrt((np.diff(np.array(pts), axis=0) ** 2).sum(1))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    for e in r["shape"]:
        if isinstance(e[0], str):
            out.append((cum[e[1]] / cum[-1], e[2]))
        else:
            out.append(e)
    return out


def _width_fracs(r):
    wc = r.get("shape_params", {}).get("width")
    if not wc:
        return None
    pts = [np.array(w[1] if isinstance(w[0], str) else w, float) for w in r["wp0"]]
    seg = np.sqrt((np.diff(np.array(pts), axis=0) ** 2).sum(1))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    out = []
    for e in wc:
        if isinstance(e[0], str):
            out.append((cum[e[1]] / cum[-1], e[2], e[3]))
        else:
            out.append(e)
    return out


def shape_polyline(r, sigma=140.0):
    """smoothed guide polyline used for terrain shaping (plain waypoints + forced link midpoints)."""
    pts = []
    for w in r["wp"]:
        if isinstance(w[0], str):
            pts.append((np.array(w[1], float) + np.array(w[2], float)) * 0.5)
        else:
            pts.append(np.array(w, dtype=float))
    pts = np.array(pts)
    seg = np.sqrt((np.diff(pts, axis=0) ** 2).sum(1))
    s = np.concatenate([[0.0], np.cumsum(seg)])
    ds = 20.0
    n = max(3, int(s[-1] / ds) + 1)
    t = np.linspace(0, s[-1], n)
    x = np.interp(t, s, pts[:, 0])
    y = np.interp(t, s, pts[:, 1])
    if sigma > 0 and n > 8:
        sg = sigma / (t[1] - t[0])
        k = int(3 * sg)
        k = min(k, n - 2)
        ker = np.exp(-0.5 * (np.arange(-k, k + 1) / sg) ** 2)
        ker /= ker.sum()
        out = []
        for v in (x, y):
            ext = np.concatenate([2 * v[0] - v[1:k + 1][::-1], v, 2 * v[-1] - v[-k - 1:-1][::-1]])
            out.append(np.convolve(ext, ker, mode="valid"))
        x, y = out
    return np.stack([x, y], 1)


# additional terrain-shaping corridors that are not tied to a single road (smooth graded approaches)
EXTRA_CORRIDORS = [
    dict(name="DESC foot", pts=[(330.0, -230.0), (240.0, -150.0), (140.0, -80.0), (60.0, -30.0), (0.0, 0.0)],
         z=[(0.0, 190.0), (1.0, 112.0)], flat=22.0, blend=90.0, strength=1.0, cross=0.0, noise=1.2),
]


def trace_corridors(calm_width_scale=1.0):
    """corridors (guide polylines) of the traced mountain roads: the massif noise relief is calmed along them so the
    hillside carries long, clean legs while the rest of the massif stays rugged."""
    out = []
    for r in ROADS:
        t = r.get("trace")
        if not t or "guide" not in t:
            continue
        hw = t["half_width"]
        wmax = float(np.max(np.asarray(hw)[:, 1])) if not np.isscalar(hw) else float(hw)
        out.append(dict(pts=np.array(t["guide"], dtype=float), z=None, flat=0.9 * wmax * calm_width_scale, blend=200.0))
    return out


def corridors():
    """terrain shaping corridors derived from the road list."""
    out = []
    for e in EXTRA_CORRIDORS:
        out.append(dict(pts=np.array(e["pts"], dtype=float), z=e["z"], flat=e["flat"], blend=e["blend"],
                        strength=e["strength"], cross=e["cross"], noise=e["noise"]))
    for r in ROADS:
        if "shape" in r:
            sp = r.get("shape_params", {})
            pts = r["guide"] if "guide" in r else shape_polyline(r, sp.get("smooth", 140.0))
            out.append(dict(pts=pts, z=r["shape"], flat=sp.get("flat", 60.0), blend=sp.get("blend", 330.0),
                            strength=sp.get("strength", 0.9), cross=sp.get("cross", 0.04), noise=sp.get("noise", 2.5),
                            width=_width_fracs(r), terrace=sp.get("terrace"), auto_z=r.get("auto_z")))
        elif "trace" in r:
            continue
        else:
            cw = r.get("corridor", CLASSES[r["cls"]]["cw"])
            pts = shape_polyline(r, 40.0)
            out.append(dict(pts=pts, z=None, flat=0.6 * cw, blend=0.9 * cw))
    return out


for _r in ROADS:
    _r.setdefault("wp0", list(_r["wp"]))
for _r in ROADS:
    pts = []
    for w in _r["wp"]:
        if isinstance(w[0], str):
            if w[0] == "via":
                pts.append(w[1])
            else:
                pts.append(w[1])
                pts.append(w[2])
        else:
            pts.append(w)
    _r["pts_preview"] = pts
