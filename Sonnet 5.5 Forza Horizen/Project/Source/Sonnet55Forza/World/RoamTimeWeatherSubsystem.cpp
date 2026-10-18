// Copyright Epic Games, Inc. All Rights Reserved.

#include "World/RoamTimeWeatherSubsystem.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

// ------------------------------------------------------------------------------------------------------------------
// FRoamWeatherParams
// ------------------------------------------------------------------------------------------------------------------

float FRoamWeatherParams::FogDensityFromVisibilityKm(float VisibilityKm)
{
	const float VisibilityM = FMath::Max(VisibilityKm * 1000.0f, 45.0f);
	const float T = FMath::LogX(10.0f, VisibilityM / 45.0f) / FMath::LogX(10.0f, 20000.0f / 45.0f);
	return FMath::Clamp(1.0f - T, 0.0f, 1.0f);
}

FRoamWeatherParams FRoamWeatherParams::ForState(ERoamWeather Weather)
{
	FRoamWeatherParams P;
	switch (Weather)
	{
	case ERoamWeather::Clear:
		P.RainIntensity = 0.0f; P.VisibilityKm = 20.0f; P.CloudCoverage = 0.25f; P.WindSpeedMs = 2.0f;
		P.LightningPerMinute = 0.0f; P.SunLightScale = 1.00f; P.SkyLightScale = 1.00f; P.TargetWetness = 0.0f;
		break;
	case ERoamWeather::Cloudy:
		P.RainIntensity = 0.0f; P.VisibilityKm = 9.0f; P.CloudCoverage = 0.75f; P.WindSpeedMs = 5.0f;
		P.LightningPerMinute = 0.0f; P.SunLightScale = 0.55f; P.SkyLightScale = 0.90f; P.TargetWetness = 0.0f;
		break;
	case ERoamWeather::Rain:
		P.RainIntensity = 0.75f; P.VisibilityKm = 2.5f; P.CloudCoverage = 0.90f; P.WindSpeedMs = 8.0f;
		P.LightningPerMinute = 0.0f; P.SunLightScale = 0.30f; P.SkyLightScale = 0.85f; P.TargetWetness = 0.80f;
		break;
	case ERoamWeather::Fog:
		P.RainIntensity = 0.0f; P.VisibilityKm = 0.12f; P.CloudCoverage = 0.65f; P.WindSpeedMs = 1.0f;
		P.LightningPerMinute = 0.0f; P.SunLightScale = 0.30f; P.SkyLightScale = 1.10f; P.TargetWetness = 0.25f;
		break;
	case ERoamWeather::Storm:
		P.RainIntensity = 1.0f; P.VisibilityKm = 0.7f; P.CloudCoverage = 1.0f; P.WindSpeedMs = 14.0f;
		P.LightningPerMinute = 6.0f; P.SunLightScale = 0.15f; P.SkyLightScale = 0.80f; P.TargetWetness = 1.0f;
		break;
	default:
		break;
	}
	P.FogDensity = FogDensityFromVisibilityKm(P.VisibilityKm);
	return P;
}

FRoamWeatherParams FRoamWeatherParams::Lerp(const FRoamWeatherParams& A, const FRoamWeatherParams& B, float Alpha)
{
	FRoamWeatherParams R;
	R.RainIntensity = FMath::Lerp(A.RainIntensity, B.RainIntensity, Alpha);
	// Visibility is perceived logarithmically: blend in log space so fog does not "snap" at the end of the fade.
	R.VisibilityKm = FMath::Exp(FMath::Lerp(FMath::Loge(FMath::Max(A.VisibilityKm, 0.04f)), FMath::Loge(FMath::Max(B.VisibilityKm, 0.04f)), Alpha));
	R.VisibilityKm = FMath::Max(R.VisibilityKm, 0.04f);
	R.FogDensity = FogDensityFromVisibilityKm(R.VisibilityKm);
	R.CloudCoverage = FMath::Lerp(A.CloudCoverage, B.CloudCoverage, Alpha);
	R.WindSpeedMs = FMath::Lerp(A.WindSpeedMs, B.WindSpeedMs, Alpha);
	R.LightningPerMinute = FMath::Lerp(A.LightningPerMinute, B.LightningPerMinute, Alpha);
	R.SunLightScale = FMath::Lerp(A.SunLightScale, B.SunLightScale, Alpha);
	R.SkyLightScale = FMath::Lerp(A.SkyLightScale, B.SkyLightScale, Alpha);
	R.TargetWetness = FMath::Lerp(A.TargetWetness, B.TargetWetness, Alpha);
	return R;
}

