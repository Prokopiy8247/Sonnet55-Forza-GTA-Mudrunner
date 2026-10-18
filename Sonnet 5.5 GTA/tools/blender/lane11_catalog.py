r"""
lane11_catalog.py - part list, workshop slots and the recommended SEDAN mount transforms (single source of truth for the
contact sheet, the docs table and gta/generated/models/vehicle_parts/parts_catalog.json).
Load after lane11_common.py.

Mount transform = where the part ORIGIN goes in the sedan's local frame (Blender: +X right, +Y forward, +Z up, origin = ground
point at the wheelbase centre). pitch = rotation about X in degrees (positive = nose up; identical sign in Godot because X maps to X).
Godot position = (x, z, -y).
"""
L11_ORDER = [
    "spoiler_lip", "spoiler_ducktail", "spoiler_wing_low", "spoiler_wing_high",
    "splitter_front", "bumper_front_sport", "bumper_rear_diffuser",
    "hood_scoop_a", "hood_vents_b", "roof_scoop", "roof_rack", "roof_light_bar",
    "skirt_side_sport", "exhaust_tip_single", "exhaust_tip_dual", "exhaust_tip_quad",
    "underglow_strip", "grille_mesh", "mirror_sport", "antenna",
    "wheel_stock", "wheel_five_spoke", "wheel_split_six", "wheel_mesh", "wheel_dish",
    "wheel_turbine", "wheel_steel_basic", "wheel_offroad", "wheel_lowprofile", "wheel_mc_sport",
]


def l11_idx(pid):
    return L11_ORDER.index(pid)


# sedan mount transforms: id -> dict(pos=(x, y, z) Blender metres, pitch=deg about X (+ = nose up), note=...)
# (all parts keep scale (1,1,1) on the sedan; other vehicles: see L11_FIT in the docs / parts_catalog.json)
L11_MOUNT = {
    "spoiler_lip":          dict(pos=(0.0, -2.13, 0.962), pitch=0.0, note="trunk lid rear edge"),
    "spoiler_ducktail":     dict(pos=(0.0, -2.00, 0.968), pitch=0.0, note="trunk lid rear edge"),
    "spoiler_wing_low":     dict(pos=(0.0, -1.98, 0.968), pitch=0.0, note="trunk lid, rear third"),
    "spoiler_wing_high":    dict(pos=(0.0, -2.00, 0.968), pitch=0.0, note="trunk lid, rear third"),
    "splitter_front":       dict(pos=(0.0, 2.30, 0.285), pitch=0.0, note="under the nose, plate top flush with the bumper underside"),
    "bumper_front_sport":   dict(pos=(0.0, 2.385, 0.27), pitch=0.0, note="shell sits ON the nose, covers bumper bar + lower valance"),
    "bumper_rear_diffuser": dict(pos=(0.0, -2.31, 0.27), pitch=0.0, note="under / on the rear bumper"),
    "hood_scoop_a":         dict(pos=(0.0, 1.35, 0.912), pitch=-5.1, note="hood centre, pitched to the hood slope"),
    "hood_vents_b":         dict(pos=(0.0, 1.55, 0.892), pitch=-5.1, note="hood centre, pitched to the hood slope"),
    "roof_scoop":           dict(pos=(0.0, -0.30, 1.45), pitch=0.0, note="flat roof centre"),
    "roof_rack":            dict(pos=(0.0, -0.30, 1.45), pitch=0.0, note="flat roof centre"),
    "roof_light_bar":       dict(pos=(0.0, 0.10, 1.45), pitch=0.0, note="front edge of the flat roof"),
    "skirt_side_sport":     dict(pos=(0.0, 0.0, 0.20), pitch=0.0, note="between the wheel arches, bottom of the sill"),
    "exhaust_tip_single":   dict(pos=(0.56, -2.36, 0.262), pitch=0.0, note="at the sedan's Exhaust empty (right side)"),
    "exhaust_tip_dual":     dict(pos=(0.0, -2.36, 0.262), pitch=0.0, note="one tip each side (x = +-0.54)"),
    "exhaust_tip_quad":     dict(pos=(0.0, -2.36, 0.262), pitch=0.0, note="two tips each side (x = +-0.47, +-0.60)"),
    "underglow_strip":      dict(pos=(0.0, 0.0, 0.175), pitch=0.0, note="under the body, centred on the wheelbase"),
    "grille_mesh":          dict(pos=(0.0, 2.345, 0.632), pitch=0.0, note="in front of the stock grille"),
    "mirror_sport":         dict(pos=(0.0, 0.62, 0.99), pitch=0.0, note="replaces the door mirrors (x = +-0.86..1.12)"),
    "antenna":              dict(pos=(0.47, -0.65, 1.45), pitch=0.0, note="roof, rear right"),
}
# sedan wheel positions (x, y, z=wheel centre height) for wheel_* parts; sedan wheel radius 0.33 -> uniform scale 0.97
L11_SEDAN_WHEELS = {"FL": (-0.79, 1.415, 0.33), "FR": (0.79, 1.415, 0.33), "RL": (-0.79, -1.415, 0.33), "RR": (0.79, -1.415, 0.33)}
