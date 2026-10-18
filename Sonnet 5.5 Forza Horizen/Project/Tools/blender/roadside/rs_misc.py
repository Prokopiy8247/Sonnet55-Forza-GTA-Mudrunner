# -*- coding: utf-8 -*-
"""Roadside kit part 5: fences, stone wall, bus shelter, billboard, culvert head-walls, milestone, cairn."""

# ----------------------------------------------------------------------------------------------------------------------
# fences
# ----------------------------------------------------------------------------------------------------------------------
def _soil_mound(mb, x, y, r=0.2, h=0.07):
    mb.lathe([(r, 0.0), (r * 0.92, h * 0.35), (r * 0.5, h * 0.9), (r * 0.32, h), (0.0, h)], 'M_RS_Soil', center=(x, y), seg=10, smooth=True, cap0=True,
             col=mb.tint(0.18, (0.9, 0.85, 0.78)), row_smooth=[True, True, True, False])

def _wood_post(mb, x, y=0.0, h=1.25, w=0.12, zbot=-0.15, tint=None):
    col = mb.tint(0.14, (1.0, 0.94, 0.88))
    mb.box((x - w / 2, y - w / 2, zbot), (x + w / 2, y + w / 2, h), 'M_RS_Wood', c=0.012, col=col)
    mb.cyl((x, y, h), (x, y, h + 0.05), w * 0.72, w * 0.18, 'M_RS_Wood', seg=4, smooth=False, roll=radians(45), col=col)
    _soil_mound(mb, x, y, 0.19, 0.06)

def _fence_wood(mb, rails):
    rng = mb.rng
    _wood_post(mb, 0.0)
    for zc in rails:
        z0 = zc + rng.uniform(-0.01, 0.01)
        # rail made of two overlapping split timbers (slight vertical / yaw offsets) so it reads hand-built
        for (xa, xb) in ((0.03, 1.31), (1.19, 2.47)):
            col = mb.tint(0.18, (1.0, 0.95, 0.9))
            dz = rng.uniform(-0.008, 0.008)
            mb.obox(((xa + xb) / 2, 0.083 + (0.012 if xa > 1 else 0.0), z0 + dz), (xb - xa, 0.05, 0.095 - (0.01 if xa > 1 else 0.0)), 'M_RS_Wood',
                    (0, 0, rng.uniform(-0.35, 0.35)), c=0.011, col=col)
        for x in (0.02, 2.48):
            mb.box((x - 0.012, 0.075, z0 - 0.012), (x + 0.012, 0.094, z0 + 0.012), 'M_RS_GalvDark')   # nail heads
    mb.grime(('M_RS_Wood',), 0.4, 0.3)
    mb.hull_box((-0.06, -0.06, -0.15), (0.06, 0.11, 1.3))
    mb.hull_box((0.06, 0.05, min(rails) - 0.08), (2.5, 0.11, max(rails) + 0.08))
    return dict(length=2.5, height=1.3, rails=list(rails))

@asset('rs_fence_wood_2_5m', 'Wooden post-and-rail fence panel 2.5 m', x=322.0, ext=(-0.2, 2.5), group='fence', budget=1500, collision='box',
       pivot='segment_start', tags=['rural', 'farmland', 'forest', 'village'], scale=(1.0, 1.0),
       usage='Tile every 2.5 m along +X (post on the origin, rails run to the next post). Road side +Y. Close a run with rs_fence_wood_endpost. Rail-height variants _b / _c share the same post and envelope (mix freely).')
def b_fence_wood(mb):
    return _fence_wood(mb, (0.38, 0.74, 1.10))

@asset('rs_fence_wood_2_5m_b', 'Wooden post-and-rail fence panel 2.5 m (variant B: three low rails)', x=388.0, ext=(-0.2, 2.5), group='fence', budget=1500, collision='box',
       pivot='segment_start', tags=['rural', 'farmland', 'forest', 'village'], scale=(1.0, 1.0),
       usage='Variant of rs_fence_wood_2_5m with the rails 8 cm lower (0.30 / 0.66 / 1.02 m): same post, tiles with the base panel.')
def b_fence_wood_b(mb):
    return _fence_wood(mb, (0.30, 0.66, 1.02))

@asset('rs_fence_wood_2_5m_c', 'Wooden post-and-rail fence panel 2.5 m (variant C: two rails)', x=394.0, ext=(-0.2, 2.5), group='fence', budget=1500, collision='box',
       pivot='segment_start', tags=['rural', 'farmland', 'forest', 'village'], scale=(1.0, 1.0),
       usage='Variant of rs_fence_wood_2_5m with two rails (0.55 / 1.05 m): same post, tiles with the base panel.')
def b_fence_wood_c(mb):
    return _fence_wood(mb, (0.55, 1.05))

@asset('rs_fence_wood_endpost', 'Wooden fence end post with rail stubs', x=328.0, ext=(-0.3, 0.3), group='fence', budget=800, collision='box',
       pivot='ground_centre', tags=['rural', 'farmland', 'forest', 'village'], scale=(1.0, 1.0),
       usage='Closes the last panel of a post-and-rail run (rail stubs point to -X).')
def b_fence_wood_end(mb):
    _wood_post(mb, 0.0)
    for zc in (0.38, 0.74, 1.10):
        mb.box((-0.25, 0.05, zc - 0.045), (-0.06, 0.1, zc + 0.045), 'M_RS_Wood', c=0.011, col=mb.tint(0.16))
    mb.grime(('M_RS_Wood',), 0.4, 0.3)
    mb.hull_box((-0.06, -0.06, -0.15), (0.06, 0.11, 1.3))

@asset('rs_fence_wire_3m', 'Wire farm fence panel 3.0 m (woven mesh, wood + T posts)', x=334.0, ext=(-0.1, 3.0), group='fence', budget=1800, collision='none',
       pivot='segment_start', tags=['rural', 'farmland', 'savanna'], scale=(1.0, 1.0),
       usage='Tile every 3.0 m along +X (round wood post on the origin). No collision (livestock fence). Close with rs_fence_wire_endpost.')
