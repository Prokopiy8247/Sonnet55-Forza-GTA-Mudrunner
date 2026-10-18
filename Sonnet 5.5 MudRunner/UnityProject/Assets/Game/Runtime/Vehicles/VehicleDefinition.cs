using System;
using UnityEngine;

namespace MudRunner.Vehicles
{
    public enum DriveMode { Always = 0, AwdOnly = 1, Never = 2 }

    [Serializable]
    public class AxleDef
    {
        public string name = "Front";
        [Tooltip("Axle position along the chassis forward axis (m, local, +z = forward)")] public float z;
        [Tooltip("Distance between left and right wheel centres (m)")] public float track = 1.6f;
        [Tooltip("Hub height at rest above the chassis origin (m, local y)")] public float hubY = 0.45f;
        public TireSpec tire = TireSpec.Default;
        [Range(-1f, 1f)] public float steerFactor = 0f;
        public DriveMode drive = DriveMode.Always;
        public bool canLockDiff = true;
        [Tooltip("Service brake torque per wheel (Nm)")] public float brakeTorque = 3500f;
        [Tooltip("Handbrake torque per wheel (Nm)")] public float handbrakeTorque = 0f;
        [Header("Suspension (per wheel)")]
        public float springRate = 60000f;      // N/m
        public float bumpDamping = 5000f;      // Ns/m
        public float reboundDamping = 8000f;   // Ns/m
        public float travelUp = 0.20f;         // m compression from rest
        public float travelDown = 0.25f;       // m droop from rest
        public float restLength = 0.45f;       // m anchor-to-hub at rest
        public float antiRoll = 20000f;        // N/m across the axle
        public float unsprungMass = 90f;       // kg per wheel+hub
        [Tooltip("Solid axle: visually the axle beam links both hubs (no effect on physics)")] public bool solidAxle = true;
    }

    [Serializable]
    public class GearboxDef
    {
        public float[] forwardRatios = { 3.8f, 2.2f, 1.45f, 1.0f, 0.78f };
        public float reverseRatio = 3.6f;
        public float finalDrive = 4.1f;
        public float lowRangeRatio = 2.6f;
        public float efficiency = 0.9f;
        public float shiftTime = 0.35f;
        public float upshiftRpm = 3600f;
        public float downshiftRpm = 1300f;
    }

    /// <summary>Data-driven description of a drivable vehicle. Mass, engine, gearbox, drivetrain, axles, tyres, suspension, fuel, winch, water.</summary>
    [CreateAssetMenu(menuName = "MudRunner/Vehicle Definition")]
    public sealed class VehicleDefinition : ScriptableObject
    {
        [Header("Identity")]
        public string displayName = "Vehicle";
        [TextArea] public string description = "";

        [Header("Body")]
        public float mass = 2000f;                         // total sprung + unsprung (kg)
        public Vector3 centerOfMass = new Vector3(0f, 0.55f, 0f);
        public Vector3 bodySize = new Vector3(1.8f, 1.0f, 4.2f);   // collider box (w,h,l) for physics/proxy
        public Vector3 bodyCenter = new Vector3(0f, 0.95f, 0f);
        public float dragCdA = 0.9f;                       // 0.5*rho*Cd*A folded: F = 0.6125 * CdA * v^2
        public float groundClearance = 0.28f;
        [Tooltip("Local-space points (x,y,z) + radius used for belly/body contact against the mud surface")] public Vector4[] bodyPoints = new Vector4[0];

        [Header("Engine")]
        public AnimationCurve torqueCurve = AnimationCurve.Linear(800, 120, 4500, 160);   // x = rpm, y = Nm
        public float idleRpm = 800f;
        public float stallRpm = 350f;
        public float redlineRpm = 4800f;
        public float engineInertia = 0.35f;                // kg m^2
        public float engineFriction = 18f;                 // Nm at idle (engine braking scales with rpm)
        public float engineBrakingPerKrpm = 9f;            // extra Nm per 1000 rpm

        [Header("Transmission")]
        public GearboxDef gearbox = new GearboxDef();
        [Range(0f, 1f)] public float frontTorqueShare = 0.5f;   // static split when several axles are driven and the centre diff is open
        public bool hasLowRange = true;
        public bool hasAwdSwitch = true;
        public bool hasCentreDiffLock = true;

