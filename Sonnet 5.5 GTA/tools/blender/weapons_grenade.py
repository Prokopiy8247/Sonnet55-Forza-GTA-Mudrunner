# weapons_grenade.py - lane 5 - weapons/grenade (0.10 m modern frag grenade, fuze up +Z; origin = body centre). Needs gta_lib + weapons_common exec'd.
W = Wpn("grenade", 14)

def revz(b, st, seg=10, mat="Paint", rot=0.0, cx=0.0, cy=0.0, caps=(True, True)):
    rings = []
    for z, r in st:
        rings.append([(cx + r * math.cos(2 * math.pi * i / seg + math.radians(rot)), cy + r * math.sin(2 * math.pi * i / seg + math.radians(rot)), z) for i in range(seg)])
    return b.loft(rings, mat, True, caps[0], caps[1])

b = W.mb("Body")
body = [(-0.0400, 0.0100), (-0.0360, 0.0190), (-0.0210, 0.0258), (0.0000, 0.0280), (0.0200, 0.0255), (0.0330, 0.0192), (0.0385, 0.0125)]
revz(b, body, 10, "GrenadeBody", 18.0)
# segmentation grooves
for z in (-0.0100, 0.0100):
    revz(b, [(z - 0.0016, 0.0283 if abs(z) < 0.011 else 0.0270), (z + 0.0016, 0.0283 if abs(z) < 0.011 else 0.0270)], 10, "Gun", 18.0)
# fuze housing, neck collar, top cap
revz(b, [(0.0380, 0.0115), (0.0440, 0.0115), (0.0450, 0.0140), (0.0520, 0.0140), (0.0525, 0.0095)], 8, "MetalDark", 22.5)
revz(b, [(0.0525, 0.0095), (0.0560, 0.0075)], 8, "Metal", 22.5)
# safety lever (spoon) hugging the body from the fuze down the +X side
ribbon_xz(b, [(0.0070, 0.0560), (0.0150, 0.0540), (0.0215, 0.0455), (0.0275, 0.0300), (0.0300, 0.0080), (0.0290, -0.0130), (0.0250, -0.0275)], 0.0150, 0.0026, "Metal")
# safety pin + pull ring (accent)
b.beam((-0.0110, 0.0, 0.0480), (0.0235, 0.0, 0.0480), 0.0017, 0.0017, 4, "Metal")
RR = 0.0078
RCX, RCZ = -0.0110 - RR, 0.0480
for i in range(6):
    a0, a1 = i * math.pi / 3, (i + 1) * math.pi / 3
    b.beam((RCX + RR * math.cos(a0), 0.0, RCZ + RR * math.sin(a0)), (RCX + RR * math.cos(a1), 0.0, RCZ + RR * math.sin(a1)), 0.0013, 0.0013, 3, "GunAccent")
W.part(b, "Body")
W.mark("Muzzle", (0, 0, 0.0))
W.mark("Grip_L", (0, 0, 0))
W.report()
