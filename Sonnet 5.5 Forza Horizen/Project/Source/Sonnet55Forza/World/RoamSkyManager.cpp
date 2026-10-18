// Copyright Epic Games, Inc. All Rights Reserved.

#include "World/RoamSkyManager.h"

#include "Camera/PlayerCameraManager.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/PostProcessComponent.h"
#include "Components/SceneComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/VolumetricCloudComponent.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamLog.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameterCollection.h"
#include "Materials/MaterialParameterCollectionInstance.h"
#include "HAL/IConsoleManager.h"
#include "Misc/PackageName.h"
#include "World/RoamTimeWeatherSubsystem.h"
#include "World/RoamWeatherFX.h"

// ======================================================================================================================
// FRoamSkyMath - pure lighting math
// ======================================================================================================================
namespace
{
	struct FSkyKeyRow
	{
		float Elev;
		float EvMin;
		float EvMax;
		float Sky;
		float Haze;
		float GroundLux;
		float TempK;
		uint8 R, G, B;
	};

	// Docs/Tech/FH5_weather_time.md section 8.3. The night row uses a narrow bracket (-1.0..0.5, never below -2).
	const FSkyKeyRow GSkyKeys[] =
	{
		{ -18.0f, -1.0f,  0.5f, 0.08f, 1.00f,      0.1f, 7500.0f, 0x0B, 0x12, 0x24 },
		{ -12.0f,  1.0f,  5.0f, 0.50f, 1.20f,      0.1f, 7500.0f, 0x1E, 0x2A, 0x4A },
		{  -6.0f,  4.5f,  8.0f, 1.00f, 1.60f,      3.4f, 7000.0f, 0x4C, 0x5E, 0x8F },
		{  -3.0f,  6.0f,  9.5f, 1.00f, 2.00f,     40.0f, 6500.0f, 0xA9, 0x8A, 0xA8 },
		{   0.0f,  9.0f, 11.5f, 0.80f, 2.20f,    400.0f, 5800.0f, 0xE8, 0x99, 0x6A },
		{   2.0f, 10.0f, 12.0f, 0.90f, 1.80f,   1500.0f, 5800.0f, 0xF2, 0xB2, 0x7A },
		{   6.0f, 11.0f, 13.0f, 1.00f, 1.40f,   6000.0f, 6000.0f, 0xF0, 0xD2, 0xA6 },
		{  15.0f, 12.0f, 14.0f, 1.00f, 1.20f,  25000.0f, 6200.0f, 0xE3, 0xD6, 0xC3 },
		{  30.0f, 13.0f, 14.5f, 1.00f, 1.05f,  55000.0f, 6400.0f, 0xC9, 0xD7, 0xEC },
		{  45.0f, 13.5f, 14.8f, 1.00f, 1.00f,  80000.0f, 6500.0f, 0xC2, 0xD6, 0xF0 },
		{  70.0f, 14.0f, 15.0f, 1.00f, 1.00f, 100000.0f, 6500.0f, 0xBF, 0xD4, 0xF0 },
	};
	constexpr int32 GNumSkyKeys = UE_ARRAY_COUNT(GSkyKeys);

	FLinearColor RowMood(const FSkyKeyRow& Row)
	{
		return FLinearColor::FromSRGBColor(FColor(Row.R, Row.G, Row.B));
	}
}

FRoamSkyKey FRoamSkyMath::SampleKey(float SunElevationDeg)
{
	FRoamSkyKey Out;
	const float E = FMath::Clamp(SunElevationDeg, GSkyKeys[0].Elev, GSkyKeys[GNumSkyKeys - 1].Elev);
	int32 Hi = 1;
	while (Hi < GNumSkyKeys - 1 && GSkyKeys[Hi].Elev < E)
	{
		++Hi;
	}
	const FSkyKeyRow& A = GSkyKeys[Hi - 1];
	const FSkyKeyRow& B = GSkyKeys[Hi];
	const float Alpha = FMath::Clamp((E - A.Elev) / FMath::Max(B.Elev - A.Elev, 0.001f), 0.0f, 1.0f);
	Out.EvMin = FMath::Lerp(A.EvMin, B.EvMin, Alpha);
	Out.EvMax = FMath::Lerp(A.EvMax, B.EvMax, Alpha);
	Out.SkyLightScale = FMath::Lerp(A.Sky, B.Sky, Alpha);
	Out.HazeMultiplier = FMath::Lerp(A.Haze, B.Haze, Alpha);
	Out.GroundLux = FMath::Lerp(A.GroundLux, B.GroundLux, Alpha);
	Out.SunTemperatureK = FMath::Lerp(A.TempK, B.TempK, Alpha);
	Out.Mood = FMath::Lerp(RowMood(A), RowMood(B), Alpha);
	return Out;
}

float FRoamSkyMath::SunIlluminance(float SunElevationDeg)
{
	// The atmosphere light stays on while the sun is up to 5 degrees BELOW the horizon: the planet occludes the direct light on the ground (the
	// atmosphere transmittance is zero there) but the sky keeps its twilight glow and the sky light capture lights the world. Cutting the light at
	// -2 degrees made the whole scene black from sunset until the moon rose.
	return 120000.0f * FMath::SmoothStep(-14.0f, -5.0f, SunElevationDeg);
}

