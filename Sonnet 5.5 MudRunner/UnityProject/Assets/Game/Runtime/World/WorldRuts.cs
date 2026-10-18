using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Applies the pre-carved ruts of the generated tracks to the live <see cref="MudField"/>.
    /// Call order: world builder returns -> GroundService.Initialize creates the field -> <see cref="Apply"/> (WorldInstantiator hooks
    /// GameManager.WorldLoaded; tests and tools call it explicitly after TestArena.Install / GroundService.Initialize).
    /// </summary>
    public static class WorldRuts
    {
        public static int Apply(MudField field, GeneratedWorld gw)
        {
            if (field == null || gw == null || gw.tracks == null) return 0;
            int calls = 0;
            foreach (var t in gw.tracks.tracks)
            {
                int i = 0;
                while (i < t.n)
                {
                    if (!t.ruts[i] || !t.carve[i]) { i++; continue; }
                    int a = i; byte surf = t.surfA[i];
                    while (i < t.n && t.ruts[i] && t.carve[i] && (t.surfA[i] == surf || i - a < 3)) i++;
                    int b = Mathf.Min(t.n - 1, i);        // overlap by one sample so consecutive runs join
                    if (b - a >= 3) { CarveRun(field, t, a, b); calls++; }
                }
            }
            return calls;
        }

        static void CarveRun(MudField field, Track t, int a, int b)
        {
            var pts = new List<Vector2>(b - a + 1);
            for (int i = a; i <= b; i++) pts.Add(new Vector2(t.x[i], t.z[i]));
            var surf = (SurfaceType)t.surfA[a];
            float depth, berm;
            switch (surf)
            {
                case SurfaceType.Bog: depth = 0.30f; berm = 0.10f; break;
                case SurfaceType.DeepMud: depth = 0.26f; berm = 0.10f; break;
                case SurfaceType.ShallowMud: depth = 0.17f; berm = 0.07f; break;
                case SurfaceType.Gravel: depth = 0.05f; berm = 0.02f; break;
                default: depth = 0.09f; berm = 0.04f; break;
            }
            depth *= t.def.ruDepth / 0.14f;
            berm *= t.def.ruDepth / 0.14f;
            field.PrecarveTrack(pts, 1.8f, depth, 0.55f, berm, 0.3f, 0.4f, 0.4f, t.index * 13 + a);
        }
    }
}
