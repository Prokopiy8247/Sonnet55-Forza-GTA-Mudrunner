#ifndef MR_GROUND_FORWARD_INCLUDED
#define MR_GROUND_FORWARD_INCLUDED

#include "GroundCommon.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct GRAttributes
{
    float3 positionOS : POSITION;
    float2 uv         : TEXCOORD0;      // x = skirt flag, y = lod index (debug)
};

struct GRVaryings
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD0;
    float  lodIndex   : TEXCOORD1;
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    float4 shadowCoord : TEXCOORD2;
#endif
};

GRVaryings GroundVert(GRAttributes input)
{
    GRVaryings o;
    float3 pw = GR_WorldPosition(input.positionOS, input.uv.x);
    o.positionWS = pw;
    o.positionCS = TransformWorldToHClip(pw);
    o.lodIndex = input.uv.y;
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    VertexPositionInputs vi;
    vi.positionWS = pw;
    vi.positionVS = TransformWorldToView(pw);
    vi.positionCS = o.positionCS;
    vi.positionNDC = float4(0, 0, 0, 0);
    o.shadowCoord = GetShadowCoord(vi);
#endif
    return o;
}

// ------------------------------------------------------------------------------------------------ surface model

struct GRSurface
{
    float3 albedo;
    float  smoothness;
    float3 normalWS;
    float  occlusion;
    float3 debugColor;
    float  debugOn;
};

static const float2x2 GR_ROT = float2x2(0.84, -0.54, 0.54, 0.84);

float3 GR_DebugRamp(float t)
{
    // blue -> cyan -> green -> yellow -> red
    return saturate(float3(abs(t * 4.0 - 3.0) - 1.0, 2.0 - abs(t * 4.0 - 2.0), 2.0 - abs(t * 4.0 - 1.0)));
}