        [Header("Axles")]
        public AxleDef[] axles = new AxleDef[0];

        [Header("Fuel")]
        public float fuelCapacity = 60f;                   // litres
        public float idleFuelRate = 0.8f;                  // L/h at idle
        public float fullLoadFuelRate = 14f;               // L/h at full torque*rpm

        [Header("Recovery & water")]
        public bool hasWinch = true;
        public float winchForce = 30000f;                  // N
        public float winchLength = 25f;                    // m
        public float fordingDepth = 0.6f;                  // m (engine intake height above ground)
        public Vector3 intakeLocal = new Vector3(0f, 1.2f, 1.6f);
        public float waterDragArea = 3.0f;                 // m^2 effective frontal/side area for water drag
        public float displacedVolume = 3.0f;               // m^3 of watertight volume (buoyancy)

        [Header("Towing")]
        public bool isTrailer;
        [Tooltip("Tow ball / pintle on the towing vehicle (local)")] public Vector3 hitchLocal = new Vector3(0f, 0.6f, -2.5f);
        [Tooltip("Drawbar eye on a trailer (local)")] public Vector3 drawbarLocal = new Vector3(0f, 0.6f, 3.7f);
        public float maxTowMass = 6000f;

        [Header("Damage")]
        public float resilience = 1f;

        public float TotalWheelCount() { return axles.Length * 2; }

        /// <summary>
        /// Rated fording depth (m above the ground): the lower of the engine intake height and the water depth at which buoyancy
        /// starts to lift the vehicle (it then loses traction and is swept away). Used by the HUD and the automated tests.
        /// </summary>
        public static float ComputeFordingRating(VehicleDefinition d, Vector3? intakeOverride = null)
        {
            float intakeH = (intakeOverride ?? d.intakeLocal).y;
            float tyreVol = 0f; foreach (var a in d.axles) tyreVol += 2f * 0.5f * Mathf.PI * a.tire.radius * a.tire.radius * a.tire.width * 0.5f;
            float need = Mathf.Clamp01((d.mass / 1000f - tyreVol) / Mathf.Max(0.1f, d.displacedVolume));
            float floorY = d.bodyCenter.y - d.bodySize.y * 0.5f;
            float floatDepth = floorY + need * d.bodySize.y;
            return Mathf.Max(0.3f, Mathf.Min(intakeH, floatDepth));
        }

        // ------------------------------------------------------------------ factories (also used to bake the .asset files)

        static AnimationCurve Curve(params float[] rpmNm)
        {
            var c = new AnimationCurve();
            for (int i = 0; i + 1 < rpmNm.Length; i += 2) c.AddKey(rpmNm[i], rpmNm[i + 1]);
            for (int i = 0; i < c.length; i++) c.SmoothTangents(i, 0.3f);
            return c;
        }

        static Vector4[] BoxPoints(Vector3 size, Vector3 center, float radius)
        {
            var list = new System.Collections.Generic.List<Vector4>();
            float hx = size.x * 0.5f, hy = size.y * 0.5f, hz = size.z * 0.5f;
            for (int ix = -1; ix <= 1; ix += 2)
                for (int iz = -1; iz <= 1; iz += 2)
                {
                    list.Add(new Vector4(center.x + ix * hx, center.y - hy, center.z + iz * hz, radius));       // belly corners
                    list.Add(new Vector4(center.x + ix * hx, center.y + hy, center.z + iz * hz, radius));       // roof corners (rollover)
                }
            list.Add(new Vector4(center.x, center.y - hy, center.z, radius));                                   // belly centre
            list.Add(new Vector4(center.x, center.y - hy, center.z + hz * 0.5f, radius));
            list.Add(new Vector4(center.x, center.y - hy, center.z - hz * 0.5f, radius));
            return list.ToArray();
        }


