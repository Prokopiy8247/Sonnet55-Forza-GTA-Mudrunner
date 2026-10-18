#ifndef MR_GROUND_COMMON_INCLUDED
#define MR_GROUND_COMMON_INCLUDED

// Shared declarations + geometry (vertex displacement) functions of the MudRunner/Ground shader.
// All maps are sampled by WORLD position:  macro height from the baked map textures, dynamic deformation from
// the global _MR_MudField window texture (R = dh, G = churn, B = compaction).

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

// ---------------------------------------------------------------------------------------------- textures
TEXTURE2D(_GR_Height);            // R32F  whole map, clamp, bilinear
TEXTURE2D(_GR_NormalMap);         // RGHalf: macro normal xz (y reconstructed), clamp, bilinear
TEXTURE2D(_GR_Control0);          // RGBA8 layers 0..3
TEXTURE2D(_GR_Control1);          // RGBA8 layers 4..7
TEXTURE2D(_GR_Params);            // RG8   extraDepth01, baseWet
TEXTURE2D_ARRAY(_GR_Albedo);      // RGBA32 sRGB: albedo + smoothness
TEXTURE2D_ARRAY(_GR_Normal);      // RGBA32: normal xy, height
SAMPLER(sampler_GR_Albedo);       // aniso 8 trilinear repeat (shared by the normal array)
TEXTURE2D(_GR_Macro);             // tileable variation noise
TEXTURE2D(_GR_Detail);            // tileable detail normal
SAMPLER(sampler_GR_Macro);

TEXTURE2D(_MR_MudField);          // global, RGBAHalf, repeat, bilinear
SAMPLER(sampler_MR_MudField);

// ---------------------------------------------------------------------------------------------- globals (GroundService)
float4 _MR_MudParams;             // x = cell size, y = window world size, z = 1/window size, w = enabled
float4 _MR_MudWindowOrigin;       // xy = world XZ of the window min corner
float  _MR_Wetness;               // 0..1 rain
float  _MR_DebugMode;             // 0 off, 1 surface type, 2 dh, 3 churn, 4 lod, 5 macro normal

// ---------------------------------------------------------------------------------------------- per material (SRP Batcher)
CBUFFER_START(UnityPerMaterial)
    float4 _GR_Map;               // xy = world XZ of map sample (0,0), z = 1/cell, w = 1/size
    float4 _GR_MapRange;          // xy = world min XZ of the map, zw = world max XZ
    float4 _GR_Tiling;            // x = 1/tileA (1/m), y = 1/tileB, z = macro low scale, w = macro mid scale
    float4 _GR_LayerScale0;       // per layer uv multiplier, layers 0..3
    float4 _GR_LayerScale1;       // layers 4..7
    float4 _GR_WetSens0;          // wetness sensitivity per layer (SurfaceDatabase)
    float4 _GR_WetSens1;
    float4 _GR_Misc;              // x = skirt drop (m), y = field normal gain, z = detail uv scale (1/m), w = unused
    float4 _GR_Misc2;             // x = normal strength, y = ripple strength, z = puddle level scale, w = unused
CBUFFER_END

// ---------------------------------------------------------------------------------------------- helpers
float2 GR_MapUV(float2 xz)
{
    return ((xz - _GR_Map.xy) * _GR_Map.z + 0.5) * _GR_Map.w;
}

// 0 at the border of the field window, 1 deeper than 12 m inside. Also 0 when the field is disabled.
float GR_WindowFade(float2 xz)
{
    float2 d = min(xz - _MR_MudWindowOrigin.xy, _MR_MudWindowOrigin.xy + _MR_MudParams.y - xz);
    return smoothstep(0.0, 12.0, min(d.x, d.y)) * (_MR_MudParams.w > 0.5 ? 1.0 : 0.0);
}

float4 GR_SampleFieldRaw(float2 xz)
{
    return SAMPLE_TEXTURE2D_LOD(_MR_MudField, sampler_MR_MudField, xz * _MR_MudParams.z, 0);
}

// (dh, churn, compaction, fade) already multiplied by the window fade
float4 GR_SampleField(float2 xz)
{
    float f = GR_WindowFade(xz);
    float3 m = GR_SampleFieldRaw(xz).rgb;
    return float4(m * f, f);
}

float GR_MacroHeight(float2 xz)
{
    return SAMPLE_TEXTURE2D_LOD(_GR_Height, sampler_LinearClamp, GR_MapUV(xz), 0).r;
}

float3 GR_MacroNormal(float2 xz)
{
    float2 nm = SAMPLE_TEXTURE2D_LOD(_GR_NormalMap, sampler_LinearClamp, GR_MapUV(xz), 0).rg;
    float ny = sqrt(max(1e-4, 1.0 - dot(nm, nm)));
    return float3(nm.x, ny, nm.y);
}

// dh gradient (dh/dx, dh/dz) from central differences at +-1 field texel
float2 GR_FieldGradient(float2 xz)
{
    float e = max(_MR_MudParams.x, 0.01);
    float f = GR_WindowFade(xz);
    float dl = GR_SampleFieldRaw(xz - float2(e, 0)).r;
    float dr = GR_SampleFieldRaw(xz + float2(e, 0)).r;
    float dd = GR_SampleFieldRaw(xz - float2(0, e)).r;
    float du = GR_SampleFieldRaw(xz + float2(0, e)).r;
    return float2(dr - dl, du - dd) * (0.5 / e) * f;
}

// normal of (macro height + dh)
float3 GR_CombinedNormal(float3 nMacro, float2 fieldGrad)
{
    float2 g = -nMacro.xz / nMacro.y + fieldGrad;
    return normalize(float3(-g.x, 1.0, -g.y));
}

// World position of a grid vertex: chunk grid (x,z) + macro height + dynamic dh; skirt vertices drop.
float3 GR_WorldPosition(float3 positionOS, float skirt)
{
    float3 pw = TransformObjectToWorld(float3(positionOS.x, 0.0, positionOS.z));
    pw.xz = clamp(pw.xz, _GR_MapRange.xy, _GR_MapRange.zw);          // collapses everything outside the map onto its border
    float h = GR_MacroHeight(pw.xz);
    float dh = GR_SampleFieldRaw(pw.xz).r * GR_WindowFade(pw.xz);
    pw.y = h + dh - skirt * _GR_Misc.x;
    return pw;
}

#endif
