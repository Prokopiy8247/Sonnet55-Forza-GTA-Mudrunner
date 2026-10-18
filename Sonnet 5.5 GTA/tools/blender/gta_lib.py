"""
gta_lib.py - shared Blender helper library for the Halcyon Bay (Godot GTA) asset pipeline.

LOAD IT inside Blender through the verified MCP connection (localhost:9890) with:

    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals())

Everything is data-API / bmesh based (no selection-dependent bpy.ops except export + armature edit mode), so several
agents can work in the same Blender session at once as long as they obey the RULES below.

RULES FOR PARALLEL AGENTS (one shared live Blender):
  * Only touch YOUR objects/collections: every object name starts with your asset prefix (e.g. "veh_sedan_*").
  * Build each asset in your own workshop slot (workshop(lane, index)), far from other agents; export resets the root to origin.
  * Never hide/delete/rename objects you did not create. Never change scene-wide settings (units, frame range, render engine).
  * Do not leave the Blender UI in edit mode; always return to object mode.
  * Rebuild idempotently: call clear_asset("prefix_") first, then rebuild.
  * Save the master file only via save_master() (it is safe to call often).

CONVENTIONS (see docs/ARCHITECTURE.md section 7 for the full list):
  * Units: metres. Blender axes: +X right, +Y FORWARD (front of vehicles/weapons/characters), +Z up.
    After GLB export (+Y up) the model faces -Z in Godot, which is Godot's forward.
  * Origins: vehicles = ground contact point at the centre of the wheelbase (Z=0 is the tyre bottom);
    characters = between the feet on the ground; weapons = primary grip point, barrel along +Y;
    buildings/props/nature = centre of the footprint at ground level.
  * Names: lowercase asset ids ("sedan"), node names inside GLB use Godot-friendly names (Body, Wheel_FL, Muzzle...).
  * Flat shaded low-poly, shared named materials (std_mat), no image textures (colours only) unless a task says otherwise.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix, Euler, Quaternion

PROJECT = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta"
MODELS = PROJECT + r"\gta\generated\models"
MASTER = PROJECT + r"\GodotSonnet5.5GTA.blend"

# ----------------------------------------------------------------------------------------------------------------
# Palette ("Halcyon": sun-bleached pastels + deep asphalt + neon accents). sRGB hex values.
# ----------------------------------------------------------------------------------------------------------------
PAL = {
    # neutrals
    "asphalt": "#2b2e33", "concrete": "#cfc8bb", "concrete_dark": "#9a958c", "plaster": "#e6d5b8",
    "white": "#f2f0ea", "offwhite": "#e6e2d6", "black": "#15171a", "charcoal": "#2a2d33",
    "steel": "#8d96a0", "steel_dark": "#4b525b", "chrome": "#c9d1d9", "rubber": "#1b1c1f",
    # pastels / accents
    "coral": "#e8795f", "teal": "#2f9c95", "mustard": "#e0b04a", "dusty_blue": "#5b7fa6", "sage": "#7ea286",
    "plum": "#7b4b7a", "brick": "#a4553f", "navy": "#25324d", "sky": "#8fc6e8", "peach": "#f0b290",
    # signal colours
    "magenta": "#ff3d9a", "cyan": "#34e0ff", "amber": "#ffb347", "red": "#d93a3a", "green": "#4f9d52",
    "yellow": "#f2cf3a", "orange": "#ee8a2b", "blue": "#2f6fd6",
    # nature
    "grass": "#6fa24a", "leaf_dark": "#3f7a46", "leaf_light": "#86b04f", "wood": "#8a5a3b", "bark": "#5f4330",
    "sand": "#e3cf9f", "rock": "#8a8579", "water": "#1b6f8a",
    # skin & hair
    "skin_1": "#f1c9a5", "skin_2": "#d9a77c", "skin_3": "#b57e57", "skin_4": "#8a5a3c", "skin_5": "#5e3b27",
    "hair_black": "#1a1512", "hair_brown": "#4a3022", "hair_blond": "#d6b46a", "hair_red": "#a8482a", "hair_grey": "#a9a39a",
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(color, alpha=1.0):
    """'#rrggbb' | palette key | (r,g,b) sRGB 0..1  ->  linear RGBA tuple for shader inputs."""
    if isinstance(color, str):
        h = PAL.get(color, color).lstrip("#")
        r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    else:
        r, g, b = color[0], color[1], color[2]
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


# ----------------------------------------------------------------------------------------------------------------
# Materials (idempotent by name). Principled BSDF only, glTF-exporter friendly.
# ----------------------------------------------------------------------------------------------------------------
def mat(name, color="#808080", rough=0.65, metal=0.0, emit=None, emit_strength=3.0, alpha=None):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        nt.nodes.clear()
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Emission Color" in bsdf.inputs:
        if emit:
            bsdf.inputs["Emission Color"].default_value = rgba(emit)
            bsdf.inputs["Emission Strength"].default_value = emit_strength
        else:
            bsdf.inputs["Emission Color"].default_value = (0, 0, 0, 1)
            bsdf.inputs["Emission Strength"].default_value = 0.0
    if alpha is not None and alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
        try:
            m.blend_method = "BLEND"
        except Exception:
            pass
    m.diffuse_color = rgba(color)
    return m


# Standard shared material names. Godot swaps some of these at runtime BY NAME (paint, lights, glass, windows...).
STD = {
    "Paint":       dict(color="#c43a3a", rough=0.35, metal=0.25),          # primary vehicle paint (Godot overrides colour)
    "Paint2":      dict(color="#22252b", rough=0.45, metal=0.15),          # secondary / roof / stripes
    "Glass":       dict(color="#16222e", rough=0.05, metal=0.0, alpha=0.45),
    "Chrome":      dict(color="#c9d1d9", rough=0.12, metal=1.0),
    "Trim":        dict(color="#1c1e22", rough=0.8),                        # black plastic / bumpers / grilles
    "Tire":        dict(color="#1b1c1f", rough=0.95),
    "Rim":         dict(color="#aab3bd", rough=0.3, metal=0.8),
    "Interior":    dict(color="#2e3138", rough=0.9),
    "LightHead":   dict(color="#fff4d6", rough=0.2, emit="#fff1c9", emit_strength=4.0),
    "LightTail":   dict(color="#8c1414", rough=0.3, emit="#ff2a2a", emit_strength=1.5),
    "LightAmber":  dict(color="#c9731a", rough=0.3, emit="#ffa02e", emit_strength=2.0),
    "LightBlue":   dict(color="#1b3a8c", rough=0.3, emit="#2f6fff", emit_strength=3.0),
    "LightRed":    dict(color="#8c1414", rough=0.3, emit="#ff2a2a", emit_strength=3.0),
    "Plate":       dict(color="#e9e6dc", rough=0.5),
    "Metal":       dict(color="#8d96a0", rough=0.45, metal=0.9),
    "MetalDark":   dict(color="#4b525b", rough=0.5, metal=0.8),
    "Concrete":    dict(color="#cfc8bb", rough=0.95),
    "Wood":        dict(color="#8a5a3b", rough=0.85),
    "Gun":         dict(color="#2a2d33", rough=0.45, metal=0.7),
    "GunLight":    dict(color="#8d96a0", rough=0.4, metal=0.8),
    "Grip":        dict(color="#1c1e22", rough=0.9),
    "Skin":        dict(color="#d9a77c", rough=0.8),
    "Hair":        dict(color="#4a3022", rough=0.8),
    "Shirt":       dict(color="#5b7fa6", rough=0.9),
    "Pants":       dict(color="#25324d", rough=0.9),
    "Shoes":       dict(color="#1b1c1f", rough=0.85),
    "Accent":      dict(color="#e0b04a", rough=0.8),
    "Leaf":        dict(color="#4f8a4a", rough=0.9),
    "LeafLight":   dict(color="#86b04f", rough=0.9),
    "Bark":        dict(color="#5f4330", rough=0.95),
    "Rock":        dict(color="#8a8579", rough=0.95),
    "Sand":        dict(color="#e3cf9f", rough=0.98),
    "Water":       dict(color="#1b6f8a", rough=0.1, alpha=0.8),
    "Neon":        dict(color="#ff3d9a", rough=0.3, emit="#ff3d9a", emit_strength=5.0),
    "NeonCyan":    dict(color="#34e0ff", rough=0.3, emit="#34e0ff", emit_strength=5.0),
    # Godot REPLACES these by name with its own shader materials (procedural windows, signal lights, ...):
    "Window":      dict(color="#243447", rough=0.1, metal=0.0),             # building windows (Godot: lit-at-night shader)
    "WallA":       dict(color="#e6d5b8", rough=0.95),
    "WallB":       dict(color="#e8795f", rough=0.95),
    "WallC":       dict(color="#5b7fa6", rough=0.95),
    "WallD":       dict(color="#cfc8bb", rough=0.95),
    "Roof":        dict(color="#9a958c", rough=0.95),
    "RoofTile":    dict(color="#a4553f", rough=0.9),
    "SignalRed":   dict(color="#401010", rough=0.3, emit="#ff2a2a", emit_strength=0.0),
    "SignalAmber": dict(color="#403010", rough=0.3, emit="#ffb347", emit_strength=0.0),
    "SignalGreen": dict(color="#104020", rough=0.3, emit="#3dff7a", emit_strength=0.0),
    "LampGlow":    dict(color="#fff0c8", rough=0.3, emit="#ffd9a0", emit_strength=3.0),
}


def std_mat(name, **override):
    """Get/create one of the shared standard materials (STD) or a custom one when override is given."""
    spec = dict(STD.get(name, dict(color="#808080")))
    spec.update(override)
    return mat(name, **spec)


def ensure_std_mats(names=None):
    for n in (names or STD.keys()):
        std_mat(n)


# ----------------------------------------------------------------------------------------------------------------
# Collections & workshop slots
# ----------------------------------------------------------------------------------------------------------------
def coll(path):
    """'GTA_GODOT/Vehicles/Cars' -> nested collection (created on demand, linked below the scene collection)."""
    parent = bpy.context.scene.collection
    c = parent
    for part in path.split("/"):
        nxt = None
        for ch in c.children:
            if ch.name == part:
                nxt = ch
                break
        if nxt is None:
            nxt = bpy.data.collections.get(part)
            if nxt is None:
                nxt = bpy.data.collections.new(part)
            if nxt.name not in [x.name for x in c.children]:
                c.children.link(nxt)
        c = nxt
    return c


def workshop(lane, index, spacing=40.0):
    """World position of an agent's private workshop slot: lane = agent number (0..), index = asset number."""
    return Vector((index * spacing, 600.0 + lane * 120.0, 0.0))


