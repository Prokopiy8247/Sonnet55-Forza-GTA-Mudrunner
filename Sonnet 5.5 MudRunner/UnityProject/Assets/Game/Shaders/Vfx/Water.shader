Shader "MudRunner/Water"
{
    // Water surface of the WaterRenderer chunks (flat world-space meshes, per-vertex current / murkiness / depth in the vertex colour).
    //  * flow-map blended scrolling normals along the current, wind drift on still water, rain ripples (_MR_Weather.x)
    //  * depth based colour + absorption using the URP depth texture (true vertical depth at every pixel), refraction of _CameraOpaqueTexture
    //  * Fresnel reflection of sky / reflection probes and sun / headlight glints through UniversalFragmentPBR (specular only)
    //  * shore foam: wherever ANY opaque geometry (bank, rock, tyre, hull) is within a few cm of the surface, plus turbulence foam in fast shallow water
    // Needs the camera depth + opaque textures (PC_RPAsset has both on; WaterRenderer also forces them on the main camera).
    Properties
    {
        _WaterTex ("Normal(rg) height(b) foam(a)", 2D) = "gray" {}
        _ShallowColor ("Shallow body colour", Color) = (0.10, 0.30, 0.27, 1)
        _DeepColor ("Deep body colour", Color) = (0.015, 0.075, 0.10, 1)
        _MurkColor ("Murky body colour", Color) = (0.12, 0.14, 0.05, 1)
        _FoamColor ("Foam colour", Color) = (0.86, 0.9, 0.92, 1)
        _Absorb ("Absorption per metre (rgb)", Color) = (0.50, 0.16, 0.11, 1)
        _AbsorbMurk ("Absorption murky (rgb)", Color) = (1.3, 0.75, 0.95, 1)
        _P0 ("Normal strength, refraction, roughness, unused", Vector) = (1.0, 0.045, 0.08, 0)
        _P1 ("Depth range (m), foam width (m), foam strength, body light", Vector) = (2.5, 0.22, 1.0, 1.0)
        _Tiling ("uv scale A, uv scale B, flow uv per m/s, flow phase speed", Vector) = (0.31, 1.13, 0.22, 0.45)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent-20"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "WaterForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma vertex Vert
            #pragma fragment Frag

            #define _SURFACE_TYPE_TRANSPARENT 1
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_WaterTex);
            SAMPLER(sampler_WaterTex);

            float4 _MR_Weather;          // x = rain 0..1, yz = wind (m/s, world xz), w = overcast

            CBUFFER_START(UnityPerMaterial)
                float4 _WaterTex_ST;
                float4 _ShallowColor;
                float4 _DeepColor;
                float4 _MurkColor;
                float4 _FoamColor;
                float4 _Absorb;
                float4 _AbsorbMurk;
                float4 _P0;
                float4 _P1;
                float4 _Tiling;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                float4 color      : COLOR;      // r,g = current (0.5 = none, +-6.4 m/s), b = murkiness, a = (unused)
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 attr       : TEXCOORD1;
                half   fogFactor  : TEXCOORD2;
                float  eyeDepth   : TEXCOORD3;
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.attr = input.color;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                o.eyeDepth = -TransformWorldToView(o.positionWS).z;
                return o;
            }

            float2 Hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            // one layer of rain rings (expanding rings in random cells); returns a normal offset
            float2 RippleLayer(float2 p, float t, float density)
            {
                float2 cell = floor(p);
                float2 f = frac(p) - 0.5;
                float2 r = Hash22(cell);
                float2 c = (r - 0.5) * 0.45;
                float phase = frac(t * 1.15 + r.x * 7.31);
                float isOn = step(r.y, density);
                float2 d = f - c;
                float dist = length(d);
                float radius = phase * 0.5;
                float x = (dist - radius) / 0.05;
                float ring = exp(-x * x) * (1.0 - phase) * (1.0 - phase);
                return d / max(dist, 1e-3) * ring * isOn;
            }

            float3 WaterNormal(float2 xz, float2 flow, float dist, float rain)
            {
                float t = _Time.y * _Tiling.w;
                float2 f = flow * _Tiling.z;
                float p0 = frac(t), p1 = frac(t + 0.5);
                float w = abs(1.0 - 2.0 * p0);                           // weight of layer 0 (undistorted at phase 0)
                float amp = rsqrt(w * w + (1.0 - w) * (1.0 - w));         // keeps the blended normal amplitude constant

                float2 uvA = xz * _Tiling.x;
                float2 a0 = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, uvA - f * p0).rg;
                float2 a1 = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, uvA - f * p1 + float2(0.5, 0.31)).rg;
                float2 nA = (lerp(a1, a0, w) * 2.0 - 1.0) * amp;

                float2 uvB = xz * _Tiling.y + float2(0.23, 0.61);
                float2 b0 = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, uvB - f * 1.6 * p0).rg;
                float2 b1 = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, uvB - f * 1.6 * p1 + float2(0.5, 0.73)).rg;
                float2 nB = (lerp(b1, b0, w) * 2.0 - 1.0) * amp;

                float farFade = lerp(1.0, 0.18, saturate((dist - 45.0) / 220.0));
                float detailFade = 1.0 - saturate((dist - 25.0) / 90.0);
                float2 n = (nA * 0.62 + nB * 0.38 * detailFade) * _P0.x * farFade;
                n *= 1.0 + length(flow) * 0.25;

                if (rain > 0.02)
                {
                    float2 rr = RippleLayer(xz * 1.9, _Time.y, rain) + RippleLayer(xz * 3.1 + 17.3, _Time.y * 1.3 + 3.0, rain);
                    n += rr * 1.1 * lerp(1.0, 0.25, saturate((dist - 20.0) / 60.0));
                    n *= 1.0 + rain * 0.6;
                }
                return normalize(float3(n.x, 1.0, n.y));
            }

            half4 Frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 posWS = i.positionWS;
                float3 V = normalize(_WorldSpaceCameraPos - posWS);
                float dist = distance(_WorldSpaceCameraPos, posWS);
                float2 suv = GetNormalizedScreenSpaceUV(i.positionCS);

                // ---- seen from below the surface: a flat murky fog, nothing fancy
                if (!IS_FRONT_VFACE(face, true, false))
                {
                    half3 under = _DeepColor.rgb * 3.0 + _ShallowColor.rgb * 0.5;
                    half3 fogged = MixFog(under, i.fogFactor);
                    return half4(fogged, 0.82);
                }

                float2 flow = (i.attr.xy * 2.0 - 1.0) * 6.4;
                float murk = i.attr.z;
                float speed = length(flow);
                float2 wind = _MR_Weather.yz;
                float2 drift = flow + wind * 0.06 + float2(0.05, 0.03);
                float rain = _MR_Weather.x;

                float3 nWS = WaterNormal(posWS.xz, drift, dist, rain);

                // ---- scene depth under the surface
                float rawD = SampleSceneDepth(suv);
                float3 scenePos = ComputeWorldSpacePosition(suv, rawD, UNITY_MATRIX_I_VP);
                float thickness = max(0.0, distance(scenePos, posWS));
                float vertical = max(0.0, posWS.y - scenePos.y);
