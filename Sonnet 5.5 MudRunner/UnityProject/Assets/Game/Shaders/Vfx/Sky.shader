Shader "MudRunner/Sky"
{
    // Skybox of the game (assigned to RenderSettings.skybox by SkyController): analytic gradient + horizon haze, sun disc + glow, moon,
    // stars, and a scrolling procedural cloud layer (planar projection of a tileable noise set) whose coverage / darkness follow overcast and rain.
    // All colours are driven from C# (palettes keyed by the sun elevation), so the same shader renders dawn, noon, dusk, night and storms.
    // The reflection probe / ambient are generated from this shader too (DynamicGI.UpdateEnvironment).
    Properties
    {
        _CloudTex ("Cloud noise (tileable)", 2D) = "gray" {}
        _ZenithColor ("Zenith", Color) = (0.16, 0.36, 0.78, 1)
        _HorizonColor ("Horizon", Color) = (0.62, 0.76, 0.92, 1)
        _GroundColor ("Below horizon", Color) = (0.30, 0.34, 0.38, 1)
        _GlowColor ("Sun glow", Color) = (1.0, 0.7, 0.4, 1)
        _SunColor ("Sun disc (HDR)", Color) = (30, 26, 20, 1)
        _MoonColor ("Moon disc (HDR)", Color) = (1.2, 1.3, 1.6, 1)
        _SunDir ("Sun direction (towards)", Vector) = (0, 1, 0, 0)
        _MoonDir ("Moon direction (towards)", Vector) = (0, -1, 0, 0)
        _P0 ("sun angular radius (rad), glow power, gradient power, haze falloff", Vector) = (0.0105, 1, 0.45, 7)
        _P1 ("star intensity, cloud cover, cloud opacity, cloud scale", Vector) = (0, 0.35, 0.9, 1.1)
        _Wind ("cloud drift uv/s (xy), -, -", Vector) = (0.004, 0.0015, 0, 0)
        _CloudLit ("Cloud lit colour", Color) = (1.0, 1.0, 1.0, 1)
        _CloudShade ("Cloud shade colour", Color) = (0.55, 0.6, 0.7, 1)
        _SunVis ("sun visibility (clouds / overcast), moon visibility, exposure, -", Vector) = (1, 0, 1, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Background" "Queue" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off
        ZWrite Off

        Pass
        {
            Name "Sky"

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_CloudTex);
            SAMPLER(sampler_CloudTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _CloudTex_ST;
                float4 _ZenithColor;
                float4 _HorizonColor;
                float4 _GroundColor;
                float4 _GlowColor;
                float4 _SunColor;
                float4 _MoonColor;
                float4 _SunDir;
                float4 _MoonDir;
                float4 _P0;
                float4 _P1;
                float4 _Wind;
                float4 _CloudLit;
                float4 _CloudShade;
                float4 _SunVis;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 dir : TEXCOORD0; };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.dir = input.positionOS.xyz;
                return o;
            }

            float Hash13(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            float3 Stars(float3 d, float intensity)
            {
                if (intensity <= 0.001) return 0;
                float3 p = d * 140.0;
                float3 cell = floor(p);
                float3 f = frac(p) - 0.5;
                float h = Hash13(cell);
                float3 jitter = float3(Hash13(cell + 7.1), Hash13(cell + 13.7), Hash13(cell + 29.3)) - 0.5;
                float dist = length(f - jitter * 0.6);
                float star = step(0.985, h) * smoothstep(0.34, 0.0, dist);
                float mag = Hash13(cell + 3.3);
                float3 tint = lerp(float3(0.8, 0.9, 1.0), float3(1.0, 0.85, 0.7), Hash13(cell + 5.9));
                return tint * star * (0.3 + 1.7 * mag * mag) * intensity;
            }

            float CloudDensity(float2 uv, out float macro)
            {
                float3 n1 = SAMPLE_TEXTURE2D_LOD(_CloudTex, sampler_CloudTex, uv * 0.35, 0).rgb;
                float3 n2 = SAMPLE_TEXTURE2D_LOD(_CloudTex, sampler_CloudTex, uv * 1.05 + 0.31, 0).rgb;
                float3 n3 = SAMPLE_TEXTURE2D_LOD(_CloudTex, sampler_CloudTex, uv * 2.7 + 0.67, 0).rgb;
                macro = SAMPLE_TEXTURE2D_LOD(_CloudTex, sampler_CloudTex, uv * 0.11 + 0.5, 0).a;
                return n1.r * 0.52 + n2.g * 0.28 + n3.b * 0.12 + n2.b * 0.08;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float h = d.y;

                // ---- gradient + haze
                float tz = pow(saturate(h), _P0.z);
                float3 sky = lerp(_HorizonColor.rgb, _ZenithColor.rgb, tz);
                float haze = exp(-max(h, 0.0) * _P0.w);
                sky = lerp(sky, _HorizonColor.rgb, haze * 0.55);
                sky = lerp(sky, _GroundColor.rgb, smoothstep(0.0, -0.20, h));

                // ---- sun glow + disc
                float sd = dot(d, _SunDir.xyz);
                float glow = pow(saturate(sd), 5.0) * 0.32 + pow(saturate(sd), 42.0) * 0.55;
                sky += _GlowColor.rgb * glow * (0.35 + 0.65 * haze) * _P0.y;
                float cosR = cos(_P0.x);
                float disc = smoothstep(cosR - 0.00007, cosR + 0.00004, sd);
                float limb = lerp(0.82, 1.0, saturate((sd - cosR) / (1.0 - cosR) * 1.0));
                float3 sunDisc = _SunColor.rgb * disc * limb * smoothstep(-0.04, 0.03, h);

                // ---- moon
                float md = dot(d, _MoonDir.xyz);
                float cosM = cos(0.0105);
                float mdisc = smoothstep(cosM - 0.00006, cosM + 0.00004, md);
                float mglow = pow(saturate(md), 90.0) * 0.07;
                float3 moon = (_MoonColor.rgb * mdisc * smoothstep(-0.02, 0.03, h) + _MoonColor.rgb * mglow * 0.25) * _SunVis.y;

                // ---- stars
                float3 stars = Stars(d, _P1.x) * smoothstep(0.02, 0.2, h);

                // ---- clouds
                float cloudMask = 0.0;
                if (h > -0.02)
                {
                    float2 uv = d.xz / (max(h, 0.0) + 0.14) * _P1.w + _Wind.xy * _Time.y;
                    float macro;
                    float dens = CloudDensity(uv, macro);
                    float cover = saturate(_P1.y);
                    float thr = lerp(0.74, 0.20, cover) + (macro - 0.5) * 0.12;
                    float cl = smoothstep(thr, thr + lerp(0.10, 0.32, cover), dens);
                    cl *= smoothstep(-0.02, 0.16, h);

                    float macro2;
                    float dens2 = CloudDensity(uv + _SunDir.xz * 0.045 / (max(_SunDir.y, 0.15) + 0.2), macro2);
                    float lightMask = saturate((dens - dens2) * 5.0 + 0.55);
                    float thick = saturate((dens - thr) * 3.0);
                    float3 cloudCol = lerp(_CloudShade.rgb, _CloudLit.rgb, lightMask * (1.0 - 0.35 * thick) + 0.18 * (1.0 - thick));
                    // silver lining near the sun
                    cloudCol += _GlowColor.rgb * pow(saturate(sd), 8.0) * (1.0 - thick) * 0.35;
                    cloudMask = cl * _P1.z;
                    sky = lerp(sky, cloudCol, cloudMask);
                }

                float3 col = sky + (sunDisc + moon + stars) * (1.0 - cloudMask * 0.95) * lerp(1.0, _SunVis.x, 0.0);
                col *= _SunVis.z;
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
