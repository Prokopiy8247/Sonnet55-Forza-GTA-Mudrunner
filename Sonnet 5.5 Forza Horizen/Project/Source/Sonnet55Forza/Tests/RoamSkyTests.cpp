// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "World/RoamSkyManager.h"

#define ROAM_SKY_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamSkyExposureTest, "Roam.Sky.ExposureBrackets", ROAM_SKY_TEST_FLAGS)
bool FRoamSkyExposureTest::RunTest(const FString& Parameters)
{
	// Noon sits around EV100 14-15, night at about -0.5..1.
	const FRoamSkyKey Noon = FRoamSkyMath::SampleKey(70.0f);
	TestTrue(TEXT("noon min EV in 13.5..14.5"), Noon.EvMin >= 13.5f && Noon.EvMin <= 14.5f);
	TestTrue(TEXT("noon max EV in 14.5..15.5"), Noon.EvMax >= 14.5f && Noon.EvMax <= 15.5f);
	const FRoamSkyKey Night = FRoamSkyMath::SampleKey(-40.0f);
	TestTrue(TEXT("night min EV never below -2"), Night.EvMin >= -2.0f);
	TestTrue(TEXT("night max EV about 0.5"), Night.EvMax <= 1.5f && Night.EvMax >= 0.0f);

	// Whole range: bracket is valid, narrow, and exposure falls monotonically towards night.
	float PrevMin = -1000.0f;
	for (int32 E = -90; E <= 90; ++E)
	{
		const FRoamSkyKey K = FRoamSkyMath::SampleKey(static_cast<float>(E));
		TestTrue(*FString::Printf(TEXT("elev %d: min >= -2"), E), K.EvMin >= -2.0f);
		TestTrue(*FString::Printf(TEXT("elev %d: max > min"), E), K.EvMax > K.EvMin);
		TestTrue(*FString::Printf(TEXT("elev %d: bracket at most 4 EV wide"), E), K.EvMax - K.EvMin <= 4.0f);
		TestTrue(*FString::Printf(TEXT("elev %d: min EV does not drop as the sun rises"), E), K.EvMin >= PrevMin - 0.0001f);
		PrevMin = K.EvMin;
	}

	// Weather darkens the day bracket, never the night.
	TestNearlyEqual(TEXT("clear weather: no bias"), FRoamSkyMath::WeatherExposureBias(1.0f, 1.0f), 0.0f, 0.0001f);
	const float StormBias = FRoamSkyMath::WeatherExposureBias(0.15f, 1.0f);
	TestTrue(TEXT("storm bias between -2 and -1 EV"), StormBias < -1.0f && StormBias > -2.0f);
	TestNearlyEqual(TEXT("no bias at night"), FRoamSkyMath::WeatherExposureBias(0.15f, 0.0f), 0.0f, 0.0001f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamSkyLightsTest, "Roam.Sky.SunMoonAndFog", ROAM_SKY_TEST_FLAGS)
bool FRoamSkyLightsTest::RunTest(const FString& Parameters)
{
	TestNearlyEqual(TEXT("no sun below -14 degrees"), FRoamSkyMath::SunIlluminance(-20.0f), 0.0f, 0.001f);
	TestNearlyEqual(TEXT("full atmosphere light from -5 degrees"), FRoamSkyMath::SunIlluminance(-5.0f), 120000.0f, 1.0f);
	TestNearlyEqual(TEXT("full sun at noon"), FRoamSkyMath::SunIlluminance(70.0f), 120000.0f, 1.0f);
	TestNearlyEqual(TEXT("half light in the middle of the fade"), FRoamSkyMath::SunIlluminance(-9.5f), 60000.0f, 100.0f);
	float Prev = -1.0f;
	for (int32 E = -10; E <= 80; ++E)
	{
		const float Lux = FRoamSkyMath::SunIlluminance(static_cast<float>(E));
		TestTrue(*FString::Printf(TEXT("sun illuminance monotonic at %d"), E), Lux >= Prev);
		Prev = Lux;
	}

	TestNearlyEqual(TEXT("moon off below the horizon"), FRoamSkyMath::MoonIlluminance(-10.0f, 0.0f), 0.0f, 0.0001f);
	TestNearlyEqual(TEXT("moon 0.35 lux when high and clear"), FRoamSkyMath::MoonIlluminance(45.0f, 0.0f), 0.35f, 0.001f);
	TestTrue(TEXT("clouds dim the moon"), FRoamSkyMath::MoonIlluminance(45.0f, 1.0f) < FRoamSkyMath::MoonIlluminance(45.0f, 0.0f));

	// Fog: monotonic in visibility, sane magnitudes.
	float PrevFog = 1000.0f;
	for (float Km = 0.04f; Km <= 30.0f; Km *= 1.25f)
	{
		const float D = FRoamSkyMath::FogDensityFromVisibilityKm(Km);
		TestTrue(*FString::Printf(TEXT("fog density falls with visibility (%.2f km)"), Km), D <= PrevFog + 0.00001f);
		PrevFog = D;
	}
	TestTrue(TEXT("20 km visibility is nearly clear air"), FRoamSkyMath::FogDensityFromVisibilityKm(20.0f) < 0.005f);
	TestTrue(TEXT("45 m visibility is dense fog"), FRoamSkyMath::FogDensityFromVisibilityKm(0.045f) > 0.5f);

	// Quantised sun rotation.
	TestNearlyEqual(TEXT("10.12 -> 10.00"), FRoamSkyMath::QuantiseDeg(10.12f, 0.25f), 10.0f, 0.0001f);
	TestNearlyEqual(TEXT("10.13 -> 10.25"), FRoamSkyMath::QuantiseDeg(10.13f, 0.25f), 10.25f, 0.0001f);
	TestNearlyEqual(TEXT("negative angles"), FRoamSkyMath::QuantiseDeg(-33.3f, 0.25f), -33.25f, 0.0001f);
	const float Once = FRoamSkyMath::QuantiseDeg(77.777f, 0.25f);
	TestNearlyEqual(TEXT("idempotent"), FRoamSkyMath::QuantiseDeg(Once, 0.25f), Once, 0.0001f);
	TestNearlyEqual(TEXT("zero step keeps the angle"), FRoamSkyMath::QuantiseDeg(12.345f, 0.0f), 12.345f, 0.0001f);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
