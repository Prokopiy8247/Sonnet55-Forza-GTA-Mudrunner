using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>One instanced prop (tree, rock, reed ...). Rendered with Graphics.RenderMeshInstanced, no GameObject.</summary>
    public struct PropInst
    {
        public ushort type;
        public float x, y, z;
        public float yaw;          // degrees
        public float scale;
    }

    /// <summary>A prop that becomes a real GameObject (buildings, bridges, signs, anchors, dynamic logs, barrels ...).</summary>
    public struct StructureDef
    {
        public string id;
        public Vector3 pos;
        public Quaternion rot;
        public float scale;
        public bool dynamic;           // rigid body (needs PropDef.mass > 0)
        public bool anchor;            // gets a WinchAnchor
        public float anchorPull;       // N (0 = unlimited)
        public Vector3 anchorLocal;
        public string text;            // optional label on signs
        public string tag;             // free text used by spawners / tests (e.g. "garage", "bridge:Old bridge B1")
    }

    /// <summary>
    /// All instanced props of a world, sorted into a coarse grid (cell x type) for cheap culling, plus the list of structures.
    /// </summary>
    public sealed class PropSet
    {
        public string[] typeIds = new string[0];
        public bool[] solid = new bool[0];            // type gets colliders from the near-player pool
        public PropInst[] insts = new PropInst[0];
        public Matrix4x4[] mats = new Matrix4x4[0];
        public int[] cellStart = new int[0];          // [(cell * (T + 1)) + t] .. start of type t in cell; [.. + T] = end of the cell
        public float cellSize = 32f;
        public int cellsX, cellsZ;
        public Vector2 gridOrigin;
        public float minY = 0f, maxY = 100f;
        public readonly List<StructureDef> structures = new List<StructureDef>();

        public int TypeCount => typeIds.Length;
        public int Count => insts.Length;
        public int[] CountPerType()
        {
            var c = new int[typeIds.Length];
            for (int i = 0; i < insts.Length; i++) c[insts[i].type]++;
            return c;
        }

        public void Build(List<PropInst> list, string[] ids, bool[] solidFlags, Vector2 origin, float worldSize, float cell = 32f)
        {
            typeIds = ids; solid = solidFlags; gridOrigin = origin; cellSize = cell;
            cellsX = Mathf.CeilToInt(worldSize / cell); cellsZ = cellsX;
            int T = ids.Length, nc = cellsX * cellsZ;
            var keys = new int[list.Count];
            var counts = new int[nc * T + 1];
            for (int i = 0; i < list.Count; i++)
            {
                var p = list[i];
                int cx = Mathf.Clamp((int)((p.x - origin.x) / cell), 0, cellsX - 1), cz = Mathf.Clamp((int)((p.z - origin.y) / cell), 0, cellsZ - 1);
                int k = (cz * cellsX + cx) * T + p.type;
                keys[i] = k;
                counts[k + 1]++;
            }
            for (int i = 0; i < nc * T; i++) counts[i + 1] += counts[i];
            insts = new PropInst[list.Count];
            var fill = new int[nc * T];
            for (int i = 0; i < list.Count; i++)
            {
                int k = keys[i];
                insts[counts[k] + fill[k]++] = list[i];
            }
            // cellStart[(cell*(T+1)) + t]
            cellStart = new int[nc * (T + 1)];
            for (int c = 0; c < nc; c++)
            {
                for (int t = 0; t < T; t++) cellStart[c * (T + 1) + t] = counts[c * T + t];
                cellStart[c * (T + 1) + T] = counts[c * T + T];
            }
            mats = new Matrix4x4[insts.Length];
            minY = float.MaxValue; maxY = float.MinValue;
            for (int i = 0; i < insts.Length; i++)
            {
                var p = insts[i];
                mats[i] = Matrix4x4.TRS(new Vector3(p.x, p.y, p.z), Quaternion.Euler(0f, p.yaw, 0f), new Vector3(p.scale, p.scale, p.scale));
                if (p.y < minY) minY = p.y;
                if (p.y > maxY) maxY = p.y;
            }
            if (insts.Length == 0) { minY = 0; maxY = 1; }
        }

        public void CellRange(int cell, int type, out int start, out int end)
        {
            int T = typeIds.Length;
            start = cellStart[cell * (T + 1) + type];
            end = type + 1 < T ? cellStart[cell * (T + 1) + type + 1] : cellStart[cell * (T + 1) + T];
        }

        public int CellIndexOf(float x, float z)
        {
            int cx = Mathf.Clamp((int)((x - gridOrigin.x) / cellSize), 0, cellsX - 1), cz = Mathf.Clamp((int)((z - gridOrigin.y) / cellSize), 0, cellsZ - 1);
            return cz * cellsX + cx;
        }
    }
}
