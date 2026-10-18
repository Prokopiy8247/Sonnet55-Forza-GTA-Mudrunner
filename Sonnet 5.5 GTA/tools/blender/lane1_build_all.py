"""lane1_build_all.py - rebuild + export all lane-1 cars (idempotent).  Load gta_lib.py and lane1_common.py first, then exec this file.
   exec(open(r"...\\tools\\blender\\lane1_build_all.py", encoding="utf8").read(), globals())"""
_TD = PROJECT + "\\tools\\blender\\"
_ORDER = ["police_cruiser", "suv", "pickup", "van", "taxi"]
_ONLY = globals().get("LANE1_ONLY", _ORDER)
_REPORT = {}
for _nm in _ORDER:
    if _nm not in _ONLY:
        continue
    exec(open(_TD + "lane1_" + _nm + ".py", encoding="utf8").read(), globals())
    car.export()
    _t = tri_total(car.root)
    _l = tri_total(car.lod_root) if car.lod_root is not None else {}
    _REPORT[_nm] = dict(total=sum(_t.values()), body=_t.get("Body"), lod=sum(_l.values()))
print("LANE1 BUILD REPORT:", _REPORT)
save_master()