def b_fence_wire(mb):
    rng = mb.rng
    H = 1.25
    mb.cyl((0, 0, -0.15), (0, 0, H), 0.058, 0.05, 'M_RS_Wood', seg=10, smooth=True, col=mb.tint(0.12, (0.95, 0.9, 0.82)))
    mb.cyl((0, 0, H), (0, 0, H + 0.04), 0.05, 0.02, 'M_RS_Wood', seg=10, smooth=True)
    _soil_mound(mb, 0.0, 0.0, 0.17, 0.05)
    # steel T-post mid span
    mb.box((1.5 - 0.02, -0.012, -0.1), (1.5 + 0.02, 0.012, 1.2), 'M_RS_GalvDark')
    mb.box((1.5 - 0.0075, -0.03, -0.1), (1.5 + 0.0075, 0.012, 1.2), 'M_RS_GalvDark')
    mb.box((1.5 - 0.012, -0.03, 1.2), (1.5 + 0.012, 0.0, 1.22), 'M_RS_GalvDark')
    zs = [0.22, 0.46, 0.70, 0.94, 1.18]
    y = 0.062
    for z in zs:
        path = []
        for i in range(13):
            t = i / 12
            path.append(Vector((3.0 * t, y + 0.0, z - 0.02 * 4 * t * (1 - t))))
        mb.tube(path, 0.0042, 'M_RS_Wire', seg=4, smooth=True)
    # vertical stays
    n = 10
    for i in range(1, n + 1):
        x = 0.3 * i
        if abs(x - 3.0) < 0.05: continue
        mb.tube([Vector((x, y, zs[0] - 0.02 * 4 * (x / 3) * (1 - x / 3))), Vector((x, y, zs[-1] - 0.02 * 4 * (x / 3) * (1 - x / 3)))], 0.003, 'M_RS_Wire', seg=4, smooth=False)
    # staples on posts
    for z in zs:
        mb.box((-0.01, 0.05, z - 0.012), (0.01, 0.07, z + 0.012), 'M_RS_GalvDark')
    return dict(length=3.0, height=1.3)

@asset('rs_fence_wire_endpost', 'Wire fence strainer end assembly (post, brace, diagonal)', x=340.0, ext=(-0.2, 1.6), group='fence', budget=1500, collision='none',
       pivot='segment_start', tags=['rural', 'farmland', 'savanna'], scale=(1.0, 1.0),
       usage='Corner / end strainer for the wire fence: strainer post on the origin, brace runs 1.5 m to +X. Rotate 180 deg to close the far end.')
def b_fence_wire_end(mb):
    H = 1.35
    mb.cyl((0, 0, -0.2), (0, 0, H), 0.1, 0.09, 'M_RS_Wood', seg=10, smooth=True, col=mb.tint(0.12, (0.93, 0.88, 0.8)))
    mb.cyl((0, 0, H), (0, 0, H + 0.06), 0.09, 0.03, 'M_RS_Wood', seg=10, smooth=True)
    mb.cyl((1.5, 0, -0.15), (1.5, 0, 1.2), 0.06, 0.055, 'M_RS_Wood', seg=10, smooth=True, col=mb.tint(0.12, (0.93, 0.88, 0.8)))
    _soil_mound(mb, 0.0, 0.0, 0.24, 0.07)
    _soil_mound(mb, 1.5, 0.0, 0.18, 0.05)
    mb.bar((0.05, 0, 0.98), (1.47, 0, 0.98), 0.08, 0.08, 'M_RS_Wood', c=0.01)
    mb.tube([Vector((0.0, 0.0, H - 0.05)), Vector((0.75, 0, 0.62)), Vector((1.5, 0.0, 0.1))], 0.005, 'M_RS_Wire', seg=5, smooth=True)
    mb.tube([Vector((0.0, 0.03, H - 0.05)), Vector((0.75, 0.03, 0.62 - 0.01)), Vector((1.5, 0.03, 0.1))], 0.005, 'M_RS_Wire', seg=5, smooth=True)
    y = 0.062
    for z in (0.22, 0.46, 0.70, 0.94, 1.18):
        mb.tube([Vector((0, y + 0.03, z)), Vector((1.5, y + 0.03, z))], 0.0042, 'M_RS_Wire', seg=4, smooth=True)

def _wall_stone(mb, course_h=0.19, hvar=0.28, lenr=(0.2, 0.52)):
    rng = mb.rng
    th = 0.55; h = 0.92; L = 2.0
    mb.box((0.04, -th / 2 + 0.05, 0.0), (L - 0.04, th / 2 - 0.05, h - 0.1), 'M_RS_Mortar')
    masonry_wall(mb, Vector((0, th / 2, 0)), 0, 0.0, L, 0.0, h - 0.17, 0.26, course_h=course_h, lenr=lenr, gap=0.014, c=0.03, prot=0.035, yaw_j=3.5, hvar=hvar)
    masonry_wall(mb, Vector((L, -th / 2, 0)), 180, 0.0, L, 0.0, h - 0.17, 0.26, course_h=course_h, lenr=lenr, gap=0.014, c=0.03, prot=0.035, yaw_j=3.5, hvar=hvar)
    for xe, ph in ((0.0, 90), (L, -90)):
        masonry_wall(mb, Vector((xe, 0, 0)), ph, -th / 2, th / 2, 0.0, h - 0.17, 0.2, course_h=0.19, lenr=(0.2, 0.3), gap=0.012, c=0.028, prot=0.03)
    # capstones (cock-and-hen) with random tilt
    x = 0.0
    while x < L - 0.05:
        Lc = min(rng.uniform(0.28, 0.46), L - x)
        if L - (x + Lc) < 0.2: Lc = L - x
        hh = rng.uniform(0.16, 0.24)
        mb.obox((x + Lc / 2, rng.uniform(-0.02, 0.02), h - 0.17 + hh / 2 - 0.02), (Lc - 0.015, th + 0.03, hh), 'M_RS_Stone', (rng.uniform(-6, 6), rng.uniform(-3, 3), rng.uniform(-3, 3)), c=0.035,
                col=mb.tint(0.14, _STONE_TINTS[rng.randrange(5)]))
        x += Lc
    mb.grime(('M_RS_Stone',), 0.3, 0.35)
    mb.hull_box((0.0, -0.3, 0.0), (L, 0.3, 0.95))
    return dict(length=L, height=0.95, thickness=0.58)