        /// <summary>Two-axle drawbar log trailer, ~1.5 t empty.</summary>
        public static VehicleDefinition CreateLogTrailer()
        {
            var d = CreateInstance<VehicleDefinition>();
            d.name = "LogTrailer";
            d.displayName = "Timber Drawbar Trailer";
            d.description = "Two-axle drawbar trailer with log bunks.";
            d.isTrailer = true;
            d.mass = 1500f;
            d.centerOfMass = new Vector3(0f, 0.85f, -1.55f);
            d.bodySize = new Vector3(2.3f, 0.35f, 6.2f);
            d.bodyCenter = new Vector3(0f, 0.95f, -0.5f);
            d.dragCdA = 1.8f;
            d.groundClearance = 0.5f;
            d.bodyPoints = BoxPoints(d.bodySize, d.bodyCenter, 0.1f);
            d.torqueCurve = AnimationCurve.Linear(800, 0, 4000, 0);
            d.idleRpm = 800f; d.stallRpm = 300f; d.redlineRpm = 4000f;
            d.hasWinch = false; d.hasAwdSwitch = false; d.hasLowRange = false; d.hasCentreDiffLock = false;
            d.fuelCapacity = 0f; d.idleFuelRate = 0f; d.fullLoadFuelRate = 0f; d.winchForce = 0f;
            d.drawbarLocal = new Vector3(0f, 0.65f, 3.7f);
            AxleDef Ax(string n, float z) => new AxleDef
            {
                name = n, z = z, track = 1.9f, hubY = 0.54f, steerFactor = 0f, drive = DriveMode.Never, canLockDiff = false,
                tire = new TireSpec { radius = 0.54f, width = 0.375f, radialStiffness = 320000f, lugDepth = 0.026f, tread = TreadType.MudTerrain, inertia = 11f, rollingResistance = 0.022f },
                brakeTorque = 3500f, handbrakeTorque = 3500f, springRate = 80000f, bumpDamping = 8000f, reboundDamping = 12000f, travelUp = 0.2f, travelDown = 0.26f, restLength = 0.5f,
                antiRoll = 10000f, unsprungMass = 120f, solidAxle = true,
            };
            d.axles = new[] { Ax("Front", -1.2f), Ax("Rear", -2.4f) };
            d.fordingDepth = 1.0f; d.waterDragArea = 3f; d.displacedVolume = 2f;
            d.intakeLocal = new Vector3(0f, 3f, 0f);
            return d;
        }

        /// <summary>Light 4x4 scout, ~1.8 t, narrow tyres: nimble, easily bogged in deep mud.</summary>
        public static VehicleDefinition CreateScout()
        {
            var d = CreateInstance<VehicleDefinition>();
            d.name = "Scout";
            d.displayName = "Pathfinder 4x4 Scout";
            d.description = "Light 4x4 scout. Nimble and quick on firm ground, but narrow tyres bog down in deep mud.";
            d.mass = 2000f;
            d.centerOfMass = new Vector3(0f, 0.62f, 0.12f);
            d.bodySize = new Vector3(1.75f, 0.85f, 3.7f);
            d.bodyCenter = new Vector3(0f, 0.95f, 0f);
            d.dragCdA = 1.1f;
            d.groundClearance = 0.26f;
            d.bodyPoints = BoxPoints(d.bodySize, d.bodyCenter, 0.12f);
            d.torqueCurve = Curve(800, 150, 1500, 215, 2500, 255, 3500, 250, 4500, 215, 5200, 170);
            d.idleRpm = 850f; d.stallRpm = 400f; d.redlineRpm = 5200f; d.engineInertia = 0.32f; d.engineFriction = 18f;
            d.gearbox = new GearboxDef
            {
                forwardRatios = new[] { 3.9f, 2.3f, 1.5f, 1.0f, 0.78f },
                reverseRatio = 3.7f, finalDrive = 4.3f, lowRangeRatio = 2.5f, efficiency = 0.9f, shiftTime = 0.3f,
                upshiftRpm = 4200f, downshiftRpm = 1500f,
            };
            d.frontTorqueShare = 0.4f;
            d.axles = new[]
            {
                new AxleDef { name = "Front", z = 1.25f, track = 1.5f, hubY = 0.44f, steerFactor = 1f, drive = DriveMode.AwdOnly,
                    tire = new TireSpec { radius = 0.40f, width = 0.235f, radialStiffness = 230000f, lugDepth = 0.014f, tread = TreadType.AllTerrain, inertia = 4.5f, rollingResistance = 0.02f },
                    brakeTorque = 2200f, springRate = 36000f, bumpDamping = 3600f, reboundDamping = 5200f, travelUp = 0.18f, travelDown = 0.22f, restLength = 0.40f,
                    antiRoll = 14000f, unsprungMass = 70f },
                new AxleDef { name = "Rear", z = -1.25f, track = 1.5f, hubY = 0.44f, steerFactor = 0f, drive = DriveMode.Always, handbrakeTorque = 2600f,
                    tire = new TireSpec { radius = 0.40f, width = 0.235f, radialStiffness = 230000f, lugDepth = 0.014f, tread = TreadType.AllTerrain, inertia = 4.5f, rollingResistance = 0.02f },
                    brakeTorque = 1800f, springRate = 40000f, bumpDamping = 3800f, reboundDamping = 5600f, travelUp = 0.18f, travelDown = 0.24f, restLength = 0.40f,
                    antiRoll = 12000f, unsprungMass = 70f },
            };
            d.fuelCapacity = 55f; d.idleFuelRate = 0.7f; d.fullLoadFuelRate = 16f;
            d.hasWinch = false; d.winchForce = 0f;
            d.fordingDepth = 0.7f; d.intakeLocal = new Vector3(0f, 0.75f, 1.45f); d.waterDragArea = 2.2f; d.displacedVolume = 2.2f;
            return d;
        }

