"""lane7: export size variants of already built assets without touching the editable source (geometry is squeezed in Y, exported, restored).
Requires the asset to be built (lane7_train_station.py). train_station_b: the industrial lot is only 21.2 m deep -> Y scale 0.87."""
import bmesh


def _scale_y(asset_id, k):
    root = bpy.data.objects[asset_id + "__root"]
    meshes = [o for o in descendants(root) if o.type == "MESH"]
    for o in meshes:
        me = o.data
        for v in me.vertices:
            v.co.y *= k
        me.update()
        o.location.y *= k
    for o in descendants(root):
        if o.type == "EMPTY" and o is not root:
            o.location.y *= k
    bpy.context.view_layer.update()
    return root


def export_scaled(asset_id, rel, k):
    root = _scale_y(asset_id, k)
    try:
        export_glb(root, rel)
    finally:
        _scale_y(asset_id, 1.0 / k)


export_scaled("train_station", "buildings/train_station_b", 0.87)
rep = stats(bpy.data.objects["train_station__root"], verbose=True)
