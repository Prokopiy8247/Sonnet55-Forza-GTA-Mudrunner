// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Core/RoamTypes.h"
#include "World/RoamTimeWeatherSubsystem.h"

#define ROAM_TW_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTimeHourWrapTest, "Roam.TimeWeather.HourWrap", ROAM_TW_TEST_FLAGS)
bool FRoamTimeHourWrapTest::RunTest(const FString& Parameters)
{
	FRoamTimeWeatherModel Model;
	Model.Reset(23.5f, ERoamWeather::Clear, 3600.0f); // one game hour per real second

	const FRoamTimeWeatherEvents Events = Model.Update(1.0f);
	TestNearlyEqual(TEXT("23.5 + 1 h wraps to 0.5"), static_cast<float>(Model.GameHour), 0.5f, 0.001f);
	TestEqual(TEXT("day counter incremented"), Model.DayIndex, 1);
	TestTrue(TEXT("day changed event"), Events.bDayChanged);
	TestTrue(TEXT("hour changed event"), Events.bHourChanged);
	TestEqual(TEXT("new hour number"), Events.NewHour, 0);

	// several days in one update stay inside [0, 24)
	Model.Reset(10.0f, ERoamWeather::Clear, 86400.0f * 3.0f); // three days per real second
	Model.Update(1.0f);
	TestTrue(TEXT("hour stays in range"), Model.GameHour >= 0.0 && Model.GameHour < 24.0);
	TestTrue(TEXT("several days passed"), Model.DayIndex >= 2);

	// explicit set wraps both ways
	TestTrue(TEXT("SetGameHour reports hour change"), Model.SetGameHour(-1.0f));
	TestNearlyEqual(TEXT("-1 -> 23"), static_cast<float>(Model.GameHour), 23.0f, 0.001f);
	Model.SetGameHour(25.0f);
	TestNearlyEqual(TEXT("25 -> 1"), static_cast<float>(Model.GameHour), 1.0f, 0.001f);
	Model.SetGameHour(24.0f);
	TestNearlyEqual(TEXT("24 -> 0"), static_cast<float>(Model.GameHour), 0.0f, 0.001f);

	// frozen clock and zero scale do not advance
	Model.Reset(12.0f, ERoamWeather::Clear, 100.0f);
	Model.bTimeFrozen = true;
	Model.Update(10.0f);
	TestNearlyEqual(TEXT("frozen clock"), static_cast<float>(Model.GameHour), 12.0f, 0.0001f);
	Model.bTimeFrozen = false;
	Model.TimeScale = 0.0f;
	Model.Update(10.0f);
	TestNearlyEqual(TEXT("zero scale"), static_cast<float>(Model.GameHour), 12.0f, 0.0001f);
	Model.TimeScale = 3600.0f;
	Model.Update(0.5f);
	TestNearlyEqual(TEXT("half an hour"), static_cast<float>(Model.GameHour), 12.5f, 0.001f);

	// night compression makes the dark hours pass faster
	FRoamTimeWeatherModel Slow;
	Slow.Reset(1.0f, ERoamWeather::Clear, 3600.0f);
	FRoamTimeWeatherModel Fast;
	Fast.bCompressNight = true;
	Fast.Reset(1.0f, ERoamWeather::Clear, 3600.0f);
	Slow.Update(0.5f);
	Fast.Update(0.5f);
	TestTrue(TEXT("night compression speeds up the night"), Fast.GameHour > Slow.GameHour + 0.5);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamSunTest, "Roam.TimeWeather.Sun", ROAM_TW_TEST_FLAGS)
