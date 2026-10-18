r"""lane11_build_all.py - rebuilds every lane-11 vehicle part, optionally exports the GLBs, then (re)builds the QA fixtures.
    LIB = r"...\tools\blender"
    exec(open(LIB + r"\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    for f in ("lane11_common.py", "lane11_catalog.py", "lane11_spoilers.py", "lane11_aero.py", "lane11_topside.py",
              "lane11_misc.py", "lane11_wheels.py", "lane11_fit.py", "lane11_build_all.py"):
        exec(open(LIB + "\\" + f, encoding="utf8").read(), globals())
    l11_build_all(export=True)          # -> gta/generated/models/vehicle_parts/<id>.glb
    l11_dump_stats()                    # tools/blender/lane11_stats.json (for lane11_docgen.py)
    l11_showcase()                      # reference sedan + part instances (QA only, not exported)
    save_master()
"""


def l11_build_all(export=True, only=None):
    groups = [l11_build_spoilers, l11_build_aero, l11_build_topside, l11_build_misc, l11_build_wheels]
    allp = []
    for g in groups:
        for P in g():
            if only and P.pid not in only:
                continue
            allp.append(P)
    tot = 0
    for P in allp:
        info = stats(P.root, verbose=False)
        tot += info["tris"]
        if export:
            P.export()
    print("built %d parts, %d tris total, exported=%s" % (len(allp), tot, export))
    return allp


def l11_dump_stats(path=None):
    """write tris / size / materials / nodes of every part to tools/blender/lane11_stats.json (read by lane11_docgen.py)."""
    import json
    path = path or os.path.join(PROJECT, "tools", "blender", "lane11_stats.json")
    out = {}
    for pid in L11_ORDER:
        root = bpy.data.objects[pid + "__root"]
        info = stats(root, verbose=False)
        out[pid] = dict(tris=info["tris"], size=info["size"], min=info["min"], max=info["max"], materials=info["materials"],
                        nodes=sorted(o.name.split("__", 1)[1] for o in root.children))
    json.dump(out, open(path, "w"), indent=1)
    return out


SHOWCASE = ["spoiler_wing_low", "bumper_front_sport", "splitter_front", "skirt_side_sport", "bumper_rear_diffuser", "hood_vents_b",
            "mirror_sport", "exhaust_tip_dual", "underglow_strip", "roof_light_bar"]


def l11_showcase(ids=None, wheel="wheel_turbine"):
    """reference sedan (shared mesh data of sedan__*, read-only) wearing a sporty set of parts at the catalog mounts."""
    ids = ids or SHOWCASE
    clear_asset("vpfit__")
    l11_make_ref()
    l11_fit(ids, clear=False)
    l11_fit_wheels({"FL": wheel, "FR": wheel, "RL": wheel, "RR": wheel})
    return ids