float FRoamSkyMath::MoonIlluminance(float MoonElevationDeg, float CloudCoverage01)
{
	// 0.35 lux at the night exposure bracket (EV100 -1..0.5) reads as dark blue moonlight; the original 1.5 lux made the night look like a dim day.
	return 0.35f * FMath::SmoothStep(-2.0f, 8.0f, MoonElevationDeg) * (1.0f - 0.4f * FMath::Clamp(CloudCoverage01, 0.0f, 1.0f));
}

float FRoamSkyMath::WeatherExposureBias(float SunLightScale, float Daylight01)
{
	const float Factor = 0.15f + 0.85f * FMath::Clamp(SunLightScale, 0.0f, 1.0f);
	return FMath::Clamp(Daylight01, 0.0f, 1.0f) * 0.8f * FMath::Log2(Factor);
}

float FRoamSkyMath::FogDensityFromVisibilityKm(float VisibilityKm)
{
	const float VisibilityM = FMath::Max(VisibilityKm * 1000.0f, 40.0f);
	return FMath::Clamp(39.12f / VisibilityM, 0.0015f, 1.5f);
}

float FRoamSkyMath::QuantiseDeg(float Deg, float StepDeg)
{
	return StepDeg > KINDA_SMALL_NUMBER ? FMath::RoundToFloat(Deg / StepDeg) * StepDeg : Deg;
}

// ======================================================================================================================
// ARoamSkyManager
// ======================================================================================================================
ARoamSkyManager::ARoamSkyManager()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	PrimaryActorTick.TickGroup = TG_PostUpdateWork; // after the camera moved this frame
	bReplicates = false;
	SetCanBeDamaged(false);

	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);

	// ---- sun (atmosphere light 0) ------------------------------------------------------------------------------------
	SunLight = CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("SunLight"));
	SunLight->SetupAttachment(Root);
	SunLight->SetMobility(EComponentMobility::Movable);
	SunLight->bAtmosphereSunLight = true;
	SunLight->AtmosphereSunLightIndex = 0;
	SunLight->Intensity = 120000.0f; // lux; the project uses the extended luminance range
	SunLight->bUseTemperature = true;
	SunLight->Temperature = 6500.0f;
	SunLight->bCastShadowsOnClouds = true;
	SunLight->bCastShadowsOnAtmosphere = true;
	SunLight->bCastCloudShadows = true;
	SunLight->ForwardShadingPriority = 1; // sun and moon are both atmosphere lights: without distinct priorities the engine prints an on-screen warning at dusk
	SunLight->DynamicShadowDistanceMovableLight = 20000.0f;
	SunLight->SetWorldRotation(FRotator(-45.0, 215.0, 0.0));

	// ---- moon (atmosphere light 1) -----------------------------------------------------------------------------------
	MoonLight = CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("MoonLight"));
	MoonLight->SetupAttachment(Root);
	MoonLight->SetMobility(EComponentMobility::Movable);
	MoonLight->bAtmosphereSunLight = true;
	MoonLight->AtmosphereSunLightIndex = 1;
	MoonLight->AtmosphereSunDiskColorScale = FLinearColor(0.35f, 0.35f, 0.35f);
	MoonLight->Intensity = 0.0f;
	MoonLight->bUseTemperature = true;
	MoonLight->Temperature = 7500.0f;
	MoonLight->bCastCloudShadows = false;
	MoonLight->ForwardShadingPriority = 0;
	MoonLight->bCastShadowsOnClouds = false;
	MoonLight->bCastShadowsOnAtmosphere = false;
	MoonLight->SetVisibility(false);

	// ---- atmosphere, clouds, fog, sky light, post process --------------------------------------------------------------
	SkyAtmosphere = CreateDefaultSubobject<USkyAtmosphereComponent>(TEXT("SkyAtmosphere"));
	SkyAtmosphere->SetupAttachment(Root);

	Clouds = CreateDefaultSubobject<UVolumetricCloudComponent>(TEXT("VolumetricCloud"));
	Clouds->SetupAttachment(Root);

	HeightFog = CreateDefaultSubobject<UExponentialHeightFogComponent>(TEXT("HeightFog"));
	HeightFog->SetupAttachment(Root);
	HeightFog->FogDensity = 0.003f;
	HeightFog->FogHeightFalloff = 0.2f;
	HeightFog->FogMaxOpacity = 1.0f;
	HeightFog->StartDistance = 0.0f;
	HeightFog->bEnableVolumetricFog = false;
	HeightFog->VolumetricFogDistance = 8000.0f;

	SkyLight = CreateDefaultSubobject<USkyLightComponent>(TEXT("SkyLight"));
	SkyLight->SetupAttachment(Root);
	SkyLight->SetMobility(EComponentMobility::Movable);
	SkyLight->bRealTimeCapture = true;
	SkyLight->SourceType = SLS_CapturedScene;
	SkyLight->bLowerHemisphereIsBlack = false;
	SkyLight->LowerHemisphereColor = FLinearColor(0.14f, 0.12f, 0.10f);
	SkyLight->bCloudAmbientOcclusion = true;

	PostProcess = CreateDefaultSubobject<UPostProcessComponent>(TEXT("PostProcess"));
	PostProcess->SetupAttachment(Root);
	PostProcess->bUnbound = true;
	PostProcess->Priority = 1.0f;
	{
		FPostProcessSettings& S = PostProcess->Settings;
		S.bOverride_AutoExposureMethod = true;
		S.AutoExposureMethod = EAutoExposureMethod::AEM_Histogram;
		S.bOverride_AutoExposureMinBrightness = true;
		S.AutoExposureMinBrightness = 14.0f;
		S.bOverride_AutoExposureMaxBrightness = true;
		S.AutoExposureMaxBrightness = 15.0f;
		S.bOverride_BloomIntensity = true;
		S.BloomIntensity = 0.6f;
		S.bOverride_ColorSaturation = true;
		S.bOverride_ColorContrast = true;
		S.bOverride_VignetteIntensity = true;
		S.VignetteIntensity = 0.25f;
	}

	RainFX = CreateDefaultSubobject<URoamRainFXComponent>(TEXT("RainFX"));
	RainFX->SetupAttachment(Root);
}

