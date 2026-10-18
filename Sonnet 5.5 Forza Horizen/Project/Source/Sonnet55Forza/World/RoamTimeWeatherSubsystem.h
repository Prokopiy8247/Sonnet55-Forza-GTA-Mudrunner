// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Math/RandomStream.h"
#include "Subsystems/WorldSubsystem.h"
#include "RoamTimeWeatherSubsystem.generated.h"

/**
 * Parameters of one weather state (values from Docs/Tech/FH5_weather_time.md sections 5 and 7). Continuous parameters are
 * cross-faded when the weather changes; everything is "logic only" - ARoamSkyManager turns them into visuals.
 */
struct SONNET55FORZA_API FRoamWeatherParams
{
	/** 0..1 rain/precipitation intensity. */
	float RainIntensity = 0.0f;
	/** 0..1 normalised fog density (0 = clear air, 1 = dense fog/dust, ~45 m visibility). Derived from VisibilityKm. */
	float FogDensity = 0.0f;
	/** Meteorological visibility in km (never below 0.04). */
	float VisibilityKm = 20.0f;
	/** 0..1 cloud coverage. */
	float CloudCoverage = 0.25f;
	float WindSpeedMs = 2.0f;
	/** Lightning flashes per minute while this state is fully active. */
	float LightningPerMinute = 0.0f;
	/** Multiplier of the direct sun intensity (sky manager). */
	float SunLightScale = 1.0f;
	/** Multiplier of the sky light intensity. */
	float SkyLightScale = 1.0f;
	/** Wetness the road converges to while this state lasts. */
	float TargetWetness = 0.0f;

	static FRoamWeatherParams ForState(ERoamWeather Weather);
	static FRoamWeatherParams Lerp(const FRoamWeatherParams& A, const FRoamWeatherParams& B, float Alpha);
	/** FogDensity01 from a visibility: 1 - log10(V/45 m) / log10(20000/45), clamped. */
	static float FogDensityFromVisibilityKm(float VisibilityKm);
};

/** What happened during one FRoamTimeWeatherModel::Update (the owner turns these into delegate calls). */
struct FRoamTimeWeatherEvents
{
	bool bHourChanged = false;
	int32 NewHour = 0;
	bool bDayChanged = false;
	bool bWeatherBlendFinished = false;
	bool bWetStateChanged = false;
	bool bLightsChanged = false;
	/** Set when the automatic weather scheduler started a transition. */
	bool bAutoWeatherStarted = false;
	ERoamWeather AutoPreviousWeather = ERoamWeather::Clear;
	ERoamWeather AutoNewWeather = ERoamWeather::Clear;
};

/**
 * Pure simulation of time of day, weather state machine, wetness and lights. No UObject, no world: the subsystem owns one
 * instance and the automation tests drive it directly ("Roam.TimeWeather.*").
 *
 * TIME: GameHour in [0, 24) wraps and increments DayIndex. TimeScale = game seconds per real second (30 => one game hour per
 * two real minutes). Optional night compression speeds the dark hours up to 4x (sun elevation below -6 degrees).
 *
 * WEATHER: Clear, Cloudy, Rain, Fog, Storm. SetWeather() starts a smooth-step cross-fade of all FRoamWeatherParams over
 * BlendSeconds (real time). Weather is a GLOBAL state (regional weather is a documented non-goal for v1).
 *
 * WETNESS (0..1): rises with rain at Rain/45 per second up to the state's TargetWetness and dries at (0.3 + 0.7*sun)/300 per
 * second (sun = sin(elevation) * (1 - clouds)), i.e. a soaked road dries in ~5 min of clear sun and ~17 min at night.
 * IsRoadWet is a Schmitt trigger (on at 0.30, off at 0.12) used for audio/VFX switches, so it does not flicker.
 */
struct SONNET55FORZA_API FRoamTimeWeatherModel
{
	// ---- configuration ---------------------------------------------------------------------------------------------
	float TimeScale = 30.0f;
	bool bTimeFrozen = false;
	bool bCompressNight = false;
	int32 DayOfYear = 172;
	float LatitudeDeg = 36.0f;
	bool bAutoWeather = false;
	/** Seconds of rain to soak the road from dry at full intensity. */
	float WetTimeSec = 45.0f;
	/** Seconds a soaked road needs to dry under full sun. */
	float DryTimeSec = 300.0f;