@asset('rs_wall_stone_2m', 'Dry-stone farm wall segment 2.0 m', x=346.0, ext=(0.0, 2.0), group='fence', budget=2200, collision='box',
       pivot='segment_start', tags=['rural', 'alpine', 'farmland', 'village'], scale=(1.0, 1.0),
       usage='Tile every 2.0 m along +X (alternate with rs_wall_stone_2m_b so the course pattern does not repeat); both faces are coursed rubble; centreline y=0 (0.55 m thick).')
def b_wall_stone(mb):
    return _wall_stone(mb, 0.19, 0.28, (0.2, 0.52))

@asset('rs_wall_stone_2m_b', 'Dry-stone farm wall segment 2.0 m (variant B: shifted courses)', x=380.0, ext=(0.0, 2.0), group='fence', budget=2200, collision='box',
       pivot='segment_start', tags=['rural', 'alpine', 'farmland', 'village'], scale=(1.0, 1.0),
       usage='Same envelope / end faces as rs_wall_stone_2m (tiles with it in any order) but with 4 courses of different heights and stone lengths.')
def b_wall_stone_b(mb):
    return _wall_stone(mb, 0.15, 0.36, (0.26, 0.62))

# ----------------------------------------------------------------------------------------------------------------------
# bus stop shelter
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_bus_stop_shelter', 'Bus stop shelter 3.2 x 1.5 m (steel, glass, bench, light box)', x=282.0, ext=(-1.0, 1.3), group='village', budget=3200, collision='box',
       pivot='ground_centre', tags=['village', 'town', 'highway_stop'], scale=(1.0, 1.0), nanite=False,
       usage='Village / town bus stop. Open side and bench front face +X (the road side). Glass is a separate material slot (M_RS_Glass) for a translucent UE material.')
def b_bus_shelter(mb):
    # platform slab
    mb.box((-0.95, -1.8, 0.0), (1.15, 1.8, 0.1), 'M_RS_Concrete', c=0.012)
    zf = 0.1
    # posts (steel)
    for (x, y) in ((-0.68, -1.5), (-0.68, 1.5), (0.7, -1.5), (0.7, 1.5), (-0.68, 0.0)):
        mb.box((x - 0.04, y - 0.04, zf), (x + 0.04, y + 0.04, 2.42), 'M_RS_PaintGrey', c=0.006)
    # roof: slightly arched slab swept along Y
    pts_top = [(-0.95 + 2.25 * i / 10, 2.50 + 0.07 * (1 - ((-0.95 + 2.25 * i / 10 - 0.15) / 1.1) ** 2)) for i in range(11)]
    prof = [(-(x), z - 2.5) for (x, z) in pts_top] + [(-(x), z - 2.5 - 0.075) for (x, z) in reversed(pts_top)]
    mb.sweep(prof, [Vector((0, -1.78, 2.5)), Vector((0, 1.78, 2.5))], 'M_RS_PaintGrey', True, False, up=(0, 0, 1), cap0=True, cap1=True, tri_caps=True)
    # blue stripe on the front lip + underside LED strip
    mb.box((1.255 - 0.02, -1.78, 2.40), (1.30 - 0.02, 1.78, 2.56), 'M_RS_SignBlue', c=0.004)
    mb.box((0.85, -1.2, 2.34), (0.93, 1.2, 2.40), 'M_RS_LampLens')
    # glass panes: back wall + both side walls (half depth)
    def pane(x0, y0, z0, x1, y1, z1):
        mb.box((x0, y0, z0), (x1, y1, z1), 'M_RS_Glass')
    for (ya, yb) in ((-1.46, -0.04), (0.04, 0.55)):
        pane(-0.69, ya, 0.35, -0.67, yb, 2.35)
    # lightbox advert panel replaces the right-hand back pane
    mb.box((-0.74, 0.6, 0.45), (-0.56, 1.46, 2.2), 'M_RS_PaintGrey', c=0.01)
    mb.box((-0.565, 0.66, 0.5), (-0.555, 1.4, 2.14), 'M_RS_LampLens')
    for sy in (-1, 1):
        yy = sy * 1.5
        pane(-0.66, yy - 0.01, 0.35, 0.05, yy + 0.01, 2.35)
    # horizontal frame rails at glass edges
    for z in (0.33, 2.36):
        mb.box((-0.69, -1.5, z - 0.02), (-0.66, 1.5, z + 0.02), 'M_RS_PaintGrey')
    for y in (-1.5, 1.5):
        for z in (0.33, 2.36):
            mb.box((-0.66, y - 0.02, z - 0.02), (0.06, y + 0.02, z + 0.02), 'M_RS_PaintGrey')
    # mullions
    for y in (-0.75, 0.0):
        mb.box((-0.69, y - 0.02, 0.35), (-0.66, y + 0.02, 2.36), 'M_RS_PaintGrey')
    # bench: seat slats + backrest + steel legs
    for i in range(3):
        mb.box((-0.60 + i * 0.13, -1.1, 0.44), (-0.60 + i * 0.13 + 0.115, 1.1, 0.49), 'M_RS_WoodPale', c=0.006, col=mb.tint(0.1))
    for i in range(2):
        mb.box((-0.62, -1.1, 0.62 + i * 0.16), (-0.59, 1.1, 0.62 + i * 0.16 + 0.1), 'M_RS_WoodPale', c=0.006, col=mb.tint(0.1))
    for y in (-1.05, 0.0, 1.05):
        mb.box((-0.55, y - 0.025, zf), (-0.2, y + 0.025, 0.44), 'M_RS_PaintGrey', c=0.004)
    # litter bin
    bx, by = 0.35, -1.52
    mb.lathe([(0.2, 0.1), (0.23, 0.12), (0.23, 0.78), (0.25, 0.80), (0.25, 0.86), (0.0, 0.86)], 'M_RS_PaintGrey', seg=14, center=(bx, by), smooth=True, row_smooth=[False, True, False, False, False])
    mb.box((bx - 0.07, by + 0.22, 0.5), (bx + 0.07, by + 0.235, 0.62), 'M_RS_SignWhite')
    # timetable case on the back wall + tactile strip on the platform edge
    mb.box((-0.74, -1.42, 1.15), (-0.66, -0.78, 1.95), 'M_RS_PaintGrey', c=0.008)
    mb.box((-0.665, -1.38, 1.2), (-0.655, -0.82, 1.9), 'M_RS_SignWhite')
    for i in range(6):
        mb.box((0.98, -1.5 + i * 0.5, 0.1), (1.12, -1.5 + i * 0.5 + 0.38, 0.115), 'M_RS_SignWhite', c=0.003)
    # roof gutter + down pipe on the back-left post
    mb.tube([Vector((-0.92, -1.78, 2.44)), Vector((-0.92, 1.78, 2.44))], 0.025, 'M_RS_PaintGrey', seg=8, smooth=True)
    mb.tube([Vector((-0.92, 1.76, 2.44)), Vector((-0.92, 1.76, 0.1))], 0.022, 'M_RS_PaintGrey', seg=8, smooth=True)
    # bus stop flag pole with round sign (simple bus pictogram from geometry)
    px, py = 0.55, 2.05
    mb.cyl((px, py, 0.1), (px, py, 3.2), 0.035, 0.035, 'M_RS_PaintGrey', seg=10, smooth=True)
    pl = sign_plane(px + 0.04, 2.85, py)
    mb.prism(pl, ellipse_pts(0, 0, 0.28, 0.28, 28), 0.0, 0.014, 'M_RS_SignBlue', 'M_RS_PaintGrey', 'M_RS_PaintGrey')
    mb.ring_prism(pl, ellipse_pts(0, 0, 0.28, 0.28, 28), ellipse_pts(0, 0, 0.255, 0.255, 28), 0.0, 0.02, 'M_RS_PaintGrey')
    body = rounded_poly([(-0.14, -0.08), (0.14, -0.08), (0.14, 0.09), (-0.14, 0.09)], 0.035, 3)
    mb.prism(pl, body, 0.014, 0.0175, 'M_RS_SignWhite', 'M_RS_SignWhite', 'M_RS_SignWhite')
    for xw in (-0.07, 0.0, 0.07):
        mb.prism(pl, rectpoly(xw - 0.025, 0.0, xw + 0.025, 0.065), 0.0175, 0.021, 'M_RS_SignBlue', 'M_RS_SignBlue', 'M_RS_SignBlue')
    for xw in (-0.08, 0.08):
        mb.prism(pl, ellipse_pts(xw, -0.085, 0.032, 0.032, 10), 0.014, 0.0175, 'M_RS_SignWhite', 'M_RS_SignWhite', 'M_RS_SignWhite')
    mb.hull_box((-0.95, -1.8, 0.0), (1.15, 1.8, 0.1))
    mb.hull_box((-0.8, -1.6, 0.1), (-0.55, 1.6, 2.6))
    mb.hull_box((-0.8, -1.6, 2.4), (1.3, 1.6, 2.6))
    mb.hull_box((0.45, 1.97, 0.1), (0.65, 2.13, 3.2))
    return dict(width=3.2, depth=1.5, height=3.2)