def clear_asset(prefix):
    """Delete every object (and orphaned mesh) whose name starts with prefix. Safe to call before rebuilding."""
    for o in [o for o in bpy.data.objects if o.name.startswith(prefix)]:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            try:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Armature):
                    bpy.data.armatures.remove(data)
            except Exception:
                pass


def _link(obj, collection):
    if obj.name not in collection.objects:
        collection.objects.link(obj)


def empty(name, loc=(0, 0, 0), rot_deg=(0, 0, 0), parent=None, collection=None, display="PLAIN_AXES", size=0.15):
    """Empty node (exported as a plain Node3D in Godot): anchors such as Muzzle, HeadlightL, SeatDriver."""
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = display
    o.empty_display_size = size
    o.location = Vector(loc)
    o.rotation_euler = Euler([math.radians(a) for a in rot_deg])
    _link(o, collection or bpy.context.scene.collection)
    if parent is not None:
        o.parent = parent
    return o


def parent_to(child, parent, keep_world=False):
    if keep_world:
        mw = child.matrix_world.copy()
        child.parent = parent
        child.matrix_parent_inverse = parent.matrix_world.inverted()
        child.matrix_world = mw
    else:
        child.parent = parent
        child.matrix_parent_inverse = Matrix.Identity(4)
    return child


