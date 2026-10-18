using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>
    /// Connects a Blender-authored model (children named Wheel_FL, Wheel_FR, Wheel_RL ... ) to the physics wheels.
    /// Filled in by the editor VehiclePrefabBuilder; at runtime <see cref="Bind"/> just hands the transforms to the Vehicle.
    /// Wheel order must match Vehicle.wheels (axle-major, left then right).
    /// </summary>
    public sealed class VehicleVisualBinder : MonoBehaviour
    {
        public Transform[] wheelVisuals;

        public void Bind(Vehicle v)
        {
            v.wheelVisuals = wheelVisuals;
            v.visualRoot = transform;
            VehicleAnchors.Collect(gameObject).Apply(v);
            var sv = GetComponent<SuspensionVisuals>() ?? gameObject.AddComponent<SuspensionVisuals>();
            sv.Setup(v);
            var vl = GetComponent<VehicleLights>() ?? gameObject.AddComponent<VehicleLights>();
            vl.Setup(v);
        }
    }
}