	// ---- state -----------------------------------------------------------------------------------------------------
	double GameHour = 10.0;
	int32 DayIndex = 0;
	ERoamWeather Weather = ERoamWeather::Clear;          // target (most recently requested) state
	ERoamWeather PreviousWeather = ERoamWeather::Clear;
	FRoamWeatherParams Params;                           // current, blended
	bool bBlending = false;
	float BlendElapsed = 0.0f;
	float BlendDuration = 0.0f;
	float Wetness = 0.0f;
	bool bRoadWet = false;
	bool bVehicleLightsOn = false;
	bool bStreetLightsOn = false;
	float NextWeatherCountdown = 0.0f;

	FRoamTimeWeatherModel();

	void Reset(float InGameHour, ERoamWeather InWeather, float InTimeScale);
	void Seed(int32 NewSeed) { Random.Initialize(NewSeed); }

	/** Advances by a real-time delta. */
	FRoamTimeWeatherEvents Update(float RealDeltaSeconds);

	/** Sets the hour (wraps into [0, 24)). Returns true if the whole-hour number changed. */
	bool SetGameHour(float Hour);

	/** Starts a transition to a weather state. BlendSeconds <= 0 switches instantly. */
	void SetWeather(ERoamWeather NewWeather, float BlendSeconds);

	/** 0..1 progress of the running transition (1 when none runs). */
	float GetBlendAlpha() const { return bBlending && BlendDuration > 0.0f ? FMath::Clamp(BlendElapsed / BlendDuration, 0.0f, 1.0f) : 1.0f; }

	/** Grip multiplier for a surface at the current wetness (dry asphalt = 1). */
	float GetGripMultiplier(ERoamSurface Surface) const { return Roam::SurfaceGripMultiplier(Surface, Wetness); }

	// ---- sun -------------------------------------------------------------------------------------------------------
	float GetSunElevationDeg() const;
	float GetSunAzimuthDeg() const;
	/** 0 at night .. 1 in full daylight (smooth between elevation -6 and +10 degrees). */
	float GetDaylight01() const;

	/**
	 * Solar position. Declination = 23.44 * sin(2 pi (N - 81)/365), hour angle = 15 * (hour - 12) degrees,
	 * sin(el) = sin(lat) sin(dec) + cos(lat) cos(dec) cos(H); azimuth is degrees clockwise from north.
	 */
	static void ComputeSunAngles(float Hour, int32 DayOfYear, float LatitudeDeg, float& OutElevationDeg, float& OutAzimuthDeg);
	/** Time-warp factor of the night compression: 1 for elevation >= -6, rising linearly to 4 at <= -14. */
	static float NightTimeFactor(float ElevationDeg);

private:
	void BeginAutoDwell();
	ERoamWeather PickNextWeather();

	FRoamWeatherParams FromParams;
	FRoamWeatherParams ToParams;
	FRandomStream Random;
};

DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnWeatherChanged, ERoamWeather /*Previous*/, ERoamWeather /*New (target)*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnWeatherBlendFinished, ERoamWeather /*Weather*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnHourChanged, int32 /*Hour 0..23*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnDayChanged, int32 /*DayIndex*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnRoadWetChanged, bool /*bWet*/);

/**
 * Time of day + weather for the world (Docs/ARCHITECTURE.md section 3). Pure logic - ARoamSkyManager renders it, the tyre
 * model asks GetGripMultiplier, traffic asks GetVisibilityKm / ShouldVehicleLightsBeOn, the HUD shows the clock and chips.
 */
