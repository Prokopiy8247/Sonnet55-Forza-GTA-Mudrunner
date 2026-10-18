# lane 8 QA: flag faces whose outward ray immediately re-hits the same mesh (typically inverted open quads such as windows)
import bmesh
from mathutils.bvhtree import BVHTree
IDS = ["tower_a", "tower_b", "tower_c", "control_tower", "hangar_a", "terminal", "warehouse_a", "factory", "hotel", "hangar_b",
       "warehouse_b", "silo_cluster", "crane_dock", "container_stack", "lighthouse", "ferris_wheel", "pier_hut"]
import sys
ONLY = globals().get("QA_ONLY") or IDS
for aid in ONLY:
    root = bpy.data.objects.get(aid + "__root")
    if root is None:
        print(aid, "MISSING")
        continue
    for o in descendants(root):
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bvh = BVHTree.FromBMesh(bm)
        per = {}
        for f in bm.faces:
            if f.calc_area() < 0.05:
                continue
            n = f.normal
            c = f.calc_center_median()
            mi = f.material_index
            mname = o.data.materials[mi].name if mi < len(o.data.materials) else "?"
            hf = bvh.ray_cast(c + n * 0.003, n, 400.0)[0] is not None
            hb = bvh.ray_cast(c - n * 0.003, -n, 400.0)[0] is not None
            tot, bad = per.get(mname, (0, 0))
            per[mname] = (tot + 1, bad + (1 if (hf and not hb) else 0))
        bm.free()
        sus = {k: v for k, v in per.items() if v[1] > 0}
        print("QA", o.name, "inverted-suspects (fwd hit, back free):", sus)
