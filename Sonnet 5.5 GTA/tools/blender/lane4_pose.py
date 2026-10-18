"""lane4_pose.py - pose test on a COPY of the rig + selected meshes (original stays untouched). exec after gta_lib + lane4_lib.
Set C4_POSE_MESHES (list of mesh names without prefix) and C4_POSES (dict name -> {bone: (rx, ry, rz) model-space degrees}) before exec.
Angles are model-space rotations about the bone head (Blender axes): +X rotation swings a hanging limb FORWARD (+Y);
negative X on Spine/Head bends forward; Z = yaw."""
from mathutils import Euler


def c4_pose_apply(arm, spec):
    bpy.context.view_layer.update()
    if arm.pose is None:
        bpy.context.view_layer.update()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for name, ang in spec.items():
        pb = arm.pose.bones[name]
        B = pb.bone.matrix_local.to_3x3()
        R = Euler([math.radians(a) for a in ang], "XYZ").to_matrix()
        pb.rotation_quaternion = (B.inverted() @ R @ B).to_quaternion()
    bpy.context.view_layer.update()


def c4_pose_copy(tag, mesh_names, spec, dx):
    """duplicate armature + meshes into human__tmp_<tag>_*, offset by dx metres in X, apply the pose; returns the new armature."""
    src = c4_rig()
    arm_d = src.data.copy()
    arm = bpy.data.objects.new(C4_PFX + "tmp_" + tag + "_arm", arm_d)
    coll(C4_COLL).objects.link(arm)
    arm.location = src.matrix_world.translation + Vector((dx, 0, 0))
    for n in mesh_names:
        o = bpy.data.objects.get(C4_PFX + n)
        if o is None:
            continue
        c = o.copy()
        c.data = o.data.copy()
        c.name = C4_PFX + "tmp_" + tag + "_" + n
        coll(C4_COLL).objects.link(c)
        for m in c.modifiers:
            if m.type == "ARMATURE":
                m.object = arm
        c.parent = arm
        c.matrix_parent_inverse = Matrix.Identity(4)
    c4_pose_apply(arm, spec)
    return arm


C4_POSES_DEFAULT = {
    "walk": {"UpperArm_R": (-35, 0, 0), "LowerArm_R": (30, 0, 0), "UpperArm_L": (35, 0, 0), "LowerArm_L": (10, 0, 0),
             "UpperLeg_R": (35, 0, 0), "LowerLeg_R": (-5, 0, 0), "UpperLeg_L": (-30, 0, 0), "LowerLeg_L": (-45, 0, 0), "Spine": (-6, 0, 0)},
    "test": {"UpperArm_R": (80, 0, 0), "LowerArm_R": (90, 0, 0), "UpperLeg_R": (70, 0, 0), "LowerLeg_R": (-90, 0, 0),
             "UpperArm_L": (0, -75, 0), "LowerArm_L": (0, 0, 0), "Spine": (-25, 0, 0), "Head": (-20, 0, 40), "UpperLeg_L": (-20, 0, 0), "LowerLeg_L": (-30, 0, 0)},
    "sit": {"UpperLeg_R": (90, 0, 0), "LowerLeg_R": (-90, 0, 0), "UpperLeg_L": (90, 0, 0), "LowerLeg_L": (-90, 0, 0),
            "UpperArm_R": (60, 0, 0), "LowerArm_R": (70, 0, 0), "UpperArm_L": (60, 0, 0), "LowerArm_L": (70, 0, 0), "Spine": (-10, 0, 0)},
    "up": {"UpperArm_R": (0, 150, 0), "UpperArm_L": (0, -150, 0), "Spine": (10, 0, 0), "Head": (20, 0, 0),
           "UpperLeg_R": (0, 35, 0), "UpperLeg_L": (0, -35, 0), "LowerArm_R": (-30, 0, 0), "LowerArm_L": (-30, 0, 0)},
    "aim": {"UpperArm_R": (85, 0, 0), "LowerArm_R": (10, 0, 0), "UpperArm_L": (70, 0, 0), "LowerArm_L": (40, 0, 0), "Spine": (0, 0, 12), "Chest": (0, 0, 12)},
}

if globals().get('C4_POSE_RUN', True):
    clear_asset(C4_PFX + "tmp_pose")
    _names = globals().get("C4_POSE_MESHES", ["Body_A"])
    _poses = globals().get("C4_POSES", C4_POSES_DEFAULT)
    _dx = 1.2
    for _tag, _spec in _poses.items():
        c4_pose_copy("pose" + _tag, _names, _spec, _dx)
        _dx += 1.2
    print("pose copies:", list(_poses.keys()))


def c4_hide_originals(hide=True):
    for o in bpy.data.objects:
        if o.name.startswith(C4_PFX) and "tmp_" not in o.name:
            o.hide_set(hide)


def c4_lineup(tag, items, spacing=0.9, spec=None):
    """items: [(body, [accessories])] -> copies of the rig in rest pose (or spec) side by side."""
    clear_asset(C4_PFX + "tmp_" + tag)
    for i, (body, accs) in enumerate(items):
        c4_pose_copy(tag + str(i), [body] + list(accs), spec or {}, i * spacing)


def c4_recolor(arm, spec):
    """preview only: give the COPIES of one figure their own colours. spec: {slot_material_name: palette key or #hex}."""
    for ch in arm.children:
        if ch.type != "MESH":
            continue
        for i, m in enumerate(ch.data.materials):
            if m is not None and m.name in spec:
                nm = "tmpmat_%s_%s" % (m.name, str(spec[m.name]).lstrip("#"))
                keep = STD.get(m.name, {})
                nmat = mat(nm, color=spec[m.name], rough=keep.get("rough", 0.8), metal=keep.get("metal", 0.0))
                ch.data.materials[i] = nmat


def c4_clean_tmp_mats():
    for m in [m for m in bpy.data.materials if m.name.startswith("tmpmat_") or m.name == "tmp_red"]:
        bpy.data.materials.remove(m)
