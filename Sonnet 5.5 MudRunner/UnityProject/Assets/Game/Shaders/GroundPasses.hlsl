#ifndef MR_GROUND_PASSES_INCLUDED
#define MR_GROUND_PASSES_INCLUDED

// ShadowCaster / DepthOnly / DepthNormals passes of MudRunner/Ground. They use exactly the same displaced
// geometry as the forward pass, so the deformed ground casts / receives correct shadows and feeds SSAO.

#include "GroundCommon.hlsl"

struct GRPAttributes
{
    float3 positionOS : POSITION;
    float2 uv         : TEXCOORD0;
};

// ------------------------------------------------------------------------------------------------ shadow caster
#if defined(GR_PASS_SHADOW)
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

float3 _LightDirection;
float3 _LightPosition;

struct GRShadowVaryings
{
    float4 positionCS : SV_POSITION;
};

GRShadowVaryings GroundShadowVert(GRPAttributes input)
{
    GRShadowVaryings o;
    float3 pw = GR_WorldPosition(input.positionOS, input.uv.x);
    float3 normalWS = GR_MacroNormal(pw.xz);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - pw);
#else
    float3 lightDirectionWS = _LightDirection;
#endif
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(pw, normalWS, lightDirectionWS));
    o.positionCS = ApplyShadowClamping(positionCS);
    return o;
}

half4 GroundShadowFrag(GRShadowVaryings input) : SV_TARGET
{
    return 0;
}
#endif

// ------------------------------------------------------------------------------------------------ depth only
#if defined(GR_PASS_DEPTH)
struct GRDepthVaryings
{
    float4 positionCS : SV_POSITION;
};

GRDepthVaryings GroundDepthVert(GRPAttributes input)
{
    GRDepthVaryings o;
    float3 pw = GR_WorldPosition(input.positionOS, input.uv.x);
    o.positionCS = TransformWorldToHClip(pw);
    return o;
}

half GroundDepthFrag(GRDepthVaryings input) : SV_TARGET
{
    return input.positionCS.z;
}
#endif

// ------------------------------------------------------------------------------------------------ depth normals
#if defined(GR_PASS_DEPTHNORMALS)
struct GRDNVaryings
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD0;
};

GRDNVaryings GroundDepthNormalsVert(GRPAttributes input)
{
    GRDNVaryings o;
    float3 pw = GR_WorldPosition(input.positionOS, input.uv.x);
    o.positionWS = pw;
    o.positionCS = TransformWorldToHClip(pw);
    return o;
}

void GroundDepthNormalsFrag(GRDNVaryings input
    , out half4 outNormalWS : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out uint outRenderingLayers : SV_Target1
#endif
)
{
    float2 xz = input.positionWS.xz;
    float3 nMacro = GR_MacroNormal(xz);
    float3 normalWS = GR_CombinedNormal(nMacro, GR_FieldGradient(xz));

#if defined(_GBUFFER_NORMALS_OCT)
    float2 octNormalWS = PackNormalOctQuadEncode(normalWS);
    float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);
    half3 packedNormalWS = PackFloat2To888(remappedOctNormalWS);
    outNormalWS = half4(packedNormalWS, 0.0);
#else
    outNormalWS = half4(normalize(normalWS), 0.0);
#endif

#ifdef _WRITE_RENDERING_LAYERS
    outRenderingLayers = EncodeMeshRenderingLayer();
#endif
}
#endif

#endif
