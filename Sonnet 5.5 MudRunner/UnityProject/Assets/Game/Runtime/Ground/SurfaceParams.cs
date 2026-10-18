using System;
using UnityEngine;

namespace MudRunner.Ground
{
    /// <summary>Surface classes painted on the map. Values are also the layer index in the 8-layer splat/control maps.</summary>
    public enum SurfaceType : byte
    {
        Rock = 0,        // bare rock / hard-pack
        FirmSoil = 1,    // compacted soil, dry dirt
        Grass = 2,       // grass / forest floor (humus)
        Gravel = 3,      // packed dirt / gravel road
        ShallowMud = 4,
        DeepMud = 5,
        Bog = 6,         // swamp / peat, extremely soft
        Sand = 7,        // sand / silt
        Count = 8,
    }

    /// <summary>
    /// Soil description used by the tyre-soil model. Pressure-sinkage follows Bekker, p = (kc/b + kphi) * z^n,
    /// shear follows Janosi-Hanamoto, tau = (c + p*tan(phi)) * (1 - exp(-j/K)). All values are SI-kN
    /// (kPa, kN/m^(n+1), kN/m^(n+2), metres). The numbers are tuned gameplay values loosely based on published
    /// terramechanics ranges (see RESEARCH_NOTES.md), not measurements.
    /// </summary>
    [Serializable]
    public struct SurfaceParams
    {
        public string name;
        public Color tint;               // debug/minimap colour (sRGB)

        // Bekker pressure-sinkage
        public float kc;                 // kN/m^(n+1)  cohesive modulus
        public float kphi;               // kN/m^(n+2)  frictional modulus
        public float n;                  // sinkage exponent
        // Mohr-Coulomb / Janosi shear
        public float cohesion;           // kPa
        public float frictionAngle;      // degrees
        public float shearK;             // m, shear deformation modulus (larger = needs more slip to develop thrust)
        // Layer behaviour
        public float softDepth;          // m, thickness of the soft layer above firm ground (hidden extra depth is added from the map)
        public float viscosity;          // 0..1, 0 = sinks instantly / flows back instantly, 1 = very viscous (slow sinking, slow rut flow-back)
        public float rutRelaxRate;       // 1/s, how fast ruts fill back at wetness=1 (diffusive flow + decay)
        public float compactionGain;     // 0..2, how much a pass stiffens the rut floor
        public float digRate;            // m of extra sinkage per m of excess slip travel (spin-digging)
        public float unitWeight;         // kN/m^3, bulldozing wedge weight
        public float bulldozeFactor;     // dimensionless multiplier on bulldozing resistance
        public float wetnessSensitivity; // 0..1, how strongly rain/wetness softens this soil
        public float hardGrip;           // extra rigid-surface friction coefficient (rock/gravel tyre grip when soil shear is small)

        public static SurfaceParams Lerp(in SurfaceParams a, in SurfaceParams b, float t)
        {
            SurfaceParams r = a;
            r.tint = Color.Lerp(a.tint, b.tint, t);
            r.kc = Mathf.Lerp(a.kc, b.kc, t);
            r.kphi = Mathf.Lerp(a.kphi, b.kphi, t);
            r.n = Mathf.Lerp(a.n, b.n, t);
            r.cohesion = Mathf.Lerp(a.cohesion, b.cohesion, t);
            r.frictionAngle = Mathf.Lerp(a.frictionAngle, b.frictionAngle, t);
            r.shearK = Mathf.Lerp(a.shearK, b.shearK, t);
            r.softDepth = Mathf.Lerp(a.softDepth, b.softDepth, t);
            r.viscosity = Mathf.Lerp(a.viscosity, b.viscosity, t);
            r.rutRelaxRate = Mathf.Lerp(a.rutRelaxRate, b.rutRelaxRate, t);
            r.compactionGain = Mathf.Lerp(a.compactionGain, b.compactionGain, t);
            r.digRate = Mathf.Lerp(a.digRate, b.digRate, t);
            r.unitWeight = Mathf.Lerp(a.unitWeight, b.unitWeight, t);
            r.bulldozeFactor = Mathf.Lerp(a.bulldozeFactor, b.bulldozeFactor, t);
            r.wetnessSensitivity = Mathf.Lerp(a.wetnessSensitivity, b.wetnessSensitivity, t);
            r.hardGrip = Mathf.Lerp(a.hardGrip, b.hardGrip, t);
            return r;
        }
    }

    /// <summary>Default soil table. Index with (int)SurfaceType.</summary>
    public static class SurfaceDatabase
    {
        public static readonly SurfaceParams[] Table = Build();

        public static ref readonly SurfaceParams Get(SurfaceType t) => ref Table[(int)t];

