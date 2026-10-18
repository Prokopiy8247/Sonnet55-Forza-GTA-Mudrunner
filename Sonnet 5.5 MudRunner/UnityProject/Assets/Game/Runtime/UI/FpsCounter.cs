using System;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>Frame-time statistics: smoothed FPS, last frame in ms, 1% low and 0.1% low over the last ~10 s. Updated once per frame by <see cref="UiRoot"/>.</summary>
    public static class FpsCounter
    {
        const int N = 600;
        static readonly float[] ring = new float[N];
        static readonly float[] sorted = new float[N];
        static int idx, count;
        static float nextStats;
        public static float Fps, FrameMs, Low1, Low01, Average, WorstMs;

        public static void Reset() { idx = 0; count = 0; Fps = FrameMs = Low1 = Low01 = Average = WorstMs = 0f; nextStats = 0f; }

        public static void Tick()
        {
            float dt = Time.unscaledDeltaTime;
            if (dt <= 0f) return;
            ring[idx] = dt; idx = (idx + 1) % N; if (count < N) count++;
            FrameMs = dt * 1000f;
            int n = Mathf.Min(count, 45);
            float sum = 0f;
            for (int i = 0; i < n; i++) sum += ring[(idx - 1 - i + N) % N];
            Fps = sum > 0f ? n / sum : 0f;
            if (Time.unscaledTime >= nextStats)
            {
                nextStats = Time.unscaledTime + 0.5f;
                Array.Copy(ring, sorted, count);
                Array.Sort(sorted, 0, count);
                float total = 0f; for (int i = 0; i < count; i++) total += sorted[i];
                Average = total > 0f ? count / total : 0f;
                int k1 = Mathf.Max(1, Mathf.CeilToInt(count * 0.01f)), k01 = Mathf.Max(1, Mathf.CeilToInt(count * 0.001f));
                float s1 = 0f, s01 = 0f;
                for (int i = 0; i < k1; i++) s1 += sorted[count - 1 - i];
                for (int i = 0; i < k01; i++) s01 += sorted[count - 1 - i];
                Low1 = 1f / Mathf.Max(1e-5f, s1 / k1);
                Low01 = 1f / Mathf.Max(1e-5f, s01 / k01);
                WorstMs = sorted[count - 1] * 1000f;
            }
        }
    }
}
