using UnityEngine;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Shader / material lookup of the VFX layer. Base material assets live in Resources/MudRunner/Vfx (created by the editor script
    /// VfxMaterialAssets, so the shaders are included in player builds); in the editor the shaders are also found by name.
    /// </summary>
    public static class VfxResources
    {
        public const string Folder = "MudRunner/Vfx/";

        static Shader particle, water, vehicleLit, sky, rain;

        public static Shader ParticleShader => Find(ref particle, "MudRunner/VfxParticle", "VfxParticle");
        public static Shader WaterShader => Find(ref water, "MudRunner/Water", "Water");
        public static Shader VehicleLitShader => Find(ref vehicleLit, "MudRunner/VehicleLit", "VehicleLit");
        public static Shader SkyShader => Find(ref sky, "MudRunner/Sky", "Sky");
        public static Shader RainShader => Find(ref rain, "MudRunner/Rain", "Rain");

        static Shader Find(ref Shader slot, string shaderName, string resName)
        {
            if (slot != null) return slot;
            var m = Resources.Load<Material>(Folder + resName);
            if (m != null && m.shader != null && m.shader.isSupported) slot = m.shader;
            if (slot == null) slot = Shader.Find(shaderName);
            if (slot == null) Debug.LogWarning("[MudRunner] VFX shader not found: " + shaderName);
            return slot;
        }

        public static Material NewMaterial(Shader sh, string name)
        {
            if (sh == null) return null;
            return new Material(sh) { name = name, hideFlags = HideFlags.DontSave };
        }
    }
}