# ----------------------------------------------------------------------------------------------------------------
# Mesh builder (bmesh). Faces are wound counter-clockwise seen from OUTSIDE.
# ----------------------------------------------------------------------------------------------------------------
class MB:
    """Low-poly mesh builder. Typical use:
        b = MB("veh_sedan_body")
        b.block((0, 0), 0.0, 0.7, (1.8, 4.2), (1.7, 4.0), mat="Paint")        # tapered box
        b.loft(rings, mat="Paint")                                             # lofted body from cross-section rings
        b.mirror_x()                                                           # build +X half, mirror the rest
        obj = b.finish(collection, name="Body")
    Material args accept a material name (looked up in STD / bpy.data.materials) or a bpy Material."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    # ---- internals ----
    def _mi(self, m):
        if m is None:
            m = "Paint"
        if isinstance(m, str):
            if m not in bpy.data.materials:
                std_mat(m)
            name = m
        else:
            name = m.name
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def v(self, p):
        return self.bm.verts.new(Vector(p))

    def face(self, verts, m=None):
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None  # duplicate face
        f.material_index = self._mi(m)
        f.smooth = False
        return f

    def quad(self, a, b, c, d, mat="Paint"):
        return self.face([self.v(a), self.v(b), self.v(c), self.v(d)], mat)

    def tri(self, a, b, c, mat="Paint"):
        return self.face([self.v(a), self.v(b), self.v(c)], mat)

    def poly(self, pts, mat="Paint"):
        return self.face([self.v(p) for p in pts], mat)

    # ---- primitives ----
    def block(self, center_xy, z0, z1, bottom_size, top_size=None, mat="Paint", top_shift=(0.0, 0.0)):
        """Rectangular (optionally tapered) block. center_xy=(cx,cy); bottom_size/top_size=(width_x, length_y);
        top_shift=(dx,dy) offsets the top face (e.g. slanted windscreen/hood)."""
        top_size = top_size or bottom_size
        cx, cy = center_xy
        bx, by = bottom_size[0] / 2, bottom_size[1] / 2
        tx, ty = top_size[0] / 2, top_size[1] / 2
        sx, sy = top_shift
        b = [(cx - bx, cy - by, z0), (cx + bx, cy - by, z0), (cx + bx, cy + by, z0), (cx - bx, cy + by, z0)]
        t = [(cx - tx + sx, cy - ty + sy, z1), (cx + tx + sx, cy - ty + sy, z1), (cx + tx + sx, cy + ty + sy, z1), (cx - tx + sx, cy + ty + sy, z1)]
        V = [self.v(p) for p in b + t]
        for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([V[i] for i in idx], mat)
        return V

    def box(self, center, size, mat="Paint"):
        """Axis-aligned box: center=(x,y,z), size=(sx,sy,sz)."""
        return self.block((center[0], center[1]), center[2] - size[2] / 2, center[2] + size[2] / 2, (size[0], size[1]), None, mat)

    def prism(self, pts_xy, z0, z1, mat="Paint", cap_bottom=True, cap_top=True):
        """Extrude a convex/concave polygon given in XY (counter-clockwise from above) from z0 to z1."""
        n = len(pts_xy)
        bot = [self.v((p[0], p[1], z0)) for p in pts_xy]
        top = [self.v((p[0], p[1], z1)) for p in pts_xy]
        if cap_bottom:
            self.face(list(reversed(bot)), mat)
        if cap_top:
            self.face(top, mat)
        for i in range(n):
            j = (i + 1) % n
            self.face([bot[i], bot[j], top[j], top[i]], mat)
        return bot, top

    def profile_extrude(self, profile_yz, half_width, mat="Paint", x_center=0.0):
        """Extrude a side profile given as (y, z) points (counter-clockwise when viewed from +X, i.e. from the
        right side of the vehicle) across X in [x_center-half_width, x_center+half_width]. Good for car side silhouettes."""
        n = len(profile_yz)
        xl, xr = x_center - half_width, x_center + half_width
        L = [self.v((xl, p[0], p[1])) for p in profile_yz]
        R = [self.v((xr, p[0], p[1])) for p in profile_yz]
        self.face(R, mat)                       # +X side (CCW seen from +X)
        self.face(list(reversed(L)), mat)       # -X side
        for i in range(n):
            j = (i + 1) % n
            self.face([L[i], L[j], R[j], R[i]], mat)
        return L, R

    def cyl(self, center, r, h, seg=12, mat="Paint", axis="Z", r_top=None, caps=True, smooth=False):
        """Cylinder / cone frustum centred at `center`, `h` long along axis X|Y|Z. r_top gives a frustum."""
        r_top = r if r_top is None else r_top
        ring_b, ring_t = [], []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ca, sa = math.cos(a), math.sin(a)
            ring_b.append(Vector((ca * r, sa * r, -h / 2)))
            ring_t.append(Vector((ca * r_top, sa * r_top, h / 2)))

        def tr(p):
            if axis == "Z":
                q = p
            elif axis == "Y":
                q = Vector((p.x, -p.z, p.y))     # local Z -> world Y
            else:  # X
                q = Vector((p.z, p.y, -p.x))     # local Z -> world X
            return q + Vector(center)

        B = [self.v(tr(p)) for p in ring_b]
        T = [self.v(tr(p)) for p in ring_t]
        faces = []
        for i in range(seg):
            j = (i + 1) % seg
            f = self.face([B[i], B[j], T[j], T[i]], mat)
            faces.append(f)
        if caps:
            if r > 1e-6:
                faces.append(self.face(list(reversed(B)), mat))
            if r_top > 1e-6:
                faces.append(self.face(T, mat))
        if smooth:
            for f in faces:
                if f:
                    f.smooth = True
        return B, T

    def beam(self, p0, p1, r0, r1=None, seg=6, mat="Metal", caps=True):
        """Round bar/cone between two arbitrary points."""
        r1 = r0 if r1 is None else r1
        a, b = Vector(p0), Vector(p1)
        d = b - a
        L = d.length
        if L < 1e-6:
            return
        z = d.normalized()
        up = Vector((0, 0, 1)) if abs(z.z) < 0.95 else Vector((1, 0, 0))
        x = up.cross(z).normalized()
        y = z.cross(x)
        R0, R1 = [], []
        for i in range(seg):
            ang = 2 * math.pi * i / seg
            off = x * math.cos(ang) + y * math.sin(ang)
            R0.append(self.v(a + off * r0))
            R1.append(self.v(b + off * r1))
        for i in range(seg):
            j = (i + 1) % seg
            self.face([R0[i], R0[j], R1[j], R1[i]], mat)
        if caps:
            self.face(list(reversed(R0)), mat)
            self.face(R1, mat)

    def sphere(self, center, r, seg=8, rings=5, mat="Paint", scale=(1, 1, 1)):
        """UV sphere (low poly); `scale` makes ellipsoids (heads, bushes, rocks)."""
        c = Vector(center)
        grid = []
        for k in range(rings + 1):
            phi = math.pi * k / rings
            row = []
            for i in range(seg):
                th = 2 * math.pi * i / seg
                p = Vector((math.sin(phi) * math.cos(th) * scale[0], math.sin(phi) * math.sin(th) * scale[1], math.cos(phi) * scale[2])) * r
                row.append(self.v(c + p))
            grid.append(row)
        for k in range(rings):
            for i in range(seg):
                j = (i + 1) % seg
                # quads everywhere; pole quads collapse to triangles when finish() welds the duplicate pole vertices
                self.face([grid[k][i], grid[k + 1][i], grid[k + 1][j], grid[k][j]], mat)

    def loft(self, rings, mat="Paint", closed=True, cap_start=True, cap_end=True):
        """Skin a list of rings (each a list of 3D points, same count, ordered the SAME way) with quads.
        Order each ring counter-clockwise when looking along the loft direction (rings[0] -> rings[-1]) from the start,
        i.e. for a vehicle lofted from rear to front (increasing Y), points go around the cross-section CCW seen from
        the rear... verify with a quick look() and flip with reverse=True via flip_all() if the faces are inside-out."""
        V = [[self.v(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for k in range(len(V) - 1):
            rng = range(n) if closed else range(n - 1)
            for i in rng:
                j = (i + 1) % n
                self.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mat)
        if closed and cap_start:
            self.face(list(reversed(V[0])), mat)
        if closed and cap_end:
            self.face(V[-1], mat)
        return V

    def mirror_x(self, merge=0.0008):
        """Mirror everything built so far across X=0 and weld vertices on the plane. Build the +X half only."""
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        bmesh.ops.mirror(self.bm, geom=geom, axis="X", merge_dist=merge)

    def translate(self, offset):
        bmesh.ops.translate(self.bm, vec=Vector(offset), verts=self.bm.verts)

    def flip_all(self):
        for f in self.bm.faces:
            f.normal_flip()

    # ---- finish ----
    def finish(self, collection=None, name=None, loc=(0, 0, 0), flat=True, smooth_angle_deg=None, uv=None, parent=None, weld=0.0004):
        """Create the Blender object. uv=None|'box' (box-projected UVs in METRES, used by Godot's procedural shaders).
        smooth_angle_deg: smooth-shade with sharp edges beyond that angle (wheels, tyres, round props). Returns the object."""
        bm = self.bm
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if uv == "box":
            uv_box(bm)
        me = bpy.data.meshes.new((name or self.name) + "_mesh")
        bm.to_mesh(me)
        bm.free()
        for mn in self.mats:
            me.materials.append(bpy.data.materials[mn])
        if smooth_angle_deg is not None:
            try:
                me.shade_smooth()
                me.set_sharp_from_angle(angle=math.radians(smooth_angle_deg))
            except Exception:
                for p in me.polygons:
                    p.use_smooth = True
        elif flat:
            try:
                me.shade_flat()
            except Exception:
                for p in me.polygons:
                    p.use_smooth = False
        obj = bpy.data.objects.new(name or self.name, me)
        obj.location = Vector(loc)
        _link(obj, collection or bpy.context.scene.collection)
        if parent is not None:
            obj.parent = parent
        return obj


def uv_box(bm, scale=1.0):
    """Box-projected UVs in metres (u,v = world metres on the dominant axis plane) - drives tiling window/wall shaders."""
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = l.vert.co
            if ax == 0:
                uvp = (p.y, p.z)
            elif ax == 1:
                uvp = (p.x, p.z)
            else:
                uvp = (p.x, p.y)
            l[layer].uv = (uvp[0] * scale, uvp[1] * scale)


def merge_objects(objs, name, collection=None, delete_sources=True):
    """Merge mesh objects into ONE mesh object with combined material slots (world transforms baked), data-API only."""
    bm = bmesh.new()
    mats = []
    for o in objs:
        me = o.data
        mw = o.matrix_world
        idx_map = {}
        for i, m in enumerate(me.materials):
            if m is not None and m.name not in mats:
                mats.append(m.name)
            idx_map[i] = mats.index(m.name) if m is not None else 0
        tmp = bmesh.new()
        tmp.from_mesh(me)
        bmesh.ops.transform(tmp, matrix=mw, verts=tmp.verts)
        for f in tmp.faces:
            f.material_index = idx_map.get(f.material_index, 0)
        mesh_tmp = bpy.data.meshes.new("_tmp_merge")
        tmp.to_mesh(mesh_tmp)
        tmp.free()
        bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    for mn in mats:
        me.materials.append(bpy.data.materials[mn])
    obj = bpy.data.objects.new(name, me)
    _link(obj, collection or bpy.context.scene.collection)
    if delete_sources:
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    return obj


# ----------------------------------------------------------------------------------------------------------------
# Shared sub-assets
# ----------------------------------------------------------------------------------------------------------------
def make_wheel(name, radius=0.34, width=0.24, collection=None, tire_mat="Tire", rim_mat="Rim", spokes=5, hub_mat="Chrome", loc=(0, 0, 0), parent=None):
    """Wheel whose ROTATION AXIS is X, origin at the wheel centre (Godot spins/steers it). Tyre + dished rim + hub."""
    b = MB(name)
    seg = 16
    # tyre: slightly rounded profile via two stacked frusta
    b.cyl((0, 0, 0), radius, width * 0.78, seg, tire_mat, axis="X", caps=False, smooth=True)
    b.cyl((width * 0.39, 0, 0), radius, width * 0.0 + 0.001, seg, tire_mat, axis="X", r_top=radius * 0.9, caps=False)
    b.cyl((-width * 0.39, 0, 0), radius, width * 0.0 + 0.001, seg, tire_mat, axis="X", r_top=radius * 0.9, caps=False)
    # shoulders
    b.cyl((width * 0.5 - 0.02, 0, 0), radius * 0.93, 0.04, seg, tire_mat, axis="X", r_top=radius * 0.78, caps=False)
    b.cyl((-width * 0.5 + 0.02, 0, 0), radius * 0.93, 0.04, seg, tire_mat, axis="X", r_top=radius * 0.78, caps=False)
    # rim face on the outside (+X) and inside (-X)
    for side in (1, -1):
        b.cyl((side * (width * 0.5 - 0.005), 0, 0), radius * 0.74, 0.03, seg, rim_mat, axis="X", r_top=radius * 0.66)
    # spokes
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        y, z = math.cos(a), math.sin(a)
        b.beam((width * 0.5 + 0.004, y * radius * 0.12, z * radius * 0.12), (width * 0.5 + 0.004, y * radius * 0.66, z * radius * 0.66), radius * 0.06, radius * 0.045, 4, rim_mat, caps=False)
    b.cyl((width * 0.5 + 0.01, 0, 0), radius * 0.13, 0.04, 8, hub_mat, axis="X")
    obj = b.finish(collection, name, loc=loc, flat=True, parent=parent)
    return obj


# ----------------------------------------------------------------------------------------------------------------
# Armature helpers (characters, animals). Bones are specified in OBJECT space of the armature.
# ----------------------------------------------------------------------------------------------------------------
def make_armature(name, bones, collection=None, loc=(0, 0, 0)):
    """bones: list of dicts {name, head(x,y,z), tail(x,y,z), parent(name|None), roll(deg, optional), deform(bool, default True)}
    Parents must be listed before children. Returns the armature object (object mode)."""
    arm = bpy.data.armatures.new(name + "_arm")
    obj = bpy.data.objects.new(name, arm)
    _link(obj, collection or bpy.context.scene.collection)
    obj.location = Vector(loc)
    prev_active = bpy.context.view_layer.objects.active
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for bd in bones:
        b = eb.new(bd["name"])
        b.head = Vector(bd["head"])
        b.tail = Vector(bd["tail"])
        b.roll = math.radians(bd.get("roll", 0.0))
        b.use_deform = bd.get("deform", True)
        if bd.get("parent"):
            b.parent = eb[bd["parent"]]
            b.use_connect = bd.get("connect", False)
    bpy.ops.object.mode_set(mode="OBJECT")
    if prev_active is not None:
        bpy.context.view_layer.objects.active = prev_active
    return obj


def weight_by_segments(mesh_obj, arm_obj, only_bones=None, blend=0.10, rigid=False):
    """Compute vertex-group weights WITHOUT bpy.ops: each vertex is weighted to the nearest bone segment(s); bones whose
    distance is within `blend` metres of the nearest share the weight (soft joints). rigid=True -> 100% nearest bone.
    Adds an Armature modifier and parents the mesh to the armature (identity inverse)."""
    arm = arm_obj.data
    segs = []
    for b in arm.bones:
        if not b.use_deform:
            continue
        if only_bones and b.name not in only_bones:
            continue
        segs.append((b.name, arm_obj.matrix_world @ b.head_local, arm_obj.matrix_world @ b.tail_local))
    for n, _, _ in segs:
        if n not in mesh_obj.vertex_groups:
            mesh_obj.vertex_groups.new(name=n)
    mw = mesh_obj.matrix_world
    for v in mesh_obj.data.vertices:
        p = mw @ v.co
        dists = []
        for n, h, t in segs:
            d = t - h
            L2 = d.length_squared
            u = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (p - h).dot(d) / L2))
            dists.append((n, (p - (h + d * u)).length))
        dists.sort(key=lambda x: x[1])
        best = dists[0][1]
        picks = [(n, d) for n, d in dists if d <= best + blend][:3] if not rigid else [dists[0]]
        ws = [1.0 / (d - best + 0.02) for n, d in picks]
        tot = sum(ws)
        for (n, d), w in zip(picks, ws):
            mesh_obj.vertex_groups[n].add([v.index], w / tot, "REPLACE")
    if not any(m.type == "ARMATURE" for m in mesh_obj.modifiers):
        mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
    mesh_obj.parent = arm_obj
    mesh_obj.matrix_parent_inverse = arm_obj.matrix_world.inverted()


def assign_rigid(mesh_obj, arm_obj, bone_name):
    """100% weight of the whole mesh to one bone (hats, glasses, hair, weapons attached to a hand...)."""
    if bone_name not in mesh_obj.vertex_groups:
        mesh_obj.vertex_groups.new(name=bone_name)
    mesh_obj.vertex_groups[bone_name].add([v.index for v in mesh_obj.data.vertices], 1.0, "REPLACE")
    if not any(m.type == "ARMATURE" for m in mesh_obj.modifiers):
        mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
    mesh_obj.parent = arm_obj
    mesh_obj.matrix_parent_inverse = arm_obj.matrix_world.inverted()


# ----------------------------------------------------------------------------------------------------------------
# Inspection / QA
# ----------------------------------------------------------------------------------------------------------------
def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def stats(root, verbose=True):
    """Print/return triangle count, bounding box (in root-local metres) and material list for a hierarchy."""
    bpy.context.view_layer.update()   # freshly created/parented objects have stale matrix_world otherwise
    objs = [o for o in descendants(root) if o.type == "MESH"]
    tris = 0
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    mats = set()
    inv = root.matrix_world.inverted()
    for o in objs:
        me = o.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        for m in me.materials:
            if m:
                mats.add(m.name)
        for c in o.bound_box:
            p = inv @ (o.matrix_world @ Vector(c))
            mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
            mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
    empties = [o.name for o in descendants(root) if o.type == "EMPTY" and o is not root]
    info = dict(name=root.name, meshes=len(objs), tris=tris, size=tuple(round(x, 3) for x in (mx - mn)),
                min=tuple(round(x, 3) for x in mn), max=tuple(round(x, 3) for x in mx), materials=sorted(mats), empties=empties)
    if verbose:
        print(info)
    return info


def nonmanifold_report(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return nm


# ----------------------------------------------------------------------------------------------------------------
# Export (GLB) + save
# ----------------------------------------------------------------------------------------------------------------
SEP = "__"   # NAMING: Blender object names are GLOBAL, so name every object "<assetid>__<NodeName>"
             # (e.g. "sedan__Body", "sedan__Wheel_FL", "pistol__Muzzle"). export_glb() strips the "<assetid>__" prefix
             # (atomically, inside the export call, and restores it afterwards) so the GLB contains the exact
             # contract names Body / Wheel_FL / Muzzle ... Never use a bare contract name as a Blender object name.


def export_glb(roots, rel_path, animations=False, skins=False, draco=False, extra_objects=(), include_root=False):
    """Export `roots` plus all their descendants to MODELS/<rel_path>.glb  (e.g. 'vehicles/sedan').
    * include_root=False (default): the root object itself is NOT exported - its children become the top-level nodes of the
      GLB (Godot: file-named root node with Body, Wheel_FL, Muzzle ... directly below it). Use include_root=True only if you
      need the root node itself (e.g. an animated rig object).
    * Every exported object named "<prefix>__<Name>" is renamed to "<Name>" for the duration of the export (restored after).
    * The first root is temporarily moved to the world origin so the exported scene is origin-centred.
    Returns the absolute file path. Objects must be visible in the view layer. Not re-entrant per name: never call with a
    bare contract name already present in the file."""
    if not isinstance(roots, (list, tuple)):
        roots = [roots]
    path = os.path.join(MODELS, rel_path.replace("/", os.sep) + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    objs = []
    for r in list(roots) + list(extra_objects):
        for d in descendants(r):
            if d is r and not include_root and r in roots:
                continue
            if d not in objs:
                objs.append(d)
    # --- temporary prefix stripping ---
    renames = []
    obj_set = set(objs)
    for o in objs:
        if SEP in o.name:
            new = o.name.split(SEP, 1)[1]
            other = bpy.data.objects.get(new)
            if other is not None and other not in obj_set:
                raise RuntimeError("export_glb: cannot rename %r to %r - an object with that name already exists" % (o.name, new))
            renames.append((o, o.name, new))
    saved = [(r, r.location.copy()) for r in roots if r.parent is None]
    sel = []
    try:
        for o, old, new in renames:
            o.name = new
        for o in objs:
            if o.name in vl.objects:
                o.select_set(True)
                sel.append(o)
        for r, _ in saved[:1]:
            r.location = Vector((0, 0, 0))
        vl.update()
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
            export_materials="EXPORT", export_cameras=False, export_lights=False, export_extras=False,
            export_animations=animations, export_skins=skins, export_draco_mesh_compression_enable=draco,
            export_texcoords=True, export_normals=True)
    finally:
        for o in sel:
            o.select_set(False)
        for o, old, new in renames:
            try:
                o.name = old
            except Exception:
                pass
        for r, loc in saved[:1]:
            r.location = loc
        vl.update()
    size = os.path.getsize(path) if os.path.exists(path) else -1
    print("exported", path, size, "bytes;", len(objs), "objects")
    return path


def save_master():
    """Save the master .blend (same path). Safe to call repeatedly; no-op unless the file is the project master."""
    if os.path.normcase(bpy.data.filepath) != os.path.normcase(MASTER):
        raise RuntimeError("Refusing to save: open file is %r, expected the project master" % bpy.data.filepath)
    bpy.ops.wm.save_mainfile(filepath=MASTER, compress=True)
    print("saved", MASTER)


def assert_master():
    assert os.path.normcase(bpy.data.filepath) == os.path.normcase(MASTER), "wrong blend file: " + bpy.data.filepath
    return True
