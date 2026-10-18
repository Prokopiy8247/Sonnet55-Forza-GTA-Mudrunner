"""
Reproducible Blender -> Unreal FBX export helper (Blender 5.2, UE 5.8).

Run inside the verified Blender MCP session (localhost:9889):
    exec(compile(open(r"<project>/Tools/blender/lib/fbx_export.py", encoding="utf8").read(), "fbx_export", "exec"))
    export_fbx(["car01_Body", "UCX_car01_Body_01"], r"<project>/Exports/Cars/car01/car01_Body.fbx", center_on="car01_ROOT")
    export_fbx(["car01_Wheel_FL"], r"<project>/Exports/Cars/car01/car01_Wheel_FL.fbx", center_on="self")

Conventions (see Docs/BLENDER_CONTRACT.md):
  * 1 Blender unit = 1 metre, +X = vehicle forward, +Y = vehicle left, +Z = up.
  * FBX written with axis_forward='-Y', axis_up='Z' and unit scale applied so UE imports in centimetres at the right size
    (verified: 4 m long body -> 400 uu, X forward preserved, Blender +Y (left) -> UE -Y).
  * `center_on`: None  -> keep world transforms;
                 "self" or an object name/Object -> temporarily translate the export set so that the *world origin of that
                 object* (or of the first exported object for "self") lands at (0,0,0). Rotation/scale are never changed.
    The objects are temporarily un-parented (world transform kept) for the export and fully restored afterwards,
    so names (UCX_*, <id>_Wheel_FL ...) are preserved in the FBX.
"""
import bpy, os
from mathutils import Matrix, Vector


def _select_only(objs):
    vl = bpy.context.view_layer
    for o in list(bpy.context.selected_objects):
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    if objs:
        vl.objects.active = objs[0]


def export_fbx(objects, filepath, center_on=None, mesh_smooth='FACE', apply_modifiers=True,
               global_scale=1.0, extra_kwargs=None):
    """Export `objects` (names or Object refs) to a single FBX at `filepath`. Returns the absolute path or None."""
    objs = [bpy.data.objects[o] if isinstance(o, str) else o for o in objects]
    filepath = os.path.abspath(filepath)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    off = Vector((0.0, 0.0, 0.0))
    if center_on == "self":
        off = objs[0].matrix_world.translation.copy()
    elif center_on is not None:
        c = bpy.data.objects[center_on] if isinstance(center_on, str) else center_on
        off = c.matrix_world.translation.copy()

    saved = []
    try:
        if center_on is not None:
            bpy.context.view_layer.update()
            worlds = {o.name: o.matrix_world.copy() for o in objs}
            for o in objs:
                saved.append((o, o.parent, o.matrix_parent_inverse.copy(), o.matrix_basis.copy(), o.parent_type))
            for o in objs:
                mw = worlds[o.name]
                o.parent = None
                mw2 = mw.copy()
                mw2.translation = mw.translation - off
                o.matrix_world = mw2
            bpy.context.view_layer.update()

        _select_only(objs)
        kwargs = dict(
            filepath=filepath,
            check_existing=False,
            use_selection=True,
            use_visible=False,
            global_scale=global_scale,
            apply_unit_scale=True,
            apply_scale_options='FBX_SCALE_ALL',
            use_space_transform=True,
            bake_space_transform=False,
            object_types={'EMPTY', 'MESH'},
            use_mesh_modifiers=apply_modifiers,
            mesh_smooth_type=mesh_smooth,
            colors_type='SRGB',
            use_tspace=True,
            use_triangles=False,
            add_leaf_bones=False,
            bake_anim=False,
            path_mode='STRIP',
            embed_textures=False,
            axis_forward='-Y',
            axis_up='Z',
        )
        if extra_kwargs:
            kwargs.update(extra_kwargs)
        res = bpy.ops.export_scene.fbx(**kwargs)
    finally:
        for (o, parent, mpi, mb, ptype) in reversed(saved):
            o.parent = parent
            o.parent_type = ptype
            o.matrix_parent_inverse = mpi
            o.matrix_basis = mb
        if saved:
            bpy.context.view_layer.update()
    return filepath if 'FINISHED' in res else None
