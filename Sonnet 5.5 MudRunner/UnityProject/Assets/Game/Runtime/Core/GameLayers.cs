using UnityEngine;

namespace MudRunner
{
    /// <summary>
    /// Physics layers used by the project. Names/indices are applied by
    /// MudRunner.EditorTools.ProjectSetup (menu: MudRunner/Setup/Apply Project Settings).
    /// </summary>
    public static class GameLayers
    {
        public const int Terrain = 6;       // TerrainCollider (smooth physical ground). Vehicle bodies do NOT collide with it.
        public const int Props = 7;         // static colliders: rocks, trees, buildings, bridges, fences
        public const int VehicleBody = 8;   // chassis / trailer / cab colliders
        public const int DynamicProps = 9;  // logs, barrels, crates, other loose rigid bodies
        public const int Triggers = 10;     // gameplay trigger volumes
        public const int Anchors = 11;      // winch anchor pick colliders (raycast only)
        public const int Debris = 12;       // small visual physics bits (no vehicle collision)

        public static readonly (int index, string name)[] Names =
        {
            (Terrain, "Terrain"),
            (Props, "Props"),
            (VehicleBody, "VehicleBody"),
            (DynamicProps, "DynamicProps"),
            (Triggers, "Triggers"),
            (Anchors, "Anchors"),
            (Debris, "Debris"),
        };

        /// <summary>Layers a wheel/suspension cast can hit (never the vehicle's own body).</summary>
        public static readonly int WheelCastMask = (1 << Terrain) | (1 << Props) | (1 << DynamicProps);

        /// <summary>Layers the chase camera collides with.</summary>
        public static readonly int CameraMask = (1 << Terrain) | (1 << Props);

        public static readonly int AnchorMask = (1 << Anchors);
    }
}