        static SurfaceParams[] Build()
        {
            var t = new SurfaceParams[(int)SurfaceType.Count];
            t[(int)SurfaceType.Rock] = new SurfaceParams
            {
                name = "Rock", tint = new Color(0.45f, 0.45f, 0.43f),
                kc = 0f, kphi = 250000f, n = 1.0f, cohesion = 400f, frictionAngle = 42f, shearK = 0.004f,
                softDepth = 0.0f, viscosity = 0f, rutRelaxRate = 0f, compactionGain = 0f, digRate = 0f,
                unitWeight = 26f, bulldozeFactor = 0f, wetnessSensitivity = 0.15f, hardGrip = 0.85f,
            };
            t[(int)SurfaceType.FirmSoil] = new SurfaceParams
            {
                name = "Firm soil", tint = new Color(0.45f, 0.36f, 0.26f),
                kc = 12f, kphi = 3200f, n = 0.85f, cohesion = 22f, frictionAngle = 32f, shearK = 0.018f,
                softDepth = 0.12f, viscosity = 0.9f, rutRelaxRate = 0.0005f, compactionGain = 0.8f, digRate = 0.025f,
                unitWeight = 17f, bulldozeFactor = 0.6f, wetnessSensitivity = 0.55f, hardGrip = 0.55f,
            };
            t[(int)SurfaceType.Grass] = new SurfaceParams
            {
                name = "Grass / forest floor", tint = new Color(0.27f, 0.36f, 0.16f),
                kc = 9f, kphi = 1900f, n = 0.75f, cohesion = 14f, frictionAngle = 27f, shearK = 0.022f,
                softDepth = 0.18f, viscosity = 0.85f, rutRelaxRate = 0.0015f, compactionGain = 0.7f, digRate = 0.04f,
                unitWeight = 16f, bulldozeFactor = 0.7f, wetnessSensitivity = 0.8f, hardGrip = 0.45f,
            };
            t[(int)SurfaceType.Gravel] = new SurfaceParams
            {
                name = "Gravel / packed dirt road", tint = new Color(0.55f, 0.5f, 0.42f),
                kc = 3f, kphi = 4600f, n = 0.9f, cohesion = 6f, frictionAngle = 37f, shearK = 0.015f,
                softDepth = 0.08f, viscosity = 0.95f, rutRelaxRate = 0.0002f, compactionGain = 0.5f, digRate = 0.012f,
                unitWeight = 19f, bulldozeFactor = 0.5f, wetnessSensitivity = 0.35f, hardGrip = 0.65f,
            };
            t[(int)SurfaceType.ShallowMud] = new SurfaceParams
            {
                name = "Shallow mud", tint = new Color(0.30f, 0.22f, 0.15f),
                kc = 3f, kphi = 170f, n = 0.7f, cohesion = 8f, frictionAngle = 16f, shearK = 0.04f,
                softDepth = 0.45f, viscosity = 0.55f, rutRelaxRate = 0.01f, compactionGain = 0.5f, digRate = 0.07f,
                unitWeight = 17f, bulldozeFactor = 1.0f, wetnessSensitivity = 1.0f, hardGrip = 0.18f,
            };
            t[(int)SurfaceType.DeepMud] = new SurfaceParams
            {
                name = "Deep mud", tint = new Color(0.22f, 0.15f, 0.10f),
                kc = 4f, kphi = 70f, n = 0.7f, cohesion = 6f, frictionAngle = 12.5f, shearK = 0.07f,
                softDepth = 0.9f, viscosity = 0.4f, rutRelaxRate = 0.03f, compactionGain = 0.3f, digRate = 0.12f,
                unitWeight = 16.5f, bulldozeFactor = 1.0f, wetnessSensitivity = 1.0f, hardGrip = 0.08f,
            };
            t[(int)SurfaceType.Bog] = new SurfaceParams
            {
                name = "Bog / swamp", tint = new Color(0.14f, 0.12f, 0.08f),
                kc = 2f, kphi = 40f, n = 0.8f, cohesion = 2.5f, frictionAngle = 7f, shearK = 0.1f,
                softDepth = 1.5f, viscosity = 0.25f, rutRelaxRate = 0.08f, compactionGain = 0.15f, digRate = 0.2f,
                unitWeight = 15f, bulldozeFactor = 1.2f, wetnessSensitivity = 1.0f, hardGrip = 0.03f,
            };
            t[(int)SurfaceType.Sand] = new SurfaceParams
            {
                name = "Sand / silt", tint = new Color(0.62f, 0.55f, 0.38f),
                kc = 1f, kphi = 1100f, n = 1.0f, cohesion = 1.2f, frictionAngle = 30f, shearK = 0.025f,
                softDepth = 0.35f, viscosity = 0.7f, rutRelaxRate = 0.004f, compactionGain = 0.6f, digRate = 0.06f,
                unitWeight = 16.5f, bulldozeFactor = 0.9f, wetnessSensitivity = 0.35f, hardGrip = 0.35f,
            };
            return t;
        }
    }
}
