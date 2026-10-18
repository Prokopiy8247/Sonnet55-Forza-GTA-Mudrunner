using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>Human readable numbers derived from a <see cref="VehicleDefinition"/> for the vehicle choice and garage screens.</summary>
    public sealed class VehicleStats
    {
        public string key, name, description;
        public float mass, powerKw, powerHp, peakTorque, peakTorqueRpm, tyreRadius, tyreWidth, winchKn, winchLen, fording, fuel, topGearSpeedKmh;
        public bool hasWinch, hasLowRange;
        public int wheels, drivenWheels, diffLocks;
        public string tyreType;

        public string Drive => wheels + "x" + drivenWheels;
        public string TyreText
        {
            get
            {
                float od = tyreRadius * 2000f, w = tyreWidth * 1000f;
                return od.ToString("0") + " x " + w.ToString("0") + " mm   (" + (od / 25.4f).ToString("0.0") + "″ x " + (w / 25.4f).ToString("0.0") + "″)";
            }
        }

        public static VehicleStats From(string key)
        {
            return From(key, GameManager.GetDefinition(key));
        }

        public static VehicleStats From(string key, VehicleDefinition d)
        {
            var s = new VehicleStats { key = key, name = d.displayName, description = d.description, mass = d.mass, fuel = d.fuelCapacity, fording = d.fordingDepth };
            float pk = 0f, ptq = 0f, ptqRpm = d.idleRpm;
            for (float r = d.idleRpm; r <= d.redlineRpm; r += 50f)
            {
                float t = d.torqueCurve.Evaluate(r);
                float p = t * r * 0.10472f;
                if (p > pk) pk = p;
                if (t > ptq) { ptq = t; ptqRpm = r; }
            }
            s.powerKw = pk / 1000f; s.powerHp = pk / 745.7f; s.peakTorque = ptq; s.peakTorqueRpm = ptqRpm;
            if (d.axles.Length > 0)
            {
                s.tyreRadius = d.axles[0].tire.radius; s.tyreWidth = d.axles[0].tire.width; s.tyreType = d.axles[0].tire.tread.ToString();
            }
            s.wheels = d.axles.Length * 2;
            foreach (var a in d.axles)
            {
                if (a.drive != DriveMode.Never) s.drivenWheels += 2;
                if (a.canLockDiff) s.diffLocks++;
            }
            if (d.hasCentreDiffLock) s.diffLocks++;
            s.hasWinch = d.hasWinch; s.winchKn = d.winchForce / 1000f; s.winchLen = d.winchLength; s.hasLowRange = d.hasLowRange;
            return s;
        }

        /// <summary>Per-metric maximum over all selectable vehicles (to normalise the comparison bars).</summary>
        public static VehicleStats MaxOfAll()
        {
            var m = new VehicleStats();
            foreach (var k in GameManager.VehicleKeys)
            {
                var s = From(k);
                m.mass = Mathf.Max(m.mass, s.mass); m.powerKw = Mathf.Max(m.powerKw, s.powerKw); m.peakTorque = Mathf.Max(m.peakTorque, s.peakTorque);
                m.tyreWidth = Mathf.Max(m.tyreWidth, s.tyreWidth); m.winchKn = Mathf.Max(m.winchKn, s.winchKn); m.fording = Mathf.Max(m.fording, s.fording); m.fuel = Mathf.Max(m.fuel, s.fuel);
            }
            return m;
        }
    }
}