# ----------------------------------------------------------------------------------------------------------------------
# roadside billboard
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_billboard_roadside', 'Roadside billboard 6 x 3 m on two steel posts (catwalk, lamps, ladder)', x=292.0, ext=(-1.0, 1.7), group='advert', budget=6500, collision='box',
       pivot='ground_base', tags=['highway', 'town', 'all_biomes'], scale=(0.9, 1.4),
       usage='Face (material M_RS_BillboardFace, UV 0..1 across the whole face) points +X; three original ad textures (T_RS_BillboardAd_A/B/C, 2048x1024) ship in Exports/Roadside/Textures; four lamp sockets in JSON for spot lights.')
def b_billboard(mb):
    ensure_ad_textures()
    for _m in ('M_RS_BillboardFace_B', 'M_RS_BillboardFace_C'):           # alternative ad materials (not used by the mesh; kept for UE by name)
        ensure_material(_m).use_fake_user = True
    W, Hh = 6.0, 3.0
    zb = 4.3                      # bottom edge of the face
    zt = zb + Hh
    xf = 0.30                     # face front plane
    # posts (round steel tube) with base plates
    for y in (-2.0, 2.0):
        mb.box((-0.35, y - 0.35, 0.0), (0.35, y + 0.35, 0.05), 'M_RS_GalvDark', c=0.006)
        for sx in (-1, 1):
            for sy in (-1, 1):
                hexbolt(mb, (sx * 0.27, y + sy * 0.27, 0.05), (0, 0, 1), r=0.022, ln=0.04, wash=0.045)
        mb.cyl((0, y, 0.05), (0, y, zt + 0.15), 0.19, 0.17, 'M_RS_GalvSteel', seg=14, smooth=True)
        mb.cyl((0, y, 0.05), (0, y, 0.45), 0.24, 0.2, 'M_RS_GalvDark', seg=14, smooth=True)
    # backing structure: two horizontal I-beams + vertical ribs
    for z in (zb + 0.45, zt - 0.45):
        mb.box((-0.22, -3.0, z - 0.1), (0.22, 3.0, z + 0.1), 'M_RS_GalvDark', c=0.006)
    for i in range(7):
        y = -2.75 + i * 0.92
        mb.box((0.18, y - 0.04, zb + 0.1), (xf - 0.03, y + 0.04, zt - 0.1), 'M_RS_GalvDark')
    # diagonal braces to the posts
    for y in (-2.0, 2.0):
        mb.bar((-0.12, y, 2.8), (-0.12, y * 1.0 + (0.0), zb + 0.4), 0.1, 0.1, 'M_RS_GalvDark')
    # frame (4 boxy bars) + back skin
    mb.box((xf - 0.03, -W / 2, zb), (xf + 0.03, W / 2, zt), 'M_RS_GalvSteel')
    fw = 0.17
    mb.box((xf - 0.05, -W / 2 - fw, zb - fw), (xf + 0.14, W / 2 + fw, zb), 'M_RS_GalvDark', c=0.012)
    mb.box((xf - 0.05, -W / 2 - fw, zt), (xf + 0.14, W / 2 + fw, zt + fw), 'M_RS_GalvDark', c=0.012)
    mb.box((xf - 0.05, -W / 2 - fw, zb), (xf + 0.14, -W / 2, zt), 'M_RS_GalvDark', c=0.012)
    mb.box((xf - 0.05, W / 2, zb), (xf + 0.14, W / 2 + fw, zt), 'M_RS_GalvDark', c=0.012)
    # the face: thin closed slab proud of the skin; its +X faces carry UV 0..1 across the whole face (texture swap in UE)
    mb.box((xf + 0.031, -W / 2, zb), (xf + 0.037, W / 2, zt), {'+x': 'M_RS_BillboardFace', 'all': 'M_RS_GalvSteel'})
    idx = mb.mats.index('M_RS_BillboardFace')
    for f in mb.bm.faces:
        if f.material_index == idx:
            for l in f.loops:
                p = l.vert.co
                l[mb.uvl].uv = ((p.y + W / 2) / W, (p.z - zb) / Hh)
    # catwalk in front of the lower edge with grating, kick plate and handrail
    cx0, cx1 = xf + 0.14, xf + 0.98
    mb.box((cx0, -3.1, zb - 0.28), (cx1, 3.1, zb - 0.24), 'M_RS_Grating')
    for y in (-3.1, -1.5, 0.0, 1.5, 3.1):
        mb.box((cx0, y - 0.03, zb - 0.38), (cx1, y + 0.03, zb - 0.28), 'M_RS_GalvDark')
    mb.box((cx1 - 0.03, -3.1, zb - 0.24), (cx1, 3.1, zb - 0.1), 'M_RS_GalvDark')
    for y in (-3.1, -1.55, 0.0, 1.55, 3.1):
        mb.cyl((cx1 - 0.02, y, zb - 0.24), (cx1 - 0.02, y, zb + 0.78), 0.022, 0.022, 'M_RS_GalvSteel', seg=8, smooth=True)
    mb.tube([Vector((cx1 - 0.02, -3.1, zb + 0.78)), Vector((cx1 - 0.02, 3.1, zb + 0.78))], 0.025, 'M_RS_GalvSteel', seg=8, smooth=True)
    mb.tube([Vector((cx1 - 0.02, -3.1, zb + 0.4)), Vector((cx1 - 0.02, 3.1, zb + 0.4))], 0.018, 'M_RS_GalvSteel', seg=8, smooth=True)
    # ladder on the right post (from ground to the catwalk)
    xl = 0.0 + 0.30
    yl = 2.62
    for yy in (yl - 0.2, yl + 0.2):
        mb.box((xl - 0.02, yy - 0.02, 0.4), (xl + 0.02, yy + 0.02, zb - 0.24), 'M_RS_GalvDark')
    z = 0.7
    while z < zb - 0.4:
        mb.cyl((xl, yl - 0.2, z), (xl, yl + 0.2, z), 0.014, 0.014, 'M_RS_GalvDark', seg=6, smooth=True)
        z += 0.3
    # lamp arms along the top edge pointing at the face (4)
    for i, y in enumerate((-2.25, -0.75, 0.75, 2.25)):
        a = Vector((xf + 0.05, y, zt + fw))
        b = Vector((xf + 0.95, y, zt + fw + 0.52))
        mb.tube([a, Vector((xf + 0.55, y, zt + fw + 0.52)), b], 0.022, 'M_RS_GalvSteel', seg=6, smooth=True)
        mb.obox((xf + 1.0, y, zt + fw + 0.5), (0.36, 0.3, 0.12), 'M_RS_PaintGrey', (0, 22, 0), c=0.02)
        mb.obox((xf + 1.0 - 0.02, y, zt + fw + 0.5 - 0.06), (0.3, 0.24, 0.01), 'M_RS_LampLens', (0, 22, 0))
        mb.sockets['spot_%d' % i] = (xf + 1.0, y, zt + fw + 0.45)
    mb.grime(('M_RS_GalvDark',), 1.0, 0.0)
    mb.hull_cyl((0, -2.0, 0), (0, -2.0, zt), 0.22, 8)
    mb.hull_cyl((0, 2.0, 0), (0, 2.0, zt), 0.22, 8)
    mb.hull_box((-0.2, -3.2, zb - 0.4), (1.0, 3.2, zt + 0.2))
    return dict(face_width=W, face_height=Hh, face_bottom=zb,
                ad_textures=[dict(material=m, file='Textures/' + AD_FILES[k], size=list(AD_SIZE)) for m, k in AD_MATERIALS.items()],
                ad_note='3 original generic ads (SUNPEAK FUEL / LAKEVIEW INN / ROADSIDE DINER) 2048x1024, UV 0..1 over the face; the mesh carries M_RS_BillboardFace (ad A), assign the other textures per UE material instance')

