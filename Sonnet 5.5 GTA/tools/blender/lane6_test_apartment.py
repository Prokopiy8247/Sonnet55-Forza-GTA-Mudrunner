"""lane6_test_apartment.py - test assembly of kit_apartment (4 x 3 bays, 5 floors)."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())
A = "kit_apartment__"
def g(face, i, corner):
    if face == 0 and i == 1: return A + "Apt_Bay_Door_Stoop"
    if face == 0 and i in (0, 2): return A + "Apt_Bay_Shop_Ground"
    return A + "Apt_Bay_Shop_Ground" if corner else A + "Apt_Bay_Shop_Ground"
def u(face, i, f, corner):
    if corner: return A + "Apt_Corner_Out"
    if f == 1 and i in (1, 2): return A + "Apt_Bay_Balcony"
    if f == 2 and i == 2: return A + "Apt_FireEscape_Bay"
    if f == 3 and i == 0 and face == 0: return A + "Apt_Bay_Solid"
    return A + "Apt_Bay_Window"
assemble_block("kitasm_apt__", 13, 4, 3, g, u, 4, GH, FH, A + "Apt_Cornice", A + "Apt_Cornice_Corner", 1.5)
