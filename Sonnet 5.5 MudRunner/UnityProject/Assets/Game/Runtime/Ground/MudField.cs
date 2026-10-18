using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Unity.Collections;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.Ground
{
    /// <summary>One cell of the dynamic ground-deformation field.</summary>
    public struct MudCell
    {
        public float dh;        // height offset vs the undisturbed surface (m): negative = rut, positive = berm
        public float churn;     // 0..1 how churned / loosened / wet-slurried the surface is (visual + softens soil)
        public float compact;   // 0..1 how compacted the soil under the surface is (stiffens the rut floor)
    }

    /// <summary>Operation describing one tyre contact patch pressing / shearing the ground.</summary>
    public struct PatchOp
    {
        public float cx, cz;          // world centre (XZ)
        public float fx, fz;          // unit forward direction (XZ) of the wheel
        public float halfWidth, halfLength;
        public float depth;           // absolute depth (m below the ORIGINAL surface) the patch floor is carved to
        public float moveSign;        // +1 / -1: which way the wheel is travelling along forward (front bulldozing side)
        public float bermFrac;        // fraction of removed volume deposited beside the patch
        public float frontFrac;       // fraction of removed volume pushed ahead of the patch
        public float maxBerm;         // cap on berm height (m)
        public float churn;           // churn added at full coverage (0..1)
        public float compact;         // compaction delta at full coverage (+ compacts, - loosens)
    }

    /// <summary>
    /// Persistent, local, cheap ground deformation. The physical terrain collider stays smooth and static;
    /// the *virtual* surface the wheels roll on is  macro height + dh(x,z)  stored here.
    ///
    ///  * CPU authoritative: a toroidal window of <see cref="W"/> x <see cref="W"/> cells (<see cref="cell"/> m each)
    ///    that follows the player. Tiles that scroll out of the window are stored sparsely and restored when
    ///    the window comes back, so ruts persist across the whole map for the whole session.
    ///  * GPU mirror: an RGBAHalf texture of the same window (wrap mode Repeat), updated tile-wise, sampled by
    ///    the ground shader for vertex displacement, shading normals, wetness and puddles.
    ///  * Relaxation: ruts slowly fill back depending on soil fluidity and wetness.
    /// </summary>
    public sealed class MudField
    {
        public const int W = 1024;                         // cells per side of the window (power of two)
        public const int TileSize = 64;                    // cells per tile side
        public const int TilesPerSide = W / TileSize;      // 16
        public const int TileCount = TilesPerSide * TilesPerSide;
        const int Mask = W - 1;
        const int RecenterHysteresisTiles = 3;

        public readonly float cell;                        // metres per field cell
        public float WindowWorldSize => W * cell;

        readonly MudCell[] cells = new MudCell[W * W];
        readonly int[] slotWx = new int[TileCount];
        readonly int[] slotWz = new int[TileCount];
        readonly bool[] slotHasData = new bool[TileCount];
        readonly bool[] slotNeedsRelax = new bool[TileCount];
        readonly bool[] slotGpuDirty = new bool[TileCount];
        readonly Dictionary<long, MudCell[]> store = new Dictionary<long, MudCell[]>();

        int winTileX, winTileZ;
        bool initialized;
        float relaxAccum;
        int relaxCursor;
        readonly MudCell[] relaxScratch = new MudCell[TileSize * TileSize];

        // GPU
        public Texture2D GpuTexture { get; private set; }
        Texture2D[] staging;
        int stagingCursor;
        NativeArray<ushort> stagingData;

        // statistics
        public int ResidentActiveTiles { get { int c = 0; for (int i = 0; i < TileCount; i++) if (slotHasData[i]) c++; return c; } }
        public int StoredTiles => store.Count;
        public int GpuTilesUploadedLastSync { get; private set; }

        public MudField(float cellSize = 0.25f)
        {
            cell = cellSize;
        }

        public Vector2 WindowOriginWorld => new Vector2(winTileX * TileSize * cell, winTileZ * TileSize * cell);

        // ------------------------------------------------------------------ indexing

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static int CellIndex(int cx, int cz) => ((cz & Mask) << 10) | (cx & Mask);   // W == 1024

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static int SlotOfCell(int cx, int cz) => (((cz >> 6) & (TilesPerSide - 1)) * TilesPerSide) + ((cx >> 6) & (TilesPerSide - 1));

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public bool IsResident(int cx, int cz)
        {
            int tx = cx >> 6, tz = cz >> 6;
            return tx >= winTileX && tx < winTileX + TilesPerSide && tz >= winTileZ && tz < winTileZ + TilesPerSide;
        }

        static long TileKey(int wtx, int wtz) => ((long)wtx << 32) | (uint)wtz;

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public int WorldToCell(float v) => Mathf.FloorToInt(v / cell);

        public bool IsResidentWorld(float x, float z) => initialized && IsResident(WorldToCell(x), WorldToCell(z));

        // ------------------------------------------------------------------ window management

        /// <summary>Keep the window around <paramref name="focus"/>. Returns true if the window moved.</summary>
        public bool Recenter(Vector3 focus, bool force = false)
        {
            int ftx = WorldToCell(focus.x) >> 6;
            int ftz = WorldToCell(focus.z) >> 6;
            int dx = ftx - TilesPerSide / 2, dz = ftz - TilesPerSide / 2;
            if (!initialized || force ||
                Mathf.Abs(dx - winTileX) >= RecenterHysteresisTiles || Mathf.Abs(dz - winTileZ) >= RecenterHysteresisTiles)
            {
                Shift(dx, dz);
                return true;
            }
            return false;
        }

        void Shift(int newX, int newZ)
        {
            for (int sz = 0; sz < TilesPerSide; sz++)
                for (int sx = 0; sx < TilesPerSide; sx++)
                {
                    int slot = sz * TilesPerSide + sx;
                    int wtx = newX + ((sx - newX) & (TilesPerSide - 1));
                    int wtz = newZ + ((sz - newZ) & (TilesPerSide - 1));
                    if (initialized && slotWx[slot] == wtx && slotWz[slot] == wtz) continue;
                    if (initialized && slotHasData[slot]) EvictSlot(slot);
                    LoadSlot(slot, wtx, wtz);
                }
            winTileX = newX; winTileZ = newZ;
            initialized = true;
        }

        void EvictSlot(int slot)
        {
            long key = TileKey(slotWx[slot], slotWz[slot]);
            if (!store.TryGetValue(key, out var arr)) { arr = new MudCell[TileSize * TileSize]; store[key] = arr; }
            int baseCx = slotWx[slot] * TileSize, baseCz = slotWz[slot] * TileSize;
            for (int r = 0; r < TileSize; r++)
                Array.Copy(cells, CellIndex(baseCx, baseCz + r), arr, r * TileSize, TileSize);
        }

        void LoadSlot(int slot, int wtx, int wtz)
        {
            slotWx[slot] = wtx; slotWz[slot] = wtz;
            int baseCx = wtx * TileSize, baseCz = wtz * TileSize;
            long key = TileKey(wtx, wtz);
            if (store.TryGetValue(key, out var arr))
            {
                for (int r = 0; r < TileSize; r++)
                    Array.Copy(arr, r * TileSize, cells, CellIndex(baseCx, baseCz + r), TileSize);
                slotHasData[slot] = true;
                slotNeedsRelax[slot] = true;
            }
            else
            {
                for (int r = 0; r < TileSize; r++)
                    Array.Clear(cells, CellIndex(baseCx, baseCz + r), TileSize);
                slotHasData[slot] = false;
                slotNeedsRelax[slot] = false;
            }
            slotGpuDirty[slot] = true;
        }

        /// <summary>Wipe everything (resident window and stored tiles).</summary>
        public void Clear()
        {
            Array.Clear(cells, 0, cells.Length);
            store.Clear();
            for (int i = 0; i < TileCount; i++) { slotHasData[i] = false; slotNeedsRelax[i] = false; slotGpuDirty[i] = true; }
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        void Touch(int cx, int cz)
        {
            int s = SlotOfCell(cx, cz);
            slotHasData[s] = true; slotNeedsRelax[s] = true; slotGpuDirty[s] = true;
        }

        // ------------------------------------------------------------------ queries

        public void Sample(float x, float z, out float dh, out float churn, out float compact)
        {
            float fx = x / cell - 0.5f, fz = z / cell - 0.5f;
            int ix = Mathf.FloorToInt(fx), iz = Mathf.FloorToInt(fz);
            float tx = fx - ix, tz = fz - iz;
            Fetch(ix, iz, out var c00); Fetch(ix + 1, iz, out var c10); Fetch(ix, iz + 1, out var c01); Fetch(ix + 1, iz + 1, out var c11);
            float w00 = (1 - tx) * (1 - tz), w10 = tx * (1 - tz), w01 = (1 - tx) * tz, w11 = tx * tz;
            dh = c00.dh * w00 + c10.dh * w10 + c01.dh * w01 + c11.dh * w11;
            churn = c00.churn * w00 + c10.churn * w10 + c01.churn * w01 + c11.churn * w11;
            compact = c00.compact * w00 + c10.compact * w10 + c01.compact * w01 + c11.compact * w11;
        }

        public float SampleDh(float x, float z)
        {
            Sample(x, z, out float dh, out _, out _);
            return dh;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        void Fetch(int cx, int cz, out MudCell c)
        {
            if (initialized && IsResident(cx, cz)) c = cells[CellIndex(cx, cz)];
            else c = default;
        }

        // ------------------------------------------------------------------ deformation

        /// <summary>
        /// Carve a contact patch to op.depth, route the removed volume into side berms and a front bulldozer
        /// pile, add churn/compaction. Returns the removed volume in m^3.
        /// </summary>
        public float CarvePatch(in PatchOp op)
        {
            if (!initialized) return 0f;
            float bermW = 0.45f, frontW = 0.4f;
            float rad = Mathf.Max(op.halfWidth, op.halfLength) + bermW + frontW + cell;
            int x0 = WorldToCell(op.cx - rad), x1 = WorldToCell(op.cx + rad);
            int z0 = WorldToCell(op.cz - rad), z1 = WorldToCell(op.cz + rad);
            if (!IsResident(x0, z0) || !IsResident(x1, z1)) return 0f;

            float removed = 0f, cellArea = cell * cell;
            float target = -op.depth;
            float lx = -op.fz, lz = op.fx;     // lateral axis

            // pass 1: carve footprint, add churn / compaction, gather deposit weights
            float sideSum = 0f, frontSum = 0f;
            for (int cz = z0; cz <= z1; cz++)
                for (int cx = x0; cx <= x1; cx++)
                {
                    float px = (cx + 0.5f) * cell - op.cx, pz = (cz + 0.5f) * cell - op.cz;
                    float u = px * op.fx + pz * op.fz, v = px * lx + pz * lz;
                    float au = Mathf.Abs(u), av = Mathf.Abs(v);
                    float wu = Mathf.Clamp01((op.halfLength - au) / cell + 0.5f);
                    float wv = Mathf.Clamp01((op.halfWidth - av) / cell + 0.5f);
                    float w = wu * wv;
                    if (w > 0f)
                    {
                        ref MudCell c = ref cells[CellIndex(cx, cz)];
                        if (c.dh > target)
                        {
                            float nd = c.dh + (target - c.dh) * w;
                            removed += (c.dh - nd) * cellArea;
                            c.dh = nd;
                        }
                        c.churn += op.churn * w * (1f - c.churn);
                        if (op.compact >= 0f) c.compact += op.compact * w * (1f - c.compact);
                        else c.compact += op.compact * w * c.compact;
                        Touch(cx, cz);
                    }
                    else
                    {
                        if (av > op.halfWidth * 0.8f && av <= op.halfWidth + bermW && au <= op.halfLength + cell * 0.5f)
                            sideSum += SideWeight(av, op.halfWidth, bermW);
                        float s = u * op.moveSign;
                        if (s > op.halfLength * 0.6f && s <= op.halfLength + frontW && av <= op.halfWidth * 1.1f)
                            frontSum += FrontWeight(s, op.halfLength, frontW);
                    }
                }

            if (removed <= 1e-7f) return 0f;

            float sideVol = removed * op.bermFrac, frontVol = removed * op.frontFrac;
            if ((sideSum > 1e-5f && sideVol > 0f) || (frontSum > 1e-5f && frontVol > 0f))
            {
                for (int cz = z0; cz <= z1; cz++)
                    for (int cx = x0; cx <= x1; cx++)
                    {
                        float px = (cx + 0.5f) * cell - op.cx, pz = (cz + 0.5f) * cell - op.cz;
                        float u = px * op.fx + pz * op.fz, v = px * lx + pz * lz;
                        float au = Mathf.Abs(u), av = Mathf.Abs(v);
                        float wu = Mathf.Clamp01((op.halfLength - au) / cell + 0.5f);
                        float wv = Mathf.Clamp01((op.halfWidth - av) / cell + 0.5f);
                        if (wu * wv > 0f) continue;
                        float add = 0f;
                        if (sideSum > 1e-5f && av > op.halfWidth * 0.8f && av <= op.halfWidth + bermW && au <= op.halfLength + cell * 0.5f)
                            add += sideVol * SideWeight(av, op.halfWidth, bermW) / sideSum / cellArea;
                        float s = u * op.moveSign;
                        if (frontSum > 1e-5f && s > op.halfLength * 0.6f && s <= op.halfLength + frontW && av <= op.halfWidth * 1.1f)
                            add += frontVol * FrontWeight(s, op.halfLength, frontW) / frontSum / cellArea;
                        if (add <= 0f) continue;
                        ref MudCell c = ref cells[CellIndex(cx, cz)];
                        float room = op.maxBerm - c.dh;
                        if (room > 0f) { c.dh += Mathf.Min(add, room); c.churn = Mathf.Min(1f, c.churn + 0.35f * Mathf.Min(1f, add / 0.05f)); }
                        Touch(cx, cz);
                    }
            }
            return removed;
        }


        /// <summary>
        /// Depth (m below the original surface, = -dh) of the shallowest and deepest field cells inside the contact patch.
        /// The wheel rests on the SHALLOWEST cell, so that is the surface that has to be carved down for the wheel to sink / dig.
        /// Returns false when the patch is outside the resident window.
        /// </summary>
        public bool PatchDepthRange(in PatchOp op, out float shallowest, out float deepest)
        {
            shallowest = deepest = 0f;
            if (!initialized) return false;
            float rad = Mathf.Max(op.halfWidth, op.halfLength) + cell * 1.5f;
            int x0 = WorldToCell(op.cx - rad), x1 = WorldToCell(op.cx + rad), z0 = WorldToCell(op.cz - rad), z1 = WorldToCell(op.cz + rad);
            if (!IsResident(x0, z0) || !IsResident(x1, z1)) return false;
            float lx = -op.fz, lz = op.fx, inflate = cell * 0.3f;
            float mn = float.MaxValue, mx = float.MinValue; int n = 0;
            for (int cz = z0; cz <= z1; cz++)
                for (int cx = x0; cx <= x1; cx++)
                {
                    float px = (cx + 0.5f) * cell - op.cx, pz = (cz + 0.5f) * cell - op.cz;
                    float u = px * op.fx + pz * op.fz, v = px * lx + pz * lz;
                    if (Mathf.Abs(u) > op.halfLength + inflate || Mathf.Abs(v) > op.halfWidth + inflate) continue;
                    float d = -cells[CellIndex(cx, cz)].dh;
                    if (d < mn) mn = d; if (d > mx) mx = d; n++;
                }
            if (n == 0)
            {
                float d = -cells[CellIndex(WorldToCell(op.cx), WorldToCell(op.cz))].dh; mn = mx = d;
            }
            shallowest = mn; deepest = mx;
            return true;
        }

        static float SideWeight(float av, float halfWidth, float bermW)
        {
            float d = Mathf.Max(0f, av - halfWidth) / bermW;
            return Mathf.Clamp01(1f - d) * 0.9f + 0.1f;
        }

        static float FrontWeight(float s, float halfLength, float frontW)
        {
            float d = Mathf.Max(0f, s - halfLength) / frontW;
            return Mathf.Clamp01(1f - d) * 0.9f + 0.1f;
        }

        /// <summary>Directly add a mound / dent (used for scripted obstacles and tests). Gaussian, centre (x,z).</summary>
        public void AddBlob(float x, float z, float radius, float height)
        {
            if (!initialized) return;
            int x0 = WorldToCell(x - radius), x1 = WorldToCell(x + radius), z0 = WorldToCell(z - radius), z1 = WorldToCell(z + radius);
            for (int cz = z0; cz <= z1; cz++)
                for (int cx = x0; cx <= x1; cx++)
                {
                    if (!IsResident(cx, cz)) continue;
                    float px = (cx + 0.5f) * cell - x, pz = (cz + 0.5f) * cell - z;
                    float d2 = (px * px + pz * pz) / (radius * radius);
                    if (d2 > 1f) continue;
                    float f = Mathf.Exp(-3f * d2);
                    cells[CellIndex(cx, cz)].dh += height * f;
                    Touch(cx, cz);
                }
        }

        // ------------------------------------------------------------------ pre-carved tracks (added by the world worker)

        ref MudCell CellRef(int cx, int cz)
        {
            if (initialized && IsResident(cx, cz)) { Touch(cx, cz); return ref cells[CellIndex(cx, cz)]; }
            long key = TileKey(cx >> 6, cz >> 6);
            if (!store.TryGetValue(key, out var arr)) { arr = new MudCell[TileSize * TileSize]; store[key] = arr; }
            return ref arr[(cz & (TileSize - 1)) * TileSize + (cx & (TileSize - 1))];
        }

        static float Noise1D(float x, int seed)
        {
            int i = Mathf.FloorToInt(x); float f = x - i; f = f * f * (3f - 2f * f);
            uint h0 = (uint)(i * 374761393 + seed * 668265263), h1 = (uint)((i + 1) * 374761393 + seed * 668265263);
            h0 = (h0 ^ (h0 >> 13)) * 1274126177u; h1 = (h1 ^ (h1 >> 13)) * 1274126177u;
            float a = ((h0 ^ (h0 >> 16)) & 0xFFFF) / 65535f, b = ((h1 ^ (h1 >> 16)) & 0xFFFF) / 65535f;
            return a + (b - a) * f;
        }

        /// <summary>
        /// Pre-carves a used-looking pair of wheel ruts (with side berms and slightly churned, compacted floors) along a world-space XZ polyline.
        /// <paramref name="width"/> = distance between the two rut centre lines (track gauge, ~1.8 m), <paramref name="depth"/> = rut depth at the
        /// centre line, <paramref name="rutWidth"/> = full width of one rut, <paramref name="bermHeight"/> &lt; 0 = 40 % of the depth.
        /// Works in every state: tiles inside the current window are written directly (and marked dirty for the GPU / relaxation), all others
        /// are written into the sparse tile store, so it can be called before or after <see cref="Recenter"/> / GroundService.Initialize
        /// (world builders call it from GameManager.WorldLoaded). Ruts relax like player-made ones (mud flows back over minutes).
        /// Depth varies along the track (+-<paramref name="variation"/>), independently for the two ruts.
        /// </summary>
        public void PrecarveTrack(IList<Vector2> polyline, float width, float depth, float rutWidth = 0.55f, float bermHeight = -1f,
                                  float churn = 0.35f, float compaction = 0.4f, float variation = 0.35f, int seed = 1)
        {
            if (polyline == null || polyline.Count < 2 || depth <= 0f) return;
            float sigma = Mathf.Max(cell * 0.75f, rutWidth * 0.5f);
            float berm = bermHeight >= 0f ? bermHeight : depth * 0.4f;
            float R = sigma * 4.2f;
            int n = polyline.Count;
            var left = new Vector2[n]; var right = new Vector2[n];
            for (int i = 0; i < n; i++)
            {
                Vector2 t = polyline[Mathf.Min(i + 1, n - 1)] - polyline[Mathf.Max(i - 1, 0)];
                t = t.sqrMagnitude > 1e-8f ? t.normalized : Vector2.up;
                Vector2 nrm = new Vector2(-t.y, t.x);
                left[i] = polyline[i] + nrm * (width * 0.5f); right[i] = polyline[i] - nrm * (width * 0.5f);
            }
            var acc = new Dictionary<long, Vector2>(8192);     // per cell: x = distance to the nearest rut line, y = depth multiplier there
            for (int side = 0; side < 2; side++)
            {
                var line = side == 0 ? left : right;
                float s0 = 0f;
                for (int i = 0; i < n - 1; i++)
                {
                    Vector2 a = line[i], b = line[i + 1];
                    float len = (b - a).magnitude;
                    if (len < 1e-4f) continue;
                    Vector2 d = (b - a) / len;
                    int x0 = WorldToCell(Mathf.Min(a.x, b.x) - R), x1 = WorldToCell(Mathf.Max(a.x, b.x) + R);
                    int z0 = WorldToCell(Mathf.Min(a.y, b.y) - R), z1 = WorldToCell(Mathf.Max(a.y, b.y) + R);
                    for (int cz = z0; cz <= z1; cz++)
                        for (int cx = x0; cx <= x1; cx++)
                        {
                            Vector2 pc = new Vector2((cx + 0.5f) * cell, (cz + 0.5f) * cell);
                            float u = Mathf.Clamp(Vector2.Dot(pc - a, d), 0f, len);
                            float dist = (pc - (a + d * u)).magnitude;
                            if (dist > R) continue;
                            long key = ((long)cx << 32) | (uint)cz;
                            if (acc.TryGetValue(key, out var cur) && cur.x <= dist) continue;
                            float mul = 1f - variation * (0.5f + 0.5f * Noise1D((s0 + u) * 0.11f + side * 37.1f, seed));
                            acc[key] = new Vector2(dist, mul);
                        }
                    s0 += len;
                }
            }
            foreach (var kv in acc)
            {
                int cx = (int)(kv.Key >> 32), cz = (int)(uint)(kv.Key & 0xFFFFFFFFL);
                float dist = kv.Value.x, mul = kv.Value.y;
                float g = dist / sigma, gb = (dist - 2f * sigma) / (0.9f * sigma);
                float dh = -depth * mul * Mathf.Exp(-g * g) + berm * mul * Mathf.Exp(-gb * gb);
                ref MudCell c = ref CellRef(cx, cz);
                if (dh < 0f) { if (dh < c.dh) c.dh = dh; } else if (dh > c.dh && c.dh >= 0f) c.dh = dh;
                float w = Mathf.Exp(-(dist * dist) / (4f * sigma * sigma));
                if (churn * w * mul > c.churn) c.churn = churn * w * mul;
                if (compaction * w > c.compact) c.compact = compaction * w;
            }
        }

        // ------------------------------------------------------------------ relaxation (ruts flow back / settle)

        /// <summary>
        /// Advance settling. <paramref name="wetness01"/> = global wetness (rain), <paramref name="rateScale"/> = debug multiplier.
        /// Runs at 10 Hz internally and processes at most <paramref name="maxTilesPerFrame"/> tiles per call.
        /// </summary>
        public void StepRelax(float dt, GroundMap map, float wetness01, float rateScale = 1f, int maxTilesPerFrame = 24)
        {
            if (!initialized) return;
            relaxAccum += dt;
            const float interval = 0.1f;
            if (relaxAccum < interval) return;
            float step = relaxAccum; relaxAccum = 0f;
            int done = 0;
            for (int n = 0; n < TileCount && done < maxTilesPerFrame; n++)
            {
                int slot = (relaxCursor + n) % TileCount;
                if (!slotNeedsRelax[slot]) continue;
                RelaxTile(slot, step, map, wetness01, rateScale);
                done++;
            }
            relaxCursor = (relaxCursor + 7) % TileCount;
        }

        void RelaxTile(int slot, float dt, GroundMap map, float wet, float rateScale)
        {
            int baseCx = slotWx[slot] * TileSize, baseCz = slotWz[slot] * TileSize;
            bool anyRelax = false, anyData = false, changed = false;
            // keep one cell of margin from the window border (neighbour data wraps there)
            int minCx = (winTileX * TileSize) + 1, maxCx = ((winTileX + TilesPerSide) * TileSize) - 2;
            int minCz = (winTileZ * TileSize) + 1, maxCz = ((winTileZ + TilesPerSide) * TileSize) - 2;
            float wetFactor = 0.25f + 1.5f * Mathf.Clamp01(wet);
            for (int r = 0; r < TileSize; r++)
            {
                int cz = baseCz + r;
                for (int q = 0; q < TileSize; q++)
                {
                    int cx = baseCx + q;
                    int idx = CellIndex(cx, cz);
                    MudCell c = cells[idx];
                    MudCell o = c;
                    if (cx >= minCx && cx <= maxCx && cz >= minCz && cz <= maxCz)
                    {
                        float x = (cx + 0.5f) * cell, z = (cz + 0.5f) * cell;
                        float fl = map != null && map.Contains(x, z) ? map.SampleFluidity(x, z) : 0f;
                        float rate = fl * wetFactor * rateScale;
                        if (rate > 0f && (Mathf.Abs(c.dh) > 1e-4f))
                        {
                            float lap = cells[CellIndex(cx - 1, cz)].dh + cells[CellIndex(cx + 1, cz)].dh
                                      + cells[CellIndex(cx, cz - 1)].dh + cells[CellIndex(cx, cz + 1)].dh - 4f * c.dh;
                            float k = Mathf.Min(0.2f, rate * dt * 6f);
                            float decay = Mathf.Min(0.5f, rate * dt * 0.5f);
                            c.dh += k * lap - decay * c.dh;
                        }
                        if (c.churn > 0f)
                            c.churn = Mathf.Max(0f, c.churn - dt * (0.004f + 0.02f * wet) * (0.3f + fl / GroundMap.MaxRelax));
                    }
                    relaxScratch[r * TileSize + q] = c;
                    if (Mathf.Abs(c.dh) > 0.002f || c.churn > 0.01f) anyRelax = true;
                    if (anyRelax || c.compact > 0.01f) anyData = true;
                    if (Mathf.Abs(c.dh - o.dh) > 2e-5f || Mathf.Abs(c.churn - o.churn) > 2e-4f) changed = true;
                }
            }
            // write back after the whole tile was evaluated (so neighbours read pre-step values)
            for (int r = 0; r < TileSize; r++)
                Array.Copy(relaxScratch, r * TileSize, cells, CellIndex(baseCx, baseCz + r), TileSize);
            slotNeedsRelax[slot] = anyRelax;
            if (!anyData)
            {
                slotHasData[slot] = false;
                store.Remove(TileKey(slotWx[slot], slotWz[slot]));
            }
            if (changed) slotGpuDirty[slot] = true;
        }

        // ------------------------------------------------------------------ GPU mirror

        public void CreateGpuResources()
        {
            if (GpuTexture != null) return;
            if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null) return;
            GpuTexture = new Texture2D(W, W, TextureFormat.RGBAHalf, false, true)
            {
                name = "MudField_Window",
                wrapMode = TextureWrapMode.Repeat,
                filterMode = FilterMode.Bilinear,
                anisoLevel = 0,
            };
            var zero = new NativeArray<ushort>(W * W * 4, Allocator.Temp, NativeArrayOptions.ClearMemory);
            GpuTexture.SetPixelData(zero, 0);
            GpuTexture.Apply(false, true);   // upload + make non-readable (CopyTexture then stays GPU-only)
            zero.Dispose();

            staging = new Texture2D[8];
            for (int i = 0; i < staging.Length; i++)
                staging[i] = new Texture2D(TileSize, TileSize, TextureFormat.RGBAHalf, false, true) { name = "MudField_Staging" + i, filterMode = FilterMode.Point };
            stagingData = new NativeArray<ushort>(TileSize * TileSize * 4, Allocator.Persistent);
            for (int i = 0; i < TileCount; i++) slotGpuDirty[i] = true;
        }

        public void DestroyGpuResources()
        {
            if (GpuTexture != null) UnityEngine.Object.Destroy(GpuTexture);
            if (staging != null) foreach (var s in staging) if (s != null) UnityEngine.Object.Destroy(s);
            if (stagingData.IsCreated) stagingData.Dispose();
            GpuTexture = null; staging = null;
        }

        /// <summary>Upload dirty tiles to the GPU texture (at most maxTiles per call).</summary>
        public void SyncGpu(int maxTiles = 32)
        {
            GpuTilesUploadedLastSync = 0;
            if (GpuTexture == null || !initialized) return;
            int uploaded = 0;
            for (int slot = 0; slot < TileCount && uploaded < maxTiles; slot++)
            {
                if (!slotGpuDirty[slot]) continue;
                slotGpuDirty[slot] = false;
                int baseCx = slotWx[slot] * TileSize, baseCz = slotWz[slot] * TileSize;
                int o = 0;
                for (int r = 0; r < TileSize; r++)
                {
                    int idx = CellIndex(baseCx, baseCz + r);
                    for (int q = 0; q < TileSize; q++)
                    {
                        MudCell c = cells[idx + q];
                        stagingData[o++] = (ushort)math.f32tof16(c.dh);
                        stagingData[o++] = (ushort)math.f32tof16(c.churn);
                        stagingData[o++] = (ushort)math.f32tof16(c.compact);
                        stagingData[o++] = 0x3C00; // 1.0
                    }
                }
                var st = staging[stagingCursor]; stagingCursor = (stagingCursor + 1) % staging.Length;
                st.SetPixelData(stagingData, 0);
                st.Apply(false, false);
                int sx = slot % TilesPerSide, sz = slot / TilesPerSide;
                Graphics.CopyTexture(st, 0, 0, 0, 0, TileSize, TileSize, GpuTexture, 0, 0, sx * TileSize, sz * TileSize);
                uploaded++;
            }
            GpuTilesUploadedLastSync = uploaded;
        }

        // ------------------------------------------------------------------ debug / persistence

        /// <summary>Total volume currently displaced (negative = removed), resident window only (m^3).</summary>
        public float ResidentVolume()
        {
            double v = 0;
            for (int i = 0; i < cells.Length; i++) v += cells[i].dh;
            return (float)(v * cell * cell);
        }

        public float MinDh()
        {
            float m = 0f;
            for (int i = 0; i < cells.Length; i++) if (cells[i].dh < m) m = cells[i].dh;
            return m;
        }

        /// <summary>Snapshot of all tiles with data (resident + stored) for save/load. Format: list of (wtx, wtz, 64x64 cells).</summary>
        public List<(int wtx, int wtz, MudCell[] data)> Snapshot()
        {
            var list = new List<(int, int, MudCell[])>();
            for (int slot = 0; slot < TileCount; slot++)
            {
                if (!slotHasData[slot]) continue;
                var arr = new MudCell[TileSize * TileSize];
                int baseCx = slotWx[slot] * TileSize, baseCz = slotWz[slot] * TileSize;
                for (int r = 0; r < TileSize; r++) Array.Copy(cells, CellIndex(baseCx, baseCz + r), arr, r * TileSize, TileSize);
                list.Add((slotWx[slot], slotWz[slot], arr));
            }
            foreach (var kv in store)
            {
                int wtx = (int)(kv.Key >> 32), wtz = (int)(kv.Key & 0xffffffffL);
                bool resident = false;
                for (int slot = 0; slot < TileCount; slot++) if (slotWx[slot] == wtx && slotWz[slot] == wtz && initialized) { resident = true; break; }
                if (!resident) list.Add((wtx, wtz, kv.Value));
            }
            return list;
        }

        public void Restore(List<(int wtx, int wtz, MudCell[] data)> tiles)
        {
            Clear();
            foreach (var t in tiles)
            {
                // resident window tiles go straight into the array, others into the store
                bool placed = false;
                if (initialized && t.wtx >= winTileX && t.wtx < winTileX + TilesPerSide && t.wtz >= winTileZ && t.wtz < winTileZ + TilesPerSide)
                {
                    int slot = (t.wtz & (TilesPerSide - 1)) * TilesPerSide + (t.wtx & (TilesPerSide - 1));
                    int baseCx = t.wtx * TileSize, baseCz = t.wtz * TileSize;
                    for (int r = 0; r < TileSize; r++) Array.Copy(t.data, r * TileSize, cells, CellIndex(baseCx, baseCz + r), TileSize);
                    slotHasData[slot] = true; slotNeedsRelax[slot] = true; slotGpuDirty[slot] = true;
                    placed = true;
                }
                if (!placed) store[TileKey(t.wtx, t.wtz)] = t.data;
            }
        }
    }
}