// ------------------------------------------------------------------------------------------------------------------
// FRoamTimeWeatherModel
// ------------------------------------------------------------------------------------------------------------------

FRoamTimeWeatherModel::FRoamTimeWeatherModel()
	: Random(1337)
{
	Params = FRoamWeatherParams::ForState(Weather);
	FromParams = Params;
	ToParams = Params;
}

void FRoamTimeWeatherModel::Reset(float InGameHour, ERoamWeather InWeather, float InTimeScale)
{
	GameHour = FMath::Fmod(static_cast<double>(InGameHour), 24.0);
	if (GameHour < 0.0)
	{
		GameHour += 24.0;
	}
	DayIndex = 0;
	TimeScale = InTimeScale;
	Weather = InWeather;
	PreviousWeather = InWeather;
	Params = FRoamWeatherParams::ForState(InWeather);
	FromParams = Params;
	ToParams = Params;
	bBlending = false;
	BlendElapsed = 0.0f;
	BlendDuration = 0.0f;
	Wetness = Params.TargetWetness; // start in equilibrium with the weather
	bRoadWet = Wetness >= 0.30f;

	const float Elevation = GetSunElevationDeg();
	bVehicleLightsOn = Elevation < 4.0f || Params.VisibilityKm < 0.5f || Params.RainIntensity > 0.5f;
	bStreetLightsOn = Elevation < 3.0f;
	BeginAutoDwell();
}

void FRoamTimeWeatherModel::ComputeSunAngles(float Hour, int32 DayOfYear, float LatitudeDeg, float& OutElevationDeg, float& OutAzimuthDeg)
{
	const double Phi = FMath::DegreesToRadians(static_cast<double>(LatitudeDeg));
	const double Delta = FMath::DegreesToRadians(23.44) * FMath::Sin(2.0 * UE_DOUBLE_PI * (static_cast<double>(DayOfYear) - 81.0) / 365.0);
	const double HourAngle = FMath::DegreesToRadians(15.0 * (static_cast<double>(Hour) - 12.0));

	const double SinElevation = FMath::Sin(Phi) * FMath::Sin(Delta) + FMath::Cos(Phi) * FMath::Cos(Delta) * FMath::Cos(HourAngle);
	OutElevationDeg = static_cast<float>(FMath::RadiansToDegrees(FMath::Asin(FMath::Clamp(SinElevation, -1.0, 1.0))));

	// Azimuth measured from south towards west, then converted to clockwise-from-north.
	const double AzimuthFromSouth = FMath::Atan2(FMath::Sin(HourAngle), FMath::Cos(HourAngle) * FMath::Sin(Phi) - FMath::Tan(Delta) * FMath::Cos(Phi));
	double Azimuth = FMath::RadiansToDegrees(AzimuthFromSouth) + 180.0;
	Azimuth = FMath::Fmod(Azimuth, 360.0);
	if (Azimuth < 0.0)
	{
		Azimuth += 360.0;
	}
	OutAzimuthDeg = static_cast<float>(Azimuth);
}

float FRoamTimeWeatherModel::NightTimeFactor(float ElevationDeg)
{
	if (ElevationDeg >= -6.0f)
	{
		return 1.0f;
	}
	if (ElevationDeg <= -14.0f)
	{
		return 4.0f;
	}
	return FMath::Lerp(1.0f, 4.0f, (-6.0f - ElevationDeg) / 8.0f);
}

