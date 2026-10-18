"""lane4_preview.py - 3 variety preview rows (A / B / C bodies with toggled accessories + recoloured material copies).
Creates human__tmp_pvA_*, pvB_*, pvC_* objects (NOT under human__root, never exported). Remove with clear_asset('human__tmp_')."""
C4_POSE_RUN = False
exec(open(os.path.join(PROJECT, "tools", "blender", "lane4_pose.py"), encoding="utf8").read(), globals())
clear_asset(C4_PFX + "tmp_")
c4_clean_tmp_mats()
c4_hide_originals(True)
_rows = {
    "pvA": ("Body_A", [
        (["Hair_1", "Hat_Cap", "Glasses_Round"], dict(Skin="skin_2", Hair="hair_brown", Shirt="coral", Pants="navy", Accent="cyan", Shoes="white")),
        (["Hair_2", "Jacket_Short", "Beard_2"], dict(Skin="skin_4", Hair="hair_black", Shirt="teal", Pants="charcoal", Accent="mustard", Shoes="brick")),
        (["Hair_6", "Vest_Armor", "Glasses_Shades"], dict(Skin="skin_1", Hair="hair_red", Shirt="white", Pants="steel_dark", Accent="magenta", Shoes="black")),
        (["Hat_Beanie", "Jacket_Long", "Backpack"], dict(Skin="skin_3", Hair="hair_blond", Shirt="plum", Pants="black", Accent="amber", Shoes="sand")),
    ]),
    "pvB": ("Body_B", [
        (["Hair_3", "Glasses_Round", "Vest_Armor"], dict(Skin="skin_1", Hair="hair_blond", Shirt="dusty_blue", Pants="plum", Accent="magenta", Shoes="white")),
        (["Hair_4", "Jacket_Short"], dict(Skin="skin_5", Hair="hair_black", Shirt="mustard", Pants="navy", Accent="teal", Shoes="red")),
        (["Hair_5", "Backpack", "Glasses_Shades"], dict(Skin="skin_3", Hair="hair_black", Shirt="sage", Pants="charcoal", Accent="coral", Shoes="black")),
        (["Hat_Police", "Vest_Tactical", "Hair_4"], dict(Skin="skin_2", Hair="hair_brown", Shirt="navy", Pants="navy", Accent="navy", Shoes="black")),
    ]),
    "pvC": ("Body_C", [
        (["Hair_1", "Beard_1", "Hat_Cap"], dict(Skin="skin_3", Hair="hair_grey", Shirt="brick", Pants="steel_dark", Accent="amber", Shoes="black")),
        (["Hair_5", "Jacket_Long", "Glasses_Shades"], dict(Skin="skin_5", Hair="hair_black", Shirt="charcoal", Pants="navy", Accent="cyan", Shoes="white")),
        (["Helmet_Tactical", "Vest_Tactical", "Beard_2"], dict(Skin="skin_2", Hair="hair_brown", Shirt="sage", Pants="charcoal", Accent="charcoal", Shoes="black")),
        (["Hair_6", "Hat_Beanie", "Backpack", "Beard_1"], dict(Skin="skin_4", Hair="hair_red", Shirt="orange", Pants="dusty_blue", Accent="white", Shoes="yellow")),
    ]),
}
for _tag, (_body, _items) in _rows.items():
    for _i, (_accs, _cols) in enumerate(_items):
        _a = c4_pose_copy("%s%d" % (_tag, _i), [_body] + _accs, {}, _i * 1.05)
        c4_recolor(_a, _cols)
# shift rows apart in Y so they can be looked at one by one
for _o in bpy.data.objects:
    if _o.name.startswith("human__tmp_pvB") and _o.parent is None:
        _o.location.y += 6.0
    if _o.name.startswith("human__tmp_pvC") and _o.parent is None:
        _o.location.y += 12.0
print("previews ready")
