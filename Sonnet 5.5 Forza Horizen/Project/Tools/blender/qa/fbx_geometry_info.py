"""
fbx_geometry_info.py - read-back check of an exported binary FBX (plain Python, no Blender needed):
    python -I Tools/blender/qa/fbx_geometry_info.py Exports/Cars/car02_sedan_cadence/car02_sedan_cadence_Body.fbx
prints one line per Geometry node: object name, vertex count (Vertices / 3) and corner count (PolygonVertexIndex), so the numbers can be
compared with the live scene (len(mesh.vertices), len(mesh.loops)) - this is how the stale Cadence export was found and how the fix
round proved that the re-exported FBX files match the scene exactly (Body / wheel / UCX hulls of cars 01-03).
"""
import struct, zlib, sys, json
def parse(path):
    b = open(path,'rb').read()
    ver = struct.unpack_from('<I', b, 23)[0]
    pos = 27
    big = ver >= 7500
    def read_node(pos):
        if big:
            end, nprops, plen, nlen = struct.unpack_from('<QQQB', b, pos); hdr = 25
        else:
            end, nprops, plen, nlen = struct.unpack_from('<IIIB', b, pos); hdr = 13
        if end == 0:
            return None, pos + hdr
        name = b[pos+hdr:pos+hdr+nlen].decode('latin1')
        p = pos + hdr + nlen
        props = []
        for _ in range(nprops):
            t = chr(b[p]); p += 1
            if t in 'YCIFDL':
                fmt = {'Y':'<h','C':'<?','I':'<i','F':'<f','D':'<d','L':'<q'}[t]
                v = struct.unpack_from(fmt, b, p)[0]; p += struct.calcsize(fmt)
            elif t in 'fdlib':
                ln, enc, clen = struct.unpack_from('<III', b, p); p += 12
                sz = {'f':4,'d':8,'l':8,'i':4,'b':1}[t]
                data = b[p:p+clen]; p += clen
                v = ('arr', t, ln, enc)
                props.append(v)
                if name in ('Vertices','PolygonVertexIndex'):
                    pass
                continue
            elif t in 'SR':
                ln = struct.unpack_from('<I', b, p)[0]; p += 4
                v = b[p:p+ln]; p += ln
            else:
                raise ValueError(t)
            props.append(v)
        children = []
        p = pos + hdr + nlen + plen
        while p < end:
            ch, p = read_node(p)
            if ch is None: break
            children.append(ch)
        return (name, props, children), end
    nodes = []
    while pos < len(b)-100:
        n, pos2 = read_node(pos)
        if n is None: break
        nodes.append(n); pos = pos2
    return nodes
def walk(nodes, name):
    for n in nodes:
        if n[0] == name: yield n
        yield from walk(n[2], name)
if __name__ == '__main__':
    path = sys.argv[1]
    nodes = parse(path)
    for g in walk(nodes, 'Geometry'):
        vcount = pcount = None
        for c in g[2]:
            if c[0] == 'Vertices': vcount = c[1][0][2] // 3
            if c[0] == 'PolygonVertexIndex': pcount = c[1][0][2]
        if vcount: print('Geometry', g[1][1].decode('latin1') if len(g[1])>1 else '?', 'verts', vcount, 'loops', pcount)