GRSurface GR_EvaluateSurface(float3 positionWS, float lodIndex)
{
    GRSurface o;
    float2 xz = positionWS.xz;
    float dist = distance(positionWS, _WorldSpaceCameraPos);
    float2 dpx = ddx(xz);
    float2 dpy = ddy(xz);
    float2 dpyY = float2(ddx(positionWS.y), ddy(positionWS.y));    // d(height)/dscreen, for the biplanar rock

    // ---- map data
    float2 muv = GR_MapUV(xz);
    float4 c0 = SAMPLE_TEXTURE2D_LOD(_GR_Control0, sampler_LinearClamp, muv, 0);
    float4 c1 = SAMPLE_TEXTURE2D_LOD(_GR_Control1, sampler_LinearClamp, muv, 0);
    float2 prm = SAMPLE_TEXTURE2D_LOD(_GR_Params, sampler_LinearClamp, muv, 0).rg;
    float extraDepth = prm.r;
    float baseWet = prm.g;
    float3 nMacro = GR_MacroNormal(xz);
    float wsum = dot(c0, 1.0) + dot(c1, 1.0);
    float winv = 1.0 / max(wsum, 1e-4);
    c0 *= winv; c1 *= winv;

    // ---- dynamic deformation
    float4 fld = GR_SampleField(xz);
    float dh = fld.x;
    float churn = saturate(fld.y);
    float compact = saturate(fld.z);
    float2 gField = GR_FieldGradient(xz) * _GR_Misc.y;
    float3 nBase = GR_CombinedNormal(nMacro, gField);

    float rutW = smoothstep(0.012, 0.11, -dh);
    float rutDeep = smoothstep(0.05, 0.32, -dh);
    float bermW = smoothstep(0.015, 0.09, dh);
    float churnW = smoothstep(0.03, 0.55, churn);

    // ---- debug views that do not need the layers
    o.debugColor = 0; o.debugOn = 0;
    if (_MR_DebugMode > 0.5)
    {
        o.debugOn = 1;
        if (_MR_DebugMode < 1.5)
        {
            float3 t0 = float3(0.45, 0.45, 0.43), t1 = float3(0.45, 0.36, 0.26), t2 = float3(0.27, 0.36, 0.16), t3 = float3(0.55, 0.50, 0.42);
            float3 t4 = float3(0.30, 0.22, 0.15), t5 = float3(0.22, 0.15, 0.10), t6 = float3(0.14, 0.12, 0.08), t7 = float3(0.62, 0.55, 0.38);
            float3 dc = t0 * c0.x + t1 * c0.y + t2 * c0.z + t3 * c0.w + t4 * c1.x + t5 * c1.y + t6 * c1.z + t7 * c1.w;
            o.debugColor = SRGBToLinear(saturate(dc));
        }
        else if (_MR_DebugMode < 2.5)
        {
            float v = dh * 4.0;                               // +-0.25 m full scale
            o.debugColor = SRGBToLinear(v < 0 ? lerp(float3(0.5, 0.5, 0.5), float3(1, 0.1, 0.05), saturate(-v)) : lerp(float3(0.5, 0.5, 0.5), float3(0.1, 0.35, 1), saturate(v)));
        }
        else if (_MR_DebugMode < 3.5)
        {
            o.debugColor = SRGBToLinear(GR_DebugRamp(churn));
        }
        else if (_MR_DebugMode < 4.5)
        {
            float li = lodIndex;
            float3 lc = li < 0.5 ? float3(1, 0.2, 0.2) : li < 1.5 ? float3(1, 0.8, 0.1) : li < 2.5 ? float3(0.2, 1, 0.2) : li < 3.5 ? float3(0.2, 0.7, 1) : float3(0.8, 0.3, 1);
            o.debugColor = SRGBToLinear(lc * (0.6 + 0.4 * nBase.y));
        }
        else
        {
            o.debugColor = SRGBToLinear(nBase * 0.5 + 0.5);
        }
        o.albedo = 0; o.smoothness = 0; o.normalWS = nBase; o.occlusion = 1;
        return o;
    }

    // ---- macro variation noise
    float4 mL = SAMPLE_TEXTURE2D(_GR_Macro, sampler_GR_Macro, xz * _GR_Tiling.z);
    float4 mM = SAMPLE_TEXTURE2D(_GR_Macro, sampler_GR_Macro, xz * _GR_Tiling.w + 0.37);

    // ---- layer weights (natural), wetness sensitivity of the natural mix
    float W[8] = { c0.x, c0.y, c0.z, c0.w, c1.x, c1.y, c1.z, c1.w };
    float wetSens = dot(c0, _GR_WetSens0) + dot(c1, _GR_WetSens1);

    // slope-based rock override (steep faces show biplanar rock instead of stretched textures)
    float steep = smoothstep(0.84, 0.70, nMacro.y + (mM.g - 0.5) * 0.10);

    // ---- mud reveal: ruts / churn expose wet mud underneath any soft surface (never on rock, less on bog)
    float reveal = saturate(churnW * 0.95 + rutW * 0.85 + bermW * 0.25) * (1.0 - W[0]) * (1.0 - 0.8 * W[6]);
    float deep = saturate(extraDepth * 1.5 + rutDeep * 1.2 + W[5] + W[6]);
    [unroll] for (int k = 0; k < 8; k++)
        W[k] *= (k >= 4 && k <= 6) ? 1.0 : (1.0 - reveal);
    W[4] += reveal * (1.0 - deep);
    W[5] += reveal * deep;
    float wn = 1.0 / max(W[0] + W[1] + W[2] + W[3] + W[4] + W[5] + W[6] + W[7], 1e-4);
    [unroll] for (int k2 = 0; k2 < 8; k2++) W[k2] *= wn;

    float LS[8] = { _GR_LayerScale0.x, _GR_LayerScale0.y, _GR_LayerScale0.z, _GR_LayerScale0.w,
                    _GR_LayerScale1.x, _GR_LayerScale1.y, _GR_LayerScale1.z, _GR_LayerScale1.w };

    // ---- texturing: distance based LOD of the sampling scheme
    float nearMask = 1.0 - smoothstep(30.0, 110.0, dist);          // normal-map strength
    float farMix = smoothstep(28.0, 90.0, dist);                   // 0: blend tile A and B, 1: only B
    bool useA = dist < 112.0;
    float mixB = lerp(0.30 + 0.35 * mL.g, 1.0, farMix);
    float hbStrength = 1.0 - smoothstep(55.0, 105.0, dist);

    float2 xzR = mul(GR_ROT, xz);
    float2 dpxR = mul(GR_ROT, dpx);
    float2 dpyR = mul(GR_ROT, dpy);

    float4 AS[8];
    float3 NH[8];
    float T[8];
    float tmax = -100.0;
    [unroll] for (int i = 0; i < 8; i++)
    {
        AS[i] = 0; NH[i] = float3(0, 0, 0.5); T[i] = -100.0;
        [branch] if (W[i] > 0.02)
        {
            float kA = _GR_Tiling.x * LS[i];
            float kB = _GR_Tiling.y * LS[i];
            float4 aB = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Albedo, sampler_GR_Albedo, xzR * kB, i, dpxR * kB, dpyR * kB);
            [branch] if (useA)
            {
                float4 aA = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Albedo, sampler_GR_Albedo, xz * kA, i, dpx * kA, dpy * kA);
                float4 nA = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Normal, sampler_GR_Albedo, xz * kA, i, dpx * kA, dpy * kA);
                AS[i] = lerp(aA, aB, mixB);
                NH[i] = float3(nA.xy * 2.0 - 1.0, nA.z);
            }
            else
            {
                AS[i] = aB;
            }
            float sgn = (i & 1) ? -1.0 : 1.0;
            T[i] = NH[i].z * hbStrength + W[i] * 2.0 + sgn * (mL.b - 0.5) * 0.7 * hbStrength;
            tmax = max(tmax, T[i]);
        }
    }

    float asum = 0.0, psum = 0.0;
    float A8[8];
    float P8[8];
    [unroll] for (int j = 0; j < 8; j++)
    {
        float v = (W[j] > 0.02) ? max(T[j] - (tmax - 0.55), 0.0) : 0.0;
        float p = (W[j] > 0.02) ? W[j] : 0.0;
        A8[j] = v; P8[j] = p;
        asum += v; psum += p;
    }
    float4 asm_ = 0; float2 pertTD = 0; float blendH = 0;
    [unroll] for (int m = 0; m < 8; m++)
    {
        float a = lerp(A8[m] / max(asum, 1e-4), P8[m] / max(psum, 1e-4), 1.0 - hbStrength);
        asm_ += AS[m] * a;
        pertTD += NH[m].xy * a;
        blendH += NH[m].z * a;
    }
    float3 albedo = asm_.rgb;
    float smoothness = asm_.a;
    float3 pert = float3(pertTD.x, 0.0, pertTD.y);

    // ---- rock on steep faces (biplanar)
    [branch] if (steep > 0.01)
    {
        float kR = _GR_Tiling.x * LS[0] * 0.8;
        float3 an = abs(nMacro);
        float wx = pow(an.x, 3.0), wz = pow(an.z, 3.0);
        float ws = 1.0 / max(wx + wz, 1e-4);
        wx *= ws; wz *= ws;
        float2 uvX = float2(positionWS.z, positionWS.y) * kR;
        float2 uvZ = float2(positionWS.x, positionWS.y) * kR;
        float2 dX = float2(dpx.y, dpyY.x) * kR, dX2 = float2(dpy.y, dpyY.y) * kR;
        float2 dZ = float2(dpx.x, dpyY.x) * kR, dZ2 = float2(dpy.x, dpyY.y) * kR;
        float4 rX = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Albedo, sampler_GR_Albedo, uvX, 0, dX, dX2);
        float4 rZ = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Albedo, sampler_GR_Albedo, uvZ, 0, dZ, dZ2);
        float4 rock = rX * wx + rZ * wz;
        float3 rp = 0;
        [branch] if (nearMask > 0.01)
        {
            float4 nX = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Normal, sampler_GR_Albedo, uvX, 0, dX, dX2);
            float4 nZ = SAMPLE_TEXTURE2D_ARRAY_GRAD(_GR_Normal, sampler_GR_Albedo, uvZ, 0, dZ, dZ2);
            float2 tX = nX.xy * 2.0 - 1.0, tZ = nZ.xy * 2.0 - 1.0;
            rp = wx * float3(0.0, tX.y, tX.x) + wz * float3(tZ.x, tZ.y, 0.0);
        }
        albedo = lerp(albedo, rock.rgb, steep);
        smoothness = lerp(smoothness, rock.a, steep);
        pert = lerp(pert, rp, steep);
    }

    // ---- macro colour variation (breaks tiling, adds large scale patchiness)
    albedo *= (0.80 + 0.40 * mL.r) * (0.90 + 0.20 * mM.r);
    float macroMottle = mM.a;

    // ---- wetness
    float wet = saturate(baseWet + _MR_Wetness * wetSens + churn * 0.8 + rutW * 0.40);
    float lum = dot(albedo, float3(0.299, 0.587, 0.114));
    albedo = lerp(lum.xxx, albedo, 1.0 + 0.12 * wet) * lerp(1.0, 0.62, wet);
    smoothness = lerp(smoothness, max(smoothness, 0.50), wet * 0.65);

    // ---- ruts / berms / churn / compaction
    albedo *= lerp(1.0, 0.62, rutW);                                 // rut floors are dark wet mud
    smoothness = lerp(smoothness, max(smoothness, 0.62), rutW * 0.80);
    albedo *= 1.0 - 0.15 * compact * rutW;                           // compacted floor: darker...
    smoothness += 0.10 * compact * rutW;                              // ...and smoother
    albedo *= 1.0 + 0.30 * bermW * (1.0 - wet * 0.5);                // berms are drier / lighter
    smoothness -= 0.30 * bermW;
    smoothness = lerp(smoothness, max(smoothness, 0.58), churnW * 0.55 * (1.0 - bermW));   // churned slurry glistens
    albedo *= 1.0 - 0.12 * churnW * (1.0 - bermW);
    albedo *= 0.94 + 0.12 * macroMottle;

    // ---- detail normal (near) + normal assembly
    float strength = _GR_Misc2.x * nearMask * lerp(1.0, 0.55, wet) * (1.0 + 0.45 * bermW) * (1.0 - 0.55 * compact * rutW);
    float2 duv = xz * _GR_Misc.z;
    float3 detSample = SAMPLE_TEXTURE2D(_GR_Detail, sampler_GR_Macro, duv).rgb;
    float2 det = (detSample.xy * 2.0 - 1.0) * (1.0 - smoothstep(4.0, 24.0, dist)) * lerp(1.0, 0.5, wet) * 0.8;
    float3 nTex = normalize(nBase + pert * strength + float3(det.x, 0.0, det.y));

    // ---- standing water in ruts
    float rainW = saturate(_MR_Wetness + baseWet * 0.7);
    float level = lerp(0.20, 0.022, smoothstep(0.35, 0.95, rainW)) * _GR_Misc2.z;
    float flatness = smoothstep(0.90, 0.97, nMacro.y);
    float puddle = smoothstep(0.0, 0.028, -dh - level) * flatness;
    float3 nFinal = nTex;
    float occlusion = 1.0 - lerp(0.0, 0.40, rutW * (1.0 - churnW * 0.5)) - 0.15 * rutDeep;
    occlusion *= lerp(1.0, lerp(0.70, 1.0, smoothstep(0.15, 0.65, blendH)), nearMask);
    [branch] if (puddle > 0.002)
    {
        float t = _Time.y;
        float3 r1 = SAMPLE_TEXTURE2D_GRAD(_GR_Detail, sampler_GR_Macro, xz * 1.3 + float2(t * 0.045, -t * 0.03), dpx * 1.3, dpy * 1.3).rgb;
        float3 r2 = SAMPLE_TEXTURE2D_GRAD(_GR_Detail, sampler_GR_Macro, xz * 2.9 + float2(-t * 0.03, t * 0.05), dpx * 2.9, dpy * 2.9).rgb;
        float2 rip = ((r1.xy + r2.xy) - 1.0) * _GR_Misc2.y;
        float3 nWater = normalize(float3(nMacro.x * 0.9 + rip.x, nMacro.y, nMacro.z * 0.9 + rip.y));
        nFinal = normalize(lerp(nTex, nWater, puddle));
        float3 waterCol = albedo * float3(0.22, 0.20, 0.17) + float3(0.012, 0.011, 0.008);
        albedo = lerp(albedo, waterCol, puddle * 0.92);
        smoothness = lerp(smoothness, 0.97, puddle);
        occlusion = lerp(occlusion, 1.0, puddle);
    }

    // geometric specular anti-aliasing: widen the highlight where the normal varies faster than a pixel (kills glitter on wet detail)
    float3 dn1 = ddx(nFinal);
    float3 dn2 = ddy(nFinal);
    float nVar = 0.25 * (dot(dn1, dn1) + dot(dn2, dn2));
    float rough = 1.0 - saturate(smoothness);
    smoothness = 1.0 - sqrt(saturate(rough * rough + min(2.0 * nVar, 0.18)));

    o.albedo = saturate(albedo);
    o.smoothness = saturate(smoothness);
    o.normalWS = nFinal;
    o.occlusion = saturate(occlusion);
    return o;
}

