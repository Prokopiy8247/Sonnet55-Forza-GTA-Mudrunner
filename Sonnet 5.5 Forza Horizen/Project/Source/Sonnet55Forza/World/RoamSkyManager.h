// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/RoamTypes.h"
#include "RoamSkyManager.generated.h"

class UDirectionalLightComponent;
class UExponentialHeightFogComponent;
class UMaterialInstanceDynamic;
class UMaterialParameterCollection;
class UPostProcessComponent;
class URoamRainFXComponent;
class URoamTimeWeatherSubsystem;
class USkyAtmosphereComponent;
class USkyLightComponent;
class USpotLightComponent;
class UVolumetricCloudComponent;

/** Broadcast when the street / vehicle lights signal changes (lamp actors, traffic and the player's car listen). */
DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnLightsSignal, bool /*bStreetLightsOn*/, bool /*bVehicleLightsOn*/);
/** Broadcast at the start of every lightning flash; DistanceKm lets an audio listener delay the thunder (about 3 s per km). */
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnLightning, float /*DistanceKm*/);

/** One row of the elevation-keyed lighting table (Docs/Tech/FH5_weather_time.md section 8.3). */
struct SONNET55FORZA_API FRoamSkyKey
{
	float EvMin = 14.0f;
	float EvMax = 15.0f;
	float SkyLightScale = 1.0f;
	float HazeMultiplier = 1.0f;
	/** Approximate ground illuminance in lux (used for the fog in-scattering luminance). */
	float GroundLux = 100000.0f;
	float SunTemperatureK = 6500.0f;
	/** Fog / sky mood colour (linear). */
	FLinearColor Mood = FLinearColor::White;
};

/** Pure lighting math of the sky manager (no UObjects), covered by Tests/RoamSkyTests.cpp. */
struct SONNET55FORZA_API FRoamSkyMath
{
	/** Interpolates the keyframe table at a sun elevation (degrees). */
	static FRoamSkyKey SampleKey(float SunElevationDeg);
	/** Atmosphere sun light in lux before the weather scale: 120000 * smoothstep(-14, -5, elevation) (stays on below the horizon for the twilight glow). */
	static float SunIlluminance(float SunElevationDeg);
	/** Moon illuminance (0.35 lux, matched to the night exposure bracket), fading in from -2 to +8 degrees, reduced by clouds. */
	static float MoonIlluminance(float MoonElevationDeg, float CloudCoverage01);
	/** Exposure shift (EV) for dimmer weather: 0.8 * log2(0.15 + 0.85 * SunLightScale), only in daylight. */
	static float WeatherExposureBias(float SunLightScale, float Daylight01);
	/** Exponential height fog density at ground level for a meteorological visibility (Koschmieder, 39.12 / V[m]). */
	static float FogDensityFromVisibilityKm(float VisibilityKm);
	/** Rounds an angle to a multiple of a step (so directional light rotation changes in discrete steps and VSM caches survive). */
	static float QuantiseDeg(float Deg, float StepDeg);
};

/**
 * Day/night and weather VISUALS (Docs/ARCHITECTURE.md section 3, research in Docs/Tech/FH5_weather_time.md sections 7-10).
 * One per level. It reads URoamTimeWeatherSubsystem (sun direction, daylight, weather parameters, wetness, lights signals) and
 * drives: DirectionalLight sun + moon (atmosphere light index 0 and 1), SkyAtmosphere, VolumetricCloud, ExponentialHeightFog,
 * SkyLight real-time capture, one unbound post-process (exposure bracket + grading per elevation and weather), a camera-attached
 * rain streak pool, lightning flashes, and the Material Parameter Collection /Game/Forza/Materials/MPC_Roam_World (wetness, rain,
 * time of day, wind; looked up softly: a missing asset is skipped).
 *
 * SPAWNING: ARoamGameMode::StartPlay calls EnsureSkyManager(). On BeginPlay the manager REPLACES the plain lighting actors the
 * world builder / test map placed (sun, SkyAtmosphere, SkyLight, height fog, volumetric cloud): it owns its own components and
 * destroys those actors at runtime (the map file is not touched).
 */
UCLASS()
class SONNET55FORZA_API ARoamSkyManager : public AActor
{
	GENERATED_BODY()

public:
	ARoamSkyManager();

	//~ Begin AActor
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void Tick(float DeltaSeconds) override;
	//~ End

	/** The manager of a world, or nullptr. */
	static ARoamSkyManager* Find(const UWorld* World);
	/** Finds the manager or spawns one (used by the game mode when the map has none). */
	static ARoamSkyManager* EnsureSkyManager(UWorld* World);

	/** Driven by Tick at UpdateRateHz; applies sun/sky/fog/exposure/MPC from the logic state. */
	virtual void UpdateSky(const URoamTimeWeatherSubsystem& TimeWeather, float DeltaSeconds);

	/** Instant snap (after `time`, teleports, photo-mode changes): re-applies everything and re-captures the sky light. */
	virtual void SnapToCurrentState();

	/** Debug (console `sky cloud`): forces the cloud material coverage / density; pass Coverage <= -900 to go back to the weather driven values. */
	void SetDebugClouds(float Coverage, float Density);
	/** Debug (console `sky flash <s> hold`): keeps a flash at its first peak until released, for screenshots. */
	void SetHoldFlash(bool bHold) { bHoldFlash = bHold; if (!bHold) { FlashTime = 10.0f; } }