float FRoamTimeWeatherModel::GetSunElevationDeg() const
{
	float Elevation = 0.0f;
	float Azimuth = 0.0f;
	ComputeSunAngles(static_cast<float>(GameHour), DayOfYear, LatitudeDeg, Elevation, Azimuth);
	return Elevation;
}

float FRoamTimeWeatherModel::GetSunAzimuthDeg() const
{
	float Elevation = 0.0f;
	float Azimuth = 0.0f;
	ComputeSunAngles(static_cast<float>(GameHour), DayOfYear, LatitudeDeg, Elevation, Azimuth);
	return Azimuth;
}

float FRoamTimeWeatherModel::GetDaylight01() const
{
	const float T = FMath::Clamp((GetSunElevationDeg() + 6.0f) / 16.0f, 0.0f, 1.0f);
	return T * T * (3.0f - 2.0f * T);
}

bool FRoamTimeWeatherModel::SetGameHour(float Hour)
{
	const int32 OldHour = FMath::FloorToInt(static_cast<float>(GameHour));
	double H = FMath::Fmod(static_cast<double>(Hour), 24.0);
	if (H < 0.0)
	{
		H += 24.0;
	}
	GameHour = H;
	return FMath::FloorToInt(static_cast<float>(GameHour)) != OldHour;
}

void FRoamTimeWeatherModel::SetWeather(ERoamWeather NewWeather, float BlendSeconds)
{
	if (NewWeather == Weather && !bBlending)
	{
		return;
	}
	PreviousWeather = Weather;
	Weather = NewWeather;
	if (BlendSeconds <= 0.0f)
	{
		Params = FRoamWeatherParams::ForState(NewWeather);
		FromParams = Params;
		ToParams = Params;
		bBlending = false;
		BlendElapsed = 0.0f;
		BlendDuration = 0.0f;
	}
	else
	{
		FromParams = Params;
		ToParams = FRoamWeatherParams::ForState(NewWeather);
		BlendElapsed = 0.0f;
		BlendDuration = BlendSeconds;
		bBlending = true;
	}
	BeginAutoDwell();
}

void FRoamTimeWeatherModel::BeginAutoDwell()
{
	// Real-time seconds the current state lasts before the scheduler picks the next one.
	float Min = 480.0f;
	float Max = 900.0f;
	switch (Weather)
	{
	case ERoamWeather::Clear:  Min = 480.0f; Max = 900.0f; break;
	case ERoamWeather::Cloudy: Min = 300.0f; Max = 600.0f; break;
	case ERoamWeather::Rain:   Min = 240.0f; Max = 480.0f; break;
	case ERoamWeather::Fog:    Min = 240.0f; Max = 480.0f; break;
	case ERoamWeather::Storm:  Min = 120.0f; Max = 240.0f; break;
	default: break;
	}
	NextWeatherCountdown = Random.FRandRange(Min, Max);
}

ERoamWeather FRoamTimeWeatherModel::PickNextWeather()
{
	// Baseline global weights (clear, cloudy, rain, fog, storm); the current state is excluded so every pick is a change.
	static const float Weights[static_cast<int32>(ERoamWeather::Count)] = { 40.0f, 30.0f, 15.0f, 5.0f, 10.0f };
	float Total = 0.0f;
	for (int32 i = 0; i < static_cast<int32>(ERoamWeather::Count); ++i)
	{
		if (i != static_cast<int32>(Weather))
		{
			Total += Weights[i];
		}
	}
	float Roll = Random.FRandRange(0.0f, Total);
	for (int32 i = 0; i < static_cast<int32>(ERoamWeather::Count); ++i)
	{
		if (i == static_cast<int32>(Weather))
		{
			continue;
		}
		Roll -= Weights[i];
		if (Roll <= 0.0f)
		{
			return static_cast<ERoamWeather>(i);
		}
	}
	return ERoamWeather::Clear;
}

