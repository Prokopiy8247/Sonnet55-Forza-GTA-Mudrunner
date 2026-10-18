"""Test-sheet stations for the road / structure / building / roadside materials (registers itself into materials_testsheet.STATIONS on import).
Owner: agent M-B.

    road      7 road strips with the real chunk UV contract (regional, mountain, highway, dirt, concrete, gravel, worn) + weather shots
    bld       building blocks (plaster, brick, stone, concrete, wood, corrugated) with tile / slate gable roofs, window glass panels, day / wet / snow / night
    struct    kerb, bridge concrete / steel, tunnel wall / light, triplanar test sphere
    roadside  every MI_RS_* on a sphere grid (+ sign boards, billboard) day / night

Run:  ue_job.ps1 Tools/ue/materials_sheet.py -Args0 "road,bld"      (screenshots: Saved/MatShots/<shot>.png)
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_testsheet_surface.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
import materials_testsheet as TS  # noqa: E402
import importlib  # noqa: E402
import materials_testmesh_surface as _tms  # noqa: E402
importlib.reload(_tms)  # re-registers the extra test meshes after materials_testmesh was reloaded

INST = L.MAT_ROOT + "/Instances/"
ROADS = L.MAT_ROOT + "/Roads/"
TD = TS.TEST_DIR + "/"


def _have(path):
    if L.exists(path):
        return True
    L.warn("test sheet: missing %s" % path)
    return False


def _label(ctx, txt, loc, rot, size):
    """Floating text label (best effort: a failure only logs a warning)."""
    try:
        a = ctx.spawn(unreal.TextRenderActor, loc, rot)
        c = a.text_render
        try:
            c.set_editor_property("text", txt)
        except Exception:  # noqa: BLE001
            c.set_text(unreal.Text(txt))
        c.set_editor_property("world_size", size)
    except Exception as ex:  # noqa: BLE001
        L.warn("test sheet label '%s' failed: %s" % (txt, ex))


def station_road(ctx, which=None):
    strips = [
        ("SM_Test_RoadReg", "MI_Road_Asphalt", "asphalt (regional)", 0.0),
        ("SM_Test_RoadReg", "MI_Road_AsphaltMountain", "mountain solid centre", 1200.0),
        ("SM_Test_RoadHwy", "MI_Road_AsphaltNew", "highway", 2800.0),
        ("SM_Test_RoadDirt", "MI_Road_Dirt", "dirt", 4500.0),
        ("SM_Test_RoadReg", "MI_Road_Concrete", "concrete", 5600.0),
        ("SM_Test_RoadReg", "MI_Road_Gravel", "gravel", 6800.0),
        ("SM_Test_RoadReg", "MI_Road_AsphaltWorn", "asphalt worn", 8000.0),
        ("SM_Test_RoadPad", "MI_Road_Asphalt", "junction pad (no paint)", 9300.0),
    ]
    for mesh, mi, label, y in strips:
        if _have(ROADS + mi):
            ctx.mesh(TD + mesh, (0.0, y, 2.0), ROADS + mi, label=label)
    cy = 4000.0
    return [
        {"name": "road_overview", "cam": (-3200, cy, 2400), "look": (2000, cy, 0), "fov": 75},
        {"name": "road_reg_close", "cam": (-150, 0, 170), "look": (900, 0, 0), "fov": 62},
        {"name": "road_hwy_close", "cam": (-150, 2800 - 250, 190), "look": (1100, 2800 + 100, 0), "fov": 62},
        {"name": "road_dirt_close", "cam": (-150, 4500, 170), "look": (900, 4500, 0), "fov": 62},
        {"name": "road_gravel_concrete", "cam": (-150, 6200, 220), "look": (900, 6200, 0), "fov": 70},
        {"name": "road_wet_rain", "cam": (-150, 0, 170), "look": (900, 0, 0), "fov": 62, "mpc": {"Wetness": 1.0, "PuddleAmount": 0.7, "RainIntensity": 0.8}},
        {"name": "road_wet_wide", "cam": (-3200, cy, 2400), "look": (2000, cy, 0), "fov": 75, "mpc": {"Wetness": 1.0, "PuddleAmount": 0.6, "RainIntensity": 0.5}},
        {"name": "road_snow", "cam": (-3200, cy, 2400), "look": (2000, cy, 0), "fov": 75, "mpc": {"SnowAmount": 0.8}},
        {"name": "road_dust", "cam": (-3200, cy, 2400), "look": (2000, cy, 0), "fov": 75, "mpc": {"DustAmount": 0.9}},
    ]


def station_bld(ctx, which=None):
    walls = [("MI_Bld_Plaster", "MI_Bld_RoofTile"), ("MI_Bld_PlasterOchre", "MI_Bld_RoofTile"), ("MI_Bld_Brick", "MI_Bld_RoofSlate"),
             ("MI_Bld_Stone", "MI_Bld_RoofSlate"), ("MI_Bld_Concrete", None), ("MI_Bld_Wood", "MI_Bld_RoofSlate"), ("MI_Bld_WoodDark", None),
             ("MI_Bld_Corrugated", "MI_Bld_Corrugated"), ("MI_Bld_MetalPainted", None)]
    for i, (w, r) in enumerate(walls):
        y = -2900.0 + i * 720.0
        if _have(INST + w):
            ctx.mesh(TD + "SM_Test_Box", (0.0, y, 0.0), INST + w, label=w)
        if r and _have(INST + r):
            ctx.mesh(TD + "SM_Test_Roof", (0.0, y, 300.0), INST + r, label=r)
    # window glass in front of a concrete backing panel, facing -X side of the row
    for i, gm in enumerate(("MI_Bld_Glass", "MI_Bld_Glass_Shop")):
        y = -2000.0 + i * 700.0
        if _have(INST + "MI_Bld_Concrete") and _have(INST + gm):
            ctx.mesh(TD + "SM_Test_Wall", (-1300.0, y, 0.0), INST + "MI_Bld_Concrete", label="backing")
            ctx.mesh(TD + "SM_Test_Wall", (-1296.0, y, 0.0), INST + gm, label=gm)
    cy = -1200.0
    base = {"cam": (-1900, cy, 300), "look": (0, cy, 150), "fov": 78}
    return [
        dict(base, name="bld_day"),
        dict(base, name="bld_close_plaster_brick", cam=(-700, -2400, 250), look=(0, -2200, 180), fov=60),
        dict(base, name="bld_close_roof", cam=(-1000, -2500 + 3 * 720, 700), look=(0, -2500 + 3 * 720, 360), fov=60),
        dict(base, name="bld_windows_day", cam=(-1700, -1650, 220), look=(-1300, -1650, 200), fov=55),
        dict(base, name="bld_wet", mpc={"Wetness": 1.0}),
        dict(base, name="bld_snow", mpc={"SnowAmount": 0.9}),
        dict(base, name="bld_night", mpc={"TimeOfDay": 22.0}, sun=(35.0, 40.0), sun_lux=0.02),
        dict(base, name="bld_windows_night", cam=(-1700, -1650, 220), look=(-1300, -1650, 200), fov=55, mpc={"TimeOfDay": 22.0}, sun=(35.0, 40.0), sun_lux=0.02),
    ]


def station_struct(ctx, which=None):
    items = [("MI_Curb", "SM_Test_Wall"), ("MI_Bridge_Concrete", "SM_Test_Wall"), ("MI_Bridge_Steel", "SM_Test_Wall"), ("MI_Tunnel_Wall", "SM_Test_Wall"),
             ("MI_Tunnel_Light", "SM_Test_Wall"), ("MI_Road_Marking", "SM_Test_Wall")]
    for i, (mi, mesh) in enumerate(items):
        if _have(ROADS + mi):
            ctx.mesh(TD + mesh, (0.0, -1500.0 + i * 650.0, 0.0), ROADS + mi, rot=(0, 0, 180.0), label=mi)   # panel fronts face +X: turn them to the camera
    # curb strip beside a road strip
    if _have(ROADS + "MI_Curb"):
        ctx.mesh(TD + "SM_Test_Curb", (-1600.0, -1500.0, 0.0), ROADS + "MI_Curb", rot=(0, 0, 90.0), label="kerb")
    # triplanar test: Building instance with Triplanar on (created on the fly)
    try:
        parent = L.load(L.MAT_ROOT + "/M_Roam_Building")
        import materials_instances as MI
        tri = L.new_instance(L.MAT_ROOT + "/Test/MI_Test_Triplanar", parent, {"TileMetres": 2.0}, {}, MI.pbr("rock_grey"), {"Triplanar": True})
        L.save(tri)
        ctx.mesh("/Engine/BasicShapes/Sphere.Sphere", (0.0, 2800.0, 120.0), tri, scale=(2.4, 2.4, 2.4), label="triplanar sphere")
    except Exception as ex:  # noqa: BLE001
        L.warn("triplanar test instance failed: %s" % ex)
    cy = -150.0
    return [
        {"name": "struct_day", "cam": (-1100, cy, 260), "look": (0, cy + 150, 150), "fov": 78},
        {"name": "struct_wet", "cam": (-1100, cy, 260), "look": (0, cy + 150, 150), "fov": 78, "mpc": {"Wetness": 1.0}},
        {"name": "struct_tunnel_night", "cam": (-1100, cy, 260), "look": (0, cy + 150, 150), "fov": 78, "mpc": {"TimeOfDay": 22.0}, "sun": (35.0, 40.0), "sun_lux": 0.02},
        {"name": "struct_triplanar", "cam": (-700, 2800, 260), "look": (0, 2800, 150), "fov": 55},
    ]


RS_GROUPS = [
    ("paint", ["PaintWhite", "PaintRed", "PaintBlack", "PaintYellow", "PaintGrey"]),
    ("plastic/rubber", ["PlasticOrange", "PlasticWhite", "PlasticGrey", "Rubber", "TyreRubber", "TyrePaint"]),
    ("metal", ["GalvSteel", "GalvDark", "SignBack", "Grating", "Wire", "Insulator", "Rope"]),
    ("signs", ["SignWhite", "SignRed", "SignBlack", "SignBlue", "SignYellow", "SignGreen"]),
    ("reflector/lens", ["ReflectorRed", "ReflectorWhite", "ReflectorAmber", "LampLens"]),
    ("textured", ["Concrete", "ConcreteDark", "Wood", "WoodPale", "Stone", "Mortar", "Hay", "Soil", "Rust"]),
]


def station_roadside(ctx, which=None):
    for r, (grp, names) in enumerate(RS_GROUPS):
        for c, n in enumerate(names):
            mi = INST + "MI_RS_" + n
            if not _have(mi):
                continue
            x = r * 200.0
            y = -520.0 + c * 130.0
            ctx.mesh("/Engine/BasicShapes/Sphere.Sphere", (x, y, 60.0), mi, scale=(0.9, 0.9, 0.9), label=n)
            _label(ctx, n, (x - 70.0, y, 8.0), (0, 0, 180.0), 14.0)
            unreal.log("MAT_SHEET_LAYOUT roadside row=%d (%s) col=%d name=%s x=%.0f y=%.0f" % (r, grp, c, n, x, y))
    # billboard faces + a speed-limit style card
    for i, sfx in enumerate(("", "_B", "_C")):
        mi = INST + "MI_RS_BillboardFace" + sfx
        if _have(mi):
            ctx.mesh(TD + "SM_Test_Card", (r_x(len(RS_GROUPS)), -300.0 + i * 260.0, 0.0), mi, scale=(1.0, 2.2, 1.2), label="billboard" + sfx)
    cy = 120.0
    return [
        {"name": "roadside_day", "cam": (-420, cy, 330), "look": (400, cy, 40), "fov": 70},
        {"name": "roadside_close", "cam": (-120, -250, 140), "look": (200, -250, 50), "fov": 60},
        {"name": "roadside_wet", "cam": (-420, cy, 330), "look": (400, cy, 40), "fov": 70, "mpc": {"Wetness": 1.0}},
        {"name": "roadside_night", "cam": (-420, cy, 330), "look": (400, cy, 40), "fov": 70, "mpc": {"TimeOfDay": 22.0}, "sun": (35.0, 40.0), "sun_lux": 0.02},
    ]


def r_x(n):
    return n * 200.0 + 40.0


ORIGIN = {"road": (0.0, 0.0), "bld": (0.0, 14000.0), "struct": (0.0, 24000.0), "roadside": (0.0, 34000.0)}


def _with_origin(name, fn):
    """Shift every actor and camera of a station by ORIGIN[name] (stations share one map and must not overlap)."""
    def wrapped(ctx):
        ox, oy = ORIGIN[name]
        orig_spawn = ctx.spawn

        def spawn(cls, loc=(0, 0, 0), rot=(0, 0, 0)):
            return orig_spawn(cls, (loc[0] + ox, loc[1] + oy, loc[2]), rot)
        ctx.spawn = spawn
        try:
            shots = fn(ctx)
        finally:
            ctx.spawn = orig_spawn
        for sh in shots:
            sh["cam"] = (sh["cam"][0] + ox, sh["cam"][1] + oy, sh["cam"][2])
            sh["look"] = (sh["look"][0] + ox, sh["look"][1] + oy, sh["look"][2])
        return shots
    return wrapped


TS.register("road", _with_origin("road", station_road))
TS.register("bld", _with_origin("bld", station_bld))
TS.register("struct", _with_origin("struct", station_struct))
TS.register("roadside", _with_origin("roadside", station_roadside))
