Shader "MudRunner/Ground"
{
    // Deformable ground: flat chunk grids displaced in the vertex shader from the baked macro height map and the
    // dynamic mud field (_MR_MudField, global). 8 procedural surface layers (Texture2DArray) blended by two control maps.
    // Properties are set by MudRunner.Rendering.GroundRenderer - edit them there, not in the inspector.
    Properties
    {
        [NoScaleOffset] _GR_Height ("Macro height (R32F)", 2D) = "black" {}
        [NoScaleOffset] _GR_NormalMap ("Macro normal (RG half)", 2D) = "black" {}
        [NoScaleOffset] _GR_Control0 ("Control 0 (layers 0-3)", 2D) = "black" {}
        [NoScaleOffset] _GR_Control1 ("Control 1 (layers 4-7)", 2D) = "black" {}
        [NoScaleOffset] _GR_Params ("Params (extraDepth, baseWet)", 2D) = "black" {}
        [NoScaleOffset] _GR_Albedo ("Albedo+smoothness array", 2DArray) = "" {}
        [NoScaleOffset] _GR_Normal ("Normal+height array", 2DArray) = "" {}
        [NoScaleOffset] _GR_Macro ("Macro variation", 2D) = "gray" {}
        [NoScaleOffset] _GR_Detail ("Detail normal", 2D) = "bump" {}

        [HideInInspector] _GR_Map ("Map (origin xy, 1/cell, 1/size)", Vector) = (0, 0, 1, 0.001)
        [HideInInspector] _GR_MapRange ("Map range (min xz, max xz)", Vector) = (0, 0, 1000, 1000)
        [HideInInspector] _GR_Tiling ("Tiling (1/tileA, 1/tileB, macroLow, macroMid)", Vector) = (0.3125, 0.0518, 0.0189, 0.0885)
        [HideInInspector] _GR_LayerScale0 ("Layer scale 0-3", Vector) = (0.8, 1.0, 1.1, 1.3)
        [HideInInspector] _GR_LayerScale1 ("Layer scale 4-7", Vector) = (0.9, 0.7, 0.8, 1.0)
        [HideInInspector] _GR_WetSens0 ("Wet sensitivity 0-3", Vector) = (0.15, 0.55, 0.8, 0.35)
        [HideInInspector] _GR_WetSens1 ("Wet sensitivity 4-7", Vector) = (1.0, 1.0, 1.0, 0.35)
        [HideInInspector] _GR_Misc ("Misc (skirt drop, field normal gain, detail scale, -)", Vector) = (2.5, 1.0, 1.6, 0)
        [HideInInspector] _GR_Misc2 ("Misc2 (normal strength, ripple, puddle level scale, -)", Vector) = (1.0, 0.18, 1.0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "Queue" = "Geometry"
            "IgnoreProjector" = "True"
        }
        LOD 300

        // ---------------------------------------------------------------------------------------- forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore

            #pragma vertex GroundVert
            #pragma fragment GroundFrag

            // Universal pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"

            #include "GroundForward.hlsl"
            ENDHLSL
        }

        // ---------------------------------------------------------------------------------------- shadow caster
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore

            #pragma vertex GroundShadowVert
            #pragma fragment GroundShadowFrag

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #define GR_PASS_SHADOW
            #include "GroundPasses.hlsl"
            ENDHLSL
        }

        // ---------------------------------------------------------------------------------------- depth only
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore

            #pragma vertex GroundDepthVert
            #pragma fragment GroundDepthFrag

            #define GR_PASS_DEPTH
            #include "GroundPasses.hlsl"
            ENDHLSL
        }

        // ---------------------------------------------------------------------------------------- depth normals (SSAO, etc.)
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore

            #pragma vertex GroundDepthNormalsVert
            #pragma fragment GroundDepthNormalsFrag

            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            #define GR_PASS_DEPTHNORMALS
            #include "GroundPasses.hlsl"
            ENDHLSL
        }
    }

    FallBack Off
}