FRoamTimeWeatherEvents FRoamTimeWeatherModel::Update(float RealDeltaSeconds)
{
	FRoamTimeWeatherEvents Events;
	const float Dt = FMath::Clamp(RealDeltaSeconds, 0.0f, 5.0f);
	if (Dt <= 0.0f)
	{
		return Events;
	}

	// ---- clock ----------------------------------------------------------------------------------------------------
	if (!bTimeFrozen && TimeScale > 0.0f)
	{
		const float Speed = TimeScale * (bCompressNight ? NightTimeFactor(GetSunElevationDeg()) : 1.0f);
		const int32 OldHour = FMath::FloorToInt(static_cast<float>(GameHour));
		GameHour += static_cast<double>(Dt) * static_cast<double>(Speed) / 3600.0;
		while (GameHour >= 24.0)
		{
			GameHour -= 24.0;
			++DayIndex;
			Events.bDayChanged = true;
		}
		const int32 NewHour = FMath::FloorToInt(static_cast<float>(GameHour));
		if (NewHour != OldHour)
		{
			Events.bHourChanged = true;
			Events.NewHour = NewHour;
		}
	}

	// ---- weather cross-fade ---------------------------------------------------------------------------------------
	if (bBlending)
	{
		BlendElapsed += Dt;
		const float T = FMath::Clamp(BlendElapsed / FMath::Max(BlendDuration, 0.001f), 0.0f, 1.0f);
		const float Smooth = T * T * (3.0f - 2.0f * T);
		Params = FRoamWeatherParams::Lerp(FromParams, ToParams, Smooth);
		if (T >= 1.0f)
		{
			bBlending = false;
			Params = ToParams;
			Events.bWeatherBlendFinished = true;
		}
	}

	// ---- wetness (asymmetric: fast wetting, slow drying) + Schmitt trigger ----------------------------------------
	const float Elevation = GetSunElevationDeg();
	if (Params.TargetWetness > Wetness)
	{
		const float Rate = FMath::Max(Params.RainIntensity, 0.2f) / FMath::Max(WetTimeSec, 1.0f);
		Wetness = FMath::Min(Params.TargetWetness, Wetness + Rate * Dt);
	}
	else if (Params.TargetWetness < Wetness)
	{
		const float Sun = FMath::Clamp(FMath::Sin(FMath::DegreesToRadians(Elevation)), 0.0f, 1.0f) * (1.0f - Params.CloudCoverage);
		const float Rate = (0.3f + 0.7f * Sun) / FMath::Max(DryTimeSec, 1.0f);
		Wetness = FMath::Max(Params.TargetWetness, Wetness - Rate * Dt);
	}
	if (!bRoadWet && Wetness >= 0.30f)
	{
		bRoadWet = true;
		Events.bWetStateChanged = true;
	}
	else if (bRoadWet && Wetness <= 0.12f)
	{
		bRoadWet = false;
		Events.bWetStateChanged = true;
	}

	// ---- lights (hysteresis) --------------------------------------------------------------------------------------
	const bool bVehicleWantsOn = Elevation < 4.0f || Params.VisibilityKm < 0.5f || Params.RainIntensity > 0.5f;
	const bool bVehicleWantsOff = Elevation > 8.0f && Params.VisibilityKm >= 0.6f && Params.RainIntensity < 0.4f;
	if (!bVehicleLightsOn && bVehicleWantsOn)
	{
		bVehicleLightsOn = true;
		Events.bLightsChanged = true;
	}
	else if (bVehicleLightsOn && bVehicleWantsOff)
	{
		bVehicleLightsOn = false;
		Events.bLightsChanged = true;
	}
	if (!bStreetLightsOn && Elevation < 3.0f)
	{
		bStreetLightsOn = true;
		Events.bLightsChanged = true;
	}
	else if (bStreetLightsOn && Elevation > 7.0f)
	{
		bStreetLightsOn = false;
		Events.bLightsChanged = true;
	}

	// ---- automatic scheduler --------------------------------------------------------------------------------------
	if (bAutoWeather && !bBlending)
	{
		NextWeatherCountdown -= Dt;
		if (NextWeatherCountdown <= 0.0f)
		{
			const ERoamWeather Old = Weather;
			const ERoamWeather Next = PickNextWeather();
			SetWeather(Next, Random.FRandRange(45.0f, 90.0f));
			Events.bAutoWeatherStarted = true;
			Events.AutoPreviousWeather = Old;
			Events.AutoNewWeather = Next;
		}
	}
	return Events;
}

