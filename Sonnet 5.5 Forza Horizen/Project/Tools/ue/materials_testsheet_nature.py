"""Test-sheet stations for the nature + fx materials (registers itself into materials_testsheet.STATIONS on import).

    stations: trees (trunks + foliage cards), ground (grass, flowers, rocks), water (sea + river over a sand bed), fx (particles, skid)
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_testsheet_nature.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
import materials_testsheet as TS  # noqa: E402

INST = L.MAT_ROOT + "/Instances/"


def _row(ctx, mesh, items, x, y0, dy, z=0.0, scale=(1, 1, 1), rot=(0, 0, 0)):
    out = []
    for i, (mi, label) in enumerate(items):
        path = INST + mi
        if not L.exists(path):
            L.warn("missing %s, skipped" % mi)
            continue
        ctx.mesh(mesh, (x, y0 + i * dy, z), path, rot=rot, scale=scale, label=label)
        out.append(label)
    return out


def station_trees(ctx):
    """Leaf cards in a row along Y at x = 0 (four crossed cards, +-225 cm in X, 140 cm tall), trunks (30 cm radius, 4 m) at x = 1200."""
    leaves = [("MI_Tree_Leaf", "leaf"), ("MI_Tree_LeafLight", "leaf light"), ("MI_Tree_LeafDry", "leaf dry"), ("MI_Tree_Needle", "needle"),
              ("MI_Tree_Palm", "palm")]
    _row(ctx, TS.TEST_DIR + "/SM_Test_FoliageCards", leaves, 0.0, -1000.0, 400.0)
    trunks = [("MI_Tree_Bark", "bark"), ("MI_Tree_Bark_Birch", "birch"), ("MI_Tree_Bark_Dark", "bark dark"), ("MI_Tree_Dead", "dead")]
    _row(ctx, TS.TEST_DIR + "/SM_Test_Trunk", trunks, 1200.0, -300.0, 130.0)
    row = {"cam": (-1100, -600, 140), "look": (0, -600, 100), "fov": 70}
    trk = {"cam": (400, -105, 230), "look": (1200, -105, 200), "fov": 70}
    return [
        dict(row, name="trees_leaves_row"),
        dict(row, name="trees_leaves_wet", mpc={"Wetness": 1.0}),
        dict(row, name="trees_leaves_snow", mpc={"SnowAmount": 0.9}),
        dict(row, name="trees_leaves_autumn", mpc={"FoliageSeason": 1.0, "SeasonTint": (1.6, 0.9, 0.35, 1)}),
        {"name": "trees_leaf_close", "cam": (0, -1450, 120), "look": (0, -1000, 100), "fov": 60},
        {"name": "trees_needle_close", "cam": (0, -250, 120), "look": (0, 200, 100), "fov": 60},
        {"name": "trees_palm_close", "cam": (0, 150, 120), "look": (0, 600, 100), "fov": 60},
        dict(trk, name="trees_trunks"),
        dict(trk, name="trees_trunks_wet", mpc={"Wetness": 1.0}),
        dict(trk, name="trees_trunks_snow", mpc={"SnowAmount": 0.9}),
        {"name": "trees_bark_close", "cam": (950, -300, 170), "look": (1200, -300, 170), "fov": 45},
    ]


def station_ground(ctx):
    grass = [("MI_GrassCards_Green", "grass"), ("MI_GrassCards_Dry", "grass dry"), ("MI_Flower_Mixed", "flowers"), ("MI_Flower_Daisy", "daisy"),
             ("MI_Flower_Poppy", "poppy"), ("MI_Flower_Lavender", "lavender")]
    mesh = TS.TEST_DIR + "/SM_Test_Card"
    # several instances per material so per-instance random cells show up
    for i, (mi, label) in enumerate(grass):
        for k in range(3):
            if L.exists(INST + mi):
                ctx.mesh(mesh, (0.0 + k * 60.0, -700.0 + i * 220.0 + k * 40.0, 0.0), INST + mi, rot=(0, 0, 20.0 * k), scale=(1, 1, 0.5), label=label)
    rocks = [("MI_Rock", "rock"), ("MI_Rock_Mossy", "rock mossy"), ("MI_Rock_Cliff", "cliff"), ("MI_Rock_RedClay", "clay")]
    for i, (mi, label) in enumerate(rocks):
        if L.exists(INST + mi):
            ctx.mesh("/Engine/BasicShapes/Sphere.Sphere", (700.0, -700.0 + i * 300.0, 90.0), INST + mi, rot=(0, 0, 25.0 * i), scale=(2.4, 1.6, 1.8),
                     label=label)
    cy = -150.0
    return [
        {"name": "ground_dry", "cam": (-700, cy - 100, 170), "look": (300, cy, 40), "fov": 70},
        {"name": "ground_wet", "cam": (-700, cy - 100, 170), "look": (300, cy, 40), "fov": 70, "mpc": {"Wetness": 1.0}},
        {"name": "ground_snow", "cam": (-700, cy - 100, 170), "look": (300, cy, 40), "fov": 70, "mpc": {"SnowAmount": 0.9}},
        {"name": "ground_rocks", "cam": (100, -700, 250), "look": (700, 100, 90), "fov": 60},
    ]


ORIGIN = {"trees": (0.0, 0.0), "ground": (0.0, 9000.0), "treemesh": (0.0, 18000.0)}


def _with_origin(name, fn):
    """Run a station with every actor / camera shifted by ORIGIN[name] (stations share one map and must not overlap)."""
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


TS.register("trees", _with_origin("trees", station_trees))
TS.register("ground", _with_origin("ground", station_ground))


# ------------------------------------------------------------------------------------------------------------------------------
# real tree meshes (Exports/Nature/Trees/<id>.fbx) imported once into /Game/Forza/Materials/Test and dressed with the slot-name instances
# ------------------------------------------------------------------------------------------------------------------------------
TREE_IDS = ["tree_oak_a", "tree_pine_a", "tree_birch_a", "tree_palm_a", "tree_olive_a", "tree_dead_a"]


def _ensure_tree(tid):
    path = TS.TEST_DIR + "/SM_" + tid
    if L.exists(path):
        return path
    fbx = L.ROOT + "Exports/Nature/Trees/%s.fbx" % tid
    t = unreal.AssetImportTask()
    t.set_editor_property("filename", fbx)
    t.set_editor_property("destination_path", TS.TEST_DIR)
    t.set_editor_property("destination_name", "SM_" + tid)
    t.set_editor_property("automated", True)
    t.set_editor_property("replace_existing", True)
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
    L.at.import_asset_tasks([t])
    return path


def station_treemesh(ctx):
    import json
    slot_map = {}
    try:
        with open(_HERE + "/materials_slot_map.json", "r", encoding="utf-8") as fh:
            slot_map = json.load(fh)
    except OSError:
        pass
    x = 0.0
    for tid in TREE_IDS:
        path = _ensure_tree(tid)
        sm = L.ea.load_asset(path)
        if sm is None:
            L.warn("tree %s not imported" % tid)
            continue
        mats = []
        for i, sl in enumerate(sm.get_editor_property("static_materials")):
            slot = str(sl.get_editor_property("material_slot_name"))
            mi = slot_map.get(slot)
            mats.append(mi if mi and L.exists(mi) else None)
        for i, mi in enumerate(mats):
            if mi:
                sm.set_material(i, L.ea.load_asset(mi))
        L.log("tree %s slots=%s" % (tid, [str(s.get_editor_property("material_slot_name")) for s in sm.get_editor_property("static_materials")]))
        a = ctx.spawn(unreal.StaticMeshActor, (0.0, x, 0.0))
        a.static_mesh_component.set_static_mesh(sm)
        a.set_actor_label(tid)
        x += 1500.0
    cy = (x - 1500.0) * 0.5
    return [
        {"name": "treemesh_all", "cam": (-4200, cy, 700), "look": (0, cy, 600), "fov": 70},
        {"name": "treemesh_wet", "cam": (-4200, cy, 700), "look": (0, cy, 600), "fov": 70, "mpc": {"Wetness": 1.0}},
        {"name": "treemesh_snow", "cam": (-4200, cy, 700), "look": (0, cy, 600), "fov": 70, "mpc": {"SnowAmount": 0.9}},
        {"name": "treemesh_close_oak", "cam": (-1100, -300, 500), "look": (0, 0, 650), "fov": 60},
        # wind check: identical view, still air vs. gale (compare the two images: crown / leaves must move, the trunk base must not)
        {"name": "treemesh_wind0", "cam": (-1100, -300, 500), "look": (0, 0, 650), "fov": 60, "mpc": {"WindStrength": 0.0}},
        {"name": "treemesh_wind1", "cam": (-1100, -300, 500), "look": (0, 0, 650), "fov": 60, "mpc": {"WindStrength": 1.0, "WindSpeed": 18.0}},
        {"name": "treemesh_close_pine", "cam": (-900, 1500 - 500, 400), "look": (0, 1500, 450), "fov": 60},
    ]


TS.register("treemesh", _with_origin("treemesh", station_treemesh))


def station_evcal(ctx):
    """Exposure calibration with the PHYSICAL sun (110000 lux): the same views at pinned EV100 values (eye adaptation min/max)."""
    shots = station_trees(ctx)
    base = [s for s in shots if s["name"] in ("trees_leaves_row", "trees_trunks")]
    out = []
    for ev in (13.0, 15.0, 17.0):
        for b in base:
            d = dict(b)
            d["name"] = "evcal_%s_ev%s" % (b["name"].split("_")[1], str(ev).replace(".", "p"))
            d["sun_lux"] = 110000.0
            d["ev"] = ev
            out.append(d)
    return out


TS.register("evcal", _with_origin("trees", station_evcal))


# ------------------------------------------------------------------------------------------------------------------------------
# ground-cover kit meshes (Exports/Nature/Cover/<id>.fbx): bushes, cacti, grass, flowers, reeds, crops, hay, logs, rocks, beach props
# ------------------------------------------------------------------------------------------------------------------------------
COVER_IDS = ["nat_bush_leafy_a", "nat_shrub_evergreen_a", "nat_cactus_saguaro_a", "nat_grass_lush", "nat_flowers_a", "nat_reeds_a", "nat_crop_wheat_row",
             "nat_hay_round", "nat_log_fallen", "nat_rock_mesa_a", "nat_beach_umbrella", "nat_rock_jagged_a"]


def _ensure_cover(cid):
    path = TS.TEST_DIR + "/SM_" + cid
    if L.exists(path):
        return path
    fbx = L.ROOT + "Exports/Nature/Cover/%s.fbx" % cid
    if not os.path.exists(fbx):
        return None
    t = unreal.AssetImportTask()
    t.set_editor_property("filename", fbx)
    t.set_editor_property("destination_path", TS.TEST_DIR)
    t.set_editor_property("destination_name", "SM_" + cid)
    t.set_editor_property("automated", True)
    t.set_editor_property("replace_existing", True)
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
    L.at.import_asset_tasks([t])
    return path


def station_cover(ctx):
    import json
    try:
        with open(_HERE + "/materials_slot_map.json", "r", encoding="utf-8") as fh:
            slot_map = json.load(fh)
    except OSError:
        slot_map = {}
    y = 0.0
    for cid in COVER_IDS:
        path = _ensure_cover(cid)
        sm = L.ea.load_asset(path) if path else None
        if sm is None:
            L.warn("cover mesh %s missing" % cid)
            continue
        slots = [str(sl.get_editor_property("material_slot_name")) for sl in sm.get_editor_property("static_materials")]
        for i, sl in enumerate(slots):
            mi = slot_map.get(sl)
            if mi and L.exists(mi):
                sm.set_material(i, L.ea.load_asset(mi))
            else:
                L.warn("cover %s slot %s has no instance" % (cid, sl))
        L.log("cover %s slots=%s" % (cid, slots))
        a = ctx.spawn(unreal.StaticMeshActor, (0.0, y, 0.0))
        a.static_mesh_component.set_static_mesh(sm)
        a.set_actor_label(cid)
        y += 550.0
    wide = {"cam": (-3400, y * 0.5, 300), "look": (0, y * 0.5, 120), "fov": 100}
    out = [dict(wide, name="cover_all"), dict(wide, name="cover_wet", mpc={"Wetness": 1.0}), dict(wide, name="cover_snow", mpc={"SnowAmount": 0.9})]
    for k in range(3):
        cy = 4 * 550.0 * k + 825.0
        out.append({"name": "cover_part%d" % k, "cam": (-1500, cy, 220), "look": (0, cy, 130), "fov": 80})
    return out


ORIGIN["cover"] = (15000.0, 4000.0)
TS.register("cover", _with_origin("cover", station_cover))
