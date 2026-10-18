"""lane 9 - rebuild + export EVERY street prop / interior asset (idempotent).
Run inside Blender (MCP execute_blender_code):
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane9_build_all.py", encoding="utf8").read(), globals())
    build_all()                    # everything            |  build_all(["street_lamp", "sofa"])  # a subset
    build_all(export=False)        # build only
"""
import io
import contextlib

_T = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender"
for _f in ("lane9_lib", "lane9_street1", "lane9_street2", "lane9_street3", "lane9_interiors1", "lane9_interiors2"):
    exec(open(_T + "\\" + _f + ".py", encoding="utf8").read(), globals())

PROPS = ["traffic_light", "street_lamp", "stop_sign", "road_cone", "trash_bin", "bench", "fire_hydrant", "bus_stop", "street_lamp_double",
         "highway_lamp", "traffic_light_ped", "speed_sign", "street_sign", "bollard", "concrete_barrier", "road_barrier", "dumpster",
         "utility_box", "mailbox", "parking_meter", "phone_booth", "newspaper_box", "fence_chainlink", "fence_wood", "fence_metal_gate",
         "utility_pole", "ladder_wall", "crate", "barrel", "pallet", "tire_stack", "container", "container_b", "container_c", "container_d",
         "dock_bollard", "life_ring", "pier_post", "billboard"]
INTERIORS = ["shop_counter", "shelf_wall", "weapon_rack_wall", "gun_bench", "clothing_rack", "mannequin", "wardrobe", "bed_double", "nightstand",
             "sofa", "tv_stand_tv", "table_round", "chair", "kitchen_unit", "barber_chair", "mirror_wall", "scuba_rack", "repair_lift",
             "tool_chest", "neon_sign_blank"]
TRI_LIMIT = {"street_lamp": 450, "street_lamp_double": 450, "highway_lamp": 450, "traffic_light": 450, "traffic_light_ped": 450}


def build_all(ids=None, export=True, save=True):
    report = []
    for aid in PROPS + INTERIORS:
        if ids and aid not in ids:
            continue
        cat = "props" if aid in PROPS else "interiors"
        a = globals()["b_" + aid]()
        info = stats(a.root, False)
        if export:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                export_glb(a.root, cat + "/" + aid)
        lim = TRI_LIMIT.get(aid, 300)
        report.append((aid, info["tris"], lim, info["size"]))
        print("%-20s %s tris=%d/%d size=%s" % (aid, cat, info["tris"], lim, info["size"]) + ("   <-- OVER BUDGET" if info["tris"] > lim else ""))
    if save and export:
        save_master()
    return report