# ----------------------------------------------------------------------------------------------------------------------
# culvert head-walls
# ----------------------------------------------------------------------------------------------------------------------
def _ray_poly_rect(cx, cz, hw0, hw1, hh0, hh1, n, start=0.0):
    """points on an axis-aligned rectangle [cx-hw0,cx+hw1] x [cz-hh0,cz+hh1] cast from (cx,cz) at n equally spaced angles"""
    pts = []
    for i in range(n):
        a = radians(start + 360.0 * i / n)
        dx, dz = cos(a), sin(a)
        tx = (hw1 if dx > 0 else hw0) / abs(dx) if abs(dx) > 1e-9 else 1e9
        tz = (hh1 if dz > 0 else hh0) / abs(dz) if abs(dz) > 1e-9 else 1e9
        t = min(tx, tz)
        pts.append((cx + dx * t, cz + dz * t))
    return pts

def _wing_hulls(mb, plw, steps, t):
    """one closed convex hull per wing-wall step (rectangle in the wing plane extruded +-t): never a flat quad"""
    for (u0, u1, v1) in steps:
        mb.hull_prism(plw, [(u0, 0.0), (u1, 0.0), (u1, v1), (u0, v1)], -t, t)

def _weep_hole(mb, y, z, r=0.05):
    pl = Plane((0.0, y, z), (0, 1, 0), (0, 0, 1))
    mb.ring_prism(pl, ellipse_pts(0, 0, r, r, 8), ellipse_pts(0, 0, r * 0.62, r * 0.62, 8), 0.0, 0.014, 'M_RS_ConcreteDark', 'M_RS_ConcreteDark', 'M_RS_ConcreteDark')
    mb.prism(pl, ellipse_pts(0, 0, r * 0.6, r * 0.6, 8), 0.0, 0.003, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack', flat=True)

@asset('rs_culvert_headwall_a', 'Culvert head-wall A (round pipe, wing walls)', x=300.0, ext=(-0.6, 2.6), group='drainage', budget=3000, collision='box',
       pivot='ground_base', tags=['all_biomes', 'road_embankment', 'stream'], scale=(0.9, 1.3),
       usage='Where a stream passes under an embankment. Opening faces +X; wing walls flare towards +X; body extends 0.4 m into -X. Collision: 4 hulls frame the open pipe mouth + one closed wedge hull per wing wall.')
def b_culvert_a(mb):
    rng = mb.rng
    N = 32
    t = 0.4
    cz = 0.78
    r = 0.62
    pl = Plane((0, 0, cz), (0, 1, 0), (0, 0, 1))           # N = +X
    hole = ellipse_pts(0, 0, r, r, N)
    outer = _ray_poly_rect(0, 0, 1.5, 1.5, cz, 1.72 - cz, N)
    mb.ring_prism(pl, outer, hole, -t, 0.0, 'M_RS_Concrete', 'M_RS_Concrete', 'M_RS_Concrete')
    # dark plug deep inside the pipe
    mb.prism(pl, ellipse_pts(0, 0, r - 0.004, r - 0.004, N), -t - 0.03, -t + 0.002, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack', smooth_side=True)
    # protruding pipe socket with a chamfered collar ring and a rolled lip
    mb.ring_prism(pl, ellipse_pts(0, 0, r + 0.1, r + 0.1, N), hole, 0.0, 0.5, 'M_RS_ConcreteDark', 'M_RS_ConcreteDark', 'M_RS_ConcreteDark', smooth_side=True)
    mb.ring_prism(pl, ellipse_pts(0, 0, r + 0.14, r + 0.14, N), ellipse_pts(0, 0, r + 0.1, r + 0.1, N), 0.34, 0.46, 'M_RS_ConcreteDark', smooth_side=True)
    mb.ring_prism(pl, ellipse_pts(0, 0, r + 0.12, r + 0.12, N), ellipse_pts(0, 0, r + 0.1, r + 0.1, N), 0.46, 0.5, 'M_RS_ConcreteDark', smooth_side=True)
    mb.ring_prism(pl, ellipse_pts(0, 0, r + 0.16, r + 0.16, N), ellipse_pts(0, 0, r + 0.1, r + 0.1, N), 0.0, 0.05, 'M_RS_ConcreteDark', smooth_side=True)   # mortar fillet at the wall
    # coping with a drip step underneath + toe
    mb.box((-t - 0.04, -1.56, 1.72), (0.05, 1.56, 1.8), 'M_RS_Concrete', c=0.016)
    mb.box((-t, -1.52, 1.68), (0.0, 1.52, 1.72), 'M_RS_ConcreteDark')
    mb.box((-0.05, -1.5, 0.0), (0.1, 1.5, 0.28), 'M_RS_ConcreteDark', c=0.01)
    # belt course above the pipe mouth (casting joint) and cast-in details on the wall face
    mb.box((0.0, -1.5, 1.50), (0.022, 1.5, 1.57), 'M_RS_Concrete', c=0.006)
    for y in (-1.15, -0.9, 0.9, 1.15):
        _weep_hole(mb, y, 0.30)
    for y in (-1.3, -0.95, 0.95, 1.3):
        for z in (0.62, 1.12):
            mb.prism(Plane((0.0, y, z), (0, 1, 0), (0, 0, 1)), rectpoly(-0.018, -0.018, 0.018, 0.018), 0.0, 0.0016, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack', flat=True)
    pp = Plane((0.012, -1.12, 1.18), (0, 1, 0), (0, 0, 1))      # ID plate
    mb.prism(pp, rounded_poly([(-0.17, -0.1), (0.17, -0.1), (0.17, 0.1), (-0.17, 0.1)], 0.02, 3), -0.012, 0.0, 'M_RS_GalvSteel', 'M_RS_GalvSteel', 'M_RS_GalvSteel')
    draw_text(mb, pp, 'C1', 0.0, 0.0, 0.11, 'M_RS_PaintBlack', sw=0.016, w0=0.0, w1=0.0014)
    # wing walls flaring 35 degrees
    wings = []
    for sy in (-1, 1):
        a = radians(35)
        d = Vector((cos(a), sy * sin(a), 0))
        plw = Plane((0, sy * 1.5, 0), d, (0, 0, 1))
        wings.append(plw)
        poly = [(0.0, 0.0), (1.55, 0.0), (1.55, 0.6), (0.0, 1.72)]
        mb.prism(plw, poly, -0.15, 0.15, 'M_RS_Concrete', 'M_RS_Concrete', 'M_RS_Concrete')
        mb.prism(plw, [(0.0, 1.72), (1.55, 0.6), (1.55, 0.67), (0.0, 1.79)], -0.19, 0.19, 'M_RS_Concrete', 'M_RS_Concrete', 'M_RS_Concrete')
    # apron slab
    mb.box((0.0, -1.35, -0.02), (1.7, 1.35, 0.12), 'M_RS_ConcreteDark', c=0.02)
    # rebar stubs / lifting eyes on the coping
    for y in (-1.0, 1.0):
        mb.torus((-0.18, y, 1.82), 0.045, 0.01, 'M_RS_Rust', nmaj=8, nmin=5, axis='Y', smooth=True)
    mb.grime(('M_RS_Concrete', 'M_RS_ConcreteDark'), 0.7, 0.45)
    # collision: frame around the open pipe mouth (the square opening 1.24 m is slightly larger than the round bore)
    mb.hull_box((-0.4, -1.55, 0.0), (0.05, -0.62, 1.8))
    mb.hull_box((-0.4, 0.62, 0.0), (0.05, 1.55, 1.8))
    mb.hull_box((-0.4, -0.62, cz + r), (0.05, 0.62, 1.8))
    mb.hull_box((-0.4, -0.62, 0.0), (0.05, 0.62, cz - r))
    for plw in wings:
        mb.hull_prism(plw, [(0.0, 0.0), (1.55, 0.0), (1.55, 0.6), (0.0, 1.72)], -0.15, 0.15)
    return dict(opening='round 1.24 m', width=3.0, height=1.8)

@asset('rs_culvert_headwall_b', 'Culvert head-wall B (box opening, trash rack, stepped wings)', x=307.0, ext=(-0.6, 2.4), group='drainage', budget=3200, collision='box',
       pivot='ground_base', tags=['all_biomes', 'road_embankment', 'stream', 'town'], scale=(0.9, 1.3),
       usage='Larger box culvert with trash rack. Opening faces +X; straight stepped wing walls; body extends 0.5 m into -X. Collision: hulls frame the opening, one closed hull per wing-wall step, thin hull for the rack, one per guard post.')
def b_culvert_b(mb):
    N = 36
    t = 0.5
    cz = 0.72
    pl = Plane((0, 0, cz), (0, 1, 0), (0, 0, 1))
    inner = _ray_poly_rect(0, 0, 0.9, 0.9, 0.62, 0.62, N, start=0.0)
    outer = _ray_poly_rect(0, 0, 1.9, 1.9, cz, 2.05 - cz, N, start=0.0)
    mb.ring_prism(pl, outer, inner, -t, 0.0, 'M_RS_Concrete', 'M_RS_Concrete', 'M_RS_Concrete')
    mb.prism(pl, rectpoly(-0.89, -0.61, 0.89, 0.61), -t - 0.03, -t + 0.002, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack')
    # lintel beam + parapet kerb
    mb.box((-t - 0.05, -1.95, 1.94), (0.08, 1.95, 2.16), 'M_RS_Concrete', c=0.015)
    mb.box((-t - 0.05, -1.95, 0.0), (0.05, 1.95, 0.12), 'M_RS_ConcreteDark', c=0.01)
    # guard posts + steel tube rail on top
    for y in (-1.8, -0.6, 0.6, 1.8):
        mb.box((-0.2, y - 0.09, 2.16), (0.0, y + 0.09, 2.62), 'M_RS_Concrete', c=0.015)
    mb.tube([Vector((-0.1, -1.8, 2.5)), Vector((-0.1, 1.8, 2.5))], 0.035, 'M_RS_GalvSteel', seg=10, smooth=True)
    # weep holes + form-tie marks on the face
    for y in (-1.45, -1.2, 1.2, 1.45):
        _weep_hole(mb, y, 0.34, 0.045)
    for y in (-1.5, -1.25, 1.25, 1.5):
        for z in (0.8, 1.4):
            mb.prism(Plane((0.0, y, z), (0, 1, 0), (0, 0, 1)), rectpoly(-0.018, -0.018, 0.018, 0.018), 0.0, 0.0016, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack', flat=True)
    # trash rack: vertical bars + two cross bars
    xr = 0.14
    for i in range(9):
        y = -0.8 + i * 0.2
        mb.box((xr - 0.012, y - 0.012, 0.12), (xr + 0.012, y + 0.012, 1.34), 'M_RS_Rust', col=mb.tint(0.2))
    for z in (0.4, 1.0):
        mb.box((xr - 0.02, -0.9, z - 0.02), (xr + 0.02, 0.9, z + 0.02), 'M_RS_Rust')
    for y in (-0.9, 0.9):
        mb.box((xr - 0.03, y - 0.03, 0.1), (xr + 0.03, y + 0.03, 1.36), 'M_RS_Rust')
    # stepped straight wing walls (angled 15 deg)
    wsteps = [(0.0, 0.5, 1.9), (0.5, 1.0, 1.4), (1.0, 1.5, 0.95), (1.5, 2.0, 0.5)]
    wings = []
    for sy in (-1, 1):
        a = radians(15)
        d = Vector((cos(a), sy * sin(a), 0))
        plw = Plane((0, sy * 1.9, 0), d, (0, 0, 1))
        wings.append(plw)
        poly = [(0.0, 0.0), (2.0, 0.0), (2.0, 0.5), (1.5, 0.5), (1.5, 0.95), (1.0, 0.95), (1.0, 1.4), (0.5, 1.4), (0.5, 1.9), (0.0, 1.9)]
        mb.prism(plw, poly, -0.15, 0.15, 'M_RS_Concrete', 'M_RS_Concrete', 'M_RS_Concrete')
    # apron + energy blocks
    mb.box((0.0, -1.7, -0.02), (1.9, 1.7, 0.12), 'M_RS_ConcreteDark', c=0.02)
    for y in (-1.1, -0.3, 0.5, 1.3):
        mb.box((1.5, y - 0.15, 0.12), (1.78, y + 0.15, 0.36), 'M_RS_Concrete', c=0.02)
    mb.grime(('M_RS_Concrete', 'M_RS_ConcreteDark'), 0.7, 0.45)
    # collision
    mb.hull_box((-0.5, -1.95, 0.0), (0.08, -0.9, 2.2))
    mb.hull_box((-0.5, 0.9, 0.0), (0.08, 1.95, 2.2))
    mb.hull_box((-0.5, -0.9, cz + 0.62), (0.08, 0.9, 2.2))
    mb.hull_box((-0.5, -0.9, 0.0), (0.08, 0.9, cz - 0.62))
    mb.hull_box((0.11, -0.9, 0.10), (0.17, 0.9, 1.36))                      # trash rack
    for plw in wings:
        _wing_hulls(mb, plw, wsteps, 0.15)
    for y in (-1.8, -0.6, 0.6, 1.8):
        mb.hull_box((-0.2, y - 0.09, 2.16), (0.0, y + 0.09, 2.62))
    return dict(opening='box 1.8 x 1.24 m', width=3.8, height=2.2)

# ----------------------------------------------------------------------------------------------------------------------
# mountain milestone + cairn
# ----------------------------------------------------------------------------------------------------------------------
def _pebble(mb, c, rx, ry, rz, mat, yaw, seg=9, rings=3, col=None, jit=0.12, tilt=(0.0, 0.0)):
    rng = mb.rng
    verts = mb.dome(c, 1.0, mat, seg=seg, rings=rings, zscale=rz, hemi=False, smooth=False, xyscale=(rx, ry), col=col)
    cc = Vector(c)
    R = Rz(yaw) @ Matrix.Rotation(radians(tilt[0]), 4, 'X') @ Matrix.Rotation(radians(tilt[1]), 4, 'Y')
    for ring in verts:
        for v in ring:
            p = v.co - cc
            p = Vector((p.x * (1 + rng.uniform(-jit, jit)), p.y * (1 + rng.uniform(-jit, jit)), p.z * (1 + rng.uniform(-jit * 0.6, jit * 0.6))))
            v.co = cc + (R @ p).to_3d()

_CAIRN_TINTS = [(1.0, 1.0, 1.0), (0.80, 0.78, 0.76), (1.12, 1.03, 0.90), (0.84, 0.90, 0.97), (1.06, 0.90, 0.82), (0.68, 0.68, 0.70), (0.95, 0.88, 0.80)]

@asset('rs_cairn_stack', 'Mountain cairn (stacked flat stones, 1.1 m)', x=312.0, ext=(-0.6, 0.6), group='mountain', budget=2400, collision='convex',
       tags=['alpine', 'mountain_road', 'desert', 'scrub'], scale=(0.7, 1.5),
       usage='Trail / pass marker on mountain roads. 8 balanced stones (angular slabs alternating with rounded river stones, per-stone colour) + angular chips; convex hull collision.')
def b_cairn(mb):
    rng = mb.rng
    levels = [(0.44, 0.33, 0.14, 'slab'), (0.40, 0.32, 0.17, 'round'), (0.34, 0.27, 0.12, 'slab'), (0.29, 0.23, 0.15, 'round'),
              (0.24, 0.20, 0.11, 'slab'), (0.19, 0.16, 0.12, 'round'), (0.14, 0.12, 0.09, 'slab'), (0.10, 0.09, 0.09, 'round')]
    z = 0.0
    cx = cy = 0.0
    for i, (a, b, h, kind) in enumerate(levels):
        cx += rng.uniform(-0.06, 0.06); cy += rng.uniform(-0.06, 0.06)
        tint = mb.tint(0.07, _CAIRN_TINTS[rng.randrange(len(_CAIRN_TINTS))])
        if kind == 'slab':
            # angular slab: frustum with the chamfered face turned to +Z (rot X 90 maps local +y to world +z)
            mb.stone((cx, cy, z + h * 0.5), (2 * a, h, 2 * b), 'M_RS_Stone', rot=(90 + rng.uniform(-5, 5), rng.uniform(-5, 5), rng.uniform(0, 360)),
                     bevel=min(0.07, a * 0.3), col=tint, jit=0.012)
            z += h * 0.96
        else:
            _pebble(mb, (cx, cy, z + h * 0.78), a, b, h, 'M_RS_Stone', rng.uniform(0, 360), seg=9, rings=3, col=tint, jit=0.2,
                    tilt=(rng.uniform(-7, 7), rng.uniform(-7, 7)))
            z += h * 1.38
    for i in range(9):
        a = rng.uniform(0, 6.28); d = rng.uniform(0.38, 0.62)
        s_ = rng.uniform(0.05, 0.13)
        tint = mb.tint(0.08, _CAIRN_TINTS[rng.randrange(len(_CAIRN_TINTS))])
        if i % 2 == 0:
            mb.stone((cos(a) * d, sin(a) * d, s_ * 0.4), (s_ * rng.uniform(1.0, 1.6), s_, s_ * rng.uniform(0.8, 1.3)), 'M_RS_Stone',
                     rot=(rng.uniform(0, 360), rng.uniform(0, 360), rng.uniform(0, 360)), bevel=s_ * 0.22, col=tint, jit=0.008)
        else:
            _pebble(mb, (cos(a) * d, sin(a) * d, s_ * 0.5), s_ * rng.uniform(0.9, 1.4), s_, s_ * 0.7, 'M_RS_Stone', rng.uniform(0, 360), seg=8, rings=2,
                    col=tint, jit=0.22, tilt=(rng.uniform(-10, 10), rng.uniform(-10, 10)))
    mb.grime(('M_RS_Stone',), 0.25, 0.3)
    mb.hull_pts([Vector((0.5 * cos(a), 0.37 * sin(a), 0.0)) for a in [i * pi / 5 for i in range(10)]] + [Vector((0.28, 0.15, 0.55)), Vector((-0.28, -0.15, 0.55)), Vector((0.1, 0.1, 1.15)), Vector((-0.1, -0.1, 1.15))])
    return dict(height=1.15)

@asset('rs_milestone_stone', 'Milestone (granite slab with painted number plate)', x=317.0, ext=(-0.4, 0.4), group='mountain', budget=1800, collision='box',
       tags=['alpine', 'mountain_road', 'village', 'rural'], scale=(0.9, 1.2),
       usage='Distance marker along mountain / rural roads; number plate faces +X.')
def b_milestone(mb):
    col = mb.tint(0.08)
    mb.box((-0.24, -0.15, 0.0), (0.24, 0.15, 0.12), 'M_RS_Stone', c=0.02, col=col)
    mb.box((-0.2, -0.1, 0.12), (0.2, 0.1, 0.72), 'M_RS_Stone', c=0.018, col=col)
    mb.dome((0, 0, 0.72), 1.0, 'M_RS_Stone', seg=12, rings=3, zscale=0.1, hemi=True, smooth=True, xyscale=(0.2, 0.1), col=col)
    pl = Plane((0.2, 0.0, 0.0), (0, 1, 0), (0, 0, 1))
    mb.prism(pl, rounded_poly([(-0.145, 0.3), (0.145, 0.3), (0.145, 0.66), (-0.145, 0.66)], 0.03, 3), -0.004, 0.01, 'M_RS_PaintWhite', 'M_RS_PaintWhite', 'M_RS_PaintWhite')
    draw_text(mb, pl, '12', 0.0, 0.5, 0.17, 'M_RS_PaintBlack', sw=0.026, w0=0.01, w1=0.0114)
    draw_text(mb, pl, 'KM', 0.0, 0.355, 0.06, 'M_RS_PaintBlack', sw=0.008, w0=0.01, w1=0.0114)
    mb.box((0.19, -0.1, 0.69), (0.215, 0.1, 0.715), 'M_RS_PaintRed')
    mb.grime(('M_RS_Stone',), 0.3, 0.4)
    mb.hull_box((-0.24, -0.15, 0.0), (0.24, 0.15, 0.8))
    return dict(height=0.8)
