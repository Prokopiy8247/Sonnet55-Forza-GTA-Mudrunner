using System.Collections.Generic;
using MudRunner.Game;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Physics colliders for the instanced props, but only around the player: every 0.25 s the solid instances (trunks, rocks, stumps,
    /// logs) within <see cref="radius"/> of the focus get a pooled collider GameObject (layer Props), those that fell outside
    /// radius + hysteresis are returned to the pool. Pools are per prop type, so steady state has no allocations.
    /// </summary>
    public sealed class PropColliderPool : MonoBehaviour
    {
        public PropSet set;
        public IPropLibrary library;
        public Transform focus;
        public float radius = 80f;
        public float hysteresis = 14f;
        public float interval = 0.25f;
        public int maxActive = 1600;

        PropDef[] defs;
        Stack<GameObject>[] free;
        readonly Dictionary<int, GameObject> active = new Dictionary<int, GameObject>(1024);
        readonly List<int> toRelease = new List<int>(256);
        readonly HashSet<int> wanted = new HashSet<int>();
        float timer;
        Vector3 lastPos = new Vector3(1e9f, 0, 1e9f);
        Transform poolRoot;

        public int ActiveCount => active.Count;
        public int LastSpawned { get; private set; }

        public void Init(PropSet s, IPropLibrary lib)
        {
            set = s; library = lib ?? PropLibraries.Current;
            int T = s.typeIds.Length;
            defs = new PropDef[T];
            free = new Stack<GameObject>[T];
            for (int t = 0; t < T; t++) { defs[t] = s.solid[t] ? library.Get(s.typeIds[t]) : null; free[t] = new Stack<GameObject>(); }
            poolRoot = new GameObject("PropColliders").transform;
            poolRoot.SetParent(transform, false);
        }

        Vector3 FocusPosition()
        {
            if (focus != null) return focus.position;
            var gm = GameManager.Instance;
            if (gm != null && gm.Player != null) return gm.Player.transform.position;
            var cam = Camera.main;
            return cam != null ? cam.transform.position : Vector3.zero;
        }

        void Update()
        {
            if (set == null) return;
            timer -= Time.unscaledDeltaTime;
            if (timer > 0f) return;
            timer = interval;
            Refresh(FocusPosition(), false);
        }

        /// <summary>Synchronise the pool with a position. force = rebuild even when the focus has not moved (after teleports).</summary>
        public void Refresh(Vector3 p, bool force)
        {
            if (set == null) return;
            if (!force && (p - lastPos).sqrMagnitude < 1f && active.Count > 0) return;
            lastPos = p;
            float R = radius, R2 = R * R, Rk = radius + hysteresis, Rk2 = Rk * Rk;
            wanted.Clear();
            int T = set.typeIds.Length;
            float cs = set.cellSize;
            int cx0 = Mathf.Max(0, Mathf.FloorToInt((p.x - R - set.gridOrigin.x) / cs)), cx1 = Mathf.Min(set.cellsX - 1, Mathf.FloorToInt((p.x + R - set.gridOrigin.x) / cs));
            int cz0 = Mathf.Max(0, Mathf.FloorToInt((p.z - R - set.gridOrigin.y) / cs)), cz1 = Mathf.Min(set.cellsZ - 1, Mathf.FloorToInt((p.z + R - set.gridOrigin.y) / cs));
            int spawned = 0;
            for (int cz = cz0; cz <= cz1; cz++)
                for (int cx = cx0; cx <= cx1; cx++)
                {
                    int cell = cz * set.cellsX + cx;
                    for (int t = 0; t < T; t++)
                    {
                        if (defs[t] == null) continue;
                        set.CellRange(cell, t, out int a, out int b);
                        for (int i = a; i < b; i++)
                        {
                            var pi = set.insts[i];
                            float dx = pi.x - p.x, dz = pi.z - p.z;
                            float d2 = dx * dx + dz * dz;
                            if (d2 > Rk2) continue;
                            if (active.ContainsKey(i)) { wanted.Add(i); continue; }
                            if (d2 > R2 || active.Count >= maxActive) continue;
                            Spawn(i, t);
                            wanted.Add(i);
                            spawned++;
                        }
                    }
                }
            toRelease.Clear();
            foreach (var kv in active) if (!wanted.Contains(kv.Key)) toRelease.Add(kv.Key);
            for (int k = 0; k < toRelease.Count; k++)
            {
                int i = toRelease[k];
                var go = active[i];
                active.Remove(i);
                go.SetActive(false);
                free[set.insts[i].type].Push(go);
            }
            LastSpawned = spawned;
        }

        void Spawn(int idx, int t)
        {
            var pi = set.insts[idx];
            GameObject go;
            if (free[t].Count > 0) go = free[t].Pop();
            else go = CreateCollider(t);
            var tr = go.transform;
            tr.SetPositionAndRotation(new Vector3(pi.x, pi.y, pi.z), Quaternion.Euler(0f, pi.yaw, 0f));
            tr.localScale = Vector3.one * pi.scale;
            go.SetActive(true);
            active[idx] = go;
        }

        GameObject CreateCollider(int t)
        {
            var def = defs[t];
            var go = new GameObject("col_" + def.id);
            go.layer = GameLayers.Props;
            go.transform.SetParent(poolRoot, false);
            go.isStatic = false;
            WorldObjects.AddColliders(go, def.colliders, false);
            return go;
        }

        void OnDestroy()
        {
            active.Clear();
        }
    }
}
