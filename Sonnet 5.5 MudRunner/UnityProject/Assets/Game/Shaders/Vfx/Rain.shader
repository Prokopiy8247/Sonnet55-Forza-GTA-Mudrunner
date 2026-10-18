Shader "MudRunner/Rain"
{
    // GPU rain: a static mesh of N camera facing streak quads (see RainMesh in WeatherVfx). The vertex shader animates every streak
    // (falling + wind slant) inside a camera centred box whose pattern is anchored in world space, so no CPU work, no allocations.
    // _MR_Weather.x = rain intensity (0..1 thins the streaks out), .yz = wind. Two materials (near / far box) are drawn.
    Properties
    {
        _Box ("Box size (m)", Vector) = (18, 14, 18, 0)
        _Fall ("Fall speed, streak length, streak width, alpha", Vector) = (9.5, 0.55, 0.012, 0.28)
        _Tint ("Tint", Color) = (0.82, 0.88, 0.95, 1)
        _MinPixel ("Minimum streak width in pixels", Float) = 1.2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent+20"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "Rain"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma target 3.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma vertex Vert
            #pragma fragment Frag
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _MR_Weather;          // x = rain, yz = wind (m/s), w = overcast
            float4 _MR_VfxSunColor;
            float4 _MR_VfxAmbient;
            float4 _MR_CamVel;           // xyz camera velocity (m/s)

            CBUFFER_START(UnityPerMaterial)
                float4 _Box;
                float4 _Fall;
                float4 _Tint;
                float _MinPixel;
            CBUFFER_END

            struct Attributes
            {
                float3 seed   : POSITION;     // 0..1 random position inside the box
                float4 rnd    : COLOR;        // 4 random numbers
                float2 corner : TEXCOORD0;    // x: 0..1 across, y: 0 = head, 1 = tail
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float  alpha      : TEXCOORD1;
                half   fogFactor  : TEXCOORD2;
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                o.uv = input.corner;
                float rain = _MR_Weather.x;
                float3 box = _Box.xyz;
                float3 cam = _WorldSpaceCameraPos;

                float speed = _Fall.x * (0.85 + 0.3 * input.rnd.r);
                float3 wind = float3(_MR_Weather.y, 0.0, _MR_Weather.z);
                float3 vel = float3(wind.x * 0.55, -speed, wind.z * 0.55);

                // world anchored lattice of streaks, wrapped around the camera
                float3 p0 = input.seed * box + vel * _Time.y;
                float3 local = frac((p0 - cam) / box);                          // 0..1 inside the box, camera at 0.5
                float3 world = cam + (local - 0.5) * box;

                // streak orientation follows the velocity relative to the camera
                float3 rel = vel - _MR_CamVel.xyz * 0.45;
                float relSpeed = max(length(rel), 0.01);
                float3 vdir = rel / relSpeed;
                float len = _Fall.y * (0.6 + 0.8 * input.rnd.g) * (relSpeed / _Fall.x);

                float3 toCam = normalize(cam - world);
                float3 right = normalize(cross(vdir, toCam));
                float dist = distance(cam, world);
                float widthWorld = max(_Fall.z, dist * _MinPixel * 0.0011);
                float3 pos = world - vdir * len * input.corner.y + right * (input.corner.x - 0.5) * 2.0 * widthWorld;

                o.positionCS = TransformWorldToHClip(pos);

                // fades: intensity thinning, near camera, box borders
                float keep = step(input.rnd.b, saturate(rain * 1.05));
                float edge = smoothstep(0.0, 0.12, local.y) * smoothstep(1.0, 0.82, local.y);
                float2 hxz = abs(local.xz - 0.5) * 2.0;
                float side = 1.0 - smoothstep(0.7, 1.0, max(hxz.x, hxz.y));
                float nearFade = smoothstep(0.35, 1.8, dist);
                float energy = _Fall.z / widthWorld;
                o.alpha = keep * edge * side * nearFade * energy * _Fall.w * (0.7 + 0.5 * input.rnd.a);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float across = 1.0 - abs(i.uv.x * 2.0 - 1.0);
                float along = smoothstep(0.0, 0.08, i.uv.y) * pow(saturate(1.0 - i.uv.y), 0.8);
                float a = i.alpha * across * across * along;
                half3 col = (_MR_VfxAmbient.rgb * 0.95 + _MR_VfxSunColor.rgb * 0.16) * _Tint.rgb;
                col = MixFog(col, i.fogFactor);
                return half4(col, saturate(a));
            }
            ENDHLSL
        }
    }
    FallBack Off
}