ARoamSkyManager* ARoamSkyManager::Find(const UWorld* World)
{
	if (!World)
	{
		return nullptr;
	}
	for (TActorIterator<ARoamSkyManager> It(const_cast<UWorld*>(World)); It; ++It)
	{
		return *It;
	}
	return nullptr;
}

ARoamSkyManager* ARoamSkyManager::EnsureSkyManager(UWorld* World)
{
	if (!World || !World->IsGameWorld())
	{
		return nullptr;
	}
	if (ARoamSkyManager* Existing = Find(World))
	{
		return Existing;
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	Params.Name = TEXT("RoamSkyManager");
	Params.NameMode = FActorSpawnParameters::ESpawnActorNameMode::Requested;
	ARoamSkyManager* Spawned = World->SpawnActor<ARoamSkyManager>(FVector::ZeroVector, FRotator::ZeroRotator, Params);
	UE_LOG(LogRoamWorld, Log, TEXT("Sky: spawned ARoamSkyManager (%s)"), Spawned ? TEXT("ok") : TEXT("FAILED"));
	return Spawned;
}

void ARoamSkyManager::AdoptLevelLighting()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return;
	}
	TArray<AActor*> ToDestroy;
	for (TActorIterator<AActor> It(World); It; ++It)
	{
		AActor* Actor = *It;
		if (!IsValid(Actor) || Actor == this || Actor->IsA<ARoamSkyManager>())
		{
			continue;
		}
		bool bMatch = Actor->FindComponentByClass<USkyAtmosphereComponent>() || Actor->FindComponentByClass<UVolumetricCloudComponent>()
			|| Actor->FindComponentByClass<USkyLightComponent>() || Actor->FindComponentByClass<UExponentialHeightFogComponent>();
		if (!bMatch)
		{
			if (const UDirectionalLightComponent* Dir = Actor->FindComponentByClass<UDirectionalLightComponent>())
			{
				bMatch = Dir->IsUsedAsAtmosphereSunLight() || Actor->ActorHasTag(TEXT("RoamBasicLighting"));
			}
		}
		if (bMatch)
		{
			ToDestroy.Add(Actor);
		}
	}
	for (AActor* Actor : ToDestroy)
	{
		UE_LOG(LogRoamWorld, Log, TEXT("Sky: replacing level lighting actor %s"), *GetNameSafe(Actor));
		Actor->Destroy();
	}
}

void ARoamSkyManager::LoadWorldMPC()
{
	if (WorldMPC || bMPCLookupDone)
	{
		return;
	}
	bMPCLookupDone = true;
	const FString PackagePath = TEXT("/Game/Forza/Materials/MPC_Roam_World");
	if (!FPackageName::DoesPackageExist(PackagePath))
	{
		UE_LOG(LogRoamWorld, Log, TEXT("Sky: MPC_Roam_World not found - material parameters are skipped"));
		return;
	}
	WorldMPC = LoadObject<UMaterialParameterCollection>(nullptr, *(PackagePath + TEXT(".MPC_Roam_World")), nullptr, LOAD_NoWarn | LOAD_Quiet);
	UE_LOG(LogRoamWorld, Log, TEXT("Sky: MPC_Roam_World %s"), WorldMPC ? TEXT("loaded") : TEXT("failed to load"));
}

