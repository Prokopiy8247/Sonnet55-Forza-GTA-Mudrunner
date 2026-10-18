"""Plain-python (no unreal import) ASCII-FBX writer for the material test meshes: flat-shaded triangles with
two UV sets, explicit normals and optional vertex colours.  Positions are written in centimetres, in the same axis convention as the
project's Blender exports (UE x = file x, UE y = -file y, z up).

    write_fbx(path, name, polys)    polys = list of dicts {v:[(x,y,z)...], n:(nx,ny,nz) | per-vertex list, uv0:[(u,v)...], uv1:[(u,v)...], col:[(r,g,b,a)...]}
Each polygon is a convex n-gon (it is written as one FBX polygon).  Helper generators below build the shapes used by the test sheet.
Run standalone:  python materials_testmesh.py <out_dir>   (writes every test mesh)
"""
import math
import os
import sys


def _fmt(vals):
    return ",".join(("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v) for v in vals)


def write_fbx(path, name, polys, has_col=False):
    verts, vindex = [], {}
    pv_idx = []
    normals, uv0, uv1, uv2, uv3, cols = [], [], [], [], [], []
    for p in polys:
        ids = []
        for i, v in enumerate(p["v"]):
            key = tuple(round(c, 4) for c in v)
            if key not in vindex:
                vindex[key] = len(verts)
                verts.append(v)
            ids.append(vindex[key])
            n = p["n"][i] if isinstance(p["n"], list) else p["n"]
            normals.append(n)
            uv0.append(p["uv0"][i])
            uv1.append(p["uv1"][i] if "uv1" in p else p["uv0"][i])
            if "uv2" in p:
                uv2.append(p["uv2"][i])
                uv3.append(p["uv3"][i] if "uv3" in p else p["uv2"][i])
            if has_col:
                cols.append(p["col"][i] if "col" in p else (1, 1, 1, 1))
        ids[-1] = -ids[-1] - 1  # last index of a polygon is stored bit-inverted
        pv_idx.extend(ids)
    flat_v = [c for v in verts for c in v]
    flat_n = [c for n in normals for c in n]
    flat_uv0 = [c for u in uv0 for c in u]
    flat_uv1 = [c for u in uv1 for c in u]
    uv_sets = [("UVMap", flat_uv0), ("UV1", flat_uv1)]
    if uv2:  # road chunks: UV2 / UV3 carry paved width / lane width / median / zone (added by M-B)
        uv_sets += [("UV2", [c for u in uv2 for c in u]), ("UV3", [c for u in uv3 for c in u])]
    idx_uv = list(range(len(uv0)))
    L = []
    w = L.append
    w("; FBX 7.3.0 project file")
    w("FBXHeaderExtension:  {\n\tFBXHeaderVersion: 1003\n\tFBXVersion: 7300\n\tCreator: \"Roamline materials test mesh writer\"\n}")
    w("GlobalSettings:  {\n\tVersion: 1000\n\tProperties70:  {")
    for pr in ('P: "UpAxis", "int", "Integer", "",2', 'P: "UpAxisSign", "int", "Integer", "",1', 'P: "FrontAxis", "int", "Integer", "",1',
               'P: "FrontAxisSign", "int", "Integer", "",-1', 'P: "CoordAxis", "int", "Integer", "",0', 'P: "CoordAxisSign", "int", "Integer", "",1',
               'P: "UnitScaleFactor", "double", "Number", "",1'):
        w("\t\t" + pr)
    w("\t}\n}")
    w("Definitions:  {\n\tVersion: 100\n\tCount: 4\n\tObjectType: \"Model\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"Geometry\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"Material\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"GlobalSettings\" {\n\t\tCount: 1\n\t}\n}")
    w("Objects:  {")
    w("\tGeometry: 1000, \"Geometry::%s\", \"Mesh\" {" % name)
    w("\t\tVertices: *%d {\n\t\t\ta: %s\n\t\t}" % (len(flat_v), _fmt(flat_v)))
    w("\t\tPolygonVertexIndex: *%d {\n\t\t\ta: %s\n\t\t}" % (len(pv_idx), _fmt(pv_idx)))
    w("\t\tGeometryVersion: 124")
    w("\t\tLayerElementNormal: 0 {\n\t\t\tVersion: 101\n\t\t\tName: \"\"\n\t\t\tMappingInformationType: \"ByPolygonVertex\"\n\t\t\tReferenceInformationType: \"Direct\"")
    w("\t\t\tNormals: *%d {\n\t\t\t\ta: %s\n\t\t\t}\n\t\t}" % (len(flat_n), _fmt(flat_n)))
    for li, (nm, uvs) in enumerate(uv_sets):
        w("\t\tLayerElementUV: %d {\n\t\t\tVersion: 101\n\t\t\tName: \"%s\"\n\t\t\tMappingInformationType: \"ByPolygonVertex\"\n\t\t\tReferenceInformationType: \"IndexToDirect\"" % (li, nm))
        w("\t\t\tUV: *%d {\n\t\t\t\ta: %s\n\t\t\t}" % (len(uvs), _fmt(uvs)))
        w("\t\t\tUVIndex: *%d {\n\t\t\t\ta: %s\n\t\t\t}\n\t\t}" % (len(idx_uv), _fmt(idx_uv)))
    if has_col:
        flat_c = [c for col in cols for c in col]
        w("\t\tLayerElementColor: 0 {\n\t\t\tVersion: 101\n\t\t\tName: \"Col\"\n\t\t\tMappingInformationType: \"ByPolygonVertex\"\n\t\t\tReferenceInformationType: \"IndexToDirect\"")
        w("\t\t\tColors: *%d {\n\t\t\t\ta: %s\n\t\t\t}" % (len(flat_c), _fmt(flat_c)))
        w("\t\t\tColorIndex: *%d {\n\t\t\t\ta: %s\n\t\t\t}\n\t\t}" % (len(idx_uv), _fmt(idx_uv)))
    w("\t\tLayerElementMaterial: 0 {\n\t\t\tVersion: 101\n\t\t\tName: \"\"\n\t\t\tMappingInformationType: \"AllSame\"\n\t\t\tReferenceInformationType: \"IndexToDirect\"\n\t\t\tMaterials: *1 {\n\t\t\t\ta: 0\n\t\t\t}\n\t\t}")
    w("\t\tLayer: 0 {\n\t\t\tVersion: 100")
    w("\t\t\tLayerElement:  {\n\t\t\t\tType: \"LayerElementNormal\"\n\t\t\t\tTypedIndex: 0\n\t\t\t}")
    w("\t\t\tLayerElement:  {\n\t\t\t\tType: \"LayerElementMaterial\"\n\t\t\t\tTypedIndex: 0\n\t\t\t}")
    w("\t\t\tLayerElement:  {\n\t\t\t\tType: \"LayerElementUV\"\n\t\t\t\tTypedIndex: 0\n\t\t\t}")
    if has_col:
        w("\t\t\tLayerElement:  {\n\t\t\t\tType: \"LayerElementColor\"\n\t\t\t\tTypedIndex: 0\n\t\t\t}")
    w("\t\t}")
    for li in range(1, len(uv_sets)):
        w("\t\tLayer: %d {\n\t\t\tVersion: 100\n\t\t\tLayerElement:  {\n\t\t\t\tType: \"LayerElementUV\"\n\t\t\t\tTypedIndex: %d\n\t\t\t}\n\t\t}" % (li, li))
    w("\t}")
    w("\tModel: 2000, \"Model::%s\", \"Mesh\" {\n\t\tVersion: 232\n\t\tProperties70:  {\n\t\t\tP: \"InheritType\", \"enum\", \"\", \"\",1\n\t\t}\n\t\tShading: T\n\t\tCulling: \"CullingOff\"\n\t}" % name)
    w("\tMaterial: 3000, \"Material::M_Slot\", \"\" {\n\t\tVersion: 102\n\t\tShadingModel: \"phong\"\n\t\tMultiLayer: 0\n\t\tProperties70:  {\n\t\t\tP: \"DiffuseColor\", \"Color\", \"\", \"A\",0.8,0.8,0.8\n\t\t}\n\t}")
    w("}")
    w("Connections:  {\n\tC: \"OO\",2000,0\n\tC: \"OO\",1000,2000\n\tC: \"OO\",3000,2000\n}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


# ------------------------------------------------------------------------------------------------- shapes (cm in, UV in metres)
def road_strip(width_m=10.5, length_m=40.0):
    """Flat road chunk facing +Z; across = file Y (centred), along = file X. UV0 = (u across 0..1, v along m/10), UV1 = (m across, m along)."""
    w, l = width_m * 100.0, length_m * 100.0
    v = [(0, -w / 2, 0), (l, -w / 2, 0), (l, w / 2, 0), (0, w / 2, 0)]
    # file -Y is UE +Y; "left road edge" = across 0 = file +Y (UE -Y)... keep simple: across increases with file -Y
    across = [width_m, width_m, 0.0, 0.0]
    along = [0.0, length_m, length_m, 0.0]
    across = [width_m - a for a in across]  # across = metres from file -Y edge
    uv0 = [(a / width_m, s / 10.0) for a, s in zip(across, along)]
    uv1 = list(zip(across, along))
    return [{"v": v, "n": (0, 0, 1), "uv0": uv0, "uv1": uv1}]


def wall_panel(width_m=6.0, height_m=4.0):
    """Vertical panel in the file Y/Z plane facing +X, UV0 = metres (u along Y, v downwards), UV1 = same."""
    w, h = width_m * 100.0, height_m * 100.0
    v = [(0, -w / 2, 0), (0, w / 2, 0), (0, w / 2, h), (0, -w / 2, h)]
    uv = [(0.0, height_m), (width_m, height_m), (width_m, 0.0), (0.0, 0.0)]
    return [{"v": v, "n": (1, 0, 0), "uv0": uv, "uv1": uv}]


def floor_tile(size_m=6.0):
    s = size_m * 50.0
    v = [(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)]
    uv = [(0.0, size_m), (size_m, size_m), (size_m, 0.0), (0.0, 0.0)]
    return [{"v": v, "n": (0, 0, 1), "uv0": uv, "uv1": uv}]


def foliage_cards(n_strips=4, length_m=1.4, width_m=0.9):
    """Four crossed foliage cards, one per tint strip of the tree kit UV layout (u in [k/4, (k+1)/4], v 0 = base .. 1 = tip in Blender;
    UE v is flipped on import so we write v_ue directly: base v=1).  Vertex colour R = tip flex, G = flutter, B = AO."""
    polys = []
    l, w = length_m * 100.0, width_m * 100.0 * 0.5
    for k in range(n_strips):
        ang = math.radians(k * 45.0)
        dx, dy = math.cos(ang), math.sin(ang)
        ox = (k - (n_strips - 1) / 2.0) * 120.0
        v = [(ox - w * dx, -w * dy, 40), (ox + w * dx, w * dy, 40), (ox + w * dx, w * dy, 40 + l), (ox - w * dx, -w * dy, 40 + l)]
        u0, u1 = k * 0.25, k * 0.25 + 0.25
        uv = [(u0, 1.0), (u1, 1.0), (u1, 0.0), (u0, 0.0)]
        col = [(0.2, 0.1, 0.9, 1), (0.2, 0.1, 0.9, 1), (1.0, 1.0, 0.7, 1), (1.0, 1.0, 0.7, 1)]
        n = (-dy, dx, 0)
        polys.append({"v": v, "n": n, "uv0": uv, "uv1": uv, "col": col})
    return polys


def card_quad(width_m=1.0, height_m=2.0):
    """Single upright quad, UV 0..1 over the whole card (v=1 at the base), vertex colour R = height (wind)."""
    w, h = width_m * 50.0, height_m * 100.0
    v = [(0, -w, 0), (0, w, 0), (0, w, h), (0, -w, h)]
    uv = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
    col = [(0, 0, 1, 1), (0, 0, 1, 1), (1, 1, 1, 1), (1, 1, 1, 1)]
    return [{"v": v, "n": (1, 0, 0), "uv0": uv, "uv1": uv, "col": col}]


def trunk(radius_m=0.3, height_m=4.0, sides=16, uv_tile_m=2.0):
    """Tree trunk: U wraps once per ring (circumference / uv_tile_m rings), V = metres / uv_tile_m... (kit: nu=round(circ/2); uvv = nu/circ)."""
    circ = 2 * math.pi * radius_m
    nu = max(1, int(round(circ / uv_tile_m)))
    uvv = nu / circ
    r, h = radius_m * 100.0, height_m * 100.0
    polys = []
    for j in range(sides):
        a0, a1 = 2 * math.pi * j / sides, 2 * math.pi * (j + 1) / sides
        p0, p1 = (r * math.cos(a0), r * math.sin(a0)), (r * math.cos(a1), r * math.sin(a1))
        v = [(p0[0], p0[1], 0), (p1[0], p1[1], 0), (p1[0], p1[1], h), (p0[0], p0[1], h)]
        n0 = (math.cos(a0), math.sin(a0), 0)
        n1 = (math.cos(a1), math.sin(a1), 0)
        u0, u1 = nu * j / sides, nu * (j + 1) / sides
        uv = [(u0, 0.0), (u1, 0.0), (u1, height_m * uvv), (u0, height_m * uvv)]
        col = [(0, 0, 1, 1), (0, 0, 1, 1), (1, 0, 1, 1), (1, 0, 1, 1)]
        polys.append({"v": v, "n": [n0, n1, n1, n0], "uv0": uv, "uv1": uv, "col": col})
    return polys


MESHES = {
    "SM_Test_Road": (lambda: road_strip(), False),
    "SM_Test_Wall": (lambda: wall_panel(), False),
    "SM_Test_Floor": (lambda: floor_tile(), False),
    "SM_Test_FoliageCards": (lambda: foliage_cards(), True),
    "SM_Test_Card": (lambda: card_quad(), True),
    "SM_Test_Trunk": (lambda: trunk(), True),
}


def write_all(out_dir):
    out = {}
    for name, (fn, col) in MESHES.items():
        p = os.path.join(out_dir, name + ".fbx").replace("\\", "/")
        write_fbx(p, name, fn(), has_col=col)
        out[name] = p
    return out


if __name__ == "__main__":
    print(write_all(sys.argv[1] if len(sys.argv) > 1 else "."))