bool FRoamSunTest::RunTest(const FString& Parameters)
{
	float Elevation = 0.0f;
	float Azimuth = 0.0f;

	// equinox noon at 36 N: elevation = 90 - 36 = 54, sun due south
	FRoamTimeWeatherModel::ComputeSunAngles(12.0f, 80, 36.0f, Elevation, Azimuth);
	TestNearlyEqual(TEXT("equinox noon elevation"), Elevation, 54.0f, 1.0f);
	TestNearlyEqual(TEXT("equinox noon azimuth is south"), Azimuth, 180.0f, 1.0f);

	// June solstice noon: 90 - 36 + 23.44 = 77.4
	FRoamTimeWeatherModel::ComputeSunAngles(12.0f, 172, 36.0f, Elevation, Azimuth);
	TestNearlyEqual(TEXT("summer noon elevation"), Elevation, 77.4f, 1.0f);

	// December solstice noon: 90 - 36 - 23.44 = 30.6
	FRoamTimeWeatherModel::ComputeSunAngles(12.0f, 355, 36.0f, Elevation, Azimuth);
	TestNearlyEqual(TEXT("winter noon elevation"), Elevation, 30.6f, 1.5f);

	// midnight is below the horizon, morning is in the east, evening in the west
	FRoamTimeWeatherModel::ComputeSunAngles(0.0f, 172, 36.0f, Elevation, Azimuth);
	TestTrue(TEXT("midnight sun below horizon"), Elevation < -20.0f);
	FRoamTimeWeatherModel::ComputeSunAngles(8.0f, 172, 36.0f, Elevation, Azimuth);
	TestTrue(TEXT("morning azimuth east of south"), Azimuth > 40.0f && Azimuth < 130.0f);
	FRoamTimeWeatherModel::ComputeSunAngles(16.0f, 172, 36.0f, Elevation, Azimuth);
	TestTrue(TEXT("afternoon azimuth west of south"), Azimuth > 230.0f && Azimuth < 320.0f);

	// daylight factor
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Clear, 0.0f);
	TestTrue(TEXT("noon is bright"), Model.GetDaylight01() > 0.99f);
	Model.SetGameHour(0.0f);
	TestTrue(TEXT("midnight is dark"), Model.GetDaylight01() < 0.01f);
	TestNearlyEqual(TEXT("night time factor"), FRoamTimeWeatherModel::NightTimeFactor(-30.0f), 4.0f, 0.001f);
	TestNearlyEqual(TEXT("day time factor"), FRoamTimeWeatherModel::NightTimeFactor(10.0f), 1.0f, 0.001f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamWeatherBlendTest, "Roam.TimeWeather.WeatherBlend", ROAM_TW_TEST_FLAGS)
bool FRoamWeatherBlendTest::RunTest(const FString& Parameters)
{
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Clear, 0.0f);
	TestNearlyEqual(TEXT("clear has no rain"), Model.Params.RainIntensity, 0.0f, 0.0001f);

	Model.SetWeather(ERoamWeather::Storm, 10.0f);
	TestEqual(TEXT("target weather is set immediately"), Model.Weather, ERoamWeather::Storm);
	TestEqual(TEXT("previous weather remembered"), Model.PreviousWeather, ERoamWeather::Clear);
	TestTrue(TEXT("blending"), Model.bBlending);

	FRoamTimeWeatherEvents Events = Model.Update(5.0f);
	TestNearlyEqual(TEXT("halfway blend (smoothstep(0.5) = 0.5)"), Model.Params.RainIntensity, 0.5f, 0.01f);
	TestNearlyEqual(TEXT("blend alpha"), Model.GetBlendAlpha(), 0.5f, 0.001f);
	TestFalse(TEXT("not finished yet"), Events.bWeatherBlendFinished);

	Events = Model.Update(5.0f);
	TestTrue(TEXT("blend finished event"), Events.bWeatherBlendFinished);
	TestFalse(TEXT("no longer blending"), Model.bBlending);
	TestNearlyEqual(TEXT("storm rain"), Model.Params.RainIntensity, 1.0f, 0.0001f);
	TestTrue(TEXT("storm reduces visibility"), Model.Params.VisibilityKm < 1.0f);
	TestTrue(TEXT("fog density rises with lower visibility"), Model.Params.FogDensity > FRoamWeatherParams::ForState(ERoamWeather::Clear).FogDensity);

	// instant switch
	Model.SetWeather(ERoamWeather::Fog, 0.0f);
	TestFalse(TEXT("instant switch does not blend"), Model.bBlending);
	TestNearlyEqual(TEXT("fog visibility"), Model.Params.VisibilityKm, 0.12f, 0.001f);

	// setting the same weather again is a no-op
	Model.SetWeather(ERoamWeather::Fog, 5.0f);
	TestFalse(TEXT("same weather does not start a blend"), Model.bBlending);

	// every state has sane monotonic fog density
	TestTrue(TEXT("fog density ordering"), FRoamWeatherParams::ForState(ERoamWeather::Fog).FogDensity > FRoamWeatherParams::ForState(ERoamWeather::Rain).FogDensity);
	TestTrue(TEXT("rain denser than clear"), FRoamWeatherParams::ForState(ERoamWeather::Rain).FogDensity > FRoamWeatherParams::ForState(ERoamWeather::Clear).FogDensity);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamWetnessTest, "Roam.TimeWeather.Wetness", ROAM_TW_TEST_FLAGS)
