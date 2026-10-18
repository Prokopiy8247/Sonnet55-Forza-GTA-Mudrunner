using UnityEngine;
using MudRunner.Ground;

namespace MudRunner.Rendering
{
    /// <summary>
    /// Builds a Unity Terrain used as a COLLIDER ONLY (rocks, logs, cargo, camera...). The TerrainData is created at runtime,
    /// resampled bilinearly from the <see cref="GroundMap"/> to the nearest valid heightmap resolution (2^n + 1 >= map size),
    /// never saved as an asset, and nothing is drawn (Terrain.drawHeightmap = false). Wheels do not use it.
    /// </summary>
    public static class GroundColliderBuilder
    {
        public static int ValidResolution(int size)
        {
            int r = 33;
            while (r < size && r < 4097) r = (r - 1) * 2 + 1;
            return r;
        }

        public static Terrain Create(GroundMap map, Transform parent = null)
        {
            int res = ValidResolution(map.size);
            float world = map.WorldSize;
            float minH = map.minHeight, maxH = map.maxHeight;
            if (maxH <= minH) { minH = Mathf.Min(minH, maxH); maxH = minH + 1f; }
            float range = Mathf.Max(maxH - minH, 0.01f);

            var heights = new float[res, res];
            float step = (map.size - 1) / (float)(res - 1);        // map samples per terrain sample
            int s = map.size;
            float[] src = map.height;
            float inv = 1f / range;
            for (int z = 0; z < res; z++)
            {
                float gz = Mathf.Min(z * step, s - 1.001f);
                int iz = (int)gz; float fz = gz - iz;
                int row0 = iz * s, row1 = row0 + s;
                for (int x = 0; x < res; x++)
                {
                    float gx = Mathf.Min(x * step, s - 1.001f);
                    int ix = (int)gx; float fx = gx - ix;
                    float a = Mathf.Lerp(src[row0 + ix], src[row0 + ix + 1], fx);
                    float b = Mathf.Lerp(src[row1 + ix], src[row1 + ix + 1], fx);
                    heights[z, x] = Mathf.Clamp01((Mathf.Lerp(a, b, fz) - minH) * inv);
                }
            }

            var td = new TerrainData { name = "MR_GroundCollider_TerrainData", hideFlags = HideFlags.DontSave };
            td.heightmapResolution = res;
            td.alphamapResolution = 16;
            td.baseMapResolution = 16;
            td.SetDetailResolution(16, 8);
            td.size = new Vector3(world, range, world);
            td.SetHeights(0, 0, heights);

            var go = new GameObject("GroundCollider") { hideFlags = HideFlags.DontSaveInEditor };
            if (parent != null) go.transform.SetParent(parent, false);
            go.transform.position = new Vector3(map.origin.x, minH, map.origin.y);
            go.layer = GameLayers.Terrain;
            go.isStatic = true;

            var terrain = go.AddComponent<Terrain>();
            terrain.terrainData = td;
            terrain.drawHeightmap = false;
            terrain.drawInstanced = false;
            terrain.drawTreesAndFoliage = false;
            terrain.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            var col = go.AddComponent<TerrainCollider>();
            col.terrainData = td;
            return terrain;
        }

        /// <summary>Destroys the collider object and its runtime TerrainData.</summary>
        public static void Destroy(Terrain terrain)
        {
            if (terrain == null) return;
            var td = terrain.terrainData;
            if (Application.isPlaying) { Object.Destroy(terrain.gameObject); if (td != null) Object.Destroy(td); }
            else { Object.DestroyImmediate(terrain.gameObject); if (td != null) Object.DestroyImmediate(td); }
        }
    }
}
