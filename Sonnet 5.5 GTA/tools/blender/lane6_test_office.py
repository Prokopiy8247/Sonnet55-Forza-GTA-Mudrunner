"""lane6_test_office.py - assembles a test office tower (5 x 3 bays, 6 floors) from the kit_office modules to validate joins."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())

PFX = "kitasm_office__"
clear_asset(PFX)
_coll = coll(COLL_BUILDINGS)
_root = empty(PFX + "root", loc=workshop(L6, 12, 100.0), collection=_coll)
_n = [0]


def put(fam, mod, x, y, z, rotz):
    src = bpy.data.objects[fam + "__" + mod]
    _n[0] += 1
    o = bpy.data.objects.new(PFX + "%03d_%s" % (_n[0], mod), src.data)
    o.location = Vector((x, y, z))
    o.rotation_euler = (0, 0, math.radians(rotz))
    _coll.objects.link(o)
    o.parent = _root
    return o


F = "kit_office"
W, D = 5, 3          # bays along front / side
faces = []            # (rotation, bay_count, origin_fn)
def face_pos(face, i):
    if face == 0:   return (-10 + 2 + 4 * i, 0.0, 0)
    if face == 1:   return (10.0, -2 - 4 * i, -90)
    if face == 2:   return (10 - 2 - 4 * i, -12.0, 180)
    return (-10.0, -10 + 4 * i, 90)


def counts(face):
    return W if face in (0, 2) else D


z = 0.0
for face in range(4):
    n = counts(face)
    for i in range(n):
        x, y, r = face_pos(face, i)
        corner = (i == n - 1)
        if corner:
            put(F, "Office_Podium_Base", x, y, 0.0, r)
        elif face == 0 and i == 2:
            put(F, "Office_Bay_Ground_Lobby", x, y, 0.0, r)
        else:
            put(F, "Office_Bay_Ground_Window", x, y, 0.0, r)
        zf = GH
        for f in range(5):
            if corner:
                mod = "Office_Corner_Out"
            elif f == 2:
                mod = "Office_Bay_Spandrel_Stripe"
            elif f >= 3 and i == 1 and face != 0:
                mod = "Office_Bay_Solid"
            else:
                mod = "Office_Bay_Window"
            put(F, mod, x, y, zf, r)
            zf += FH
        put(F, "Office_Cornice", x, y, zf, r)
        if 0 < i < n - 1:
            put(F, "Office_Crown_A", x, y, zf + 1.45, r)
# pilasters on the front gridlines
for gx in (-6.0, 6.0):
    put(F, "Office_Pilaster", gx, 0.0, 0.0, 0)
    put(F, "Office_Pilaster", gx, 0.0, GH, 0)
    put(F, "Office_Pilaster", gx, 0.0, GH + FH, 0)
print("assembled", _n[0], "pieces")