bool FRoamWetnessTest::RunTest(const FString& Parameters)
{
	// ---- wetting under rain ---------------------------------------------------------------------------------------
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Clear, 0.0f); // frozen noon
	TestNearlyEqual(TEXT("dry road"), Model.Wetness, 0.0f, 0.0001f);
	TestFalse(TEXT("road not wet"), Model.bRoadWet);

	Model.SetWeather(ERoamWeather::Rain, 0.0f);
	bool bWetEventSeen = false;
	for (int32 i = 0; i < 90; ++i)
	{
		bWetEventSeen |= Model.Update(1.0f).bWetStateChanged;
	}
	TestTrue(TEXT("wet state flipped on"), bWetEventSeen && Model.bRoadWet);
	TestNearlyEqual(TEXT("wetness converges to the rain target"), Model.Wetness, FRoamWeatherParams::ForState(ERoamWeather::Rain).TargetWetness, 0.001f);

	// ---- drying is slower than wetting and depends on the sun --------------------------------------------------------
	const float SoakedAfterRain = Model.Wetness;
	FRoamTimeWeatherModel Noon = Model;
	Noon.SetWeather(ERoamWeather::Clear, 0.0f);
	FRoamTimeWeatherModel Night = Model;
	Night.SetGameHour(2.0f);
	Night.SetWeather(ERoamWeather::Clear, 0.0f);
	for (int32 i = 0; i < 100; ++i)
	{
		Noon.Update(1.0f);
		Night.Update(1.0f);
	}
	TestTrue(TEXT("road dries at noon"), Noon.Wetness < SoakedAfterRain);
	TestTrue(TEXT("road dries slower at night"), Night.Wetness > Noon.Wetness);
	TestTrue(TEXT("drying 100 s is slower than the 45 s wetting rate"), (SoakedAfterRain - Noon.Wetness) < 0.5f);

	// ---- hysteresis of the wet flag ------------------------------------------------------------------------------------
	FRoamTimeWeatherModel H;
	H.Reset(12.0f, ERoamWeather::Clear, 0.0f);
	H.Wetness = 0.2f;
	H.bRoadWet = true;
	H.Params.TargetWetness = 0.2f;
	H.Update(0.1f);
	TestTrue(TEXT("between 0.12 and 0.30 a wet road stays wet"), H.bRoadWet);
	H.bRoadWet = false;
	H.Update(0.1f);
	TestFalse(TEXT("between 0.12 and 0.30 a dry road stays dry"), H.bRoadWet);
	H.Wetness = 0.31f;
	H.Params.TargetWetness = 0.31f;
	H.Update(0.1f);
	TestTrue(TEXT("above 0.30 the flag switches on"), H.bRoadWet);
	H.Wetness = 0.11f;
	H.Params.TargetWetness = 0.11f;
	H.Update(0.1f);
	TestFalse(TEXT("below 0.12 the flag switches off"), H.bRoadWet);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamGripTableTest, "Roam.TimeWeather.GripTable", ROAM_TW_TEST_FLAGS)
bool FRoamGripTableTest::RunTest(const FString& Parameters)
{
	using namespace Roam;
	TestNearlyEqual(TEXT("dry asphalt"), SurfaceGripMultiplier(ERoamSurface::Asphalt, 0.0f), 1.00f, 0.001f);
	TestNearlyEqual(TEXT("wet asphalt"), SurfaceGripMultiplier(ERoamSurface::Asphalt, 0.7f), 0.72f, 0.001f);
	TestNearlyEqual(TEXT("storm asphalt"), SurfaceGripMultiplier(ERoamSurface::Asphalt, 1.0f), 0.62f, 0.001f);
	TestNearlyEqual(TEXT("dry dirt"), SurfaceGripMultiplier(ERoamSurface::Dirt, 0.0f), 0.78f, 0.001f);
	TestNearlyEqual(TEXT("wet dirt"), SurfaceGripMultiplier(ERoamSurface::Dirt, 0.7f), 0.55f, 0.001f);
	TestNearlyEqual(TEXT("gravel"), SurfaceGripMultiplier(ERoamSurface::Gravel, 0.0f), 0.70f, 0.001f);
	TestNearlyEqual(TEXT("grass"), SurfaceGripMultiplier(ERoamSurface::Grass, 0.0f), 0.60f, 0.001f);
	TestNearlyEqual(TEXT("sand"), SurfaceGripMultiplier(ERoamSurface::Sand, 0.0f), 0.55f, 0.001f);
	TestNearlyEqual(TEXT("snow"), SurfaceGripMultiplier(ERoamSurface::Snow, 0.0f), 0.35f, 0.001f);

	// asphalt grip never increases with wetness; every value is a usable multiplier
	float Previous = 2.0f;
	for (int32 i = 0; i <= 20; ++i)
	{
		const float Wetness = static_cast<float>(i) / 20.0f;
		const float Grip = SurfaceGripMultiplier(ERoamSurface::Asphalt, Wetness);
		TestTrue(*FString::Printf(TEXT("asphalt grip monotonic at %.2f"), Wetness), Grip <= Previous + KINDA_SMALL_NUMBER);
		Previous = Grip;
	}
	for (ERoamSurface Surface : TEnumRange<ERoamSurface>())
	{
		for (float Wetness : { 0.0f, 0.35f, 0.7f, 1.0f })
		{
			const float Grip = SurfaceGripMultiplier(Surface, Wetness);
			TestTrue(*FString::Printf(TEXT("%s grip %.2f in range"), *EnumToString(Surface), Wetness), Grip > 0.2f && Grip <= 1.0f);
		}
	}
	// wetness clamps
	TestNearlyEqual(TEXT("wetness below 0 clamps"), SurfaceGripMultiplier(ERoamSurface::Asphalt, -1.0f), 1.0f, 0.001f);
	TestNearlyEqual(TEXT("wetness above 1 clamps"), SurfaceGripMultiplier(ERoamSurface::Asphalt, 3.0f), 0.62f, 0.001f);

	// the model reproduces the table: a storm soaks the road to 1.0
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Storm, 0.0f);
	TestNearlyEqual(TEXT("storm model wetness"), Model.Wetness, 1.0f, 0.001f);
	TestNearlyEqual(TEXT("storm model asphalt grip"), Model.GetGripMultiplier(ERoamSurface::Asphalt), 0.62f, 0.001f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamAutoWeatherTest, "Roam.TimeWeather.AutoWeather", ROAM_TW_TEST_FLAGS)
