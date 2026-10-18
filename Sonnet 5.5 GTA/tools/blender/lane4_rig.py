"""lane4_rig.py - (re)creates human__root, human__Armature (21 deform bones per ARCHITECTURE s12) and the hand sockets.
Run after gta_lib.py + lane4_lib.py. WARNING: deletes ALL human__* objects (meshes must be rebuilt afterwards) when C4_REBUILD_RIG is True
(default); with C4_REBUILD_RIG=False it only makes sure the rig exists."""
try:
    _rebuild = C4_REBUILD_RIG
except NameError:
    _rebuild = True

if _rebuild or c4_rig() is None:
    clear_asset(C4_PFX)
    _coll = coll(C4_COLL)
    _root = empty(C4_PFX + "root", loc=workshop(4, 0), collection=_coll, display="ARROWS", size=0.3)
    _arm = make_armature(C4_PFX + "Armature", c4_bone_list(), collection=_coll)
    parent_to(_arm, _root)
    _arm.data.display_type = "STICK"
    for _n, _sx in (("R", 1), ("L", -1)):
        empty(C4_PFX + "HandSocket_" + _n, loc=(0.43 * _sx, 0.04, 0.78), parent=_arm, collection=_coll, display="SPHERE", size=0.04)
    bpy.context.view_layer.update()
print("rig ok:", len(c4_rig().data.bones), "bones; root at", tuple(c4_root().location))