void ARoamSkyManager::BeginPlay()
{
	Super::BeginPlay();
	SetActorTickInterval(0.0f);

	// The project's exposure runs from EV100 -1 (night) to 15 (noon); the engine's default cached-lighting pre-exposure (4) only covers [-8, 12]
	// and prints a red 'cached lighting is going to be clipped' warning over the screen at noon. 8 covers [-4, 16].
	if (IConsoleVariable* PreExposure = IConsoleManager::Get().FindConsoleVariable(TEXT("r.EyeAdaptation.CachedLightingPreExposure")))
	{
		PreExposure->Set(8.0f, ECVF_SetByCode);
	}

	if (bReplaceLevelLighting)
	{
		AdoptLevelLighting();
	}

	// Cloud material instance (coverage / density driven by the weather); the engine's simple cloud material is the default.
	if (Clouds)
	{
		if (UMaterialInterface* CloudMat = Clouds->Material.LoadSynchronous())
		{
			CloudMID = UMaterialInstanceDynamic::Create(CloudMat, this);
			if (CloudMID)
			{
				const float Cov = CloudMID->K2_GetScalarParameterValue(TEXT("Cloud_GlobalCoverage"));
				const float Den = CloudMID->K2_GetScalarParameterValue(TEXT("Cloud_GlobalDensity"));
				CloudBaseCoverage = Cov; // the engine default is negative (-0.2): coverage is an offset, not a 0..1 fraction
				CloudBaseDensity = Den > 0.001f ? Den : 1.0f;
				Clouds->SetMaterial(CloudMID);
				UE_LOG(LogRoamWorld, Log, TEXT("Sky: cloud material defaults coverage=%.3f density=%.3f"), Cov, Den);
			}
		}
	}

	if (RainFX)
	{
		RainFX->InitFX();
	}
	LoadWorldMPC();

	if (UWorld* World = GetWorld())
	{
		TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>();
	}
	if (URoamTimeWeatherSubsystem* TW = TimeWeather.Get())
	{
		WeatherHandle = TW->OnWeatherChanged.AddUObject(this, &ARoamSkyManager::HandleWeatherChanged);
		HourHandle = TW->OnHourChanged.AddUObject(this, &ARoamSkyManager::HandleHourChanged);
		SnapToCurrentState();
		UE_LOG(LogRoamWorld, Log, TEXT("Sky: manager active - %s"), *Describe());
	}
	else
	{
		UE_LOG(LogRoamWorld, Warning, TEXT("ARoamSkyManager: no URoamTimeWeatherSubsystem in this world"));
	}
}

void ARoamSkyManager::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (URoamTimeWeatherSubsystem* TW = TimeWeather.Get())
	{
		TW->OnWeatherChanged.Remove(WeatherHandle);
		TW->OnHourChanged.Remove(HourHandle);
	}
	Super::EndPlay(EndPlayReason);
}

void ARoamSkyManager::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	const URoamTimeWeatherSubsystem* TW = TimeWeather.Get();
	if (!TW)
	{
		return;
	}

	TickAccumulator += DeltaSeconds;
	if (TickAccumulator >= 1.0f / FMath::Max(UpdateRateHz, 1.0f))
	{
		UpdateSky(*TW, TickAccumulator);
		TickAccumulator = 0.0f;
	}
	UpdateLightning(*TW, DeltaSeconds);
	UpdateRain(*TW, DeltaSeconds);
}

void ARoamSkyManager::SnapToCurrentState()
{
	const URoamTimeWeatherSubsystem* TW = TimeWeather.Get();
	if (!TW)
	{
		return;
	}
	bForceApply = true;
	LastSunRotApplied = FRotator(1000.0, 0.0, 0.0);
	LastMoonRotApplied = FRotator(1000.0, 0.0, 0.0);
	UpdateSky(*TW, 0.1f);
	if (SkyLight)
	{
		SkyLight->RecaptureSky();
	}
}