	/** Starts a lightning flash now (Strength01 scales the brightness). Works in any weather (debug / scripted events). */
	void TriggerLightning(float Strength01 = 1.0f);

	/** Centre of the current exposure bracket (EV100) - what the rain streaks and flashes are calibrated against. */
	float GetExposureCenterEV100() const { return ExposureCenterEV; }
	bool AreStreetLightsOn() const { return bStreetLightsSignal; }
	bool AreVehicleLightsOn() const { return bVehicleLightsSignal; }
	bool IsLightningFlashing() const { return FlashLevel > 0.002f; }
	int32 GetRainStreakCount() const;
	/** One-line state summary for logs / the `sky` console command. */
	FString Describe() const;

	/** Update rate in Hz of the slow part (lights, fog, post-process, MPC). Rain and lightning run every frame. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sky", meta = (ClampMin = "1.0", ClampMax = "60.0"))
	float UpdateRateHz = 30.0f;

	/** Directional light rotation step in degrees (sun and moon rotate in steps so virtual shadow map caches stay valid). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sky", meta = (ClampMin = "0.0", ClampMax = "2.0"))
	float SunRotationStepDeg = 0.25f;

	/** Destroy the plain lighting actors found in the level when the manager starts. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sky")
	bool bReplaceLevelLighting = true;

	/** Debug overrides written to the MPC (snow by altitude and dust zones are future work). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sky", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float SnowAmountOverride = 0.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sky", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float DustAmountOverride = 0.0f;

	FRoamOnLightsSignal OnLightsSignal;
	FRoamOnLightning OnLightning;

private:
	void HandleWeatherChanged(ERoamWeather Previous, ERoamWeather New);
	void HandleHourChanged(int32 Hour);

	void AdoptLevelLighting();
	void LoadWorldMPC();
	void UpdateMPC(const URoamTimeWeatherSubsystem& TW);
	void UpdateRain(const URoamTimeWeatherSubsystem& TW, float DeltaSeconds);
	void UpdateLightning(const URoamTimeWeatherSubsystem& TW, float DeltaSeconds);
	void ApplySun();
	void ApplySkyLight();
	void BroadcastLightsIfChanged(const URoamTimeWeatherSubsystem& TW);
	void UpdatePlayerHeadlights();

	// ---- components (all owned by the manager) --------------------------------------------------------------------------------
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<UDirectionalLightComponent> SunLight;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<UDirectionalLightComponent> MoonLight;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<USkyAtmosphereComponent> SkyAtmosphere;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<UVolumetricCloudComponent> Clouds;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<UExponentialHeightFogComponent> HeightFog;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<USkyLightComponent> SkyLight;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<UPostProcessComponent> PostProcess;
	UPROPERTY(VisibleAnywhere, Category = "Sky")
	TObjectPtr<URoamRainFXComponent> RainFX;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> CloudMID;
	UPROPERTY(Transient)
	TObjectPtr<UMaterialParameterCollection> WorldMPC;

	UPROPERTY(Transient)
	TArray<TObjectPtr<USpotLightComponent>> HeadBeams;
	TWeakObjectPtr<APawn> HeadBeamPawn;

	TWeakObjectPtr<URoamTimeWeatherSubsystem> TimeWeather;
	FDelegateHandle WeatherHandle;
	FDelegateHandle HourHandle;

	// ---- cached state ----------------------------------------------------------------------------------------------------
	float TickAccumulator = 0.0f;
	float SlowAccumulator = 0.0f;
	bool bForceApply = true;

	float BaseSunLux = 0.0f;
	FRotator BaseSunRot = FRotator::ZeroRotator;
	float BaseSkyLightIntensity = 1.0f;
	float ExposureCenterEV = 14.0f;
	float CurrentDaylight = 1.0f;
	float LastWindStrength = 0.0f;
	float CloudBaseCoverage = 1.0f;
	float CloudBaseDensity = 1.0f;
	bool bSunFlashOverride = false;

	float BaseBloom = 0.6f;
	FVector SmoothedCameraVelocity = FVector::ZeroVector;
	FRotator LastSunRotApplied = FRotator(1000.0, 0.0, 0.0);
	FRotator LastMoonRotApplied = FRotator(1000.0, 0.0, 0.0);

	bool bStreetLightsSignal = false;
	bool bVehicleLightsSignal = false;
	bool bLightsSignalSent = false;

	// camera tracking for the rain
	FVector PrevCameraLocation = FVector::ZeroVector;
	bool bHavePrevCamera = false;

	// lightning
	float NextLightningIn = 8.0f;
	bool bFlashActive = false;
	float FlashTime = 0.0f;
	float FlashLevel = 0.0f;
	float FlashStrength = 1.0f;
	float FlashPulseTimes[3] = { 0.0f, 0.12f, 0.31f };
	float FlashPulseAmps[3] = { 1.0f, 0.6f, 0.9f };
	FRotator FlashRot = FRotator(-60.0, 0.0, 0.0);

	bool bMPCLookupDone = false;
	bool bHoldFlash = false;
	float DebugCloudCoverage = -999.0f;
	float DebugCloudDensity = -1.0f;
};