// ------------------------------------------------------------------------------------------------------------------
// URoamTimeWeatherSubsystem
// ------------------------------------------------------------------------------------------------------------------

URoamTimeWeatherSubsystem* URoamTimeWeatherSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	return World ? World->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr;
}

bool URoamTimeWeatherSubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void URoamTimeWeatherSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	Model.DayOfYear = Settings->SunDayOfYear;
	Model.LatitudeDeg = Settings->SunLatitudeDeg;
	Model.bAutoWeather = Settings->bAutoWeather;
	Model.Reset(Settings->DefaultGameHour, Settings->DefaultWeather, Settings->DefaultTimeScale);
	UE_LOG(LogRoamWorld, Log, TEXT("TimeWeather initialised: %s"), *Describe());
}

void URoamTimeWeatherSubsystem::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	Dispatch(Model.Update(DeltaTime));
}

void URoamTimeWeatherSubsystem::Dispatch(const FRoamTimeWeatherEvents& Events)
{
	if (Events.bDayChanged)
	{
		OnDayChanged.Broadcast(Model.DayIndex);
	}
	if (Events.bHourChanged)
	{
		OnHourChanged.Broadcast(Events.NewHour);
	}
	if (Events.bAutoWeatherStarted)
	{
		OnWeatherChanged.Broadcast(Events.AutoPreviousWeather, Events.AutoNewWeather);
	}
	if (Events.bWeatherBlendFinished)
	{
		OnWeatherBlendFinished.Broadcast(Model.Weather);
	}
	if (Events.bWetStateChanged)
	{
		OnRoadWetChanged.Broadcast(Model.bRoadWet);
	}
}

void URoamTimeWeatherSubsystem::SetGameHour(float Hour)
{
	Model.SetGameHour(Hour);
	OnHourChanged.Broadcast(FMath::FloorToInt(static_cast<float>(Model.GameHour)));
}

FString URoamTimeWeatherSubsystem::GetTimeString() const
{
	const int32 TotalMinutes = FMath::FloorToInt(static_cast<float>(Model.GameHour) * 60.0f);
	return FString::Printf(TEXT("%02d:%02d"), (TotalMinutes / 60) % 24, TotalMinutes % 60);
}

void URoamTimeWeatherSubsystem::SetTimeScale(float GameSecondsPerRealSecond)
{
	Model.TimeScale = FMath::Max(0.0f, GameSecondsPerRealSecond);
}

FVector URoamTimeWeatherSubsystem::GetSunDirection() const
{
	const float El = FMath::DegreesToRadians(Model.GetSunElevationDeg());
	const float Az = FMath::DegreesToRadians(Model.GetSunAzimuthDeg());
	// World: +X = north, +Y = east, +Z = up.
	return FVector(FMath::Cos(El) * FMath::Cos(Az), FMath::Cos(El) * FMath::Sin(Az), FMath::Sin(El));
}

