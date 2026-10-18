using System;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Vehicles
{
    public enum TreadType { Highway = 0, AllTerrain = 1, MudTerrain = 2, Flotation = 3 }

    [Serializable]
    public struct TireSpec
    {
        [Tooltip("Unloaded outer radius (m)")] public float radius;
        [Tooltip("Section width (m)")] public float width;
        [Tooltip("Radial stiffness (N/m). Lower = softer / lower pressure = longer footprint")] public float radialStiffness;
        [Tooltip("Lug (tread block) depth (m)")] public float lugDepth;
        public TreadType tread;
        [Tooltip("Wheel + tyre + brake rotating inertia (kg m^2)")] public float inertia;
        [Tooltip("Rolling resistance coefficient on hard ground")] public float rollingResistance;

        public static TireSpec Default => new TireSpec
        {
            radius = 0.45f, width = 0.30f, radialStiffness = 350000f, lugDepth = 0.02f,
            tread = TreadType.AllTerrain, inertia = 8f, rollingResistance = 0.02f,
        };
    }

    /// <summary>Result of the per-wheel soil evaluation for one physics step.</summary>
    public struct SoilContact
    {
        public float sinkage;          // equilibrium sinkage below the reference surface (m)
        public float contactLength;    // footprint length (m)
        public float contactArea;      // b * l (m^2)
        public float compactionResistance; // N
        public float bulldozeResistance;   // N
        public float thrustCap;        // N, maximum longitudinal friction/shear force available
        public float lateralCap;       // N
        public bool bottomedOut;       // reached the bottom of the soft layer
    }

    /// <summary>
    /// Pure tyre-soil math (no Unity state): a real-time-friendly reduction of Bekker/Wong terramechanics.
    ///   pressure-sinkage       p = (kc/b + kphi) z^n
    ///   compaction resistance  Rc = b k z^(n+1)/(n+1)
    ///   bulldozing resistance  Rb = f * b z (c Kc + 0.5 gamma z Kg)
    ///   shear (thrust)         tau = (c + p tan(phi)) (1 - exp(-j/K)),  F = A tau_max (1 - K/(j) (1 - e^(-j/K))), j = i*l
    /// </summary>
    public static class TireSoilModel
    {
        const float Kc = 1.2f;   // bulldozing cohesion coefficient
        const float Kg = 1.0f;   // bulldozing weight coefficient

        public static float TreadCohesionMul(TreadType t)
        {
            switch (t)
            {
                case TreadType.Highway: return 0.55f;
                case TreadType.AllTerrain: return 0.85f;
                case TreadType.MudTerrain: return 1.2f;
                default: return 0.9f; // Flotation
            }
        }

        public static float TreadFrictionMul(TreadType t)
        {
            switch (t)
            {
                case TreadType.Highway: return 0.8f;
                case TreadType.AllTerrain: return 0.95f;
                case TreadType.MudTerrain: return 1.05f;
                default: return 1.0f;
            }
        }

        public static float TreadHardGripMul(TreadType t)
        {
            switch (t)
            {
                case TreadType.Highway: return 1.0f;
                case TreadType.AllTerrain: return 0.95f;
                case TreadType.MudTerrain: return 0.85f;
                default: return 0.9f;
            }
        }

        /// <summary>Tyre deflection (m) under load on rigid ground.</summary>
        public static float Deflection(in TireSpec tire, float fz)
        {
            return Mathf.Clamp(fz / Mathf.Max(1000f, tire.radialStiffness), 0f, tire.radius * 0.35f);
        }

        /// <summary>Contact patch length for a wheel of radius R pressed z (soil) + tyre deflection deep.</summary>
        public static float ContactLength(float radius, float zTotal)
        {
            zTotal = Mathf.Clamp(zTotal, 0f, radius * 0.98f);
            float t = 2f * radius * zTotal - zTotal * zTotal;
            return 2f * Mathf.Sqrt(Mathf.Max(0f, t));
        }

        /// <summary>Bearing modulus k = kc/b + kphi in Pa/m^n.</summary>
        public static float Modulus(in SoilSample soil, float width, float stiffnessScale)
        {
            return (soil.kc * 1000f / Mathf.Max(0.05f, width) + soil.kphi * 1000f) * stiffnessScale;
        }

        /// <summary>
        /// Equilibrium sinkage for vertical load fz (N). stiffnessScale folds in compaction (&gt;1) and churn (&lt;1).
        /// maxDepth = soft layer thickness measured from the reference surface. Bisection, monotone.
        /// </summary>
        public static float SolveSinkage(in TireSpec tire, float fz, in SoilSample soil, float stiffnessScale, float maxDepth, out bool bottomedOut)
        {
            bottomedOut = false;
            if (fz <= 1f) return 0f;
            float b = tire.width;
            float k = Modulus(soil, b, stiffnessScale);
            float n = Mathf.Max(0.3f, soil.n);
            float defl = Deflection(tire, fz);
            float zmax = Mathf.Max(0f, Mathf.Min(maxDepth, tire.radius * 1.2f));
            if (zmax < 1e-4f) return 0f;

            // f(z) = supported load - fz ; increasing in z
            float f0 = Supported(tire, k, n, 0f, defl) - fz;
            if (f0 >= 0f) return 0f;
            float fmax = Supported(tire, k, n, zmax, defl) - fz;
            if (fmax < 0f) { bottomedOut = true; return zmax; }
            float lo = 0f, hi = zmax;
            for (int i = 0; i < 18; i++)
            {
                float mid = 0.5f * (lo + hi);
                if (Supported(tire, k, n, mid, defl) - fz < 0f) lo = mid; else hi = mid;
            }
            return 0.5f * (lo + hi);
        }

        static float Supported(in TireSpec tire, float k, float n, float z, float deflection)
        {
            // the tyre keeps part of its radial deflection on soft soil; it relaxes as the soil gives way
            float zTotal = z + deflection / (1f + 6f * z / tire.radius);
            float l = ContactLength(tire.radius, zTotal);
            return k * Mathf.Pow(z + 0.004f, n) * tire.width * l;   // +4 mm: surface roughness / lug penetration
        }

        /// <summary>Evaluate the full soil contact (sinkage, resistances, shear caps) for a given sinkage z and load.</summary>
        public static SoilContact Evaluate(in TireSpec tire, float fz, float z, in SoilSample soil, float stiffnessScale, bool bottomedOut)
        {
            var c = new SoilContact();
            c.sinkage = z;
            c.bottomedOut = bottomedOut;
            float defl = Deflection(tire, fz);
            float zTotal = z + defl / (1f + 6f * z / tire.radius);
            c.contactLength = ContactLength(tire.radius, zTotal);
            c.contactArea = tire.width * c.contactLength;
            float n = Mathf.Max(0.3f, soil.n);
            float k = Modulus(soil, tire.width, stiffnessScale);

            // resistances (N)
            c.compactionResistance = tire.width * k * Mathf.Pow(Mathf.Max(0f, z), n + 1f) / (n + 1f);
            float cPa = soil.cohesion * 1000f;
            c.bulldozeResistance = soil.bulldozeFactor * tire.width * z *
                (cPa * Kc + 0.5f * soil.unitWeight * 1000f * z * Kg * (1f + soil.tanPhi));

            // shear capacity
            float cohMul = TreadCohesionMul(tire.tread), fricMul = TreadFrictionMul(tire.tread);
            float soilThrust = c.contactArea * cPa * cohMul + fz * soil.tanPhi * fricMul;
            float hard = soil.hardGrip * TreadHardGripMul(tire.tread) * fz;
            c.thrustCap = Mathf.Max(soilThrust, hard);
            // lateral: soil shear plus the bulldozed wedge on the tyre side wall when the wheel is buried
            float side = 0.5f * c.bulldozeResistance;
            c.lateralCap = Mathf.Max(0.9f * soilThrust + side, 0.9f * hard);
            return c;
        }

        /// <summary>Janosi-Hanamoto averaged shear fraction (0..1) for slip ratio i, contact length l, shear modulus K.</summary>
        public static float ThrustFraction(float slip, float contactLength, float shearK)
        {
            float x = Mathf.Abs(slip) * contactLength / Mathf.Max(1e-4f, shearK);
            if (x < 0.02f) return 0.5f * x - x * x / 6f;
            return 1f - (1f - Mathf.Exp(-x)) / x;
        }
    }
}
