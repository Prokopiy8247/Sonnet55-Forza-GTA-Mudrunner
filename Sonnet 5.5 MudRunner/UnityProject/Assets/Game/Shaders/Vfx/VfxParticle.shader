Shader "MudRunner/VfxParticle"
{
    // Billboard / stretched / horizontal particle shader of the VFX layer.
    // The sprite texture holds a VIEW-SPACE normal in RGB and coverage in A (see VfxTextures), so puffs, lumps and droplets are lit
    // by the sun + ambient (globals published by SkyController: _MR_VfxSunColor, _MR_VfxSunDir, _MR_VfxAmbient) and look like small 3D shapes.
    // Particle (vertex) colour = albedo tint. Soft against the scene depth, fades out near the camera, fogged.
    Properties
    {
        _MainTex ("Normal (rgb) / coverage (a) sprite", 2D) = "white" {}
        _Color ("Tint", Color) = (1, 1, 1, 1)
        _LightAmount ("Lighting amount (0 = unlit)", Range(0, 1)) = 1
        _Wrap ("Light wrap", Range(0, 1)) = 0.3
        _Spec ("Specular (wet)", Range(0, 2)) = 0
        _SpecPower ("Specular power", Range(4, 128)) = 32
        _Emissive ("Self illumination", Range(0, 2)) = 0
        _SoftDistance ("Soft particle distance (m, 0 = off)", Float) = 0.5
        _NearFade ("Near camera fade distance (m)", Float) = 0.8
        _AlphaMul ("Alpha multiplier", Float) = 1
        _AlphaPow ("Alpha contrast (>1 = crisper)", Float) = 1
        _FogAmount ("Fog amount", Range(0, 1)) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src blend", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst blend", Float) = 10
        [Enum(Off, 0, Front, 1, Back, 2)] _Cull ("Cull", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
            "PreviewType" = "Plane"
        }

        Pass
        {
            Name "VfxParticle"
            Tags { "LightMode" = "UniversalForward" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            ZTest LEqual
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 3.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma vertex Vert
            #pragma fragment Frag
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            float4 _MR_VfxSunColor;     // rgb = sun colour * intensity
            float4 _MR_VfxSunDir;       // xyz = direction TOWARDS the sun
            float4 _MR_VfxAmbient;      // rgb = ambient light colour

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _LightAmount;
                float _Wrap;
                float _Spec;
                float _SpecPower;
                float _Emissive;
                float _SoftDistance;
                float _NearFade;
                float _AlphaMul;
                float _AlphaPow;
                float _FogAmount;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                half4  color      : COLOR;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half4  color      : COLOR;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half   fogFactor  : TEXCOORD2;
                float  eyeDepth   : TEXCOORD3;
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.color = input.color;
                o.uv = TRANSFORM_TEX(input.uv, _MainTex);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                o.eyeDepth = -TransformWorldToView(o.positionWS).z;
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                half alpha = tex.a;
                alpha = pow(saturate(alpha), _AlphaPow) * i.color.a * _Color.a * _AlphaMul;

                float partEye = i.eyeDepth;
                if (_SoftDistance > 0.001)
                {
                    float2 suv = GetNormalizedScreenSpaceUV(i.positionCS);
                    float sceneEye = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                    alpha *= saturate((sceneEye - partEye) / _SoftDistance);
                }
                alpha *= saturate((partEye - _ProjectionParams.y) / max(_NearFade, 0.01));

                half3 albedo = i.color.rgb * _Color.rgb;
                half3 lit = albedo;
                if (_LightAmount > 0.001)
                {
                    float3 nVS = tex.rgb * 2.0 - 1.0;
                    float3 nWS = normalize(mul((float3x3)UNITY_MATRIX_I_V, nVS));
                    float3 L = _MR_VfxSunDir.xyz;
                    float ndl = saturate((dot(nWS, L) + _Wrap) / (1.0 + _Wrap));
                    float3 light = _MR_VfxAmbient.rgb * (0.78 + 0.22 * nWS.y) + _MR_VfxSunColor.rgb * ndl;
                    half3 shaded = albedo * light;
                    if (_Spec > 0.001)
                    {
                        float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                        float3 H = normalize(L + V);
                        shaded += _MR_VfxSunColor.rgb * (pow(saturate(dot(nWS, H)), _SpecPower) * _Spec);
                    }
                    lit = lerp(albedo, shaded, _LightAmount);
                }
                lit += albedo * _Emissive;
                half3 fogged = MixFog(lit, i.fogFactor);
                lit = lerp(lit, fogged, _FogAmount);
                return half4(lit, saturate(alpha));
            }
            ENDHLSL
        }
    }
    FallBack Off
}
