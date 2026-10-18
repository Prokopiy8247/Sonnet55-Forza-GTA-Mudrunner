"""Systems-A - elevator props: elevator_door (street-level lift door on the tower facade) and elevator_roof (machine-room house on the
roof next to the helipad). Run inside Blender (MCP execute_blender_code):
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane9_lib.py", encoding="utf8").read(), globals())
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\sysa_elevator.py", encoding="utf8").read(), globals())
    build_elevators()          # builds + exports props/elevator_door.glb and props/elevator_roof.glb, saves the master

Contract (Godot: InteractionElevator.build_door): origin on the floor; Blender +Y = front (Godot -Z). Meshes `Body` (static), `DoorL` and
`DoorR` (sliding leaves, Godot slides them +-0.52 m along X), empties `Stand` (where a rider steps out) and `UsePoint`.
elevator_door: origin on the facade (the wall is at y <= 0), 2.3 m wide, protrudes 0.22 m.  elevator_roof: origin = centre of the house on
the roof slab, house 3.8 (x) x 3.2 (y) x 3.0 m with the door in the front wall (+Y), overhang to y = 1.7.
"""

M_EL = {
    "ElevSteel":   dict(color="#b6bdc4", rough=0.32, metal=0.95),
    "ElevSteelDk": dict(color="#6f777f", rough=0.4, metal=0.9),
    "ElevCab":     dict(color="#f3dfb6", rough=0.6, emit="#ffd9a0", emit_strength=0.9),
    "ElevFloor":   dict(color="#2c2f35", rough=0.7),
    "ElevArrow":   dict(color="#3a2a10", rough=0.3, emit="#ffb347", emit_strength=3.0),
    "ElevBtn":     dict(color="#d8e4ea", rough=0.3, emit="#9fd4ff", emit_strength=1.6),
    "RoofConc":    dict(color="#bdb8ad", rough=0.95),
    "RoofConcDk":  dict(color="#8d897f", rough=0.95),
    "RoofHaz":     dict(color="#e8b92f", rough=0.55),
}
for _n, _s in M_EL.items():
    mat(_n, **_s)


def _leaf(a, node, x0, x1, y0, y1, z0, z1):
    """One sliding leaf = brushed steel panel with a vertical grain strip and a dark strip along the meeting edge."""
    b = a.mb(node)
    bx(b, (x0, x1), (y0, y1), (z0, z1), "ElevSteel")
    xc = (x0 + x1) / 2
    bx(b, (xc - 0.012, xc + 0.012), (y1, y1 + 0.006), (z0 + 0.12, z1 - 0.12), "ElevSteelDk")
    ex = x0 if x0 >= 0 else x1                                                                       # edge at x = 0 (the meeting edge)
    bx(b, (ex - 0.012, ex + 0.012), (y1, y1 + 0.012), (z0, z1), "ElevSteelDk")
    a.fin(b, node)


def b_elevator_door():
    a = new_asset("elevator_door", 90)
    b = a.mb("Body")
    # --- frame: two wide pilasters + lintel (brushed steel) around a 1.1 m opening, 2.2 m high
    HW, OW, H, LH = 1.15, 0.55, 2.2, 2.7
    bx(b, (OW, HW), (0.0, 0.2), (0.0, LH), "ElevSteel")                                                # right pilaster
    bx(b, (-HW, -OW), (0.0, 0.2), (0.0, LH), "ElevSteel")                                              # left pilaster
    bx(b, (OW - 0.02, OW + 0.05), (0.2, 0.225), (0.0, H), "ElevSteelDk")                               # reveal lips
    bx(b, (-OW - 0.05, -OW + 0.02), (0.2, 0.225), (0.0, H), "ElevSteelDk")
    bx(b, (-OW, OW), (0.0, 0.2), (H, LH), "ElevSteel")
    bx(b, (-HW - 0.05, HW + 0.05), (0.0, 0.23), (0.0, 0.1), "ElevSteelDk")                          # kick plinth
    # --- lit cab visible when the leaves open
    bx(b, (-OW, OW), (0.0, 0.012), (0.1, H), "ElevCab")                                             # back wall (glowing)
    bx(b, (-OW, OW), (0.0, 0.22), (0.0, 0.05), "ElevFloor")                                         # threshold sill
    # --- floor indicator + arrows above the door
    bx(b, (-0.38, 0.38), (0.2, 0.235), (H + 0.18, H + 0.46), "MetalDark")
    ext(b, [(-0.2, H + 0.25), (-0.04, H + 0.25), (-0.12, H + 0.39)], "xz", 0.235, 0.245, "ElevArrow")   # up arrow
    ext(b, [(0.04, H + 0.39), (0.2, H + 0.39), (0.12, H + 0.25)], "xz", 0.235, 0.245, "ElevArrow")      # down arrow
    # call panel on the right pilaster
    bx(b, (0.74, 0.96), (0.2, 0.23), (1.0, 1.4), "MetalDark")
    for i, zz in enumerate((1.3, 1.1)):
        bx(b, (0.82, 0.88), (0.23, 0.25), (zz - 0.035, zz + 0.035), "ElevBtn")
    # warning plate
    bx(b, (-0.95, -0.75), (0.2, 0.212), (1.2, 1.3), "PlateYellow")
    a.fin(b, "Body")
    _leaf(a, "DoorL", -OW, 0.0, 0.035, 0.075, 0.0, H)
    _leaf(a, "DoorR", 0.0, OW, 0.035, 0.075, 0.0, H)
    a.mark("Stand", (0.0, 1.5, 0.0))
    a.mark("UsePoint", (0.0, 1.25, 0.0))
    return a