// ------------------------------------------------------------------------------------------------ fragment

void GroundFrag(GRVaryings input
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out uint outRenderingLayers : SV_Target1
#endif
)
{
    GRSurface s = GR_EvaluateSurface(input.positionWS, input.lodIndex);

    if (s.debugOn > 0.5)
    {
        outColor = half4(s.debugColor, 1);
#ifdef _WRITE_RENDERING_LAYERS
        outRenderingLayers = EncodeMeshRenderingLayer();
#endif
        return;
    }

    InputData inputData = (InputData)0;
    inputData.positionWS = input.positionWS;
    inputData.positionCS = input.positionCS;
    inputData.normalWS = s.normalWS;
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), 0.0);
    inputData.vertexLighting = half3(0, 0, 0);
    inputData.bakedGI = SampleSHPixel(half3(0, 0, 0), s.normalWS);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = half4(1, 1, 1, 1);

    SurfaceData sd = (SurfaceData)0;
    sd.albedo = s.albedo;
    sd.metallic = 0.0;
    sd.specular = half3(0, 0, 0);
    sd.smoothness = s.smoothness;
    sd.normalTS = half3(0, 0, 1);
    sd.emission = half3(0, 0, 0);
    sd.occlusion = s.occlusion;
    sd.alpha = 1.0;
    sd.clearCoatMask = 0.0;
    sd.clearCoatSmoothness = 1.0;

    half4 color = UniversalFragmentPBR(inputData, sd);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    outColor = half4(color.rgb, 1.0);

#ifdef _WRITE_RENDERING_LAYERS
    outRenderingLayers = EncodeMeshRenderingLayer();
#endif
}

#endif