#if UNITY_REVERSED_Z
                if (rawD <= 0.00001) { thickness = 500.0; vertical = 50.0; }       // nothing behind (sky / beyond far plane)
#else
                if (rawD >= 0.99999) { thickness = 500.0; vertical = 50.0; }
#endif

                // ---- light
                float4 shadowCoord = TransformWorldToShadowCoord(posWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 sunLight = mainLight.color * mainLight.shadowAttenuation;
                half3 ambient = SampleSH(half3(0, 1, 0));
                half bodyLight = (dot(ambient, half3(0.33, 0.33, 0.33)) + dot(sunLight, half3(0.33, 0.33, 0.33)) * 0.30) * _P1.w;
                bodyLight = saturate(bodyLight * 0.9 + 0.012);

                // ---- refraction
                float depthFade = saturate(vertical * 1.6);
                float2 refrUV = suv + nWS.xz * _P0.y * depthFade / (1.0 + dist * 0.015);
                float eyeRefr = LinearEyeDepth(SampleSceneDepth(refrUV), _ZBufferParams);
                refrUV = eyeRefr < i.eyeDepth ? suv : refrUV;
                half3 bed = SampleSceneColor(refrUV);

                // ---- body colour + absorption
                half3 absorb = lerp(_Absorb.rgb, _AbsorbMurk.rgb, murk);
                half3 T = exp(-thickness * absorb);
                float dT = saturate(vertical / max(_P1.x, 0.1));
                half3 body = lerp(_ShallowColor.rgb, _DeepColor.rgb, dT);
                body = lerp(body, _MurkColor.rgb * (0.6 + 0.4 * (1.0 - dT)), murk * 0.85);
                body *= bodyLight;
                half3 underColor = bed * T + body * (1.0 - T);

                // ---- reflections / glints (specular only: albedo 0)
                InputData inputData = (InputData)0;
                inputData.positionWS = posWS;
                inputData.positionCS = i.positionCS;
                inputData.normalWS = nWS;
                inputData.viewDirectionWS = V;
                inputData.shadowCoord = shadowCoord;
                inputData.fogCoord = i.fogFactor;
                inputData.vertexLighting = half3(0, 0, 0);
                inputData.bakedGI = half3(0, 0, 0);
                inputData.normalizedScreenSpaceUV = suv;
                inputData.shadowMask = half4(1, 1, 1, 1);
                SurfaceData sd = (SurfaceData)0;
                sd.albedo = half3(0, 0, 0);
                sd.metallic = 0.0;
                sd.specular = half3(0, 0, 0);
                sd.smoothness = 1.0 - _P0.z;
                sd.normalTS = half3(0, 0, 1);
                sd.emission = half3(0, 0, 0);
                sd.occlusion = 1.0;
                sd.alpha = 1.0;
                half4 spec = UniversalFragmentPBR(inputData, sd);

                float NoV = saturate(dot(nWS, V));
                float fres = 0.02 + 0.98 * pow(1.0 - NoV, 5.0);
                fres = saturate(fres * 1.0);
                half3 color = underColor * (1.0 - fres * 0.85) + spec.rgb;

                // ---- foam
                float2 fuv = posWS.xz;
                float foamA = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, fuv * 0.55 + drift * (_Time.y * 0.05)).a;
                float foamB = SAMPLE_TEXTURE2D(_WaterTex, sampler_WaterTex, fuv * 1.3 - drift * (_Time.y * 0.08) + 0.37).a;
                float foamTex = foamA * 0.6 + foamB * 0.4;
                float edgeN = (foamTex - 0.5) * 0.20;
                float shore = 1.0 - smoothstep(0.0, _P1.y, vertical + edgeN);
                shore *= saturate(0.35 + foamTex * 1.2);
                float shallow = 1.0 - smoothstep(0.35, 1.8, vertical);
                float turb = saturate((speed - 0.9) / 1.4) * shallow * saturate(foamTex * 1.4 - 0.25) * 0.65;
                float foam = saturate(shore + turb) * _P1.z;
                half3 foamCol = _FoamColor.rgb * (0.18 + bodyLight * 1.1 + dot(sunLight, half3(0.3, 0.3, 0.3)) * 0.5);
                color = lerp(color, foamCol, foam);

                float alpha = saturate(vertical * 7.0 + foam);
                color = MixFog(color, i.fogFactor);
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