// ----------------------------------------------------------------------------------------------------------------------
// Slow update: lights, atmosphere, fog, clouds, post process, MPC
// ----------------------------------------------------------------------------------------------------------------------
void ARoamSkyManager::UpdateSky(const URoamTimeWeatherSubsystem& TW, float DeltaSeconds)
{
	const FRoamWeatherParams& P = TW.GetWeatherParams();
	const float Elev = TW.GetSunElevationDeg();
	const float Daylight = TW.GetDaylight01();
	CurrentDaylight = Daylight;
	const FRoamSkyKey Key = FRoamSkyMath::SampleKey(Elev);
	const float Fog01 = FMath::Clamp(P.FogDensity, 0.0f, 1.0f);

	SlowAccumulator += DeltaSeconds;
	const bool bSlow = bForceApply || SlowAccumulator >= 0.1f;
	if (bSlow)
	{
		SlowAccumulator = 0.0f;
	}

	// ---- sun (quantised rotation) ----
	const FVector SunDir = TW.GetSunDirection();
	BaseSunLux = FRoamSkyMath::SunIlluminance(Elev) * P.SunLightScale;
	FRotator SunRot = (-SunDir).Rotation();
	SunRot.Pitch = FRoamSkyMath::QuantiseDeg(static_cast<float>(SunRot.Pitch), SunRotationStepDeg);
	SunRot.Yaw = FRoamSkyMath::QuantiseDeg(static_cast<float>(SunRot.Yaw), SunRotationStepDeg);
	SunRot.Roll = 0.0;
	BaseSunRot = SunRot;
	if (SunLight && !FMath::IsNearlyEqual(SunLight->Temperature, Key.SunTemperatureK, 20.0f))
	{
		SunLight->SetTemperature(Key.SunTemperatureK);
	}

	// ---- exposure bracket (needed by the flash and the rain colour) ----
	const float Bias = FRoamSkyMath::WeatherExposureBias(P.SunLightScale, Daylight);
	const float EvMin = FMath::Max(Key.EvMin + Bias, -1.5f);
	const float EvMax = FMath::Max(Key.EvMax + Bias, EvMin + 0.5f);
	ExposureCenterEV = 0.5f * (EvMin + EvMax);

	ApplySun();

	// ---- moon: opposite the sun, turned 25 degrees around the vertical so it is not always exactly mirrored ----
	if (MoonLight)
	{
		const FVector MoonDir = FQuat(FVector::UpVector, FMath::DegreesToRadians(25.0)).RotateVector(-SunDir);
		const float MoonElev = FMath::RadiansToDegrees(FMath::Asin(FMath::Clamp(static_cast<float>(MoonDir.Z), -1.0f, 1.0f)));
		const float MoonLux = FRoamSkyMath::MoonIlluminance(MoonElev, P.CloudCoverage);
		MoonLight->SetVisibility(MoonLux > 0.002f);
		if (!FMath::IsNearlyEqual(MoonLight->Intensity, MoonLux, 0.002f))
		{
			MoonLight->SetIntensity(MoonLux);
		}
		FRotator MoonRot = (-MoonDir).Rotation();
		MoonRot.Pitch = FRoamSkyMath::QuantiseDeg(static_cast<float>(MoonRot.Pitch), SunRotationStepDeg);
		MoonRot.Yaw = FRoamSkyMath::QuantiseDeg(static_cast<float>(MoonRot.Yaw), SunRotationStepDeg);
		MoonRot.Roll = 0.0;
		if (!MoonRot.Equals(LastMoonRotApplied, 0.0001))
		{
			MoonLight->SetWorldRotation(MoonRot);
			LastMoonRotApplied = MoonRot;
		}
	}

	// ---- sky light ----
	BaseSkyLightIntensity = Key.SkyLightScale * P.SkyLightScale;
	ApplySkyLight();

	if (!bSlow)
	{
		return;
	}

	// ---- atmosphere ----
	if (SkyAtmosphere)
	{
		SkyAtmosphere->SetMieScatteringScale(0.004f * Key.HazeMultiplier * (1.0f + 2.0f * Fog01 * Fog01));
		const float Storm = FMath::Clamp((P.CloudCoverage - 0.8f) * 5.0f, 0.0f, 1.0f);
		const float Lum = FMath::Lerp(1.0f, 0.8f, Storm);
		SkyAtmosphere->SetSkyLuminanceFactor(FLinearColor(Lum, Lum, Lum));
		SkyAtmosphere->SetHeightFogContribution(1.0f - 0.5f * Fog01);
	}

	// ---- height fog (Koschmieder density from the visibility, in-scattering luminance only for real fog) ----
	if (HeightFog)
	{
		const float FogW = FMath::SmoothStep(0.35f, 0.85f, Fog01);
		const float GroundScale = 0.15f + 0.85f * P.SunLightScale;
		const float Lum = Key.GroundLux / PI * 0.35f * GroundScale * FogW;
		HeightFog->FogDensity = FRoamSkyMath::FogDensityFromVisibilityKm(P.VisibilityKm);
		HeightFog->FogHeightFalloff = FMath::Lerp(0.2f, 0.05f, Fog01 * Fog01);
		HeightFog->FogInscatteringLuminance = Key.Mood * Lum;
		if (!HeightFog->bEnableVolumetricFog && Fog01 > 0.35f)
		{
			HeightFog->bEnableVolumetricFog = true;
		}
		else if (HeightFog->bEnableVolumetricFog && Fog01 < 0.25f)
		{
			HeightFog->bEnableVolumetricFog = false;
		}
		HeightFog->MarkRenderStateDirty();
	}

	// ---- clouds ----
	if (CloudMID)
	{
		const bool bDebug = DebugCloudCoverage > -900.0f;
		const float Cov = bDebug ? DebugCloudCoverage : CloudBaseCoverage + (P.CloudCoverage - 0.35f) * 1.3f;
		const float Den = (bDebug && DebugCloudDensity > 0.0f) ? DebugCloudDensity : CloudBaseDensity * (0.8f + 0.6f * P.CloudCoverage);
		CloudMID->SetScalarParameterValue(TEXT("Cloud_GlobalCoverage"), Cov);
		CloudMID->SetScalarParameterValue(TEXT("Cloud_GlobalDensity"), Den);
	}

	// ---- post process: exposure bracket + grading per condition (docs section 10.1) ----
	if (PostProcess)
	{
		const float Night = 1.0f - Daylight;
		const float Golden = FMath::SmoothStep(-4.0f, 1.0f, Elev) * (1.0f - FMath::SmoothStep(6.0f, 16.0f, Elev));
		const float Overcast = FMath::Max(P.RainIntensity, FMath::Clamp((P.CloudCoverage - 0.5f) * 2.0f, 0.0f, 1.0f));
		const float FogW = FMath::SmoothStep(0.5f, 0.85f, Fog01);

		float Sat = FMath::Lerp(1.10f, 1.15f, Golden);
		float Con = FMath::Lerp(1.04f, 1.06f, Golden);
		float Bloom = FMath::Lerp(0.60f, 0.90f, Golden);
		Sat = FMath::Lerp(Sat, 0.82f, Overcast);
		Con = FMath::Lerp(Con, 1.02f, Overcast);
		Sat = FMath::Lerp(Sat, 0.78f, FogW);
		Con = FMath::Lerp(Con, 0.92f, FogW);
		Sat = FMath::Lerp(Sat, 0.90f, Night);
		Con = FMath::Lerp(Con, 1.08f, Night);
		Bloom = FMath::Lerp(Bloom, 1.00f, Night);

		FPostProcessSettings& S = PostProcess->Settings;
		S.AutoExposureMinBrightness = EvMin;
		S.AutoExposureMaxBrightness = EvMax;
		S.ColorSaturation = FVector4(Sat, Sat, Sat, 1.0);
		S.ColorContrast = FVector4(Con, Con, Con, 1.0);
		S.VignetteIntensity = FMath::Lerp(0.25f, 0.35f, Night);
		BaseBloom = Bloom;
		if (FlashLevel <= 0.002f)
		{
			S.BloomIntensity = Bloom;
		}
	}

	UpdateMPC(TW);
	BroadcastLightsIfChanged(TW);
	bForceApply = false;
}