UCLASS()
class SONNET55FORZA_API URoamTimeWeatherSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	static URoamTimeWeatherSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem / UWorldSubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;
	//~ End

	//~ Begin FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(URoamTimeWeatherSubsystem, STATGROUP_Tickables); }
	//~ End

	// ---- time ------------------------------------------------------------------------------------------------------
	/** Current game hour in [0, 24). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetGameHour() const { return static_cast<float>(Model.GameHour); }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetGameHour(float Hour);
	/** "HH:MM". */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	FString GetTimeString() const;
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	int32 GetDayIndex() const { return Model.DayIndex; }
	/** Game seconds per real second (30 = one game hour per two real minutes); 0 freezes the clock. */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetTimeScale(float GameSecondsPerRealSecond);
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetTimeScale() const { return Model.TimeScale; }
	/** Freezes the clock without changing the scale (photo mode). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetTimeFrozen(bool bFrozen) { Model.bTimeFrozen = bFrozen; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool IsTimeFrozen() const { return Model.bTimeFrozen; }
	void SetNightCompression(bool bEnabled) { Model.bCompressNight = bEnabled; }

	// ---- sun / lights ----------------------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetSunElevationDeg() const { return Model.GetSunElevationDeg(); }
	/** Degrees clockwise from north (+X = north, +Y = east). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetSunAzimuthDeg() const { return Model.GetSunAzimuthDeg(); }
	/** World-space unit vector pointing TOWARD the sun (a directional light's rotation is (-direction).Rotation()). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	FVector GetSunDirection() const;
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetDaylight01() const { return Model.GetDaylight01(); }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool IsNight() const { return Model.GetSunElevationDeg() < -6.0f; }
	/** Headlights on: sun below 4 degrees (hysteresis to 8), low visibility, heavy rain or fog. */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool ShouldVehicleLightsBeOn() const { return Model.bVehicleLightsOn; }
	/** Street lights in settlements / junctions: sun below 3 degrees (hysteresis to 7). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool AreStreetLightsOn() const { return Model.bStreetLightsOn; }

	// ---- weather ---------------------------------------------------------------------------------------------------
	/** Target weather (the state being faded to, or the current state once the blend finished). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	ERoamWeather GetWeather() const { return Model.Weather; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	ERoamWeather GetPreviousWeather() const { return Model.PreviousWeather; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetWeather(ERoamWeather NewWeather, float BlendSeconds = 30.0f);
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool IsWeatherBlending() const { return Model.bBlending; }
	/** 0..1 progress of the cross-fade (1 when settled). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetWeatherBlend() const { return Model.GetBlendAlpha(); }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetAutoWeather(bool bEnabled);
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool IsAutoWeather() const { return Model.bAutoWeather; }

	/** Blended parameters (for the sky manager). */
	const FRoamWeatherParams& GetWeatherParams() const { return Model.Params; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetRainIntensity() const { return Model.Params.RainIntensity; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetFogDensity() const { return Model.Params.FogDensity; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetVisibilityKm() const { return Model.Params.VisibilityKm; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetCloudCoverage() const { return Model.Params.CloudCoverage; }
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetWindSpeedMs() const { return Model.Params.WindSpeedMs; }

	// ---- road wetness / grip ---------------------------------------------------------------------------------------
	/** Road wetness 0..1 (rises while raining, dries slowly). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetWetness() const { return Model.Wetness; }
	/** Debug/photo override. */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	void SetWetness(float Wetness01);
	/** Schmitt-trigger wet flag (on at 0.30, off at 0.12). */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	bool IsRoadWet() const { return Model.bRoadWet; }
	/**
	 * Grip multiplier of a surface under the current wetness, dry asphalt = 1.0 (Roam::SurfaceGripMultiplier):
	 * asphalt 1.00 dry / 0.72 wet / 0.62 storm, dirt 0.78 / 0.55, gravel 0.70, grass 0.60, sand 0.55, snow 0.35 ...
	 * The car's own tyre data (FRoamTireSpec::SurfaceBias, WetGripBias) multiplies on top.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|TimeWeather")
	float GetGripMultiplier(ERoamSurface Surface) const { return Model.GetGripMultiplier(Surface); }

	// ---- events ----------------------------------------------------------------------------------------------------
	FRoamOnWeatherChanged OnWeatherChanged;
	FRoamOnWeatherBlendFinished OnWeatherBlendFinished;
	FRoamOnHourChanged OnHourChanged;
	FRoamOnDayChanged OnDayChanged;
	FRoamOnRoadWetChanged OnRoadWetChanged;

	const FRoamTimeWeatherModel& GetModel() const { return Model; }
	FRoamTimeWeatherModel& GetMutableModel() { return Model; }

	/** One-line summary for logs/console. */
	FString Describe() const;

private:
	void Dispatch(const FRoamTimeWeatherEvents& Events);

	FRoamTimeWeatherModel Model;
};