bool FRoamAutoWeatherTest::RunTest(const FString& Parameters)
{
	const auto RunSequence = [](int32 SeedValue, TArray<ERoamWeather>& OutSequence)
	{
		FRoamTimeWeatherModel Model;
		Model.Seed(SeedValue);
		Model.Reset(12.0f, ERoamWeather::Clear, 0.0f);
		Model.bAutoWeather = true;
		ERoamWeather Last = Model.Weather;
		for (int32 i = 0; i < 6000; ++i)
		{
			const FRoamTimeWeatherEvents Events = Model.Update(1.0f);
			if (Events.bAutoWeatherStarted)
			{
				OutSequence.Add(Events.AutoNewWeather);
				if (Events.AutoNewWeather == Last)
				{
					return false; // the scheduler must always change the state
				}
				Last = Events.AutoNewWeather;
			}
		}
		return true;
	};

	TArray<ERoamWeather> A;
	TArray<ERoamWeather> B;
	TArray<ERoamWeather> C;
	TestTrue(TEXT("scheduler never repeats the current state"), RunSequence(1234, A));
	RunSequence(1234, B);
	RunSequence(99, C);
	TestTrue(TEXT("scheduler produced transitions"), A.Num() >= 3);
	TestTrue(TEXT("same seed gives the same sequence"), A == B);
	TestFalse(TEXT("different seeds differ"), A == C);

	// off by default: nothing happens
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Clear, 0.0f);
	for (int32 i = 0; i < 5000; ++i)
	{
		Model.Update(1.0f);
	}
	TestEqual(TEXT("auto weather off keeps the weather"), Model.Weather, ERoamWeather::Clear);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamLightsTest, "Roam.TimeWeather.Lights", ROAM_TW_TEST_FLAGS)
bool FRoamLightsTest::RunTest(const FString& Parameters)
{
	FRoamTimeWeatherModel Model;
	Model.Reset(12.0f, ERoamWeather::Clear, 0.0f);
	TestFalse(TEXT("noon: lights off"), Model.bVehicleLightsOn);
	TestFalse(TEXT("noon: street lights off"), Model.bStreetLightsOn);

	Model.SetGameHour(0.0f);
	const FRoamTimeWeatherEvents Events = Model.Update(0.1f);
	TestTrue(TEXT("midnight: vehicle lights on"), Model.bVehicleLightsOn);
	TestTrue(TEXT("midnight: street lights on"), Model.bStreetLightsOn);
	TestTrue(TEXT("lights change reported"), Events.bLightsChanged);

	Model.SetGameHour(12.0f);
	Model.Update(0.1f);
	TestFalse(TEXT("back to noon: lights off"), Model.bVehicleLightsOn);

	// heavy weather turns the headlights on at noon
	Model.SetWeather(ERoamWeather::Storm, 0.0f);
	Model.Update(0.1f);
	TestTrue(TEXT("storm: headlights on"), Model.bVehicleLightsOn);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