void ARoamSkyManager::ApplySun()
{
	if (!SunLight)
	{
		return;
	}
	float Lux = BaseSunLux;
	FRotator Rot = BaseSunRot;
	float Disk = 1.0f;
	bSunFlashOverride = false;
	if (FlashLevel > 0.002f)
	{
		// Flash energy is relative to the current exposure so it reads the same at noon and at night.
		Lux += FlashLevel * 4.5f * FMath::Exp2(ExposureCenterEV);
		if (BaseSunLux < 3000.0f)
		{
			// The sun is down: borrow its atmosphere light for the flash (lights the sky and the clouds from above, no visible disk).
			Rot = FlashRot;
			Disk = 0.0f;
			bSunFlashOverride = true;
		}
	}

	SunLight->SetVisibility(Lux > 0.05f);
	if (!FMath::IsNearlyEqual(SunLight->Intensity, Lux, Lux * 0.002f + 0.001f))
	{
		SunLight->SetIntensity(Lux);
	}
	if (!Rot.Equals(LastSunRotApplied, 0.0001))
	{
		SunLight->SetWorldRotation(Rot);
		LastSunRotApplied = Rot;
	}
	if (!FMath::IsNearlyEqual(SunLight->AtmosphereSunDiskColorScale.R, Disk, 0.001f))
	{
		SunLight->SetAtmosphereSunDiskColorScale(FLinearColor(Disk, Disk, Disk));
	}
}

void ARoamSkyManager::ApplySkyLight()
{
	if (!SkyLight)
	{
		return;
	}
	const float Target = BaseSkyLightIntensity * (1.0f + 2.5f * FlashLevel);
	if (!FMath::IsNearlyEqual(SkyLight->Intensity, Target, Target * 0.002f + 0.0005f))
	{
		SkyLight->SetIntensity(Target);
	}
}

void ARoamSkyManager::BroadcastLightsIfChanged(const URoamTimeWeatherSubsystem& TW)
{
	const bool bStreet = TW.AreStreetLightsOn();
	const bool bVehicle = TW.ShouldVehicleLightsBeOn();
	if (!bLightsSignalSent || bStreet != bStreetLightsSignal || bVehicle != bVehicleLightsSignal)
	{
		bLightsSignalSent = true;
		bStreetLightsSignal = bStreet;
		bVehicleLightsSignal = bVehicle;
		OnLightsSignal.Broadcast(bStreet, bVehicle);
	}
	UpdatePlayerHeadlights();
}

// The player's car only has emissive lamp lenses (RoamVehicleVisuals); two shadowless spot lights give the road a visible pool at night / in fog.
void ARoamSkyManager::UpdatePlayerHeadlights()
{
	UWorld* World = GetWorld();
	APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	APawn* Pawn = PC ? PC->GetPawn() : nullptr;
	if (HeadBeamPawn.Get() != Pawn)
	{
		for (USpotLightComponent* Beam : HeadBeams)
		{
			if (Beam)
			{
				Beam->DestroyComponent();
			}
		}
		HeadBeams.Reset();
		HeadBeamPawn = Pawn;
	}
	USceneComponent* Root = Pawn ? Pawn->GetRootComponent() : nullptr;
	if (!Root || !bVehicleLightsSignal)
	{
		for (USpotLightComponent* Beam : HeadBeams)
		{
			if (Beam && Beam->IsVisible())
			{
				Beam->SetVisibility(false);
			}
		}
		return;
	}
	if (HeadBeams.Num() == 0)
	{
		for (int32 Side = -1; Side <= 1; Side += 2)
		{
			USpotLightComponent* Beam = NewObject<USpotLightComponent>(Pawn, NAME_None, RF_Transient);
			Beam->SetMobility(EComponentMobility::Movable);
			Beam->IntensityUnits = ELightUnits::Candelas;
			Beam->SetIntensity(600.0f);
			Beam->SetInnerConeAngle(12.0f);
			Beam->SetOuterConeAngle(40.0f);
			Beam->SetAttenuationRadius(8000.0f);
			Beam->SetCastShadows(false);
			Beam->SetUseTemperature(true);
			Beam->SetTemperature(5600.0f);
			Beam->SetSourceRadius(4.0f);
			Beam->RegisterComponent();
			Beam->AttachToComponent(Root, FAttachmentTransformRules::KeepRelativeTransform);
			Beam->SetRelativeLocationAndRotation(FVector(215.0, 55.0 * Side, 62.0), FRotator(-3.0, 0.0, 0.0));
			HeadBeams.Add(Beam);
		}
	}
	for (USpotLightComponent* Beam : HeadBeams)
	{
		if (Beam && !Beam->IsVisible())
		{
			Beam->SetVisibility(true);
		}
	}
}

