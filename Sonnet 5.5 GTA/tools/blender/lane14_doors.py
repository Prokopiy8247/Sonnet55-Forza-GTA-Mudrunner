"""lane14_doors.py - hospital_sliding_door_pair + police_door_pair.
Frame (static) + two leaves `Door_L` (-X) / `Door_R` (+X). Origin of the asset = bottom centre of the 3.0 m opening on the door plane, front (street side) = Blender +Y = -Z Godot.
LEAF ORIGINS = the OUTER bottom edge of each leaf in its closed position (x = -1.5 / +1.5): slide by translating along X (Door_L towards -X, Door_R towards +X, up to ~1.4 m, the leaves run behind the fixed side lights)
or swing by rotating about the leaf's own vertical axis (the same point is the hinge). Set ONLY=[...] before exec to build a subset."""
import math
from mathutils import Vector

CATB = "GTA_GODOT/Buildings"
OPEN_W, OPEN_H = 3.0, 2.4
LEAF_W = 1.5
LEAF_Y = -0.06         # leaf plane (behind the fixed side lights)


def leaf_mesh(b, sgn, style):
    """leaf geometry in the leaf's local frame (origin = outer bottom edge): spans local x 0 .. sgn*1.5 (towards the opening centre)"""
    t = 0.045
    H = OPEN_H - 0.03
    navy = style == "police"
    fm = "DoorFrameNavy" if navy else "DoorFrameSteel"
    bw = 0.1 if navy else 0.065

    def X(a, c):
        return (a * sgn, c * sgn)

    def bx(xa, xb, za, zb, m, skip=""):
        x0, x1 = X(xa, xb)
        b.abox(x0, x1, -t / 2, t / 2, za, zb, m, skip)
    bx(0.0, bw, 0.0, H, fm)                                    # outer stile
    bx(LEAF_W - bw, LEAF_W, 0.0, H, fm)                        # meeting stile
    bx(bw, LEAF_W - bw, H - bw, H, fm)                         # top rail
    low = 0.22 if not navy else 0.85
    bx(bw, LEAF_W - bw, 0.0, low, "DoorFrameWhite" if not navy else "DoorFrameNavy")      # kick plate / lower panel
    gx0, gx1 = bw, LEAF_W - bw
    xa, xb = X(gx0, gx1)
    b.yq(0.0, xa, xb, low, H - bw, 1, "Glass")                 # glass
    if not navy:
        b.yq(t / 2 + 0.002, xa, xb, 1.02, 1.12, 1, "DoorTealStripe")     # frosted privacy band (hospital teal)
        b.yq(-t / 2 - 0.002, xa, xb, 1.02, 1.12, -1, "DoorTealStripe")
        b.yq(t / 2 + 0.002, xa, xb, 1.32, 1.36, 1, "DoorDecal")
    else:
        b.yq(t / 2 + 0.002, xa, xb, 1.45, 1.5, 1, "DoorDecal")
        b.yq(-t / 2 - 0.002, xa, xb, 1.45, 1.5, -1, "DoorDecal")
        # push bar on the meeting stile side + chrome pull handle
        hx = (LEAF_W - bw - 0.08) * sgn
        b.cyl((hx, t / 2 + 0.06, 1.0), 0.022, 0.62, 5, "DoorBar", axis="Z", caps="bt")
        b.cyl((hx, -t / 2 - 0.06, 1.0), 0.022, 0.62, 5, "DoorBar", axis="Z", caps="bt")
        for zz in (0.75, 1.25):
            b.abox(hx - 0.02, hx + 0.02, t / 2, t / 2 + 0.06, zz - 0.02, zz + 0.02, "DoorBar", "-y -z")


def frame_mesh(b, style):
    navy = style == "police"
    fm = "DoorFrameNavy" if navy else "DoorFrameWhite"
    fm2 = "DoorFrameSteel" if not navy else "DoorFrameNavy"
    SW = 1.35                                                     # fixed side light width (the leaves tuck behind it)
    xo = OPEN_W / 2 + SW + 0.1                                    # outer edge of the frame (3.0 + 0.05..)
    # header / motor housing
    b.abox(-xo - 0.05, xo + 0.05, -0.17, 0.13, OPEN_H, OPEN_H + 0.32, fm)
    b.yq(0.1312, -xo, xo, OPEN_H + 0.05, OPEN_H + 0.1, 1, "DoorTealStripe" if not navy else "DoorDecal")
    b.abox(-0.2, 0.2, 0.13, 0.17, OPEN_H + 0.12, OPEN_H + 0.26, "DoorSensor")                  # sensor box
    # jambs + outer posts
    for sg in (-1, 1):
        b.abox(sg * (OPEN_W / 2) - 0.05, sg * (OPEN_W / 2) + 0.05, -0.12, 0.08, 0.0, OPEN_H, fm2)
        b.abox(sg * xo - 0.05, sg * xo + 0.05, -0.12, 0.08, 0.0, OPEN_H, fm2)
        # fixed side light: glass + kick rail + mid mullion
        xa, xb = (OPEN_W / 2 + 0.05) * sg, (xo - 0.05) * sg
        b.yq(0.02, min(xa, xb), max(xa, xb), 0.2, OPEN_H, 1, "Glass")
        b.abox(min(xa, xb), max(xa, xb), -0.0, 0.05, 0.0, 0.2, fm2)
        xm = (xa + xb) / 2
        b.abox(xm - 0.03, xm + 0.03, -0.01, 0.05, 0.2, OPEN_H, fm2)
        if not navy:
            b.yq(0.052, min(xa, xb), max(xa, xb), 1.02, 1.12, 1, "DoorTealStripe")
    # floor guide track
    b.abox(-xo - 0.05, xo + 0.05, -0.15, 0.07, 0.0, 0.03, "DoorFrameSteel")


def build_pair(aid, slot, style):
    A = A14(aid, slot, CATB, spacing=14.0)
    fb = HB(aid + "_frame")
    frame_mesh(fb, style)
    A.mesh(fb, "Frame", uv=None)
    for name, sgn in (("Door_L", 1), ("Door_R", -1)):
        lb = HB(aid + "_" + name)
        leaf_mesh(lb, sgn, style)
        A.mesh(lb, name, loc=(-sgn * LEAF_W, LEAF_Y, 0.0), uv=None)
    A.mark("Center", (0, 0, 0), size=0.3, display="PLAIN_AXES")
    A.mark("TriggerFront", (0, 1.6, 0), size=0.25, display="PLAIN_AXES")
    A.mark("TriggerBack", (0, -1.6, 0), size=0.25, display="PLAIN_AXES")
    return A


def build_hospital():
    return build_pair("hospital_sliding_door_pair", 21, "hospital")


def build_police():
    return build_pair("police_door_pair", 22, "police")


BUILD = {"hospital_sliding_door_pair": (build_hospital, 400), "police_door_pair": (build_police, 400)}
for _id, (_fn, _bud) in BUILD.items():
    if globals().get("ONLY") and _id not in ONLY:
        continue
    _fn().report(_bud)