        /// <summary>Mid-size utility truck, ~4 t, with winch. Balanced.</summary>
        public static VehicleDefinition CreateUtility()
        {
            var d = CreateInstance<VehicleDefinition>();
            d.name = "Utility";
            d.displayName = "Bruiser 4x4 Utility Truck";
            d.description = "Balanced 4x4 utility truck with a front winch. Wider mud tyres and low range for slogging.";
            d.mass = 4200f;
            d.centerOfMass = new Vector3(0f, 0.85f, 0.2f);
            d.bodySize = new Vector3(2.15f, 1.2f, 5.2f);
            d.bodyCenter = new Vector3(0f, 1.25f, 0f);
            d.dragCdA = 2.2f;
            d.groundClearance = 0.34f;
            d.bodyPoints = BoxPoints(d.bodySize, d.bodyCenter, 0.14f);
            d.torqueCurve = Curve(800, 380, 1200, 560, 1800, 700, 2600, 640, 3400, 520, 4000, 400);
            d.idleRpm = 750f; d.stallRpm = 350f; d.redlineRpm = 4000f; d.engineInertia = 0.9f; d.engineFriction = 30f;
            d.gearbox = new GearboxDef
            {
                forwardRatios = new[] { 4.6f, 2.6f, 1.6f, 1.0f, 0.75f },
                reverseRatio = 4.2f, finalDrive = 4.9f, lowRangeRatio = 2.7f, efficiency = 0.9f, shiftTime = 0.45f,
                upshiftRpm = 3000f, downshiftRpm = 1100f,
            };
            d.frontTorqueShare = 0.45f;
            d.axles = new[]
            {
                new AxleDef { name = "Front", z = 1.6f, track = 1.85f, hubY = 0.56f, steerFactor = 1f, drive = DriveMode.AwdOnly,
                    tire = new TireSpec { radius = 0.54f, width = 0.375f, radialStiffness = 320000f, lugDepth = 0.026f, tread = TreadType.MudTerrain, inertia = 11f, rollingResistance = 0.022f },
                    brakeTorque = 5200f, springRate = 95000f, bumpDamping = 8500f, reboundDamping = 12500f, travelUp = 0.22f, travelDown = 0.28f, restLength = 0.5f,
                    antiRoll = 40000f, unsprungMass = 140f },
                new AxleDef { name = "Rear", z = -1.5f, track = 1.85f, hubY = 0.56f, steerFactor = 0f, drive = DriveMode.Always, handbrakeTorque = 4200f,
                    tire = new TireSpec { radius = 0.54f, width = 0.375f, radialStiffness = 320000f, lugDepth = 0.026f, tread = TreadType.MudTerrain, inertia = 11f, rollingResistance = 0.022f },
                    brakeTorque = 4200f, springRate = 105000f, bumpDamping = 9000f, reboundDamping = 13500f, travelUp = 0.22f, travelDown = 0.3f, restLength = 0.5f,
                    antiRoll = 34000f, unsprungMass = 150f },
            };
            d.fuelCapacity = 110f; d.idleFuelRate = 1.4f; d.fullLoadFuelRate = 28f;
            d.hasWinch = true; d.winchForce = 45000f; d.winchLength = 30f;
            d.hitchLocal = new Vector3(0f, 0.6f, -2.85f); d.maxTowMass = 7000f;
            d.fordingDepth = 1.05f; d.intakeLocal = new Vector3(0.9f, 1.1f, 1.3f); d.waterDragArea = 4.2f; d.displacedVolume = 5.0f;
            return d;
        }