def b_elevator_roof():
    a = new_asset("elevator_roof", 91)
    b = a.mb("Body")
    W, D, H = 1.9, 1.6, 3.0                         # half width (x), half depth (y), wall height
    OW, DOOR_H = 0.55, 2.2
    # --- floor slab + plinth
    bx(b, (-W - 0.1, W + 0.1), (-D - 0.1, D + 0.2), (0.0, 0.12), "RoofConcDk")
    # --- walls: left/right/back (thick), front piers + lintel (thin facing so the leaves slide behind them)
    bx(b, (-W, -W + 0.3), (-D, D - 0.15), (0.12, H), "RoofConc")
    bx(b, (W - 0.3, W), (-D, D - 0.15), (0.12, H), "RoofConc")
    bx(b, (-W + 0.3, W - 0.3), (-D, -D + 0.3), (0.12, H), "RoofConc")
    for sx in (-1, 1):
        bx(b, (OW if sx > 0 else -W, W if sx > 0 else -OW), (D - 0.15, D), (0.12, H), "RoofConc")
    bx(b, (-OW, OW), (D - 0.15, D), (DOOR_H, H), "RoofConc")
    # steel door frame trim on the front
    bx(b, (OW, OW + 0.1), (D, D + 0.07), (0.12, DOOR_H + 0.1), "ElevSteel")
    bx(b, (-OW - 0.1, -OW), (D, D + 0.07), (0.12, DOOR_H + 0.1), "ElevSteel")
    bx(b, (-OW - 0.1, OW + 0.1), (D, D + 0.07), (DOOR_H, DOOR_H + 0.1), "ElevSteel")
    # --- roof slab with overhang, parapet strip, hazard band
    bx(b, (-W - 0.2, W + 0.2), (-D - 0.2, D + 0.2), (H, H + 0.18), "RoofConcDk")
    bx(b, (-W - 0.2, W + 0.2), (D + 0.2 - 0.04, D + 0.2), (H + 0.18, H + 0.34), "RoofConcDk")
    bx(b, (-W + 0.1, W - 0.1), (D - 0.01, D + 0.012), (2.55, 2.75), "RoofHaz")                      # hazard band over the door
    # --- lit cab interior
    bx(b, (-OW, OW), (-D + 0.3, -D + 0.32), (0.12, DOOR_H), "ElevCab")
    bx(b, (-OW, OW), (-D + 0.3, D - 0.2), (0.12, 0.16), "ElevFloor")
    bx(b, (-OW, OW), (-D + 0.3, D - 0.2), (DOOR_H - 0.04, DOOR_H), "ElevCab")
    # --- indicator lamp + sign above the door
    bx(b, (-0.35, 0.35), (D + 0.07, D + 0.1), (DOOR_H + 0.16, DOOR_H + 0.36), "MetalDark")
    bx(b, (-0.3, 0.3), (D + 0.1, D + 0.108), (DOOR_H + 0.2, DOOR_H + 0.32), "ElevArrow")
    # call panel
    bx(b, (OW + 0.14, OW + 0.34), (D + 0.0, D + 0.04), (1.0, 1.4), "MetalDark")
    for zz in (1.3, 1.1):
        bx(b, (OW + 0.21, OW + 0.27), (D + 0.04, D + 0.06), (zz - 0.035, zz + 0.035), "ElevBtn")
    # --- side louvre vents (both sides)
    for sx in (-1, 1):
        xs = sx * W
        o = 1.0 if sx > 0 else -1.0
        bx(b, (min(xs, xs + 0.03 * o), max(xs, xs + 0.03 * o)), (-0.6, 0.6), (1.2, 2.3), "MetalDark")
        for k in range(7):
            zz = 1.28 + k * 0.15
            bx(b, (min(xs + 0.03 * o, xs + 0.07 * o), max(xs + 0.03 * o, xs + 0.07 * o)), (-0.55, 0.55), (zz, zz + 0.05), "Metal")
    # --- roof gear: cooling unit, vent pipe, small antenna mast
    bx(b, (-1.1, -0.2), (-0.9, 0.0), (H + 0.18, H + 0.62), "UtilGrey")
    cylz(b, -0.65, -0.45, H + 0.62, H + 0.72, 0.28, 10, "MetalDark")
    cylz(b, 1.0, -0.8, H + 0.18, H + 0.95, 0.07, 8, "Metal")
    cylz(b, 1.0, -0.8, H + 0.95, H + 1.0, 0.11, 8, "MetalDark")
    cylz(b, 1.45, 0.4, H + 0.18, H + 2.2, 0.025, 6, "ElevSteelDk")
    b.sphere((1.45, 0.4, H + 2.22), 0.05, 6, 4, "ReflectRed")
    # --- exterior ladder-free service light over the door
    bx(b, (-0.12, 0.12), (D + 0.0, D + 0.14), (H - 0.3, H - 0.18), "MetalDark")
    bx(b, (-0.1, 0.1), (D + 0.14, D + 0.16), (H - 0.28, H - 0.2), "LampGlow")
    a.fin(b, "Body")
    _leaf(a, "DoorL", -OW, 0.0, D - 0.28, D - 0.2, 0.12, DOOR_H)
    _leaf(a, "DoorR", 0.0, OW, D - 0.28, D - 0.2, 0.12, DOOR_H)
    a.mark("Stand", (0.0, D + 1.5, 0.0))
    a.mark("UsePoint", (0.0, D + 1.2, 0.0))
    return a


def build_elevators(export=True, save=True):
    import io, contextlib
    for aid, fn in (("elevator_door", b_elevator_door), ("elevator_roof", b_elevator_roof)):
        a = fn()
        info = stats(a.root, False)
        print("%-16s tris=%d size=%s" % (aid, info["tris"], info["size"]))
        if export:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                export_glb(a.root, "props/" + aid)
            print(buf.getvalue().strip())
    if save and export:
        save_master()