void URoamTimeWeatherSubsystem::SetWeather(ERoamWeather NewWeather, float BlendSeconds)
{
	const ERoamWeather Old = Model.Weather;
	if (NewWeather == Old && !Model.bBlending)
	{
		return;
	}
	Model.SetWeather(NewWeather, BlendSeconds);
	OnWeatherChanged.Broadcast(Old, NewWeather);
	if (BlendSeconds <= 0.0f)
	{
		OnWeatherBlendFinished.Broadcast(NewWeather);
	}
}

void URoamTimeWeatherSubsystem::SetAutoWeather(bool bEnabled)
{
	Model.bAutoWeather = bEnabled;
}

void URoamTimeWeatherSubsystem::SetWetness(float Wetness01)
{
	Model.Wetness = FMath::Clamp(Wetness01, 0.0f, 1.0f);
	const bool bWasWet = Model.bRoadWet;
	Model.bRoadWet = Model.Wetness >= 0.30f;
	if (bWasWet != Model.bRoadWet)
	{
		OnRoadWetChanged.Broadcast(Model.bRoadWet);
	}
}

FString URoamTimeWeatherSubsystem::Describe() const
{
	return FString::Printf(TEXT("time=%s day=%d scale=%.1f weather=%s%s wet=%.2f rain=%.2f vis=%.2fkm sunEl=%.1f lights=%d"),
		*GetTimeString(), Model.DayIndex, Model.TimeScale, *Roam::EnumToString(Model.Weather), Model.bBlending ? TEXT("(blending)") : TEXT(""),
		Model.Wetness, Model.Params.RainIntensity, Model.Params.VisibilityKm, Model.GetSunElevationDeg(), Model.bVehicleLightsOn ? 1 : 0);
}