// ----------------------------------------------------------------------------------------------------------------------
// Material parameter collection
// ----------------------------------------------------------------------------------------------------------------------
void ARoamSkyManager::UpdateMPC(const URoamTimeWeatherSubsystem& TW)
{
	if (!WorldMPC)
	{
		return;
	}
	UWorld* World = GetWorld();
	UMaterialParameterCollectionInstance* Inst = World ? World->GetParameterCollectionInstance(WorldMPC) : nullptr;
	if (!Inst)
	{
		return;
	}
	const FRoamWeatherParams& P = TW.GetWeatherParams();
	const float Wet = TW.GetWetness();
	const float Wind = FMath::Clamp(P.WindSpeedMs * 0.07f, 0.05f, 1.0f);
	LastWindStrength = Wind;

	// Missing parameters are ignored silently by the instance (it returns false), so an older MPC asset is harmless.
	(void)Inst->SetScalarParameterValue(TEXT("Wetness"), Wet);
	(void)Inst->SetScalarParameterValue(TEXT("PuddleAmount"), FMath::Clamp(Wet * Wet * 0.6f, 0.0f, 1.0f));
	(void)Inst->SetScalarParameterValue(TEXT("RainIntensity"), P.RainIntensity);
	(void)Inst->SetScalarParameterValue(TEXT("SnowAmount"), SnowAmountOverride);
	(void)Inst->SetScalarParameterValue(TEXT("DustAmount"), DustAmountOverride);
	(void)Inst->SetScalarParameterValue(TEXT("TimeOfDay"), TW.GetGameHour());
	(void)Inst->SetScalarParameterValue(TEXT("NightFactor"), 1.0f - TW.GetDaylight01());
	(void)Inst->SetScalarParameterValue(TEXT("WindStrength"), Wind);
	(void)Inst->SetScalarParameterValue(TEXT("WindSpeed"), P.WindSpeedMs);
	const FVector WindDir = FRotator(0.0, 35.0, 0.0).Vector();
	(void)Inst->SetVectorParameterValue(TEXT("WindDirection"), FLinearColor(static_cast<float>(WindDir.X), static_cast<float>(WindDir.Y), 0.0f, 0.0f));
}

// ----------------------------------------------------------------------------------------------------------------------
// Rain (every frame, camera attached)
// ----------------------------------------------------------------------------------------------------------------------
void ARoamSkyManager::UpdateRain(const URoamTimeWeatherSubsystem& TW, float DeltaSeconds)
{
	if (!RainFX || !RainFX->IsReady())
	{
		return;
	}
	const UWorld* World = GetWorld();
	const APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	const APlayerCameraManager* PCM = PC ? PC->PlayerCameraManager.Get() : nullptr;
	if (!PCM)
	{
		return;
	}
	const FRoamWeatherParams& P = TW.GetWeatherParams();
	const FVector Cam = PCM->GetCameraLocation();
	FVector Vel = FVector::ZeroVector;
	if (bHavePrevCamera && DeltaSeconds > 1.0e-4f)
	{
		Vel = (Cam - PrevCameraLocation) / DeltaSeconds;
		if (Vel.SizeSquared() > 15000.0 * 15000.0) // teleport / respawn
		{
			Vel = FVector::ZeroVector;
			SmoothedCameraVelocity = FVector::ZeroVector;
		}
	}
	PrevCameraLocation = Cam;
	bHavePrevCamera = true;
	SmoothedCameraVelocity = FMath::VInterpTo(SmoothedCameraVelocity, Vel, DeltaSeconds, 12.0f);

	const FVector WindDir = FRotator(0.0, 35.0, 0.0).Vector();
	const FVector WindCm = WindDir * (P.WindSpeedMs * 100.0);
	const float Fall = 800.0f + 350.0f * P.RainIntensity;
	RainFX->UpdateRain(P.RainIntensity, Cam, SmoothedCameraVelocity, WindCm, ExposureCenterEV, CurrentDaylight, Fall, DeltaSeconds);
}

int32 ARoamSkyManager::GetRainStreakCount() const
{
	return RainFX ? RainFX->GetActiveCount() : 0;
}

// ----------------------------------------------------------------------------------------------------------------------
// Lightning
// ----------------------------------------------------------------------------------------------------------------------
void ARoamSkyManager::SetDebugClouds(float Coverage, float Density)
{
	DebugCloudCoverage = Coverage;
	DebugCloudDensity = Density;
	bForceApply = true;
}

