using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.Rendering
{
    /// <summary>
    /// Shared flat grid meshes (local XZ only, y = 0) for the ground chunk LODs. Heights come from textures in the vertex shader.
    /// Every mesh has a skirt: an extra ring of vertices (uv.x = 1) that the shader drops by a fixed amount, which hides T-junction
    /// cracks between neighbouring chunks of different LOD. uv.y = LOD index (debug view).
    /// Skirt triangles are emitted with both windings so they show from either side regardless of the chunk edge.
    /// </summary>
    public static class GroundMeshes
    {
        [StructLayout(LayoutKind.Sequential)]
        struct GridVertex
        {
            public Vector3 pos;
            public Vector2 uv;
        }

        /// <summary>Build a (quads x quads) grid covering [0,size]^2.</summary>
        public static Mesh BuildGrid(int quads, float size, int lodIndex)
        {
            int nv = quads + 1;
            int top = nv * nv;
            int total = top + 4 * nv;
            var verts = new GridVertex[total];
            float step = size / quads;
            for (int z = 0; z < nv; z++)
                for (int x = 0; x < nv; x++)
                    verts[z * nv + x] = new GridVertex { pos = new Vector3(x * step, 0f, z * step), uv = new Vector2(0f, lodIndex) };
            // skirt vertices: south, north, west, east
            for (int i = 0; i < nv; i++)
            {
                verts[top + i] = new GridVertex { pos = new Vector3(i * step, 0f, 0f), uv = new Vector2(1f, lodIndex) };
                verts[top + nv + i] = new GridVertex { pos = new Vector3(i * step, 0f, size), uv = new Vector2(1f, lodIndex) };
                verts[top + 2 * nv + i] = new GridVertex { pos = new Vector3(0f, 0f, i * step), uv = new Vector2(1f, lodIndex) };
                verts[top + 3 * nv + i] = new GridVertex { pos = new Vector3(size, 0f, i * step), uv = new Vector2(1f, lodIndex) };
            }

            int triCount = quads * quads * 2 + 4 * quads * 4;
            var idx = new ushort[triCount * 3];
            int p = 0;
            for (int z = 0; z < quads; z++)
                for (int x = 0; x < quads; x++)
                {
                    ushort i00 = (ushort)(z * nv + x), i10 = (ushort)(i00 + 1), i01 = (ushort)(i00 + nv), i11 = (ushort)(i01 + 1);
                    if (((x + z) & 1) == 0)
                    {
                        idx[p++] = i00; idx[p++] = i01; idx[p++] = i11;
                        idx[p++] = i00; idx[p++] = i11; idx[p++] = i10;
                    }
                    else
                    {
                        idx[p++] = i00; idx[p++] = i01; idx[p++] = i10;
                        idx[p++] = i10; idx[p++] = i01; idx[p++] = i11;
                    }
                }
            // skirts (two-sided): edge vertex index in the top grid, matching skirt vertex index
            for (int e = 0; e < 4; e++)
                for (int i = 0; i < quads; i++)
                {
                    int a0, a1;
                    switch (e)
                    {
                        case 0: a0 = i; a1 = i + 1; break;                                   // south z=0
                        case 1: a0 = quads * nv + i; a1 = a0 + 1; break;                      // north z=size
                        case 2: a0 = i * nv; a1 = (i + 1) * nv; break;                        // west x=0
                        default: a0 = i * nv + quads; a1 = (i + 1) * nv + quads; break;       // east x=size
                    }
                    ushort t0 = (ushort)a0, t1 = (ushort)a1;
                    ushort b0 = (ushort)(top + e * nv + i), b1 = (ushort)(top + e * nv + i + 1);
                    idx[p++] = t0; idx[p++] = b0; idx[p++] = b1;
                    idx[p++] = t0; idx[p++] = b1; idx[p++] = t1;
                    idx[p++] = t0; idx[p++] = b1; idx[p++] = b0;
                    idx[p++] = t0; idx[p++] = t1; idx[p++] = b1;
                }

            var mesh = new Mesh { name = "MR_GroundGrid_LOD" + lodIndex + "_" + quads, indexFormat = IndexFormat.UInt16 };
            mesh.SetVertexBufferParams(total,
                new VertexAttributeDescriptor(VertexAttribute.Position, VertexAttributeFormat.Float32, 3),
                new VertexAttributeDescriptor(VertexAttribute.TexCoord0, VertexAttributeFormat.Float32, 2));
            mesh.SetVertexBufferData(verts, 0, 0, total, 0, MeshUpdateFlags.DontRecalculateBounds);
            mesh.SetIndexBufferParams(idx.Length, IndexFormat.UInt16);
            mesh.SetIndexBufferData(idx, 0, 0, idx.Length, MeshUpdateFlags.DontRecalculateBounds);
            mesh.subMeshCount = 1;
            mesh.SetSubMesh(0, new SubMeshDescriptor(0, idx.Length, MeshTopology.Triangles), MeshUpdateFlags.DontRecalculateBounds);
            mesh.bounds = new Bounds(new Vector3(size * 0.5f, 0f, size * 0.5f), new Vector3(size, 20f, size));
            mesh.UploadMeshData(true);
            return mesh;
        }

        /// <summary>Visible (non-skirt) triangle count of a grid with the given quads per side.</summary>
        public static int SurfaceTriangles(int quads) { return quads * quads * 2; }
    }
}