// ------------------------------------------------------------------------------------------------------------------
// Console commands (registered statically, resolved at call time)
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	URoamTimeWeatherSubsystem* GetTimeWeather(const FRoamConsoleContext& Ctx)
	{
		return Ctx.World ? Ctx.World->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr;
	}

	bool ParseTimeText(const FString& Text, float& OutHour)
	{
		const FString T = Text.ToLower();
		struct FNamedTime { const TCHAR* Name; float Hour; };
		static const FNamedTime Named[] =
		{
			{ TEXT("dawn"), 5.5f }, { TEXT("sunrise"), 6.5f }, { TEXT("morning"), 9.0f }, { TEXT("noon"), 12.0f },
			{ TEXT("afternoon"), 15.0f }, { TEXT("golden"), 18.0f }, { TEXT("goldenhour"), 18.0f }, { TEXT("sunset"), 19.5f },
			{ TEXT("dusk"), 20.5f }, { TEXT("night"), 23.0f }, { TEXT("midnight"), 0.0f },
		};
		for (const FNamedTime& Entry : Named)
		{
			if (T == Entry.Name)
			{
				OutHour = Entry.Hour;
				return true;
			}
		}
		FString Left;
		FString Right;
		if (T.Split(TEXT(":"), &Left, &Right) && Left.IsNumeric() && Right.IsNumeric())
		{
			OutHour = FCString::Atof(*Left) + FCString::Atof(*Right) / 60.0f;
			return OutHour >= 0.0f && OutHour < 24.0f + KINDA_SMALL_NUMBER;
		}
		if (T.IsNumeric())
		{
			OutHour = FCString::Atof(*T);
			return true;
		}
		return false;
	}
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("time", "time [hour|HH:MM|dawn|noon|sunset|night ...]", "Show or set the game time of day.", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTimeWeatherSubsystem* TW = GetTimeWeather(Ctx);
		if (!TW)
		{
			return Ctx.Fail(TEXT("no time/weather system (no game world)"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return TW->Describe();
		}
		float Hour = 0.0f;
		if (!ParseTimeText(Ctx.Arg(0), Hour))
		{
			return Ctx.Fail(TEXT("usage: time <0-24 | HH:MM | dawn | sunrise | morning | noon | afternoon | golden | sunset | dusk | night>"));
		}
		TW->SetGameHour(Hour);
		return FString::Printf(TEXT("time set to %s"), *TW->GetTimeString());
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("timescale", "timescale <game seconds per second>", "Set how fast the clock runs (30 = 1 game hour per 2 minutes, 0 = freeze).", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTimeWeatherSubsystem* TW = GetTimeWeather(Ctx);
		if (!TW)
		{
			return Ctx.Fail(TEXT("no time/weather system (no game world)"));
		}
		float Scale = 0.0f;
		if (!Ctx.GetFloat(0, Scale))
		{
			return FString::Printf(TEXT("timescale = %.2f"), TW->GetTimeScale());
		}
		TW->SetTimeScale(Scale);
		return FString::Printf(TEXT("timescale = %.2f"), TW->GetTimeScale());
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("weather", "weather [clear|cloudy|rain|fog|storm|auto on|off] [blendSeconds]", "Show or set the weather (cross-fades over blendSeconds, default 20).", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTimeWeatherSubsystem* TW = GetTimeWeather(Ctx);
		if (!TW)
		{
			return Ctx.Fail(TEXT("no time/weather system (no game world)"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return TW->Describe();
		}
		if (Ctx.Arg(0).Equals(TEXT("auto"), ESearchCase::IgnoreCase))
		{
			bool bOn = true;
			if (Ctx.NumArgs() > 1 && !Ctx.GetBool(1, bOn))
			{
				return Ctx.Fail(TEXT("usage: weather auto on|off"));
			}
			TW->SetAutoWeather(bOn);
			return FString::Printf(TEXT("automatic weather %s"), bOn ? TEXT("on") : TEXT("off"));
		}
		FString Name = Ctx.Arg(0).ToLower();
		if (Name == TEXT("overcast")) { Name = TEXT("cloudy"); }
		else if (Name == TEXT("thunderstorm") || Name == TEXT("thunder")) { Name = TEXT("storm"); }
		else if (Name == TEXT("sun") || Name == TEXT("sunny")) { Name = TEXT("clear"); }
		else if (Name == TEXT("rainy")) { Name = TEXT("rain"); }
		ERoamWeather Weather = ERoamWeather::Clear;
		if (!Roam::ParseEnum(Name, Weather) || Weather == ERoamWeather::Count)
		{
			return Ctx.Fail(TEXT("usage: weather <clear|cloudy|rain|fog|storm> [blendSeconds]"));
		}
		float Blend = 20.0f;
		if (Ctx.NumArgs() > 1 && !Ctx.GetFloat(1, Blend))
		{
			return Ctx.Fail(TEXT("blendSeconds must be a number"));
		}
		TW->SetWeather(Weather, Blend);
		return FString::Printf(TEXT("weather -> %s (%.0fs)"), *Roam::EnumToString(Weather), Blend);
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("wetness", "wetness [0..1]", "Show or force the road wetness (debug).", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTimeWeatherSubsystem* TW = GetTimeWeather(Ctx);
		if (!TW)
		{
			return Ctx.Fail(TEXT("no time/weather system (no game world)"));
		}
		float Value = 0.0f;
		if (Ctx.GetFloat(0, Value))
		{
			TW->SetWetness(Value);
		}
		return FString::Printf(TEXT("wetness = %.2f (road %s)"), TW->GetWetness(), TW->IsRoadWet() ? TEXT("wet") : TEXT("dry"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("grip", "grip", "Print the current grip multiplier of every surface.", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTimeWeatherSubsystem* TW = GetTimeWeather(Ctx);
		if (!TW)
		{
			return Ctx.Fail(TEXT("no time/weather system (no game world)"));
		}
		FString Text = FString::Printf(TEXT("grip multipliers at wetness %.2f:"), TW->GetWetness());
		for (ERoamSurface Surface : TEnumRange<ERoamSurface>())
		{
			Text += FString::Printf(TEXT("\n  %-9s %.2f"), *Roam::EnumToString(Surface), TW->GetGripMultiplier(Surface));
		}
		return Text;
	});