void ARoamSkyManager::TriggerLightning(float Strength01)
{
	FlashStrength = FMath::Clamp(Strength01, 0.1f, 2.0f);
	FlashPulseTimes[0] = 0.0f;
	FlashPulseTimes[1] = FMath::FRandRange(0.08f, 0.16f);
	FlashPulseTimes[2] = FlashPulseTimes[1] + FMath::FRandRange(0.10f, 0.20f);
	FlashPulseAmps[0] = FMath::FRandRange(0.8f, 1.0f);
	FlashPulseAmps[1] = FMath::FRandRange(0.35f, 0.7f);
	FlashPulseAmps[2] = FMath::FRandRange(0.6f, 1.0f);
	FlashRot = FRotator(-FMath::FRandRange(50.0f, 75.0f), FMath::FRandRange(0.0f, 360.0f), 0.0f);
	FlashTime = 0.0f;
	bFlashActive = true;
	OnLightning.Broadcast(FMath::FRandRange(0.5f, 8.0f));
}

void ARoamSkyManager::UpdateLightning(const URoamTimeWeatherSubsystem& TW, float DeltaSeconds)
{
	const FRoamWeatherParams& P = TW.GetWeatherParams();
	if (!bFlashActive && P.LightningPerMinute > 0.01f && FMath::FRand() < P.LightningPerMinute / 60.0f * DeltaSeconds)
	{
		TriggerLightning(FMath::FRandRange(0.5f, 1.0f));
	}

	float Level = 0.0f;
	if (bFlashActive)
	{
		if (!bHoldFlash)
		{
			FlashTime += DeltaSeconds;
		}
		for (int32 i = 0; i < 3; ++i)
		{
			if (FlashTime >= FlashPulseTimes[i])
			{
				Level += FlashPulseAmps[i] * FMath::Exp(-(FlashTime - FlashPulseTimes[i]) / 0.06f);
			}
		}
		Level = FMath::Min(Level, 1.2f) * FlashStrength;
		if (FlashTime > 1.0f)
		{
			bFlashActive = false;
			Level = 0.0f;
		}
	}

	if (!FMath::IsNearlyEqual(Level, FlashLevel, 0.002f) || (Level == 0.0f && FlashLevel != 0.0f))
	{
		FlashLevel = Level;
		ApplySun();
		ApplySkyLight();
		if (PostProcess)
		{
			PostProcess->Settings.BloomIntensity = BaseBloom + 1.2f * FlashLevel;
		}
	}
}

// ----------------------------------------------------------------------------------------------------------------------
void ARoamSkyManager::HandleWeatherChanged(ERoamWeather Previous, ERoamWeather New)
{
	UE_LOG(LogRoamWorld, Log, TEXT("Sky: weather %s -> %s"), *Roam::EnumToString(Previous), *Roam::EnumToString(New));
}

void ARoamSkyManager::HandleHourChanged(int32 Hour)
{
	(void)Hour;
}

FString ARoamSkyManager::Describe() const
{
	return FString::Printf(TEXT("sky: sunLux=%.0f skyLight=%.2f EV100=%.1f (centre) daylight=%.2f rainStreaks=%d flash=%.2f lights(street=%d vehicle=%d) mpc=%s clouds=%s"),
		BaseSunLux, BaseSkyLightIntensity, ExposureCenterEV, CurrentDaylight, GetRainStreakCount(), FlashLevel,
		bStreetLightsSignal ? 1 : 0, bVehicleLightsSignal ? 1 : 0, WorldMPC ? TEXT("yes") : TEXT("no"), CloudMID ? TEXT("yes") : TEXT("no"));
}

// ======================================================================================================================
// Console: sky [flash [strength]]  (time / weather / timescale live in RoamTimeWeatherSubsystem.cpp)
// ======================================================================================================================
ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("sky", "sky [flash [strength] [hold|release] | cloud <coverage> [density]]", "Show the sky / weather visuals state, or trigger a lightning flash.", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamSkyManager* Sky = ARoamSkyManager::Find(Ctx.World);
		if (!Sky)
		{
			return Ctx.Fail(TEXT("no sky manager in this world"));
		}
		if (Ctx.NumArgs() > 0 && Ctx.Arg(0).Equals(TEXT("flash"), ESearchCase::IgnoreCase))
		{
			if (Ctx.Arg(1).Equals(TEXT("release"), ESearchCase::IgnoreCase))
			{
				Sky->SetHoldFlash(false);
				return TEXT("flash released");
			}
			float Strength = 1.0f;
			Ctx.GetFloat(1, Strength);
			Sky->SetHoldFlash(Ctx.Arg(2).Equals(TEXT("hold"), ESearchCase::IgnoreCase));
			Sky->TriggerLightning(Strength);
			return TEXT("lightning flash");
		}
		if (Ctx.NumArgs() > 0 && Ctx.Arg(0).Equals(TEXT("cloud"), ESearchCase::IgnoreCase))
		{
			float Coverage = -999.0f;
			float Density = -1.0f;
			Ctx.GetFloat(1, Coverage);
			Ctx.GetFloat(2, Density);
			Sky->SetDebugClouds(Coverage, Density);
			return FString::Printf(TEXT("cloud coverage override %.2f density %.4f (<= -900 = weather driven)"), Coverage, Density);
		}
		return Sky->Describe();
	});
