using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.Vfx
{
    /// <summary>The pooled particle systems of the VFX layer (one world-space system per effect type, driven by script Emit calls).</summary>
    public enum Fx
    {
        MudBlob, MudSlurry, Dust, Pebble, Droplet, Mist, Foam, Ripple, Smoke, Steam, SplashPuff, Count
    }

    /// <summary>
    /// Owns ONE ParticleSystem per <see cref="Fx"/> (world space, emission module off, <c>maxParticles</c> = the pool bound scaled by quality).
    /// Every vehicle / weather effect emits into these shared systems with <see cref="Emit"/> (per particle position / velocity / colour / size / life),
    /// so there is no per-wheel component, no per-effect GameObject churn, one draw call per type and a hard bound on the live particle count.
    /// Zero GC allocations after construction.
    /// </summary>
    public sealed class ParticleHub : MonoBehaviour
    {
        struct Cfg
        {
            public Fx fx; public string name;
            public int cap, order;
            public float gravity, drag, fadeIn, fadeOutStart;
            public float[] size;            // size multiplier over lifetime, evenly spaced keys
            public ParticleSystemRenderMode mode;
            public float velocityScale, lengthScale, maxSize;
            public bool sheet, sort;
        }

        sealed class Sys
        {
            public ParticleSystem ps; public ParticleSystemRenderer pr; public int cap, baseCap, count; public Material mat; public Cfg cfg;
        }

        static readonly Cfg[] Configs =
        {
            new Cfg { fx = Fx.MudBlob,    name = "MudBlob",    cap = 2200, order = 0,   gravity = 1.0f,   drag = 0.05f, fadeIn = 0.02f, fadeOutStart = 0.88f, size = new[] { 1f, 1f, 0.95f, 0.5f }, mode = ParticleSystemRenderMode.Stretch, velocityScale = 0.010f, lengthScale = 1f, maxSize = 1.5f, sheet = true },
            new Cfg { fx = Fx.MudSlurry,  name = "MudSlurry",  cap = 900,  order = -1,  gravity = 0.45f,  drag = 1.1f,  fadeIn = 0.08f, fadeOutStart = 0.35f, size = new[] { 0.45f, 0.9f, 1.3f, 1.6f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 1.5f, sheet = true },
            new Cfg { fx = Fx.Dust,       name = "Dust",       cap = 700,  order = -5,  gravity = -0.02f, drag = 1.5f,  fadeIn = 0.12f, fadeOutStart = 0.30f, size = new[] { 0.35f, 1.2f, 2.3f, 3.0f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 2.0f, sheet = true, sort = false },
            new Cfg { fx = Fx.Pebble,     name = "Pebble",     cap = 260,  order = 1,   gravity = 1.0f,   drag = 0.02f, fadeIn = 0.0f,  fadeOutStart = 0.9f,  size = new[] { 1f, 1f, 1f, 0.7f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 1.0f, sheet = true },
            new Cfg { fx = Fx.Droplet,    name = "Droplet",    cap = 2000, order = 2,   gravity = 1.0f,   drag = 0.12f, fadeIn = 0.02f, fadeOutStart = 0.55f, size = new[] { 1f, 0.95f, 0.8f, 0.55f }, mode = ParticleSystemRenderMode.Stretch, velocityScale = 0.045f, lengthScale = 1.1f, maxSize = 1.0f },
            new Cfg { fx = Fx.Mist,       name = "Mist",       cap = 360,  order = -2,  gravity = 0.05f,  drag = 1.4f,  fadeIn = 0.10f, fadeOutStart = 0.25f, size = new[] { 0.4f, 1.1f, 1.9f, 2.5f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 2.0f, sheet = true },
            new Cfg { fx = Fx.Foam,       name = "Foam",       cap = 900,  order = -10, gravity = 0f,     drag = 0.5f,  fadeIn = 0.08f, fadeOutStart = 0.45f, size = new[] { 0.5f, 1.1f, 1.5f, 1.75f }, mode = ParticleSystemRenderMode.HorizontalBillboard, maxSize = 4.0f, sheet = true },
            new Cfg { fx = Fx.Ripple,     name = "Ripple",     cap = 160,  order = -9,  gravity = 0f,     drag = 0.8f,  fadeIn = 0.05f, fadeOutStart = 0.30f, size = new[] { 0.15f, 0.6f, 0.9f, 1.0f }, mode = ParticleSystemRenderMode.HorizontalBillboard, maxSize = 4.0f },
            new Cfg { fx = Fx.Smoke,      name = "Smoke",      cap = 520,  order = -4,  gravity = -0.08f, drag = 0.9f,  fadeIn = 0.08f, fadeOutStart = 0.30f, size = new[] { 0.35f, 1.6f, 2.9f, 3.7f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 2.0f, sheet = true, sort = true },
            new Cfg { fx = Fx.Steam,      name = "Steam",      cap = 160,  order = -3,  gravity = -0.25f, drag = 1.0f,  fadeIn = 0.10f, fadeOutStart = 0.25f, size = new[] { 0.4f, 1.3f, 2.2f, 2.8f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 2.0f, sheet = true },
            new Cfg { fx = Fx.SplashPuff, name = "SplashPuff", cap = 420,  order = 3,   gravity = 0.4f,   drag = 2.0f,  fadeIn = 0.03f, fadeOutStart = 0.20f, size = new[] { 0.5f, 1.0f, 1.2f, 1.3f }, mode = ParticleSystemRenderMode.Billboard, maxSize = 1.0f, sheet = true },
        };

        readonly Sys[] sys = new Sys[(int)Fx.Count];
        VfxQuality quality = VfxQuality.High;
        bool visible = true;

        public static ParticleHub Create(Transform parent, VfxQuality q)
        {
            var go = new GameObject("ParticleHub");
            go.transform.SetParent(parent, false);
            var hub = go.AddComponent<ParticleHub>();
            hub.Build(q);
            return hub;
        }

        void Build(VfxQuality q)
        {
            quality = q;
            for (int i = 0; i < Configs.Length; i++)
            {
                var c = Configs[i];
                var s = new Sys { cfg = c, baseCap = c.cap };
                s.mat = MakeMaterial(c.fx);
                var go = new GameObject("Fx_" + c.name);
                go.transform.SetParent(transform, false);
                s.ps = go.AddComponent<ParticleSystem>();
                s.ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
                s.pr = go.GetComponent<ParticleSystemRenderer>();
                Configure(s);
                s.cap = Mathf.Max(8, Mathf.RoundToInt(c.cap * VfxDirector.ScaleFor(q)));
                var main = s.ps.main; main.maxParticles = s.cap;
                s.ps.Play();
                sys[(int)c.fx] = s;
            }
        }

        void Configure(Sys s)
        {
            var c = s.cfg;
            var ps = s.ps;
            var main = ps.main;
            main.playOnAwake = false; main.loop = true; main.duration = 1f; main.prewarm = false;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.scalingMode = ParticleSystemScalingMode.Hierarchy;
            main.startLifetime = 1f; main.startSpeed = 0f; main.startSize = 0.2f; main.startColor = Color.white;
            main.gravityModifier = c.gravity;
            main.maxParticles = c.cap;
            main.stopAction = ParticleSystemStopAction.None;
            var em = ps.emission; em.enabled = false;
            var sh = ps.shape; sh.enabled = false;

            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient();
            float a0 = Mathf.Max(c.fadeIn, 0.001f), a1 = Mathf.Clamp(c.fadeOutStart, a0 + 0.01f, 0.999f);
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                      new[] { new GradientAlphaKey(c.fadeIn <= 0f ? 1f : 0f, 0f), new GradientAlphaKey(1f, a0), new GradientAlphaKey(1f, a1), new GradientAlphaKey(0f, 1f) });
            col.color = new ParticleSystem.MinMaxGradient(g);

            var sz = ps.sizeOverLifetime; sz.enabled = true;
            var curve = new AnimationCurve();
            for (int k = 0; k < c.size.Length; k++) curve.AddKey(new Keyframe(k / (float)(c.size.Length - 1), c.size[k]));
            for (int k = 0; k < curve.length; k++) curve.SmoothTangents(k, 0.3f);
            sz.size = new ParticleSystem.MinMaxCurve(1f, curve);

            if (c.drag > 0f)
            {
                var lim = ps.limitVelocityOverLifetime; lim.enabled = true;
                lim.limit = new ParticleSystem.MinMaxCurve(1000f);
                lim.dampen = 0f;
                lim.drag = new ParticleSystem.MinMaxCurve(c.drag);
            }

            if (c.sheet)
            {
                var ts = ps.textureSheetAnimation; ts.enabled = true;
                ts.mode = ParticleSystemAnimationMode.Grid;
                ts.numTilesX = 2; ts.numTilesY = 2;
                ts.animation = ParticleSystemAnimationType.WholeSheet;
                ts.timeMode = ParticleSystemAnimationTimeMode.Lifetime;
                ts.frameOverTime = new ParticleSystem.MinMaxCurve(0f);
                ts.startFrame = new ParticleSystem.MinMaxCurve(0f, 0.99f);
                ts.cycleCount = 1;
            }

            var pr = s.pr;
            pr.sharedMaterial = s.mat;
            pr.renderMode = c.mode;
            if (c.mode == ParticleSystemRenderMode.Stretch) { pr.velocityScale = c.velocityScale; pr.lengthScale = c.lengthScale; pr.cameraVelocityScale = 0f; }
            pr.shadowCastingMode = ShadowCastingMode.Off;
            pr.receiveShadows = false;
            pr.lightProbeUsage = LightProbeUsage.Off;
            pr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            pr.motionVectorGenerationMode = MotionVectorGenerationMode.ForceNoMotion;
            pr.maxParticleSize = c.maxSize;
            pr.minParticleSize = 0f;
            pr.sortingOrder = c.order;
            pr.sortMode = c.sort ? ParticleSystemSortMode.Distance : ParticleSystemSortMode.None;
            pr.allowRoll = false;
        }

        // ------------------------------------------------------------------ materials

        static Material MakeMaterial(Fx fx)
        {
            var sh = VfxResources.ParticleShader;
            var m = VfxResources.NewMaterial(sh, "VFX_" + fx);
            if (m == null) return null;
            Texture2D tex = VfxTextures.Puff;
            float light = 1f, wrap = 0.5f, spec = 0f, specPow = 32f, emissive = 0f, soft = 0.5f, nearFade = 0.8f, alphaMul = 1f, alphaPow = 1f;
            switch (fx)
            {
                case Fx.MudBlob:    tex = VfxTextures.Blob;    wrap = 0.22f; spec = 0.45f; specPow = 18f; soft = 0.20f; nearFade = 0.4f; alphaPow = 1.5f; break;
                case Fx.MudSlurry:  tex = VfxTextures.Puff;    wrap = 0.55f; spec = 0.10f; specPow = 12f; soft = 0.40f; alphaMul = 0.85f; break;
                case Fx.Dust:       tex = VfxTextures.Puff;    wrap = 0.85f; light = 0.9f; soft = 1.0f; nearFade = 2.0f; alphaMul = 0.7f; break;
                case Fx.Pebble:     tex = VfxTextures.Blob;    wrap = 0.25f; spec = 0.5f; specPow = 28f; soft = 0.1f; nearFade = 0.4f; alphaPow = 1.5f; break;
                case Fx.Droplet:    tex = VfxTextures.Droplet; wrap = 0.55f; light = 0.9f; spec = 1.4f; specPow = 48f; soft = 0.1f; nearFade = 0.4f; emissive = 0.18f; break;
                case Fx.Mist:       tex = VfxTextures.Puff;    wrap = 0.95f; light = 0.85f; emissive = 0.12f; soft = 0.8f; nearFade = 1.5f; alphaMul = 0.55f; break;
                case Fx.Foam:       tex = VfxTextures.Foam;    wrap = 1f; light = 0.7f; emissive = 0.10f; soft = 0.25f; nearFade = 0.5f; break;
                case Fx.Ripple:     tex = VfxTextures.Ring;    wrap = 1f; light = 0.6f; emissive = 0.10f; soft = 0.0f; nearFade = 0.3f; alphaMul = 0.7f; break;
                case Fx.Smoke:      tex = VfxTextures.Puff;    wrap = 1f; light = 1f; soft = 0.9f; nearFade = 1.5f; alphaMul = 0.9f; break;
                case Fx.Steam:      tex = VfxTextures.Puff;    wrap = 1f; light = 0.85f; emissive = 0.10f; soft = 0.8f; nearFade = 1.2f; alphaMul = 0.75f; break;
                case Fx.SplashPuff: tex = VfxTextures.Puff;    wrap = 0.9f; light = 0.9f; emissive = 0.15f; soft = 0.3f; nearFade = 0.4f; alphaMul = 0.8f; break;
            }
            m.SetTexture("_MainTex", tex);
            m.SetFloat("_LightAmount", light); m.SetFloat("_Wrap", wrap); m.SetFloat("_Spec", spec); m.SetFloat("_SpecPower", specPow);
            m.SetFloat("_Emissive", emissive); m.SetFloat("_SoftDistance", soft); m.SetFloat("_NearFade", nearFade);
            m.SetFloat("_AlphaMul", alphaMul); m.SetFloat("_AlphaPow", alphaPow);
            m.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha); m.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_Cull", 0f);
            m.renderQueue = (int)RenderQueue.Transparent + 5;
            return m;
        }

        // ------------------------------------------------------------------ per frame

        public void BeginFrame()
        {
            for (int i = 0; i < sys.Length; i++) { var s = sys[i]; if (s != null) s.count = s.ps.particleCount; }
        }

        public int Count(Fx fx) { var s = sys[(int)fx]; return s != null ? s.count : 0; }
        public int Cap(Fx fx) { var s = sys[(int)fx]; return s != null ? s.cap : 0; }
        public float Fill(Fx fx) { var s = sys[(int)fx]; return s != null && s.cap > 0 ? (float)s.count / s.cap : 1f; }
        public int TotalCount { get { int n = 0; for (int i = 0; i < sys.Length; i++) if (sys[i] != null) n += sys[i].count; return n; } }
        public int TotalCap { get { int n = 0; for (int i = 0; i < sys.Length; i++) if (sys[i] != null) n += sys[i].cap; return n; } }
        /// <summary>Live particle count read straight from the systems (not the per-frame cached value).</summary>
        public int LiveCount(Fx fx) { var s = sys[(int)fx]; return s != null ? s.ps.particleCount : 0; }
        public ParticleSystem System(Fx fx) { var s = sys[(int)fx]; return s != null ? s.ps : null; }

        /// <summary>Emit one particle. Returns false when the pool of that type is full (the particle is dropped).</summary>
        public bool Emit(Fx fx, Vector3 position, Vector3 velocity, Color32 color, float size, float life)
        {
            var s = sys[(int)fx];
            if (s == null || s.count >= s.cap || !visible) return false;
            var ep = new ParticleSystem.EmitParams();
            ep.position = position; ep.velocity = velocity; ep.startColor = color; ep.startSize = size; ep.startLifetime = life;
            s.ps.Emit(ep, 1);
            s.count++;
            return true;
        }

        public void SetQuality(VfxQuality q)
        {
            quality = q;
            for (int i = 0; i < sys.Length; i++)
            {
                var s = sys[i]; if (s == null) continue;
                s.cap = Mathf.Max(8, Mathf.RoundToInt(s.baseCap * VfxDirector.ScaleFor(q)));
                var main = s.ps.main; main.maxParticles = s.cap;
            }
        }

        /// <summary>Hide / clear everything (global VFX toggle).</summary>
        public void SetVisible(bool v)
        {
            if (visible == v) return;
            visible = v;
            for (int i = 0; i < sys.Length; i++)
            {
                var s = sys[i]; if (s == null) continue;
                s.pr.enabled = v;
                if (!v) { s.ps.Clear(false); s.count = 0; }
            }
        }

        public void ClearAll()
        {
            for (int i = 0; i < sys.Length; i++) { var s = sys[i]; if (s != null) { s.ps.Clear(false); s.count = 0; } }
        }

        void OnDestroy()
        {
            for (int i = 0; i < sys.Length; i++)
            {
                var s = sys[i];
                if (s != null && s.mat != null) { if (Application.isPlaying) Destroy(s.mat); else DestroyImmediate(s.mat); }
            }
        }
    }
}