        /// <summary>Heavy 6x6 hauler, ~10 t, big flotation-capable tyres, trailer/cargo capable.</summary>
        public static VehicleDefinition CreateHauler()
        {
            var d = CreateInstance<VehicleDefinition>();
            d.name = "Hauler";
            d.displayName = "Mammoth 6x6 Hauler";
            d.description = "Heavy 6x6 cargo hauler on huge tyres with high ground clearance. Floats over soft ground and pulls a trailer.";
            d.mass = 9000f;
            d.centerOfMass = new Vector3(0f, 1.05f, -0.1f);
            d.bodySize = new Vector3(2.5f, 1.4f, 7.2f);
            d.bodyCenter = new Vector3(0f, 1.6f, 0f);
            d.dragCdA = 3.8f;
            d.groundClearance = 0.55f;
            d.bodyPoints = BoxPoints(d.bodySize, d.bodyCenter, 0.16f);
            d.torqueCurve = Curve(700, 900, 1100, 1500, 1500, 1900, 2000, 1850, 2600, 1450, 3000, 1000);
            d.idleRpm = 650f; d.stallRpm = 300f; d.redlineRpm = 2800f; d.engineInertia = 2.2f; d.engineFriction = 60f; d.engineBrakingPerKrpm = 20f;
            d.gearbox = new GearboxDef
            {
                forwardRatios = new[] { 6.4f, 3.7f, 2.2f, 1.45f, 1.0f, 0.78f },
                reverseRatio = 6.0f, finalDrive = 5.4f, lowRangeRatio = 2.4f, efficiency = 0.88f, shiftTime = 0.6f,
                upshiftRpm = 2300f, downshiftRpm = 1000f,
            };
            d.frontTorqueShare = 0.34f;
            AxleDef Ax(string n, float z, float steer, DriveMode dm, float hp) => new AxleDef
            {
                name = n, z = z, track = 2.0f, hubY = 0.76f, steerFactor = steer, drive = dm, handbrakeTorque = hp,
                tire = new TireSpec { radius = 0.76f, width = 0.60f, radialStiffness = 260000f, lugDepth = 0.034f, tread = TreadType.Flotation, inertia = 28f, rollingResistance = 0.026f },
                brakeTorque = 9000f, springRate = 190000f, bumpDamping = 16000f, reboundDamping = 24000f, travelUp = 0.26f, travelDown = 0.34f, restLength = 0.66f,
                antiRoll = 70000f, unsprungMass = 260f,
            };
            d.axles = new[] { Ax("Front", 2.4f, 1f, DriveMode.Always, 0f), Ax("Mid", -0.5f, 0f, DriveMode.Always, 7000f), Ax("Rear", -2.0f, 0f, DriveMode.Always, 7000f) };
            d.fuelCapacity = 260f; d.idleFuelRate = 2.8f; d.fullLoadFuelRate = 55f;
            d.hasWinch = true; d.winchForce = 70000f; d.winchLength = 35f;
            d.hitchLocal = new Vector3(0f, 0.9f, -4.05f); d.maxTowMass = 16000f;
            d.fordingDepth = 1.45f; d.intakeLocal = new Vector3(1.1f, 1.5f, 2.2f); d.waterDragArea = 6.5f; d.displacedVolume = 9.0f;
            return d;
        }
    }
}
